"""Tests für das API-Meta-Paket (Paket F: Essen und Wetter). Offline.

Lauf: `python tests/test_api_meta.py`. Frisch-Ladepfade (Essen-refresh ohne
Cache, echte Wetter-Abfrage) brauchen Netz beziehungsweise Schlüssel und
werden hier nicht getestet; geprüft werden Schutz, Validierung, der
Essen-Cache-Kurzschluss über eine Fixture (danach entfernt) und die
Wetter-Fehlerübersetzung ohne Schlüssel.
"""

import json
import sys
from datetime import date, datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import app as A
import essen as essenplan
from api import core


def check(name, cond):
    print(("OK  " if cond else "FEHLER ") + name)
    if not cond:
        raise SystemExit(f"Test fehlgeschlagen: {name}")


def _fixture():
    days = {}
    for i, name in enumerate(["Montag", "Dienstag", "Mittwoch",
                              "Donnerstag", "Freitag"]):
        days[name] = {"date": f"2026-09-{21 + i}",
                      "dishes": [{"text": f"Gericht {name}",
                                  "price": "7,90 €"}],
                      "note": ""}
    return {"week": "2026-W39", "label": "21.9. – 25.9.2026",
            "source_url": "https://example.invalid/menu.pdf",
            "days": days, "today": "Donnerstag"}


def main():
    A.app.config["TESTING"] = True
    client = A.app.test_client()

    rules = {str(r) for r in A.app.url_map.iter_rules()}
    check("Route /api/v1/essen registriert", "/api/v1/essen" in rules)
    check("Route /api/v1/wetter registriert", "/api/v1/wetter" in rules)

    r = client.get("/api/v1/essen")
    check("essen ohne Token 401", r.status_code == 401)
    r = client.get("/api/v1/wetter?city=Berlin")
    check("wetter ohne Token 401", r.status_code == 401)

    created = core.create_token("schule", "nutzer", "geheim")
    token = created["token"]
    auth = {"Authorization": f"Bearer {token}"}
    week_key = essenplan.week_key(date.today())
    cache_path = essenplan.CACHE_DIR / f"essen_{week_key}.json"
    had_cache = cache_path.is_file()
    try:
        r = client.get("/api/v1/wetter", headers=auth)
        check("wetter ohne Ort 400 VALIDATION",
              r.status_code == 400 and r.get_json()["code"] == "VALIDATION")

        if not had_cache:
            with open(cache_path, "w", encoding="utf-8") as f:
                json.dump({"version": 1,
                           "saved_at": datetime.now()
                           .strftime("%Y-%m-%d %H:%M:%S"),
                           "data": _fixture()}, f, ensure_ascii=False)
        r = client.get("/api/v1/essen", headers=auth)
        j = r.get_json()
        check("essen 200 mit allen fünf Tagen",
              r.status_code == 200 and len(j.get("days", {})) == 5
              and all(len(j["days"][d]["dishes"]) > 0
                      for d in j["days"]))
        check("essen mit Preisen und Quelle",
              "7,90 €" in json.dumps(j, ensure_ascii=False)
              and j.get("source_url"))
    finally:
        core.revoke_token(token)
        if not had_cache:
            try:
                cache_path.unlink()
            except OSError:
                pass

    print("Alle Meta-Tests bestanden.")


if __name__ == "__main__":
    main()
