"""Tests für API-Token im Web-UI (Einstellungen). Offline, ohne Zugangsdaten.

Lauf: `python tests/test_web_api_token.py`. Die Web-Sitzung wird direkt
gesetzt (kein EduPage-Login); geprüft werden Sektion, einmalige
Token-Anzeige, Gültigkeit des Tokens gegen /api/v1, Besitzschutz beim
Widerrufen und Aufräumen aller Test-Token.
"""

import hashlib
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import app as A
from api import core


def check(name, cond):
    print(("OK  " if cond else "FEHLER ") + name)
    if not cond:
        raise SystemExit("Test fehlgeschlagen: {}".format(name))


SUBDOMAIN = "apitest"
USERNAME = "webuitester"


def _login(client):
    with client.session_transaction() as s:
        s["username"] = USERNAME
        s["subdomain"] = SUBDOMAIN
        s["pwd_enc"] = A._fernet().encrypt(b"geheim").decode()


def main():
    A.app.config["TESTING"] = True
    client = A.app.test_client()
    _login(client)
    created = []

    try:
        r = client.get("/einstellungen")
        html = r.get_data(as_text=True)
        check("Einstellungen 200 mit API-Sektion",
              r.status_code == 200 and "API-Token" in html
              and "/einstellungen/api-token" in html)

        r = client.post("/einstellungen/api-token",
                        data={"device": "Testgerät"})
        check("Erstellen leitet auf Einstellungen",
              r.status_code in (301, 302)
              and r.headers.get("Location", "").endswith("/einstellungen"))
        r = client.get("/einstellungen")
        html = r.get_data(as_text=True)
        m = re.search(r'id="newApiToken">([^<]+)<', html)
        check("Token genau einmal gezeigt", m is not None)
        token = m.group(1).strip()
        created.append(token)
        check("Hinweis nur-einmal sichtbar",
              "nur einmal" in html and "Testgerät" in html)
        r = client.get("/einstellungen")
        check("zweiter Aufruf ohne Token-Anzeige",
              'id="newApiToken"' not in r.get_data(as_text=True))

        r = client.get("/api/v1/me",
                       headers={"Authorization": "Bearer {}".format(token)})
        check("Token funktioniert gegen /api/v1",
              r.status_code == 200
              and r.get_json() == {"subdomain": SUBDOMAIN,
                                   "username": USERNAME})

        r = client.get("/einstellungen")
        check("Token in der Liste",
              "Testgerät" in r.get_data(as_text=True))

        # Fremder Token-Hash wird abgewiesen (Besitzschutz).
        foreign = core.create_token("andereschule", "fremder", "geheim")
        foreign_hash = hashlib.sha256(
            foreign["token"].encode()).hexdigest()
        try:
            r = client.post("/einstellungen/api-token/widerrufen",
                            data={"id": foreign_hash})
            check("fremder Hash abgelehnt (Redirect)",
                  r.status_code in (301, 302))
            r = client.get("/api/v1/me", headers={
                "Authorization": "Bearer {}".format(foreign["token"])})
            check("fremder Token weiter gültig", r.status_code == 200)
        finally:
            core.revoke_token(foreign["token"])

        # Eigenen Token widerrufen.
        own_hash = hashlib.sha256(token.encode()).hexdigest()
        r = client.post("/einstellungen/api-token/widerrufen",
                        data={"id": own_hash})
        check("Widerrufen leitet auf Einstellungen",
              r.status_code in (301, 302))
        created.remove(token)
        r = client.get("/api/v1/me",
                       headers={"Authorization": "Bearer {}".format(token)})
        check("nach Widerruf 401", r.status_code == 401)

        # Ohne Auswahl: Fehlermeldung, kein Crash.
        r = client.post("/einstellungen/api-token/widerrufen", data={})
        check("Widerrufen ohne ID leitet weiter",
              r.status_code in (301, 302))
    finally:
        for t in created:
            core.revoke_token(t)

    print("Alle Web-Token-Tests bestanden.")


if __name__ == "__main__":
    main()
