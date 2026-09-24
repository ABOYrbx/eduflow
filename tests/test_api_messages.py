"""Tests für das API-Paket B (Nachrichten und Threads). Offline.

Lauf: `python tests/test_api_messages.py` (oder per pytest, falls vorhanden).
Nutzt einen Fixture-Timeline-Cache für einen Testnutzer, ein gemocktes
EduPage-Objekt (kein Netzwerk) und räumt alle Fixture-Dateien danach weg.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from flask import Flask

import cache as apicache
from api import bp as api_bp
from api import core
from api import messages as msgmod


SUBDOMAIN = "testschule"
USERNAME = "testnutzer"
UHASH = apicache.user_hash(SUBDOMAIN, USERNAME)


def check(name, cond):
    print(("OK  " if cond else "FEHLER ") + name)
    if not cond:
        raise SystemExit("Test fehlgeschlagen: %s" % name)


def rec(eid, ts, etype, text, author="Lehrer L", extra=None):
    return {"id": eid, "timestamp": ts, "text": text,
            "author": author, "recipient": "Klasse 1",
            "type": etype, "additional_data": extra or {},
            "is_starred": False, "is_done": False, "done_at": "",
            "reaction_count": 0, "created_at": ts, "is_removed": False}


# Fixture: 101 + 104 + 105 Top-Level-Nachrichten, 102 Antwort (textReply),
# 103 Hausaufgabe. 104 mit EduPage-Anhang, 105 mit fremder Adresse.
RECORDS = [
    rec(101, "2024-05-01 10:00:00", "sprava", "Elternabend am Freitag"),
    rec(102, "2024-05-02 11:00:00", "sprava", "Antwort im Thread",
        extra={"textReply": "Danke für die Info!"}),
    rec(103, "2024-05-03 12:00:00", "homework", "Hausaufgabe Mathe"),
    rec(104, "2024-05-04 13:00:00", "news", "Ausflugsmaterial als PDF",
        extra={"filename": "Test.pdf", "file": "/cloud/test.pdf"}),
    rec(105, "2024-05-05 14:00:00", "sprava", "Fremder Anhang",
        extra={"filename": "X.bin", "file": "https://evil.com/x.pdf"}),
]
NEW_RECORD = rec(999, "2024-06-01 09:00:00", "sprava", "Hallo vom Test")


class FakeAccount(object):
    def __init__(self, rid, name):
        self._rid = rid
        self.name = name

    def get_id(self):
        return self._rid


class FakeUpstream(object):
    status_code = 200
    headers = {"Content-Type": "text/plain"}

    def iter_content(self, chunk_size=65536):
        yield b"datei-inhalt"


class FakeSession(object):
    def __init__(self):
        self.last_url = None

    def get(self, url, stream=True, timeout=30):
        self.last_url = url
        return FakeUpstream()


class FakeEdupage(object):
    """Gemocktes EduPage-Objekt (kein Netzwerk)."""

    def __init__(self):
        self.subdomain = SUBDOMAIN
        self.session = FakeSession()
        self.sent = []
        self.include_new = False

    def get_notification_history(self, since):
        records = list(RECORDS)
        if self.include_new:
            records = records + [NEW_RECORD]
        return [apicache.record_to_event(r) for r in records]

    def send_message(self, recipients, body):
        self.sent.append((list(recipients), body))
        self.include_new = True
        return 999

    def get_teachers(self):
        return [FakeAccount("Teacher7", "Lehrer L")]

    def get_students(self):
        return [FakeAccount("Student9", "Schüler S")]


THREAD_FIXTURE = {
    "likes": [{"name": "Anna A", "date": "01.05.2024 10:05"}],
    "replies": [{"name": "Schüler S", "date": "02.05.2024 11:00",
                 "text": "Danke für die Info!"}],
    "reply_ids": ["102"],
    "summary": {"total": 2, "likes": 1, "replies": 1, "seen": 0},
}


def main():
    fake = FakeEdupage()
    real_login = msgmod._api_login
    msgmod._api_login = lambda: (fake, SUBDOMAIN, USERNAME)

    import app as webapp
    real_likes = webapp.get_message_likes
    real_reply = webapp.send_reply
    webapp.get_message_likes = lambda ed, eid: dict(THREAD_FIXTURE)
    replied = []
    webapp.send_reply = lambda ed, gid, text: replied.append((gid, text)) or {}

    mini = Flask(__name__)
    mini.register_blueprint(api_bp)
    client = mini.test_client()

    created = core.create_token(SUBDOMAIN, USERNAME, "geheim")
    token = created["token"]
    auth = {"Authorization": "Bearer %s" % token}

    apicache.save_timeline(UHASH, "2024-01-01", list(RECORDS))

    try:
        # --- Auth-Schutz
        r = client.get("/api/v1/messages")
        check("ohne Token 401 TOKEN_INVALID",
              r.status_code == 401
              and r.get_json()["code"] == "TOKEN_INVALID")

        # --- Liste: nur Top-Level-Nachrichten, neueste zuerst
        r = client.get("/api/v1/messages", headers=auth)
        body = r.get_json()
        check("Liste 200 mit Hüllobjekt",
              r.status_code == 200
              and body["total"] == 3 and body["limit"] == 50
              and body["offset"] == 0)
        ids = [m["id"] for m in body["items"]]
        check("Antwort (102) und Hausaufgabe (103) ausgeschlossen",
              ids == [105, 104, 101])
        check("Serializer aus dem Web (event_to_dict)",
              body["items"][0]["type"] == "sprava"
              and "timestamp_iso" in body["items"][0]
              and "type_label" in body["items"][0])

        # --- Filter + Suche + Paginierung
        r = client.get("/api/v1/messages?type=sprava", headers=auth)
        check("Typfilter sprava",
              [m["id"] for m in r.get_json()["items"]] == [105, 101])
        r = client.get("/api/v1/messages?type=xxx", headers=auth)
        check("unbekannter Typ 400 VALIDATION",
              r.status_code == 400
              and r.get_json()["code"] == "VALIDATION")
        r = client.get("/api/v1/messages?q=elternabend", headers=auth)
        check("Textsuche (case-insensitiv)",
              [m["id"] for m in r.get_json()["items"]] == [101])
        r = client.get("/api/v1/messages?q=Elternabend Freitag", headers=auth)
        check("Mehrwortsuche (UND)",
              [m["id"] for m in r.get_json()["items"]] == [101])
        r = client.get("/api/v1/messages?q=elternabend+mathe", headers=auth)
        check("Suche ohne Treffer total 0",
              r.get_json()["total"] == 0)
        r = client.get("/api/v1/messages?since=2025-01-01", headers=auth)
        check("Zeitraumfilter seit 2025 leer",
              r.get_json()["total"] == 0)
        r = client.get("/api/v1/messages?since=kein-datum", headers=auth)
        check("ungültiges Datum 400 VALIDATION",
              r.status_code == 400
              and r.get_json()["code"] == "VALIDATION")
        r = client.get("/api/v1/messages?limit=1&offset=1", headers=auth)
        body = r.get_json()
        check("Paginierung mit Gesamtzahl",
              body["total"] == 3 and body["limit"] == 1
              and body["offset"] == 1
              and [m["id"] for m in body["items"]] == [104])
        r = client.get("/api/v1/messages?limit=0", headers=auth)
        check("ungültiges Limit 400 VALIDATION",
              r.status_code == 400
              and r.get_json()["code"] == "VALIDATION")

        # --- Thread aus dem Cache
        apicache.save_likes(UHASH, 101, dict(THREAD_FIXTURE))
        r = client.get("/api/v1/messages/101/thread", headers=auth)
        body = r.get_json()
        check("Thread aus Cache (Likes + Antworten)",
              r.status_code == 200 and body["cached"] is True
              and len(body["likes"]) == 1 and len(body["replies"]) == 1
              and body["reply_ids"] == ["102"]
              and body["summary"]["total"] == 2)

        # --- Thread frisch (refresh=1 nutzt Web-Helfer)
        r = client.get("/api/v1/messages/101/thread?refresh=1", headers=auth)
        body = r.get_json()
        check("Thread refresh=1 cached False",
              r.status_code == 200 and body["cached"] is False
              and body["summary"]["replies"] == 1)

        # --- Gelesen-Markierung (Web-Logik, alle Nachrichtentypen)
        r = client.post("/api/v1/messages/read", headers=auth)
        check("als gelesen: 4 markiert",
              r.status_code == 200 and r.get_json() == {"marked": 4})
        r = client.post("/api/v1/messages/read", headers=auth)
        check("erneut gelesen: 0 markiert",
              r.get_json() == {"marked": 0})

        # --- Empfängerliste
        r = client.get("/api/v1/recipients", headers=auth)
        body = r.get_json()
        check("Empfänger mit Hüllobjekt",
              r.status_code == 200 and body["total"] == 2
              and body["items"][0]["name"] == "Lehrer L"
              and body["items"][1]["id"] == "Student9")

        # --- Senden: Validierung
        r = client.post("/api/v1/messages/send", headers=auth, json={})
        check("Senden ohne alles 400 VALIDATION",
              r.status_code == 400)
        r = client.post("/api/v1/messages/send", headers=auth,
                        json={"recipients": ["Teacher7"], "body": "   "})
        check("Senden ohne Text 400 VALIDATION",
              r.status_code == 400)
        r = client.post("/api/v1/messages/send", headers=auth,
                        json={"recipients": ["nonsens"], "body": "Hi"})
        check("Senden mit falscher ID 400 VALIDATION",
              r.status_code == 400)

        # --- Senden: Erfolg gibt Ressource zurück
        r = client.post("/api/v1/messages/send", headers=auth,
                        json={"recipients": ["Teacher7"], "body": "Hallo!"})
        body = r.get_json()
        check("Senden liefert Nachricht #999",
              r.status_code == 200 and body["id"] == 999
              and body["text"] == "Hallo vom Test")
        check("Sende-Helfer mit ID und Text aufgerufen",
              fake.sent == [(["Teacher7"], "Hallo!")])

        # --- Antworten: Validierung + Erfolg mit Thread
        r = client.post("/api/v1/messages/101/reply", headers=auth, json={})
        check("Antwort ohne Text 400 VALIDATION",
              r.status_code == 400)
        r = client.post("/api/v1/messages/101/reply", headers=auth,
                        json={"body": "Verstanden, danke!"})
        body = r.get_json()
        check("Antwort liefert Thread mit Antwort",
              r.status_code == 200 and len(body["replies"]) == 1
              and body["cached"] is False)
        check("Antwort-Helfer mit Gruppen-ID aufgerufen",
              replied == [(101, "Verstanden, danke!")])

        # --- Download: ohne Token abgewiesen
        r = client.get("/api/v1/messages/104/attachments/0")
        check("Download ohne Token 401 TOKEN_INVALID",
              r.status_code == 401
              and r.get_json()["code"] == "TOKEN_INVALID")

        # --- Download: per ?token= mit Dateiname
        r = client.get("/api/v1/messages/104/attachments/0?token=%s" % token)
        check("Download per Query-Token 200 mit Dateiname",
              r.status_code == 200
              and r.data == b"datei-inhalt"
              and "Test.pdf" in r.headers.get("Content-Disposition", ""))
        check("Proxy ruft EduPage-Adresse auf",
              fake.session.last_url == "https://testschule.edupage.org/cloud/test.pdf")

        # --- Download: fremde Adresse und Fehlfälle
        r = client.get("/api/v1/messages/105/attachments/0", headers=auth)
        check("fremde Adresse 400 VALIDATION",
              r.status_code == 400
              and r.get_json()["code"] == "VALIDATION")
        r = client.get("/api/v1/messages/104/attachments/7", headers=auth)
        check("falscher Index 404 NOT_FOUND",
              r.status_code == 404
              and r.get_json()["code"] == "NOT_FOUND")
        r = client.get("/api/v1/messages/4242/attachments/0", headers=auth)
        check("falsche ID 404 NOT_FOUND",
              r.status_code == 404
              and r.get_json()["code"] == "NOT_FOUND")

        print("Alle Nachrichten-Tests bestanden.")
    finally:
        msgmod._api_login = real_login
        webapp.get_message_likes = real_likes
        webapp.send_reply = real_reply
        core.revoke_token(token)
        for name in ("timeline_%s.json" % UHASH,
                     "likes_%s.json" % UHASH,
                     "seen_%s.json" % UHASH):
            try:
                (apicache.CACHE_DIR / name).unlink()
            except OSError:
                pass


if __name__ == "__main__":
    main()
