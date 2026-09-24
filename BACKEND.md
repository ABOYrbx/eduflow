# EduFlow API-Backend v1 — Bauplan (Mehr-Agenten-fähig)

Ziel: ein versioniertes JSON-Backend unter dem Pfadpräfix `/api/v1`, gegen das eine
Android-App gebaut werden kann. Die bestehenden Web-Seiten und Web-Routen bleiben
unverändert und voll funktionsfähig; das API kommt daneben, ohne Breaking Changes.

## 1. Fixe Architektur-Entscheidungen (gelten für alle Pakete)

- Alle neuen Routen leben unter `/api/v1`. Es gibt genau einen Registrierungs­punkt,
  an dem alle Teilmodule angebunden werden.
- Authentifizierung ausschließlich über Bearer-Token im Authorization-Header.
  Ausnahme: Datei-Downloads akzeptieren zusätzlich einen Token-Query-Parameter,
  weil native Download-Komponenten nicht immer Header setzen können.
- Token sind opake Zufallswerte. Serverseitig liegt pro Token ein Datensatz mit
  Subdomain, Benutzername, Fernet-verschlüsseltem Passwort, Erstell- und
  Ablaufzeit sowie optionalem Gerätenamen. Das Passwortmuster (verschlüsselt,
  nie Klartext) wird vom Web-Login übernommen, nicht neu erfunden.
- Standard-Ablaufzeit für Token: 30 Tage. Abgelaufene Token werden abgelehnt,
  nicht stillschweigend verlängert.
- 2FA ist zweistufig: Die Login-Antwort meldet bei Bedarf den Status
  2FA erforderlich zusammen mit einem Zwischen-Token; ein zweiter Aufruf mit
  Code tauscht es gegen ein vollwertiges Token. Das Zwischen-Token-Prinzip wird
  vom Web-2FA-Ablauf übernommen.
- Erfolgsantworten geben das Ressourcen-Objekt direkt zurück. Listen geben ein
  Objekt mit den Feldern für Einträge, Gesamtzahl, Limit und Offset zurück.
- Fehlerantworten haben immer dieselbe Form: ein Feld für die lesbare Meldung
  und ein Feld für einen stabilen Fehlercode aus dem festen Vokabular
  (unter anderem: falsche Zugangsdaten, Captcha erforderlich, Token ungültig,
  Token abgelaufen, Validierungsfehler, nicht gefunden, EduPage-Fehler,
  fehlende Server-Konfiguration).
- Datums- und Zeitwerte sind ISO-8601-Zeichenketten, Preise und Texte bleiben
  unverändert wie im Web. Benutzersichtbare Meldungen sind deutsch.
- Keine neuen Serializer: Die bestehenden Dict-Bauer werden eins zu eins als
  API-Antwortobjekte wiederverwendet (Nachrichten, Hausaufgaben, Stundenplan­stunden,
  Noten, Essensplan, Threads, Empfänger). Das garantiert Web- und App-Parität.
- Der bestehende Datei-Cache und die pro Benutzer gespeicherten Zustände
  (gelesen, Papierkorb, Einstellungen, Likes) werden mitbenutzt, nicht dupliziert.
  App und Web sehen dadurch denselben Stand.
- Passwörter, API-Schlüssel und Token-Hashes erscheinen niemals in Antworten
  oder Logs. Bestehende Secret-Dateien und Ignorier-Regeln bleiben unangetastet.
- Jede Liste ist paginierbar (Limit mit sinnvollem Maximum, Offset ab null) und
  liefert die Gesamtzahl mit. Filter heißen überall gleich wie die bestehenden
  Web-Parameter (Typ, Status, Zeitraum, Suche), soweit vorhanden.

## 2. Paket 0 — Kernmodul (GEBAUT und EINGEFROREN)

Stand: umgesetzt in den Dateien api-Paketinit, api/core und tests/test_api_core.
Lauf der Tests: tests/test_api_core direkt mit Python starten (kein
Test-Framework nötig). Die App bindet den Blueprint genau einmal an.

Eingefrorene Schnittstelle, gegen die alle Pakete programmieren:

- Der Blueprint heißt api_v1 (Präfix /api/v1). Ressourcen-Pakete legen ihre
  Routen auf genau diesen Blueprint, sonst nirgendwo.
- Der Routen-Schutz heißt token_required und wird als Decorator verwendet.
  Er liest das Bearer-Token, lehnt fehlende oder unbekannte Token mit dem Code
  TOKEN_INVALID ab, abgelaufene mit TOKEN_EXPIRED, und stellt bei Erfolg die
  Felder api_subdomain, api_username und api_password auf dem Request-Kontext
  bereit (entschlüsseltes Passwort für das EduPage-Re-Login).
- Token-Verwaltung über vier Funktionen: Anlegen (mit Subdomain, Benutzername,
  Passwort, optionalem Gerätenamen und Laufzeit, Standard 30 Tage, per
  EDUFLOW_API_TOKEN_DAYS überstimmbar), Prüfen (liefert Zugangsdaten oder
  nichts zurück), Ablauf-Abfrage und gezieltes Widerrufen. Ablage in der Datei
  api_tokens im bestehenden Cache-Verzeichnis (nur Hashes, atomar geschrieben).
- Fehler immer über den zentralen Fehler-Bauer (Meldung, Code, Status).
  Feststehende Codes des Kerns: TOKEN_INVALID, TOKEN_EXPIRED, VALIDATION.
- Paginierung immer über zwei Helfer: einen, der Limit (Standard 50, Maximum
  200) und Offset validiert und bei Verstoß einen deutschen Validierungs­fehler
  wirft, und einen, der aus Einträgen, Limit und Offset das Hüllobjekt mit
  Einträgen, Gesamtzahl, Limit und Offset baut.
- Python-Untergrenze ist 3.9 (keine neue Syntax über diesem Stand verwenden,
  zum Beispiel keine unverpackten Oder-Typen in Annotationen).

Ab diesem Punkt sind alle Pakete A bis G parallel baubar.

## 3. Paket A — Authentifizierung (GEBAUT)

Stand: umgesetzt in api/auth (Tests: tests/test_api_auth, offline lauffähig).
Festgelegte Routenpfade: Anmelden unter auth/login, Zwei-Faktor-Abschluss
unter auth/2fa, Abmelden unter auth/logout, eigener Benutzer unter me.

- Anmelden nimmt Subdomain (optional, dann automatisch), Benutzername,
  Passwort und optionalen Gerätenamen. Falsche Zugangsdaten geben den Code
  für falsche Zugangsdaten, Captcha-Zwang den Captcha-Code mit Status 403,
  alle anderen EduPage-Fehler den Upstream-Code. Fehlende Felder oder kein
  JSON geben den Validierungs-Code.
- 2FA-Pflicht antwortet mit Status 2fa_required plus Zwischen-Token und
  Hinweismeldung. Der Abschluss tauscht Zwischen-Token und Code gegen ein
  vollwertiges Token; unbekannte oder Web-fremde Zwischen-Token geben den
  Pending-Code, falsche Codes den Code für ungültige Codes.
- Abmelden widerruft genau das verwendete Token und meldet Status ok.
- Der Benutzer-Endpunkt gibt Subdomain und Benutzername des Token-Inhabers
  zurück.
- Die 2FA-Zwischenablage ist die bestehende des Web-Logins, API-Einträge sind
  markiert und werden von Web-Einträgen getrennt geprüft (keine Vermischung).
- Akzeptanz erfüllt: kompletter Token-Fluss, Validierung, Pending-Trennung
  und Schutzverhalten laufen offline im Testclient; Live-Login und echter
  Code-Abschluss brauchen ein EduPage-Konto und sind nicht automatisiert.

## 4. Paket B — Nachrichten und Threads (GEBAUT)

Stand: umgesetzt in den Dateien api/messages und tests/test_api_messages.
Lauf der Tests: tests/test_api_messages direkt mit Python starten (kein
Test-Framework nötig). Tests bestehen.

Festgelegte Routenpfade: Nachrichtenliste unter messages (mit Zeitraum,
Typfilter, Textsuche und Paginierung), Thread einer Nachricht unter
messages/eindeutige-ID/thread, Gelesen-Markierung unter messages/read,
Empfängerliste unter recipients, Senden unter messages/send, Antworten
unter messages/eindeutige-ID/reply, Dateianhang unter
messages/eindeutige-ID/attachments/Index (zusätzlich mit Token-Query
erreichbar).

- Die Liste zeigt nur Top-Level-Nachrichten (Antworten sind über das
  Antwort-Kennzeichen ausgeschlossen, wie im Web). Sie unterstützt Zeitraum,
  Typfilter und Textsuche sowie Paginierung und liefert Antwortobjekte aus dem
  bestehenden Nachrichten-Bauer.
- Der Thread-Endpunkt liefert Likes, Antworten und Zusammenfassung aus der
  bestehenden Thread-Logik inklusive Datei-Cache.
- Gelesen-Markierung übernimmt die bestehende Gelesen-Logik für alle aktuellen
  Nachrichtentypen.
- Senden und Antworten nutzen die bestehenden Sende-Helfer (Gruppen-ID,
  Text, Empfängerauflösung); die Empfängerliste nutzt den bestehenden Helfer.
- Der Dateianhang-Endpunkt ist ein authentifizierter Proxy auf die eingeloggte
  EduPage-Sitzung (nur EduPage-Adressen, Stream, Dateiname aus den
  Nachrichtendaten), zusätzlich mit Token-Query-Parameter erreichbar.
- Akzeptanz erfüllt: Liste ohne Antworten, Thread mit Likes und Antworten,
  Senden und Antworten gegen Fixture-Cache, Download verweigert fremde
  Adressen (Testlauf grün).

## 5. Paket C — Hausaufgaben (GEBAUT)

Stand: umgesetzt in den Dateien api/homework und tests/test_api_homework.
Lauf der Tests: tests/test_api_homework direkt mit Python starten (kein
Test-Framework nötig). Tests bestehen.

Festgelegte Routenpfade: Hausaufgabenliste unter homework (mit Zeitraum,
Statusfilter, Test-Einbeziehung und Paginierung), Erledigt-Schalter unter
homework/eindeutige-ID/done, Papierkorb unter homework/eindeutige-ID/trash.

- Die Liste nutzt Zeitraum, Statusfilter, Test-Einbeziehung und Paginierung und
  liefert Antwortobjekte aus dem bestehenden Hausaufgaben-Bauer in der
  bestehenden Sortierung (überfällig zuerst, Papierkorb-Einträge ans Ende).
  Zähler für offen, überfällig, erledigt und Papierkorb werden mitgeliefert.
- Erledigt-Markierung nutzt den bestehenden Server-Helfer und pflegt den
  lokalen Cache sofort nach, wie im Web.
- Der Papierkorb nutzt dieselbe lokale Dateiablage wie das Web (kein
  Server-Zustand), inklusive der Regel, dass Zurückholen gleichzeitig als
  offen markiert.
- Akzeptanz erfüllt: Filter, Zähler und Sortierung stimmen mit dem Web
  überein; Statuswechsel ist nach erneutem Laden sichtbar (Testlauf grün).

## 6. Paket D — Stundenplan (GEBAUT)

Stand: umgesetzt in den Dateien api/timetable und tests/test_api_timetable.
Lauf der Tests: tests/test_api_timetable direkt mit Python starten (kein
Test-Framework nötig).

Routen: Tagesansicht, Wochenansicht.

- Die Tagesansicht nimmt ein Tagesdatum (Standard: heute) und liefert
  Anzeigeobjekte aus dem bestehenden Stunden-Bauer inklusive Zusammenfassung
  aufeinanderfolgender Lernzeit-Stunden, wie im Web.
- Die Wochenansicht nimmt ein Datum innerhalb der Woche und liefert Montag bis
  Freitag mit denselben Tagesobjekten plus Wochenbezeichnung.
- Beide nutzen den bestehenden Stundenplan-Cache mit dessen
  Vergangenheits-, Heute- und Zukunfts-Laufzeiten; ein Aktualisierungs­schalter
  lädt frisch.
- Akzeptanz: Tag und Woche gegen Fixture-Cache liefern dieselben Strukturen
  wie die Web-Seite (Lernzeit-Blöcke, Entfall-Kennzeichen, Online-Kennzeichen).

## 7. Paket E — Noten (GEBAUT)

Stand: umgesetzt in api/grades (Tests: tests/test_api_grades, offline
lauffähig). Festgelegter Routenpfad: Notenliste unter grades mit
Paginierung (limit, offset) und Aktualisierungs­schalter (refresh=1).

- Die Liste liefert Anzeigeobjekte aus dem bestehenden Noten-Bauer in
  Cache-Reihenfolge (keine neuen Filter, keine neue Sortierung) in der
  Listen-Hülle plus Cache-Info.
- Ist der Cache frisch und kein Refresh verlangt, antwortet die Route ohne
  EduPage-Login (offline-fähig); sonst Re-Login mit den Token-Zugangsdaten.
- Fehlerbild als Muster für alle Ressourcen-Pakete (B, C, D, F, G bitte
  übernehmen): VALIDATION mit 400 bei ungültiger Paginierung,
  BAD_CREDENTIALS mit 401 bei ungültig gewordenen Zugangsdaten,
  CAPTCHA_REQUIRED mit 403 bei Captcha-Zwang, EDUPAGE_2FA mit 401 wenn
  EduPage erneut 2FA verlangt (dann neu über auth/login anmelden),
  UPSTREAM mit 502 für alle anderen EduPage-Fehler.
- Akzeptanz erfüllt: Schutz, Validierung, frischer-Cache-Kurzschluss und
  Paginierung laufen offline im Testclient; der Frisch-Ladepfad braucht ein
  EduPage-Konto und ist nicht automatisiert.

## 8. Paket F — Essen und Wetter (GEBAUT)

Stand: umgesetzt in api/meta (Tests: tests/test_api_meta, offline
lauffähig). Festgelegte Routenpfade: Wochen-Essensplan unter essen
(mit Aktualisierungs­schalter refresh=1), Wetter unter wetter
(mit ?lat=..&lon=.. oder ?city=..).

- Der Essens-Endpunkt liefert Wochenbezeichnung, PDF-Quelle, Tage mit
  Gerichten und heutigem Tag aus dem bestehenden Essensmodul inklusive
  Wochen-Cache; Fehler mit UPSTREAM. Braucht kein EduPage-Login.
- Die Wetter-Logik der Web-Route wurde verhaltensgleich in den Helfer
  get_wetter_payload ausgelagert (einzige inhaltliche app.py-Änderung dieses
  Pakets); Web-Route und API-Route nutzen ihn gemeinsam. Fehlercodes:
  VALIDATION ohne Ort, CONFIG_MISSING ohne Schlüssel, UPSTREAM bei
  Upstream und Netz.
- Akzeptanz erfüllt: Essensantwort enthält alle fünf Tage mit Preisen und
  Quelle; Schutz, Validierung und Fehlerübersetzung laufen offline im
  Testclient; echte Wetter-Abfrage und Essen-Refresh brauchen Netz und sind
  nicht automatisiert.

## 9. Paket G — Einstellungen und Cache (GEBAUT)

Stand: umgesetzt in den Dateien api/settings und tests/test_api_settings.
Lauf der Tests: tests/test_api_settings direkt mit Python starten (kein
Test-Framework nötig). Tests bestehen.

Festgelegte Routenpfade: Einstellungen lesen/speichern unter settings
(lesen per GET, speichern per PUT im Web-Formularformat), Cache leeren
per POST unter cache-clear (wie die Web-Route).

Routen: Einstellungen lesen und speichern, Cache leeren.

- Einstellungen lesen liefert Schema und Werte aus dem bestehenden
  Einstellungs­schema; Speichern validiert gegen dasselbe Schema mit derselben
  Normalisierung wie das Web (keine eigene Validierung).
- Cache-Leeren löscht dieselben Dateien wie die Web-Funktion (eigene Caches
  plus Essens-Caches, Einstellungen bleiben erhalten) und meldet die Anzahl.
- Akzeptanz: Ungültige Werte fallen auf Defaults zurück wie im Web;
  Cache-Leeren erhält die Einstellungen.

## 10. Paketübergreifende Regeln für alle Agenten

- Keine bestehenden Web-Routen, Templates oder Helper-Signaturen ändern.
  Neue Module liegen in einem eigenen API-Paketverzeichnis; die Anbindung an
  die App erfolgt an genau einer Stelle.
- Jeder Agent arbeitet auf einem eigenen Zweig ab dem Hauptzweig und fasst nur
  seine Paket-Dateien plus die eine Anbindungsstelle an.
- Neue Abhängigkeiten sind zu begründen und in die bestehende
  Abhängigkeits­datei einzutragen; bevorzugt wird ohne neue Abhängigkeiten
  gebaut (der Testclient von Flask genügt für Tests).
- Tests laufen offline gegen Fixture-Caches, niemals mit echten Zugangsdaten
  im Repository. Jedes Paket liefert einen Testlauf, der Routenform,
  Fehlercodes, Paginierung und Cache-Wiederverwendung prüft.
- Antworttexte für Fehler sind deutsch, kurz und ohne interne Details
  (keine Stacktraces, keine Schlüssel, keine Pfade).

## 11. Integrations-Reihenfolge und Abnahme

1. Paket 0 fertigstellen und Schnittstelle einfrieren.
2. Pakete A bis G parallel bauen (alle nur gegen die eingefrorene
   Kern-Schnittstelle und die bestehenden Helper).
3. Zusammenführen in dieser Reihenfolge: Auth, Nachrichten, Hausaufgaben,
   Stundenplan, Noten, Essen und Wetter, Einstellungen und Cache.
4. End-zu-End-Abnahme im Testclient: Anmelden (inklusive simulierter
   2FA-Pflicht), jede Liste mit Paginierung, je ein Schreibaufruf pro Paket,
   Abmelden mit anschließend abgelehntem Token, sowie der Nachweis, dass alle
  Web-Seiten unverändert rendern.
5. Nicht-Ziele dieser Ausbaustufe: Push-Benachrichtigungen, Datei-Uploads von
   der App, Mehrbenutzer-Verwaltung und ein öffentlicher Betrieb (der Server
   bleibt ein lokales Werkzeug wie bisher).

## 12. Härtung P0 + P1 (umgesetzt, abwärtskompatibel bis auf Codes)

P0 – Vereinheitlicht (Tests: alle `tests/test_api_*` + `test_api_e2e` grün):
- Kanonisches Fehler-Vokabular in `api/core.py` (`ERROR_CODES`,
  `edupage_login_error`): VALIDATION (400), TOKEN_INVALID/EXPIRED (401),
  PENDING_INVALID/INVALID_CODE (401), BAD_CREDENTIALS (401),
  EDUPAGE_2FA (401, neu über `/auth/login`), CAPTCHA_REQUIRED (403),
  NOT_FOUND (404), RATE_LIMITED (429), CONFIG_MISSING (503), UPSTREAM (502).
  Alt-Codes EDUPAGE_ERROR → UPSTREAM, REAUTH_REQUIRED/2FA_REQUIRED →
  EDUPAGE_2FA (betrifft Nachrichten-Thread/Senden, Stundenplan, Hausaufgaben).
- `POST /messages/send` lädt nach dem Senden synchron frisch
  (`fetch_history_with_fallback`, kein stale-while-revalidate) – behebt
  Race, bei dem die neue Nachricht nicht gefunden wurde.
- Neu (ohne Auth, additiv): `GET /api/v1/health` (`{status, version}`) und
  `GET /api/v1/openapi.json` (minimale OpenAPI-3.0-Spec aller Routen).

P1 – Auth-Härtung (Tests: `tests/test_api_hardening.py` grün):
- `GET /devices` (eigene Tokens, ohne Secrets), `DELETE /devices/<hash>`
  (Besitzschutz via `revoke_token_by_hash`), `POST /auth/refresh`
  (Rotation: neu ausstellen, alt widerrufen) – Web-UI (`/einstellungen`)
  nutzt dieselben Kern-Helfer weiter.
- `PENDING_2FA` mit `created`-Stempel + TTL (10 Min., `EDUFLOW_PENDING_TTL`),
  `prune_pending_2fa`/`pending_2fa_get` in `app.py`; Web- (`/2fa`) und
  API- (`/auth/2fa`) Ablauf prüfen die TTL, alte Einträge ohne Stempel
  bleiben gültig (rückwärtskompatibel).
- Login-Rate-Limit in `api/auth.py` (20 Versuche / 10 Min. / IP,
  `EDUFLOW_LOGIN_LIMIT`/`EDUFLOW_LOGIN_WINDOW`, 429 RATE_LIMITED,
  `reset_login_rate_limit` für Tests). Zählt `/auth/login` + `/auth/2fa`.
