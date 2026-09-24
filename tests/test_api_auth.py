"""Tests für das API-Auth-Paket (Paket A). Offline, ohne Zugangsdaten.

Lauf: `python tests/test_api_auth.py`. Live-Login und echter 2FA-Abschluss
brauchen ein EduPage-Konto und werden hier nicht getestet; geprüft werden
Validierung, Pending-Trennung (Web gegen API) und der Token-Fluss über
direkt angelegte Kern-Token.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import app as A
from api import core


def check(name, cond):
    print(("OK  " if cond else "FEHLER ") + name)
    if not cond:
        raise SystemExit(f"Test fehlgeschlagen: {name}")


def main():
    A.app.config["TESTING"] = True
    client = A.app.test_client()

    # Routen vorhanden
    rules = {str(r) for r in A.app.url_map.iter_rules()}
    for path in ("/api/v1/auth/login", "/api/v1/auth/2fa",
                 "/api/v1/auth/logout", "/api/v1/me"):
        check(f"Route {path} registriert", path in rules)

    # Validierung ohne Netz
    r = client.post("/api/v1/auth/login", data="kein-json",
                    content_type="text/plain")
    check("Login ohne JSON 400 VALIDATION",
          r.status_code == 400 and r.get_json()["code"] == "VALIDATION")
    r = client.post("/api/v1/auth/login", json={"username": "x"})
    check("Login ohne Passwort 400 VALIDATION",
          r.status_code == 400 and r.get_json()["code"] == "VALIDATION")
    r = client.post("/api/v1/auth/2fa", json={"pending_token": "x"})
    check("2FA ohne Code 400 VALIDATION",
          r.status_code == 400 and r.get_json()["code"] == "VALIDATION")
    r = client.post("/api/v1/auth/2fa",
                    json={"pending_token": "unbekannt", "code": "123456"})
    check("2FA mit unbekanntem Token 401 PENDING_INVALID",
          r.status_code == 401
          and r.get_json()["code"] == "PENDING_INVALID")

    # Web-Pending wird von der API abgewiesen (Trennung der Abläufe)
    A.PENDING_2FA["web-test-token"] = {"username": "w",
                                       "two_factor": object()}
    try:
        r = client.post("/api/v1/auth/2fa",
                        json={"pending_token": "web-test-token",
                              "code": "123456"})
        check("2FA weist Web-Eintrag ab",
              r.status_code == 401
              and r.get_json()["code"] == "PENDING_INVALID")
    finally:
        A.PENDING_2FA.pop("web-test-token", None)

    # Schutz ohne Token
    r = client.get("/api/v1/me")
    check("me ohne Token 401 TOKEN_INVALID",
          r.status_code == 401 and r.get_json()["code"] == "TOKEN_INVALID")
    r = client.post("/api/v1/auth/logout")
    check("logout ohne Token 401 TOKEN_INVALID",
          r.status_code == 401 and r.get_json()["code"] == "TOKEN_INVALID")

    # Voller Token-Fluss (Token direkt über den Kern angelegt, kein Netz)
    created = core.create_token("schule", "nutzer", "geheim",
                                device="testgeraet")
    token = created["token"]
    try:
        r = client.get("/api/v1/me",
                       headers={"Authorization": f"Bearer {token}"})
        check("me mit Token liefert Inhaber",
              r.status_code == 200
              and r.get_json() == {"subdomain": "schule",
                                   "username": "nutzer"})
        r = client.post("/api/v1/auth/logout",
                        headers={"Authorization": f"Bearer {token}"})
        check("logout widerruft mit Status ok",
              r.status_code == 200 and r.get_json() == {"status": "ok"})
        r = client.get("/api/v1/me",
                       headers={"Authorization": f"Bearer {token}"})
        check("nach logout ist Token ungültig",
              r.status_code == 401
              and r.get_json()["code"] == "TOKEN_INVALID")
    finally:
        core.revoke_token(token)

    print("Alle Auth-Tests bestanden.")


if __name__ == "__main__":
    main()
