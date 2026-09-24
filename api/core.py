"""EduFlow API v1 – Kernmodul (Paket 0, Schnittstelle eingefroren).

Enthält alles, was alle API-Pakete gemeinsam nutzen: opake Bearer-Token
(Erstellen, Prüfen, Widerrufen), den Auth-Schutz für Routen, den zentralen
Fehler-Bauer und Paginierungs-Helfer.

Absichtlich ohne Import aus app.py (keine Importzyklen): Der Fernet-Schlüssel
wird aus derselben Quelle gelesen (Env `EDUFLOW_KEY` oder Datei `.eduflow.key`);
das Passwort liegt wie beim Web-Login nur verschlüsselt im Token-Datensatz.
Token-Datensätze liegen in `.cache/api_tokens.json` (Hash statt Klartext,
atomar geschrieben, Abgelaufene werden bei jedem Schreiben entsorgt).
"""

import hashlib
import json
import os
import secrets
import tempfile
from datetime import datetime, timedelta
from functools import wraps
from pathlib import Path
from typing import Optional

from cryptography.fernet import Fernet
from flask import g, jsonify, request

BASE_DIR = Path(__file__).resolve().parent.parent
CACHE_DIR = BASE_DIR / ".cache"
_TOKEN_PATH = CACHE_DIR / "api_tokens.json"

# Standard-Ablaufzeit für Token (Tage), per Env überstimmbar.
TOKEN_TTL_DAYS = int(os.environ.get("EDUFLOW_API_TOKEN_DAYS", "30"))

_DATETIME_FMT = "%Y-%m-%d %H:%M:%S"


# ------------------------------------------------------------ Schlüssel

def _fernet() -> Fernet:
    """Fernet mit demselben Schlüssel wie das Web-Login (Env oder Datei)."""
    raw = os.environ.get("EDUFLOW_KEY")
    if raw:
        return Fernet(raw.encode())
    key = (BASE_DIR / ".eduflow.key").read_bytes().strip()
    return Fernet(key)


# ------------------------------------------------------------ Token-Ablage

def _read_store() -> dict:
    try:
        with open(_TOKEN_PATH, "r", encoding="utf-8") as f:
            data = json.load(f)
        if isinstance(data, dict) and isinstance(data.get("tokens"), dict):
            return data["tokens"]
    except Exception:
        pass
    return {}


def _write_store(tokens: dict) -> None:
    try:
        CACHE_DIR.mkdir(parents=True, exist_ok=True)
    except Exception:
        pass
    now = datetime.now()
    pruned = {}
    for h, rec in tokens.items():
        try:
            if isinstance(rec, dict) and datetime.strptime(
                    rec.get("expires", ""), _DATETIME_FMT) > now:
                pruned[h] = rec
        except (ValueError, TypeError):
            continue
    fd, tmp = tempfile.mkstemp(prefix=_TOKEN_PATH.name + ".",
                                dir=str(CACHE_DIR))
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump({"version": 1, "tokens": pruned}, f,
                      ensure_ascii=False, indent=1)
        os.replace(tmp, _TOKEN_PATH)
    except Exception:
        try:
            os.unlink(tmp)
        except Exception:
            pass


def _hash(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


# ------------------------------------------------------------ Token-API

def create_token(subdomain: str, username: str, password: str,
                 device: str = "", days: int = TOKEN_TTL_DAYS) -> dict:
    """Neues Token anlegen. Returns {token, expires} (Klartext nur hier)."""
    token = secrets.token_urlsafe(32)
    now = datetime.now()
    tokens = _read_store()
    tokens[_hash(token)] = {
        "subdomain": (subdomain or "").strip(),
        "username": (username or "").strip(),
        "pwd_enc": _fernet().encrypt(password.encode()).decode(),
        "created": now.strftime(_DATETIME_FMT),
        "expires": (now + timedelta(days=max(0, days))).strftime(_DATETIME_FMT),
        "device": str(device or "")[:80],
    }
    _write_store(tokens)
    return {"token": token, "expires": tokens[_hash(token)]["expires"]}


def verify_token(token: str) -> Optional[dict]:
    """Token prüfen. Returns {subdomain, username, password, ...} oder None.

    Das Passwort wird dabei entschlüsselt (für das zustandslose
    EduPage-Re-Login wie im Web). Ungültige oder beschädigte Datensätze
    geben None zurück; Abgelaufene werden beim nächsten Schreiben entsorgt.
    """
    if not token:
        return None
    rec = _read_store().get(_hash(token))
    if not isinstance(rec, dict):
        return None
    try:
        if datetime.strptime(rec.get("expires", ""),
                             _DATETIME_FMT) <= datetime.now():
            return None
        password = _fernet().decrypt(rec["pwd_enc"].encode()).decode()
    except Exception:
        return None
    return {"subdomain": rec.get("subdomain", ""),
            "username": rec.get("username", ""),
            "password": password,
            "device": rec.get("device", ""),
            "expires": rec.get("expires", "")}


def token_expired(token: str) -> bool:
    """True, wenn das Token bekannt, aber abgelaufen ist."""
    if not token:
        return False
    rec = _read_store().get(_hash(token))
    if not isinstance(rec, dict):
        return False
    try:
        return datetime.strptime(rec.get("expires", ""),
                                 _DATETIME_FMT) <= datetime.now()
    except (ValueError, TypeError):
        return False


def revoke_token(token: str) -> bool:
    """Genau dieses Token widerrufen. Returns True bei Treffer."""
    if not token:
        return False
    tokens = _read_store()
    if _hash(token) not in tokens:
        return False
    del tokens[_hash(token)]
    _write_store(tokens)
    return True


def list_user_tokens(subdomain: str, username: str) -> list:
    """Eigene Token-Datensätze für die Web-Anzeige (ohne Secrets).

    Returns [{id, short, device, created, expires}] – `id` ist der
    Datensatz-Hash (zum gezielten Widerrufen), nie der Klartext-Token.
    Abgelaufene werden übersprungen (sie räumt der nächste Schreibzugriff
    weg); Sortierung: neueste zuerst.
    """
    sub = (subdomain or "").strip().lower()
    user = (username or "").strip().lower()
    out = []
    try:
        tokens = _read_store()
    except Exception:
        return []
    for h, rec in tokens.items():
        try:
            if not isinstance(rec, dict):
                continue
            if datetime.strptime(rec.get("expires", ""),
                                 _DATETIME_FMT) <= datetime.now():
                continue
            if (str(rec.get("subdomain", "")).strip().lower() != sub
                    or str(rec.get("username", "")).strip().lower() != user):
                continue
            out.append({
                "id": h,
                "short": "…{}".format(h[-6:]),
                "device": str(rec.get("device", "") or ""),
                "created": str(rec.get("created", "")),
                "expires": str(rec.get("expires", "")),
            })
        except Exception:
            continue
    out.sort(key=lambda r: r["created"], reverse=True)
    return out


def revoke_token_by_hash(token_hash: str, subdomain: str,
                         username: str) -> bool:
    """Token-Datensatz per Hash widerrufen, nur bei eigenem Treffer.

    Der Hash allein genügt nicht: Subdomain/Benutzername müssen zum
    Datensatz passen, sonst wird nichts gelöscht. Returns True bei Treffer.
    """
    if not token_hash:
        return False
    sub = (subdomain or "").strip().lower()
    user = (username or "").strip().lower()
    tokens = _read_store()
    rec = tokens.get(token_hash)
    if not isinstance(rec, dict):
        return False
    try:
        if (str(rec.get("subdomain", "")).strip().lower() != sub
                or str(rec.get("username", "")).strip().lower() != user):
            return False
    except Exception:
        return False
    del tokens[token_hash]
    _write_store(tokens)
    return True


# ------------------------------------------------------------ Routen-Schutz

def token_required(view):
    """Auth-Schutz für API-Routen (Bearer-Token im Authorization-Header).

    Bei Erfolg stehen die Zugangsdaten unter `g.api_subdomain`,
    `g.api_username`, `g.api_password` bereit. Sonst Fehler mit Code
    TOKEN_INVALID (fehlend/unbekannt) oder TOKEN_EXPIRED (abgelaufen).
    """
    @wraps(view)
    def wrapped(*args, **kwargs):
        auth = request.headers.get("Authorization", "")
        token = auth[7:] if auth[:7].lower() == "bearer " else ""
        creds = verify_token(token.strip())
        if creds is None:
            if token_expired(token.strip()):
                return api_error("Token ist abgelaufen. Bitte erneut anmelden.",
                                 "TOKEN_EXPIRED", 401)
            return api_error("Ungültiges oder fehlendes Token.",
                             "TOKEN_INVALID", 401)
        g.api_subdomain = creds["subdomain"]
        g.api_username = creds["username"]
        g.api_password = creds["password"]
        return view(*args, **kwargs)

    return wrapped


# ------------------------------------------------------------ Fehler
#
# Kanonisches Fehler-Vokabular (P0-vereinheitlicht, siehe BACKEND.md §1):
# - VALIDATION (400): ungültige Parameter / kein JSON / Validierungsfehler
# - TOKEN_INVALID (401): fehlendes oder unbekanntes Bearer-Token
# - TOKEN_EXPIRED (401): bekanntes, aber abgelaufenes Token
# - PENDING_INVALID (401): unbekanntes/abgelaufenes 2FA-Zwischen-Token
# - INVALID_CODE (401): falscher 2FA-Code
# - BAD_CREDENTIALS (401): falsche EduPage-Zugangsdaten
# - EDUPAGE_2FA (401): EduPage verlangt erneut 2FA → neu über /auth/login
# - CAPTCHA_REQUIRED (403): EduPage verlangt Captcha (einmal im Browser lösen)
# - NOT_FOUND (404): Ressource (Nachricht, Datei, Aufgabe) nicht gefunden
# - RATE_LIMITED (429): zu viele Login-Versuche, später erneut versuchen
# - CONFIG_MISSING (503): Server-Schlüssel fehlt (z. B. Wetter ohne Key)
# - UPSTREAM (502): alle anderen EduPage-/Netzfehler
#
# Historisch gab es zusätzlich EDUPAGE_ERROR, REAUTH_REQUIRED und
# 2FA_REQUIRED – sie sind seit P0 auf UPSTREAM bzw. EDUPAGE_2FA abgebildet
# und werden nicht mehr neu vergeben.

ERROR_CODES = frozenset({
    "VALIDATION", "TOKEN_INVALID", "TOKEN_EXPIRED", "PENDING_INVALID",
    "INVALID_CODE", "BAD_CREDENTIALS", "EDUPAGE_2FA", "CAPTCHA_REQUIRED",
    "NOT_FOUND", "RATE_LIMITED", "CONFIG_MISSING", "UPSTREAM",
})


def api_error(message: str, code: str, status: int = 400):
    """Zentrale Fehlerantwort: immer {error, code} plus HTTP-Status."""
    return jsonify({"error": message, "code": code}), status


def edupage_login_error(exc):
    """EduPage-Re-Login-Fehler auf (message, code, status) mappen.

    Einheitlich für alle Ressourcen-Pakete (B–G): BadCredentials →
    BAD_CREDENTIALS (401), Captcha → CAPTCHA_REQUIRED (403), sonst
    UPSTREAM (502). 2FA-während-Re-Login behandelt der Aufrufer separat
    mit EDUPAGE_2FA (401), weil dann ein frischer /auth/login nötig ist.
    """
    from edupage_api.exceptions import (
        BadCredentialsException,
        CaptchaException,
    )

    if isinstance(exc, BadCredentialsException):
        return ("Gespeicherte Zugangsdaten sind ungültig. "
                "Bitte erneut anmelden.", "BAD_CREDENTIALS", 401)
    if isinstance(exc, CaptchaException):
        return ("EduPage verlangt ein Captcha. "
                "Bitte einmal im Browser anmelden.", "CAPTCHA_REQUIRED", 403)
    return ("Anmeldung fehlgeschlagen: {}".format(exc), "UPSTREAM", 502)


# ------------------------------------------------------------ Paginierung

def get_pagination(args, default: int = 50, maximum: int = 200) -> tuple:
    """Limit/Offset aus Query-Parametern validieren. Returns (limit, offset).

    Wirft ValueError mit deutscher Meldung bei ungültigen Werten (Aufrufer
    antwortet damit per api_error mit Code VALIDATION und Status 400).
    """
    try:
        limit = int(args.get("limit", default))
        offset = int(args.get("offset", 0))
    except (TypeError, ValueError):
        raise ValueError("Limit und Offset müssen ganze Zahlen sein.")
    if not 1 <= limit <= maximum:
        raise ValueError(f"Limit muss zwischen 1 und {maximum} liegen.")
    if offset < 0:
        raise ValueError("Offset darf nicht negativ sein.")
    return limit, offset


def page(items: list, limit: int, offset: int) -> dict:
    """Listen-Hüllobjekt {items, total, limit, offset} bauen."""
    total = len(items)
    return {"items": items[offset:offset + limit],
            "total": total, "limit": limit, "offset": offset}
