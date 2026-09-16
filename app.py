"""EduFlow Dashboard (Nachrichten + Hausaufgaben).

Simple Flask web dashboard:
- input EduFlow login (subdomain, username, password)
- view all timeline messages from as far back as possible
  (uses Edupage.get_notification_history with an early `date_from`).
- view all Hausaufgaben (timeline EventType.HOMEWORK + optional Tests)

Run:
    pip install -r requirements.txt
    python app.py
Then open http://127.0.0.1:5000
"""

import json
import os
import secrets
from datetime import date, datetime, timedelta
from functools import wraps

from flask import (
    Flask,
    flash,
    redirect,
    render_template,
    request,
    session,
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

app = Flask(__name__)
# Signed cookie session key. Override with env var in production.
app.secret_key = os.environ.get("FLASK_SECRET_KEY", secrets.token_hex(32))

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


def event_to_dict(ev) -> dict:
    timestamp = ev.timestamp
    if isinstance(timestamp, datetime):
        ts_str = timestamp.strftime("%Y-%m-%d %H:%M")
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

    return {
        "id": ev.event_id,
        "timestamp": ts_str,
        "timestamp_iso": ts_iso,
        "sort_key": ts_iso,
        "author": format_person(ev.author),
        "recipient": format_person(ev.recipient),
        "type": type_value,
        "text": text,
        "is_starred": bool(getattr(ev, "is_starred", False)),
        "is_done": bool(getattr(ev, "is_done", False)),
        "reaction_count": getattr(ev, "reaction_count", 0) or 0,
        "extra": extra_json,
    }


def login_required(view):
    @wraps(view)
    def wrapped(*args, **kwargs):
        if "username" not in session or "subdomain" not in session:
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
        return text[:maxlen]
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

# Deutsche Labels für Timeline-Typen (Dropdown im Nachrichten-Filter).
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
    "oexam": "mündliche Prüfung",
    "pexam": "Projektprüfung",
    "rexam": "Wiederholungsprüfung",
    "testing": "Testung",
    "testpridelenie": "Prüfungszuweisung",
    "testvysledok": "Prüfungsergebnis",
    "znamka": "Note",
    "znamkydoc": "Notendokument",
}


def type_label(t: str) -> str:
    return TYPE_LABELS.get(t, t)


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
    password = session["password"]
    edupage, two_factor, real_subdomain = do_login(username, password, subdomain)
    if two_factor is not None:
        raise RuntimeError("2FA_REQUIRED")
    session["subdomain"] = real_subdomain
    return edupage, username, real_subdomain


# ---------------------------------------------------------------- routes

@app.route("/")
def index():
    if "username" in session:
        return redirect(url_for("dashboard"))
    return render_template("login.html")


@app.route("/login", methods=["POST"])
def login():
    username = request.form.get("username", "").strip()
    password = request.form.get("password", "")
    subdomain = request.form.get("subdomain", "").strip()

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
            "password": password,
        }
        session["pending_2fa"] = token
        return redirect(url_for("twofa"))

    session["username"] = username
    session["password"] = password  # needed to re-login on each dashboard load; local tool only
    session["subdomain"] = real_subdomain
    return redirect(url_for("dashboard"))


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
        session["username"] = pending["username"]
        session["password"] = pending["password"]
        session["subdomain"] = pending["subdomain"]
        PENDING_2FA.pop(token, None)
        session.pop("pending_2fa", None)
        return redirect(url_for("dashboard"))

    return render_template("2fa.html")


@app.route("/dashboard")
@login_required
def dashboard():
    username = session["username"]
    subdomain = session["subdomain"]
    password = session["password"]

    since_str = request.args.get("since", EARLIEST_DEFAULT.isoformat())
    try:
        since = date.fromisoformat(since_str)
    except ValueError:
        since = EARLIEST_DEFAULT
        since_str = since.isoformat()

    only_messages = request.args.get("only_messages", "1") == "1"
    selected_type = (request.args.get("type") or "").strip()
    force_refresh = request.args.get("refresh", "0") == "1"

    # Re-login on every load (EduPage sessions expire; keeps things stateless)
    try:
        edupage, two_factor, real_subdomain = do_login(username, password, subdomain)
        if two_factor is not None:
            flash("Sitzung erfordert erneut 2FA. Bitte erneut anmelden.", "error")
            return redirect(url_for("logout"))
        session["subdomain"] = real_subdomain
        subdomain = real_subdomain
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
            only_messages=only_messages,
            messages=[],
            total=0,
            error=f"Nachrichten konnten nicht geladen werden: {e}",
            type_options=[],
            selected_type="",
            first_source=None,
            last_source=None,
            oldest_label="",
            n_requests=0,
            cache_info="",
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
            only_messages=only_messages,
            messages=[],
            total=0,
            error=f"Nachrichten konnten nicht geladen werden: {e}",
            type_options=[],
            selected_type="",
            first_source=None,
            last_source=None,
            oldest_label="",
            n_requests=0,
            cache_info="",
        )

    # Älteste Nachricht finden – ihr Datum ist der Verlauf-Start
    # (ungefiltert, d.h. über alle Timeline-Typen hinweg).
    oldest_ev, newest_ev = oldest_and_newest(events)
    first_source = fmt_day(oldest_ev.timestamp) if oldest_ev else None
    last_source = fmt_day(newest_ev.timestamp) if newest_ev else None
    oldest_label = short_label(oldest_ev) if oldest_ev else ""
    if oldest_ev is not None:
        since_str = oldest_ev.timestamp.date().isoformat()

    items = [event_to_dict(e) for e in events]
    # newest first
    items.sort(key=lambda m: m["sort_key"], reverse=True)

    if only_messages:
        # "sprava" are direct messages; keep news/polls too as they are message-like.
        # Everything else (grades, timetable, ...) is hidden in this mode.
        message_types = {"sprava", "news", "anketa", "chat", "genotif"}
        items = [m for m in items if m["type"] in message_types]

    # Typ-Optionen mit deutscher Bezeichnung + Anzahl für den Filter.
    # Ungültige Auswahl aus der URL zurücksetzen, sonst würde alles ausgeblendet.
    counts: dict = {}
    for m in items:
        counts[m["type"]] = counts.get(m["type"], 0) + 1
    if selected_type not in counts:
        selected_type = ""
    type_options = sorted(
        ((t, type_label(t), counts[t]) for t in counts),
        key=lambda o: o[1].lower(),
    )

    return render_template(
        "dashboard.html",
        username=username,
        subdomain=subdomain,
        since=since_str,
        only_messages=only_messages,
        messages=items,
        total=len(items),
        error=None,
        type_options=type_options,
        selected_type=selected_type,
        first_source=first_source,
        last_source=last_source,
        oldest_label=oldest_label,
        n_requests=n_requests,
        cache_info=cache_info,
    )


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

    status_filter = request.args.get("status", "alle")  # alle|offen|überfällig|erledigt
    include_tests = request.args.get("include_tests", "0") == "1"
    force_refresh = request.args.get("refresh", "0") == "1"

    try:
        edupage, username, subdomain = get_logged_in_edupage()
    except RuntimeError:
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
            items=[], total=0, n_offen=0, n_ueber=0, n_erledigt=0,
            error=f"Konnte Hausaufgaben nicht laden: {e}",
            first_source=None, last_source=None, oldest_label="",
            n_requests=0, cache_info="",
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
            items=[], total=0, n_offen=0, n_ueber=0, n_erledigt=0,
            error=f"Konnte Hausaufgaben nicht laden: {e}",
            first_source=None, last_source=None, oldest_label="",
            n_requests=0, cache_info="",
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

    n_offen = sum(1 for i in items if i["status"] in ("offen", "heute fällig"))
    n_ueber = sum(1 for i in items if i["status"] == "überfällig")
    n_erledigt = sum(1 for i in items if i["status"] == "erledigt")

    if status_filter == "offen":
        items = [i for i in items if i["status"] in ("offen", "heute fällig", "ohne Datum")]
    elif status_filter == "überfällig":
        items = [i for i in items if i["status"] == "überfällig"]
    elif status_filter == "erledigt":
        items = [i for i in items if i["status"] == "erledigt"]

    # Sortierung: Überfällige zuerst, dann Offene (nach Fälligkeit,
    # ohne Datum hinten), Erledigte ans Ende.
    def _rank(i):
        if i["status"] == "überfällig":
            return 0
        if i["status"] == "erledigt":
            return 2
        return 1

    items.sort(key=lambda i: (_rank(i), i["due"] == "", i["due"], i["assigned_iso"]))

    return render_template(
        "homework.html", username=username, subdomain=subdomain,
        since=since_str, status=status_filter, include_tests=include_tests,
        items=items, total=len(items), n_offen=n_offen, n_ueber=n_ueber,
        n_erledigt=n_erledigt, error=None,
        first_source=first_source, last_source=last_source,
        oldest_label=oldest_label, n_requests=n_requests,
        cache_info=cache_info,
    )


def _event_type_str(ev) -> str:
    try:
        return ev.event_type.value if ev.event_type else ""
    except Exception:
        return str(getattr(ev, "event_type", ""))


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
    except RuntimeError:
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


@app.route("/cache-clear")
@login_required
def cache_clear():
    """Eigenen lokalen API-Cache löschen (Timeline + Stundenplan)."""
    from pathlib import Path
    uhash = apicache.user_hash(session.get("subdomain", ""), session.get("username", ""))
    n = 0
    try:
        for p in apicache.CACHE_DIR.glob(f"*_{uhash}*.json"):
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
    app.run(host="127.0.0.1", port=5000, debug=True)
