# Node-Parität — Plan, NestJS voll funktional zu machen

Python/Flask bleibt das Echt-Backend, bis dieser Plan vollständig
abgenommen ist (AGENTS.md-Regeln gelten unverändert, iOS ausgenommen).
Ziel: NestJS wird **drahtkompatibel** zu `/api/v1` aus Python — gleiche
Routen, gleiche DTOs, gleiche Fehler-`code`s und -Texte, gleiche Auth-
Abläufe — damit Android/macOS ohne Client-Umbau umschalten können.
Der Fake-Provider (`EDUFLOW_PROVIDER=fake`, demo/demo) bleibt nur für
Vorführungen (plaene/DEMO.md).

## Kritischer Pfad (vorab geklärt)

- Es gibt **kein edupage-api für Node**. Paket N-A muss das EduPage-
  HTTP-Protokoll in TypeScript nachbauen (Login, Cookies, 2FA,
  Timeline, Senden). Das ist der größte Brocken; alles andere baut auf
  echten Daten statt Fake-Daten auf.
- Auth-Schema: Python nutzt opake 30-Tage-Bearer + `pending_token`
  (TTL 10 Min) + `?dl=`-Kurz-Tokens (5 Min). Nest nutzt JWT
  access+refresh + Postgres. Parität heißt: Python-Semantik
  nachbauen (Antwortformen, TTLs, Rate-Limit 20/10 Min/IP), sonst
  brechen TokenStore/Interceptor der Apps.
- Paginierung: `limit` 50/max 200, `{items, total, limit, offset}`,
  deutsche Fehlermeldungen wie `api/core.py` (Paket N0 erledigt das).

## Pakete

- **N0 Fundament (diese Branch):** Paginierungs-Parität (Meldungen,
  `""`-Verhalten, Grenzen) + Routenmatrix-Test gegen alle 30
  Python-Pfade + Konventionen. Abnahme: `npm test`, `npm run
  typecheck` grün, nur additive Änderungen.
- **N-A Auth echt:** EduPage-Login/2FA/Rate-Limit/Geräte, opake
  Bearer + Pending- + DL-Tokens, `/me`, `/devices`. Abnahme:
  Login/2FA/Refresh/Logout-Flows gegen Fixtures, Texte wie Python.
- **N-B Nachrichten:** Liste/Thread/Senden/Antworten/Likes,
  lokal getracktes Ungelesen, Empfänger, Attachments + DL-Tokens.
- **N-C Hausaufgaben:** Filter, done/trash, Zähler, DTO-Parität.
- **N-D Stundenplan:** Tag/Woche, DTO-Parität (JETZT-Logik bleibt
  Client-Sache).
- **N-E Noten:** Schnitt, Halbjahre, Fächer.
- **N-F Einstellungen:** Schema-Parität zu `app.py`, Geräte,
  Cache-Clear.
- **N-G Meta:** Mensa-PDF-Parser in TS + Wochen-Cache, Wetter
  (OpenWeather-Key, Suche, Detail).
- **N-H Schulalltag:** Vertretungen + Agenda (Kalender/Prüfungen/
  Anwesenheit).
- **N-I Web:** Next.js-Seitenparität zu den 11 Flask-Templates
  (Login/2FA, Übersicht, Dashboard, Verfassen, Hausaufgaben,
  Stundenplan, Noten, Einstellungen, Termine).
- **N-J Cutover:** DTO-Diff-Tests Python↔Node, App-Umschaltung
  (Server-URL), Python-Archivierung. **Kein Löschen ohne
  explizite Freigabe.**

## Regeln je Paket

- Eigene Branch ab `main`, additive Änderungen, bestehende Tests
  bleiben grün (`npm test`, `npm run typecheck`; Python-Seite:
  `python3 tests/test_api_e2e.py` unangetastet).
- Alles offline testbar (Fixtures/Fakes, nie echte Zugangsdaten).
- UI-/Fehlertexte deutsch, kurz, ohne Secrets/Stacktraces/Pfade.
  Fehler-`code`-Vokabular aus `api/core.py` nie erweitern ohne
  Absprache. Commits nur als `ABOYrbx` + noreply-Mail.
