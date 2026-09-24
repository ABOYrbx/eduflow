"""EduFlow API v1 – Hausaufgaben (Paket C).

Routen (alle JSON, alle unter /api/v1, Schutz via Bearer-Token):
- GET /homework – Liste mit Zeitraum, Statusfilter, Test-Einbeziehung,
  Suche und Paginierung. Antwortobjekte aus dem bestehenden
  Hausaufgaben-Bauer, Sortierung wie im Web (überfällig zuerst,
  Papierkorb ans Ende). Zähler für offen, überfällig, erledigt und
  Papierkorb werden mitgeliefert.
- POST /homework/<id>/done – als erledigt/offen markieren (JSON {done}).
- POST /homework/<id>/trash – in den Papierkorb legen/zurückholen
  (JSON {hide}, Alias {trash}). Zurückholen markiert gleichzeitig als
  offen, wie im Web.

Wiederverwendet ausschließlich das Kernmodul (api.core), den bestehenden
Datei-Cache plus lokale Zustände (Papierkorb, done-Flag) und die
bestehenden Helper aus app.py (Lazy-Import gegen Importzyklen). Kein
App-Import auf Modulebene.
"""

from datetime import date
from typing import Optional

import cache as apicache
from flask import g, request

from api import bp
from api.core import api_error, get_pagination, page, token_required
from edupage_api.exceptions import (
    BadCredentialsException,
    CaptchaException,
    NotLoggedInException,
)

_STATUS_VALUES = ("alle", "offen", "überfällig", "erledigt", "papierkorb")


def _body() -> Optional[dict]:
    data = request.get_json(silent=True)
    return data if isinstance(data, dict) else None


def _parse_bool(value, default: bool = False) -> bool:
    """Flag aus JSON/Query tolerant lesen (bool, 1/0, true/false, on/off)."""
    if value is None:
        return default
    if isinstance(value, bool):
        return value
    if isinstance(value, int) and not isinstance(value, bool):
        if value in (0, 1):
            return bool(value)
        raise ValueError("Ungültiger Wahrheitswert (0 oder 1 erwartet).")
    s = str(value).strip().lower()
    if s in ("1", "true", "on", "yes", "ja"):
        return True
    if s in ("0", "false", "off", "no", "nein"):
        return False
    raise ValueError("Ungültiger Wahrheitswert (true/false erwartet).")


def _edupage_or_error():
    """EduPage-Re-Login aus dem Token. Returns (edupage, subdomain, err).

    Fehlercodes aus dem kanonischen Vokabular (api.core).
    """
    from app import do_login
    from api.core import edupage_login_error

    try:
        edupage, two_factor, real_subdomain = do_login(
            g.api_username, g.api_password, g.api_subdomain)
    except (BadCredentialsException, CaptchaException, Exception) as e:
        message, code, status = edupage_login_error(e)
        return None, "", api_error(message, code, status)
    if two_factor is not None:
        return None, "", api_error(
            "Anmeldung erfordert Zwei-Faktor-Code. "
            "Bitte über /auth/login erneut anmelden.",
            "EDUPAGE_2FA", 401)
    return edupage, real_subdomain, None


def _parse_since(raw: Optional[str]) -> date:
    from app import EARLIEST_DEFAULT

    if raw is None or str(raw).strip() == "":
        return EARLIEST_DEFAULT
    try:
        return date.fromisoformat(str(raw).strip())
    except ValueError:
        raise ValueError("Ungültiges Datum (YYYY-MM-DD erwartet).")


def _build_view(edupage, subdomain: str, username: str, since: date,
                status: str, include_tests: bool, q: str,
                force_refresh: bool) -> "tuple":
    """Hausaufgaben-Liste exakt wie im Web aufbauen.

    Returns (gefilterte_sortierte_items, counts, cache_info).
    counts: {offen, ueberfaellig, erledigt, papierkorb} wie die Web-Zähler
    (offen zählt offen + heute fällig, ohne Papierkorb).
    """
    from app import (
        HOMEWORK_TYPES,
        EXAM_TYPES,
        _event_type_str,
        get_timeline_cached,
        homework_to_dict,
        mark_hidden,
    )

    events, _n_req, _effective, meta = get_timeline_cached(
        edupage, subdomain, username, since, force_refresh)
    cache_info = ""
    try:
        cache_info = str((meta or {}).get("cache_info", ""))
    except Exception:
        cache_info = ""

    wanted = set(HOMEWORK_TYPES)
    if include_tests:
        wanted |= set(EXAM_TYPES)
    items = [homework_to_dict(e) for e in events
             if _event_type_str(e) in wanted]

    uhash = apicache.user_hash(subdomain, username)
    try:
        hidden = apicache.load_hidden(uhash)
    except Exception:
        hidden = set()
    visible, hidden_items = mark_hidden(items, hidden)
    counts = {
        "offen": sum(1 for i in visible
                     if i.get("status") in ("offen", "heute fällig")),
        "ueberfaellig": sum(1 for i in visible
                            if i.get("status") == "überfällig"),
        "erledigt": sum(1 for i in visible
                        if i.get("status") == "erledigt"),
        "papierkorb": len(hidden_items),
    }

    if status == "papierkorb":
        items = hidden_items
    elif status == "alle":
        items = visible + hidden_items
    else:
        items = visible

    if status == "offen":
        items = [i for i in items
                 if i.get("status") in ("offen", "heute fällig", "ohne Datum")]
    elif status == "überfällig":
        items = [i for i in items if i.get("status") == "überfällig"]
    elif status == "erledigt":
        items = [i for i in items if i.get("status") == "erledigt"]

    from app import homework_rank

    items.sort(key=lambda i: (homework_rank(i), i.get("due") == "",
                              i.get("due") or "", i.get("assigned_iso") or ""))

    needle = (q or "").strip().lower()
    if needle:
        def _hay(i) -> str:
            return " ".join(str(i.get(k) or "") for k in
                            ("title", "subject", "author",
                             "description", "type_label")).lower()

        items = [i for i in items if needle in _hay(i)]

    return items, counts, cache_info


def _dict_by_id(uhash: str, event_id) -> Optional[dict]:
    """Aktuelles Hausaufgaben-Dict aus dem lokalen Cache (oder None)."""
    from app import homework_to_dict

    try:
        cached = apicache.load_timeline(uhash)
        records = (cached.get("events", []) if cached else []) or []
    except Exception:
        return None
    target = None
    for r in records:
        try:
            if str(r.get("id")) == str(event_id):
                target = r
                break
        except Exception:
            continue
    if target is None:
        return None
    try:
        d = homework_to_dict(apicache.record_to_event(target))
    except Exception:
        return None
    try:
        hidden = apicache.load_hidden(uhash)
        d["is_hidden"] = str(d.get("id")) in {
            str(x) for x in hidden} if hidden else False
    except Exception:
        d["is_hidden"] = False
    return d


@bp.route("/homework", methods=["GET"])
@token_required
def api_homework_list():
    """Hausaufgabenliste (Filter wie Web, plus Paginierung und Zähler)."""
    args = request.args
    try:
        limit, offset = get_pagination(args)
    except ValueError as e:
        return api_error(str(e), "VALIDATION", 400)
    try:
        since = _parse_since(args.get("since"))
    except ValueError as e:
        return api_error(str(e), "VALIDATION", 400)
    status = (args.get("status", "alle") or "alle").strip()
    if status not in _STATUS_VALUES:
        return api_error(
            "Ungültiger Status (alle, offen, überfällig, "
            "erledigt oder papierkorb erwartet).", "VALIDATION", 400)
    try:
        include_tests = _parse_bool(args.get("include_tests", "0"), False)
        force_refresh = _parse_bool(args.get("refresh", "0"), False)
    except ValueError as e:
        return api_error(str(e), "VALIDATION", 400)
    q = (args.get("q") or "")[:200]

    edupage, subdomain, err = _edupage_or_error()
    if err is not None:
        return err

    try:
        items, counts, cache_info = _build_view(
            edupage, subdomain, g.api_username, since, status,
            include_tests, q, force_refresh)
    except NotLoggedInException:
        return api_error("Sitzung abgelaufen. Bitte erneut anmelden.",
                         "UPSTREAM", 502)
    except Exception as e:
        return api_error(
            "Hausaufgaben konnten nicht geladen werden: {}".format(e),
            "UPSTREAM", 502)

    result = page(items, limit, offset)
    result["counts"] = counts
    result["cache_info"] = cache_info
    return result, 200


@bp.route("/homework/<event_id>/done", methods=["POST"])
@token_required
def api_homework_done(event_id):
    """Hausaufgabe als erledigt/offen markieren (JSON {done})."""
    data = _body()
    if data is None:
        return api_error("Ungültige Anfrage (JSON erwartet).",
                         "VALIDATION", 400)
    try:
        done = _parse_bool(data.get("done", True), True)
    except ValueError as e:
        return api_error(str(e), "VALIDATION", 400)

    edupage, subdomain, err = _edupage_or_error()
    if err is not None:
        return err
    uhash = apicache.user_hash(subdomain, g.api_username)

    from app import EARLIEST_DEFAULT, set_homework_done

    try:
        items, _counts, _info = _build_view(
            edupage, subdomain, g.api_username, EARLIEST_DEFAULT,
            "alle", True, "", False)
    except NotLoggedInException:
        return api_error("Sitzung abgelaufen. Bitte erneut anmelden.",
                         "UPSTREAM", 502)
    except Exception as e:
        return api_error(
            "Hausaufgaben konnten nicht geladen werden: {}".format(e),
            "UPSTREAM", 502)
    if not any(str(i.get("id")) == str(event_id) for i in items):
        return api_error("Hausaufgabe nicht gefunden.", "NOT_FOUND", 404)

    try:
        set_homework_done(edupage, event_id, done)
    except Exception as e:
        return api_error(
            "Status konnte nicht geändert werden: {}".format(e),
            "UPSTREAM", 502)
    try:
        apicache.set_record_done(uhash, event_id, done)
    except Exception:
        pass

    updated = _dict_by_id(uhash, event_id)
    if updated is None:
        return api_error("Hausaufgabe nicht gefunden.", "NOT_FOUND", 404)
    return updated, 200


@bp.route("/homework/<event_id>/trash", methods=["POST"])
@token_required
def api_homework_trash(event_id):
    """Papierkorb: hineinlegen/zurückholen (JSON {hide}, Alias {trash}).

    Zurückholen markiert gleichzeitig als offen, wie im Web.
    """
    data = _body()
    if data is None:
        return api_error("Ungültige Anfrage (JSON erwartet).",
                         "VALIDATION", 400)
    raw = data.get("hide", None)
    if raw is None:
        raw = data.get("trash", None)
    try:
        hide = _parse_bool(raw, True)
    except ValueError as e:
        return api_error(str(e), "VALIDATION", 400)

    edupage, subdomain, err = _edupage_or_error()
    if err is not None:
        return err
    uhash = apicache.user_hash(subdomain, g.api_username)

    from app import EARLIEST_DEFAULT, HOMEWORK_TYPES, set_homework_done

    try:
        items, _counts, _info = _build_view(
            edupage, subdomain, g.api_username, EARLIEST_DEFAULT,
            "alle", True, "", False)
    except NotLoggedInException:
        return api_error("Sitzung abgelaufen. Bitte erneut anmelden.",
                         "UPSTREAM", 502)
    except Exception as e:
        return api_error(
            "Hausaufgaben konnten nicht geladen werden: {}".format(e),
            "UPSTREAM", 502)
    current = None
    for i in items:
        if str(i.get("id")) == str(event_id):
            current = i
            break
    if current is None:
        return api_error("Hausaufgabe nicht gefunden.", "NOT_FOUND", 404)

    if hide:
        try:
            apicache.hide_ids(uhash, [event_id])
        except Exception:
            pass
    else:
        rec_type = str(current.get("type") or "")
        if rec_type in set(HOMEWORK_TYPES):
            try:
                set_homework_done(edupage, event_id, False)
            except Exception as e:
                return api_error(
                    "Aufgabe konnte nicht als offen markiert werden: "
                    "{}".format(e), "UPSTREAM", 502)
            try:
                apicache.set_record_done(uhash, event_id, False)
            except Exception:
                pass
        try:
            apicache.unhide_ids(uhash, [event_id])
        except Exception:
            pass

    updated = _dict_by_id(uhash, event_id)
    if updated is None:
        return api_error("Hausaufgabe nicht gefunden.", "NOT_FOUND", 404)
    return updated, 200
