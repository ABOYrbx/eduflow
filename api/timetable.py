"""EduFlow API v1 – Stundenplan (Paket D).

Routen (alle JSON, alle unter /api/v1, alle mit Token-Schutz):
- GET /timetable/day – Tagesansicht. Query: `day` (YYYY-MM-DD, Standard:
  heute), `refresh=1` lädt frisch statt aus dem Cache. Antwort: Tag,
  deutsche Tagesbezeichnung, Vor-/Folgetag, Stunden als Anzeigeobjekte
  aus dem bestehenden Stunden-Bauer inklusive zusammengefasster
  Lernzeit-Blöcke (wie die Web-Seite) plus Cache-Hinweis.
- GET /timetable/week – Wochenansicht. Query: `day` (ein Datum innerhalb
  der Woche, Standard: heute), `refresh=1` wie oben. Antwort: angefragter
  Tag, Montag, Wochenbezeichnung und Montag bis Freitag mit denselben
  Tagesobjekten wie die Tagesansicht (ganztägige Events herausgefiltert,
  wie die Web-Seite) plus Cache-Hinweis.

Es wird ausschließlich wiederverwendet: Token-Schutz und Fehler-Bauer aus
dem Kernmodul (api.core), Login, Stundenplan-Cache, Stunden-Bauer,
Lernzeit-Zusammenfassung und Wochentagsnamen aus app.py (Lazy-Import gegen
Importzyklen), Datei-Cache aus cache.py. Keine eigene Login-, Cache- oder
Bau-Logik.

Fehlercodes: TOKEN_INVALID / TOKEN_EXPIRED (Schutz), VALIDATION (falsches
Datum), BAD_CREDENTIALS (gespeicherte Zugangsdaten ungültig),
CAPTCHA_REQUIRED (EduPage verlangt Captcha), EDUPAGE_2FA (Sitzung
verlangt erneut 2FA – bitte neu über /auth/login anmelden),
UPSTREAM (EduPage-Fehler).
"""

from datetime import date, timedelta
from typing import Dict, List, Optional, Tuple

from flask import g, request

from api import bp
from api.core import api_error, token_required
from edupage_api.exceptions import (
    BadCredentialsException,
    CaptchaException,
    NotLoggedInException,
)


def _parse_day(value: Optional[str]) -> date:
    """Tagesdatum aus Query lesen (Standard: heute). Wirft ValueError."""
    if not value:
        return date.today()
    try:
        return date.fromisoformat(value.strip())
    except (ValueError, TypeError, AttributeError):
        raise ValueError(
            "Das Datum muss im Format JJJJ-MM-TT angegeben werden.")


def _login():
    """EduPage-Re-Login aus den Token-Zugangsdaten.

    Returns (Fehlerantwort, None) bei Problemen oder
    (None, (edupage, username, subdomain)) bei Erfolg.
    Fehlercodes aus dem kanonischen Vokabular (api.core).
    """
    from app import SessionExpired, do_login
    from api.core import edupage_login_error
    try:
        edupage, two_factor, real_subdomain = do_login(
            g.api_username, g.api_password, g.api_subdomain)
    except (RuntimeError, SessionExpired):
        return (api_error("Sitzung erfordert erneut 2FA. "
                           "Bitte erneut über /auth/login anmelden.",
                           "EDUPAGE_2FA", 401), None)
    except (BadCredentialsException, CaptchaException, Exception) as e:
        message, code, status = edupage_login_error(e)
        return (api_error(message, code, status), None)
    if two_factor is not None:
        return (api_error("Sitzung erfordert erneut 2FA. "
                           "Bitte erneut über /auth/login anmelden.",
                           "EDUPAGE_2FA", 401), None)
    return None, (edupage, g.api_username, real_subdomain)


def _load_day(edupage, subdomain: str, username: str, day: date,
              force: bool) -> Tuple[Optional[dict], Optional[list]]:
    """Ein Tag über den bestehenden Stundenplan-Cache laden.

    Returns (Fehlerantwort, None) oder
    (None, (Rohstunden, Cache-Hinweis, aus_cache)).
    Die Rohstunden sind Anzeigeobjekte aus dem bestehenden Stunden-Bauer;
    Aufrufer fassen Lernzeit-Blöcke genau einmal zusammen (wie im Web).
    """
    from app import get_timetable_day_cached
    try:
        raw, meta = get_timetable_day_cached(
            edupage, subdomain, username, day, force)
    except NotLoggedInException:
        return (api_error("EduPage meldet: nicht angemeldet.",
                          "UPSTREAM", 502), None)
    except Exception as e:
        return (api_error(f"Stundenplan konnte nicht geladen werden: {e}",
                          "UPSTREAM", 502), None)
    return None, (raw, meta.get("cache_info", ""),
                  bool(meta.get("from_cache", False)))


@bp.route("/timetable/day", methods=["GET"])
@token_required
def api_timetable_day():
    from app import GERMAN_WEEKDAYS, merge_lernzeit
    try:
        day = _parse_day(request.args.get("day", ""))
    except ValueError as e:
        return api_error(str(e), "VALIDATION", 400)
    force = request.args.get("refresh", "0") == "1"

    err, login = _login()
    if err is not None:
        return err
    edupage, username, subdomain = login

    err, loaded = _load_day(edupage, subdomain, username, day, force)
    if err is not None:
        return err
    raw, cache_info, _from_cache = loaded
    lessons = merge_lernzeit(raw)

    return {
        "day": day.isoformat(),
        "day_label": f"{GERMAN_WEEKDAYS[day.weekday()]} "
                     f"{day.strftime('%d.%m.%Y')}",
        "prev_day": (day - timedelta(days=1)).isoformat(),
        "next_day": (day + timedelta(days=1)).isoformat(),
        "today": date.today().isoformat(),
        "lessons": lessons,
        "cache_info": cache_info,
    }, 200


@bp.route("/timetable/week", methods=["GET"])
@token_required
def api_timetable_week():
    from app import _is_allday_event, merge_lernzeit
    try:
        day = _parse_day(request.args.get("day", ""))
    except ValueError as e:
        return api_error(str(e), "VALIDATION", 400)
    force = request.args.get("refresh", "0") == "1"

    err, login = _login()
    if err is not None:
        return err
    edupage, username, subdomain = login

    monday = day - timedelta(days=day.weekday())
    days: List[Dict] = []
    n_cached = 0
    for i in range(5):
        current = monday + timedelta(days=i)
        err, loaded = _load_day(edupage, subdomain, username,
                                current, force)
        if err is not None:
            return err
        raw, _info, from_cache = loaded
        if from_cache:
            n_cached += 1
        merged = merge_lernzeit(raw)
        # Ganztägige Events nicht als Stunden eintragen (wie im Web).
        merged = [entry for entry in merged
                  if not _is_allday_event(entry)]
        days.append({
            "date": current.isoformat(),
            "day_name": _day_name(current),
            "day_date": current.strftime("%d.%m."),
            "is_today": current == date.today(),
            "lessons": merged,
        })
    # Hinweis wie im Web: Anteil der Tage, die aus dem Cache kamen.
    if n_cached == 5:
        cache_info = "Woche aus Cache (0 API-Requests)"
    elif n_cached:
        cache_info = (f"Woche teils aus Cache ({n_cached}/5 Tage, "
                      f"{5 - n_cached} neu geladen)")
    else:
        cache_info = "Woche frisch geladen (5 API-Requests)"

    return {
        "day": day.isoformat(),
        "monday": monday.isoformat(),
        "week_label": f"Woche {monday.strftime('%d.%m.')} – "
                      f"{(monday + timedelta(days=4)).strftime('%d.%m.%Y')}",
        "days": days,
        "cache_info": cache_info,
    }, 200


def _day_name(day: date) -> str:
    from app import GERMAN_WEEKDAYS
    return GERMAN_WEEKDAYS[day.weekday()]
