# EduFlow Dashboard (Nachrichten + Hausaufgaben)

Simple local web dashboard built on the [EduPage API Python library](https://github.com/EdupageAPI/edupage-api)
(`pip install edupage-api`).

- Enter your school **subdomain**, **username** and **password**
- View the **Übersicht** (`/`, start page after login):
  live clock (top left), **ungelesene Nachrichten** (left),
  **offene Hausaufgaben** (right). Read state is tracked locally
  per user (the API has no unread flag): opening Nachrichten or
  pressing "Alle als gelesen markieren" marks everything as seen.
- View **all timeline messages from as far back as possible**
  (uses `Edupage.get_notification_history(date_from)` with an early date, default `2010-01-01`)
- View **Hausaufgaben** (`/hausaufgaben`): timeline events of type `homework`
  with Fälligkeitsdatum (from `additional_data.oldVals.date`), Status
  (offen / heute fällig / überfällig / erledigt), Suche + CSV-Export,
  Swipe-System (Karte nach links = fertig/wieder öffnen via
  `POST /hausaufgaben/erledigt`, nach rechts = in den Papierkorb via
  `POST /hausaufgaben/ausblenden`, Filter „Papierkorb" zum Zurückholen –
  Zurückholen markiert die Aufgabe gleichzeitig als offen).
  Hinweis: Der Papierkorb ist bewusst nur lokal (`hidden_<hash>.json`, wie der
  Gelesen-Status) – Schüler können aufgegebene Hausaufgaben auf EduPage
  nicht löschen, nur das done-Flag ist Server-Zustand.
- View **Stundenplan** (`/stundenplan`): `Edupage.get_my_timetable(date)`
  with day navigation (Zurück / Heute / Weiter) and week view (Mo–Fr, `?view=week`)
- Search / filter by type, reload from an earlier date, export to CSV

## Run

```bash
pip install -r requirements.txt
python app.py
```

Then open http://127.0.0.1:8000 (port via `PORT` env var;
note: macOS AirPlay Receiver blocks port 5000, hence the 8000 default)

## API-Keys (.env)

Copy `.env.example` to `.env` (git-ignored, stays local) and fill in:

```bash
OPENWEATHER_KEY=dein-key-für-die-wetterkarte
```

Optional der Wetter-Standort (Koordinaten gehen vor, sonst Stadtname,
sonst Browser-Geo, sonst Berlin):

```bash
WEATHER_LAT=48.21
WEATHER_LON=16.37
# oder einfach:
WEATHER_CITY=Wien
```

Without a key the weather card shows "nicht verfügbar". Everything
else works without any keys.

## How "as far back as possible" works

- `get_notifications()` only returns ~1 month from the login payload.
- `get_notification_history(date_from)` queries
  `POST /timeline/?module=todo&akcia=getData&filterTab=messages`
  with `datefrom=YYYY-MM-DD` and returns everything since then.
- The dashboard fetches the history from an early date (default
  `2000-01-01`, changeable via the "Verlauf seit" field), finds the oldest
  message in the answer and takes its date as the history start
  (`fetch_history_with_fallback` + `oldest_and_newest` in `app.py`).
  The "Verlauf seit" field is prefilled with exactly that date, and the
  oldest entry is shown in the stats line ("Oldest message" /
  "Älteste Aufgabe", incl. number of API requests).
- If the server rejects a very early date (`RequestError`), the fetch is
  retried with a shorter period (2 years / 1 year).
- "messages only" mode keeps `sprava, news, anketa, chat, genotif`;
  switch to "all timeline events" to also see grades, timetable changes, etc.

## 2FA / captcha

- If your account uses 2FA, you'll be asked for the e-mail/app code
  (`TwoFactorLogin.finish_with_code`).
- If EduFlow demands a captcha, log in once in a real browser, then retry here.

## Security

Local tool only. The password is kept Fernet-encrypted (`cryptography`)
in the signed Flask session cookie to re-login on each page load
(key in `.eduflow.key`, session key in `.eduflow_secret`, both git-ignored).
"Angemeldet bleiben" keeps you logged in for 30 days across browser and
server restarts; without it the session ends when the browser closes.
Don't expose this publicly.
Env overrides: `FLASK_SECRET_KEY`, `EDUFLOW_KEY`.

## Files

- `app.py` – Flask app (`/`, `/login`, `/2fa`, `/uebersicht`, `/als-gelesen`, `/dashboard`, `/likes/<id>` (wer hat geliked), `/datei/<id>/<idx>` (Datei-Download), `/hausaufgaben`, `/hausaufgaben/erledigt` (als erledigt markieren), `/hausaufgaben/ausblenden` (Papierkorb: reinlegen/zurückholen + als offen markieren), `/stundenplan`, `/einstellungen`, `/logout`)
- `templates/login.html`, `templates/2fa.html`, `templates/overview.html`, `templates/dashboard.html`, `templates/homework.html`, `templates/timetable.html`, `templates/settings.html` (Aussehen + allgemeine Einstellungen, per `SETTINGS_SCHEMA` in `app.py` erweiterbar)
- `cache.py` – `settings_<hash>.json` pro User (bleibt bei "Cache leeren" erhalten)
- `static/uber.css` – shared Design im Uber-iOS-Stil (weiß/Schwarz, Full-Pill-Buttons, Inter)
- `static/theme.js` – Dark Mode (Toggle in der Navi, folgt zuerst dem System, speichert die Wahl in localStorage) + Akzentfarbe (8 Farben im Profilmenü, `data-accent`, localStorage)
- `requirements.txt`

## Hausaufgaben

- Quelle: wie im offiziellen `examples/get_homework.py` – `get_notification_history(since)`
  filtern nach `EventType.HOMEWORK`. Optional `include_tests=1` für
  `bexam, sexam, oexam, pexam, rexam, testing, etesthw, testpridelenie`.
- Titel aus `additional_data.oldVals.title`, Fälligkeitsdatum aus `oldVals.date`
  (`YYYY-MM-DD`), Fallback auf `ev.text`.
- Status: `is_done` (via `userProps.doneMaxCas`) → erledigt, sonst Vergleich
  Fälligkeitsdatum vs. heute → überfällig / heute fällig / offen.
- Sortierung: überfällige zuerst, dann nach Fälligkeitsdatum.
