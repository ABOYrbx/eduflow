"""EduFlow API v1 – Systemrouten (P0, additiv, ohne Auth).

- GET /health – Liveness für App/Monitoring, immer ohne Token.
- GET /openapi.json – minimale OpenAPI-3.0-Beschreibung aller /api/v1-Routen
  plus kanonischem Fehler-Vokabular (siehe api.core). Nur Doku, keine Logik.
"""

from flask import jsonify

from api import bp
from api.core import ERROR_CODES


@bp.route("/health", methods=["GET"])
def api_health():
    """Liveness-Probe (kein Token, keine EduPage-Abhängigkeit)."""
    return jsonify({"status": "ok", "version": "v1"})


def _openapi_spec():
    """Minimale, handgepflegte Spec (kein Generator, keine neue Dependency)."""
    bearer = {"bearerAuth": {"type": "http", "scheme": "bearer"}}
    err = {
        "type": "object",
        "required": ["error", "code"],
        "properties": {
            "error": {"type": "string"},
            "code": {"type": "string", "enum": sorted(ERROR_CODES)},
        },
    }
    page = {
        "type": "object",
        "required": ["items", "total", "limit", "offset"],
        "properties": {
            "items": {"type": "array", "items": {"type": "object"}},
            "total": {"type": "integer"},
            "limit": {"type": "integer"},
            "offset": {"type": "integer"},
        },
    }

    def op(summary, params=None, body=None, ok=None, secure=True):
        o = {"summary": summary, "responses": {
            "200": {"description": "OK",
                    "content": {"application/json": {
                        "schema": ok or page}}},
            "400": {"description": "Validierungsfehler",
                    "content": {"application/json": {"schema": err}}},
            "401": {"description": "Auth-/EduPage-Fehler",
                    "content": {"application/json": {"schema": err}}},
        }}
        if params:
            o["parameters"] = params
        if body is not None:
            o["requestBody"] = {
                "required": True,
                "content": {"application/json": {"schema": body}},
            }
        if secure:
            o["security"] = [{"bearerAuth": []}]
        return o

    q = lambda name, desc: {  # noqa: E731
        "in": "query", "name": name, "required": False,
        "schema": {"type": "string"}, "description": desc}

    paths = {
        "/health": {"get": op("Liveness-Probe", secure=False,
                              ok={"type": "object"})},
        "/openapi.json": {"get": op("Diese Spec", secure=False,
                                    ok={"type": "object"})},
        "/auth/login": {"post": op(
            "Anmelden (ok oder 2fa_required)", secure=False,
            body={"type": "object"},
            ok={"type": "object"})},
        "/auth/2fa": {"post": op(
            "2FA-Abschluss (Zwischen-Token + Code → Token)", secure=False,
            body={"type": "object"},
            ok={"type": "object"})},
        "/auth/logout": {"post": op("Token widerrufen",
                                    ok={"type": "object"})},
        "/auth/refresh": {"post": op("Token rotieren (alt → neu)",
                                     ok={"type": "object"})},
        "/me": {"get": op("Eigener Benutzer",
                          ok={"type": "object"})},
        "/devices": {"get": op("Eigene Tokens listen",
                               ok={"type": "object"})},
        "/devices/{id}": {"delete": op(
            "Eigenes Token widerrufen",
            params=[{"in": "path", "name": "id", "required": True,
                     "schema": {"type": "string"}}],
            ok={"type": "object"})},
        "/messages": {"get": op(
            "Nachrichtenliste (Top-Level)",
            params=[q("since", "JJJJ-MM-TT"), q("type", "Nachrichtentyp"),
                    q("q", "Textsuche"), q("limit", "1..200"),
                    q("offset", "ab 0"), q("refresh", "0/1")])},
        "/messages/send": {"post": op(
            "Nachricht senden", body={"type": "object"},
            ok={"type": "object"})},
        "/messages/read": {"post": op(
            "Alle als gelesen markieren", ok={"type": "object"})},
        "/messages/{id}/thread": {"get": op(
            "Thread (Likes, Antworten)",
            params=[{"in": "path", "name": "id", "required": True,
                     "schema": {"type": "integer"}},
                    q("refresh", "0/1")],
            ok={"type": "object"})},
        "/messages/{id}/reply": {"post": op(
            "Antworten", body={"type": "object"},
            ok={"type": "object"})},
        "/messages/{id}/attachments/{idx}": {"get": op(
            "Dateianhang (Header-, ?dl- oder ?token=)",
            ok={"type": "string", "format": "binary"})},
        "/messages/download-token": {"post": op(
            "Kurzzeit-Download-Token ausstellen",
            body={"type": "object"},
            ok={"type": "object"})},
        "/recipients": {"get": op("Empfängerliste")},
        "/homework": {"get": op(
            "Hausaufgabenliste",
            params=[q("since", "JJJJ-MM-TT"),
                    q("status", "alle/offen/überfällig/erledigt/papierkorb"),
                    q("include_tests", "0/1"), q("q", "Suche"),
                    q("limit", "1..200"), q("offset", "ab 0"),
                    q("refresh", "0/1")],
            ok={"type": "object"})},
        "/homework/{id}/done": {"post": op(
            "Erledigt-Schalter", body={"type": "object"},
            ok={"type": "object"})},
        "/homework/{id}/trash": {"post": op(
            "Papierkorb", body={"type": "object"},
            ok={"type": "object"})},
        "/timetable/day": {"get": op(
            "Tagesansicht",
            params=[q("day", "JJJJ-MM-TT"), q("refresh", "0/1")],
            ok={"type": "object"})},
        "/timetable/week": {"get": op(
            "Wochenansicht Mo–Fr",
            params=[q("day", "Datum in der Woche"), q("refresh", "0/1")],
            ok={"type": "object"})},
        "/substitutions/week": {"get": op(
            "Vertretungsplan Mo–Fr",
            params=[q("day", "Datum in der Woche")],
            ok={"type": "object"})},
        "/school/agenda": {"get": op(
            "Schultermine, Tests und Anwesenheitsmeldungen",
            params=[q("since", "Zeitraum ab JJJJ-MM-TT"),
                    q("until", "Zeitraum bis JJJJ-MM-TT"),
                    q("refresh", "0/1")],
            ok={"type": "object"})},
        "/grades": {"get": op(
            "Notenliste",
            params=[q("limit", "1..200"), q("offset", "ab 0"),
                    q("refresh", "0/1")])},
        "/essen": {"get": op(
            "Wochen-Essensplan",
            params=[q("refresh", "0/1")],
            ok={"type": "object"})},
        "/wetter": {"get": op(
            "Wetter-Proxy",
            params=[q("lat", "Breite"), q("lon", "Länge"),
                    q("city", "Stadtname")],
            ok={"type": "object"})},
        "/wetter/suche": {"get": op(
            "Städte für Wetter-Einstellungen suchen",
            params=[q("q", "Mindestens zwei Zeichen Suchtext")],
            ok={"type": "object"})},
        "/settings": {
            "get": op("Einstellungen lesen", ok={"type": "object"}),
            "put": op("Einstellungen speichern", body={"type": "object"},
                      ok={"type": "object"}),
        },
        "/cache-clear": {"post": op("Cache leeren (ohne Einstellungen)",
                                    ok={"type": "object"})},
    }
    return {
        "openapi": "3.0.0",
        "info": {"title": "EduFlow API", "version": "v1"},
        "servers": [{"url": "/api/v1"}],
        "components": {"securitySchemes": bearer},
        "paths": {"/api/v1" + p if p.startswith("/") else p: v
                  for p, v in paths.items()},
    }


@bp.route("/openapi.json", methods=["GET"])
def api_openapi():
    """OpenAPI-Spec als JSON (kein Token, nur Doku)."""
    return jsonify(_openapi_spec())
