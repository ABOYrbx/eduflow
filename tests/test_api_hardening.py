"""Härtungs-Tests P0+P1 (offline, ohne Zugangsdaten).

Lauf: `python3 tests/test_api_hardening.py`.
Prüft: kanonisches Fehler-Vokabular, /health + /openapi.json,
Geräte-Verwaltung, Token-Refresh (Rotation), PENDING-TTL und
Login-Rate-Limit (429 RATE_LIMITED).
"""

import sys
from datetime import datetime, timedelta
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import app as A
from api import core
from api.auth import reset_login_rate_limit


def check(name, cond):
    print(("OK  " if cond else "FEHLER ") + name)
    if not cond:
        raise SystemExit("Test fehlgeschlagen: %s" % name)


class _Fake2FA:
    def __init__(self, ok_code="123456"):
        self.ok_code = ok_code

    def finish_with_code(self, code):
        if str(code) != self.ok_code:
            raise RuntimeError("falscher Code")


def main():
    A.app.config["TESTING"] = True
    client = A.app.test_client()
    reset_login_rate_limit()

    # --- P0: Systemrouten ohne Token ----------------------------------
    r = client.get("/api/v1/health")
    check("health ohne Token 200 ok",
          r.status_code == 200 and r.get_json() == {
              "status": "ok", "version": "v1"})
    r = client.get("/api/v1/openapi.json")
    body = r.get_json()
    check("openapi 200 mit Pfaden",
          r.status_code == 200 and isinstance(body.get("paths"), dict)
          and "/api/v1/health" in body["paths"]
          and "/api/v1/auth/refresh" in body["paths"]
          and "/api/v1/devices" in body["paths"])
    check("openapi nennt kanonische Codes",
          "UPSTREAM" in str(body) and "EDUPAGE_2FA" in str(body)
          and "EDUPAGE_ERROR" not in str(body)
          and "REAUTH_REQUIRED" not in str(body))

    # --- P0: kanonische Codes bei Login-Fehlern -------------------------
    from edupage_api.exceptions import BadCredentialsException
    orig_login = A.do_login
    A.do_login = lambda u, p, s: (_ for _ in ()).throw(
        BadCredentialsException())
    try:
        r = client.get("/api/v1/timetable/day",
                       headers={"Authorization": "Bearer x"})
        # ohne gültiges Token zuerst TOKEN_INVALID (Schutz vor Login)
        check("ohne Token zuerst TOKEN_INVALID",
              r.status_code == 401
              and r.get_json()["code"] == "TOKEN_INVALID")
    finally:
        A.do_login = orig_login

    # --- P1: Geräte + Refresh ------------------------------------------
    created = core.create_token("schule", "haertung", "geheim",
                                device="geraet-a")
    token_a = created["token"]
    created_b = core.create_token("schule", "haertung", "geheim",
                                  device="geraet-b")
    token_b = created_b["token"]
    try:
        ha = {"Authorization": "Bearer " + token_a}
        r = client.get("/api/v1/devices", headers=ha)
        body = r.get_json()
        check("devices listet 2 eigene",
              r.status_code == 200 and body["total"] == 2
              and {d["device"] for d in body["items"]}
              == {"geraet-a", "geraet-b"}
              and all("token" not in d and "pwd" not in str(d).lower()
                      for d in body["items"]))
        # fremder Hash -> 404, kein Löschen
        r = client.delete("/api/v1/devices/" + "0" * 64, headers=ha)
        check("fremder Geräte-Hash 404 NOT_FOUND",
              r.status_code == 404
              and r.get_json()["code"] == "NOT_FOUND")
        # eigenes Gerät per Hash löschen
        import hashlib
        hb = hashlib.sha256(token_b.encode()).hexdigest()
        r = client.delete("/api/v1/devices/" + hb, headers=ha)
        check("eigenes Gerät löschen 200 ok",
              r.status_code == 200 and r.get_json() == {"status": "ok"})
        r = client.get("/api/v1/me",
                       headers={"Authorization": "Bearer " + token_b})
        check("gelöschtes Gerät 401",
              r.status_code == 401)
        # Refresh rotiert: neu gültig, alt ungültig
        r = client.post("/api/v1/auth/refresh", headers=ha)
        body = r.get_json()
        check("refresh 200 mit neuem Token",
              r.status_code == 200 and body["status"] == "ok"
              and body["token"] and body["token"] != token_a)
        token_c = body["token"]
        try:
            r = client.get("/api/v1/me", headers=ha)
            check("altes Token nach Refresh ungültig",
                  r.status_code == 401
                  and r.get_json()["code"] == "TOKEN_INVALID")
            r = client.get(
                "/api/v1/me",
                headers={"Authorization": "Bearer " + token_c})
            check("neues Token nach Refresh gültig",
                  r.status_code == 200)
        finally:
            core.revoke_token(token_c)
    finally:
        core.revoke_token(token_a)
        core.revoke_token(token_b)

    # --- P1: PENDING-TTL ------------------------------------------------
    A.PENDING_2FA["api-alt"] = {
        "two_factor": _Fake2FA(), "username": "u", "subdomain": "s",
        "password": "p", "device": "d", "api": True,
        "created": datetime.now() - timedelta(seconds=660),
    }
    try:
        r = client.post("/api/v1/auth/2fa",
                        json={"pending_token": "api-alt", "code": "123456"})
        check("abgelaufenes Pending 401 PENDING_INVALID",
              r.status_code == 401
              and r.get_json()["code"] == "PENDING_INVALID")
        check("abgelaufenes Pending geprunt",
              "api-alt" not in A.PENDING_2FA)
    finally:
        A.PENDING_2FA.pop("api-alt", None)

    # frisches API-Pending funktioniert (richtiger Code -> Token)
    A.PENDING_2FA["api-frisch"] = {
        "two_factor": _Fake2FA("999999"), "username": "s-user",
        "subdomain": "s-sub", "password": "geheim", "device": "d",
        "api": True, "created": datetime.now(),
    }
    try:
        r = client.post("/api/v1/auth/2fa",
                        json={"pending_token": "api-frisch",
                              "code": "falsch"})
        check("falscher Code 401 INVALID_CODE",
              r.status_code == 401
              and r.get_json()["code"] == "INVALID_CODE")
        r = client.post("/api/v1/auth/2fa",
                        json={"pending_token": "api-frisch",
                              "code": "999999"})
        body = r.get_json()
        check("richtiger Code 200 ok",
              r.status_code == 200 and body["status"] == "ok"
              and body["token"])
        core.revoke_token(body["token"])
    finally:
        A.PENDING_2FA.pop("api-frisch", None)

    # --- P1: Rate-Limit --------------------------------------------------
    reset_login_rate_limit()
    try:
        last = None
        for _ in range(21):
            last = client.post("/api/v1/auth/login",
                               json={"username": "", "password": ""})
        check("21. schneller Versuch 429 RATE_LIMITED",
              last.status_code == 429
              and last.get_json()["code"] == "RATE_LIMITED")
    finally:
        reset_login_rate_limit()
    r = client.post("/api/v1/auth/login", json={"username": "",
                                                "password": ""})
    check("nach Reset wieder 400 VALIDATION",
          r.status_code == 400 and r.get_json()["code"] == "VALIDATION")

    print("Alle Härtungs-Tests bestanden.")


if __name__ == "__main__":
    main()
