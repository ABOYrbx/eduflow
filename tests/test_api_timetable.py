"""Tests für das API-Stundenplan-Paket (Paket D). Offline, ohne Zugangsdaten.

Lauf: `python tests/test_api_timetable.py`. Der EduPage-Login wird
attrappiert; Stunden kommen aus Fixture-Caches im bestehenden Format
(einmal direkt geseedet, einmal über den Aktualisierungsschalter aus
einem Fake-Stundenplan). Geprüft werden Routenform, Fehlercodes,
Lernzeit-Blöcke, Entfall-/Online-Kennzeichen, Wochenstruktur und
Cache-Wiederverwendung (kein EduPage-Aufruf bei frischem Cache).
"""

import copy
import sys
from datetime import date, time, timedelta
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


def raw_lesson(period, time_range, title, lernzeit=False,
               cancelled=False, online=False, event=False):
    return {"period": period, "time": time_range, "title": title,
            "is_lernzeit": lernzeit, "teachers": "F. Lehrer",
            "rooms": "R1", "is_cancelled": cancelled,
            "is_event": event, "is_online": online}


# Rohstunden wie aus dem Stunden-Bauer: zwei aufeinanderfolgende
# Lernzeit-Stunden (werden zu einem Block), eine entfallene und eine
# Online-Stunde.
SEED_RAW = [
    raw_lesson("1", "07:45–08:30", "Mathe"),
    raw_lesson("2", "08:35–09:20", "Lernzeit", lernzeit=True),
    raw_lesson("3", "09:35–10:20", "Lernzeit", lernzeit=True),
    raw_lesson("4", "10:25–11:10", "Englisch", cancelled=True),
    raw_lesson("5", "11:15–12:00", "Physik", online=True),
]


class _Named:
    def __init__(self, name):
        self.name = name


def fake_lesson(title, period, start, end, cancelled=False,
                event=False, online=False):
    return SimpleNamespace(
        subject=SimpleNamespace(name=title), curriculum="",
        teachers=[_Named("F. Lehrer")], classrooms=[_Named("R1")],
        period=period, start_time=time(*start), end_time=time(*end),
        is_cancelled=cancelled, is_event=event,
        online_lesson_link="https://meet.example/x" if online else None)


# Fake-Stundenplan für den Aktualisierungspfad: wie SEED_RAW plus ein
# ganztägiges Event (ohne Stundennummer) – das fällt in der Woche weg,
# bleibt am Tag aber sichtbar (wie im Web).
FAKE_LESSONS = [
    fake_lesson("Mathe", 1, (7, 45), (8, 30)),
    fake_lesson("Lernzeit", 2, (8, 35), (9, 20)),
    fake_lesson("Lernzeit", 3, (9, 35), (10, 20)),
    fake_lesson("Englisch", 4, (10, 25), (11, 10), cancelled=True),
    fake_lesson("Physik", 5, (11, 15), (12, 0), online=True),
    fake_lesson("Projekttag", None, (0, 0), (0, 0), event=True),
]


class _NoCallEdupage:
    """Attrappe, die bei jedem Stundenplan-Zugriff laut scheitert."""
    subdomain = SUBDOMAIN

    def get_my_timetable(self, day):
        raise AssertionError(
            "EduPage darf bei frischem Cache nicht aufgerufen werden")


class _FakeEdupage:
    subdomain = SUBDOMAIN

    def __init__(self):
        self.calls = []

    def get_my_timetable(self, day):
        self.calls.append(day)
        return SimpleNamespace(lessons=list(FAKE_LESSONS))


def week_monday():
    return date.today() - timedelta(days=date.today().weekday())


def main():
    A.app.config["TESTING"] = True
    client = A.app.test_client()
    uhash = apicache.user_hash(SUBDOMAIN, USERNAME)
    monday = week_monday()
    week_days = [monday + timedelta(days=i) for i in range(5)]

    # Routen vorhanden
    rules = {str(r) for r in A.app.url_map.iter_rules()}
    check("Route /api/v1/timetable/day registriert",
          "/api/v1/timetable/day" in rules)
    check("Route /api/v1/timetable/week registriert",
          "/api/v1/timetable/week" in rules)

    # Schutz ohne Token
    for path in ("/api/v1/timetable/day", "/api/v1/timetable/week"):
        r = client.get(path)
        check(f"{path} ohne Token 401 TOKEN_INVALID",
              r.status_code == 401
              and r.get_json()["code"] == "TOKEN_INVALID")

    # Token für alle weiteren Aufrufe (Validierung läuft vor dem Login
    # und braucht daher kein Netz).
    orig_login = A.do_login
    created = core.create_token(SUBDOMAIN, USERNAME, "geheim")
    token = created["token"]
    headers = {"Authorization": f"Bearer {token}"}

    # Validierung ohne Netz
    r = client.get("/api/v1/timetable/day?day=kein-datum",
                   headers=headers)
    check("Tagesansicht mit falschem Datum 400 VALIDATION",
          r.status_code == 400 and r.get_json()["code"] == "VALIDATION")
    r = client.get("/api/v1/timetable/week?day=32.13.2026",
                   headers=headers)
    check("Wochenansicht mit falschem Datum 400 VALIDATION",
          r.status_code == 400 and r.get_json()["code"] == "VALIDATION")

    try:
        # Fixture-Cache seeden (aktuelle Woche Mo–Fr, frisch gespeichert).
        for day in week_days:
            apicache.save_timetable(uhash, day,
                                    copy.deepcopy(SEED_RAW))
        A.do_login = lambda u, p, s: (_NoCallEdupage(), None, SUBDOMAIN)

        # Tagesansicht aus dem Cache
        probe = week_days[0].isoformat()
        r = client.get(f"/api/v1/timetable/day?day={probe}",
                       headers=headers)
        body = r.get_json()
        expected = A.merge_lernzeit(copy.deepcopy(SEED_RAW))
        check("Tagesansicht 200 mit Tag und Bezeichnung",
              r.status_code == 200 and body["day"] == probe
              and body["day_label"].startswith("Montag "))
        check("Tagesansicht liefert Web-Strukturen",
              body["lessons"] == expected)
        merged = [entry for entry in body["lessons"]
                  if entry.get("rowspan", 1) > 1]
        check("Lernzeit-Block zusammengefasst (2–3, rowspan 2)",
              len(merged) == 1 and merged[0]["period"] == "2–3"
              and merged[0]["rowspan"] == 2)
        by_title = {entry["title"]: entry for entry in body["lessons"]}
        check("Entfall-Kennzeichen",
              by_title["Englisch"]["is_cancelled"] is True)
        check("Online-Kennzeichen",
              by_title["Physik"]["is_online"] is True)
        check("Cache-Hinweis aus Cache",
              body["cache_info"].startswith("aus Cache"))
        check("Vor-/Folgetag und Heute",
              body["prev_day"] == (week_days[0]
                                   - timedelta(days=1)).isoformat()
              and body["next_day"] == week_days[1].isoformat()
              and body["today"] == date.today().isoformat())

        # Wochenansicht aus dem Cache
        r = client.get(f"/api/v1/timetable/week?day={probe}",
                       headers=headers)
        body = r.get_json()
        check("Wochenansicht 200 mit Montag und Bezeichnung",
              r.status_code == 200
              and body["monday"] == monday.isoformat()
              and body["week_label"].startswith("Woche "))
        check("Woche hat 5 Tage Mo–Fr",
              [d["date"] for d in body["days"]]
              == [d.isoformat() for d in week_days])
        check("Tagesobjekte wie in der Tagesansicht",
              all(d["lessons"] == expected for d in body["days"]))
        check("genau ein Tag als heute markiert",
              sum(1 for d in body["days"] if d["is_today"]) == 1
              and [d["date"] for d in body["days"]
                   if d["is_today"]] == [date.today().isoformat()])
        check("Woche komplett aus Cache",
              body["cache_info"]
              == "Woche aus Cache (0 API-Requests)")

        # Aktualisierungsschalter: Fake-Stundenplan mit Event
        fake = _FakeEdupage()
        A.do_login = lambda u, p, s: (fake, None, SUBDOMAIN)
        r = client.get(f"/api/v1/timetable/day?day={probe}&refresh=1",
                       headers=headers)
        body = r.get_json()
        check("Aktualisierung lädt frisch (5 EduPage-Aufrufe pro Woche "
              "später, hier 1 für den Tag)",
              r.status_code == 200 and len(fake.calls) == 1
              and body["cache_info"] == "frisch geladen")
        titles = [entry["title"] for entry in body["lessons"]]
        check("Tag zeigt ganztägiges Event (wie im Web)",
              "Projekttag" in titles)
        check("Tag mergt Lernzeit aus Fake-Stundenplan",
              any(entry.get("period") == "2–3"
                  for entry in body["lessons"]))
        stored = apicache.load_timetable(uhash, week_days[0])
        check("Aktualisierung schreibt Cache",
              stored is not None and len(stored["lessons"]) == 6)

        r = client.get(f"/api/v1/timetable/week?day={probe}&refresh=1",
                       headers=headers)
        body = r.get_json()
        check("Woche lädt 5 Tage frisch",
              r.status_code == 200 and len(fake.calls) == 6)
        week_titles = [entry["title"]
                       for d in body["days"] for entry in d["lessons"]]
        check("Woche filtert ganztägiges Event (wie im Web)",
              "Projekttag" not in week_titles)
        check("Woche nach Aktualisierung frisch geladen",
              body["cache_info"]
              == "Woche frisch geladen (5 API-Requests)")

        # Login-Fehlercodes
        from edupage_api.exceptions import (
            BadCredentialsException, CaptchaException)
        A.do_login = lambda u, p, s: (_ for _ in ()).throw(
            BadCredentialsException())
        r = client.get("/api/v1/timetable/day", headers=headers)
        check("ungültige Zugangsdaten 401 BAD_CREDENTIALS",
              r.status_code == 401
              and r.get_json()["code"] == "BAD_CREDENTIALS")
        A.do_login = lambda u, p, s: (_ for _ in ()).throw(
            CaptchaException())
        r = client.get("/api/v1/timetable/day", headers=headers)
        check("Captcha-Zwang 403 CAPTCHA_REQUIRED",
              r.status_code == 403
              and r.get_json()["code"] == "CAPTCHA_REQUIRED")
        A.do_login = lambda u, p, s: (fake, object(), SUBDOMAIN)
        r = client.get("/api/v1/timetable/day", headers=headers)
        check("erneute 2FA-Pflicht 401 EDUPAGE_2FA",
              r.status_code == 401
              and r.get_json()["code"] == "EDUPAGE_2FA")
    finally:
        A.do_login = orig_login
        core.revoke_token(token)
        for day in week_days:
            try:
                apicache._timetable_path(uhash, day).unlink()
            except OSError:
                pass

    print("Alle Stundenplan-Tests bestanden.")


if __name__ == "__main__":
    main()
