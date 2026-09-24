"""EduFlow API v1 – Noten (Paket E).

Route (JSON, mit Schutz):
- GET /grades – Notenliste mit Paginierung (limit, offset) und
  Aktualisierungs­schalter (refresh=1 lädt frisch statt aus dem Cache).

Verhalten wie die Web-Notenseite: Anzeigeobjekte aus dem bestehenden
Noten-Bauer in Cache-Reihenfolge (keine neuen Filter, keine neue
Sortierung), derselbe Noten-Cache mit derselben Laufzeit. Ist der Cache
frisch und kein Refresh verlangt, antwortet die Route ohne EduPage-Login
(offline-fähig); sonst Re-Login mit den Token-Zugangsdaten.

Fehlerbild (Muster für alle Ressourcen-Pakete): VALIDATION (400) bei
ungültiger Paginierung, BAD_CREDENTIALS (401) bei ungültig gewordenen
Zugangsdaten, CAPTCHA_REQUIRED (403) bei Captcha-Zwang, EDUPAGE_2FA (401)
wenn EduPage erneut 2FA verlangt (dann neu über /auth/login anmelden),
UPSTREAM (502) für alle anderen EduPage-Fehler.
"""

from flask import g, request

import cache as apicache
from api import bp
from api.core import api_error, get_pagination, page, token_required
from edupage_api.exceptions import BadCredentialsException, CaptchaException


def _relogin():
    """EduPage-Re-Login mit Token-Zugangsdaten. Returns (edupage, subdomain).

    Wirft api_error-Tupel-verträgliche Fehler nicht selbst, sondern gibt
    (Fehlerantwort, None) bzw. (None, (edupage, subdomain)) zurück –
    Aufrufer geben die Fehlerantwort direkt weiter.
    """
    from app import do_login
    from api.core import edupage_login_error
    try:
        edupage, two_factor, real_subdomain = do_login(
            g.api_username, g.api_password, g.api_subdomain)
    except (BadCredentialsException, CaptchaException, Exception) as e:
        message, code, status = edupage_login_error(e)
        return api_error(message, code, status), None
    if two_factor is not None:
        return api_error("Sitzung erfordert erneut 2FA. "
                         "Bitte erneut über /auth/login anmelden.",
                         "EDUPAGE_2FA", 401), None
    return None, (edupage, real_subdomain)


@bp.route("/grades", methods=["GET"])
@token_required
def api_grades():
    try:
        limit, offset = get_pagination(request.args)
    except ValueError as e:
        return api_error(str(e), "VALIDATION", 400)
    force = request.args.get("refresh", "0") == "1"
    uhash = apicache.user_hash(g.api_subdomain, g.api_username)

    if not force:
        cached = apicache.load_grades(uhash)
        if cached is not None and apicache.is_fresh(
                cached.get("saved_at"), apicache.GRADES_TTL_S):
            items = cached.get("grades", []) or []
            out = page(items, limit, offset)
            age = apicache.cache_age_s(cached.get("saved_at")) or 0
            out["cache_info"] = (
                f"aus Cache ({apicache.format_age(age)} alt)")
            return out, 200

    err, login = _relogin()
    if err is not None:
        return err
    edupage, real_subdomain = login

    from app import get_grades_cached
    try:
        items, meta = get_grades_cached(edupage, real_subdomain,
                                        g.api_username, force)
    except Exception as e:
        return api_error(f"Noten konnten nicht geladen werden: {e}",
                         "UPSTREAM", 502)
    out = page(items, limit, offset)
    out["cache_info"] = meta.get("cache_info", "")
    return out, 200
