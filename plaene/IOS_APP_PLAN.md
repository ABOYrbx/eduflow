# EduFlow iOS — Gesamtplan: ganze App bauen

Ziel: aus dem bestehenden Gerüst (`ios/`, Pakete 0/A/D gebaut) eine
fertige, abgenommene iOS-App machen. Quelle aller Details: `IOS.md`
(Architektur, Paket-Schnittstellen), `BACKEND.md` (API-Vertrag),
`GET /api/v1/openapi.json` (Routen-Referenz).

Ist-Stand: 13 Swift-Dateien, Pakete 0 (Kern), A (Auth/Einstellungen/Geräte),
D (Stundenplan/Übersicht/Essen/Wetter) gebaut. Offen: Paket B
(Nachrichten/Threads), Paket C (Hausaufgaben/Noten), Feinschliff, Abnahme.

Regeln für alle Phasen (aus `IOS.md` §7): kein Backend anfassen, keine
Paket-0-Signaturen ändern, nur System-Frameworks, deutsche UI-Texte,
401-Verhalten → Login (`needsReLogin` + `AuthAwareError`), Tests offline
mit gemocktem `APIClient`. Jeder Agent arbeitet auf eigenem Branch ab `main`.

---

## Phase 1 — Paket B: Nachrichten und Threads

Ziel: Nachrichten-Tab mit Liste, Thread, Verfassen, Anhängen.
Parität zu `/dashboard` und `templates/compose.html`.

- [x] **B1 — DTOs ergänzen** (`Core/DTOs.swift`, bestehende Typen unverändert):
  `ThreadLike`, `ThreadReply`, `ThreadSummary`, `ThreadResponse`
  (aus `get_message_likes` in `app.py`: likes, replies, reply_ids, summary,
  cached), `RecipientItem` (Lehrer + Mitschüler aus `get_recipients`,
  nach Name sortiert), Sende-Bodies (`recipients: [IDs]`, `body`;
  Antwort: `{body}`). (Erledigt.)
- [x] **B2 — `Features/Messages/MessagesService.swift`**: `list(since:type:q:limit:offset:refresh:)`,
  `thread(id:refresh:)`, `markRead()`, `recipients(limit:offset:)`,
  `send(recipients:body:)`, `reply(id:body:)`. Nur gegen `APIClient`.
  (Erledigt.)
- [x] **B3 — Liste** (`MessagesViewModel` + `MessagesView`): Typfilter
  (`sprava/news/anketa/chat/genotif`, Default alle), Textsuche (debounced),
  Paginierung (limit 50, Mehr laden), Pull-to-Refresh, Kopfzähler
  (geladen + als-gelesen), Karte (Autor, Zeit, Typ-Label, Text, Likes,
  Anhänge). Nur Top-Level (Antworten mit `textReply` rausfiltern, wie Web).
  (Erledigt.)
- [x] **B4 — Thread** (`ThreadView` + ViewModel): Likes, Antworten,
  Zusammenfassung, Cache-Hinweis, Antwort schreiben (geht an alle im
  Thread, wie im Web). Anhänge melden fertige Download-URL
  (`attachmentURL`, nur `*.edupage.org`, Dateiname aus Nachrichtendaten).
  (Erledigt; Download-UI beim Öffnen aus der Nachrichten-App nachziehen.)
- [x] **B5 — Verfassen** (`ComposeView` + ViewModel): Empfängerliste laden
  + Auswahl, Validierung wie serverseitig (mind. 1 gültige ID im Format
  von `_RECIPIENT_ID_RE` in `app.py`, nicht-leerer Body; Server kürzt auf
  5000 Zeichen) → sonst `VALIDATION`. Gesendete Nachricht erscheint sofort
  in der Liste. (Erledigt; reine `MessageCompose`-Validierung, offline testbar.)
- [x] **B6 — Verdrahtung**: Nachrichten-Tab in `MainTabs`
  (`EduFlowApp.swift`) ergänzen, `landing`-Ziel `dashboard` beachten.
  (Erledigt; Tab drin, `landing`-Steuerung in Phase 3/F1.)
- [x] **B7 — Offline-Tests**: Routenform, Fehlercodes, Paginierung,
  401-Verhalten, `VALIDATION` bei leeren Empfängern/Body, fremde URLs geblockt.
  (Erledigt als XCTest-Target `EduFlowTests` mit `MessagesTests` —
  Ausführung in Xcode, hier nur `swiftc -parse`.)

Abnahme B: Liste mit Paging/Filter/Suche wie `/dashboard`; Thread mit
Likes; Senden + Antworten gegen Test-Backend sichtbar.

## Phase 2 — Paket C: Hausaufgaben und Noten

Ziel: Hausaufgaben-Tab mit Filtern/Swipe plus Noten-Tab.
Parität zu `/hausaufgaben` und `/noten`.

- [x] **C1 — Noten-DTO** (`Core/DTOs.swift`): `GradeItem` (Cache-Reihenfolge
  wie `grade_to_dict`), Schnitt wie `grades_average` in `app.py`.
  (`HomeworkItem`, `HomeworkCounts`, `HomeworkListResponse` existieren.)
- [x] **C2 — `Features/Homework/HomeworkService.swift`**: `list(since:status:includeTests:q:limit:offset:refresh:)`,
  `setDone(id:done:)`, `setTrash(id:hide:)`. Nur gegen `APIClient`.
- [x] **C3 — Liste** (`HomeworkViewModel` + `HomeworkView`): Suche,
  Statusfilter (`alle/offen/überfällig/erledigt/papierkorb`),
  Tests-Schalter, Zähler (`offen/ueberfaellig/erledigt/papierkorb`),
  Sortierung überfällig-zuerst (`homework_rank` aus `app.py`), Refresh.
- [x] **C4 — Swipe** (`.swipeActions`): links = fertig/wieder öffnen
  (`POST done`), rechts = Papierkorb (`POST trash`, Zurückholen markiert
  gleichzeitig als offen, wie im Web) — plus Buttons als Alternative.
- [x] **C5 — Noten** (`GradesService`, `GradesViewModel`, `GradesView`):
  Liste in Cache-Reihenfolge + Schnitt, Refresh, Paginierung.
- [x] **C6 — Verdrahtung**: Hausaufgaben- und Noten-Tabs in `MainTabs`,
  `landing`-Ziele `hausaufgaben`/`noten` beachten.
- [x] **C7 — Offline-Tests**: wie B7 plus Filter/Zähler/Sortierung und
  Statuswechsel-Sichtbarkeit nach Reload.

Abnahme C: Filter, Zähler, Sortierung wie `/hausaufgaben`; Swipe-Verhalten
wie im Web; Noten mit Schnitt wie `/noten`.

## Phase 3 — Feinschliff

- [x] **F1 — Start-Tab aus `landing`-Setting**: nach Login und beim Start
  den Tab aus `GET /settings` wählen (`uebersicht/dashboard/hausaufgaben/
  noten/stundenplan`, Fallback Übersicht). Betrifft `RootView`/`MainTabs`.
- [x] **F2 — Launcher-Icon**: `Assets.xcassets` mit eigenem Icon anlegen,
  Ziel aus `IOS.md` §2-TODO schließen.
- [ ] **F3 — Leere-/Fehlerzustände vereinheitlichen**: alle Tabs zeigen
  konsistent Lade-, Leer- und Fehlerzustände (bestehende Bausteine
  `AuthAwareError`, `CountChip`, `SectionHead` wiederverwenden).
- [x] **F4 — Offline-Tests für A/D nachziehen** (falls fehlend): Login-,
  Token- und Settings-Fluss sowie Stundenplan/Essen/Wetter-Fehlercodes
  (`VALIDATION` ohne Ort, `CONFIG_MISSING` ohne Schlüssel).
- [ ] **F5 — `IOS.md` nachziehen**: gebaute Pakete B/C auf GEBAUT setzen,
  Stand-Zeilen mit Dateilisten ergänzen (wie bei 0/A/D geschehen).

## Phase 4 — End-zu-End-Abnahme

Voraussetzung: Backend läuft lokal (`python app.py`), Simulator,
`GET /api/v1/health` grün.

- [ ] **E1 — Anmelden** (inkl. simulierter 2FA-Pflicht), jede Liste mit
  Paginierung durchblättern.
- [ ] **E2 — Schreibaufrufe**: Nachricht senden + beantworten, Aufgabe als
  erledigt markieren + in Papierkorb legen/zurückholen, Cache leeren.
- [ ] **E3 — Abmelden** mit anschließend abgelehntem Token
  (`TOKEN_INVALID`); Geräte-Tab zeigt Widerruf sofort.
- [ ] **E4 — Web-Parität**: `python tests/test_api_e2e.py` grün; alle Tabs
  gegen dieselben Daten wie die Web-Seiten geprüft.
- [ ] **E5 — Build sauber**: keine Xcode-Warnungen im eigenen Code,
  `swiftc -parse` über alle Dateien grün (Fallback ohne Xcode).

## Reihenfolge und Abhängigkeiten

1. Phase 1 und 2 parallel baubar (nur gegen eingefrorenes Paket 0 +
   `openapi.json`), danach zusammenführen: erst Nachrichten-Tab, dann
   Hausaufgaben/Noten-Tabs.
2. Phase 3 nach dem Merge (F1 braucht alle Tabs).
3. Phase 4 zum Schluss, alles auf einmal.

## Nicht-Ziele (wie `IOS.md` §8)

Push-Benachrichtigungen, Datei-Uploads aus der App,
Mehrbenutzer-Verwaltung, Produktiv-Betrieb — der Server bleibt ein lokales
Werkzeug.
