"""End-zu-End-Abnahme des API-Backends v1 (BACKEND.md Abschnitt 11).

Lauf: `python tests/test_api_e2e.py`. Komplett offline ohne echte
Zugangsdaten: Der EduPage-Login ist attrappiert, alle Listen kommen aus
Fixture-Caches im bestehenden Format.

Ablauf: Anmelden (normal + simulierte 2FA-Pflicht), jede Liste mit
Paginierung, je ein Schreibaufruf pro Paket (senden, erledigt, speichern,
Cache leeren, abmelden), Abmelden mit anschließend abgelehntem Token, und
der Nachweis, dass alle Web-Seiten unverändert rendern.
"""

import copy
import json
import sys
from datetime import date, datetime, timedelta
from pathlib import Path
from types import SimpleNamespace

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import cache as apicache
import app as A
from api import core

SUBDOMAIN = "schule"
USERNAME = "nutzer"


def check(name, cond):
    print(("OK  " if cond else "FEHLER ") + name)
    if not cond:
        raise SystemExit(f"Test fehlgeschlagen: {name}")


def mk_event(event_id, type_value, text, day, hour=10, extra=None):
    return SimpleNamespace(
        event_id=event_id,
        timestamp=datetime(2026, 9, day, hour, 0, 0),
        text=text, author="F. Lehrer", recipient="Ich",
        event_type=SimpleNamespace(value=type_value),
        additional_data=extra or {},
        is_starred=False, is_done=False, done_at=None,
        reaction_count=0, created_at=None, is_removed=False)


class _FakeResp:
    def __init__(self, status, payload):
        self.status_code = status
        self._payload = payload

    def json(self):
        return dict(self._payload)


class _FakeSession:
    def post(self, url, data=None, headers=None, timeout=None):
        if "homeworkFlag" in str(url):
            return _FakeResp(200, {"timelineUserProps": {}})
        raise AssertionError("Unerwarteter POST: " + str(url))


class _FakeAccount:
    def __init__(self, rid, name):
        self._rid = rid
        self.name = name

    def get_id(self):
        return self._rid


class _FakeEdupage:
    subdomain = SUBDOMAIN

    def __init__(self):
        self.events = []
        self.session = _FakeSession()

    def get_notification_history(self, since):
        return list(self.events)

    def get_my_timetable(self, day):
        raise AssertionError("Stundenplan-Fixture fehlt für " + str(day))

    def get_teachers(self):
        return [_FakeAccount("Teacher7", "B. Beispiel")]

    def get_students(self):
        return [_FakeAccount("Student42", "A. Muster")]

    def send_message(self, recipients, body):
        ev = mk_event(9001, "sprava", body, 24, 12)
        self.events.append(ev)
        return 9001


class _Fake2FA:
    def finish_with_code(self, code):
        if str(code) != "123456":
            raise RuntimeError("falscher Code")


def mk_grade():
    return SimpleNamespace(
        event_id=301, title="Vokabeltest", grade_n=2.0, comment="",
        date=datetime(2026, 9, 10, 10, 0, 0), subject_id=1,
        subject_name="Mathe", teacher=SimpleNamespace(name="L. Lehr"),
        max_points=None, more_details=None, importance=1.0,
        verbal=False, percent=None, class_grade_avg=2.5)


def raw_lesson():
    return {"period": "1", "time": "07:45–08:30", "title": "Mathe",
            "is_lernzeit": False, "teachers": "F. Lehrer", "rooms": "R1",
            "is_cancelled": False, "is_event": False, "is_online": False}


def essen_fixture():
    days = {}
    for name in ("Montag", "Dienstag", "Mittwoch", "Donnerstag",
                 "Freitag"):
        days[name] = {"date": "2026-09-2%d" % (["Montag", "Dienstag",
                      "Mittwoch", "Donnerstag",
                      "Freitag"].index(name) + 1),
                      "dishes": [{"text": "Nudeln", "price": "7,90 €"}],
                      "note": ""}
    return {"week": "2026-W39", "label": "21.9. – 25.9.2026",
            "source_url": "https://example.org/plan.pdf", "days": days,
            "today": "Montag"}


def seed_timeline(uhash, events):
    apicache.save_timeline(
        uhash, "2026-01-01",
        [apicache.event_to_record(e) for e in events])


def seed_all(uhash, fake):
    from datetime import timedelta
    seed_timeline(uhash, fake.events)
    apicache.save_grades(uhash, [A.grade_to_dict(mk_grade())])
    monday = date.today() - timedelta(days=date.today().weekday())
    for i in range(5):
        apicache.save_timetable(uhash, monday + timedelta(days=i),
                                [raw_lesson()])


def rm(path):
    try:
        Path(path).unlink()
    except OSError:
        pass


def main():
    A.app.config["TESTING"] = True
    client = A.app.test_client()
    uhash = apicache.user_hash(SUBDOMAIN, USERNAME)

    fake = _FakeEdupage()
    fake.events = [
        mk_event(101, "sprava", "Elternabend am Freitag", 22),
        mk_event(102, "news", "Ausflug ins Museum", 23),
        mk_event(103, "sprava", "Alles klar", 23, 11,
                 {"textReply": "danke"}),
        mk_event(201, "homework", "Seite 42", 21, 9,
                 {"oldVals": {"title": "Vokabeln",
                              "date": "2026-09-25"}}),
    ]
    seed_all(uhash, fake)

    import essen as essenplan
    week_key = essenplan.week_key(date.today())
    essen_path = essenplan.CACHE_DIR / ("essen_%s.json" % week_key)
    essen_backup = None
    if essen_path.is_file():
        essen_backup = essen_path.read_bytes()
    with open(essen_path, "w", encoding="utf-8") as f:
        json.dump({"version": 1,
                   "saved_at": datetime.now()
                   .strftime("%Y-%m-%d %H:%M:%S"),
                   "data": essen_fixture()}, f, ensure_ascii=False)

    orig_login = A.do_login
    orig_wetter = A.get_wetter_payload
    pending = None
    A.do_login = lambda u, p, s: (fake, None, SUBDOMAIN)
    A.get_wetter_payload = lambda lat, lon, city: (
        {"error": "Kein API-Key"}, 503)
    tokens = []
    try:
        # ---- Anmelden (Paket A) ----------------------------------
        r = client.post("/api/v1/auth/login",
                        json={"username": USERNAME, "password": "geheim",
                              "subdomain": SUBDOMAIN})
        body = r.get_json()
        check("Login 200 mit Token",
              r.status_code == 200 and body["status"] == "ok"
              and body["token"] and body["username"] == USERNAME)
        tokens.append(body["token"])
        auth = {"Authorization": "Bearer " + body["token"]}
        r = client.get("/api/v1/me", headers=auth)
        check("me liefert Inhaber",
              r.status_code == 200
              and r.get_json() == {"subdomain": SUBDOMAIN,
                                   "username": USERNAME})

        # ---- Simulierte 2FA-Pflicht -------------------------------
        A.do_login = lambda u, p, s: (fake, _Fake2FA(), SUBDOMAIN)
        r = client.post("/api/v1/auth/login",
                        json={"username": USERNAME, "password": "geheim",
                              "subdomain": SUBDOMAIN})
        body = r.get_json()
        check("Login mit 2FA meldet Zwischenstatus",
              r.status_code == 200 and body["status"] == "2fa_required"
              and body["pending_token"])
        pending = body["pending_token"]
        r = client.post("/api/v1/auth/2fa",
                        json={"pending_token": pending, "code": "000000"})
        check("falscher Code 401 INVALID_CODE",
              r.status_code == 401
              and r.get_json()["code"] == "INVALID_CODE")
        r = client.post("/api/v1/auth/2fa",
                        json={"pending_token": pending, "code": "123456"})
        body = r.get_json()
        check("richtiger Code tauscht zu Token",
              r.status_code == 200 and body["status"] == "ok"
              and body["token"])
        tokens.append(body["token"])
        A.do_login = lambda u, p, s: (fake, None, SUBDOMAIN)

        # ---- Nachrichten (Paket B): Liste mit Paginierung ---------
        r = client.get("/api/v1/messages?limit=1&offset=0", headers=auth)
        body = r.get_json()
        check("Nachrichtenliste paginiert (total 2, Seite 1)",
              r.status_code == 200 and body["total"] == 2
              and len(body["items"]) == 1 and body["limit"] == 1
              and body["offset"] == 0)
        r = client.get("/api/v1/messages?limit=1&offset=1", headers=auth)
        check("Nachrichtenliste Seite 2",
              len(r.get_json()["items"]) == 1)
        r = client.get("/api/v1/messages?type=news", headers=auth)
        check("Typfilter news genau eine",
              r.get_json()["total"] == 1)
        r = client.get("/api/v1/messages?q=elternabend", headers=auth)
        check("Textsuche findet Elternabend",
              r.get_json()["total"] == 1)
        r = client.get("/api/v1/messages/101/thread", headers=auth)
        check("Thread ohne Eintrag 502 UPSTREAM (offline)",
              r.status_code == 502
              and r.get_json()["code"] == "UPSTREAM")
        apicache.save_likes(uhash, 101,
                            {"likes": [{"name": "A. Muster",
                                        "date": "24.09.2026 10:00"}],
                             "replies": [], "reply_ids": [],
                             "summary": {"total": 1, "likes": 1,
                                         "replies": 0, "seen": 0}})
        r = client.get("/api/v1/messages/101/thread", headers=auth)
        body = r.get_json()
        check("Thread aus Cache mit Like",
              r.status_code == 200 and len(body["likes"]) == 1
              and body["cached"] is True)
        r = client.get("/api/v1/recipients", headers=auth)
        body = r.get_json()
        check("Empfängerliste Lehrer + Schüler",
              r.status_code == 200 and body["total"] == 2)

        # ---- Hausaufgaben (Paket C): Liste mit Paginierung --------
        r = client.get("/api/v1/homework?limit=1", headers=auth)
        body = r.get_json()
        check("Hausaufgabenliste mit Zählern",
              r.status_code == 200 and body["total"] == 1
              and body["counts"]["offen"] == 1)

        # ---- Stundenplan (Paket D) --------------------------------
        today = date.today().isoformat()
        r = client.get("/api/v1/timetable/day?day=" + today,
                       headers=auth)
        body = r.get_json()
        check("Tagesansicht Mathe aus Cache",
              r.status_code == 200 and body["day"] == today
              and body["lessons"][0]["title"] == "Mathe")
        r = client.get("/api/v1/timetable/week?day=" + today,
                       headers=auth)
        body = r.get_json()
        check("Wochenansicht 5 Tage mit Bezeichnung",
              r.status_code == 200 and len(body["days"]) == 5
              and body["week_label"].startswith("Woche "))

        # ---- Noten (Paket E): Liste mit Paginierung ---------------
        r = client.get("/api/v1/grades?limit=1", headers=auth)
        body = r.get_json()
        check("Notenliste paginiert aus Cache",
              r.status_code == 200 and body["total"] == 1
              and body["items"][0]["subject"] == "Mathe")

        # ---- Essen und Wetter (Paket F) ----------------------------
        r = client.get("/api/v1/essen", headers=auth)
        body = r.get_json()
        check("Essen 5 Tage mit Preis",
              r.status_code == 200 and len(body.get("days", {})) == 5
              and "7,90" in json.dumps(body, ensure_ascii=False))
        r = client.get("/api/v1/wetter", headers=auth)
        check("Wetter ohne Ort 400 VALIDATION",
              r.status_code == 400
              and r.get_json()["code"] == "VALIDATION")
        r = client.get("/api/v1/wetter?city=Berlin", headers=auth)
        check("Wetter ohne Schlüssel 503 CONFIG_MISSING",
              r.status_code == 503
              and r.get_json()["code"] == "CONFIG_MISSING")

        # ---- Schreibaufrufe ---------------------------------------
        r = client.post("/api/v1/messages/send", headers=auth,
                        json={"recipients": ["Teacher7"],
                              "body": "Hallo aus der Abnahme"})
        body = r.get_json()
        check("Senden liefert Ressource mit neuem Text",
              r.status_code == 200 and "Abnahme" in body.get("text", ""))
        r = client.get("/api/v1/messages", headers=auth)
        check("Gesendete Nachricht in der Liste",
              r.get_json()["total"] == 3)

        r = client.post("/api/v1/messages/read", headers=auth)
        check("Als gelesen markiert (101, 102, 103 + gesendete 9001)",
              r.status_code == 200
              and r.get_json()["marked"] == 4)

        r = client.post("/api/v1/homework/201/done", headers=auth,
                        json={"done": True})
        body = r.get_json()
        check("Erledigt-Markierung sichtbar",
              r.status_code == 200 and body.get("is_done") is True)
        r = client.post("/api/v1/homework/201/done", headers=auth,
                        json={"done": False})
        check("Wieder geöffnet",
              r.status_code == 200
              and r.get_json().get("is_done") is False)

        r = client.put("/api/v1/settings", headers=auth,
                       json={"landing": "noten", "ov_unread": 9999})
        check("Einstellungen speichern 200",
              r.status_code == 200)
        r = client.get("/api/v1/settings", headers=auth)
        body = r.get_json()
        check("Einstellungen gelesen, ungültig auf Default (50)",
              body["values"]["landing"] == "noten"
              and body["values"]["ov_unread"] == 50)

        r = client.post("/api/v1/cache-clear", headers=auth)
        body = r.get_json()
        check("Cache leeren meldet Anzahl",
              r.status_code == 200 and body.get("cleared", 0) >= 1)
        r = client.get("/api/v1/settings", headers=auth)
        check("Einstellungen bleiben bei Cache leeren erhalten",
              r.get_json()["values"]["landing"] == "noten")

        # ---- Abmelden ----------------------------------------------
        # Startseite zurück auf Übersicht (sonst leitet / zu /noten um;
        # muss vor dem Logout passieren, danach ist das Token ungültig).
        client.put("/api/v1/settings", headers=auth,
                   json={"landing": "uebersicht"})
        r = client.post("/api/v1/auth/logout", headers=auth)
        check("Logout mit Status ok",
              r.status_code == 200 and r.get_json() == {"status": "ok"})
        r = client.get("/api/v1/me", headers=auth)
        check("nach Logout ist Token ungültig",
              r.status_code == 401
              and r.get_json()["code"] == "TOKEN_INVALID")

        # ---- Web-Seiten rendern unverändert -------------------------
        seed_all(uhash, fake)  # Cache leeren hat sie weggewischt
        apicache.save_likes(uhash, 101, {"likes": [], "replies": [],
                                         "summary": {}})
        web = A.app.test_client()
        with web.session_transaction() as sess:
            sess["username"] = USERNAME
            sess["subdomain"] = SUBDOMAIN
            sess["pwd_enc"] = A._fernet().encrypt(b"geheim").decode()
        for path in ("/", "/dashboard", "/hausaufgaben", "/noten",
                     "/stundenplan", "/einstellungen"):
            r = web.get(path)
            check("Web-Seite rendert: " + path, r.status_code == 200)
        plain = A.app.test_client()
        r = plain.get("/")
        check("Login-Seite ohne Sitzung 200 mit Anmeldeformular",
              r.status_code == 200 and "Anmelden" in r.get_data(True))
        r = plain.get("/dashboard", follow_redirects=False)
        check("Nachrichten ohne Sitzung leiten zu /",
              r.status_code == 302)
    finally:
        A.do_login = orig_login
        A.get_wetter_payload = orig_wetter
        if pending:
            A.PENDING_2FA.pop(pending, None)
        for token in tokens:
            core.revoke_token(token)
        rm(apicache.CACHE_DIR / ("timeline_%s.json" % uhash))
        rm(apicache.CACHE_DIR / ("grades_%s.json" % uhash))
        monday = date.today() - timedelta(days=date.today().weekday())
        for i in range(5):
            rm(apicache.CACHE_DIR / ("timetable_%s_%s.json"
                                     % (uhash, (monday
                                                + timedelta(days=i))
                                        .isoformat())))
        rm(apicache.CACHE_DIR / ("likes_%s.json" % uhash))
        rm(apicache.CACHE_DIR / ("seen_%s.json" % uhash))
        rm(apicache.CACHE_DIR / ("hidden_%s.json" % uhash))
        rm(apicache.CACHE_DIR / ("settings_%s.json" % uhash))
        if essen_backup is not None:
            essen_path.write_bytes(essen_backup)
        else:
            rm(essen_path)

    print("End-zu-End-Abnahme bestanden.")


if __name__ == "__main__":
    main()
