"""Tests für das API-Paket G (Einstellungen und Cache). Offline.

Lauf: `python tests/test_api_settings.py`. Nutzt einen Test-Token und
eigene Cache-Dateien (eindeutiger Test-User, danach entfernt). Geprüft
werden Schutz, Schema/Werte-Parität zum Web, Speichern im
Web-Formularformat (ungültige Werte fallen auf Defaults wie im Web)
und Cache-Leeren mit Erhalt der Einstellungen.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import cache as apicache
import app as A
from api import core


def check(name, cond):
    print(("OK  " if cond else "FEHLER ") + name)
    if not cond:
        raise SystemExit("Test fehlgeschlagen: {}".format(name))


SUBDOMAIN = "apitest"
USERNAME = "settingstester"


def _clean(uhash):
    try:
        for p in apicache.CACHE_DIR.glob("*_{}*.json".format(uhash)):
            try:
                p.unlink()
            except Exception:
                pass
    except Exception:
        pass


def main():
    uhash = apicache.user_hash(SUBDOMAIN, USERNAME)
    _clean(uhash)

    # Essens-Caches sichern (Cache-Leeren räumt sie global weg wie im Web).
    essen_backup = {}
    try:
        for p in apicache.CACHE_DIR.glob("essen_*.json"):
            try:
                essen_backup[str(p)] = p.read_bytes()
            except Exception:
                pass
    except Exception:
        pass

    created = core.create_token(SUBDOMAIN, USERNAME, "geheim")
    token = created["token"]
    auth = {"Authorization": "Bearer {}".format(token)}
    try:
        A.app.config["TESTING"] = True
        client = A.app.test_client()

        rules = {str(r) for r in A.app.url_map.iter_rules()}
        check("Route GET /api/v1/settings registriert",
              "/api/v1/settings" in rules)
        check("Route POST /api/v1/cache-clear registriert",
              "/api/v1/cache-clear" in rules)

        r = client.get("/api/v1/settings")
        check("settings ohne Token 401 TOKEN_INVALID",
              r.status_code == 401
              and r.get_json().get("code") == "TOKEN_INVALID")
        r = client.post("/api/v1/cache-clear")
        check("cache-clear ohne Token 401 TOKEN_INVALID",
              r.status_code == 401
              and r.get_json().get("code") == "TOKEN_INVALID")

        # Lesen: Schema und Default-Werte wie im Web.
        r = client.get("/api/v1/settings", headers=auth)
        body = r.get_json()
        check("settings 200 mit Schema und Werten",
              r.status_code == 200
              and isinstance(body.get("schema"), list)
              and isinstance(body.get("values"), dict))
        keys = {s.get("key") for s in body["schema"]}
        check("Schema enthält Kern-Keys",
              {"landing", "hw_status", "hw_tests",
               "ov_unread", "ov_homework"} <= keys)
        check("Defaults wie Web",
              body["values"].get("landing") == "uebersicht"
              and body["values"].get("hw_status") == "alle"
              and body["values"].get("hw_tests") is False)

        # Speichern im Web-Formularformat (volle Form wie im Web).
        r = client.put("/api/v1/settings", headers=auth,
                       json={"landing": "hausaufgaben", "hw_status": "alle",
                             "hw_tests": True, "ov_unread": 25,
                             "ov_homework": 10})
        check("PUT ok mit Werten",
              r.status_code == 200
              and r.get_json().get("status") == "ok"
              and r.get_json()["values"].get("landing") == "hausaufgaben"
              and r.get_json()["values"].get("ov_unread") == 25
              and r.get_json()["values"].get("hw_tests") is True)
        r = client.get("/api/v1/settings", headers=auth)
        check("GET spiegelt Gespeichertes",
              r.get_json()["values"].get("landing") == "hausaufgaben")

        # Ungültige Werte fallen auf Defaults zurück (wie Web),
        # unbekannte Schlüssel werden ignoriert.
        r = client.put("/api/v1/settings", headers=auth,
                       json={"landing": "quatsch",
                             "hw_status": "quatsch",
                             "hw_tests": False,
                             "ov_unread": 999,
                             "ov_homework": 10,
                             "unbekannt": 1})
        b = r.get_json()
        check("ungültig -> Defaults, unbekannt ignoriert",
              r.status_code == 200
              and b["values"].get("landing") == "uebersicht"
              and b["values"].get("hw_status") == "alle"
              and b["values"].get("ov_unread") == 50
              and "unbekannt" not in b["values"])

        # Kein JSON-Objekt -> VALIDATION.
        r = client.put("/api/v1/settings", headers=auth,
                       data="kein-json", content_type="text/plain")
        check("PUT ohne JSON 400 VALIDATION",
              r.status_code == 400
              and r.get_json().get("code") == "VALIDATION")

        # Cache-Leeren: eigene Dateien weg, Einstellungen bleiben.
        apicache.save_timeline(uhash, "2000-01-01", [])
        apicache.save_settings(uhash, {"landing": "noten"})
        dummy_essen = apicache.CACHE_DIR / "essen_2099-W99.json"
        try:
            dummy_essen.write_text('{"version": 1}', encoding="utf-8")
        except Exception:
            pass
        r = client.post("/api/v1/cache-clear", headers=auth)
        b = r.get_json()
        check("clear ok mit Anzahl",
              r.status_code == 200 and b.get("status") == "ok"
              and isinstance(b.get("cleared"), int) and b["cleared"] >= 1)
        check("eigene Timeline gelöscht",
              apicache.load_timeline(uhash) is None)
        check("Einstellungen bleiben erhalten",
              apicache.load_settings(uhash).get("landing") == "noten")
        check("Essens-Dummy mit gelöscht", not dummy_essen.exists())
        r = client.get("/api/v1/settings", headers=auth)
        check("Settings nach Clear lesbar",
              r.status_code == 200
              and r.get_json()["values"].get("landing") == "noten")
    finally:
        core.revoke_token(token)
        _clean(uhash)
        try:
            for name, data in essen_backup.items():
                try:
                    Path(name).write_bytes(data)
                except Exception:
                    pass
        except Exception:
            pass

    print("Alle Settings-Tests bestanden.")


if __name__ == "__main__":
    main()
