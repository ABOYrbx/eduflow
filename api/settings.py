"""EduFlow API v1 – Einstellungen und Cache (Paket G).

Routen (JSON, mit Schutz):
- GET /settings – Einstellungs­schema und Werte des Token-Inhabers
  (Defaults plus gespeicherte Werte, selbe Normalisierung wie im Web).
- PUT /settings – Werte aus JSON speichern (gegen dasselbe Schema
  validiert wie das Web-Formular; echte JSON-Booleans werden vorher auf
  die Formular-Schreibweise gebracht, sonst identische Prüfung).
- POST /cache-clear – dieselben Dateien löschen wie die Web-Funktion
  (eigene Caches plus Essens-Caches, Einstellungen bleiben erhalten)
  und die Anzahl melden.

App-Code wird nur gelesen (Schema, Defaults, Normalisierung, Cache-Ablage),
nie geändert; Zugangsdaten kommen aus dem Token-Schutz.
"""

from flask import g, request

import cache as apicache
from api import bp
from api.core import api_error, token_required


def _uhash() -> str:
    return apicache.user_hash(g.api_subdomain, g.api_username)


def _merged_values(uhash: str) -> dict:
    from app import SETTINGS_DEFAULTS, SETTINGS_SCHEMA, _coerce_setting
    merged = dict(SETTINGS_DEFAULTS)
    try:
        stored = apicache.load_settings(uhash)
        for spec in SETTINGS_SCHEMA:
            if spec["key"] in stored:
                merged[spec["key"]] = _coerce_setting(spec, stored[spec["key"]])
    except Exception:
        pass
    return merged


@bp.route("/settings", methods=["GET"])
@token_required
def api_settings_get():
    from app import SETTINGS_SCHEMA
    return {"schema": SETTINGS_SCHEMA,
            "values": _merged_values(_uhash())}, 200


@bp.route("/settings", methods=["PUT"])
@token_required
def api_settings_put():
    data = request.get_json(silent=True)
    if not isinstance(data, dict):
        return api_error("Ungültige Anfrage (JSON-Objekt erwartet).",
                         "VALIDATION", 400)
    from app import settings_from_form
    # Ältere App-Versionen senden nur die ihnen bekannten Felder. Unbekannte
    # neuere Kontoeinstellungen (z. B. die Übersichtsreihenfolge) beibehalten.
    data = {**_merged_values(_uhash()), **data}
    normalized = {}
    for key, value in data.items():
        if value is True:
            normalized[key] = "1"
        elif value is False:
            normalized[key] = "0"
        else:
            normalized[key] = value
    try:
        values = settings_from_form(normalized)
    except Exception as e:
        return api_error(f"Einstellungen konnten nicht gespeichert werden: {e}",
                         "VALIDATION", 400)
    try:
        apicache.save_settings(_uhash(), values)
    except Exception as e:
        return api_error(f"Einstellungen konnten nicht gespeichert werden: {e}",
                         "UPSTREAM", 502)
    return {"status": "ok", "values": _merged_values(_uhash())}, 200


@bp.route("/cache-clear", methods=["POST"])
@token_required
def api_cache_clear():
    from pathlib import Path
    uhash = _uhash()
    n = 0
    try:
        for p in apicache.CACHE_DIR.glob(f"*_{uhash}*.json"):
            if p.name.startswith("settings_"):
                continue  # Einstellungen bleiben erhalten, wie im Web
            try:
                Path(p).unlink()
                n += 1
            except Exception:
                pass
        for p in apicache.CACHE_DIR.glob("essen_*.json"):
            try:
                Path(p).unlink()
                n += 1
            except Exception:
                pass
    except Exception as e:
        return api_error(f"Cache konnte nicht gelöscht werden: {e}",
                         "UPSTREAM", 502)
    return {"status": "ok", "cleared": n}, 200
