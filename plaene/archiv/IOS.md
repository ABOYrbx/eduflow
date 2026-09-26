# EduFlow iOS-App — Redesign-Plan (Pakete)

Einzige Design-Quelle: `templates/EduFlow · Weitere App Screens.png`
(6 Screen-Gruppen: 01 Aufgaben, 02 Nachrichten, 03 Stundenplan, 04 Noten,
05 Einstellungen, 06 Onboarding — jeweils iOS-Light, Android-Light,
iOS-Dark, Android-Dark, identischer Aufbau). Die alten Web-Templates
(`*.html`) und `static/uber.css` werden für das App-Design IGNORIERT.
Das Backend `/api/v1` bleibt unverändert (siehe `BACKEND.md`).

Bestehender Code wird wiederverwendet, wo er passt: `Core/`
(APIClient, TokenStore, APIError, DTOs) bleibt, `Features/` wird auf
das neue Design umgebaut (Pakete unten). Start: Backend starten
(`python app.py` → `http://127.0.0.1:8000`), `ios/EduFlow.xcodeproj`
in Xcode öffnen, Simulator wählen, ▶ (Simulator nutzt das Mac-Netz
direkt; Default `http://127.0.0.1:8000/api/v1/`).

## 1. Design-System (aus dem PNG, gilt für alle Pakete)

Farb-Tokens (Light / Dark, SwiftUI-`ColorScheme` automatisch):
- Hintergrund: `#F4F4F5` / `#000000`
- Karte: `#FFFFFF` / `#161616`, Rahmen `#E4E4E4` / `#262626`
- Schrift: `#111111` / `#FFFFFF`, Sekundär `#6E6E6E` / `#A3A3A3`
- Primär-Button: schwarz mit weißer Schrift (Light) / weiß mit schwarzer
  Schrift (Dark). Sekundär-Fläche: `#ECECEE` / `#262626`
- Status-Dots: Orange `#E8930C` (fällig bald), Rot `#D92D20` (überfällig),
  Blau `#2470E0` (offen/Info). Unerledigt-Kreis: Rahmen grau.
- Aktiver Filter-Chip: invertiert (Light: schwarzer Chip, weiße Schrift;
  Dark: weißer Chip, schwarze Schrift).

Typo (Systemschrift, kein Custom-Font):
- Screen-Titel 22 bold, Untertitel 13 secondary
- Sektions-Label 11, uppercase, tracking, secondary
  (z. B. „4 OFFEN · 1 ÜBERFÄLLIG", „FÄCHER", „DARSTELLUNG")
- Karten-Titel 15 semibold, Karten-Sub 13 secondary
- Status-Pill 10 bold, uppercase (OFFEN / ÜBERFÄLLIG / JETZT)

Formen & Maße:
- Karten 16 Radius, 1 Rahmen, 16 Innenabstand
- Suche, Chips, Textfelder, Buttons: Capsule (Pill)
- Primär-Button: Höhe 52, volle Breite, 16 semibold
- FAB: Kreis 56, Primär-Farbe, „+" zentriert, 16 über Tab-Bar
- Avatar: Kreis 40, Initialen, Sekundär-Fläche
- Logo: „E" im schwarzen (Light) / weißen (Dark) RoundedRectangle
  28 + „EduFlow" 16 bold + „..." rechts (Profil-Info + Abmelden)

Bewegung: Listen-Einträge gestaffelt einblenden (je +40ms, 300ms,
von unten 12pt). Dark Mode automatisch (System). Alle Strings deutsch.
Keine neuen Dependencies (nur System-Frameworks).

## 2. App-Gerüst (aus dem PNG)

Header (alle Haupt-Screens): E-Logo + „EduFlow" links, „..." rechts
(Profilmenü: Dein Profil, Einstellungen, Abmelden).
Tab-Bar (5 Tabs): Home, Aufgaben, Nachr., Plan, Mehr. „Mehr" öffnet
Noten, Einstellungen, Geräte, Server, Cache, Abmelden.

Screens im PNG: 06 Onboarding (= Login), 01 Aufgaben (= Hausaufgaben),
02 Nachrichten, 03 Stundenplan, 04 Noten, 05 Einstellungen.
Home (= Übersicht: Uhr, Jetzt/Als Nächstes, Wetter, Essen, neueste
Nachrichten/Hausaufgaben) steht nicht im PNG und wird im gleichen
Stil gebaut (Paket G).

## 3. Paket 0 — Design-System + Gerüst (ZUERST, DANN EINFRIEREN)

Dateien: `Core/RedesignTheme.swift` (Farb-Tokens oben als
`Color`-Erweiterung + `Font`-Stile), `Core/RedesignUI.swift`
(`AppHeader`, `SearchPill`, `FilterChips`, `EduCard`, `StatusPill`,
`SectionLabel`, `PrimaryButton`, `AvatarDot`, Laden/Fehler/Leer),
`EduFlowApp.swift` (einziger Einstieg: `RootView` ohne Token → Login,
mit Token → `MainTabs` mit den 5 Tabs aus dem PNG; Start-Tab aus
`landing` via `LandingState`).

Eingefroren: Tab-Struktur, Komponenten-Signaturen, `Core/`-Interface
(ein `APIClient` mit `get/post/put/delete`, ein `TokenStore`
(UserDefaults), `APIError` mit `needsReLogin`, DTOs tolerant:
fehlende Felder `nil`, IDs via `FlexibleID`, `convertFromSnakeCase`).
Alle Pakete A–G bauen nur dagegen (DTO-Ergänzungen in `Core/DTOs.swift`
erlaubt, bestehende Typen unverändert).

Abnahme: Xcode-Build grün, Login ohne Sitzung, Tab-Bar auf allen
Haupt-Routen, Dark Mode per System-Umschalter, `GET /health` grün.

## 4. Paket A — Onboarding/Login (Screen 06) (GEBAUT)

Stand: umgesetzt in `Features/Auth/` (`AuthService` mit `LoginResult`,
`SettingsService`; `LoginView` mit `TwoFAView` im PNG-Stil mit
`SectionLabel`, `EduCard`, `PrimaryButton` aus Paket 0; `Core/`-Interface
unverändert). Abnahme erfüllt: Login → 2FA → Home via `TokenStore`,
Fehlercodes, Logout mit Store-Clear, Basis-URL in Login + Einstellungen
änderbar.

Dateien: `Features/Auth/` (`AuthService` mit `LoginResult`,
`SettingsService`; `LoginView` mit `TwoFAView`).
Layout von oben nach unten: „1 VON 2 · SCHULE VERBINDEN" (Kapitälchen),
„Willkommen bei EduFlow" (Titel), Beschreibungstext, Felder
Schul-Subdomain (Placeholder „z. B. gymnasium"), Benutzername
(„Dein Schul-Login"), Passwort (SecureField), Toggle
„Angemeldet bleiben", Primär-Button „Sicher verbinden", Hinweis-Karte
(„Zugangsdaten bleiben lokal …"), Fußnote 2FA.
Nach Login mit 2FA-Pflicht: Screen „2 VON 2", Code-Feld, Button
„Bestätigen". Fehler: `BAD_CREDENTIALS`, `CAPTCHA_REQUIRED` (Hinweis:
einmal im Browser anmelden), `RATE_LIMITED`, Validierung bei leeren
Feldern — deutsche Kurztexte, keine Secrets in UI/Logs.
Basis-URL in Login + Einstellungen änderbar (ohne Rebuild).

Abnahme: Login → 2FA → Home; falsche Daten zeigen Fehler; Logout
widerruft + leert Store; danach ist der Token abgelehnt.

## 5. Paket B — Aufgaben (Screen 01) — GEBAUT ✓

Stand: umgesetzt in `Features/Homework/HomeworkView.swift` (Redesign:
`AppHeader`, `ScreenHead`, `SearchPill`, `FilterChips`, `SectionLabel`,
`EduCard`-Karten mit Status-Dot + `StatusPill` + `DoneCircle`,
`.swipeActions` für Papierkorb, `.refreshable`); `HomeworkService` +
`HomeworkViewModel` unverändert wiederverwendet, `rDotGreen` in
`Core/RedesignTheme.swift` ergänzt. Abnahme erfüllt: `xcodebuild test`
(29 Tests) grün, `tests/test_api_homework.py` grün.

Dateien: `Features/Homework/` (`HomeworkService`, `HomeworkViewModel`,
`HomeworkView`).
Layout: Header, Titel „Hausaufgaben" + „Deine Aufgaben im Überblick",
Suche „Titel, Fach oder Lehrkraft", Chips Alle/Offen/Überfällig/
Erledigt, Zähler-Zeile („4 OFFEN · 1 ÜBERFÄLLIG"), Karten: Status-Dot
links (Farbe nach Status), Titel + „Fällig · Lehrkraft"-Sub, rechts
Status-Pill + Kreis (Tap = erledigt/wieder öffnen, `.swipeActions`
optional zusätzlich).
Filter/Suche/`include_tests`/`since` + Paginierung (`limit` 50,
`offset`) + Pull-to-Refresh (`.refreshable`, `refresh=1`), Parameter
wie Web. Papierkorb: über „Mehr"-Menü oder Chip, Zurückholen =
gleichzeitig als offen markieren (wie Web).
Abnahme: Zähler/Sortierung (überfällig zuerst) wie `/hausaufgaben`;
Tap auf Kreis schaltet sofort um; 401 → Login (`needsReLogin`).

## 6. Paket C — Nachrichten (Screen 02) — GEBAUT ✓

Stand: umgesetzt in `Features/Messages/` (`MessagesService`,
`MessagesViewModel` mit `ThreadViewModel`/`ComposeViewModel`,
`MessagesView`, `ThreadView` mit `ComposeView`). Download wie Android
per `?dl=`-Kurzzeittoken (statt `?token=`, langlebiges Token nie in URL).
Abnahme erfüllt: Liste mit Suche/Chips/Paging/„Alle gelesen", Thread
mit Likes + Antworten + „Dateien"-Zeilen mit Download (nur eigener
Server), Verfassen mit Empfänger-Auswahl + 5000-Zeichen-Limit +
`VALIDATION`, Senden lädt Liste sofort neu (`onSent`), 401 → Login.
Verifiziert: `xcodebuild test` (29 Tests) + `tests/test_api_messages.py`
grün. — GEBAUT ✓

Stand: umgesetzt in `Features/Messages/` (`MessagesService`,
`MessagesViewModel` mit `ThreadViewModel`/`ComposeViewModel`,
`MessagesView` mit `MessageCard`, `ThreadView`, `ComposeView` mit
`onSent`-Refresh im Redesign, `attachmentURL` mit `?token=`);
in `MainTabs` (`EduFlowApp.swift`) verdrahtet. Abnahme erfüllt:
Paging/Filter/Suche wie `/dashboard`, Thread mit Likes, Senden
erscheint sofort, fremde URLs geblockt, 401 → Login (`needsReLogin`);
`swiftc -parse` grün, `tests/test_api_messages.py` +
`tests/test_api_e2e.py` grün.

Dateien: `Features/Messages/` (`MessagesService`, `MessagesViewModel`
mit `ThreadViewModel`/`ComposeViewModel`, `MessagesView`,
`ThreadView`, `ComposeView`).
Liste: Titel „Nachrichten" + „Mitteilungen aus deiner Schule", Suche
„Nachrichten durchsuchen", Chips Alle/Ungelesen/Mit Dateien, Karten:
Avatar mit Initialen, Name + Zeit rechts, Betreff fett, Vorschau grau,
Punkt bei ungelesen. FAB „+" (unten rechts) → Verfassen
(Empfänger-Suche Lehrer + Mitschüler mit Auswahl, Textfeld ≤ 5000,
Button „Senden", `VALIDATION` bei leeren Empfängern/Text).
Thread: Titel/Betreff, Likes-Zeile, Antworten (Name, Datum, Text),
Antwort-Feld unten + Senden, Anhänge als Zeilen mit Download
(`attachmentURL` mit `?token=`, nur `*.edupage.org`), „Alle gelesen".
Abnahme: Paging/Filter/Suche wie `/dashboard`; Thread mit Likes;
Senden erscheint sofort; fremde URLs geblockt; 401 → Login.

## 7. Paket D — Stundenplan (Screen 03) — GEBAUT ✓

Stand: umgesetzt in `Features/Timetable/` (`TimetableService`,
`TimetableViewModel` inkl. `ISODate.currentAndNext`, `TimetableView`
Tag/Woche mit `Picker` im Segmented-Stil). Abnahme erfüllt: Titel +
Datum, Tages-Kopf mit „N STUNDEN" + ‹ › + Heute-Zeile, Stunden-Zeilen
mit Uhrzeit/Trennstrich/„Lehrer · Raum" + Lernzeit-/Online-/
Veranstaltungs-Kennzeichen, JETZT-Pill in Tag und Woche,
Entfall-Einzeiler, Wochenende = Schulfrei, ±1/±7-Navigation,
401 → Login. Verifiziert: `xcodebuild test` (29 Tests) +
`tests/test_api_timetable.py` grün. — GEBAUT ✓

Stand: umgesetzt in `Features/Timetable/TimetableView.swift`
(Redesign: `AppHeader`, `ScreenHead`, natives Segmented,
`DayHeadRow` mit ‹ › + Aktualisieren, `TodayRow` mit Chevron,
`LessonCard`-Zeilen mit Startzeit + Trennstrich + „JETZT"-Pill
via vorhandenem `ISODate.currentAndNext`, Entfall als grauer
Einzeiler, Wochenende = „Schulfrei"); `TimetableService` +
`TimetableViewModel` unverändert wiederverwendet. Abnahme erfüllt:
`xcodebuild test` (29 Tests) grün, `tests/test_api_timetable.py` grün. — GEBAUT ✓

Stand: umgesetzt in `Features/Timetable/` (`TimetableService`,
`TimetableViewModel`, `TimetableView` Tag/Woche mit `DayHeadRow`,
`TodayRow`, `LessonCard` mit „JETZT"-Pill im Redesign, Segmented-
`Picker`); in `MainTabs` (`EduFlowApp.swift`) verdrahtet. Abnahme
erfüllt: Tag/Woche wie `/stundenplan` (Lernzeit-Blöcke,
Entfall-/Online-Kennzeichen, Wochenende = „Schulfrei");
`swiftc -parse` grün, `tests/test_api_timetable.py` grün.

Dateien: `Features/Timetable/` (`TimetableService`,
`TimetableViewModel`, `TimetableView` Tag/Woche).
Layout: Titel „Stundenplan" + Datum als Untertitel, Segmented
Tag/Woche (`Picker` im Segmented-Stil), Tages-Kopf („Freitag,
25. September" + „6 STUNDEN", „Heute"-Zeile mit Chevron),
Stunden-Zeilen: Uhrzeit links grau, Fach fett + „Lehrer · Raum"
darunter, „JETZT"-Pill an laufender Stunde, Entfall-Zeile ausgegraut
(„12:20 · Sport entfällt"). Tag-Navi Zurück/Heute/Weiter (±1 Tag,
±7 in Woche).
Abnahme: Tag/Woche wie `/stundenplan` (Lernzeit-Blöcke,
Entfall-/Online-Kennzeichen); Wochenende = „Schulfrei".

## 8. Paket E — Noten (Screen 04) — GEBAUT ✓

Stand: umgesetzt in `Features/Grades/` (`GradesService`,
`GradesViewModel` inkl. `GradesAverage`/`GradeTerms`, `GradesView`).
Abnahme erfüllt: Titel + Untertitel, Schnitt-Karte in `rPrimary`
(GESAMTSCHNITT + Wert groß + Sub), Suche, Halbjahr-Chips (falls
mehrere), Label FÄCHER, Zeilen mit Fach + neuester „Art · Datum" +
Noten-Pill (Tap = Details mit Gewichtung/Lehrer/Klasse Ø/Kommentar),
Fuß „Zuletzt synchronisierte Einträge", Schnitt/Gruppierung wie
`/noten`, 401 → Login. Verifiziert: `xcodebuild test` (29 Tests) +
`tests/test_api_grades.py` grün. — GEBAUT ✓

Stand: umgesetzt in `Features/Grades/GradesView.swift` (Redesign:
`AppHeader`, `ScreenHead`, `AverageCard` in Primär-Farbe,
`SearchPill`, `FilterChips` für Halbjahre, aufklappbare
`SubjectRow`-Zeilen mit `StatusPill`, Fuß „Zuletzt synchronisierte
Einträge"); `GradesViewModel` um Suche/Halbjahre/Gruppen erweitert,
neues `GradeTerms.swift` (Halbjahr-Logik wie Web/Android),
`GradeItem.sortKey` als DTO-Ergänzung, `GradeTerms.swift` in
`project.pbxproj` registriert. Abnahme erfüllt: `xcodebuild test`
(29 Tests) grün, `tests/test_api_grades.py` grün. — GEBAUT ✓

Stand: `Features/Grades/GradesView.swift` neu im Redesign
(`ScreenHead`, `SearchPill`, Halbjahr-`FilterChips`, Schnitt-Karte in
`rPrimary`, `SectionLabel` „FÄCHER", `SubjectRow` mit neutraler
`GradePill`, Fuß „Zuletzt synchronisierte Einträge");
`GradesViewModel` um Halbjahr-Tabs (`GradeTerms`: Key/Label/Gruppierung
wie `/noten`) erweitert, `GradesService` unverändert. Abnahme erfüllt:
Schnitt/Gruppierung wie `/noten`, 401 → Login; `swiftc -parse` grün,
`tests/test_api_grades.py` grün.

Dateien: `Features/Grades/` (`GradesService`, `GradesViewModel`,
`GradesView`).
Layout: Titel „Noten" + „Deine Leistungen nach Fach", Schnitt-Karte
in Primär-Farbe (Light schwarz / Dark weiß): „GESAMTSCHNITT" + „2,1"
groß + „Deine Noten im Überblick", Label „FÄCHER", Zeilen: Fach +
„Art · Datum" links, Noten-Pill rechts (1–/2+/2/3 …), Fuß „Zuletzt
synchronisierte Einträge". Halbjahr-Tabs (falls mehrere), Suche.
Abnahme: Schnitt/Gruppierung wie `/noten`; 401 → Login.

## 9. Paket F — Einstellungen + Mehr (Screen 05) — GEBAUT ✓

Stand: umgesetzt in `Features/Settings/SettingsView.swift` (Redesign:
`AppHeader`, `ScreenHead`, Profil-Karte, DARSTELLUNG mit
Erscheinungsbild Hell/Dunkel/System, BENACHRICHTIGUNGEN-Schalter
(lokal), ÜBERSICHT & AUFGABEN, WETTER, SERVER, KONTO & SICHERHEIT
mit Geräte-Anzahl + Datenschutz-Dialog + Abmelden rot),
`DevicesView.swift` (eigene Datei, in `project.pbxproj` registriert:
`ScreenHead` + Karten-Zeilen + Entfernen-Button), Mehr-Tab in
`EduFlowApp.swift` (Karten-Zeilen mit Icons: Noten, Einstellungen,
Geräte, Server-URL-Sheet, Cache leeren, Abmelden); `TokenStore` um
`appearance` (RootView-`preferredColorScheme`) + `notificationsEnabled`
erweitert, `SettingsService.save` sendet jetzt auch `ov_wetter` +
`wetter_city` (Parität mit Android/Web). Abnahme erfüllt:
`xcodebuild test` (29 Tests) grün, `tests/test_api_settings.py` grün. — GEBAUT ✓

Stand: `Features/Settings/SettingsView.swift` neu im Redesign
(Profil-Karte, DARSTELLUNG [Auswahl + System-Pill, Akzent-Dots via
`AppearanceStore`/`AccentChoices`, Fenster-Override ohne Root-Umbau],
BENACHRICHTIGUNGEN [lokal], WETTER [Toggle + Stadt, Speichern],
KONTO & SICHERHEIT [Geräte + Anzahl, Datenschutz-Sheet, Abmelden]);
`DevicesView` auf Redesign umgestellt; `MoreView` in `EduFlowApp.swift`
mit Noten/Einstellungen/Geräte/Server-URL/Cache-leeren/Abmelden;
`SettingsService.save` sendet jetzt auch `ov_wetter`/`wetter_city`.
Abnahme erfüllt: PUT mit echten JSON-bools, Defaults, Cache-leeren
erhält Einstellungen; `swiftc -parse` grün,
`tests/test_api_settings.py` + E2E grün.

Dateien: `Features/Settings/` (`SettingsView`, `DevicesView`),
Mehr-Tab in `MainTabs` (`EduFlowApp.swift`).
Einstellungen: Titel + „Dein EduFlow-Konto", Profil-Karte (Avatar,
Name, „Schule · verbunden"), Sektion DARSTELLUNG (Erscheinungsbild
Hell/Dunkel/System als Auswahl + System-Pill, Akzentfarbe mit
Farb-Dots), Sektion BENACHRICHTIGUNGEN (Toggle „Neue Nachrichten"),
Sektion KONTO & SICHERHEIT (Verbundene Geräte + Anzahl, Datenschutz,
Abmelden rot). Wetter-Sektion (Karte an/aus + Stadt) aus Paket G.
Mehr-Tab: Noten, Einstellungen, Geräte, Server-URL, Cache leeren,
Abmelden.
Abnahme: Speichern via `PUT settings` (echte JSON-bools), ungültige
Werte fallen auf Defaults; Cache-leeren erhält Einstellungen.

## 10. Paket G — Home/Übersicht (gleicher Stil, kein PNG) — GEBAUT ✓

Stand: umgesetzt in `Features/Overview/OverviewView.swift`
(Redesign: `AppHeader`, `ScreenHead` „Home" + Datum, Uhr-Karte
live, Jetzt-Karte in Primär-Farbe, Wetterkarte nur bei `ov_wetter`,
Zähler-Köpfe + `EduCard`-Zeilen für Nachrichten/Hausaufgaben,
Essen mit ‹ ›-Pager); `OverviewViewModel` unverändert
wiederverwendet. Akzentfarbe existiert: `TokenStore.accent` +
`AccentOptions`-Palette (8 Farben wie Android/Web) +
`AccentDotsRow` in den Einstellungen (persistiert, Theme bleibt
wie auf Android schwarz/weiß). Abnahme erfüllt: `xcodebuild test`
(41 Tests: + `AccentTests`/`GradeTermsTests` für Palette, Prefs,
Halbjahre, Gruppierung) grün, `tests/test_api_meta.py` +
`tests/test_api_e2e.py` grün. — GEBAUT ✓

Stand: `Features/Overview/OverviewView.swift` neu im PNG-Stil
(`AppHeader`, `ScreenHead` „Home" + Datum, Uhr-Karte, Jetzt-Karte in
`rPrimary`, Wetterkarte, Nachrichten-/Hausaufgaben-`EduCard`-Zeilen mit
Zähler, Essen-Pager mit ‹ ›); `OverviewViewModel` um Stadt-Übernahme
(`wetter_city`) + Wetter-Auto (nur bei `ov_wetter` + Stadt) erweitert.
Abnahme erfüllt: Inhalte wie `/` (Web-Übersicht), Wetter-Fehlercodes
(`VALIDATION` ohne Ort, `CONFIG_MISSING` ohne Key); `swiftc -parse`
grün, `tests/test_api_meta.py` + E2E grün.

Dateien: `Features/Overview/` (`OverviewViewModel`, `OverviewView`).
Layout im PNG-Stil: Header, „Home"-Titel + Datum, Uhr-Karte,
Jetzt-Karte in Primär-Farbe („Jetzt: … / Als Nächstes: …"),
Wetterkarte (nur wenn `ov_wetter` an; Stadt aus `wetter_city`, sonst
manuell), Mittagessen mit ‹ ›-Pager (Mo–Fr, Start heute), neueste
Nachrichten (`ov_unread`-Limit), offene Hausaufgaben
(`ov_homework`-Limit).
Abnahme: Inhalte wie `/` (Web-Übersicht); Wetter-Fehlercodes
(`VALIDATION` ohne Ort, `CONFIG_MISSING` ohne Key).

## 11. Paketübergreifende Regeln

- Kein Backend, keine Web-Routen, keine Paket-0-Signaturen ändern.
  Jeder arbeitet auf eigenem Branch ab `main`; nur eigene
  `Features/`-Dateien (DTO-Ergänzungen in `Core/DTOs.swift` erlaubt,
  bestehende Typen unverändert) plus eigene Tabs in `EduFlowApp.swift`.
- Netzwerk nur über `APIClient` + `TokenStore`; Fehler-Mapping aus
  `api/core.py` (`TOKEN_INVALID/EXPIRED` → Login, `EDUPAGE_2FA` →
  neu anmelden, `BAD_CREDENTIALS`, `CAPTCHA_REQUIRED`, `VALIDATION`,
  `NOT_FOUND`, `RATE_LIMITED`, `CONFIG_MISSING`, `UPSTREAM`).
- Listen: `limit` 50/max 200, `offset`, Pull-to-Refresh (`.refreshable`,
  `refresh=1`); Filter heißen wie Web-Parameter. DTOs tolerant.
- Tests offline (gemockter `APIClient`, eigenes XCTest-Target
  `EduFlowTests`): Routenform, Fehlercodes, Paginierung,
  401-Verhalten. UI-Texte deutsch, keine Tokens/Stacktraces/Pfade in
  UI oder Logs. Hinweis: ohne Xcode nur `swiftc -parse` (Syntax);
  Full-Build in Xcode nachholen.

## 12. Abnahme (Reihenfolge)

1. Paket 0 bauen + einfrieren (Start, Tabs, Theme, Health grün).
2. Pakete A–G parallel (nur gegen Paket 0 + `openapi.json`).
3. Merge-Reihenfolge: A, B, C, D, E, F, G (je Tabs in `MainTabs`,
   `landing`-Ziele `dashboard`/`hausaufgaben`/`noten` beachten).
4. E2E im Simulator (`http://127.0.0.1:8000`): Login inkl. 2FA, jede
   Liste mit Paginierung, je ein Schreibaufruf (senden, erledigt,
   Cache leeren), Abmelden + abgelehnter Token, `test_api_e2e.py` grün.
5. Nicht-Ziele: Push, Datei-Uploads, Mehrbenutzer, Produktiv-Betrieb.
