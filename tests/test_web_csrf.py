"""Tests für CSRF-Schutz der Web-Routen (+ POST-only Logout/Cache-Clear).

Lauf: `python tests/test_web_csrf.py`. Offline, ohne Zugangsdaten:
POSTs ohne/falsch CSRF-Token werden abgewiesen (Redirect, keine Aktion
– der EduPage-Login wird dabei nie erreicht); Formulare enthalten das
Token; /logout und /cache-clear akzeptieren kein GET mehr.
"""

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


def _login(client):
    with client.session_transaction() as s:
        s["username"] = "csrftest"
        s["subdomain"] = "csrfschule"
        s["pwd_enc"] = A._fernet().encrypt(b"geheim").decode()


def _csrf(client):
    with client.session_transaction() as s:
        return s.get("csrf_token", "")


def _logged_in(client):
    with client.session_transaction() as s:
        return "username" in s


def main():
    A.app.config["TESTING"] = True
    client = A.app.test_client()

    # --- Formulare enthalten das Token (auch ohne Sitzung) ---------------
    r = client.get("/")
    html = r.get_data(as_text=True)
    check("Login-Formular mit CSRF-Feld",
          r.status_code == 200 and 'name="csrf_token"' in html)

    # --- Login ohne Token: abgewiesen, kein Login-Versuch -----------------
    r = client.post("/login", data={"username": "x", "password": "y"})
    check("Login ohne CSRF leitet ab",
          r.status_code in (301, 302))
    check("Login ohne CSRF meldet nicht an", not _logged_in(client))

    _login(client)
    tok = _csrf(client)
    check("Sitzung hat CSRF-Token", bool(tok))

    # --- Schreibende Web-Routen ohne Token: abgewiesen --------------------
    for path, data in (
        ("/nachrichten/senden", {"body": "CSRF-Angriff"}),
        ("/hausaufgaben/erledigt", {"id": "1", "done": "1"}),
        ("/hausaufgaben/ausblenden", {"id": "1", "hide": "1"}),
        ("/einstellungen", {"landing": "noten"}),
        ("/einstellungen/api-token", {"device": "Angriff"}),
        ("/als-gelesen", {}),
    ):
        r = client.post(path, data=data)
        check("ohne CSRF abgewiesen: %s" % path,
              r.status_code in (301, 302))
    r = client.get("/einstellungen")
    html = r.get_data(as_text=True)
    check("ohne CSRF kein Token erstellt",
          "Noch keine aktiven Token" in html)

    # --- Header-Variante funktioniert (für fetch) --------------------------
    r = client.post("/einstellungen/api-token", data={"device": "HDR"},
                    headers={"X-CSRF-Token": tok})
    check("CSRF per Header akzeptiert",
          r.status_code in (301, 302))
    r = client.get("/einstellungen")
    html = r.get_data(as_text=True)
    m = re.search(r'id="newApiToken">([^<]+)<', html)
    check("Token per Header-Flow genau einmal gezeigt", m is not None)
    created = [m.group(1).strip()] if m else []
    try:
        check("Einstellungs-Formular mit CSRF-Feld",
              'name="csrf_token"' in html)
        for t in created:
            core.revoke_token(t)
        created = []
    finally:
        for t in created:
            core.revoke_token(t)

    # --- Logout/Cache-Clear nur per POST -----------------------------------
    r = client.get("/logout")
    check("GET /logout 405", r.status_code == 405)
    check("GET /logout meldet nicht ab", _logged_in(client))
    r = client.get("/cache-clear")
    check("GET /cache-clear 405", r.status_code == 405)
    r = client.post("/logout", data={"csrf_token": _csrf(client)})
    check("POST /logout mit CSRF meldet ab",
          r.status_code in (301, 302) and not _logged_in(client))

    print("Alle CSRF-Tests bestanden.")


if __name__ == "__main__":
    main()
