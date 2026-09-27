<div align="center">

English | [Deutsch](README.de.md)

<a href="https://github.com/ABOYrbx/eduflow">
<img src="mac/EduFlow/Resources/icon.png" alt="EduFlow logo" width="120">
</a>

# EduFlow

Local school dashboard for EduPage: messages, homework, timetable, grades, canteen & more.
NestJS API + Next.js web UI + native Android and macOS apps.

[![Stars](https://img.shields.io/github/stars/ABOYrbx/eduflow?style=for-the-badge)](https://github.com/ABOYrbx/eduflow/stargazers)
[![Forks](https://img.shields.io/github/forks/ABOYrbx/eduflow?style=for-the-badge)](https://github.com/ABOYrbx/eduflow/network/members)
[![Issues](https://img.shields.io/github/issues/ABOYrbx/eduflow?style=for-the-badge)](https://github.com/ABOYrbx/eduflow/issues)
[![PRs](https://img.shields.io/github/issues-pr/ABOYrbx/eduflow?style=for-the-badge)](https://github.com/ABOYrbx/eduflow/pulls)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge)](LICENSE)

[View Demo](#demo-mode) · [Report Bug](https://github.com/ABOYrbx/eduflow/issues/new?labels=bug) · [Request Feature](https://github.com/ABOYrbx/eduflow/issues/new?labels=enhancement) · [Documentation](https://a-dev.gitbook.io/eduflow)

</div>

<details>
<summary>Table of Contents</summary>

1. [About The Project](#about-the-project)
   - [Built With](#built-with)
2. [Getting Started](#getting-started)
   - [Prerequisites](#prerequisites)
   - [Installation](#installation)
3. [Usage](#usage)
   - [Demo mode](#demo-mode)
   - [Native apps](#native-apps)
   - [API reference](#api-reference)
4. [Roadmap](#roadmap)
5. [Star History](#star-history)
6. [Contributing](#contributing)
   - [Top contributors](#top-contributors)
7. [License](#license)
8. [Contact](#contact)
9. [Acknowledgments](#acknowledgments)

</details>

## About The Project

EduFlow is a **local-first school dashboard** on top of EduPage: a versioned JSON
backend (`/api/v1`) with a real EduPage provider plus a fake provider for demos,
a provider-neutral Next.js web UI, and native Android (Kotlin/Compose) and
macOS (SwiftUI) clients. iOS exists but is shelved.

Why EduFlow:

- Your school data stays local — the server is a local tool, never a public deployment
- One API contract for web, Android and macOS (`{items, total, limit, offset}` lists, `{error, code}` errors)
- Demo mode with synthetic data (`demo` / `demo`), so you can try everything without an EduPage account

Full German docs with architecture, features and API: [docs/](docs/README.md).

([back to top](#eduflow))

### Built With

- [![NestJS](https://img.shields.io/badge/NestJS-E0234E?style=for-the-badge&logo=nestjs&logoColor=white)](https://nestjs.com/)
- [![Next.js](https://img.shields.io/badge/Next.js-000000?style=for-the-badge&logo=nextdotjs&logoColor=white)](https://nextjs.org/)
- [![React](https://img.shields.io/badge/React-20232A?style=for-the-badge&logo=react&logoColor=61DAFB)](https://reactjs.org/)
- [![TypeScript](https://img.shields.io/badge/TypeScript-3178C6?style=for-the-badge&logo=typescript&logoColor=white)](https://www.typescriptlang.org/)
- [![Prisma](https://img.shields.io/badge/Prisma-2D3748?style=for-the-badge&logo=prisma&logoColor=white)](https://www.prisma.io/)
- [![PostgreSQL](https://img.shields.io/badge/PostgreSQL-4169E1?style=for-the-badge&logo=postgresql&logoColor=white)](https://www.postgresql.org/)
- [![Kotlin](https://img.shields.io/badge/Kotlin-7F52FF?style=for-the-badge&logo=kotlin&logoColor=white)](https://kotlinlang.org/) [![Jetpack Compose](https://img.shields.io/badge/Jetpack_Compose-4285F4?style=for-the-badge&logo=jetpackcompose&logoColor=white)](https://developer.android.com/compose)
- [![Swift](https://img.shields.io/badge/Swift-F05138?style=for-the-badge&logo=swift&logoColor=white)](https://www.swift.org/) [![SwiftUI](https://img.shields.io/badge/SwiftUI-007AFF?style=for-the-badge&logo=swift&logoColor=white)](https://developer.apple.com/swiftui/)

([back to top](#eduflow))

## Getting Started

### Prerequisites

- Node.js + npm
- PostgreSQL (or let `install.sh` set it up on macOS/Homebrew, Debian/Ubuntu)
- For native builds: Android SDK + Gradle 8.7, or Xcode 16+ on macOS 14+

### Installation

1. Clone the repo
   ```sh
   git clone https://github.com/ABOYrbx/eduflow.git
   cd eduflow
   ```
2. Install dependencies
   ```sh
   npm install
   ```
3. Run the setup assistant (PostgreSQL, local API config with `0600` permissions)
   ```sh
   ./install.sh
   ```
4. Start the real version (NestJS API + Next.js web)
   ```sh
   ./run.sh
   ```
   Web: http://localhost:8000 — API: http://127.0.0.1:3000/api/v1

([back to top](#eduflow))

## Usage

| Mode | Command | API | Web |
|---|---|---|---|
| Real (EduPage login) | `./run.sh` | `http://127.0.0.1:3000` | http://localhost:8000 |
| Demo (fake data) | `./run.sh --demo` | `http://127.0.0.1:3100` | http://localhost:8101 |

Both modes can run side by side. Custom ports: `API_PORT=… WEB_PORT=… ./run.sh [--demo]`
(`run.sh` checks ports and never switches silently).

### Demo mode

Start with `./run.sh --demo`, then choose **View demo** in the web UI or the apps.
Test accounts (synthetic data, demo only):

- Standard: `demo` / `demo`
- 2FA demo: `demo-2fa` / `demo`, code `123456`

### Native apps

- **Android** (`android/`, Kotlin + Compose, packages 0, A–G): default API
  `http://10.0.2.2:3000/api/v1/` (emulator loopback), demo `http://10.0.2.2:3100/api/v1/`.
  Build/test with Gradle 8.7: `:app:assembleDebug :app:testDebugUnitTest` (59 offline unit tests).
- **macOS** (`mac/`, project `EduFlow Mac`, SwiftUI): default API
  `http://127.0.0.1:3000/api/v1/`, demo `http://127.0.0.1:3100/api/v1/`.
  Build/test: `xcodebuild -project "mac/EduFlow Mac.xcodeproj" -scheme "EduFlow Mac" -destination 'platform=macOS' test` (52 tests).
- **iOS** (`ios/`, project `EduFlow iOS`): built, but shelved until further notice.

### API reference

- `GET /api/v1/health` (no auth) and `GET /api/v1/openapi.json` (route reference)
- Auth via Bearer token (30 days); file downloads additionally accept a short-lived `?dl=` token
- 2FA in two steps: `auth/login` → `2fa_required` + `pending_token`, then `auth/2fa`
- All UI strings are German; error `code`s stay stable and untranslated

*For more examples, please refer to the [Documentation](docs/README.md).*

([back to top](#eduflow))

## Roadmap

- [ ] Live cutover to the NestJS backend (DTO diff against real accounts, app switch-over)
- [ ] Attendance: absences/delays overview, sick-note submission
- [ ] Canteen ordering (where the school enables it)
- [ ] Surveys, sign-ups and confirmations
- [x] Substitutions + school agenda (`substitutions/week`, `school/agenda`)
- [x] Demo mode for web, Android and macOS
- [x] Native Android app (packages 0, A–G)
- [x] Native macOS app (packages 0, A–D)

See the [open issues](https://github.com/ABOYrbx/eduflow/issues) for the full list of proposed features and known issues.

([back to top](#eduflow))

## Star History

[![Star History Chart](https://api.star-history.com/svg?repos=ABOYrbx/eduflow&type=Date)](https://www.star-history.com/#ABOYrbx/eduflow&Date)

([back to top](#eduflow))

## Contributing

Contributions are what make the open source community such an amazing place to learn, inspire, and create. Any contributions you make are **greatly appreciated**.

1. Fork the Project
2. Create your Feature Branch (`git checkout -b feature/AmazingFeature`)
3. Commit your Changes in English (`git commit -m 'Add some AmazingFeature'`)
4. Push to the Branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

Please keep tests offline (fake provider / fakes / URL stubs, never real credentials) and run
`npm run typecheck` + `npm test` before pushing. Secrets, caches and login data must never be
read, logged or committed.

### Top contributors

[![contrib.rocks image](https://contrib.rocks/image?repo=ABOYrbx/eduflow)](https://github.com/ABOYrbx/eduflow/graphs/contributors)

([back to top](#eduflow))

## License

Distributed under the MIT License. See [LICENSE](LICENSE) for more information.

([back to top](#eduflow))

## Contact

ABOYrbx — [@ABOYrbx](https://github.com/ABOYrbx)

Project Link: [https://github.com/ABOYrbx/eduflow](https://github.com/ABOYrbx/eduflow)

([back to top](#eduflow))

## Acknowledgments

- [EduPage API Python library](https://github.com/EdupageAPI/edupage-api) — the original integration reference
- [Best-README-Template](https://github.com/othneildrew/Best-README-Template) — structure of this file
- [Shields.io](https://shields.io) — badges · [Star History](https://www.star-history.com) — growth chart · [contrib.rocks](https://contrib.rocks) — contributors
- [Crowdin](https://crowdin.com) — localization workflow

([back to top](#eduflow))
