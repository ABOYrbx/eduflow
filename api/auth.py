"""EduFlow API v1 – Authentifizierung (Paket A + P1-Härtung).

Routen (alle JSON, alle unter /api/v1):
- POST /auth/login – Anmelden mit Subdomain, Benutzername, Passwort und
  optionalem Gerätenamen. Antwortet mit Status ok plus Token, Ablauf,
  Subdomain und Benutzername – oder mit Status 2fa_required plus
  Zwischen-Token, wenn EduPage einen Zwei-Faktor-Code verlangt.
- POST /auth/2fa – Zwischen-Token und Code gegen ein vollwertiges Token
  tauschen.
- POST /auth/logout – genau das verwendete Token widerrufen (mit Schutz).
- POST /auth/refresh – Token rotieren (altes widerrufen, neues ausstellen).
- GET /me – Subdomain und Benutzername des Token-Inhabers (mit Schutz).
- GET /devices – eigene Tokens listen (ohne Secrets, mit Ablauf).
- DELETE /devices/<id> – eigenes Token per Datensatz-Hash widerrufen.

Token-Logik steht ausschließlich im Kernmodul (api.core); hier steht nur der
EduPage-Login-Ablauf (Wiederverwendung von do_login aus app.py, Lazy-Import
gegen Importzyklen) und die 2FA-Zwischenablage (Wiederverwendung von
PENDING_2FA aus app.py, markiert als API-Einträge, damit Web- und API-Abläufe
sich nicht vermischen). P1: Login-Rate-Limit (429 RATE_LIMITED) und
PENDING-TTL (10 Min., siehe app.pending_2fa_get).
"""

import os
import secrets
import time
from typing import Optional

from flask import g, request

from api import bp
from api.core import (
    api_error,
    create_token,
    list_user_tokens,
    revoke_token,
    revoke_token_by_hash,
    token_required,
)
from edupage_api.exceptions import BadCredentialsException, CaptchaException

# Login-Rate-Limit: max. N Versuche pro Fenster und IP (Brute-Force-Schutz).
# Per Env überstimmbar, Tests nutzen reset_login_rate_limit().
LOGIN_RATE_LIMIT_N = int(os.environ.get("EDUFLOW_LOGIN_LIMIT", "20") or 20)
LOGIN_RATE_LIMIT_WINDOW_S = int(
    os.environ.get("EDUFLOW_LOGIN_WINDOW", "600") or 600)
_LOGIN_ATTEMPTS: dict = {}


def _client_ip() -> str:
    """Client-IP fürs Rate-Limit (Proxy-Header nur falls gesetzt)."""
    try:
        fwd = (request.headers.get("X-Forwarded-For") or "").split(",")[0].strip()
        if fwd:
            return fwd[:64]
        return (request.remote_addr or "unknown")[:64]
    except Exception:
        return "unknown"


def _rate_limited(ip: str) -> bool:
    """True, wenn die IP im Fenster zu oft versucht hat (und jetzt zählt)."""
    try:
        now = time.time()
        hits = _LOGIN_ATTEMPTS.get(ip) or []
        hits = [t for t in hits if now - t < LOGIN_RATE_LIMIT_WINDOW_S]
        hits.append(now)
        _LOGIN_ATTEMPTS[ip] = hits[-LOGIN_RATE_LIMIT_N * 2:]
        return len(hits) > LOGIN_RATE_LIMIT_N
    except Exception:
        return False


def reset_login_rate_limit() -> None:
    """Rate-Limit-Speicher leeren (nur für Tests)."""
    try:
        _LOGIN_ATTEMPTS.clear()
    except Exception:
        pass


def _body() -> Optional[dict]:
    data = request.get_json(silent=True)
    return data if isinstance(data, dict) else None


def _bearer_token() -> str:
    auth = request.headers.get("Authorization", "")
    return auth[7:].strip() if auth[:7].lower() == "bearer " else ""


@bp.route("/auth/login", methods=["POST"])
def api_login():
    if _rate_limited(_client_ip()):
        return api_error("Zu viele Versuche. Bitte später erneut versuchen.",
                         "RATE_LIMITED", 429)
    data = _body()
    if data is None:
        return api_error("Ungültige Anfrage (JSON erwartet).",
                         "VALIDATION", 400)
    username = str(data.get("username") or "").strip()
    password = data.get("password") or ""
    if not isinstance(password, str):
        password = str(password)
    subdomain = str(data.get("subdomain") or "").strip()
    device = str(data.get("device") or "")[:80]
    if not username or not password:
        return api_error("Bitte Benutzername und Passwort angeben.",
                         "VALIDATION", 400)

    from datetime import datetime

    from app import PENDING_2FA, do_login, prune_pending_2fa
    try:
        prune_pending_2fa()
    except Exception:
        pass
    try:
        _edupage, two_factor, real_subdomain = do_login(
            username, password, subdomain)
    except BadCredentialsException:
        return api_error("Falscher Benutzername, Passwort oder Subdomain.",
                         "BAD_CREDENTIALS", 401)
    except CaptchaException:
        return api_error(
            "EduPage verlangt ein Captcha. "
            "Bitte einmal im Browser anmelden, dann erneut versuchen.",
            "CAPTCHA_REQUIRED", 403)
    except Exception as e:
        return api_error(f"Anmeldung fehlgeschlagen: {e}", "UPSTREAM", 502)

    if two_factor is not None:
        pending = secrets.token_hex(16)
        PENDING_2FA[pending] = {
            "edupage": _edupage,
            "two_factor": two_factor,
            "username": username,
            "subdomain": real_subdomain,
            "password": password,
            "device": device,
            "api": True,
            "created": datetime.now(),
        }
        return {"status": "2fa_required",
                "pending_token": pending,
                "message": "Zwei-Faktor-Code aus E-Mail oder App eingeben "
                           "und an /auth/2fa senden."}, 200

    created = create_token(real_subdomain, username, password, device=device)
    return {"status": "ok", "token": created["token"],
            "expires": created["expires"],
            "subdomain": real_subdomain, "username": username}, 200


@bp.route("/auth/2fa", methods=["POST"])
def api_2fa():
    if _rate_limited(_client_ip()):
        return api_error("Zu viele Versuche. Bitte später erneut versuchen.",
                         "RATE_LIMITED", 429)
    data = _body()
    if data is None:
        return api_error("Ungültige Anfrage (JSON erwartet).",
                         "VALIDATION", 400)
    pending_token = str(data.get("pending_token") or "").strip()
    code = str(data.get("code") or "").strip()
    if not pending_token or not code:
        return api_error("Bitte Zwischen-Token und Code angeben.",
                         "VALIDATION", 400)

    from app import PENDING_2FA, pending_2fa_get
    pending = pending_2fa_get(pending_token)
    if not isinstance(pending, dict) or not pending.get("api"):
        return api_error("Zwischenschritt abgelaufen. "
                         "Bitte erneut anmelden.", "PENDING_INVALID", 401)
    try:
        pending["two_factor"].finish_with_code(code)
    except Exception:
        return api_error("Der Code wurde nicht akzeptiert. "
                         "Bitte erneut versuchen.", "INVALID_CODE", 401)

    PENDING_2FA.pop(pending_token, None)
    created = create_token(pending.get("subdomain", ""),
                           pending.get("username", ""),
                           pending.get("password", ""),
                           device=pending.get("device", ""))
    return {"status": "ok", "token": created["token"],
            "expires": created["expires"],
            "subdomain": pending.get("subdomain", ""),
            "username": pending.get("username", "")}, 200


@bp.route("/auth/logout", methods=["POST"])
@token_required
def api_logout():
    revoke_token(_bearer_token())
    return {"status": "ok"}, 200


@bp.route("/auth/refresh", methods=["POST"])
@token_required
def api_refresh():
    """Token rotieren: neues Token, altes widerrufen (Sliding bleibt 30 Tage).

    Nimmt Subdomain/Benutzername/Passwort aus dem validierten Token
    (g.api_*), stellt ein neues mit gleichem Gerätenamen aus und
    widerruft danach das alte. Abgelaufene Tokens kommen hier nicht an
    (token_required lehnt sie vorher mit TOKEN_EXPIRED ab).
    """
    from api.core import verify_token

    old = _bearer_token()
    creds = verify_token(old)
    device = ""
    try:
        # Gerätenamen aus dem Datensatz übernehmen (falls vorhanden).
        import hashlib
        import json as _json

        from api.core import _TOKEN_PATH

        h = hashlib.sha256(old.encode("utf-8")).hexdigest()
        with open(_TOKEN_PATH, "r", encoding="utf-8") as f:
            data = _json.load(f)
        rec = (data.get("tokens") or {}).get(h) or {}
        device = str(rec.get("device") or "")[:80]
    except Exception:
        device = ""
    created = create_token(g.api_subdomain, g.api_username,
                           g.api_password, device=device)
    try:
        revoke_token(old)
    except Exception:
        pass
    _ = creds
    return {"status": "ok", "token": created["token"],
            "expires": created["expires"],
            "subdomain": g.api_subdomain,
            "username": g.api_username}, 200


@bp.route("/me", methods=["GET"])
@token_required
def api_me():
    return {"subdomain": g.api_subdomain,
            "username": g.api_username}, 200


@bp.route("/devices", methods=["GET"])
@token_required
def api_devices():
    """Eigene API-Tokens listen (keine Secrets, neueste zuerst)."""
    try:
        items = list_user_tokens(g.api_subdomain, g.api_username)
    except Exception as e:
        return api_error("Geräte konnten nicht geladen werden: {}".format(e),
                         "UPSTREAM", 502)
    return {"items": items, "total": len(items)}, 200


@bp.route("/devices/<token_hash>", methods=["DELETE"])
@token_required
def api_device_revoke(token_hash):
    """Eigenes Token per Datensatz-Hash widerrufen (Besitzschutz)."""
    token_hash = (token_hash or "").strip()
    if not token_hash:
        return api_error("Bitte Token-ID angeben.", "VALIDATION", 400)
    ok = revoke_token_by_hash(token_hash, g.api_subdomain, g.api_username)
    if not ok:
        return api_error("Token nicht gefunden.", "NOT_FOUND", 404)
    return {"status": "ok"}, 200
