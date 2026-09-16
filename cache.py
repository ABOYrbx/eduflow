"""Lokaler Cache für EduPage-API-Antworten (Timeline + Stundenplan).

Ziel: Ladezeiten reduzieren, indem API-Antworten lokal als JSON gespeichert
und nur dann neu geladen/aktualisiert werden, wenn nötig:

- Timeline (`get_notification_history`): eine Datei pro User. Beim ersten
  Aufruf voller Fetch ab `since`, danach gilt der Cache `TIMELINE_TTL_S`
  als frisch (0 API-Requests). Ist er älter, wird nur ein kurzes Fenster
  (`TIMELINE_WINDOW_DAYS`, default 60 Tage) neu geladen und per Event-ID
  gemergt: neue Events kommen dazu, veränderte (Text, done, starred, ...)
  werden aktualisiert, unveränderte bleiben unangetastet.
- Stundenplan (`get_my_timetable`): eine Datei pro User+Datum. Vergangene
  Tage ändern sich praktisch nicht (lange TTL), heute kurz, Zukunft mittel.

Alles best-effort: kaputter/fehlender Cache -> frisch laden, Schreibfehler
werden ignoriert, Lesefehler fallen auf frischen Fetch zurück. Bei
Netzfehlern mit vorhandenem Cache wird der alte Stand als Fallback served.
"""

import hashlib
import json
import os
import tempfile
from datetime import date, datetime, timedelta
from pathlib import Path
from types import SimpleNamespace
from typing import Any, Dict, List, Optional, Tuple

CACHE_DIR = Path(__file__).resolve().parent / ".cache"

# Timeline frisch für 15 Minuten -> 0 API-Requests beim Blättern/Suchen.
TIMELINE_TTL_S = int(os.environ.get("EDUFLOW_TIMELINE_TTL", "900"))
# Inkrementelles Fenster bei stale Cache: nur diese letzten Tage neu laden.
TIMELINE_WINDOW_DAYS = int(os.environ.get("EDUFLOW_TIMELINE_WINDOW_DAYS", "60"))

# Stundenplan-TTLs (Sekunden). Umweltvariablen zum Tunen.
TT_TTL_PAST_S = int(os.environ.get("EDUFLOW_TT_TTL_PAST", str(7 * 24 * 3600)))
TT_TTL_TODAY_S = int(os.environ.get("EDUFLOW_TT_TTL_TODAY", "600"))
TT_TTL_FUTURE_S = int(os.environ.get("EDUFLOW_TT_TTL_FUTURE", "3600"))

_DATETIME_FMT = "%Y-%m-%d %H:%M:%S"


# ------------------------------------------------------------ Basis-Helpers

def user_hash(subdomain: str, username: str) -> str:
    raw = f"{(subdomain or '').strip().lower()}:{(username or '').strip().lower()}"
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()[:16]


def _ensure_dir() -> None:
    try:
        CACHE_DIR.mkdir(parents=True, exist_ok=True)
    except Exception:
        pass


def _timeline_path(uhash: str) -> Path:
    return CACHE_DIR / f"timeline_{uhash}.json"


def _timetable_path(uhash: str, day: date) -> Path:
    return CACHE_DIR / f"timetable_{uhash}_{day.isoformat()}.json"


def _atomic_write_json(path: Path, payload: Dict[str, Any]) -> None:
    _ensure_dir()
    fd, tmp = tempfile.mkstemp(prefix=path.name + ".", dir=str(path.parent))
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(payload, f, ensure_ascii=False, indent=1)
        os.replace(tmp, path)
    except Exception:
        try:
            os.unlink(tmp)
        except Exception:
            pass


def _read_json(path: Path) -> Optional[Dict[str, Any]]:
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
        return data if isinstance(data, dict) else None
    except Exception:
        return None


def _parse_dt(value: Any) -> Optional[datetime]:
    if isinstance(value, datetime):
        return value
    if not value or not isinstance(value, str):
        return None
    for fmt in (_DATETIME_FMT, "%Y-%m-%dT%H:%M:%S", "%Y-%m-%dT%H:%M:%S.%f", "%Y-%m-%d"):
        try:
            return datetime.strptime(value.strip(), fmt)
        except ValueError:
            continue
    try:
        return datetime.fromisoformat(value)
    except Exception:
        return None


def _person_to_str(p: Any) -> str:
    if p is None:
        return "–"
    if isinstance(p, str):
        return p
    name = getattr(p, "name", None)
    if isinstance(name, str) and name.strip():
        return name
    try:
        return str(p)
    except Exception:
        return "–"


def _etype_to_str(et: Any) -> str:
    if et is None:
        return "unknown"
    v = getattr(et, "value", et)
    return str(v) if v else "unknown"


# ------------------------------------------------- Timeline: Record-Format

def event_to_record(ev: Any) -> Dict[str, Any]:
    """TimelineEvent -> JSON-serialisierbares Dict (normalisiert)."""
    ts = getattr(ev, "timestamp", None)
    ts_str = ts.strftime(_DATETIME_FMT) if isinstance(ts, datetime) else str(ts or "")
    done_at = getattr(ev, "done_at", None)
    created_at = getattr(ev, "created_at", None)
    ad = getattr(ev, "additional_data", {})
    if not isinstance(ad, dict):
        ad = {"_raw": str(ad) if ad else ""}
    try:
        json.dumps(ad, ensure_ascii=False)
    except Exception:
        ad = {"_raw": str(ad)}
    return {
        "id": getattr(ev, "event_id", None),
        "timestamp": ts_str,
        "text": getattr(ev, "text", "") or "",
        "author": _person_to_str(getattr(ev, "author", None)),
        "recipient": _person_to_str(getattr(ev, "recipient", None)),
        "type": _etype_to_str(getattr(ev, "event_type", None)),
        "additional_data": ad,
        "is_starred": bool(getattr(ev, "is_starred", False)),
        "is_done": bool(getattr(ev, "is_done", False)),
        "done_at": done_at.strftime(_DATETIME_FMT) if isinstance(done_at, datetime) else "",
        "reaction_count": int(getattr(ev, "reaction_count", 0) or 0),
        "created_at": created_at.strftime(_DATETIME_FMT) if isinstance(created_at, datetime) else "",
        "is_removed": bool(getattr(ev, "is_removed", False)),
    }


def record_to_event(rec: Dict[str, Any]) -> SimpleNamespace:
    """Cache-Record -> Objekt mit gleicher Attribut-Schnittstelle wie TimelineEvent.

    Damit funktionieren die bestehenden `event_to_dict` / `homework_to_dict`
    unverändert weiter (sie greifen auf .event_id, .timestamp, .text,
    .author/.recipient (str), .event_type.value, .additional_data, .is_done,
    .done_at, .is_starred, .reaction_count zu).
    """
    ts = _parse_dt(rec.get("timestamp"))
    done_at = _parse_dt(rec.get("done_at")) if rec.get("done_at") else None
    created_at = _parse_dt(rec.get("created_at")) if rec.get("created_at") else None
    return SimpleNamespace(
        event_id=rec.get("id"),
        timestamp=ts if ts is not None else rec.get("timestamp", ""),
        text=rec.get("text", "") or "",
        author=rec.get("author", "–") or "–",
        recipient=rec.get("recipient", "–") or "–",
        event_type=SimpleNamespace(value=rec.get("type", "unknown")),
        additional_data=rec.get("additional_data", {}) or {},
        is_starred=bool(rec.get("is_starred", False)),
        is_done=bool(rec.get("is_done", False)),
        done_at=done_at,
        reaction_count=int(rec.get("reaction_count", 0) or 0),
        created_at=created_at,
        is_removed=bool(rec.get("is_removed", False)),
    )


def _record_key(rec: Dict[str, Any]) -> Optional[str]:
    rid = rec.get("id")
    return None if rid is None else str(rid)


def merge_records(
    old: List[Dict[str, Any]], new: List[Dict[str, Any]]
) -> Tuple[List[Dict[str, Any]], int, int]:
    """Merged frisch geladene Records in den alten Stand (keyed by ID).

    Returns (merged, n_added, n_updated). Unveränderte bleiben unangetastet
    (gleiche Dict-Referenz-Inhalte), neue kommen dazu, geänderte werden
    ersetzt. Gelöschte IDs aus dem Fenster werden NICHT entfernt, weil das
    Fenster nur einen Ausschnitt abdeckt (alte Events außerhalb bleiben).
    """
    by_id: Dict[str, Dict[str, Any]] = {}
    order: List[str] = []
    for r in old:
        k = _record_key(r)
        if k is None:
            continue
        if k not in by_id:
            order.append(k)
        by_id[k] = r
    added = 0
    updated = 0
    for r in new:
        k = _record_key(r)
        if k is None:
            continue
        prev = by_id.get(k)
        if prev is None:
            by_id[k] = r
            order.append(k)
            added += 1
        elif prev != r:
            by_id[k] = r
            updated += 1
    merged = [by_id[k] for k in order]
    return merged, added, updated


def load_timeline(uhash: str) -> Optional[Dict[str, Any]]:
    data = _read_json(_timeline_path(uhash))
    if not data or not isinstance(data.get("events"), list):
        return None
    return data


def save_timeline(uhash: str, earliest_iso: str, records: List[Dict[str, Any]]) -> None:
    try:
        _atomic_write_json(_timeline_path(uhash), {
            "version": 1,
            "saved_at": datetime.now().strftime(_DATETIME_FMT),
            "earliest": earliest_iso,
            "events": records,
        })
    except Exception:
        pass


def set_record_done(uhash: str, event_id, done: bool) -> bool:
    """Done-Status eines Timeline-Records lokal nachpflegen (ohne Neu-Fetch).

    Wird nach erfolgreichem `homeworkFlag`-Request aufgerufen, damit die
    Anzeige sofort stimmt. Returns True, wenn der Record gefunden wurde.
    """
    try:
        data = load_timeline(uhash)
        if not data:
            return False
        changed = False
        now_str = datetime.now().strftime(_DATETIME_FMT)
        for r in data.get("events", []) or []:
            if str(r.get("id")) != str(event_id):
                continue
            r["is_done"] = bool(done)
            r["done_at"] = now_str if done else ""
            changed = True
            break
        if not changed:
            return False
        _atomic_write_json(_timeline_path(uhash), {
            "version": 1,
            "saved_at": datetime.now().strftime(_DATETIME_FMT),
            "earliest": data.get("earliest", ""),
            "events": data.get("events", []),
        })
        return True
    except Exception:
        return False


def cache_age_s(saved_at_str: Any) -> Optional[int]:
    dt = _parse_dt(saved_at_str)
    if dt is None:
        return None
    try:
        return max(0, int((datetime.now() - dt).total_seconds()))
    except Exception:
        return None


def format_age(age_s: Optional[int]) -> str:
    if age_s is None:
        return "unbekannt"
    if age_s < 60:
        return f"{age_s} Sek."
    mins = age_s // 60
    if mins < 60:
        return f"{mins} Min."
    hours = mins // 60
    if hours < 24:
        return f"{hours} Std. {mins % 60} Min."
    return f"{hours // 24} Tage"


# ------------------------------------------------- Stundenplan-Cache

def timetable_ttl_for(day: date) -> int:
    today = date.today()
    if day < today:
        return TT_TTL_PAST_S
    if day == today:
        return TT_TTL_TODAY_S
    return TT_TTL_FUTURE_S


def load_timetable(uhash: str, day: date) -> Optional[Dict[str, Any]]:
    data = _read_json(_timetable_path(uhash, day))
    if not data or not isinstance(data.get("lessons"), list):
        return None
    return data


def save_timetable(uhash: str, day: date, lessons: List[Dict[str, Any]]) -> None:
    try:
        _atomic_write_json(_timetable_path(uhash, day), {
            "version": 1,
            "saved_at": datetime.now().strftime(_DATETIME_FMT),
            "day": day.isoformat(),
            "lessons": lessons,
        })
    except Exception:
        pass


def is_fresh(saved_at_str: Any, ttl_s: int) -> bool:
    age = cache_age_s(saved_at_str)
    return age is not None and age < ttl_s


# ------------------------------------------------- Gelesen-Status
# Die EduPage-API kennt kein "ungelesen"-Flag, daher wird lokal pro User
# gespeichert, welche Timeline-Event-IDs bereits gesehen wurden.
# Alles best-effort wie der Rest des Caches. `cache-clear` in app.py
# löscht diese Datei automatisch mit (Muster `*_<uhash>.json`).

def _seen_path(uhash: str) -> Path:
    return CACHE_DIR / f"seen_{uhash}.json"


def load_seen(uhash: str) -> set:
    """IDs bereits gesehener Timeline-Events (Strings)."""
    data = _read_json(_seen_path(uhash))
    if not data or not isinstance(data.get("ids"), list):
        return set()
    try:
        return {str(i) for i in data.get("ids", [])}
    except Exception:
        return set()


def save_seen(uhash: str, ids: set) -> None:
    try:
        _atomic_write_json(_seen_path(uhash), {
            "version": 1,
            "saved_at": datetime.now().strftime(_DATETIME_FMT),
            "ids": sorted(str(i) for i in ids),
        })
    except Exception:
        pass


def mark_seen(uhash: str, ids) -> int:
    """Fügt IDs zum Gelesen-Status hinzu. Returns Anzahl neu markierter."""
    try:
        seen = load_seen(uhash)
        new = {str(i) for i in (ids or []) if i is not None}
        added = new - seen
        if added:
            save_seen(uhash, seen | new)
        return len(added)
    except Exception:
        return 0


# ------------------------------------------------- Einstellungen
# Allgemeine Einstellungen pro User (Startseite, Filter-Defaults, Limits).
# Gleiches JSON-Format und gleiche Best-effort-Semantik wie oben.
# WICHTIG: `settings_*.json` wird von "Cache leeren" bewusst NICHT gelöscht
# (siehe cache_clear in app.py) – Einstellungen sollen erhalten bleiben.

def _settings_path(uhash: str) -> Path:
    return CACHE_DIR / f"settings_{uhash}.json"


def load_settings(uhash: str) -> dict:
    """Gespeicherte Einstellungen (rohes Dict, ggf. leer/unvollständig)."""
    try:
        data = _read_json(_settings_path(uhash))
        if isinstance(data, dict) and isinstance(data.get("values"), dict):
            return dict(data["values"])
    except Exception:
        pass
    return {}


def save_settings(uhash: str, values: dict) -> None:
    try:
        _atomic_write_json(_settings_path(uhash), {
            "version": 1,
            "saved_at": datetime.now().strftime(_DATETIME_FMT),
            "values": {str(k): v for k, v in (values or {}).items()},
        })
    except Exception:
        pass


# ------------------------------------------------- Ausgeblendete Aufgaben
# Schüler können aufgegebene Hausaufgaben auf EduPage nicht löschen
# (nur das done-Flag ist Schüler-Zustand). "Löschen" ist daher ein rein
# lokaler Zustand pro User: ausgeblendete Event-IDs erscheinen weder auf
# der Hausaufgaben-Seite noch in der Übersicht. Gleiches Format und
# gleiche Best-effort-Semantik wie der Gelesen-Status oben.

def _hidden_path(uhash: str) -> Path:
    return CACHE_DIR / f"hidden_{uhash}.json"


def load_hidden(uhash: str) -> set:
    """IDs lokal ausgeblendeter Timeline-Events (Strings)."""
    data = _read_json(_hidden_path(uhash))
    if not data or not isinstance(data.get("ids"), list):
        return set()
    try:
        return {str(i) for i in data.get("ids", [])}
    except Exception:
        return set()


def _save_hidden(uhash: str, ids: set) -> None:
    try:
        _atomic_write_json(_hidden_path(uhash), {
            "version": 1,
            "saved_at": datetime.now().strftime(_DATETIME_FMT),
            "ids": sorted(str(i) for i in ids),
        })
    except Exception:
        pass


def hide_ids(uhash: str, ids) -> int:
    """Blendet IDs aus. Returns Anzahl neu ausgeblendeter."""
    try:
        hidden = load_hidden(uhash)
        new = {str(i) for i in (ids or []) if i is not None}
        added = new - hidden
        if added:
            _save_hidden(uhash, hidden | new)
        return len(added)
    except Exception:
        return 0


def unhide_ids(uhash: str, ids) -> int:
    """Blendet IDs wieder ein. Returns Anzahl wieder eingeblendeter."""
    try:
        hidden = load_hidden(uhash)
        gone = {str(i) for i in (ids or []) if i is not None} & hidden
        if gone:
            _save_hidden(uhash, hidden - gone)
        return len(gone)
    except Exception:
        return 0
