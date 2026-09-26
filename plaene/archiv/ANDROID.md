# EduFlow Android-App — Redesign-Plan (Pakete)

Einzige Design-Quelle: `templates/EduFlow · Weitere App Screens.png`
(6 Screen-Gruppen: 01 Aufgaben, 02 Nachrichten, 03 Stundenplan, 04 Noten,
05 Einstellungen, 06 Onboarding — jeweils iOS-Light, Android-Light,
iOS-Dark, Android-Dark, identischer Aufbau). Die alten Web-Templates
(`*.html`) und `static/uber.css` werden für das App-Design IGNORIERT.
Bestehende Backend-Verträge bleiben stabil; additive Endpunkte sind in
`BACKEND.md` dokumentiert.

Bestehender Code wird wiederverwendet, wo er passt: `data/` (ApiService,
ApiClient, TokenStore, Repositories, DTOs) bleibt, `ui/` wird auf das
neue Design umgebaut (Pakete unten). Die alte Pillen-TopBar (`TopBar.kt`)
entfällt — Navigation läuft über die Bottom-Bar aus dem PNG.

## 1. Design-System (aus dem PNG, gilt für alle Pakete)

Farb-Tokens (Light / Dark):
- Hintergrund: `#F4F4F5` / `#000000`
- Karte: `#FFFFFF` / `#161616`, Rahmen `#E4E4E4` / `#262626`
- Schrift: `#111111` / `#FFFFFF`, Sekundär `#6E6E6E` / `#A3A3A3`
- Primär-Button: schwarz mit weißer Schrift (Light) / weiß mit schwarzer
  Schrift (Dark). Sekundär-Fläche: `#ECECEE` / `#262626`
- Status-Dots: Orange `#E8930C` (fällig bald), Rot `#D92D20` (überfällig),
  Blau `#2470E0` (offen/Info). Unerledigt-Kreis: Rahmen grau.
- Aktiver Filter-Chip: schwarz/weiß invertiert (Light: schwarzer Chip,
  weiße Schrift; Dark: weißer Chip, schwarze Schrift).

Typo (Systemschrift, keine Custom-Font nötig):
- Screen-Titel 22sp fett, Untertitel 13sp grau
- Sektions-Label 11sp, Kapitälchen, letterspaced, grau
  (z. B. „4 OFFEN · 1 ÜBERFÄLLIG", „FÄCHER", „DARSTELLUNG")
- Karten-Titel 15sp semibold, Karten-Sub 13sp grau
- Status-Pill 10sp fett, uppercase (OFFEN / ÜBERFÄLLIG / JETZT)

Formen & Maße:
- Karten 16dp Radius, 1dp Rahmen, 16dp Innenabstand
- Suche, Chips, Textfelder, Buttons: vollrund (Pill)
- Primär-Button: Höhe 52dp, volle Breite, 16sp semibold
- FAB: Kreis 56dp, Primär-Farbe, „+" zentriert, 16dp über Bottom-Bar
- Avatar: Kreis 40dp, initials, graue Fläche (`#ECECEE` / `#262626`)
- Logo: „E" in schwarzem (Light) / weißem (Dark) Rundquadrat 28dp +
  Schriftzug „EduFlow" 16sp fett + „..."-Menü rechts

Bewegung: Listen-Einträge blenden gestaffelt ein (je +40ms, 300ms,
von unten 12dp). Dark Mode folgt dem System (der Light/Dark-Schalter
im PNG ist nur Präsentation). Alle Strings deutsch.

## 2. App-Gerüst (aus dem PNG)

Header (alle Haupt-Screens): E-Logo + „EduFlow" links, „..." rechts
(Profilmenü: Dein Profil, Einstellungen, Abmelden).
Bottom-Bar (5 Tabs, deutsche Kurzlabels): Home, Aufgaben, Nachr., Plan,
Mehr. Aktiv-Tab: Pill-Hintergrund in Primär-Farbe. „Mehr" öffnet
Noten, Einstellungen, Geräte, Server, Cache, Abmelden.

Screens im PNG: 06 Onboarding (= Login), 01 Aufgaben (= Hausaufgaben),
02 Nachrichten, 03 Stundenplan, 04 Noten, 05 Einstellungen.
Home (= Übersicht: Uhr, Jetzt/Als Nächstes, Wetter, Essen, neueste
Nachrichten/Hausaufgaben) steht nicht im PNG und wird im gleichen
Stil gebaut (Paket G).

## 3. Paket 0 — Design-System + Gerüst (ZUERST, DANN EINFRIEREN)

Dateien: `ui/theme/Color.kt` (Tokens oben), `ui/theme/Type.kt`
(Systemschrift, Größen/Gewichte oben), `ui/theme/Theme.kt`
(`EduFlowTheme` + Dark-via-System), `ui/common/RedesignUi.kt`
(`AppHeader`, `SearchPill`, `FilterChips`, `EduCard`, `StatusPill`,
`SectionLabel`, `PrimaryButton`, `AvatarDot`, `LoadingBox`,
`ErrorBox`, `EmptyBox`), `ui/navigation/Routes.kt` (Routen:
`login`, `twofa?pending={pending}`, `home`, `homework`, `messages`,
`messages/thread/{id}`, `messages/neu`, `timetable`, `grades`,
`settings`, `devices`, `more`), `ui/navigation/BottomBar.kt` +
`NavGraph.kt` (einziger NavHost, Start aus Sitzung: ohne Token →
Login, mit Token → `landing`-Setting), `MainActivity.kt`
(Theme + NavHost verdrahten, alte TopBar entfernen).

Eingefroren: Routen-Namen, Komponenten-Signaturen, `data/`-Interface
(ein Retrofit-`ApiService`, ein `TokenStore`, Bearer-Interceptor,
DTOs tolerant). Alle Pakete A–G bauen nur dagegen.

Abnahme: App startet ohne Crash, Login ohne Sitzung, Bottom-Bar auf
allen Haupt-Routen, Dark Mode per System-Umschalter, `GET /health`
grün gegen `http://10.0.2.2:8000`.

## 4. Paket A — Onboarding/Login (Screen 06) (GEBAUT)

Stand: umgesetzt in `ui/auth/` (`AuthViewModel`, `LoginScreen`,
`TwoFaScreen` im PNG-Stil mit `SectionLabel`, `EduCard`,
`PrimaryButton` aus Paket 0; Logik und `data/`-Interface unverändert).
Abnahme erfüllt: Login → 2FA → Home via Session-Flow, Fehlercodes,
Logout mit Store-Clear, Basis-URL in Login + Einstellungen änderbar.

Dateien: `ui/auth/` (`AuthViewModel`, `LoginScreen`, `TwoFaScreen`).
Layout von oben nach unten: „1 VON 2 · SCHULE VERBINDEN" (Kapitälchen),
„Willkommen bei EduFlow" (Titel), Beschreibungstext, Felder
Schul-Subdomain (Placeholder „z. B. gymnasium"), Benutzername
(„Dein Schul-Login"), Passwort (maskiert), Checkbox
„Angemeldet bleiben", Primär-Button „Sicher verbinden", Hinweis-Karte
(„Zugangsdaten bleiben lokal …"), Fußnote 2FA.
Nach Login mit 2FA-Pflicht: Screen „2 VON 2", Code-Feld, Button
„Bestätigen". Fehler: `BAD_CREDENTIALS`, `CAPTCHA_REQUIRED` (Hinweis:
einmal im Browser anmelden), `RATE_LIMITED`, Validierung bei leeren
Feldern — deutsche Kurztexte, keine Secrets in UI/Logs.
Basis-URL (Default `http://10.0.2.2:8000/api/v1/`) in Login + Mehr
änderbar (`normalizeBaseUrl`, ohne Rebuild).

Abnahme: Login → 2FA → Home; falsche Daten zeigen Fehler; Logout
widerruft + leert Store; danach ist der Token abgelehnt.

## 5. Paket B — Aufgaben (Screen 01) — GEBAUT ✓

Stand: umgesetzt in `ui/homework/HomeworkListScreen.kt` (Redesign:
`AppHeader`, `ScreenHead`, `SearchPill`, `FilterChips`, `SectionLabel`,
`EduCard`-Karten mit Status-Dot + Status-Pill + Kreis-Checkbox,
Wisch-Geste für Papierkorb), `HomeworkViewModel.kt` +
`HomeworkNavigation.kt` (mit `onOpenSettings`/`onLogout`, verdrahtet in
`NavGraph.kt`); `data/` (`HomeworkRepository`, `Homework`-DTOs)
unverändert wiederverwendet. Abnahme erfüllt: `assembleDebug` +
`testDebugUnitTest` (59 Tests) grün, `tests/test_api_homework.py` grün.

Dateien: `data/repository/HomeworkRepository.kt` (bestehend),
`data/dto/Homework.kt` (bestehend),
`ui/homework/{HomeworkViewModel, HomeworkListScreen, HomeworkNavigation}.kt`.
Layout: Header, Titel „Hausaufgaben" + „Deine Aufgaben im Überblick",
Suche „Titel, Fach oder Lehrkraft", Chips Alle/Offen/Überfällig/
Erledigt, Zähler-Zeile („4 OFFEN · 1 ÜBERFÄLLIG"), Karten: Status-Dot
links (Farbe nach Status), Titel + „Fällig · Lehrkraft"-Sub, rechts
Status-Pill + Kreis-Checkbox (tap = erledigt/wieder öffnen).
Filter/Suche/`include_tests`/`since` + Paginierung (`limit` 50,
`offset`) + Pull-to-Refresh (`refresh=1`), Parameter wie Web.
Papierkorb: über „Mehr"-Menü oder Chip erreichbar, Zurückholen =
gleichzeitig als offen markieren (wie Web).
Abnahme: Zähler/Sortierung (überfällig zuerst) wie `/hausaufgaben`;
tap auf Kreis schaltet sofort um; 401 → Login.

## 6. Paket C — Nachrichten (Screen 02) — GEBAUT ✓

Stand: umgesetzt in `ui/messages/` (`MessagesScreen.kt` mit Liste +
`ThreadScreen` + `ComposeScreen`, `MessagesViewModel.kt`,
`MessagesNavigation.kt` mit Routen Liste → Thread → Verfassen);
`data/` (`MessagesRepository` inkl. `?dl=`-Kurzzeittoken-Download,
`Messages`-DTOs) wiederverwendet. Abnahme erfüllt: Liste mit Suche/
Chips/Paging/„Alle gelesen", Thread mit Likes + Antworten + „Dateien"-
Zeilen mit Download (nur eigener Server), Verfassen mit Empfänger-
Checkboxen + 5000-Zeichen-Limit + `VALIDATION`, Senden lädt Liste neu,
401 → Login. Verifiziert: `tests/test_api_messages.py` grün; Android-
Build statisch geprüft (kein Gradle auf dieser Maschine). — GEBAUT ✓

Stand: umgesetzt in `ui/messages/` (`MessagesViewModel` mit
`ThreadViewModel`/`ComposeViewModel`, `MessagesScreen` mit `MessageCard`/
`ThreadScreen`/`ComposeScreen` im Redesign, `MessagesNavigation` mit
Thread-/Compose-Routen + `?dl=`-Download, verdrahtet in `NavGraph.kt`);
`data/` (`MessagesRepository`, `Messages`-DTOs) unverändert
wiederverwendet. Abnahme erfüllt: Liste/Thread/Verfassen wie
`/dashboard`, Paging/Filter/Suche, Senden erscheint sofort
(REFRESH_KEY), fremde URLs geblockt, 401 → Login;
`tests/test_api_messages.py` + `tests/test_api_e2e.py` grün.

Dateien: `data/MessagesRepository.kt`, `data/dto/Messages.kt`,
`ui/messages/{MessagesViewModel, MessagesScreen, ThreadScreen,
ComposeScreen, MessagesNavigation}.kt`.
Liste: Titel „Nachrichten" + „Mitteilungen aus deiner Schule", Suche
„Nachrichten durchsuchen", Chips Alle/Ungelesen/Mit Dateien, Karten:
Avatar mit Initialen, Name + Zeit rechts, Betreff fett, Vorschau grau,
Punkt bei ungelesen. FAB „+" → Verfassen (Empfänger-Suche Lehrer +
Mitschüler mit Checkboxen, Textfeld ≤ 5000, Button „Senden",
`VALIDATION` bei leeren Empfängern/Text).
Thread: Titel/Betreff, Likes-Zeile, Antworten (Name, Datum, Text),
Antwort-Feld unten („Antworten …" + Senden), Anhänge als Zeilen mit
Download (`?dl=`-Kurzzeittoken, nur `*.edupage.org`), „Alle gelesen".
Abnahme: Paging/Filter/Suche wie `/dashboard`; Thread mit Likes;
Senden erscheint sofort; fremde URLs geblockt; 401 → Login.

## 7. Paket D — Stundenplan (Screen 03) — GEBAUT ✓

Stand: umgesetzt in `ui/timetable/` (`TimetableViewModel`,
`DayScreen`, `WeekScreen` über `TimetableScreen`, `TimetableNavigation`);
`data/` (`TimetableRepository`, `Timetable`-DTOs) wiederverwendet.
Abnahme erfüllt: Titel + Datum, Segmented Tag/Woche, Tages-Kopf mit
„N STUNDEN" + ‹ › + Heute-Zeile, Stunden-Zeilen mit Uhrzeit/Trennstrich/
„Lehrer · Raum" + Lernzeit-/Online-/Veranstaltungs-Kennzeichen,
JETZT-Pill in Tag und Woche, Entfall-Einzeiler, Wochenende = Schulfrei,
±1/±7-Navigation, 401 → Login. Verifiziert:
`tests/test_api_timetable.py` grün; Android-Build statisch geprüft
(kein Gradle auf dieser Maschine). — GEBAUT ✓

Stand: umgesetzt in `ui/timetable/DayScreen.kt` (Redesign:
`AppHeader`, `ScreenHead`, lokales `TimetableSegmented`,
`DayHeadRow` mit ‹ › + Aktualisieren, `TodayRow` mit Chevron,
`LessonCard`-Zeilen mit Startzeit + Trennstrich + „JETZT"-Pill,
Entfall als grauer Einzeiler), `WeekScreen.kt` (gleicher Stil,
`HEUTE`-Pill in der heutigen Spalte), `TimetableViewModel.kt`
unverändert wiederverwendet; `TimetableNavigation.kt` +
`NavGraph.kt` (`timetableDestination` mit `onOpenSettings`/`onLogout`)
verdrahtet. Abnahme erfüllt: `assembleDebug` +
`testDebugUnitTest` (59 Tests) grün, `tests/test_api_timetable.py` grün. — GEBAUT ✓

Stand: umgesetzt in `ui/timetable/` (`TimetableViewModel`,
`TimetableScreen` mit `DayScreen`/`WeekScreen` im Redesign:
`TimetableSegmented`, `DayHeadRow`, `TodayRow`, `LessonCard` mit
„JETZT"-Pill, `AuthAwareError`, `TimetableNavigation`, verdrahtet in
`NavGraph.kt`); `data/` (`TimetableRepository`, `Timetable`-DTOs)
unverändert wiederverwendet. Abnahme erfüllt: Tag/Woche wie
`/stundenplan` (Lernzeit-Blöcke, Entfall-/Online-Kennzeichen,
Wochenende = „Schulfrei"); `tests/test_api_timetable.py` grün.

Dateien: `data/TimetableRepository.kt`, `data/dto/Timetable.kt`,
`ui/timetable/{TimetableViewModel, DayScreen, WeekScreen,
TimetableNavigation}.kt`.
Layout: Titel „Stundenplan" + Datum als Untertitel, Segmented
Tag/Woche, Tages-Kopf („Freitag, 25. September" + „6 STUNDEN",
„Heute"-Zeile mit Chevron), Stunden-Zeilen: Uhrzeit links grau,
Fach fett + „Lehrer · Raum" darunter, „JETZT"-Pill an laufender
Stunde, Entfall-Zeile ausgegraut („12:20 · Sport entfällt").
Tag-Navi Zurück/Heute/Weiter (±1 Tag, ±7 in Woche).
Abnahme: Tag/Woche wie `/stundenplan` (Lernzeit-Blöcke,
Entfall-/Online-Kennzeichen); Wochenende = „Schulfrei".

## 8. Paket E — Noten (Screen 04) — GEBAUT ✓

Stand: umgesetzt in `ui/grades/` (`GradesViewModel`, `GradesScreen`,
`GradesNavigation`); `data/` (`GradesRepository`, `Grades`-DTOs mit
`gradesAverage`/`groupGradesBySubject`/`buildGradeTerms`) wiederverwendet.
Abnahme erfüllt: Titel + Untertitel, Schnitt-Karte in Primär-Farbe
(GESAMTSCHNITT + Wert groß + Sub), Suche, Halbjahr-Chips (falls
mehrere), Label FÄCHER, Zeilen mit Fach + neuester „Art · Datum" +
Noten-Pill (Tap = Details mit Gewichtung/Lehrer/Klasse Ø/Kommentar),
Fuß „Zuletzt synchronisierte Einträge", Schnitt/Gruppierung wie
`/noten`, 401 → Login. Verifiziert: `tests/test_api_grades.py` grün;
Android-Build statisch geprüft (kein Gradle auf dieser Maschine). — GEBAUT ✓

Stand: umgesetzt in `ui/grades/GradesScreen.kt` (Redesign:
`AppHeader`, `ScreenHead`, `AverageCard` in Primär-Farbe,
`SearchPill`, `FilterChips` für Halbjahre, `SectionLabel`,
aufklappbare Fach-Zeilen mit neuester „Art · Datum" + Noten-Pill,
Fuß „Zuletzt synchronisierte Einträge"), `GradesViewModel.kt`
unverändert wiederverwendet; `GradesNavigation.kt` + `NavGraph.kt`
(`gradesDestination` mit `onOpenSettings`/`onLogout`) verdrahtet.
Abnahme erfüllt: `assembleDebug` + `testDebugUnitTest` (59 Tests)
grün, `tests/test_api_grades.py` grün. — GEBAUT ✓

Stand: `ui/grades/GradesScreen.kt` neu im Redesign (`AppHeader`,
`ScreenHead`, `SearchPill`, Halbjahr-`FilterChips`, Schnitt-Karte in
Primär-Farbe, `SectionLabel` „FÄCHER", `SubjectRow` mit neutraler
`GradePill`, Fuß „Zuletzt synchronisierte Einträge");
`GradesViewModel`, `GradesNavigation`, `data/` (`GradesRepository`,
`Grades`-DTOs mit Schnitt-/Halbjahr-Logik) unverändert
wiederverwendet. Abnahme erfüllt: Schnitt/Gruppierung wie `/noten`,
401 → Login; `tests/test_api_grades.py` grün.

Dateien: `data/repository/GradesRepository.kt`,
`data/dto/Grades.kt`,
`ui/grades/{GradesViewModel, GradesScreen, GradesNavigation}.kt`.
Layout: Titel „Noten" + „Deine Leistungen nach Fach", schwarze
(ulf: weiße) Schnitt-Karte: „GESAMTSCHNITT" + „2,1" groß +
„Deine Noten im Überblick", Label „FÄCHER", Zeilen: Fach + „Art ·
Datum" links, Noten-Pill rechts (1–/2+/2/3 …), Fuß „Zuletzt
synchronisierte Einträge". Halbjahr-Tabs (falls mehrere), Suche.
Abnahme: Schnitt/Gruppierung wie `/noten`; 401 → Login.

## 9. Paket F — Einstellungen + Mehr (Screen 05) — GEBAUT ✓

Stand: umgesetzt in `ui/settings/SettingsScreen.kt` (Redesign:
`ScreenHead`, Profil-Karte mit `session`, `AppearanceRow`
Hell/Dunkel/System + System-Pill, Akzent-Dots, „Neue Nachrichten"-
Schalter (lokal via SharedPreferences), Sektion „Übersicht &
Aufgaben" (Startseite-/Filter-Chips, Tests-Schalter, Limit-Felder),
Wetter (an/aus + Stadt, Speichern via PUT), Konto & Sicherheit
(Geräte + Anzahl, Datenschutz-Dialog, Abmelden rot)),
`DevicesScreen.kt` (`ScreenHead` + `EduCard`-Zeilen + Entfernen),
`ui/more/MoreScreen.kt` (Noten, Einstellungen, Geräte, Server-URL-
Dialog, Cache leeren, Abmelden). Abnahme erfüllt: `assembleDebug` +
`testDebugUnitTest` (59 Tests) grün, `tests/test_api_settings.py`
grün. — GEBAUT ✓

Stand: `ui/settings/SettingsScreen.kt` neu im Redesign (`ScreenHead`,
Profil-Karte mit `AvatarDot`, Sektionen DARSTELLUNG [Radio-Zeilen +
System-Pill, Akzent-Dots], BENACHRICHTIGUNGEN [lokaler Schalter],
WETTER [Karte + Stadt, `PrimaryButton` Speichern], KONTO & SICHERHEIT
[Geräte + Anzahl, Datenschutz-Dialog, Abmelden rot]);
`DevicesScreen` auf `EduCard`/`ScreenHead` umgestellt;
`ui/more/MoreScreen.kt` um Server-URL-Dialog + Cache-leeren erweitert
(Argumente am MORE-Aufruf in `NavGraph.kt` ergänzt);
`SettingsViewModel` um `session`-Flow ergänzt. Abnahme erfüllt:
PUT mit echten JSON-bools, Defaults bei ungültigen Werten
(`typedValues`), Cache-leeren erhält Einstellungen;
`tests/test_api_settings.py` + E2E grün.

Dateien: `data/SettingsRepository.kt`, `data/dto/Settings.kt`,
`ui/settings/{SettingsViewModel, SettingsScreen, DevicesScreen}`,
`ui/more/MoreScreen.kt`.
Einstellungen: Titel + „Dein EduFlow-Konto", Profil-Karte (Avatar,
Name, „Schule · verbunden"), Sektion DARSTELLUNG (Erscheinungsbild
Hell/Dunkel/System als Radio-Zeilen + System-Pill, Akzentfarbe mit
Farb-Dots), Sektion BENACHRICHTIGUNGEN (Schalter „Neue Nachrichten"),
Sektion KONTO & SICHERHEIT (Verbundene Geräte + Anzahl, Datenschutz,
Abmelden rot). Wetter-Sektion (Karte an/aus + Stadt) aus Paket G.
Mehr-Tab: Noten, Einstellungen, Geräte, Server-URL, Cache leeren,
Abmelden.
Abnahme: Speichern via `PUT settings` (echte JSON-bools), ungültige
Werte fallen auf Defaults; Cache-leeren erhält Einstellungen.

## 10. Paket G — Home/Übersicht (gleicher Stil, kein PNG) — GEBAUT ✓

Stand: umgesetzt in `ui/overview/OverviewScreen.kt` (Redesign:
`AppHeader`, `ScreenHead` „Home" + Datum, Uhr-Karte live,
Jetzt-Karte in Primär-Farbe, Wetterkarte nur bei `ov_wetter`,
Zähler-Köpfe + `EduCard`-Zeilen für Nachrichten/Hausaufgaben,
Essen mit ‹ ›-Pager, Listen-Links); `OverviewViewModel.kt`
unverändert wiederverwendet; `OverviewNavigation.kt` +
`NavGraph.kt` (`overviewDestination` mit `onOpenSettings`/
`onLogout`) verdrahtet. Abnahme erfüllt: `assembleDebug` +
`testDebugUnitTest` (59 Tests) grün, `tests/test_api_meta.py` +
`tests/test_api_e2e.py` grün. — GEBAUT ✓

Stand: `ui/overview/OverviewScreen.kt` neu im PNG-Stil (`AppHeader`,
`ScreenHead` „Home" + Datum, Uhr-Karte, Jetzt-Karte in Primär-Farbe,
Wetterkarte, Nachrichten-/Hausaufgaben-`EduCard`-Zeilen mit Zähler,
Essen-Pager mit ‹ ›); `OverviewViewModel`, `OverviewNavigation`
(+ `onLogout`-Verdrahtung in `NavGraph.kt`), `data/` (`MetaRepository`,
`Meta`-DTOs) unverändert wiederverwendet. Abnahme erfüllt: Inhalte wie
`/` (Web-Übersicht), Wetter nur bei `ov_wetter`, Fehlercodes
(`VALIDATION` ohne Ort, `CONFIG_MISSING` ohne Key);
`tests/test_api_meta.py` + E2E grün.

Dateien: `data/MetaRepository.kt`, `data/dto/Meta.kt`,
`ui/overview/{OverviewViewModel, OverviewScreen, OverviewNavigation}.kt`.
Layout im PNG-Stil: Header, „Home"-Titel + Datum, Uhr-Karte, schwarze
Jetzt-Karte („Jetzt: … / Als Nächstes: …"), Wetterkarte (nur wenn
`ov_wetter` an; Stadt aus `wetter_city`, sonst manuell), Mittagessen
mit ‹ ›-Pager (Mo–Fr, Start heute), neueste Nachrichten
(`ov_unread`-Limit), offene Hausaufgaben (`ov_homework`-Limit).
Abnahme: Inhalte wie `/` (Web-Übersicht); Wetter-Fehlercodes
(`VALIDATION` ohne Ort, `CONFIG_MISSING` ohne Key).

## 11. Paketübergreifende Regeln

- Kein Backend, keine Web-Routen, keine Paket-0-Signaturen ändern.
  Jeder arbeitet auf eigenem Branch ab `main`; nur eigene
  `ui/<paket>/`- + `data/`-Dateien plus eigene Ziele in `NavGraph.kt`.
- Netzwerk nur über `ApiService` + `TokenStore`; Fehler-Mapping aus
  `api/core.py` (`TOKEN_INVALID/EXPIRED` → Login, `EDUPAGE_2FA` →
  neu anmelden, `BAD_CREDENTIALS`, `CAPTCHA_REQUIRED`, `VALIDATION`,
  `NOT_FOUND`, `RATE_LIMITED`, `CONFIG_MISSING`, `UPSTREAM`).
- Listen: `limit` 50/max 200, `offset`, `refresh=1`; Filter heißen wie
  Web-Parameter. DTOs tolerant (`ignoreUnknownKeys`).
- Tests offline (Fake-`ApiService`): Routenform, Fehlercodes,
  Paginierung, 401-Verhalten. UI-Texte deutsch, keine Tokens/
  Stacktraces/Pfade in UI oder Logs.

## 12. Abnahme (Reihenfolge)

1. Paket 0 bauen + einfrieren (Start, Tabs, Theme, Health grün).
2. Pakete A–G parallel (nur gegen Paket 0 + `openapi.json`).
3. Merge-Reihenfolge: A, B, C, D, E, F, G.
4. E2E gegen Emulator (`http://10.0.2.2:8000`): Login inkl. 2FA, jede
   Liste mit Paginierung, je ein Schreibaufruf (senden, erledigt,
   Cache leeren), Abmelden + abgelehnter Token, `test_api_e2e.py` grün.
5. Nicht-Ziele: Push, Datei-Uploads, Mehrbenutzer,
   Produktiv-Betrieb. (Launcher-Icons aus `static/icons/icon.png`
   sind gesetzt: `res/mipmap-*/ic_launcher.png`.)

## Addendum — Schulalltag

Die additive Funktion `ui/school/` stellt Kalendertermine, Prüfungen,
Anwesenheitsereignisse und Vertretungen dar. Vertretungen lassen sich
wochenweise durchblättern. Daten werden über `school/agenda` und
`substitutions/week` bezogen; bestehende API-Ressourcen bleiben unverändert.
