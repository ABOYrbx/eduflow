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

## Pakete (Stand: N0–NI umgesetzt auf `feature/node-paritaet-na`)

- **N0 Fundament (fertig):** Paginierungs-Parität (Meldungen,
  `""`-Verhalten, Grenzen) + Routenmatrix-Test gegen alle 30
  Python-Pfade + Konventionen.
- **N-A Auth echt (fertig):** EduPage-Login/2FA/Rate-Limit/Geräte, opake
  Bearer + Pending- + DL-Tokens, `/me`, `/devices` — drahtkompatibel zu
  `api/core.py` + `api/auth.py`. Fake-Demo unverändert.
- **N-B Nachrichten (fertig):** Liste/Thread/Senden/Antworten/Likes,
  lokal getracktes Ungelesen, Empfänger, Attachments + DL-Tokens.
- **N-C Hausaufgaben (fertig):** Filter, done/trash, Zähler, DTO-Parität.
- **N-D Stundenplan (fertig):** Tag/Woche, gcall-Protokoll,
  Lernzeit-Blöcke, Ganztags-Filter.
- **N-E Noten (fertig):** znamky-Protokoll, grade_to_dict, Cache.
- **N-F Einstellungen (fertig):** Schema-Parität, UserPreference,
  Cache-Clear. Geräte/`/me` aus N-A.
- **N-G Meta (fertig):** Mensa-PDF-Parser in TS (neue Dep `pdf-parse`
  als pypdf-Äquivalent) + Wochen-Cache, Wetter-Proxy + Suche.
- **N-H Schulalltag (fertig):** Vertretungen (Viewer-Protokoll, echte
  Markup-Form verifiziert) + Agenda.
- **N-I Web (fertig):** Next.js provider-neutral (Cookies ohne
  `refresh_token`, optionale Refresh-UI).
- **N-J Cutover (offen):** Live-DTO-Diffs Python↔Node brauchen einen
  Staging-Server mit echten Zugangsdaten (nicht offline machbar);
  danach App-Umschaltung und Python-Archivierung. **Kein Löschen ohne
  explizite Freigabe.**

## Regeln je Paket

- Eigene Branch ab `main`, additive Änderungen, bestehende Tests
  bleiben grün (`npm test`, `npm run typecheck`; Python-Seite:
  `python3 tests/test_api_e2e.py` unangetastet).
- Alles offline testbar (Fixtures/Fakes, nie echte Zugangsdaten).
- UI-/Fehlertexte deutsch, kurz, ohne Secrets/Stacktraces/Pfade.
  Fehler-`code`-Vokabular aus `api/core.py` nie erweitern ohne
  Absprache. Commits nur als `ABOYrbx` + noreply-Mail.
