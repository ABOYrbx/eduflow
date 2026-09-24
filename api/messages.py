"""EduFlow API v1 – Paket B: Nachrichten und Threads.

Routen (alle auf dem `api_v1`-Blueprint, Präfix `/api/v1`):
- GET  /messages                              – Nachrichtenliste (Top-Level)
- GET  /messages/<id>/thread                  – Thread (Likes, Antworten)
- POST /messages/read                         – alle als gelesen markieren
- GET  /recipients                            – Empfängerliste
- POST /messages/send                         – Nachricht senden
- POST /messages/<id>/reply                   – Antwort senden
- GET  /messages/<id>/attachments/<idx>       – Dateianhang laden

Alle Routen außer dem Download brauchen ein Bearer-Token (siehe
`api.core.token_required`); der Download akzeptiert zusätzlich
`?token=`, weil native Download-Komponenten nicht immer Header setzen
können. Serializer und Cache-Verhalten sind eins zu eins aus dem Web
übernommen (Nachrichten-Bauer, Thread-Logik, Gelesen-Status, Likes-Cache),
damit App und Web denselben Stand sehen.

Absichtlich ohne Import aus app.py auf Modulebene (Importzyklus: app.py
bindet den Blueprint beim Start ein). Die Web-Helper werden innerhalb der
Funktionen importiert – zur Request-Zeit ist app vollständig geladen.
"""

import re
import unicodedata
from datetime import date
from urllib.parse import urlparse

from flask import Response, g, jsonify, request, stream_with_context

from api import bp
from api.core import (
    api_error,
    get_pagination,
    page,
    token_expired,
    token_required,
    verify_token,
)
from edupage_api.exceptions import (
    BadCredentialsException,
    CaptchaException,
)

import cache as apicache


# ------------------------------------------------------------ Anmeldung

class _LoginFailed(Exception):
    """EduPage-Re-Login ist gescheitert (trägt API-Fehlerdaten)."""

    def __init__(self, message, code, status):
        super().__init__(message)
        self.message = message
        self.code = code
        self.status = status


def _api_login():
    """EduPage-Re-Login aus den Token-Zugangsdaten (wie Web-Re-Login).

    Returns (edupage, subdomain, username). Wirft _LoginFailed mit
    deutschem Fehlertext und stabilem Code (kanonisches Vokabular aus
    api.core: BAD_CREDENTIALS, CAPTCHA_REQUIRED, EDUPAGE_2FA, UPSTREAM).
    """
    from app import do_login  # lazy: kein Importzyklus mit app.py
    from api.core import edupage_login_error

    try:
        edupage, two_factor, real_subdomain = do_login(
            g.api_username, g.api_password, g.api_subdomain)
    except (BadCredentialsException, CaptchaException, Exception) as e:
        message, code, status = edupage_login_error(e)
        # Do-Login meldet falsche Subdomain als BadCredentials – Text aus
        # dem kanonischen Helper übernehmen, für messages den Hinweis auf
        # Benutzername/Passwort/Subdomain behalten.
        if code == "BAD_CREDENTIALS":
            message = ("Benutzername, Passwort oder Subdomain ist falsch.")
        raise _LoginFailed(message, code, status)
    if two_factor is not None:
        raise _LoginFailed(
            "Sitzung erfordert erneut 2FA. "
            "Bitte erneut über /auth/login anmelden.",
            "EDUPAGE_2FA", 401)
    return edupage, real_subdomain, g.api_username


def _login_or_error():
    """_api_login für Views: Returns (edupage, subdomain, username, None)
    oder (None, None, None, Fehlerantwort)."""
    try:
        edupage, subdomain, username = _api_login()
        return edupage, subdomain, username, None
    except _LoginFailed as e:
        return None, None, None, api_error(e.message, e.code, e.status)


# ------------------------------------------------------------ Suche

def _norm(s):
    # type: (object) -> str
    """Kleinschreibung + Umlaute-Toleranz (wie Web-Suche)."""
    if not isinstance(s, str):
        return ""
    return "".join(
        c for c in unicodedata.normalize("NFD", s.lower())
        if unicodedata.category(c) != "Mn")


# ------------------------------------------------------------ Liste

@bp.route("/messages", methods=["GET"])
@token_required
def messages_list():
    """Nachrichtenliste: nur Top-Level (keine Antworten), neueste zuerst.

    Query: since (JJJJ-MM-TT, Standard 2000-01-01), type (Nachrichtentyp),
    q (Textsuche, alle Wörter), limit/offset, refresh (0/1).
    """
    from app import (  # lazy: kein Importzyklus mit app.py
        EARLIEST_DEFAULT,
        MESSAGE_TYPES,
        _event_type_str,
        _is_reply,
        event_to_dict,
        get_timeline_cached,
    )

    try:
        limit, offset = get_pagination(request.args)
    except ValueError as e:
        return api_error(str(e), "VALIDATION", 400)

    since_raw = (request.args.get("since") or "").strip()
    if not since_raw:
        since_raw = EARLIEST_DEFAULT.isoformat()
    try:
        since = date.fromisoformat(since_raw)
    except ValueError:
        return api_error(
            "Datum muss im Format JJJJ-MM-TT sein.", "VALIDATION", 400)

    type_filter = (request.args.get("type") or "").strip()
    if type_filter and type_filter not in MESSAGE_TYPES:
        return api_error(
            "Unbekannter Nachrichtentyp. Gültig: %s."
            % ", ".join(sorted(MESSAGE_TYPES)),
            "VALIDATION", 400)

    q = (request.args.get("q") or "").strip()[:200]
    words = _norm(q).split()
    force = request.args.get("refresh", "0") == "1"

    edupage, subdomain, username, err = _login_or_error()
    if err is not None:
        return err
    try:
        events, _, _, _ = get_timeline_cached(
            edupage, subdomain, username, since, force)
    except Exception as e:
        return api_error(
            "Nachrichten konnten nicht geladen werden: %s" % e,
            "UPSTREAM", 502)

    items = []
    for ev in events:
        t = _event_type_str(ev)
        if t not in MESSAGE_TYPES or _is_reply(ev):
            continue
        if type_filter and t != type_filter:
            continue
        d = event_to_dict(ev)
        if words:
            hay = _norm(" ".join((
                d.get("author", ""), d.get("recipient", ""),
                d.get("text", ""), d.get("type_label", ""))))
            if not all(w in hay for w in words):
                continue
        items.append(d)
    items.sort(key=lambda d: d.get("sort_key", ""), reverse=True)
    return jsonify(page(items, limit, offset))


# ------------------------------------------------------------ Thread

def _thread_payload(result, cached):
    # type: (dict, bool) -> dict
    result = result or {}
    return {"likes": result.get("likes", []),
            "replies": result.get("replies", []),
            "reply_ids": result.get("reply_ids", []),
            "summary": result.get("summary", {}),
            "cached": cached}


@bp.route("/messages/<int:event_id>/thread", methods=["GET"])
@token_required
def message_thread(event_id):
    """Thread einer Nachricht (Likes, Antworten, Zusammenfassung).

    Nutzt denselben Datei-Cache wie das Web; nur bei Miss, stale Cache
    oder `?refresh=1` geht ein Request an EduPage.
    """
    from app import get_message_likes  # lazy: kein Importzyklus mit app.py

    force = request.args.get("refresh", "0") == "1"
    edupage, subdomain, username, err = _login_or_error()
    if err is not None:
        return err
    uhash = apicache.user_hash(subdomain, username)
    if not force:
        try:
            cached = apicache.load_likes(uhash, event_id)
            if cached is not None and apicache.is_fresh(
                    cached.get("saved_at"), apicache.LIKES_TTL_S):
                return jsonify(_thread_payload(
                    cached.get("data") or {}, True))
        except Exception:
            pass
    try:
        result = get_message_likes(edupage, event_id)
    except Exception as e:
        return api_error(
            "Thread konnte nicht geladen werden: %s" % e,
            "UPSTREAM", 502)
    try:
        apicache.save_likes(uhash, event_id, result)
    except Exception:
        pass
    return jsonify(_thread_payload(result, False))


# ------------------------------------------------------------ Gelesen

@bp.route("/messages/read", methods=["POST"])
@token_required
def messages_read():
    """Alle aktuellen Nachrichten als gelesen markieren (Web-Logik).

    Wie die Web-Funktion werden alle Nachrichtentypen markiert
    (Antworten stehen zusätzlich im Thread, schaden hier nicht).
    Reiner Cache-Zugriff, kein EduPage-Login nötig. Returns {marked}.
    """
    from app import MESSAGE_TYPES  # lazy: kein Importzyklus mit app.py

    uhash = apicache.user_hash(g.api_subdomain, g.api_username)
    try:
        cached = apicache.load_timeline(uhash)
        records = cached.get("events", []) if cached else []
        ids = [r.get("id") for r in records
               if str(r.get("type", "")) in MESSAGE_TYPES]
        n = apicache.mark_seen(uhash, ids)
    except Exception as e:
        return api_error(
            "Gelesen-Status konnte nicht gespeichert werden: %s" % e,
            "UPSTREAM", 502)
    return jsonify({"marked": n})


# ------------------------------------------------------------ Empfänger

@bp.route("/recipients", methods=["GET"])
@token_required
def recipients():
    """Empfängerliste (Lehrer + Mitschüler, nach Name sortiert)."""
    from app import get_recipients  # lazy: kein Importzyklus mit app.py

    try:
        limit, offset = get_pagination(request.args)
    except ValueError as e:
        return api_error(str(e), "VALIDATION", 400)
    edupage, _, _, err = _login_or_error()
    if err is not None:
        return err
    try:
        recs = get_recipients(edupage)
    except Exception as e:
        return api_error(
            "Empfänger konnten nicht geladen werden: %s" % e,
            "UPSTREAM", 502)
    return jsonify(page(recs, limit, offset))


# ------------------------------------------------------------ Senden

def _clean_recipients(raw):
    # type: (object) -> list
    """Empfänger-IDs säubern (Liste oder CSV-String, Duplikate raus)."""
    from app import _RECIPIENT_ID_RE  # lazy: kein Importzyklus mit app.py

    if isinstance(raw, str):
        raw = raw.split(",")
    if not isinstance(raw, list):
        return []
    seen = set()
    valid = []
    for r in raw:
        r = r.strip() if isinstance(r, str) else ""
        if r and r not in seen:
            seen.add(r)
            if _RECIPIENT_ID_RE.match(r):
                valid.append(r)
    return valid


@bp.route("/messages/send", methods=["POST"])
@token_required
def messages_send():
    """Neue Nachricht senden. JSON: {recipients: [IDs], body: Text}.

    Returns das Ressourcen-Objekt der neuen Nachricht (Web-Bauer).
    """
    from app import (  # lazy: kein Importzyklus mit app.py
        EARLIEST_DEFAULT,
        event_to_dict,
        fetch_history_with_fallback,
    )

    data = request.get_json(silent=True)
    if not isinstance(data, dict):
        data = {}
    valid = _clean_recipients(data.get("recipients"))
    body = data.get("body", "")
    body = body.strip()[:5000] if isinstance(body, str) else ""
    if not valid:
        return api_error(
            "Bitte mindestens einen gültigen Empfänger angeben.",
            "VALIDATION", 400)
    if not body:
        return api_error(
            "Bitte einen Nachrichtentext eingeben.", "VALIDATION", 400)

    edupage, subdomain, username, err = _login_or_error()
    if err is not None:
        return err
    try:
        new_id = edupage.send_message(valid, body)
    except Exception as e:
        return api_error(
            "Senden fehlgeschlagen: %s" % e, "UPSTREAM", 502)

    # Synchron frisch laden (kein stale-while-revalidate: nach dem Senden
    # muss die neue Nachricht sofort sichtbar sein) und Ressource zurückgeben.
    try:
        events, _, _ = fetch_history_with_fallback(
            edupage, EARLIEST_DEFAULT)
        try:
            uhash = apicache.user_hash(subdomain, username)
            apicache.save_timeline(
                uhash, EARLIEST_DEFAULT.isoformat(),
                [apicache.event_to_record(e) for e in events])
        except Exception:
            pass
        for ev in events:
            if str(getattr(ev, "event_id", "")) == str(new_id):
                return jsonify(event_to_dict(ev))
    except Exception:
        pass
    return api_error(
        "Gesendet, aber die neue Nachricht wurde nicht gefunden.",
        "UPSTREAM", 502)


# ------------------------------------------------------------ Antworten

@bp.route("/messages/<int:event_id>/reply", methods=["POST"])
@token_required
def message_reply(event_id):
    """Auf eine Nachricht antworten. JSON: {body: Text}.

    Antwort geht an alle im Thread (Web-Verhalten). Returns den
    aufgefrischten Thread (Likes, Antworten, Zusammenfassung).
    """
    from app import (  # lazy: kein Importzyklus mit app.py
        get_message_likes,
        send_reply,
    )

    data = request.get_json(silent=True)
    if not isinstance(data, dict):
        data = {}
    body = data.get("body", "")
    body = body.strip()[:5000] if isinstance(body, str) else ""
    if not body:
        return api_error(
            "Bitte einen Antworttext eingeben.", "VALIDATION", 400)

    edupage, subdomain, username, err = _login_or_error()
    if err is not None:
        return err
    try:
        send_reply(edupage, event_id, body)
    except ValueError as e:
        return api_error(str(e), "VALIDATION", 400)
    except Exception as e:
        return api_error(
            "Antwort fehlgeschlagen: %s" % e, "UPSTREAM", 502)

    # Thread-Cache sofort auffrischen, damit die Antwort sichtbar ist.
    try:
        uhash = apicache.user_hash(subdomain, username)
        result = get_message_likes(edupage, event_id)
        try:
            apicache.save_likes(uhash, event_id, result)
        except Exception:
            pass
        return jsonify(_thread_payload(result, False))
    except Exception as e:
        return api_error(
            "Antwort wurde gesendet, der Thread konnte aber nicht "
            "geladen werden: %s" % e,
            "UPSTREAM", 502)


# ------------------------------------------------------------ Download

def _download_credentials():
    # type: () -> tuple
    """Token aus Header oder `?token=` prüfen (für native Downloader).

    Returns (creds, None) oder (None, Fehlerantwort).
    """
    auth = request.headers.get("Authorization", "")
    token = auth[7:] if auth[:7].lower() == "bearer " else ""
    token = (token or "").strip()
    if not token:
        token = (request.args.get("token") or "").strip()
    creds = verify_token(token)
    if creds is None:
        if token_expired(token):
            return None, api_error(
                "Token ist abgelaufen. Bitte erneut anmelden.",
                "TOKEN_EXPIRED", 401)
        return None, api_error(
            "Ungültiges oder fehlendes Token.", "TOKEN_INVALID", 401)
    return creds, None


@bp.route("/messages/<int:event_id>/attachments/<int:idx>", methods=["GET"])
def message_attachment(event_id, idx):
    """Dateianhang als authentifizierter Proxy (EduPage-Sitzung).

    Nur EduPage-Adressen, gestreamt, mit Original-Dateiname.
    """
    from app import (  # lazy: kein Importzyklus mit app.py
        EARLIEST_DEFAULT,
        extract_attachments,
        get_timeline_cached,
    )

    creds, err = _download_credentials()
    if err is not None:
        return err
    g.api_subdomain = creds["subdomain"]
    g.api_username = creds["username"]
    g.api_password = creds["password"]

    edupage, subdomain, username, login_err = _login_or_error()
    if login_err is not None:
        return login_err

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
            return api_error(
                "Download fehlgeschlagen: %s" % e, "UPSTREAM", 502)
    if record is None:
        return api_error("Nachricht nicht gefunden.", "NOT_FOUND", 404)

    atts = extract_attachments(record.get("additional_data") or {})
    if idx < 0 or idx >= len(atts):
        return api_error("Datei nicht gefunden.", "NOT_FOUND", 404)

    raw_url = atts[idx]["url"]
    if raw_url.startswith("/"):
        url = "https://%s.edupage.org%s" % (subdomain, raw_url)
    else:
        url = raw_url
    if not (urlparse(url).hostname or "").endswith(".edupage.org"):
        return api_error("Ungültiger Download-Link.", "VALIDATION", 400)

    try:
        upstream = edupage.session.get(url, stream=True, timeout=30)
    except Exception as e:
        return api_error(
            "Download fehlgeschlagen: %s" % e, "UPSTREAM", 502)
    if upstream.status_code != 200:
        return api_error(
            "EduPage meldet Fehler %s." % upstream.status_code,
            "UPSTREAM", 502)

    filename = re.sub(r'["\r\n]', "", atts[idx]["name"] or "")[:120]
    filename = filename or "datei"
    ctype = (upstream.headers.get("Content-Type", "application/octet-stream")
             .split(";")[0].strip() or "application/octet-stream")
    return Response(
        stream_with_context(upstream.iter_content(chunk_size=65536)),
        content_type=ctype,
        headers={"Content-Disposition":
                 'attachment; filename="%s"' % filename},
    )
