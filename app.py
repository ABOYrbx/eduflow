"""EduFlow Dashboard (Nachrichten + Hausaufgaben).

Simple Flask web dashboard:
- input EduFlow login (subdomain, username, password)
- view all timeline messages from as far back as possible
  (uses Edupage.get_notification_history with an early `date_from`).
- view all Hausaufgaben (timeline EventType.HOMEWORK + optional Tests)

Run:
    pip install -r requirements.txt
    python app.py
Then open http://127.0.0.1:8000
"""

import html
import json
import os
import re
import secrets
from base64 import b64encode
from datetime import date, datetime, timedelta, timezone
from functools import wraps
from pathlib import Path
from typing import Optional
from urllib.parse import quote, urlencode, urlparse

from cryptography.fernet import Fernet
import requests
from flask import (
    Flask,
    Response,
    flash,
    jsonify,
    redirect,
    render_template,
    request,
    session,
    stream_with_context,
    url_for,
)

from edupage_api import Edupage
from edupage_api.exceptions import (
    BadCredentialsException,
    CaptchaException,
    MissingDataException,
    NotLoggedInException,
)
from edupage_api.people import EduAccount

import cache as apicache

# Mini-.env-Loader (keine extra Dependency): lädt KEY=Value aus .env im
# Projektordner in os.environ, ohne echte Env-Vars zu überschreiben.
# Dort liegen die API-Keys (siehe .env.example). .env ist git-ignoriert.
def _load_dotenv() -> None:
    try:
        path = Path(__file__).resolve().parent / ".env"
        if not path.is_file():
            return
        for raw in path.read_text(encoding="utf-8").splitlines():
            line = raw.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            if line.lower().startswith("export "):
                line = line[7:].lstrip()
            key, _, value = line.partition("=")
            key, value = key.strip(), value.strip()
            if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
                value = value[1:-1]
            if key and key not in os.environ:
                os.environ[key] = value
    except OSError:
        pass


_load_dotenv()

app = Flask(__name__)

# Lokales Dev-Tool: statische Dateien (CSS/JS/Icons) nie cachen, damit nach
# Änderungen sofort der frische Stand ankommt (kein hartes Neuladen nötig).
app.config["SEND_FILE_MAX_AGE_DEFAULT"] = 0

BASE_DIR = Path(__file__).resolve().parent


def _load_or_create_file_secret(name: str, nbytes: int = 32) -> bytes:
    """Lädt ein lokales Secret (0600) oder erstellt es einmalig.

    Dadurch bleibt der Flask-Session-Key über Neustarts stabil und man
    bleibt eingeloggt. Alternativ per Env-Var überschreibbar.
    """
    path = BASE_DIR / name
    try:
        if path.is_file() and path.stat().st_size >= nbytes:
            return path.read_bytes()
    except OSError:
        pass
    try:
        data = secrets.token_bytes(nbytes)
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, "wb") as f:
            f.write(data)
        try:
            os.chmod(path, 0o600)
        except OSError:
            pass
        return data
    except OSError:
        return secrets.token_bytes(nbytes)


# Stabiler Session-Key (bleibt über Neustarts erhalten) + lange Cookie-Laufzeit.
app.secret_key = os.environ.get("FLASK_SECRET_KEY") or _load_or_create_file_secret(".eduflow_secret").hex()
app.permanent_session_lifetime = timedelta(days=30)


class SessionExpired(Exception):
    """Session unbrauchbar (fehlt, altes Format oder Schlüssel weg) → neu anmelden."""


def _fernet() -> Fernet:
    raw = os.environ.get("EDUFLOW_KEY")
    if raw:
        key = raw.encode()
    else:
        key_path = BASE_DIR / ".eduflow.key"
        try:
            if key_path.is_file():
                key = key_path.read_bytes().strip()
            else:
                key = Fernet.generate_key()
                fd = os.open(key_path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
                with os.fdopen(fd, "wb") as f:
                    f.write(key)
                try:
                    os.chmod(key_path, 0o600)
                except OSError:
                    pass
        except OSError as e:
            raise SessionExpired(f"Schlüsseldatei nicht lesbar: {e}")
    try:
        return Fernet(key)
    except Exception as e:
        raise SessionExpired(f"Ungültiger Schlüssel: {e}")


def store_login_session(username: str, subdomain: str, password: str, remember: bool) -> None:
    """Legt die Login-Session an. Das Passwort liegt nur Fernet-verschlüsselt
    im signierten Cookie, nie im Klartext. Mit remember=True bleibt man
    30 Tage (auch über Browser- und Server-Neustarts) eingeloggt."""
    session["username"] = username
    session["subdomain"] = subdomain
    session["pwd_enc"] = _fernet().encrypt(password.encode()).decode()
    session.pop("password", None)  # Altlast aus älteren Versionen
    session.permanent = remember
    session.modified = True


def session_password() -> str:
    """Entschlüsselt das Passwort aus der Session. Wirft SessionExpired."""
    token = session.get("pwd_enc")
    if not token:
        raise SessionExpired("Keine gespeicherten Zugangsdaten.")
    try:
        return _fernet().decrypt(token.encode()).decode()
    except SessionExpired:
        raise
    except Exception:
        raise SessionExpired("Gespeicherte Zugangsdaten ungültig.")

# Server-side store for in-progress 2FA logins:
# token -> {"edupage": Edupage, "two_factor": TwoFactorLogin,
#           "username": ..., "subdomain": ...}
PENDING_2FA: dict = {}

# Verlauf ab der frühestmöglichen Datenquelle der API anfordern.
# get_notification_history(date_from) liefert alles ab date_from bis heute zurück,
# daher fragt ein sehr frühes Datum automatisch den kompletten verfügbaren
# Verlauf ab. Der tatsächlich älteste zurückgegebene Eintrag ist dann die
# erste mögliche Datenquelle (siehe events_range()).
EARLIEST_DEFAULT = date(2000, 1, 1)


# ---------------------------------------------------------------- helpers

def format_person(p) -> str:
    if p is None:
        return "–"
    if isinstance(p, str):
        return p
    if isinstance(p, EduAccount):
        # e.g. "Max Mustermann (Teacher)"
        try:
            return f"{p.name}"
        except Exception:
            return str(p)
    return str(p)


GERMAN_MONTHS = ["Januar", "Februar", "März", "April", "Mai", "Juni",
                 "Juli", "August", "September", "Oktober", "November",
                 "Dezember"]


def pretty_timestamp(ts: datetime) -> str:
    """Menschenlesbarer Zeitstempel statt Technik-Format:
    "Heute · 10:00", "Gestern · 10:00", "Montag · 10:00",
    "16. September · 10:00" bzw. mit Jahr bei älteren Einträgen."""
    try:
        d = ts.date()
    except Exception:
        return str(ts)
    today = date.today()
    time_part = ts.strftime("%H:%M")
    delta = (today - d).days
    if delta == 0:
        return f"Heute · {time_part}"
    if delta == 1:
        return f"Gestern · {time_part}"
    if 1 < delta < 7:
        return f"{GERMAN_WEEKDAYS[d.weekday()]} · {time_part}"
    month = GERMAN_MONTHS[d.month - 1]
    if d.year == today.year:
        return f"{d.day}. {month} · {time_part}"
    return f"{d.day}. {month} {d.year} · {time_part}"


def event_to_dict(ev) -> dict:
    timestamp = ev.timestamp
    if isinstance(timestamp, datetime):
        ts_str = pretty_timestamp(timestamp)
        ts_iso = timestamp.isoformat()
    else:
        ts_str = str(timestamp)
        ts_iso = str(timestamp)

    try:
        type_value = ev.event_type.value if ev.event_type else "unknown"
    except Exception:
        type_value = str(getattr(ev, "event_type", "unknown"))

    text = ev.text or ""
    # additional_data can be dict or str
    try:
        extra = ev.additional_data
        if isinstance(extra, dict):
            extra_json = json.dumps(extra, ensure_ascii=False, indent=2)
            # Try to surface a fuller message body if present
            for key in ("messageContent", "text", "nazov", "name"):
                if not text.strip() and isinstance(extra.get(key), str) and extra.get(key).strip():
                    text = extra.get(key)
        else:
            extra_json = str(extra) if extra else ""
    except Exception:
        extra_json = ""
        extra = {}

    # Slowakische Server-Floskeln (Známka, Udalosť, …) eindeutschen.
    text = translate_server_text(text)

    attachments = extract_attachments(extra if isinstance(extra, dict) else {})

    return {
        "id": ev.event_id,
        "timestamp": ts_str,
        "timestamp_iso": ts_iso,
        "sort_key": ts_iso,
        "author": format_person(ev.author),
        "recipient": format_person(ev.recipient),
        "type": type_value,
        "type_label": type_label(type_value),
        "text": text,
        "is_starred": bool(getattr(ev, "is_starred", False)),
        "is_done": bool(getattr(ev, "is_done", False)),
        "reaction_count": getattr(ev, "reaction_count", 0) or 0,
        "extra": extra_json,
        "attachments": attachments,
    }


# Dateianhänge in den Timeline-Rohdaten finden. EduPage legt Dateien je nach
# Nachrichtentyp unterschiedlich ab (u. a. Cloud-Dateien mit "file"-Pfad,
# Link-Listen oder HTML-Links in messageContent). Darum wird generisch
# gesucht: Dicts mit Datei-Name + URL/Pfad sowie <a href>-Links.
_ATTACH_NAME_KEYS = ("filename", "fileName", "name", "nazov", "nadpis",
                     "subor", "originalName")
_ATTACH_URL_KEYS = ("url", "file", "src", "href", "link", "downloadLink",
                    "path")
_ATTACH_SKIP_KEYS = ("avatar", "photo", "icon", "thumbnail", "image")


def extract_attachments(extra) -> list:
    """Alle Dateianhänge aus additional_data sammeln -> [{name, url}]."""
    found: list = []
    seen: set = set()

    def _add(name, url):
        if not isinstance(url, str):
            return
        url = url.strip()
        if not url or url in seen:
            return
        if not (url.startswith("http://") or url.startswith("https://")
                or url.startswith("/")):
            return
        if not isinstance(name, str) or not name.strip():
            name = url.rsplit("/", 1)[-1] or "Datei"
        name = re.sub(r'[\r\n"]', "", name.strip())[:120] or "Datei"
        seen.add(url)
        found.append({"name": name, "url": url})

    def _walk(node, depth=0):
        if node is None or depth > 6:
            return
        if isinstance(node, dict):
            name = None
            for k in _ATTACH_NAME_KEYS:
                v = node.get(k)
                if isinstance(v, str) and v.strip():
                    name = v.strip()
                    break
            url = None
            for k in _ATTACH_URL_KEYS:
                v = node.get(k)
                if isinstance(v, str) and v.strip():
                    s = v.strip()
                    if s.startswith(("http://", "https://", "/")):
                        url = s
                        break
            if url and (name or "file" in node or "url" in node):
                _add(name or url.rsplit("/", 1)[-1], url)
            for k, v in node.items():
                if (isinstance(k, str)
                        and any(s in k.lower() for s in _ATTACH_SKIP_KEYS)
                        and not isinstance(v, (dict, list))):
                    continue
                _walk(v, depth + 1)
        elif isinstance(node, list):
            for v in node:
                _walk(v, depth + 1)
        elif isinstance(node, str) and depth <= 2 and "<a " in node:
            for m in re.finditer(
                    r'<a\s[^>]*href="([^"]+)"[^>]*>(.*?)</a>',
                    node, re.I | re.S):
                href = m.group(1).strip()
                label = re.sub(r"<[^>]+>", "", m.group(2)).strip()
                if href.startswith(("http://", "https://", "/")):
                    _add(label or None, href)

    try:
        _walk(extra or {})
    except Exception:
        pass
    return found


def login_required(view):
    @wraps(view)
    def wrapped(*args, **kwargs):
        if "username" not in session or "subdomain" not in session or "pwd_enc" not in session:
            return redirect(url_for("index"))
        return view(*args, **kwargs)

    return wrapped


def do_login(username: str, password: str, subdomain: str):
    """Create Edupage object and log in. Returns (edupage, two_factor_or_None)."""
    edupage = Edupage()
    subdomain = (subdomain or "").strip()
    if subdomain:
        # Allow full URLs / domains: extract bare subdomain
        subdomain = subdomain.replace("https://", "").replace("http://", "").strip().strip("/")
        if ".edupage.org" in subdomain:
            subdomain = subdomain.split(".edupage.org")[0].split(".")[-1]
        # user may paste "myschool.edupage.org" -> "myschool"
        if "." in subdomain:
            subdomain = subdomain.split(".")[0]
        two_factor = edupage.login(username, password, subdomain)
    else:
        two_factor = edupage.login_auto(username, password)
        subdomain = edupage.subdomain
    return edupage, two_factor, subdomain


def fetch_history_with_fallback(edupage: Edupage, since: date):
    """Holt den Verlauf ab `since` und findet darin die älteste Nachricht.

    Laut API-Doku liefert ein Request mit date_from den kompletten Zeitraum
    bis heute, daher steckt die älteste Nachricht bereits in dieser Antwort
    (siehe oldest_and_newest). Lehnt der Server ein sehr frühes Datum ab
    (RequestError), wird es mit kürzerem Zeitraum (2 Jahre / 1 Jahr) erneut
    versucht. Eine leere Periode (MissingDataException) zählt als kein Eintrag.

    Returns (events, n_requests, effective_since).
    """
    if not isinstance(since, date):
        since = EARLIEST_DEFAULT
    attempts = [since]
    for days in (730, 365):
        fallback = date.today() - timedelta(days=days)
        if fallback > attempts[-1]:
            attempts.append(fallback)
    n_requests = 0
    last_err: Exception | None = None
    for attempt in attempts:
        n_requests += 1
        try:
            events = edupage.get_notification_history(attempt)
            return events or [], n_requests, attempt
        except MissingDataException:
            return [], n_requests, attempt
        except Exception as e:  # z.B. RequestError bei zu frühem Datum
            last_err = e
            continue
    raise last_err if last_err is not None else RuntimeError("history fetch failed")


def _filter_events_since(events, since: date):
    """Nur Events mit timestamp >= since behalten (Cache enthält ggf. mehr)."""
    out = []
    for e in events:
        ts = getattr(e, "timestamp", None)
        try:
            if isinstance(ts, datetime) and ts.date() < since:
                continue
        except Exception:
            pass
        out.append(e)
    return out


def get_timeline_cached(edupage: Edupage, subdomain: str, username: str,
                        since: date, force_refresh: bool = False):
    """Timeline mit lokalem Cache (siehe cache.py).

    - Kein Cache / `since` älter als Cache-Start / force -> voller Fetch,
      Cache wird ersetzt.
    - Frischer Cache (TTL) -> 0 API-Requests, direkt aus Datei.
    - Staler Cache -> nur letztes Fenster (TIMELINE_WINDOW_DAYS) neu laden
      und per ID mergen (neu dazu, geändert aktualisiert).

    Returns (events, n_requests, effective_since, meta).
    meta: {from_cache, cache_age_s, cache_info, added, updated, stale_fallback}
    """
    uhash = apicache.user_hash(subdomain, username)
    cached = apicache.load_timeline(uhash)

    def _records_to_events(records):
        return [apicache.record_to_event(r) for r in records]

    def _info_fresh(age_s):
        return f"aus Cache ({apicache.format_age(age_s)} alt, 0 API-Requests)"

    # ---- kein Cache: voller Fetch -------------------------------------
    if cached is None:
        events, n_req, effective = fetch_history_with_fallback(edupage, since)
        try:
            apicache.save_timeline(
                uhash, effective.isoformat(),
                [apicache.event_to_record(e) for e in events])
        except Exception:
            pass
        meta = {"from_cache": False, "cache_age_s": 0,
                "cache_info": f"frisch geladen ({n_req} API-Requests)",
                "added": len(events), "updated": 0, "stale_fallback": False}
        return events, n_req, effective, meta

    records = cached.get("events", []) or []
    try:
        cached_earliest = date.fromisoformat(cached.get("earliest", ""))
    except Exception:
        cached_earliest = since
    age_s = apicache.cache_age_s(cached.get("saved_at"))

    # ---- User will weiter zurück als der Cache reicht: voll neu --------
    if since < cached_earliest:
        events, n_req, effective = fetch_history_with_fallback(edupage, since)
        try:
            apicache.save_timeline(
                uhash, effective.isoformat(),
                [apicache.event_to_record(e) for e in events])
        except Exception:
            pass
        meta = {"from_cache": False, "cache_age_s": 0,
                "cache_info": f"frisch geladen ({n_req} API-Requests)",
                "added": len(events), "updated": 0, "stale_fallback": False}
        return events, n_req, effective, meta

    # ---- frischer Cache: ohne API --------------------------------------
    if not force_refresh and apicache.is_fresh(cached.get("saved_at"), apicache.TIMELINE_TTL_S):
        events = _filter_events_since(_records_to_events(records), since)
        meta = {"from_cache": True, "cache_age_s": age_s or 0,
                "cache_info": _info_fresh(age_s),
                "added": 0, "updated": 0, "stale_fallback": False}
        return events, 0, cached_earliest, meta

    # ---- staler Cache: inkrementell mergen ------------------------------
    window_since = date.today() - timedelta(days=apicache.TIMELINE_WINDOW_DAYS)
    try:
        fresh, n_req, _eff = fetch_history_with_fallback(edupage, window_since)
    except Exception:
        # Offline/API-Fehler: alten Stand weiter serven statt 500.
        events = _filter_events_since(_records_to_events(records), since)
        meta = {"from_cache": True, "cache_age_s": age_s or 0,
                "cache_info": f"offline: Cache ({apicache.format_age(age_s)} alt) – Aktualisierung fehlgeschlagen",
                "added": 0, "updated": 0, "stale_fallback": True}
        return events, 0, cached_earliest, meta

    new_records = [apicache.event_to_record(e) for e in fresh]
    merged, added, updated = apicache.merge_records(records, new_records)
    try:
        apicache.save_timeline(uhash, cached_earliest.isoformat(), merged)
    except Exception:
        pass
    events = _filter_events_since(_records_to_events(merged), since)
    if added or updated:
        info = f"aktualisiert ({n_req} API-Requests, {added} neu, {updated} geändert)"
    else:
        info = f"geprüft, keine Änderungen ({n_req} API-Requests, Cache {apicache.format_age(0)} aktualisiert)"
    meta = {"from_cache": False, "cache_age_s": 0, "cache_info": info,
            "added": added, "updated": updated, "stale_fallback": False}
    return events, n_req, cached_earliest, meta


def get_timetable_day_cached(edupage: Edupage, subdomain: str, username: str,
                             day: date, force_refresh: bool = False):
    """Ein einzelner Stundenplan-Tag mit Cache.

    Returns (lessons_dicts, meta {from_cache, cache_age_s, cache_info}).
    lessons_dicts ist bereits das `lesson_to_dict`-Format (anzeigefertig).
    """
    uhash = apicache.user_hash(subdomain, username)
    cached = apicache.load_timetable(uhash, day)
    ttl = apicache.timetable_ttl_for(day)
    if cached is not None and not force_refresh \
            and apicache.is_fresh(cached.get("saved_at"), ttl):
        age = apicache.cache_age_s(cached.get("saved_at")) or 0
        return cached.get("lessons", []), {
            "from_cache": True, "cache_age_s": age,
            "cache_info": f"aus Cache ({apicache.format_age(age)} alt)"}

    # Miss / stale / force -> frisch laden
    tt = edupage.get_my_timetable(day)
    lessons = [lesson_to_dict(l) for l in (tt.lessons if tt else [])]
    try:
        apicache.save_timetable(uhash, day, lessons)
    except Exception:
        pass
    return lessons, {"from_cache": False, "cache_age_s": 0,
                     "cache_info": "frisch geladen"}


def oldest_and_newest(events):
    """(ältestes Event, neuestes Event) nach timestamp, oder (None, None)."""
    cand = [e for e in events if getattr(e, "timestamp", None) is not None]
    if not cand:
        return None, None
    return (min(cand, key=lambda e: e.timestamp),
            max(cand, key=lambda e: e.timestamp))


def fmt_day(dt) -> str:
    try:
        return dt.strftime("%d.%m.%Y")
    except Exception:
        return str(dt)


def short_label(ev, maxlen: int = 80) -> str:
    """Kurztitel eines TimelineEvents (erste Textzeile bzw. oldVals.title)."""
    text = (getattr(ev, "text", "") or "").strip().replace("\n", " ")
    if text:
        return translate_server_text(text[:maxlen])
    ad = getattr(ev, "additional_data", {}) or {}
    if isinstance(ad, dict):
        old = ad.get("oldVals") if isinstance(ad.get("oldVals"), dict) else {}
        for d in (old, ad):
            for k in ("title", "nazov", "name"):
                v = d.get(k)
                if isinstance(v, str) and v.strip():
                    return v.strip()[:maxlen]
    return f"#{getattr(ev, 'event_id', '?')}"


# ------------------------------------------------------- Hausaufgaben

# Timeline-Typen, die im Hausaufgaben-Dashboard interessieren.
HOMEWORK_TYPES = {"homework"}
EXAM_TYPES = {"bexam", "sexam", "oexam", "pexam", "rexam", "testing",
              "etesthw", "testpridelenie"}

# Nachrichtentypen für Dashboard + Übersicht ("sprava" sind Direktnachrichten,
# news/anketa/chat/genotif sind nachrichtenartig; Noten, Stundenplan etc. nicht).
MESSAGE_TYPES = {"sprava", "news", "anketa", "chat", "genotif"}

# Übersicht: wie viele Einträge je Spalte maximal (Fallback, falls keine
# Einstellung gespeichert ist – siehe SETTINGS_SCHEMA/"ov_unread"/"ov_homework").
OVERVIEW_UNREAD_LIMIT = 10
OVERVIEW_HOMEWORK_LIMIT = 10

# Allgemeine Einstellungen (Einstellungsseite `/einstellungen`, Ablage pro
# User in cache.py). Neue Einstellung = ein Dict anhängen – Speichern,
# Validieren und Formular-Rendering laufen generisch über dieses Schema.
# kinds: "select" (options=[(value, label), ...]), "bool", "int" (min/max),
# "text" (placeholder, maxlength), "password" (wie text, maskiert).
# Optional "section": Überschrift, ab der die Einstellung in einer eigenen
# Untergruppe gezeigt wird. "hint": Hilfetext unter dem Feld.
SETTINGS_SCHEMA = [
    {"key": "landing", "kind": "select", "label": "Startseite nach Anmeldung",
     "options": [("uebersicht", "Übersicht"), ("dashboard", "Nachrichten"),
                 ("hausaufgaben", "Hausaufgaben"), ("stundenplan", "Stundenplan")],
     "default": "uebersicht"},
    {"key": "hw_status", "kind": "select", "label": "Hausaufgaben: Standardfilter",
     "options": [("alle", "Alle"), ("offen", "Nur offene"),
                 ("überfällig", "Nur überfällige"), ("erledigt", "Nur erledigte"),
                 ("papierkorb", "Papierkorb")],
     "default": "alle"},
    {"key": "hw_tests", "kind": "bool",
     "label": "Hausaufgaben: Tests und Prüfungen standardmäßig einbeziehen",
     "default": False},
    {"key": "ov_unread", "kind": "int",
     "label": "Übersicht: max. ungelesene Nachrichten",
     "min": 1, "max": 50, "default": OVERVIEW_UNREAD_LIMIT},
    {"key": "ov_homework", "kind": "int",
     "label": "Übersicht: max. offene Hausaufgaben",
     "min": 1, "max": 50, "default": OVERVIEW_HOMEWORK_LIMIT},
]
SETTINGS_DEFAULTS = {s["key"]: s["default"] for s in SETTINGS_SCHEMA}


def user_settings() -> dict:
    """Einstellungen des eingeloggten Users (Defaults + gespeicherte Werte)."""
    merged = dict(SETTINGS_DEFAULTS)
    try:
        uhash = apicache.user_hash(session.get("subdomain", ""),
                                   session.get("username", ""))
        stored = apicache.load_settings(uhash)
        for spec in SETTINGS_SCHEMA:
            if spec["key"] in stored:
                merged[spec["key"]] = _coerce_setting(spec, stored[spec["key"]])
    except Exception:
        pass
    return merged


def _coerce_setting(spec: dict, value):
    """Einzelwert gegen Schema prüfen/normalisieren (fällt auf Default zurück)."""
    kind = spec.get("kind")
    try:
        if kind == "select":
            valid = [v for v, _ in spec.get("options", [])]
            return value if value in valid else spec["default"]
        if kind == "bool":
            return bool(value) if isinstance(value, bool) else str(value) in ("1", "true", "on")
        if kind == "int":
            iv = int(value)
            return max(spec.get("min", iv), min(spec.get("max", iv), iv))
        if kind in ("text", "password"):
            s = str(value or "").strip().replace("\n", " ").replace("\r", "")
            return s[:int(spec.get("maxlength", 500))]
    except (TypeError, ValueError):
        pass
    return spec["default"]


def settings_from_form(form) -> dict:
    """POST-Formular gegen Schema validieren -> speicherfertiges Dict."""
    values = {}
    for spec in SETTINGS_SCHEMA:
        key = spec["key"]
        kind = spec.get("kind")
        if kind == "bool":
            # Checkbox: nur bei gesetztem Haken im Formular enthalten.
            values[key] = form.get(key, "0") in ("1", "true", "on")
        else:
            values[key] = _coerce_setting(spec, form.get(key))
    return values

# Deutsche Labels für alle Timeline-Typen der EduPage-API
# (Karten, Dropdowns, CSV-Exporte; Filter-Logik nutzt weiter Rohwerte).
TYPE_LABELS = {
    "sprava": "Nachricht",
    "chat": "Chat",
    "anketa": "Umfrage",
    "news": "Neuigkeit",
    "genotif": "Mitteilung",
    "homework": "Hausaufgabe",
    "etesthw": "Online-Test",
    "homeworkstudentstav": "Hausaufgaben-Status",
    "bexam": "Schularbeit",
    "sexam": "Test",
    "oexam": "Mündliche Prüfung",
    "pexam": "Projektprüfung",
    "rexam": "Wiederholungsprüfung",
    "testing": "Testung",
    "testpridelenie": "Prüfungszuweisung",
    "testvysledok": "Prüfungsergebnis",
    "znamka": "Note",
    "znamkydoc": "Notendokument",
    "other_cb": "Klassenbucheintrag",
    "ctevent": "Klassenereignis",
    "bmeeting": "Besprechung",
    "culture": "Kulturveranstaltung",
    "event": "Ereignis",
    "excursion": "Exkursion",
    "parentsevening": "Elternabend",
    "process": "Vorgang",
    "schoolevent": "Schulveranstaltung",
    "trip": "Ausflug",
    "signin": "Anmeldung",
    "meeting": "Versammlung",
    "freeday": "Freier Tag",
    "holiday": "Feiertag",
    "sholiday": "Schulferien",
    "ttcancel": "Entfallene Stunde",
    "ctlesson": "Klassenlehrerstunde",
    "distant": "Distanzunterricht",
    "lesson": "Unterricht",
    "project": "Projekt",
    "plesson": "Geplante Stunde",
    "other_safety": "Sicherheitshinweis",
    "rlesson": "Wiederholungsstunde",
    "timetable": "Stundenplan",
    "bookroom": "Raumbuchung",
    "changeroom": "Raumwechsel",
    "substitution": "Vertretung",
    "pipnutie": "Anstupser",
    "ospravedlnenka": "Entschuldigung",
    "representation": "Repräsentation",
    "student_absent": "Fehlzeit",
    "strava_kredit": "Essensguthaben",
    "strava_vydaj": "Essensausgabe",
    "stravamenu": "Speiseplan",
    "h_stravamenu": "Speiseplan (Verlauf)",
    "confirmation": "Bestätigung",
    "contest": "Wettbewerb",
    "album": "Fotoalbum",
    "payments": "Zahlungen",
    "lost": "Fundsache",
    "vcelicka": "Bienchen",
    "other": "Sonstiges",
    "h_attendance": "Anwesenheit (Verlauf)",
    "h_vcelicka": "Bienchen (Verlauf)",
    "h_clearcache": "Cache (Verlauf)",
    "h_cleardbi": "Datenbank (Verlauf)",
    "h_clearisicdata": "ISIC-Daten (Verlauf)",
    "h_clearplany": "Pläne (Verlauf)",
    "h_contest": "Wettbewerb (Verlauf)",
    "h_dailyplan": "Tagesplan (Verlauf)",
    "h_edusettings": "Schuleinstellungen (Verlauf)",
    "h_financie": "Finanzen (Verlauf)",
    "h_znamky": "Noten (Verlauf)",
    "h_homework": "Hausaufgaben (Verlauf)",
    "h_igroups": "Gruppen (Verlauf)",
    "h_process": "Vorgang (Verlauf)",
    "h_processtypes": "Vorgangsarten (Verlauf)",
    "h_settings": "Einstellungen (Verlauf)",
    "h_substitution": "Vertretung (Verlauf)",
    "h_timetable": "Stundenplan (Verlauf)",
    "h_userphoto": "Profilfoto (Verlauf)",
    "unknown": "Unbekannt",
}


def type_label(t: str) -> str:
    return TYPE_LABELS.get(t, t)


# Slowakische Auto-Texte des EduPage-Servers (Noten, Ereignisse, Tests,
# Entschuldigungen, Fotoalben, Stundenplan) → Deutsch. Die Phrasen enthalten
# slowakische Sonderzeichen und treffen daher keinen deutschen Text.
# Längere Phrasen stehen zuerst (Substring-Ersetzung der Reihe nach).
SK_DE_PHRASES = [
    ("Zverejnený nový rozvrh", "Neuer Stundenplan veröffentlicht"),
    ("Aktualizovaný fotoalbum", "Aktualisiertes Fotoalbum"),
    ("Nová ospravedlnenka", "Neue Entschuldigung"),
    ("Pridelený test", "Zugeteilter Test"),
    ("Udalosť:", "Ereignis:"),
    ("Známka", "Note"),
    # Fallbacks ohne Diakritika (falls der Server je ohne liefert):
    ("Zverejneny novy rozvrh", "Neuer Stundenplan veröffentlicht"),
    ("Aktualizovany fotoalbum", "Aktualisiertes Fotoalbum"),
    ("Nova ospravedlnenka", "Neue Entschuldigung"),
    ("Prideleny test", "Zugeteilter Test"),
    ("Udalost:", "Ereignis:"),
    ("Znamka", "Note"),
]


def translate_server_text(text: str) -> str:
    """Slowakische Server-Floskeln im Timeline-Text eindeutschen."""
    if not text:
        return text
    for sk, de in SK_DE_PHRASES:
        if sk in text:
            text = text.replace(sk, de)
    return text


def _parse_due_date(value) -> "date | None":
    if not value or not isinstance(value, str):
        return None
    value = value.strip()
    for fmt in ("%Y-%m-%d %H:%M:%S", "%Y-%m-%d", "%d.%m.%Y", "%d.%m.%Y %H:%M"):
        try:
            return datetime.strptime(value, fmt).date()
        except ValueError:
            continue
    return None


def homework_to_dict(ev) -> dict:
    """TimelineEvent (Hausaufgabe/Test) -> Template-Dict mit Fälligkeitsdatum + Status."""
    try:
        type_value = ev.event_type.value if ev.event_type else "unknown"
    except Exception:
        type_value = str(getattr(ev, "event_type", "unknown"))

    timestamp = ev.timestamp
    if isinstance(timestamp, datetime):
        assigned_str = timestamp.strftime("%Y-%m-%d %H:%M")
        assigned_iso = timestamp.isoformat()
    else:
        assigned_str = str(timestamp)
        assigned_iso = str(timestamp)

    ad = ev.additional_data if isinstance(ev.additional_data, dict) else {}
    old = ad.get("oldVals") if isinstance(ad.get("oldVals"), dict) else {}

    def pick(*dicts, keys):
        for d in dicts:
            if not isinstance(d, dict):
                continue
            for k in keys:
                v = d.get(k)
                if isinstance(v, str) and v.strip():
                    return v.strip()
                if v is not None and k in ("predmet", "subject", "subjectid"):
                    return v
        return ""

    # Fälligkeitsdatum: liegt fast immer in oldVals.date (YYYY-MM-DD)
    due_raw = pick(old, ad, keys=("date", "dueDate", "due-date", "dateto",
                                  "duedate", "termin", "dateTo"))
    due = _parse_due_date(due_raw)

    title = pick(old, ad, keys=("title", "nazov", "name", "nadpis")) or ""
    description = pick(old, ad, keys=("popis", "description", "text",
                                      "messageContent", "detail")) or ""
    subject = pick(old, ad, keys=("predmet", "subject", "subjectName",
                                  "predmetName")) or ""

    text = (ev.text or "").strip()
    if not title:
        # Erste Zeile des Texts als Titel-Ersatz
        title = text.split("\n")[0].strip()[:120] if text else f"Hausaufgabe #{ev.event_id}"
    if not description and text and text != title:
        description = text

    is_done = bool(getattr(ev, "is_done", False))
    done_at = getattr(ev, "done_at", None)
    done_at_str = done_at.strftime("%Y-%m-%d %H:%M") if isinstance(done_at, datetime) else ""

    today = date.today()
    if is_done:
        status = "erledigt"
    elif due is None:
        status = "ohne Datum"
    elif due < today:
        status = "überfällig"
    elif due == today:
        status = "heute fällig"
    else:
        status = "offen"

    status_class = {
        "überfällig": "st-ueber",
        "heute fällig": "st-heute",
        "offen": "st-offen",
        "erledigt": "st-erledigt",
    }.get(status, "st-ohne")
    tag_class = {
        "überfällig": "tag-red",
        "heute fällig": "tag-amber",
        "offen": "tag-blue",
        "erledigt": "tag-green",
    }.get(status, "tag-gray")

    try:
        extra_json = json.dumps(ad, ensure_ascii=False, indent=2)
    except Exception:
        extra_json = str(ad)

    return {
        "id": ev.event_id,
        "type": type_value,
        "type_label": type_label(type_value),
        "title": title,
        "description": description,
        "subject": str(subject),
        "author": format_person(ev.author),
        "recipient": format_person(ev.recipient),
        "assigned": assigned_str,
        "assigned_iso": assigned_iso,
        "due": due.isoformat() if due else "",
        "due_display": due.strftime("%a %d.%m.%Y") if due else "–",
        "due_raw": due_raw or "",
        "status": status,
        "status_class": status_class,
        "tag_class": tag_class,
        "is_done": is_done,
        "done_at": done_at_str,
        "is_starred": bool(getattr(ev, "is_starred", False)),
        "extra": extra_json,
    }


def get_logged_in_edupage():
    """Re-login aus Session-Cookie. Returns (edupage, username, subdomain) oder wirft."""
    username = session["username"]
    subdomain = session["subdomain"]
    password = session_password()  # wirft SessionExpired bei alter/leerer Session
    edupage, two_factor, real_subdomain = do_login(username, password, subdomain)
    if two_factor is not None:
        raise RuntimeError("2FA_REQUIRED")
    session["subdomain"] = real_subdomain
    return edupage, username, real_subdomain


# ---------------------------------------------------------------- routes

@app.route("/")
def index():
    if "username" in session and "pwd_enc" in session:
        landing = user_settings().get("landing", "uebersicht")
        if landing == "dashboard":
            return redirect(url_for("dashboard"))
        if landing == "hausaufgaben":
            return redirect(url_for("hausaufgaben"))
        if landing == "stundenplan":
            return redirect(url_for("stundenplan"))
        return uebersicht()
    return render_template("login.html")


@app.route("/login", methods=["POST"])
def login():
    username = request.form.get("username", "").strip()
    password = request.form.get("password", "")
    subdomain = request.form.get("subdomain", "").strip()
    remember = request.form.get("remember", "0") == "1"

    if not username or not password:
        flash("Bitte Benutzername und Passwort eingeben.", "error")
        return redirect(url_for("index"))

    try:
        edupage, two_factor, real_subdomain = do_login(username, password, subdomain)
    except BadCredentialsException:
        flash("Falscher Benutzername, Passwort oder Subdomain.", "error")
        return redirect(url_for("index"))
    except CaptchaException:
        flash("EduFlow verlangt ein Captcha. Bitte einmal im Browser anmelden, dann erneut versuchen.", "error")
        return redirect(url_for("index"))
    except Exception as e:
        flash(f"Anmeldung fehlgeschlagen: {e}", "error")
        return redirect(url_for("index"))

    if two_factor is not None:
        # 2FA required -> stash pending login server-side, ask for code
        token = secrets.token_hex(16)
        PENDING_2FA[token] = {
            "edupage": edupage,
            "two_factor": two_factor,
            "username": username,
            "subdomain": real_subdomain,
            "password": password,  # nur im Server-Speicher, nie im Cookie
            "remember": remember,
        }
        session["pending_2fa"] = token
        return redirect(url_for("twofa"))

    store_login_session(username, real_subdomain, password, remember)
    return redirect("/uebersicht")


@app.route("/2fa", methods=["GET", "POST"])
def twofa():
    token = session.get("pending_2fa")
    pending = PENDING_2FA.get(token) if token else None
    if not pending:
        flash("2FA-Sitzung abgelaufen. Bitte erneut anmelden.", "error")
        return redirect(url_for("index"))

    if request.method == "POST":
        code = request.form.get("code", "").strip()
        if not code:
            flash("Bitte den 2FA-Code aus E-Mail / App eingeben.", "error")
            return render_template("2fa.html")
        try:
            pending["two_factor"].finish_with_code(code)
        except Exception as e:
            flash(f"2FA fehlgeschlagen: {e}", "error")
            return render_template("2fa.html")
        # success
        store_login_session(
            pending["username"], pending["subdomain"],
            pending["password"], pending.get("remember", True),
        )
        PENDING_2FA.pop(token, None)
        session.pop("pending_2fa", None)
        return redirect("/")

    return render_template("2fa.html")


@app.route("/dashboard")
@login_required
def dashboard():
    username = session["username"]
    subdomain = session["subdomain"]

    since_str = request.args.get("since", EARLIEST_DEFAULT.isoformat())
    try:
        since = date.fromisoformat(since_str)
    except ValueError:
        since = EARLIEST_DEFAULT
        since_str = since.isoformat()

    selected_type = (request.args.get("type") or "").strip()
    force_refresh = request.args.get("refresh", "0") == "1"
    q = (request.args.get("q") or "").strip()[:200]

    # Re-login on every load (EduPage sessions expire; keeps things stateless)
    try:
        password = session_password()
        edupage, two_factor, real_subdomain = do_login(username, password, subdomain)
        if two_factor is not None:
            flash("Sitzung erfordert erneut 2FA. Bitte erneut anmelden.", "error")
            return redirect(url_for("logout"))
        session["subdomain"] = real_subdomain
        subdomain = real_subdomain
    except SessionExpired:
        flash("Anmeldung abgelaufen. Bitte erneut anmelden.", "error")
        return redirect(url_for("logout"))
    except BadCredentialsException:
        flash("Gespeicherte Zugangsdaten sind ungültig. Bitte erneut anmelden.", "error")
        return redirect(url_for("logout"))
    except CaptchaException:
        flash("EduFlow verlangt ein Captcha. Bitte einmal im Browser anmelden, dann erneut versuchen.", "error")
        return redirect(url_for("logout"))
    except Exception as e:
        return render_template(
            "dashboard.html",
            username=username,
            subdomain=subdomain,
            since=since_str,
            groups=[],
            total=0,
            error=f"Nachrichten konnten nicht geladen werden: {e}",
            type_options=[],
            selected_type="",
            first_source=None,
            last_source=None,
            oldest_label="",
            n_requests=0,
            cache_info="",
            attach_map={},
            type_labels=TYPE_LABELS,
            q=q,
        )

    try:
        # Verlauf aus lokalem Cache (nur bei Änderung/neuen Einträgen neu laden).
        events, n_requests, _effective, _cache = get_timeline_cached(
            edupage, subdomain, username, since, force_refresh)
        cache_info = _cache.get("cache_info", "")
    except NotLoggedInException:
        flash("Nicht angemeldet. Bitte erneut anmelden.", "error")
        return redirect(url_for("logout"))
    except Exception as e:
        return render_template(
            "dashboard.html",
            username=username,
            subdomain=subdomain,
            since=since_str,
            groups=[],
            total=0,
            error=f"Nachrichten konnten nicht geladen werden: {e}",
            type_options=[],
            selected_type="",
            first_source=None,
            last_source=None,
            oldest_label="",
            n_requests=0,
            cache_info="",
            attach_map={},
            type_labels=TYPE_LABELS,
            q=q,
        )

    # Älteste Nachricht finden – ihr Datum ist der Verlauf-Start
    # (ungefiltert, d.h. über alle Timeline-Typen hinweg).
    oldest_ev, newest_ev = oldest_and_newest(events)
    first_source = fmt_day(oldest_ev.timestamp) if oldest_ev else None
    last_source = fmt_day(newest_ev.timestamp) if newest_ev else None
    oldest_label = short_label(oldest_ev) if oldest_ev else ""
    if oldest_ev is not None:
        since_str = oldest_ev.timestamp.date().isoformat()

    # Gruppiert nach Kategorie (jeweils neueste zuerst): Nachrichten,
    # Hausaufgaben (mit Fälligkeit + Status), Tests & Prüfungen, Sonstiges.
    # Der alte ?only_messages-URL-Parameter wird ignoriert – alles wird
    # gruppiert gezeigt, Typ und Suche filtern live im Browser.
    def _sort_key(e):
        ts = getattr(e, "timestamp", None)
        if isinstance(ts, datetime):
            return ts.isoformat()
        return str(ts or "")

    groups = [
        {"key": "nachrichten", "label": "Nachrichten", "kind": "message", "items": []},
        {"key": "hausaufgaben", "label": "Hausaufgaben", "kind": "homework", "items": []},
        {"key": "tests", "label": "Tests & Prüfungen", "kind": "homework", "items": []},
        {"key": "sonstige", "label": "Sonstiges", "kind": "message", "items": []},
    ]
    by_key = {g["key"]: g for g in groups}
    seen_ids: list = []
    for e in sorted(events, key=_sort_key, reverse=True):
        t = _event_type_str(e)
        if t in MESSAGE_TYPES:
            by_key["nachrichten"]["items"].append(event_to_dict(e))
            seen_ids.append(getattr(e, "event_id", None))
        elif t in HOMEWORK_TYPES:
            by_key["hausaufgaben"]["items"].append(homework_to_dict(e))
        elif t in EXAM_TYPES:
            by_key["tests"]["items"].append(homework_to_dict(e))
        else:
            by_key["sonstige"]["items"].append(event_to_dict(e))

    # Typ-Optionen mit deutscher Bezeichnung + Anzahl für den Filter.
    # Ungültige Auswahl aus der URL zurücksetzen, sonst würde alles ausgeblendet.
    counts: dict = {}
    for g in groups:
        for m in g["items"]:
            counts[m["type"]] = counts.get(m["type"], 0) + 1
    if selected_type not in counts:
        selected_type = ""
    type_options = sorted(
        ((t, type_label(t), counts[t]) for t in counts),
        key=lambda o: o[1].lower(),
    )

    # Wer die Nachrichtenliste öffnet, hat alles Aktuelle gesehen:
    # Nachrichtentypen als gelesen markieren (für die Übersicht).
    try:
        apicache.mark_seen(
            apicache.user_hash(subdomain, username), seen_ids)
    except Exception:
        pass

    attach_map = {}
    for g in groups:
        if g["kind"] != "message":
            continue
        for m in g["items"]:
            if m.get("attachments"):
                attach_map[str(m["id"])] = [a["name"] for a in m["attachments"]]

    return render_template(
        "dashboard.html",
        username=username,
        subdomain=subdomain,
        since=since_str,
        groups=groups,
        total=sum(len(g["items"]) for g in groups),
        error=None,
        type_options=type_options,
        selected_type=selected_type,
        first_source=first_source,
        last_source=last_source,
        oldest_label=oldest_label,
        n_requests=n_requests,
        cache_info=cache_info,
        attach_map=attach_map,
        type_labels=TYPE_LABELS,
        q=q,
    )


def mark_hidden(items, hidden) -> tuple:
    """Teilt Hausaufgaben-Dicts in (sichtbar, gelöscht) und setzt je
    Eintrag das `is_hidden`-Flag (für Design + Sortierung)."""
    hidden = {str(x) for x in (hidden or set()) if x is not None}
    visible, deleted = [], []
    for i in items or []:
        if str(i.get("id")) in hidden:
            i["is_hidden"] = True
            deleted.append(i)
        else:
            i["is_hidden"] = False
            visible.append(i)
    return visible, deleted


def homework_rank(i) -> int:
    """Sortierrang: überfällig zuerst, dann offen, dann erledigt,
    gelöschte (Papierkorb) immer ganz unten."""
    if i.get("is_hidden"):
        return 3
    if i.get("status") == "überfällig":
        return 0
    if i.get("status") == "erledigt":
        return 2
    return 1


@app.route("/hausaufgaben")
@app.route("/homework")
@login_required
def hausaufgaben():
    username = session["username"]
    subdomain = session["subdomain"]

    since_str = request.args.get("since", EARLIEST_DEFAULT.isoformat())
    try:
        since = date.fromisoformat(since_str)
    except ValueError:
        since = EARLIEST_DEFAULT
        since_str = since.isoformat()

    # Defaults aus den Einstellungen, solange kein expliziter URL-Parameter da ist.
    _s = user_settings()
    status_filter = request.args.get("status", _s["hw_status"])  # alle|offen|überfällig|erledigt|papierkorb
    if status_filter not in ("alle", "offen", "überfällig", "erledigt", "papierkorb"):
        status_filter = _s["hw_status"]
    include_tests = request.args.get(
        "include_tests", "1" if _s["hw_tests"] else "0") == "1"
    force_refresh = request.args.get("refresh", "0") == "1"

    try:
        edupage, username, subdomain = get_logged_in_edupage()
    except (RuntimeError, SessionExpired):
        flash("Sitzung erfordert erneut 2FA. Bitte erneut anmelden.", "error")
        return redirect(url_for("logout"))
    except BadCredentialsException:
        flash("Gespeicherte Zugangsdaten sind ungültig. Bitte erneut anmelden.", "error")
        return redirect(url_for("logout"))
    except CaptchaException:
        flash("EduFlow verlangt ein Captcha. Bitte einmal im Browser anmelden, dann erneut versuchen.", "error")
        return redirect(url_for("logout"))
    except Exception as e:
        return render_template(
            "homework.html", username=username, subdomain=subdomain,
            since=since_str, status=status_filter, include_tests=include_tests,
            items=[], total=0, n_offen=0, n_ueber=0, n_erledigt=0, n_hidden=0,
            error=f"Konnte Hausaufgaben nicht laden: {e}",
            first_source=None, last_source=None, oldest_label="",
            n_requests=0, cache_info="", type_labels=TYPE_LABELS,
        )

    try:
        # Verlauf aus lokalem Cache (gleicher Timeline-Cache wie Dashboard).
        events, n_requests, _effective, _cache = get_timeline_cached(
            edupage, subdomain, username, since, force_refresh)
        cache_info = _cache.get("cache_info", "")
    except NotLoggedInException:
        flash("Nicht angemeldet. Bitte erneut anmelden.", "error")
        return redirect(url_for("logout"))
    except Exception as e:
        return render_template(
            "homework.html", username=username, subdomain=subdomain,
            since=since_str, status=status_filter, include_tests=include_tests,
            items=[], total=0, n_offen=0, n_ueber=0, n_erledigt=0, n_hidden=0,
            error=f"Konnte Hausaufgaben nicht laden: {e}",
            first_source=None, last_source=None, oldest_label="",
            n_requests=0, cache_info="", type_labels=TYPE_LABELS,
        )

    wanted = set(HOMEWORK_TYPES)
    if include_tests:
        wanted |= EXAM_TYPES
    hw_events = [e for e in events if _event_type_str(e) in wanted]
    # Älteste Hausaufgabe finden – ihr Datum ist der Verlauf-Start dieser Seite.
    oldest_hw, newest_hw = oldest_and_newest(hw_events)
    first_source = fmt_day(oldest_hw.timestamp) if oldest_hw else None
    last_source = fmt_day(newest_hw.timestamp) if newest_hw else None
    oldest_label = (homework_to_dict(oldest_hw).get("title", "")
                    if oldest_hw else "")
    if oldest_hw is not None:
        since_str = oldest_hw.timestamp.date().isoformat()
    items = [homework_to_dict(e) for e in hw_events]

    # Lokal ausgeblendete Aufgaben (Swipe nach rechts) herausfiltern –
    # außer im Papierkorb-Modus (zeigt nur diese) und bei "alle"
    # (zeigt sie zusätzlich ganz unten, eigenes Design via is_hidden).
    # Die Zähler beziehen sich immer auf die sichtbaren Aufgaben.
    hidden = apicache.load_hidden(apicache.user_hash(subdomain, username))
    visible, hidden_items = mark_hidden(items, hidden)
    n_hidden = len(hidden_items)
    n_offen = sum(1 for i in visible if i["status"] in ("offen", "heute fällig"))
    n_ueber = sum(1 for i in visible if i["status"] == "überfällig")
    n_erledigt = sum(1 for i in visible if i["status"] == "erledigt")

    if status_filter == "papierkorb":
        items = hidden_items
    elif status_filter == "alle":
        items = visible + hidden_items
    else:
        items = visible

    if status_filter == "offen":
        items = [i for i in items if i["status"] in ("offen", "heute fällig", "ohne Datum")]
    elif status_filter == "überfällig":
        items = [i for i in items if i["status"] == "überfällig"]
    elif status_filter == "erledigt":
        items = [i for i in items if i["status"] == "erledigt"]

    # Sortierung: Überfällige zuerst, dann Offene (nach Fälligkeit,
    # ohne Datum hinten), Erledigte danach, Gelöschte ganz ans Ende.
    items.sort(key=lambda i: (homework_rank(i), i["due"] == "", i["due"], i["assigned_iso"]))

    return render_template(
        "homework.html", username=username, subdomain=subdomain,
        since=since_str, status=status_filter, include_tests=include_tests,
        items=items, total=len(items), n_offen=n_offen, n_ueber=n_ueber,
        n_erledigt=n_erledigt, n_hidden=n_hidden, error=None,
        first_source=first_source, last_source=last_source,
        oldest_label=oldest_label, n_requests=n_requests,
        cache_info=cache_info, type_labels=TYPE_LABELS,
    )


@app.route("/hausaufgaben/erledigt", methods=["POST"])
@login_required
def hausaufgabe_erledigt():
    """Hausaufgabe als erledigt markieren (oder wieder öffnen)."""
    username = session["username"]
    subdomain = session["subdomain"]

    event_id = (request.form.get("id") or "").strip()
    done = request.form.get("done", "1") == "1"
    # Filter für den Rücksprung erhalten
    back_args = {
        "status": request.form.get("status", "alle"),
        "since": request.form.get("since", EARLIEST_DEFAULT.isoformat()),
        "include_tests": request.form.get("include_tests", "0"),
    }
    back = url_for("hausaufgaben", **back_args)

    if not event_id:
        flash("Keine Aufgabe ausgewählt.", "error")
        return redirect(back)

    try:
        edupage, username, subdomain = get_logged_in_edupage()
    except (RuntimeError, SessionExpired):
        flash("Sitzung erfordert erneut 2FA. Bitte erneut anmelden.", "error")
        return redirect(url_for("logout"))
    except (BadCredentialsException, CaptchaException):
        flash("Anmeldung ungültig. Bitte erneut anmelden.", "error")
        return redirect(url_for("logout"))
    except Exception as e:
        flash(f"Konnte Status nicht ändern: {e}", "error")
        return redirect(back)

    try:
        set_homework_done(edupage, event_id, done)
    except Exception as e:
        flash(f"Konnte Status nicht ändern: {e}", "error")
        return redirect(back)

    # Lokalen Cache sofort nachpflegen, damit die Anzeige ohne Neu-Fetch stimmt.
    try:
        apicache.set_record_done(
            apicache.user_hash(subdomain, username), event_id, done)
    except Exception:
        pass
    flash("Als erledigt markiert." if done else "Wieder geöffnet.", "info")
    return redirect(back)


@app.route("/hausaufgaben/ausblenden", methods=["POST"])
@login_required
def hausaufgabe_ausblenden():
    """Hausaufgabe in den Papierkorb legen (oder daraus zurückholen).

    Hinweis: Schüler können aufgegebene Hausaufgaben auf EduPage nicht
    löschen – nur das done-Flag ist Schüler-Zustand auf dem Server.
    Der Papierkorb ist daher bewusst rein lokal (pro User, Datei
    `hidden_<hash>.json`, wie der Gelesen-Status).
    Zurückholen markiert die Aufgabe gleichzeitig als offen: bei echten
    Hausaufgaben via Server (`homeworkFlag`, sonst bliebe sie erledigt),
    bei anderen Typen (z. B. Tests ohne done-Flag) nur lokal.
    """
    username = session["username"]
    subdomain = session["subdomain"]

    event_id = (request.form.get("id") or "").strip()
    hide = request.form.get("hide", "1") == "1"
    back_args = {
        "status": request.form.get("status", "alle"),
        "since": request.form.get("since", EARLIEST_DEFAULT.isoformat()),
        "include_tests": request.form.get("include_tests", "0"),
    }
    back = url_for("hausaufgaben", **back_args)

    if not event_id:
        flash("Keine Aufgabe ausgewählt.", "error")
        return redirect(back)

    uhash = apicache.user_hash(subdomain, username)
    if hide:
        apicache.hide_ids(uhash, [event_id])
        flash("Aufgabe in den Papierkorb verschoben.", "info")
        return redirect(back)

    # Zurückholen: einblenden + als offen markieren.
    try:
        edupage, username, subdomain = get_logged_in_edupage()
    except (RuntimeError, SessionExpired):
        flash("Sitzung erfordert erneut 2FA. Bitte erneut anmelden.", "error")
        return redirect(url_for("logout"))
    except (BadCredentialsException, CaptchaException):
        flash("Anmeldung ungültig. Bitte erneut anmelden.", "error")
        return redirect(url_for("logout"))
    except Exception as e:
        flash(f"Konnte Aufgabe nicht wiederherstellen: {e}", "error")
        return redirect(back)

    # Nur echte Hausaufgaben kennen das done-Flag auf dem Server.
    rec_type = None
    try:
        cached = apicache.load_timeline(uhash)
        for r in (cached.get("events", []) if cached else []):
            if str(r.get("id")) == str(event_id):
                rec_type = str(r.get("type", ""))
                break
    except Exception:
        pass
    if rec_type in HOMEWORK_TYPES:
        try:
            set_homework_done(edupage, event_id, False)
        except Exception as e:
            flash(f"Konnte Aufgabe nicht als offen markieren: {e}", "error")
            return redirect(back)
        try:
            apicache.set_record_done(uhash, event_id, False)
        except Exception:
            pass
        apicache.unhide_ids(uhash, [event_id])
        flash("Aufgabe aus dem Papierkorb geholt und als offen markiert.", "info")
    else:
        apicache.unhide_ids(uhash, [event_id])
        flash("Aufgabe aus dem Papierkorb geholt.", "info")
    return redirect(back)


# ------------------------------------------------------- Übersicht

def unread_messages(events, seen: set, limit: int = OVERVIEW_UNREAD_LIMIT):
    """Neueste Nachrichtentypen, die noch nicht als gesehen markiert sind.

    Die EduPage-API kennt kein "ungelesen"-Flag, daher zählt lokal:
    alles aus MESSAGE_TYPES, dessen ID nicht in `seen` steht.
    Returns (items, total_unread) – items sind `event_to_dict`-Dicts,
    neueste zuerst, auf `limit` gekürzt.
    """
    dicts = [event_to_dict(e) for e in events if _event_type_str(e) in MESSAGE_TYPES]
    dicts.sort(key=lambda m: m["sort_key"], reverse=True)
    unread = [m for m in dicts if str(m["id"]) not in seen]
    return unread[:limit], len(unread)


def open_homework(events, hidden=None, limit: int = OVERVIEW_HOMEWORK_LIMIT):
    """Offene Hausaufgaben für die Übersicht (überfällig zuerst).

    `hidden`: IDs lokal ausgeblendeter Aufgaben (werden überall rausgefiltert).
    Returns (shown, n_offen, n_ueber, n_erledigt): `shown` sind die vordersten
    `limit` unerledigten Aufgaben, die Zähler beziehen sich auf alle Hausaufgaben.
    """
    hidden = hidden or set()
    items = [homework_to_dict(e) for e in events
             if _event_type_str(e) in HOMEWORK_TYPES
             and str(getattr(e, "event_id", "")) not in hidden]
    n_offen = sum(1 for i in items if i["status"] in ("offen", "heute fällig"))
    n_ueber = sum(1 for i in items if i["status"] == "überfällig")
    n_erledigt = sum(1 for i in items if i["status"] == "erledigt")

    def _rank(i):
        if i["status"] == "überfällig":
            return 0
        if i["status"] == "erledigt":
            return 2
        return 1

    items.sort(key=lambda i: (_rank(i), i["due"] == "", i["due"], i["assigned_iso"]))
    shown = [i for i in items if i["status"] != "erledigt"][:limit]
    return shown, n_offen, n_ueber, n_erledigt


@app.route("/uebersicht")
def uebersicht_alt():
    # Alte URL bleibt als Weiterleitung erhalten.
    return redirect("/")


@app.route("/overview")
@login_required
def uebersicht():
    """Startseite: Uhr oben links, swipebares Stunden-Karussell oben rechts,
    ungelesene Nachrichten links, offene Hausaufgaben rechts."""
    username = session["username"]
    subdomain = session["subdomain"]
    now = datetime.now()
    now_date = f"{GERMAN_WEEKDAYS[now.weekday()]}, {now.strftime('%d.%m.%Y')}"

    def _fail(error):
        return render_template(
            "overview.html", username=username, subdomain=subdomain,
            now_time=now.strftime("%H:%M:%S"), now_date=now_date,
            unread=[], n_unread=0, homework=[],
            n_offen=0, n_ueber=0, n_erledigt=0, current=None, next=None,
            lessons=[], lesson_start=0,
            weather_lat=WEATHER_LAT if WEATHER_LAT is not None else "",
            weather_lon=WEATHER_LON if WEATHER_LON is not None else "",
            weather_city=WEATHER_CITY,
            error=error, cache_info="",
        )

    try:
        edupage, username, subdomain = get_logged_in_edupage()
    except (RuntimeError, SessionExpired):
        flash("Sitzung erfordert erneut 2FA. Bitte erneut anmelden.", "error")
        return redirect(url_for("logout"))
    except BadCredentialsException:
        flash("Gespeicherte Zugangsdaten sind ungültig. Bitte erneut anmelden.", "error")
        return redirect(url_for("logout"))
    except CaptchaException:
        flash("EduFlow verlangt ein Captcha. Bitte einmal im Browser anmelden, dann erneut versuchen.", "error")
        return redirect(url_for("logout"))
    except Exception as e:
        return _fail(f"Konnte Übersicht nicht laden: {e}")

    try:
        # Gleicher Timeline-Cache wie Nachrichten/Hausaufgaben.
        events, _n_requests, _effective, _cache = get_timeline_cached(
            edupage, subdomain, username, EARLIEST_DEFAULT, False)
        cache_info = _cache.get("cache_info", "")
    except NotLoggedInException:
        flash("Nicht angemeldet. Bitte erneut anmelden.", "error")
        return redirect(url_for("logout"))
    except Exception as e:
        return _fail(f"Konnte Übersicht nicht laden: {e}")

    uhash = apicache.user_hash(subdomain, username)
    _s = user_settings()
    unread, n_unread = unread_messages(
        events, apicache.load_seen(uhash), _s["ov_unread"])
    homework, n_offen, n_ueber, n_erledigt = open_homework(
        events, apicache.load_hidden(uhash), _s["ov_homework"])

    # Aktuelle Stunde für oben rechts: heutiger Stundenplan (aus Cache),
    # laufende bzw. nächste nicht-entfallene Stunde bestimmen.
    # Events (is_event, z. B. Projekttag) werden bewusst ignoriert –
    # hier stehen nur echte Unterrichtsstunden.
    current = None
    nxt = None
    _day_lessons = []
    try:
        _day_lessons, _dm = get_timetable_day_cached(
            edupage, subdomain, username, date.today(), False)

        def _range(s):
            try:
                _a, _b = s.split("–")
                return (datetime.strptime(_a.strip(), "%H:%M").time(),
                        datetime.strptime(_b.strip(), "%H:%M").time())
            except Exception:
                return (None, None)

        _now_t = now.time()
        for _d in _day_lessons:
            _s, _e = _range(_d.get("time", ""))
            if (_s and _e and _s <= _now_t <= _e and not _d.get("is_cancelled")
                    and not _d.get("is_event")):
                current = _d
                break
        for _d in _day_lessons:
            _s, _e = _range(_d.get("time", ""))
            if (_s and _e and _now_t < _s and not _d.get("is_cancelled")
                    and not _d.get("is_event")):
                nxt = _d
                break
    except Exception:
        current, nxt = None, None

    # Alle Stunden des Tages für das swipebare Karussell oben rechts:
    # echte Unterrichtsstunden (keine Events), Lernzeit zusammengefasst
    # wie im Stundenplan, laufende Stunde markiert, Startposition passend.
    lessons_today = []
    lesson_start = 0
    try:
        for _d in merge_lernzeit([dict(d) for d in _day_lessons]):
            if _d.get("is_event"):
                continue
            _s, _e = _range(_d.get("time", ""))
            _d["is_now"] = bool(
                _s and _e and _s <= _now_t <= _e and not _d.get("is_cancelled"))
            lessons_today.append(_d)
        if lessons_today:
            # _now_t/_range existieren hier sicher (_day_lessons war nicht leer)
            lesson_start = lesson_start_index(lessons_today, _now_t)
    except Exception:
        lessons_today = []
        lesson_start = 0

    return render_template(
        "overview.html", username=username, subdomain=subdomain,
        now_time=now.strftime("%H:%M:%S"), now_date=now_date,
        unread=unread, n_unread=n_unread, homework=homework,
        n_offen=n_offen, n_ueber=n_ueber, n_erledigt=n_erledigt,
        current=current, next=nxt, lessons=lessons_today,
        lesson_start=lesson_start,
        weather_lat=WEATHER_LAT if WEATHER_LAT is not None else "",
        weather_lon=WEATHER_LON if WEATHER_LON is not None else "",
        weather_city=WEATHER_CITY,
        error=None, cache_info=cache_info,
    )


# ------------------------------------------------------- Wetter (OpenWeatherMap)
# Key kommt aus der .env-Datei (OPENWEATHER_KEY, siehe .env.example) oder
# aus der Umgebung. Ohne Key meldet /api/wetter einen Fehler statt
# hartcodiertem Key im Code.
OPENWEATHER_KEY = os.environ.get("OPENWEATHER_KEY", "")


def _env_float(name: str):
    try:
        return float(os.environ.get(name, ""))
    except (TypeError, ValueError):
        return None


# Wetter-Standort aus der .env (WEATHER_LAT/WEATHER_LON). Falls leer,
# nimmt das Frontend die Browser-Geolocation, Fallback Berlin.
WEATHER_LAT = _env_float("WEATHER_LAT")
WEATHER_LON = _env_float("WEATHER_LON")
# Alternativ nur Stadtname (z. B. WEATHER_CITY=Wien). Koordinaten gehen vor.
WEATHER_CITY = (os.environ.get("WEATHER_CITY", "") or "").strip()


def _owm_cap(s: str) -> str:
    """Nur ersten Buchstaben groß (OWM liefert alles klein, Substantive
    wie "Regen" müssen groß bleiben) – str.capitalize() würde sie
    kleinschreiben."""
    s = s or ""
    return s[:1].upper() + s[1:] if s else ""


def _owm_localtime(ts, tz_offset) -> str:
    """Unix-Zeit + OWM-Timezone-Offset -> lokale HH:MM (oder "–")."""
    try:
        return datetime.fromtimestamp(int(ts) + int(tz_offset or 0),
                                      tz=timezone.utc).strftime("%H:%M")
    except (TypeError, ValueError, OverflowError, OSError):
        return "–"


def _owm_compass(deg) -> str:
    """Windrichtung in Grad -> Himmelsrichtung (N, NO, O, …) oder "–"."""
    try:
        dirs = ["N", "NO", "O", "SO", "S", "SW", "W", "NW"]
        return dirs[int((float(deg) + 22.5) // 45) % 8]
    except (TypeError, ValueError):
        return "–"


def _owm_aggregate_day(fc: dict, day_offset: int = 1) -> Optional[dict]:
    """Tageswerte aus der 3-Stunden-Vorhersage (2.5/forecast).

    `day_offset`: 0 = heute (Rest des Tages), 1 = morgen, 2 = übermorgen.
    Liefert max/min-Temperatur, Wetterlage (Mittagseintrag bevorzugt,
    sonst häufigstes Icon) und Regenwahrscheinlichkeit (`pop` als
    Tagesmaximum in Prozent, None ohne Daten).
    """
    day = (date.today() + timedelta(days=day_offset)).isoformat()
    entries = [e for e in (fc.get("list") or [])
               if str(e.get("dt_txt", "")).startswith(day)]
    temps = [e.get("main", {}).get("temp") for e in entries]
    temps = [t for t in temps if isinstance(t, (int, float))]
    if not temps:
        return None
    conds = [(e.get("weather") or [{}])[0] for e in entries]
    # Wetterlage: am besten mittags, sonst häufigstes Icon.
    midday = [c for e, c in zip(entries, conds)
              if "12:00:00" in str(e.get("dt_txt", "")) and c.get("icon")]
    if midday:
        icon, desc = midday[0]["icon"], midday[0].get("description", "")
    else:
        icons = [c.get("icon") for c in conds if c.get("icon")]
        icon = max(set(icons), key=icons.count) if icons else ""
        desc = next((c.get("description", "") for c in conds
                     if c.get("icon") == icon), "")
    pops = [e.get("pop") for e in entries]
    pops = [p for p in pops if isinstance(p, (int, float))]
    return {"max": round(max(temps)), "min": round(min(temps)),
            "desc": _owm_cap(desc), "icon": icon or "",
            "pop": round(max(pops) * 100) if pops else None}


@app.route("/api/wetter")
@login_required
def api_wetter():
    """Wetter-Proxy (Key bleibt serverseitig): heute + morgen +
    übermorgen als JSON (je mit Regenwahrscheinlichkeit `pop` in %),
    dazu Stundenvorhersage (`hourly`, nächste 24 h in 3-h-Schritten),
    Details (gefühlte Temperatur, Wind, …) und Ortsname (`city`).

    Ort per ?lat=..&lon=.. oder ?city=Name (OpenWeatherMap löst den
    Stadtnamen selbst auf). Ohne Angabe: 400.
    """
    params = {"appid": OPENWEATHER_KEY, "units": "metric", "lang": "de"}
    try:
        lat = float(request.args.get("lat", ""))
        lon = float(request.args.get("lon", ""))
    except (TypeError, ValueError):
        lat = lon = None
    city = (request.args.get("city") or "").strip()
    if lat is not None and lon is not None:
        params["lat"], params["lon"] = lat, lon
    elif city:
        params["q"] = city
    else:
        return {"error": "bad coords"}, 400
    if not OPENWEATHER_KEY:
        return {"error": "Kein API-Key (OPENWEATHER_KEY in .env eintragen)"}, 503
    try:
        cur = requests.get("https://api.openweathermap.org/data/2.5/weather",
                           params=params, timeout=8).json()
        if str(cur.get("cod")) != "200":
            return {"error": cur.get("message", "upstream")}, 502
        fc = requests.get("https://api.openweathermap.org/data/2.5/forecast",
                          params=params, timeout=8).json()
    except Exception as e:
        return {"error": str(e)}, 502
    w = (cur.get("weather") or [{}])[0]
    main = cur.get("main", {})
    wind = cur.get("wind", {})
    sys = cur.get("sys", {}) if isinstance(cur.get("sys"), dict) else {}
    tz = ((fc.get("city") or {}).get("timezone")
          if isinstance(fc, dict) else None)
    if not isinstance(tz, (int, float)):
        tz = cur.get("timezone", 0) if isinstance(cur, dict) else 0
    if not isinstance(tz, (int, float)):
        tz = 0
    tomorrow = _owm_aggregate_day(fc, 1) or {}
    day3 = _owm_aggregate_day(fc, 2) or {}
    day3["label"] = GERMAN_WEEKDAYS[(date.today() + timedelta(days=2)).weekday()]
    today_pop = _owm_aggregate_day(fc, 0)

    hourly = []
    for e in (fc.get("list") or [])[:8]:
        if not isinstance(e, dict):
            continue
        w2 = (e.get("weather") or [{}])[0] if isinstance(e.get("weather"), list) else {}
        main2 = e.get("main", {}) if isinstance(e.get("main"), dict) else {}
        t2 = main2.get("temp")
        p2 = e.get("pop")
        hourly.append({
            "time": _owm_localtime(e.get("dt"), tz),
            "temp": round(t2) if isinstance(t2, (int, float)) else None,
            "icon": w2.get("icon", "") or "",
            "desc": _owm_cap(w2.get("description", "") or ""),
            "pop": round(p2 * 100) if isinstance(p2, (int, float)) else None,
        })

    def _num(v):
        return v if isinstance(v, (int, float)) else None

    wind_ms = _num(wind.get("speed"))
    vis_m = _num(cur.get("visibility"))
    return {
        "city": cur.get("name", "") or "",
        "today": {
            "temp": round(main.get("temp", 0)),
            "max": round(main.get("temp_max", main.get("temp", 0))),
            "min": round(main.get("temp_min", main.get("temp", 0))),
            "desc": _owm_cap(w.get("description", "") or ""),
            "icon": w.get("icon", ""),
            "pop": today_pop["pop"] if today_pop else None,
        },
        "tomorrow": tomorrow,
        "day3": day3,
        "hourly": hourly,
        "details": {
            "feels_like": round(main["feels_like"]) if isinstance(main.get("feels_like"), (int, float)) else None,
            "humidity": _num(main.get("humidity")),
            "pressure": _num(main.get("pressure")),
            "wind_kmh": round(wind_ms * 3.6) if wind_ms is not None else None,
            "wind_dir": _owm_compass(wind.get("deg")),
            "clouds": _num((cur.get("clouds", {}) or {}).get("all")) if isinstance(cur.get("clouds"), dict) else None,
            "visibility_km": round(vis_m / 1000, 1) if vis_m is not None else None,
            "sunrise": _owm_localtime(sys.get("sunrise"), tz),
            "sunset": _owm_localtime(sys.get("sunset"), tz),
        },
    }


@app.route("/als-gelesen", methods=["POST"])
@login_required
def als_gelesen():
    """Alle aktuellen Nachrichten als gelesen markieren (Button der Übersicht)."""
    uhash = apicache.user_hash(session.get("subdomain", ""), session.get("username", ""))
    try:
        cached = apicache.load_timeline(uhash)
        records = cached.get("events", []) if cached else []
        ids = [r.get("id") for r in records
               if str(r.get("type", "")) in MESSAGE_TYPES]
        n = apicache.mark_seen(uhash, ids)
        if n:
            flash(f"{n} Nachrichten als gelesen markiert.", "info")
        else:
            flash("Nichts Neues – alles bereits gelesen.", "info")
    except Exception as e:
        flash(f"Gelesen-Status konnte nicht gespeichert werden: {e}", "error")
    return redirect("/uebersicht")


def _event_type_str(ev) -> str:
    try:
        return ev.event_type.value if ev.event_type else ""
    except Exception:
        return str(getattr(ev, "event_type", ""))


def _encode_eqap(params: dict) -> str:
    """EduPage-Form-Body im `eqap`-Format bauen (wie die JS-Referenzlib).

    `eqap=<base64 von urlencodierter Query>&eqaz=0`.
    `safe=""` damit auch "/" kodiert wird (wie JS encodeURIComponent).
    """
    query = urlencode(params)
    return f"eqap={quote(b64encode(query.encode('utf-8')).decode('ascii'), safe='')}&eqaz=0"


def encode_homework_flag_body(event_id, done: bool) -> str:
    """Request-Body für EduPages homeworkFlag-Endpoint bauen.

    Gleiche Kodierung wie die offizielle JS-Lib (EdupageAPI):
    `eqap=<base64 von urlencodierter Query>&eqaz=0` mit
    homeworkid=`timeline:<id>`, flag=`done`, value=`1`/`0`.
    """
    return _encode_eqap({
        "homeworkid": f"timeline:{event_id}",
        "flag": "done",
        "value": "1" if done else "0",
    })


def set_homework_done(edupage: Edupage, event_id, done: bool) -> dict:
    """Hausaufgabe auf EduPage als erledigt/offen markieren.

    Nutzt `POST /timeline/?akcia=homeworkFlag` wie der Web-Client.
    Returns die frischen `timelineUserProps` bei Erfolg, wirft sonst.
    """
    url = f"https://{edupage.subdomain}.edupage.org/timeline/?akcia=homeworkFlag"
    resp = edupage.session.post(
        url,
        data=encode_homework_flag_body(event_id, done),
        headers={
            "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8",
            "X-Requested-With": "XMLHttpRequest",
        },
        timeout=30,
    )
    if resp.status_code != 200:
        raise RuntimeError(f"EduPage meldet Fehler {resp.status_code}.")
    try:
        data = resp.json()
    except Exception:
        raise RuntimeError("Unerwartete Antwort von EduPage.")
    if not isinstance(data, dict) or "timelineUserProps" not in data:
        raise RuntimeError("EduPage hat die Änderung nicht bestätigt.")
    return data.get("timelineUserProps") or {}


def _liker_display_name(raw) -> str:
    """Anzeigename aus `vlastnik_meno` (z. B. "Max Müller (Schüler)" -> "Max Müller")."""
    if not isinstance(raw, str) or not raw.strip():
        return "Unbekannt"
    raw = raw.strip()
    if raw.endswith(")") and " (" in raw:
        raw = raw.rsplit(" (", 1)[0].strip() or raw
    return raw or "Unbekannt"


def _fmt_like_date(raw) -> str:
    """Like-Zeitstempel lesbar machen ("2026-09-16 20:01:00" -> "16.09.2026 20:01")."""
    if not isinstance(raw, str) or not raw.strip():
        return ""
    try:
        return datetime.strptime(raw.strip(), "%Y-%m-%d %H:%M:%S").strftime("%d.%m.%Y %H:%M")
    except (ValueError, TypeError):
        return raw.strip()


def parse_likes_response(data, root_id=None) -> dict:
    """Reaktionen aus einer getRepliesItem-Antwort aufschlüsseln (Thread).

    Antwort-Shape (wie JS-Referenzlib): `{"status": "ok", "data": {"reakcie": [...]}}`.
    Wichtig: `pocet_reakcii` (die Zahl an der Karte) zählt ALLE Reaktionen –
    Likes, Antworten und Gesehen-Bestätigungen. Echte Likes sind Einträge
    mit gesetztem `data.like` (data kann auch JSON-String sein); alle anderen
    Nicht-Bestätigungen sind Antworten und werden mit Autor, Datum und Text
    als Thread zur Hauptnachricht gebündelt.

    Returns {"likes": [{name, date}], "replies": [{name, date, text}],
             "summary": {"total", "likes", "replies", "seen"}}.
    """
    items: list = []
    try:
        if isinstance(data, dict):
            inner = data.get("data")
            if isinstance(inner, dict):
                items = inner.get("reakcie") or inner.get("replies") or []
            elif isinstance(inner, list):
                items = inner
            else:
                items = data.get("reakcie") or data.get("items") or []
        elif isinstance(data, list):
            items = data
    except Exception:
        items = []
    if not isinstance(items, list):
        items = []

    likes: list = []
    replies: list = []
    n_seen = 0
    for e in items:
        try:
            if not isinstance(e, dict):
                continue
            if e.get("pomocny_zaznam"):
                continue
            if root_id is not None and str(e.get("timelineid")) == str(root_id):
                continue
            edata = e.get("data")
            if isinstance(edata, str):
                try:
                    edata = json.loads(edata)
                except Exception:
                    edata = {}
            if not isinstance(edata, dict):
                edata = {}
            if edata.get("like"):
                likes.append({
                    "name": _liker_display_name(e.get("vlastnik_meno")),
                    "date": _fmt_like_date(edata.get("like")),
                })
            elif e.get("typ") == "confirmation":
                # Gesehen-/Empfangsbestätigung, kein Like
                n_seen += 1
            else:
                replies.append({
                    "name": _liker_display_name(e.get("vlastnik_meno")),
                    "date": _fmt_like_date(e.get("cas_pridania")),
                    "text": _reply_text(e, edata),
                })
        except Exception:
            continue
    return {
        "likes": likes,
        "replies": replies,
        "summary": {
            "total": len(likes) + len(replies) + n_seen,
            "likes": len(likes),
            "replies": len(replies),
            "seen": n_seen,
        },
    }


def _strip_html(s) -> str:
    """HTML-Tags entfernen + Entities auflösen (für Antwort-Texte im Thread)."""
    if not isinstance(s, str):
        return ""
    s = re.sub(r"<[^>]+>", " ", s)
    return re.sub(r"\s+", " ", html.unescape(s)).strip()


def _reply_text(e, edata) -> str:
    """Antwort-Text aus allen bekannten Feldvarianten holen."""
    for v in (edata.get("messageContent"), edata.get("text"),
              edata.get("textReply"), e.get("text")):
        if isinstance(v, str) and v.strip():
            return _strip_html(v)
    return ""


def get_message_likes(edupage: Edupage, event_id) -> dict:
    """Thread einer Nachricht laden (`POST /timeline/?akcia=getRepliesItem`).

    Returns {"likes": [...], "replies": [...], "summary": {...}}
    (siehe parse_likes_response). Wirft RuntimeError bei Server-/Antwortfehlern.
    """
    url = f"https://{edupage.subdomain}.edupage.org/timeline/?akcia=getRepliesItem"
    resp = edupage.session.post(
        url,
        data=_encode_eqap({"groupid": str(event_id), "lastsync": ""}),
        headers={
            "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8",
            "X-Requested-With": "XMLHttpRequest",
        },
        timeout=30,
    )
    if resp.status_code != 200:
        raise RuntimeError(f"EduPage meldet Fehler {resp.status_code}.")
    try:
        data = resp.json()
    except Exception:
        raise RuntimeError("Unerwartete Antwort von EduPage.")
    return parse_likes_response(data, root_id=event_id)


# ------------------------------------------------------- Stundenplan

GERMAN_WEEKDAYS = ["Montag", "Dienstag", "Mittwoch", "Donnerstag",
                   "Freitag", "Samstag", "Sonntag"]


def lesson_to_dict(lesson) -> dict:
    """Lesson -> Template-Dict (Stundenplan)."""
    def _t(t):
        try:
            return t.strftime("%H:%M")
        except Exception:
            return str(t) if t is not None else "–"

    subject = getattr(lesson, "subject", None)
    subject_name = (getattr(subject, "name", "") or "").strip()
    curriculum = (getattr(lesson, "curriculum", "") or "").strip()
    title = subject_name or curriculum or "–"
    teachers = ", ".join(
        getattr(t, "name", str(t)) for t in (getattr(lesson, "teachers", None) or [])
    )
    rooms = ", ".join(
        getattr(r, "name", str(r)) for r in (getattr(lesson, "classrooms", None) or [])
    )
    period = getattr(lesson, "period", None)
    return {
        "period": str(period) if period is not None else "–",
        "time": f"{_t(getattr(lesson, 'start_time', None))}–{_t(getattr(lesson, 'end_time', None))}",
        "title": title,
        "is_lernzeit": "lernzeit" in title.lower(),
        "teachers": teachers,
        "rooms": rooms,
        "is_cancelled": bool(getattr(lesson, "is_cancelled", False)),
        "is_event": bool(getattr(lesson, "is_event", False)),
        "is_online": bool(getattr(lesson, "online_lesson_link", None)),
    }


def _is_lernzeit(d) -> bool:
    return "lernzeit" in (d.get("title") or "").lower()


def _period_num(d):
    try:
        return int(d.get("period"))
    except (TypeError, ValueError):
        return None


def _is_allday_event(d) -> bool:
    """Ganztägiges Event (z. B. Projekttag, Ferientag): kein Stundenbezug.

    Erkennbar am Event-Flag plus fehlender Stundennummer – normale Stunden
    haben immer eine Nummer, ganztägige Events liefert die API ohne
    `uniperiod` (Anzeige "–"). Solche Einträge würden in der Wochenmatrix
    eine eigene letzte Zeile ("–.") aufspannen, daher werden sie dort
    herausgefiltert statt als Stunde eingetragen.
    """
    return bool(d.get("is_event")) and _period_num(d) is None


def merge_lernzeit(items):
    """Verbindet aufeinanderfolgende Lernzeit-Stunden zu einem Block.

    Nur Einträge mit "Lernzeit" im Titel, die direkt hintereinander liegen
    (Stundennummern fortlaufend), werden vereint: Anzeige z. B. "1–2. Std."
    mit Zeitspanne erster Beginn bis letzter Schluss. Alle anderen Stunden
    (auch sonstige Doppelstunden) bleiben einzeln. Der Block merkt sich
    zusätzlich row_period (erste Stunde, für die Matrix-Platzierung) und
    rowspan (Anzahl verbundener Stunden, für die Wochenansicht).
    """
    out = []
    i = 0
    while i < len(items):
        cur = items[i]
        if _is_lernzeit(cur):
            group = [cur]
            j = i + 1
            while j < len(items) and _is_lernzeit(items[j]):
                pn_prev = _period_num(group[-1])
                pn_cur = _period_num(items[j])
                if pn_prev is not None and pn_cur is not None and pn_cur != pn_prev + 1:
                    break
                group.append(items[j])
                j += 1
            if len(group) > 1:
                first, last = group[0], group[-1]

                def _union(key):
                    seen = []
                    for g in group:
                        for part in (g.get(key) or "").split(","):
                            part = part.strip()
                            if part and part not in seen:
                                seen.append(part)
                    return ", ".join(seen)

                merged = dict(first)
                if first.get("period") not in (None, "–") and last.get("period") not in (None, "–"):
                    merged["period"] = f"{first['period']}–{last['period']}"
                merged["time"] = f"{first.get('time', '').split('–')[0]}–{last.get('time', '').split('–')[-1]}"
                merged["teachers"] = _union("teachers")
                merged["rooms"] = _union("rooms")
                merged["is_cancelled"] = all(g.get("is_cancelled") for g in group)
                merged["is_event"] = any(g.get("is_event") for g in group)
                merged["is_online"] = any(g.get("is_online") for g in group)
                merged["row_period"] = first.get("period")
                merged["rowspan"] = len(group)
                out.append(merged)
                i = j
                continue
        out.append(cur)
        i += 1
    for d in out:
        d.setdefault("row_period", d.get("period"))
        d.setdefault("rowspan", 1)
    return out


def lesson_start_index(lessons, now_t) -> int:
    """Startposition Stunden-Karussell: laufende Stunde, sonst nächste
    kommende (nicht entfallene), sonst letzte Stunde, sonst 0."""
    if not lessons:
        return 0
    for i, _d in enumerate(lessons):
        if _d.get("is_now"):
            return i
    for i, _d in enumerate(lessons):
        if _d.get("is_cancelled"):
            continue
        try:
            _start = datetime.strptime(
                _d.get("time", "").split("–")[0].strip(), "%H:%M").time()
        except Exception:
            continue
        if now_t < _start:
            return i
    return len(lessons) - 1


@app.route("/stundenplan")
@login_required
def stundenplan():
    username = session["username"]
    subdomain = session["subdomain"]

    day_str = request.args.get("day", date.today().isoformat())
    try:
        day = date.fromisoformat(day_str)
    except ValueError:
        day = date.today()
    day_str = day.isoformat()
    view = request.args.get("view", "day")
    if view not in ("day", "week"):
        view = "day"
    force_refresh = request.args.get("refresh", "0") == "1"
    prev_day = (day - timedelta(days=1)).isoformat()
    next_day = (day + timedelta(days=1)).isoformat()
    day_label = f"{GERMAN_WEEKDAYS[day.weekday()]} {day.strftime('%d.%m.%Y')}"

    try:
        edupage, username, subdomain = get_logged_in_edupage()
    except (RuntimeError, SessionExpired):
        flash("Sitzung erfordert erneut 2FA. Bitte erneut anmelden.", "error")
        return redirect(url_for("logout"))
    except BadCredentialsException:
        flash("Gespeicherte Zugangsdaten sind ungültig. Bitte erneut anmelden.", "error")
        return redirect(url_for("logout"))
    except CaptchaException:
        flash("EduFlow verlangt ein Captcha. Bitte einmal im Browser anmelden, dann erneut versuchen.", "error")
        return redirect(url_for("logout"))
    except Exception as e:
        return render_template(
            "timetable.html", username=username, subdomain=subdomain,
            day=day_str, prev_day=prev_day, next_day=next_day,
            today_str=date.today().isoformat(), day_label=day_label,
            view=view, lessons=[], week=[], periods=[], matrix={}, covered=set(), period_rows={}, gap_rows=[], blank_labels=set(),
            error=f"Stundenplan konnte nicht geladen werden: {e}",
            cache_info="",
        )

    if view == "week":
        # Wochenliste Mo–Fr, ausgehend vom Montag der gewählten Woche.
        monday = day - timedelta(days=day.weekday())
        week = []
        n_cached_days = 0
        try:
            for i in range(5):
                d = monday + timedelta(days=i)
                day_lessons, _m = get_timetable_day_cached(
                    edupage, subdomain, username, d, force_refresh)
                if _m.get("from_cache"):
                    n_cached_days += 1
                day_lessons = merge_lernzeit(day_lessons)
                # Ganztägige Events nicht als Stunden-Zeile eintragen
                # (würden sonst eine letzte "–."-Zeile in der Matrix bilden).
                day_lessons = [l for l in day_lessons if not _is_allday_event(l)]
                week.append({
                    "date": d.isoformat(),
                    "label": f"{GERMAN_WEEKDAYS[d.weekday()]} {d.strftime('%d.%m.%Y')}",
                    "day_name": GERMAN_WEEKDAYS[d.weekday()],
                    "day_date": d.strftime("%d.%m."),
                    "is_today": d == date.today(),
                    "lessons": day_lessons,
                })
            if n_cached_days == 5:
                week_cache_info = "Woche aus Cache (0 API-Requests)"
            elif n_cached_days:
                week_cache_info = f"Woche teils aus Cache ({n_cached_days}/5 Tage, {5 - n_cached_days} neu geladen)"
            else:
                week_cache_info = "Woche frisch geladen (5 API-Requests)"
        except NotLoggedInException:
            flash("Nicht angemeldet. Bitte erneut anmelden.", "error")
            return redirect(url_for("logout"))
        except Exception as e:
            return render_template(
                "timetable.html", username=username, subdomain=subdomain,
                day=day_str, prev_day=prev_day, next_day=next_day,
                today_str=date.today().isoformat(), day_label=day_label,
                view=view, lessons=[], week=[], periods=[], matrix={}, covered=set(), period_rows={}, gap_rows=[], blank_labels=set(),
                error=f"Stundenplan konnte nicht geladen werden: {e}",
                cache_info="",
            )
        # Matrix: Zeilen = Stunden (1., 2., …), Spalten = Tage (Mo–Fr).
        # row_period platziert verbundene Lernzeit-Blöcke in ihrer ersten Zeile.
        def _period_key(p):
            return int(p) if p.isdigit() else 999

        matrix = {
            d["date"]: {l["row_period"]: l for l in d["lessons"]} for d in week
        }
        # Zellen, die von einem mehrzeiligen Lernzeit-Block überdeckt werden,
        # werden nicht gerendert (sonst verrutscht das Grid nach rechts).
        covered = set()
        for d in week:
            for l in d["lessons"]:
                rs = l.get("rowspan", 1) or 1
                rp = l.get("row_period")
                if rs > 1 and rp is not None and str(rp).isdigit():
                    for k in range(1, rs):
                        covered.add((d["date"], str(int(rp) + k)))
        # Überdeckte Folgezeilen brauchen trotzdem eine eigene Zeile,
        # damit der Block nicht in die nächste Stunde hineinragt.
        periods = sorted(
            {l["row_period"] for d in week for l in d["lessons"]}
            | {p for (_, p) in covered},
            key=_period_key,
        )
        # Zeilennummern: Kopf = 1, danach fortlaufend (keine Lücken,
        # keine ausgelassenen Zahlen).
        period_rows = {p: i + 2 for i, p in enumerate(periods)}
        gap_rows = []
        blank_labels = set()
        return render_template(
            "timetable.html", username=username, subdomain=subdomain,
            day=monday.isoformat(),
            prev_day=(monday - timedelta(days=7)).isoformat(),
            next_day=(monday + timedelta(days=7)).isoformat(),
            today_str=date.today().isoformat(), day_label=day_label,
            week_label=f"Woche {monday.strftime('%d.%m.')} – {(monday + timedelta(days=4)).strftime('%d.%m.%Y')}",
            view=view, lessons=[], week=week, periods=periods,
            matrix=matrix, covered=covered, period_rows=period_rows,
            gap_rows=gap_rows, blank_labels=blank_labels, error=None,
            cache_info=week_cache_info,
        )

    try:
        day_lessons_raw, day_cache = get_timetable_day_cached(
            edupage, subdomain, username, day, force_refresh)
        day_cache_info = day_cache.get("cache_info", "")
    except NotLoggedInException:
        flash("Nicht angemeldet. Bitte erneut anmelden.", "error")
        return redirect(url_for("logout"))
    except Exception as e:
        return render_template(
            "timetable.html", username=username, subdomain=subdomain,
            day=day_str, prev_day=prev_day, next_day=next_day,
            today_str=date.today().isoformat(), day_label=day_label,
            view=view, lessons=[], week=[], periods=[], matrix={}, covered=set(), period_rows={}, gap_rows=[], blank_labels=set(),
            error=f"Stundenplan konnte nicht geladen werden: {e}",
            cache_info="",
        )

    lessons = merge_lernzeit(day_lessons_raw)
    return render_template(
        "timetable.html", username=username, subdomain=subdomain,
        day=day_str, prev_day=prev_day, next_day=next_day,
        today_str=date.today().isoformat(), day_label=day_label,
        view=view, lessons=lessons, week=[], error=None,
        cache_info=day_cache_info,
    )


@app.route("/datei/<int:event_id>/<int:idx>")
@login_required
def datei(event_id: int, idx: int):
    """Dateianhang einer Nachricht direkt herunterladen.

    Der Download läuft als Proxy über die eingeloggte EduPage-Session,
    daher funktionieren auch geschützte Datei-Links ohne separaten Login.
    """
    username = session["username"]
    subdomain = session["subdomain"]

    try:
        edupage, username, subdomain = get_logged_in_edupage()
    except RuntimeError:
        flash("Sitzung erfordert erneut 2FA. Bitte erneut anmelden.", "error")
        return redirect(url_for("logout"))
    except SessionExpired:
        flash("Anmeldung abgelaufen. Bitte erneut anmelden.", "error")
        return redirect(url_for("logout"))
    except (BadCredentialsException, CaptchaException):
        flash("Anmeldung ungültig. Bitte erneut anmelden.", "error")
        return redirect(url_for("logout"))
    except Exception as e:
        return f"Download fehlgeschlagen: {e}", 502

    # Anhang anhand der Event-ID aus dem lokalen Cache auflösen.
    uhash = apicache.user_hash(subdomain, username)
    record = None
    try:
        cached = apicache.load_timeline(uhash)
        for r in (cached.get("events", []) if cached else []) or []:
            if str(r.get("id")) == str(event_id):
                record = r
                break
    except Exception:
        record = None
    if record is None:
        try:
            events, _, _, _ = get_timeline_cached(
                edupage, subdomain, username, EARLIEST_DEFAULT)
            for e in events:
                if str(getattr(e, "event_id", None)) == str(event_id):
                    record = apicache.event_to_record(e)
                    break
        except Exception as e:
            return f"Download fehlgeschlagen: {e}", 502
    if record is None:
        return "Nachricht nicht gefunden.", 404

    atts = extract_attachments(record.get("additional_data") or {})
    if idx < 0 or idx >= len(atts):
        return "Datei nicht gefunden.", 404

    raw_url = atts[idx]["url"]
    url = f"https://{subdomain}.edupage.org{raw_url}" if raw_url.startswith("/") else raw_url
    if not (urlparse(url).hostname or "").endswith(".edupage.org"):
        return "Ungültiger Download-Link.", 400

    try:
        upstream = edupage.session.get(url, stream=True, timeout=30)
    except Exception as e:
        return f"Download fehlgeschlagen: {e}", 502
    if upstream.status_code != 200:
        return f"EduPage meldet Fehler {upstream.status_code}.", 502

    filename = re.sub(r'["\r\n]', "", atts[idx]["name"] or "")[:120] or "datei"
    ctype = (upstream.headers.get("Content-Type", "application/octet-stream")
             .split(";")[0].strip() or "application/octet-stream")
    return Response(
        stream_with_context(upstream.iter_content(chunk_size=65536)),
        content_type=ctype,
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )


@app.route("/likes/<int:event_id>")
@login_required
def likes(event_id: int):
    """Liefert als JSON den Thread einer Nachricht.

    {"likes": [{name, date}], "replies": [{name, date, text}],
     "summary": {"total", "likes", "replies", "seen"}, "cached": bool}.
    Hinweis: Die Reaktions-Zahl an der Karte (pocet_reakcii) zählt ALLE
    Reaktionen (Likes + Antworten + Gesehen) – `summary` schlüsselt das auf.

    Threads liegen pro User im Datei-Cache (`likes_<hash>.json`, TTL
    `LIKES_TTL_S`); nur bei Miss/stalem Cache oder `?refresh=1` geht ein
    Request an EduPage.
    """
    try:
        edupage, username, subdomain = get_logged_in_edupage()
    except (RuntimeError, SessionExpired):
        return jsonify({"error": "Sitzung abgelaufen. Bitte erneut anmelden."}), 401
    except (BadCredentialsException, CaptchaException):
        return jsonify({"error": "Anmeldung ungültig. Bitte erneut anmelden."}), 401
    except Exception as e:
        return jsonify({"error": f"Anmeldung fehlgeschlagen: {e}"}), 502

    uhash = apicache.user_hash(subdomain, username)
    if request.args.get("refresh", "0") != "1":
        try:
            cached = apicache.load_likes(uhash, event_id)
            if cached is not None and apicache.is_fresh(
                    cached.get("saved_at"), apicache.LIKES_TTL_S):
                data = cached.get("data") or {}
                return jsonify({"likes": data.get("likes", []),
                                "replies": data.get("replies", []),
                                "summary": data.get("summary", {}),
                                "cached": True})
        except Exception:
            pass

    try:
        result = get_message_likes(edupage, event_id)
        try:
            apicache.save_likes(uhash, event_id, result)
        except Exception:
            pass
        return jsonify({"likes": result["likes"], "replies": result["replies"],
                        "summary": result["summary"], "cached": False})
    except Exception as e:
        return jsonify({"error": f"Likes konnten nicht geladen werden: {e}"}), 502


@app.route("/einstellungen", methods=["GET", "POST"])
@login_required
def einstellungen():
    """Einstellungsseite: Aussehen (lokal im Browser) + Allgemeines (Server)."""
    username = session["username"]
    subdomain = session["subdomain"]
    uhash = apicache.user_hash(subdomain, username)

    if request.method == "POST":
        try:
            apicache.save_settings(uhash, settings_from_form(request.form))
            flash("Einstellungen gespeichert.", "info")
        except Exception as e:
            flash(f"Einstellungen konnten nicht gespeichert werden: {e}", "error")
        return redirect(url_for("einstellungen"))

    return render_template(
        "settings.html", username=username, subdomain=subdomain,
        schema=SETTINGS_SCHEMA, values=user_settings(), error=None,
    )


@app.route("/cache-clear")
@login_required
def cache_clear():
    """Eigenen lokalen API-Cache löschen (Timeline + Stundenplan).

    Einstellungen (`settings_*.json`) bleiben bewusst erhalten.
    """
    from pathlib import Path
    uhash = apicache.user_hash(session.get("subdomain", ""), session.get("username", ""))
    n = 0
    try:
        for p in apicache.CACHE_DIR.glob(f"*_{uhash}*.json"):
            if p.name.startswith("settings_"):
                continue  # Einstellungen bleiben bei "Cache leeren" erhalten
            try:
                Path(p).unlink()
                n += 1
            except Exception:
                pass
        flash(f"Lokaler Cache gelöscht ({n} Dateien). Nächster Aufruf lädt frisch.", "info")
    except Exception as e:
        flash(f"Cache konnte nicht gelöscht werden: {e}", "error")
    back = request.referrer or url_for("dashboard")
    return redirect(back)


@app.route("/logout")
def logout():
    session.clear()
    return redirect(url_for("index"))


if __name__ == "__main__":
    # Standard-Port 8000 (Port 5000 meiden: macOS AirPlay-Empfänger antwortet
    # dort mit 403). Per PORT-Env-Var änderbar (z. B. PORT=8080).
    port = int(os.environ.get("PORT", "8000"))
    app.run(host="127.0.0.1", port=port, debug=True)
