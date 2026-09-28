Egal was du machst gehe NIEMALS an .eduflow.key oder .eduflow_secret und lese es, sowie alles im cache oder irgendeine Art von Logins usw.

# EduFlow — Projektübersicht für Agenten

> **Backend-Stand:** NestJS (`apps/api`, Port 3000) ist das Standard-Backend
> (drahtkompatibel zu `/api/v1`, siehe `plaene/NODE_PARITAET.md`), Web-UI ist
> Next.js (`apps/web`, Port 8000). Der Python-Stack ist archiviert
> (Branch `archive/python-legacy`) und wird nicht mehr ausgebaut.

Lokales Schul-Dashboard (EduPage): Next.js-Web-App + NestJS-JSON-Backend
`/api/v1` + native Clients (Android, macOS, iOS). Server bleibt ein
lokales Werkzeug, kein Produktiv-Betrieb. Secrets (`.env*`, `.cache/`,
DB-/Vault-Zugänge) niemals lesen, loggen oder committen.

Fokus-Reihenfolge: **Android + macOS + Web-UI**. **iOS ist vorerst
zurückgestellt** (gebaut, aber keine weiteren Arbeiten ohne expliziten Auftrag).

## Struktur

```
apps/api/         NestJS-Backend (TypeScript): `/api/v1` mit EduPage-Provider
                  (echt) + Fake-Provider (Demo, Login demo/demo)
apps/web/         Next.js-Web-UI (provider-neutral, deutsche Kataloge in
                  `messages/de.json`), Design in `src/app/uber.css`
packages/         Geteilte TypeScript-Verträge (`@eduflow/contracts`)
migration/        Installer-Skripte + Migrationsnotizen (`migration/README.md`)
run.sh/install.sh Start (echt: API :3000 + Web :8000; Demo: `--demo`) +
                  Setup-Assistent (Postgres, `.env.local` mit 0600)
templates/        Nur Designvorlage (PNG, lokal, nicht getrackt) — kein Code
static/icons/     Logo-Quelle (`icon.png`)
android/          Kotlin + Compose App (Pakete 0, A–G GEBAUT, Launcher-Icons gesetzt)
mac/              SwiftUI App (Pakete 0, A–D GEBAUT, 52 Swift-Testing-Tests grün)
ios/              SwiftUI App (Pakete 0, A–G gebaut — ZURÜCKGESTELLT, s. unten)
```

Alle Projektpläne liegen zentral im Ordner `plaene/` (Index: `plaene/README.md`).
Die Bereichspläne sind abgeschlossen und eingefroren in `plaene/archiv/`
(`BACKEND.md`, `ANDROID.md`, `MACOS.md`, `IOS.md`); der iOS-Gesamtplan liegt
in `plaene/IOS_APP_PLAN.md`. Der Funktionslücken- und Ausbauplan für eine
Annäherung an EduPage steht in `plaene/EDUPAGE_LUECKENPLAN.md`. Design-Quellen:
Android/iOS folgen ausschließlich
`templates/EduFlow · Weitere App Screens.png` (6 Screen-Gruppen, Light/Dark;
Web-Design wird fürs App-Design IGNORIERT).
**macOS folgt bewusst dem Web-Design (`apps/web/src/app/uber.css`), NICHT dem PNG.**

## Backend `/api/v1` (bestehende Routen stabil halten)

- NestJS mit zwei Providern (`EDUFLOW_PROVIDER`): `edupage` = echt (lebt von
  der Login-Sitzung, Tokens/2FA gegen EduPage), `fake` = Demo
  (`demo`/`demo`). Auth nur per Bearer-Token (30 Tage, DB-Ablage); Ausnahme:
  Datei-Downloads auch via `?dl=`-Kurz-Token (5 Min, empfohlen) / `?token=`.
- 2FA zweistufig: `auth/login` → `2fa_required` + `pending_token` (TTL 10 Min),
  `auth/2fa` tauscht gegen Voll-Token. Rate-Limit 20/10 Min/IP → 429.
- Fehler immer `{error, code}` mit kanonischem Vokabular
  (`VALIDATION, TOKEN_INVALID/EXPIRED, PENDING_INVALID/INVALID_CODE,
  BAD_CREDENTIALS, EDUPAGE_2FA, CAPTCHA_REQUIRED, NOT_FOUND, RATE_LIMITED,
  CONFIG_MISSING, UPSTREAM`; deutsche Texte aus `src/messages/de.json`).
  Listen immer `{items, total, limit, offset}` (`limit` 50/max 200).
  DTOs = Web-Dicts 1:1 (Web/App-Parität).
- Routen-Referenz: `GET /api/v1/openapi.json`, `GET /api/v1/health` (ohne Auth).
- Neue additive Routen sind zulässig, wenn bestehende Antworten und DTOs
  kompatibel bleiben. Backend-Dependencies begründen.
- Schulalltag: Vertretungen (`substitutions/week`) sowie Kalender-/Prüfungs-/
  Anwesenheitsereignisse (`school/agenda`) via `SchoolController`. Web:
  `/agenda`; Android/macOS: „Termine & Vertretungen“.

## Android (`android/`, Pakete 0, A–G = GEBAUT)

- Stack fix: Kotlin, Compose BOM 2024.06.00, Material3, Navigation-Compose
  2.7.7, DataStore 1.1.1, Retrofit 2.11.0 + OkHttp 4.12.0 +
  kotlinx-serialization 1.7.3 (`minSdk 26`, `target/compile 34`, `jvm 17`).
- Ein Einstieg (`MainActivity` + `NavGraph`), Bottom-Bar mit Pille (Home,
  Aufgaben, Nachr., Plan, Mehr), MVVM pro Feature (`ui/<paket>/` +
  `HomeworkViewModel`-Muster). Netzwerk nur über ein Retrofit-`ApiService`
  + einen `TokenStore` (DataStore, inkl. Korruptions-Handler),
  Bearer per Interceptor, DTOs tolerant (`ignoreUnknownKeys`).
- Paket 0 eingefroren: `ui/theme/*`, `ui/common/RedesignUi.kt` (`AppHeader`
  mit Logo, `SearchPill`, `FilterChips`, `EduCard`, `StatusPill`,
  `SectionLabel`, `PrimaryButton`, `AvatarDot`), `Routes.kt`, `BottomBar.kt`,
  `NavGraph.kt`, `data/`-Interface. Pakete bauen nur dagegen; `NavGraph`
  nur eigene Ziele anfassen.
- Gebaut: A Onboarding/Login+2FA (`ui/auth/`), B Aufgaben (`ui/homework/`,
  Kreis-Checkbox, Papierkorb, Zähler), C Nachrichten (Liste/Thread/Verfassen,
  `?dl=`-Download, lokal getracktes Ungelesen), D Stundenplan (Tag/Woche,
  JETZT-Pill, Entfall-Einzeiler, Wochenende = Schulfrei), E Noten
  (Schnitt-Karte, Halbjahr-Chips, aufklappbare Fächer), F Einstellungen+Mehr
  (Profil-Karte, Darstellung mit Akzent-Dots, Wetter-, Übersichts-Sektionen,
  Geräte, Server-Dialog + Cache im Mehr-Tab), G Home (Uhr live, Jetzt-Karte,
  Wetter nur bei `ov_wetter`).
- Schulalltag: Kalender-/Prüfungs-/Anwesenheitsereignisse und navigierbare
  Vertretungswochen unter `ui/school/`.
- Logo: `static/icons/icon.png` → `res/mipmap-*/ic_launcher.png` (Manifest)
  + `res/drawable-nodpi/logo.png` (AppHeader).
- Default-URL `http://10.0.2.2:3000/api/v1/` (Emulator-Loopback, in Login +
  Einstellungen änderbar). Bauen/Testen (Gradle liegt NICHT im PATH):
  `<GRADLE-DIST>/gradle-8.7/bin/gradle :app:assembleDebug
  :app:testDebugUnitTest` in `android/` → 58 Unit-Tests offline mit
  Fake-`ApiService` (`Auth/Logic/ResourcesPackageTest`).

## macOS (`mac/`, Pakete 0, A–D = GEBAUT)

- Stack fix: Swift 5 language mode, SwiftUI (App-Lifecycle), macOS 14+,
  nur System-Frameworks, Swift Testing, stubbendes URL-Protokoll pro Route
  (offline). Design = Web (`apps/web/src/app/uber.css`: Pillen-Navi,
  Akzentfarben, Hell/Dunkel per System), eigener Font (`Inter.ttf`).
- Architektur: ein Einstieg (`EduFlowApp` + `ContentView`), Top-Pillen-Navi
  statt Sidebar (Übersicht, Nachrichten, Hausaufgaben, Noten,   Stundenplan; Wetter in Übersicht, Einstellungen als Sheet), Onboarding-Fenster
  klein+fix (400×600), danach frei skalierbar. MVVM pro Feature
  (View + ViewModel + Repository), `@Observable`-Store, ein `APIClient`
  (Bearer zentral) + ein `TokenStore` (Datei mit 0600 in Application
  Support — bewusst KEINE Keychain, sonst Dialog bei Ad-hoc-Signierung).
- Gebaut: 0 Kern (Client, Store, DTOs, Routen, Theme, CommonViews), A Auth
  (Login/2FA/Logout) + Einstellungen + Geräte, B Nachrichten (Liste, Thread
  mit Likes/Antworten, Verfassen mit Empfänger-Suche), C Hausaufgaben
  (Filter, Papierkorb, erledigt) + Noten (Schnitt, Fächer), D Stundenplan
  (Tag/Woche) + Übersicht (Uhr, Jetzt/Weiter, Wetter, Neueste).
- Schulalltag: Kalender-/Prüfungs-/Anwesenheitsereignisse und navigierbarer
  Vertretungsplan in `School/SchoolViews.swift`.
  DTOs 1:1 aus `@eduflow/contracts`, Fehler/Deutschtexte wie Backend-Katalog.
- Logo: `mac/EduFlow/Resources/icon.png` (+ `AppIcon.icns`) verdrahtet;
  offene Kleinigkeit: Marken-Box in `ContentView` zeigt noch „E".
- Server = derselbe Mac (`http://127.0.0.1:3000`, Loopback-Ausnahme in
  `Info.plist`, Sandbox + Netzwerk-Entitlement). Bauen/Testen:
  `xcodebuild -project "mac/EduFlow Mac.xcodeproj" -scheme "EduFlow Mac"
  -destination 'platform=macOS' test` → 52 Tests grün (`EduFlowTests/`:
  Core/Auth/Homework/Message/Timetable/Onboarding).

## Web-UI (`apps/web/`, Next.js)

- Seiten (alle via `DashboardApp` + `LoginForm`, deutsche Texte aus
  `messages/de.json` via `t()`): Login (+2FA), Übersicht (Uhr, Jetzt/Weiter,
  Wetter, Stunden-Karussell), Nachrichten (Mail-Layout mit
  Likes, Suche, Filter), Verfassen/Antworten, Hausaufgaben (inkl.
  Papierkorb), Stundenplan (Tag/Woche), Noten, Einstellungen (inkl.
  API-Token-Verwaltung + Geräte), Termine & Vertretungen.
- Start: `./run.sh` → API :3000 + Web :8000 (echt, EduPage-Login);
  `./run.sh --demo` → Demo (`demo`/`demo`). Ersteinrichtung: `./install.sh`
  (Postgres, `.env.local` mit 0600). Session-Proxy unter `src/app/api/`
  zeigt per `API_SERVER_URL` auf die API.
- Prüfen: `npm run typecheck` (alle Pakete) + `npm test` (API: 88 Jest-Tests,
  offline mit Fake-Provider) — beide müssen grün bleiben.

## iOS (`ios/` — ZURÜCKGESTELLT, nicht aktiv weiterbauen)

- Stand: Pakete 0, A–G gebaut (SwiftUI, nur System-Frameworks, `APIClient`
  + `TokenStore` (UserDefaults) + `APIError`, DTOs tolerant). 41 Tests grün
  (`EduFlowTests`: Core/Homework/Messages/Accent/GradeTerms).
- Bekannte PNG-Abweichungen (bewusst nicht weiter verfolgt): native
  Tab-Bar statt Pillen-Leiste, native Titelzeilen zusätzlich zu den
  Screen-Köpfen, Schalter statt Checkbox im Login.
- Falls doch Simulator-Arbeit nötig: genutztes Gerät ist **iPhone 18 Pro**
  (nicht iPhone 17) — falsches Ziel zeigt alte Installation. Default-URL
  `http://127.0.0.1:3000/api/v1/`. Neue Dateien müssen in
  `ios/EduFlow iOS.xcodeproj/project.pbxproj` registriert werden (BuildFile +
  FileReference + Gruppen- + Phasen-Eintrag), sonst „not in scope".

## Logo (eine Quelle)

- `static/icons/icon.png` (1254×1254, blaues S mit Hut auf Schwarz) ist die
  einzige Logo-Quelle: Android-Launcher (`mipmap-*`), iOS-AppIcon (1024) +
  Header (`Logo.imageset`, 24pt, optisch zentriert), macOS-Resources,
  Android-Header (`drawable-nodpi`). Ausnahme: macOS-Marken-Box (noch „E").

## Regeln für alle Arbeiten

- Identität: Commits und Pushes laufen ausschließlich über den GitHub-Account
  (`ABOYrbx`, Mail `ABOYrbx@users.noreply.github.com`) — niemals mit
  Klarnamen oder lokalen Rechner-Mails. Echte Namen und lokale
  Benutzerpfade (`/Users/<name>/…`, Hostnamen) gehören weder in Commits noch
  in getrackte Dateien; Build-/Output-Ordner (`build/`, `.gradle/`,
  `DerivedData/`, `xcuserdata/`) werden nie committet.
- Alle UI-Strings deutsch, kurz, ohne Secrets/Stacktraces/Pfade — und immer
  in den Quelldateien der Plattform (keine Hardcodings, sonst kann Crowdin
  sie nicht übersetzen): Web → `apps/web/messages/de.json` (`t()`),
  Backend → `apps/api/src/messages/de.json` (`t()`),
  Android → `values/strings.xml` (`stringResource`),
  macOS → `Localizable.xcstrings` (`NSLocalizedString` bei Dynamik).
  `code`-Vokabular, Status-/Typ-Werte und Routen bleiben stabil und werden
  nie übersetzt (Details: `plaene/LOKALISIERUNG.md`).
  401-Verhalten überall → Login (`TOKEN_INVALID/EXPIRED`, `EDUPAGE_2FA` →
  neu anmelden). Jeder arbeitet auf eigenem Branch ab `main`; bei
  parallelen Bearbeitungen derselben Dateien zuerst Stand per Build
  verifizieren, nichts blind überschreiben.
- Tests laufen offline (Fake-Provider / Fake-Clients / URL-Stubs), nie mit
  echten Zugangsdaten. Backend: `npm test` (88 Jest-Tests) + `npm run
  typecheck` müssen grün bleiben.
- Nicht-Ziele: Push, Datei-Uploads aus Apps, Mehrbenutzer, Produktiv-Betrieb.
