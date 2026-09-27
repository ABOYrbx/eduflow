<div align="center">

[English](README.md) | Deutsch

<a href="https://github.com/ABOYrbx/eduflow">
<img src="mac/EduFlow/Resources/icon.png" alt="EduFlow-Logo" width="120">
</a>

# EduFlow

Lokales Schul-Dashboard für EduPage: Nachrichten, Hausaufgaben, Stundenplan, Noten, Essen & mehr.
NestJS-API + Next.js-Web-UI + native Android- und macOS-Apps.

[![Stars](https://img.shields.io/github/stars/ABOYrbx/eduflow?style=for-the-badge)](https://github.com/ABOYrbx/eduflow/stargazers)
[![Forks](https://img.shields.io/github/forks/ABOYrbx/eduflow?style=for-the-badge)](https://github.com/ABOYrbx/eduflow/network/members)
[![Issues](https://img.shields.io/github/issues/ABOYrbx/eduflow?style=for-the-badge)](https://github.com/ABOYrbx/eduflow/issues)
[![PRs](https://img.shields.io/github/issues-pr/ABOYrbx/eduflow?style=for-the-badge)](https://github.com/ABOYrbx/eduflow/pulls)
[![Lizenz: MIT](https://img.shields.io/badge/Lizenz-MIT-yellow.svg?style=for-the-badge)](LICENSE)

[Demo ansehen](#demo-modus) · [Bug melden](https://github.com/ABOYrbx/eduflow/issues/new?labels=bug) · [Feature wünschen](https://github.com/ABOYrbx/eduflow/issues/new?labels=enhancement)

</div>

<details>
<summary>Inhaltsverzeichnis</summary>

1. [Über das Projekt](#über-das-projekt)
   - [Technologien](#technologien)
2. [Erste Schritte](#erste-schritte)
   - [Voraussetzungen](#voraussetzungen)
   - [Installation](#installation)
3. [Verwendung](#verwendung)
   - [Demo-Modus](#demo-modus)
   - [Native Apps](#native-apps)
   - [API-Referenz](#api-referenz)
4. [Roadmap](#roadmap)
5. [Star-Historie](#star-historie)
6. [Mitmachen](#mitmachen)
   - [Top-Beitragende](#top-beitragende)
7. [Lizenz](#lizenz)
8. [Kontakt](#kontakt)
9. [Danksagungen](#danksagungen)

</details>

## Über das Projekt

EduFlow ist ein **lokales Schul-Dashboard** auf Basis von EduPage: ein versioniertes
JSON-Backend (`/api/v1`) mit echtem EduPage-Provider plus Fake-Provider für Demos,
eine provider-neutrale Next.js-Web-UI sowie native Android- (Kotlin/Compose) und
macOS-Clients (SwiftUI). iOS existiert, ist aber zurückgestellt.

Darum EduFlow:

- Schuldaten bleiben lokal — der Server ist ein lokales Werkzeug, kein öffentlicher Betrieb
- Ein API-Vertrag für Web, Android und macOS (Listen als `{items, total, limit, offset}`, Fehler als `{error, code}`)
- Demo-Modus mit synthetischen Daten (`demo` / `demo`), ganz ohne EduPage-Konto ausprobierbar

Vollständige deutsche Projektdokumentation mit Architektur, Funktionen und API: [docs/](docs/README.md).

([nach oben](#eduflow))

### Technologien

- [![NestJS](https://img.shields.io/badge/NestJS-E0234E?style=for-the-badge&logo=nestjs&logoColor=white)](https://nestjs.com/)
- [![Next.js](https://img.shields.io/badge/Next.js-000000?style=for-the-badge&logo=nextdotjs&logoColor=white)](https://nextjs.org/)
- [![React](https://img.shields.io/badge/React-20232A?style=for-the-badge&logo=react&logoColor=61DAFB)](https://reactjs.org/)
- [![TypeScript](https://img.shields.io/badge/TypeScript-3178C6?style=for-the-badge&logo=typescript&logoColor=white)](https://www.typescriptlang.org/)
- [![Prisma](https://img.shields.io/badge/Prisma-2D3748?style=for-the-badge&logo=prisma&logoColor=white)](https://www.prisma.io/)
- [![PostgreSQL](https://img.shields.io/badge/PostgreSQL-4169E1?style=for-the-badge&logo=postgresql&logoColor=white)](https://www.postgresql.org/)
- [![Kotlin](https://img.shields.io/badge/Kotlin-7F52FF?style=for-the-badge&logo=kotlin&logoColor=white)](https://kotlinlang.org/) [![Jetpack Compose](https://img.shields.io/badge/Jetpack_Compose-4285F4?style=for-the-badge&logo=jetpackcompose&logoColor=white)](https://developer.android.com/compose)
- [![Swift](https://img.shields.io/badge/Swift-F05138?style=for-the-badge&logo=swift&logoColor=white)](https://www.swift.org/) [![SwiftUI](https://img.shields.io/badge/SwiftUI-007AFF?style=for-the-badge&logo=swift&logoColor=white)](https://developer.apple.com/swiftui/)

([nach oben](#eduflow))

## Erste Schritte

### Voraussetzungen

- Node.js + npm
- PostgreSQL (oder über `install.sh` auf macOS/Homebrew, Debian/Ubuntu einrichten lassen)
- Für native Builds: Android-SDK + Gradle 8.7 oder Xcode 16+ unter macOS 14+

### Installation

1. Repo klonen
   ```sh
   git clone https://github.com/ABOYrbx/eduflow.git
   cd eduflow
   ```
2. Abhängigkeiten installieren
   ```sh
   npm install
   ```
3. Setup-Assistent starten (PostgreSQL, lokale API-Konfiguration mit Rechten `0600`)
   ```sh
   ./install.sh
   ```
4. Echte Version starten (NestJS-API + Next.js-Web)
   ```sh
   ./run.sh
   ```
   Web: http://localhost:8000 — API: http://127.0.0.1:3000/api/v1

([nach oben](#eduflow))

## Verwendung

| Modus | Befehl | API | Web |
|---|---|---|---|
| Echt (EduPage-Login) | `./run.sh` | `http://127.0.0.1:3000` | http://localhost:8000 |
| Demo (Fake-Daten) | `./run.sh --demo` | `http://127.0.0.1:3100` | http://localhost:8101 |

Beide Modi können nebeneinander laufen. Eigene Ports: `API_PORT=… WEB_PORT=… ./run.sh [--demo]`
(`run.sh` prüft Ports und wechselt nie stillschweigend).

### Demo-Modus

Mit `./run.sh --demo` starten, dann in der Web-UI oder den Apps **Demo ansehen** wählen.
Testkonten (synthetische Daten, nur Demo):

- Standard: `demo` / `demo`
- 2FA-Demo: `demo-2fa` / `demo`, Code `123456`

### Native Apps

- **Android** (`android/`, Kotlin + Compose, Pakete 0, A–G): Standard-API
  `http://10.0.2.2:3000/api/v1/` (Emulator-Loopback), Demo `http://10.0.2.2:3100/api/v1/`.
  Bauen/Testen mit Gradle 8.7: `:app:assembleDebug :app:testDebugUnitTest` (59 Offline-Unit-Tests).
- **macOS** (`mac/`, Projekt `EduFlow Mac`, SwiftUI): Standard-API
  `http://127.0.0.1:3000/api/v1/`, Demo `http://127.0.0.1:3100/api/v1/`.
  Bauen/Testen: `xcodebuild -project "mac/EduFlow Mac.xcodeproj" -scheme "EduFlow Mac" -destination 'platform=macOS' test` (52 Tests).
- **iOS** (`ios/`, Projekt `EduFlow iOS`): gebaut, aber bis auf Weiteres zurückgestellt.

### API-Referenz

- `GET /api/v1/health` (ohne Auth) und `GET /api/v1/openapi.json` (Routen-Referenz)
- Auth nur per Bearer-Token (30 Tage); Datei-Downloads zusätzlich per kurzlebigem `?dl=`-Token
- 2FA in zwei Schritten: `auth/login` → `2fa_required` + `pending_token`, dann `auth/2fa`
- Alle UI-Strings sind deutsch; Fehler-`code`s bleiben stabil und unübersetzt

*Weitere Beispiele in der [Dokumentation](docs/README.md).*

([nach oben](#eduflow))

## Roadmap

- [ ] Live-Cutover aufs NestJS-Backend (DTO-Abgleich mit echten Konten, App-Umschaltung)
- [ ] Anwesenheit: Fehlzeiten-/Verspätungsübersicht, Krankmeldung einreichen
- [ ] Essensbestellung (wo die Schule sie freischaltet)
- [ ] Umfragen, Anmeldungen und Bestätigungen
- [x] Vertretungen + Schulagenda (`substitutions/week`, `school/agenda`)
- [x] Demo-Modus für Web, Android und macOS
- [x] Native Android-App (Pakete 0, A–G)
- [x] Native macOS-App (Pakete 0, A–D)

Vollständige Liste vorgeschlagener Features und bekannter Probleme in den
[offenen Issues](https://github.com/ABOYrbx/eduflow/issues).

([nach oben](#eduflow))

## Star-Historie

[![Star-Historie-Diagramm](https://api.star-history.com/svg?repos=ABOYrbx/eduflow&type=Date)](https://www.star-history.com/#ABOYrbx/eduflow&Date)

([nach oben](#eduflow))

## Mitmachen

Beiträge machen Open Source erst zu dem, was es ist: ein Ort zum Lernen, Inspirieren und
Schaffen. Jeder Beitrag ist **sehr willkommen**.

1. Projekt forken
2. Feature-Branch anlegen (`git checkout -b feature/AmazingFeature`)
3. Änderungen auf Englisch committen (`git commit -m 'Add some AmazingFeature'`)
4. Branch pushen (`git push origin feature/AmazingFeature`)
5. Pull Request öffnen

Bitte Tests offline halten (Fake-Provider / Fakes / URL-Stubs, nie echte Zugangsdaten) und vor
dem Push `npm run typecheck` + `npm test` ausführen. Secrets, Caches und Login-Daten dürfen
weder gelesen, geloggt noch committet werden.

### Top-Beitragende

[![contrib.rocks-Bild](https://contrib.rocks/image?repo=ABOYrbx/eduflow)](https://github.com/ABOYrbx/eduflow/graphs/contributors)

([nach oben](#eduflow))

## Lizenz

Veröffentlicht unter der MIT-Lizenz. Siehe [LICENSE](LICENSE) für Details.

([nach oben](#eduflow))

## Kontakt

ABOYrbx — [@ABOYrbx](https://github.com/ABOYrbx)

Projekt-Link: [https://github.com/ABOYrbx/eduflow](https://github.com/ABOYrbx/eduflow)

([nach oben](#eduflow))

## Danksagungen

- [EduPage-API-Python-Library](https://github.com/EdupageAPI/edupage-api) — ursprüngliche Integrationsreferenz
- [Best-README-Template](https://github.com/othneildrew/Best-README-Template) — Struktur dieser Datei
- [Shields.io](https://shields.io) — Badges · [Star History](https://www.star-history.com) — Wachstumsdiagramm · [contrib.rocks](https://contrib.rocks) — Beitragende
- [Crowdin](https://crowdin.com) — Lokalisierungs-Workflow

([nach oben](#eduflow))
