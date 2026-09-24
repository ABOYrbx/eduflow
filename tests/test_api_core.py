"""Tests für das API-Kernmodul (Paket 0). Offline, ohne Zugangsdaten.

Lauf: `python tests/test_api_core.py` (oder per pytest, falls vorhanden).
Erzeugt kurz ein Test-Token in `.cache/api_tokens.json` und räumt es danach
wieder weg.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from flask import Flask

from api import bp as api_bp
from api import core


def check(name, cond):
    print(("OK  " if cond else "FEHLER ") + name)
    if not cond:
        raise SystemExit(f"Test fehlgeschlagen: {name}")


def main():
    # Fehler-Bauer
    app = Flask(__name__)
    with app.test_request_context():
        resp, status = core.api_error("Kaputt.", "VALIDATION", 400)
        check("api_error Form und Status",
              resp.get_json() == {"error": "Kaputt.", "code": "VALIDATION"}
              and status == 400)

    # Paginierung
    check("get_pagination Defaults", core.get_pagination({}) == (50, 0))
    check("get_pagination Werte", core.get_pagination(
        {"limit": "10", "offset": "20"}) == (10, 20))
    for bad in ({"limit": "0"}, {"limit": "9999"}, {"offset": "-1"},
                {"limit": "abc"}):
        try:
            core.get_pagination(bad)
            check(f"get_pagination weist {bad} ab", False)
        except ValueError:
            pass
    check("get_pagination weist Ungültiges ab", True)
    p = core.page([1, 2, 3, 4, 5], 2, 1)
    check("page Hüllobjekt",
          p == {"items": [2, 3], "total": 5, "limit": 2, "offset": 1})

    # Token-Runde
    created = core.create_token("schule", "nutzer", "geheim", device="test")
    token = created["token"]
    check("create_token liefert Token und Ablauf",
          len(token) >= 32 and created["expires"])
    creds = core.verify_token(token)
    check("verify_token gibt Zugangsdaten",
          creds is not None and creds["subdomain"] == "schule"
          and creds["username"] == "nutzer" and creds["password"] == "geheim")
    check("verify_token lehnt Unbekanntes ab",
          core.verify_token("unbekannt") is None)
    check("verify_token lehnt Leeres ab", core.verify_token("") is None)

    # Abgelaufenes Token (direkt in die Ablage gelegt, da Schreiben
    # Abgelaufenes sofort entsorgt)
    import hashlib
    import json
    from datetime import datetime, timedelta
    old_token = "test-abgelaufen-" + token[:8]
    old_hash = hashlib.sha256(old_token.encode()).hexdigest()
    past = (datetime.now() - timedelta(days=1)).strftime("%Y-%m-%d %H:%M:%S")
    try:
        with open(core._TOKEN_PATH, "r", encoding="utf-8") as f:
            store = json.load(f)
    except Exception:
        store = {"version": 1, "tokens": {}}
    store["tokens"][old_hash] = {
        "subdomain": "schule", "username": "nutzer",
        "pwd_enc": core._fernet().encrypt(b"geheim").decode(),
        "created": past, "expires": past, "device": "test",
    }
    with open(core._TOKEN_PATH, "w", encoding="utf-8") as f:
        json.dump(store, f)
    check("verify_token lehnt Abgelaufenes ab",
          core.verify_token(old_token) is None)
    check("token_expired erkennt Ablauf",
          core.token_expired(old_token) is True)
    check("token_expired bei Unbekanntem falsch",
          core.token_expired("unbekannt") is False)

    # Schutz-Decorator auf Mini-App
    mini = Flask(__name__)

    @mini.route("/privat")
    @core.token_required
    def privat():
        from flask import g
        return {"user": g.api_username}

    client = mini.test_client()
    r = client.get("/privat")
    check("ohne Token 401 TOKEN_INVALID",
          r.status_code == 401 and r.get_json()["code"] == "TOKEN_INVALID")
    r = client.get("/privat", headers={"Authorization": "Bearer falsch"})
    check("falsches Token 401 TOKEN_INVALID",
          r.status_code == 401 and r.get_json()["code"] == "TOKEN_INVALID")
    r = client.get("/privat",
                   headers={"Authorization": f"Bearer {old_token}"})
    check("abgelaufenes Token 401 TOKEN_EXPIRED",
          r.status_code == 401 and r.get_json()["code"] == "TOKEN_EXPIRED")
    r = client.get("/privat", headers={"Authorization": f"Bearer {token}"})
    check("gültiges Token 200 mit Benutzer",
          r.status_code == 200 and r.get_json() == {"user": "nutzer"})

    # Aufräumen
    check("revoke_token trifft", core.revoke_token(token) is True)
    check("nach revoke ungültig", core.verify_token(token) is None)
    check("revoke ohne Treffer falsch",
          core.revoke_token("unbekannt") is False)
    core.revoke_token(old_token)

    # Blueprint-Anbindung
    check("Blueprint-Präfix /api/v1", api_bp.url_prefix == "/api/v1")

    print("Alle Kern-Tests bestanden.")


if __name__ == "__main__":
    main()
