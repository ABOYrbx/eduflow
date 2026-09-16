# EduFlow Dashboard (Nachrichten + Hausaufgaben)

Simple local web dashboard built on the [EduPage API Python library](https://github.com/EdupageAPI/edupage-api)
(`pip install edupage-api`).

- Enter your school **subdomain**, **username** and **password**
- View **all timeline messages from as far back as possible**
  (uses `Edupage.get_notification_history(date_from)` with an early date, default `2010-01-01`)
- View **Hausaufgaben** (`/hausaufgaben`): timeline events of type `homework`
  with Fälligkeitsdatum (from `additional_data.oldVals.date`), Status
  (offen / heute fällig / überfällig / erledigt), Suche + CSV-Export
- View **Stundenplan** (`/stundenplan`): `Edupage.get_my_timetable(date)`
  with day navigation (Zurück / Heute / Weiter) and week view (Mo–Fr, `?view=week`)
- Search / filter by type, reload from an earlier date, export to CSV

## Run

```bash
pip install -r requirements.txt
python app.py
```

Then open http://127.0.0.1:5000

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

Local tool only. Credentials are kept in the signed Flask session cookie
to re-login on each page load. Don't expose this publicly.
Set a stable key via `FLASK_SECRET_KEY` env var if you restart often.

## Files

- `app.py` – Flask app (`/`, `/login`, `/2fa`, `/dashboard`, `/hausaufgaben`, `/stundenplan`, `/logout`)
- `templates/login.html`, `templates/2fa.html`, `templates/dashboard.html`, `templates/homework.html`, `templates/timetable.html`
- `static/uber.css` – shared Design im Uber-iOS-Stil (weiß/Schwarz, Full-Pill-Buttons, Inter)
- `static/theme.js` – Dark Mode (Toggle in der Navi, folgt zuerst dem System, speichert die Wahl in localStorage)
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
