"""EduFlow API v1 – Essen und Wetter (Paket F).

Routen (JSON, mit Schutz):
- GET /essen – Wochen-Essensplan mit Aktualisierungs­schalter (refresh=1
  lädt das PDF neu statt aus dem Wochen-Cache). Antwortobjekt aus dem
  bestehenden Essensmodul (Woche, Label, PDF-Quelle, Tage, heute); Fehler
  mit UPSTREAM. Braucht kein EduPage-Login (öffentliche Quelle plus Cache).
- GET /wetter/suche – serverseitige Live-Ortssuche mit ?q=Suchtext.
- GET /wetter – Wetter-Proxy mit ?lat=..&lon=.. oder ?city=Name (Logik aus
  der bestehenden Web-Route, Key bleibt serverseitig). Ohne Ort VALIDATION,
  ohne Schlüssel CONFIG_MISSING, bei Upstream/Netz UPSTREAM.
"""

from flask import request

import essen as essenplan
from api import bp
from api.core import api_error, token_required


@bp.route("/essen", methods=["GET"])
@token_required
def api_essen():
    force = request.args.get("refresh", "0") == "1"
    try:
        return essenplan.get_week_menu(force_refresh=force), 200
    except essenplan.EssenUnavailable as e:
        return api_error(str(e), "UPSTREAM", 502)
    except Exception as e:
        return api_error(f"Essenplan konnte nicht geladen werden: {e}",
                         "UPSTREAM", 502)


@bp.route("/wetter", methods=["GET"])
@token_required
def api_wetter():
    try:
        lat = float(request.args.get("lat", ""))
        lon = float(request.args.get("lon", ""))
    except (TypeError, ValueError):
        lat = lon = None
    city = (request.args.get("city") or "").strip()[:100]
    if (lat is None or lon is None) and not city:
        return api_error("Bitte Koordinaten (?lat=..&lon=..) oder Stadt "
                         "(?city=..) angeben.", "VALIDATION", 400)

    from app import get_wetter_payload
    payload, status = get_wetter_payload(lat, lon, city)
    if status == 200:
        return payload, 200
    message = payload.get("error", "Wetter derzeit nicht verfügbar.")
    if status == 400:
        return api_error(message, "VALIDATION", 400)
    if status == 503:
        return api_error(message, "CONFIG_MISSING", 503)
    return api_error(message, "UPSTREAM", 502)


@bp.route("/wetter/suche", methods=["GET"])
@token_required
def api_wetter_suche():
    query = (request.args.get("q") or "").strip()[:100]
    if len(query) < 2:
        return {"items": []}, 200
    from app import search_wetter_cities
    payload, status = search_wetter_cities(query)
    if status == 200:
        return payload, 200
    message = payload.get("error", "Stadtsuche nicht verfügbar.")
    if status == 503:
        return api_error(message, "CONFIG_MISSING", 503)
    return api_error(message, "UPSTREAM", 502)
