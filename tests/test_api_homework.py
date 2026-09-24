"""Tests für das API-Hausaufgaben-Paket (Paket C). Offline, ohne Zugangsdaten.

Lauf: `python tests/test_api_homework.py`. Nutzt einen Test-Token plus
Fake-EduPage (Affection: do_login und set_homework_done werden
monkeygepatcht), Fixture-Timeline im bestehenden Datei-Cache. Prüft
Routenform, Fehlercodes, Filter/Zähler/Sortierung wie im Web,
Paginierung und Cache-Wiederverwendung sowie Statuswechsel mit
erneutem Laden.
"""

import sys
from datetime import datetime, timedelta
from pathlib import Path
from types import SimpleNamespace

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import cache as apicache
import app as A
from api import core


def check(name, cond):
    print(("OK  " if cond else "FEHLER ") + name)
    if not cond:
        raise SystemExit("Test fehlgeschlagen: {}".format(name))


SUBDOMAIN = "apitest"
USERNAME = "hwtester"


def _mk_event(event_id, etype, title, subject, due_iso, days_ago,
              is_done=False, description=""):
    old_vals = {"title": title, "predmet": subject,
                "popis": description or title}
    if due_iso:
        old_vals["date"] = due_iso
    return SimpleNamespace(
        event_id=event_id,
        timestamp=datetime.now() - timedelta(days=days_ago),
        text="{} Text".format(title),
        author="Lehrer A",
        recipient="Klasse",
        event_type=SimpleNamespace(value=etype),
        additional_data={"oldVals": old_vals},
        is_starred=False,
        is_done=is_done,
        done_at=datetime.now() if is_done else None,
        reaction_count=0,
        created_at=None,
        is_removed=False,
    )


class FakeEdupage:
    calls = 0

    def __init__(self, events):
        self.subdomain = SUBDOMAIN
        self.session = SimpleNamespace()
        self._events = events

    def get_notification_history(self, since):
        FakeEdupage.calls += 1
        return list(self._events)


def _clean_test_cache(uhash):
    try:
        for p in apicache.CACHE_DIR.glob("*_{}*.json".format(uhash)):
            if p.name.startswith("settings_"):
                continue
            try:
                p.unlink()
            except Exception:
                pass
    except Exception:
        pass


def main():
    today = datetime.now().date()
    due_yesterday = (today - timedelta(days=1)).isoformat()
    due_tomorrow = (today + timedelta(days=1)).isoformat()

    fixtures = [
        _mk_event(101, "homework", "Mathe Übung", "Mathe",
                  due_yesterday, 3, False, "Seite 10"),
        _mk_event(102, "homework", "Deutsch Aufsatz", "Deutsch",
                  due_tomorrow, 2, False, "Einleitung"),
        _mk_event(103, "homework", "Englisch Vokabeln", "Englisch",
                  due_tomorrow, 1, True, "Unit 3"),
        _mk_event(104, "bexam", "Physik Test", "Physik",
                  due_tomorrow, 1, False, "Kapitel 2"),
        _mk_event(105, "homework", "Kunst Skizze", "Kunst",
                  "", 4, False, "Baum"),
    ]

    uhash = apicache.user_hash(SUBDOMAIN, USERNAME)
    _clean_test_cache(uhash)
    FakeEdupage.calls = 0

    orig_login = A.do_login
    orig_done = A.set_homework_done
    done_calls = []

    def fake_login(username, password, subdomain):
        return FakeEdupage(fixtures), None, SUBDOMAIN

    def fake_done(edupage, event_id, done):
        done_calls.append((str(event_id), bool(done)))
        return {"ok": True}

    A.do_login = fake_login
    A.set_homework_done = fake_done

    created = core.create_token(SUBDOMAIN, USERNAME, "geheim")
    token = created["token"]
    auth = {"Authorization": "Bearer {}".format(token)}

    try:
        A.app.config["TESTING"] = True
        client = A.app.test_client()

        rules = {str(r) for r in A.app.url_map.iter_rules()}
        check("Route GET /api/v1/homework registriert",
              "/api/v1/homework" in rules)
        check("Route POST done registriert",
              "/api/v1/homework/<event_id>/done" in rules)
        check("Route POST trash registriert",
              "/api/v1/homework/<event_id>/trash" in rules)

        r = client.get("/api/v1/homework")
        check("ohne Token 401 TOKEN_INVALID",
              r.status_code == 401
              and r.get_json().get("code") == "TOKEN_INVALID")

        r = client.get("/api/v1/homework", headers=auth,
                       query_string={"limit": "0"})
        check("bad limit 400 VALIDATION",
              r.status_code == 400
              and r.get_json().get("code") == "VALIDATION")
        r = client.get("/api/v1/homework", headers=auth,
                       query_string={"status": "falsch"})
        check("bad status 400 VALIDATION",
              r.status_code == 400
              and r.get_json().get("code") == "VALIDATION")
        r = client.get("/api/v1/homework", headers=auth,
                       query_string={"since": "kein-datum"})
        check("bad since 400 VALIDATION",
              r.status_code == 400
              and r.get_json().get("code") == "VALIDATION")

        # Liste ohne Tests: 4 Hausaufgaben (bexam 104 fehlt).
        r = client.get("/api/v1/homework", headers=auth)
        body = r.get_json()
        check("Liste 200 mit Hülle",
              r.status_code == 200
              and set(("items", "total", "limit", "offset"))
              <= set(body.keys()))
        check("Liste total 4 ohne Tests", body["total"] == 4)
        check("Zähler ohne Tests",
              body["counts"] == {"offen": 1, "ueberfaellig": 1,
                                 "erledigt": 1, "papierkorb": 0})
        ids = [i["id"] for i in body["items"]]
        check("Sortierung überfällig zuerst, erledigt danach",
              ids == [101, 102, 105, 103])
        check("Antwort nutzt Hausaufgaben-Bauer",
              all("due_display" in i and "status" in i
                  for i in body["items"]))
        check("Erster Fetch genau 1 API-Zugriff", FakeEdupage.calls == 1)

        # Zweiter Aufruf kommt aus dem Cache (kein neuer Zugriff).
        r2 = client.get("/api/v1/homework", headers=auth)
        check("Cache-Wiederverwendung (kein neuer Fetch)",
              r2.status_code == 200 and FakeEdupage.calls == 1)

        # Mit Tests: bexam 104 kommt dazu, offen steigt auf 2.
        r = client.get("/api/v1/homework", headers=auth,
                       query_string={"include_tests": "1"})
        body = r.get_json()
        check("mit Tests total 5", body["total"] == 5)
        check("mit Tests offen 2", body["counts"]["offen"] == 2)

        # Statusfilter wie im Web.
        r = client.get("/api/v1/homework", headers=auth,
                       query_string={"status": "offen"})
        check("offen enthält offen + ohne Datum",
              r.get_json()["total"] == 2)
        r = client.get("/api/v1/homework", headers=auth,
                       query_string={"status": "überfällig"})
        b = r.get_json()
        check("überfällig genau 101",
              b["total"] == 1 and b["items"][0]["id"] == 101)
        r = client.get("/api/v1/homework", headers=auth,
                       query_string={"status": "erledigt"})
        check("erledigt genau 103",
              r.get_json()["total"] == 1
              and r.get_json()["items"][0]["id"] == 103)
        r = client.get("/api/v1/homework", headers=auth,
                       query_string={"status": "papierkorb"})
        check("Papierkorb anfangs leer", r.get_json()["total"] == 0)

        # Paginierung.
        r = client.get("/api/v1/homework", headers=auth,
                       query_string={"limit": "2", "offset": "0"})
        b = r.get_json()
        check("Seite 1 mit total",
              b["total"] == 4 and len(b["items"]) == 2
              and b["limit"] == 2 and b["offset"] == 0)
        r = client.get("/api/v1/homework", headers=auth,
                       query_string={"limit": "2", "offset": "2"})
        b = r.get_json()
        check("Seite 2 Rest",
              b["total"] == 4 and len(b["items"]) == 2
              and [i["id"] for i in b["items"]] == [105, 103])

        # Erledigt-Markierung ist nach erneutem Laden sichtbar.
        r = client.post("/api/v1/homework/102/done", headers=auth,
                        json={"done": True})
        check("done 200 mit Ressource",
              r.status_code == 200 and r.get_json().get("id") == 102
              and r.get_json().get("is_done") is True)
        r = client.get("/api/v1/homework", headers=auth,
                       query_string={"status": "erledigt"})
        ids = sorted(i["id"] for i in r.get_json()["items"])
        check("102 nach done unter erledigt", ids == [102, 103])
        r = client.post("/api/v1/homework/102/done", headers=auth,
                        json={"done": False})
        check("reopen 200 offen",
              r.status_code == 200
              and r.get_json().get("is_done") is False)
        r = client.get("/api/v1/homework", headers=auth,
                       query_string={"status": "offen"})
        check("102 nach reopen wieder offen",
              102 in [i["id"] for i in r.get_json()["items"]])

        # Papierkorb rein/raus, Zurückholen markiert als offen.
        r = client.post("/api/v1/homework/105/trash", headers=auth,
                        json={"hide": True})
        check("trash hide 200 mit Flag",
              r.status_code == 200
              and r.get_json().get("is_hidden") is True)
        r = client.get("/api/v1/homework", headers=auth,
                       query_string={"status": "papierkorb"})
        check("Papierkorb enthält 105",
              r.get_json()["total"] == 1
              and r.get_json()["items"][0]["id"] == 105)
        r = client.get("/api/v1/homework", headers=auth)
        b = r.get_json()
        check("alle mit Papierkorb ans Ende",
              b["total"] == 4 and b["items"][-1]["id"] == 105
              and b["counts"]["papierkorb"] == 1)
        done_calls.clear()
        r = client.post("/api/v1/homework/105/trash", headers=auth,
                        json={"hide": False})
        check("restore 200 eingeblendet",
              r.status_code == 200
              and r.get_json().get("is_hidden") is False)
        check("restore markiert als offen (Server-Call)",
              ("105", False) in done_calls)
        r = client.get("/api/v1/homework", headers=auth,
                       query_string={"status": "papierkorb"})
        check("Papierkorb nach restore leer",
              r.get_json()["total"] == 0)

        # Fehlerfälle.
        r = client.post("/api/v1/homework/999/done", headers=auth,
                        json={"done": True})
        check("done unbekannt 404 NOT_FOUND",
              r.status_code == 404
              and r.get_json().get("code") == "NOT_FOUND")
        r = client.post("/api/v1/homework/999/trash", headers=auth,
                        json={"hide": True})
        check("trash unbekannt 404 NOT_FOUND",
              r.status_code == 404
              and r.get_json().get("code") == "NOT_FOUND")
        r = client.post("/api/v1/homework/102/done", headers=auth,
                        data="kein-json", content_type="text/plain")
        check("done ohne JSON 400 VALIDATION",
              r.status_code == 400
              and r.get_json().get("code") == "VALIDATION")

        def _boom(edupage, event_id, done):
            raise RuntimeError("EduPage kaputt")

        A.set_homework_done = _boom
        r = client.post("/api/v1/homework/102/done", headers=auth,
                        json={"done": True})
        check("Serverfehler 502 UPSTREAM",
              r.status_code == 502
              and r.get_json().get("code") == "UPSTREAM")
        A.set_homework_done = fake_done
    finally:
        A.do_login = orig_login
        A.set_homework_done = orig_done
        core.revoke_token(token)
        _clean_test_cache(uhash)

    print("Alle Homework-Tests bestanden.")


if __name__ == "__main__":
    main()
