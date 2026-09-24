"""Tests für das API-Noten-Paket (Paket E). Offline, ohne Zugangsdaten.

Lauf: `python tests/test_api_grades.py`. Der Frisch-Ladepfad (refresh=1 ohne
Cache) braucht ein EduPage-Konto und wird hier nicht getestet; geprüft
werden Schutz, Validierung und der frische-Cache-Kurzschluss über eine
eingesetzte Fixture-Datei (danach wieder entfernt).
"""

import json
import sys
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import app as A
import cache as apicache
from api import core


def check(name, cond):
    print(("OK  " if cond else "FEHLER ") + name)
    if not cond:
        raise SystemExit(f"Test fehlgeschlagen: {name}")


def _fixture():
    return [
        {"id": 1, "title": "KA", "subject": "Mathematik",
         "teacher": "Frau X", "date_display": "20.09.2026",
         "date_iso": "2026-09-20", "sort_key": "2026-09-20T00:00:00",
         "comment": "", "grade_display": "2", "grade_num": 2.0,
         "weight": 1.0, "weight_display": "", "grade_sub": "",
         "badge": "g12", "class_avg": 2.5, "class_avg_display": "2,5",
         "is_classic": True},
        {"id": 2, "title": "Test", "subject": "Deutsch",
         "teacher": "Herr Y", "date_display": "18.09.2026",
         "date_iso": "2026-09-18", "sort_key": "2026-09-18T00:00:00",
         "comment": "", "grade_display": "1", "grade_num": 1.0,
         "weight": 1.0, "weight_display": "", "grade_sub": "",
         "badge": "g12", "class_avg": None, "class_avg_display": "",
         "is_classic": True},
    ]


def main():
    A.app.config["TESTING"] = True
    client = A.app.test_client()

    rules = {str(r) for r in A.app.url_map.iter_rules()}
    check("Route /api/v1/grades registriert", "/api/v1/grades" in rules)

    r = client.get("/api/v1/grades")
    check("ohne Token 401 TOKEN_INVALID",
          r.status_code == 401 and r.get_json()["code"] == "TOKEN_INVALID")

    created = core.create_token("schule", "nutzer", "geheim")
    token = created["token"]
    auth = {"Authorization": f"Bearer {token}"}
    uhash = apicache.user_hash("schule", "nutzer")
    cache_path = apicache.CACHE_DIR / f"grades_{uhash}.json"
    try:
        r = client.get("/api/v1/grades?limit=0", headers=auth)
        check("ungültiges Limit 400 VALIDATION",
              r.status_code == 400 and r.get_json()["code"] == "VALIDATION")

        # Frische Fixture einsäen (kein Netz nötig)
        cache_path.parent.mkdir(parents=True, exist_ok=True)
        with open(cache_path, "w", encoding="utf-8") as f:
            json.dump({"version": 1,
                       "saved_at": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
                       "grades": _fixture()}, f, ensure_ascii=False)

        r = client.get("/api/v1/grades", headers=auth)
        j = r.get_json()
        check("Liste 200 mit Hülle und Cache-Info",
              r.status_code == 200 and j["total"] == 2
              and len(j["items"]) == 2 and j["limit"] == 50
              and j["offset"] == 0 and "Cache" in j.get("cache_info", ""))
        check("Noten-Objekte aus Cache-Bauer",
              j["items"][0]["subject"] == "Mathematik"
              and j["items"][0]["grade_num"] == 2.0)

        r = client.get("/api/v1/grades?limit=1&offset=1", headers=auth)
        j = r.get_json()
        check("Paginierung schneidet aus",
              r.status_code == 200 and j["total"] == 2
              and len(j["items"]) == 1
              and j["items"][0]["subject"] == "Deutsch")
    finally:
        core.revoke_token(token)
        try:
            cache_path.unlink()
        except OSError:
            pass

    print("Alle Noten-Tests bestanden.")


if __name__ == "__main__":
    main()
