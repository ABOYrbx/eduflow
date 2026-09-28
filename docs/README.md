# EduFlow – Projektdokumentation

# Dokumentation momentan wegen großer Änderung nicht aktuell und zu nutzen.

Diese Dokumentation beschreibt den im Repository sichtbaren Aufbau und Funktionsumfang von EduFlow. Sie ergänzt die Arbeitsregeln und Detailpläne; sie ersetzt keine davon. Aktualisierungsstand ist der Node-Paritätsstand N0–NI (Cutover N-J offen).

## Schnellnavigation

| Dokument | Inhalt |
| --- | --- |
| [Architektur](ARCHITEKTUR.md) | Systemübersicht, Datenfluss, Sitzungen und Cache |
| [Funktionen](FUNKTIONEN.md) | Fachliche Abläufe und sichtbarer Funktionsumfang |
| [API v1](API.md) | Routen, Authentifizierung, Parameter und Fehlercodes |
| [Plattformen](PLATTFORMEN.md) | Web, Android, macOS und zurückgestelltes iOS |
| [Entwicklung und Tests](ENTWICKLUNG.md) | Lokaler Start, Konfiguration, Build und Testbefehle |
| [TypeScript-Migration](MIGRATION.md) | NestJS-/Prisma-/Next.js-Prototyp und bekannte Lücken |

## Was EduFlow ist

EduFlow ist ein **lokales Schul-Dashboard für eine einzelne Schüler-/Eltern-Sitzung**. Es liest Schulalltagsdaten über EduPage, bereitet sie für die Weboberfläche und Apps auf und speichert ausgewählte Einstellungen sowie abgeleitete Zustände lokal. Die fachliche Datenquelle bleibt EduPage.

Der Funktionsumfang umfasst Nachrichten und Threads, Hausaufgaben, Stunden- und Vertretungspläne, Schultermine und Prüfungen, Noten, Essensplan, Wetter, Einstellungen und Geräteverwaltung. Die Weboberfläche und nativen Clients verwenden denselben versionierten API-Vertrag `/api/v1`.

## Wichtig: zwei Backend-Stände

Das Repository enthält derzeit zwei nebeneinander bestehende Implementierungen:

1. **Python-Referenzanwendung:** Flask in `app.py`, gemeinsame JSON-API in `api/`, Web-Templates unter `templates/`. Sie ist die aktuelle Referenz für EduPage-Integration und den stabilen `/api/v1`-Vertrag.
2. **TypeScript-Migration:** NestJS unter `apps/api/`, Next.js unter `apps/web/` und gemeinsame Verträge unter `packages/contracts/`. Neben dem Fake-Schulprovider für lokale Demo (`EDUFLOW_PROVIDER=fake`) ist ein echter EduPage-Anbieter implementiert (Paritätspakete N0–NI: Auth, Nachrichten, Aufgaben, Stundenplan, Noten, Einstellungen, Essen/Wetter, Schulalltag, provider-neutrales Web) — drahtkompatibel zu `/api/v1`. Der Cutover (N-J: Live-Abgleich mit echten Zugangsdaten, App-Umschaltung, Python-Archivierung) ist noch **offen**; bis zur Abnahme bleibt die Python-Anwendung das Live-Backend.

`./run.sh --demo` startet ausdrücklich die TypeScript-Demo mit Fake-Provider auf Port 3100 und die Next.js-Weboberfläche auf Port 8101. Die Python-Anwendung startet getrennt mit `python3 app.py` auf Port 8000. Die beiden Modi nicht verwechseln; Details: [Entwicklung](ENTWICKLUNG.md) und [Migration](MIGRATION.md).

## Arbeitsregeln und Quellenhierarchie

Vor Codeänderungen immer die Projektregeln in `AGENTS.md` (repo-intern, nicht Teil dieser Website) beachten. Besonders wichtig: Secrets, Cache-Dateien und Zugangsdaten niemals lesen, protokollieren oder committen; sichtbare Strings sind kurz und deutsch; API-Antworten und Helper-Signaturen kompatibel halten; Tests ohne echte Zugangsdaten ausführen. Android und macOS sowie Web haben Vorrang. iOS ist zurückgestellt.

Wenn Angaben voneinander abweichen, gilt diese Reihenfolge:

1. `AGENTS.md` und die dort genannten verbindlichen Bereichspläne
2. Implementierung und Tests des betroffenen Bereichs
3. Weitere Dateien unter `plaene/` (repo-intern, nicht Teil dieser Website)
4. Diese Überblicksdokumentation
5. Das ältere `README.md` im Repository-Stamm, das noch historische Projektbeschreibungen enthält

Verbindlich sind der Node-Paritätsplan (`plaene/NODE_PARITAET.md`, Pakete N0–NI umgesetzt, Cutover N-J offen) sowie die fertig gebauten, eingefrorenen Bereichspläne unter `plaene/archiv/` (`BACKEND.md`, `ANDROID.md`, `MACOS.md`, `IOS.md`); dazu `IOS_APP_PLAN.md`, `EDUPAGE_LUECKENPLAN.md`, `DEMO.md` und `LOKALISIERUNG.md` direkt in `plaene/`. Alle repo-intern, nicht Teil dieser Website.

## Repository-Karte

```text
app.py, cache.py, essen.py   Python-Flask-App, Cache, Mensa-PDF-Parser
api/                         Python-API v1: Auth, Nachrichten, Schule, usw.
templates/, static/          Python-Weboberfläche, CSS/JavaScript/Logo
android/                     Android-Client (Kotlin, Jetpack Compose)
mac/                         macOS-Client (Swift, SwiftUI)
ios/                         iOS-Client (derzeit zurückgestellt)
apps/api/                    TypeScript-API (NestJS, Prisma, Fake-Provider)
apps/web/                    TypeScript-Webclient (Next.js, React)
packages/contracts/          TypeScript-API-Vertrag und Fehlercodes
migration/                   Installations- und Migrationsskripte
plaene/                      Bereichspläne, Demo- und Ausbauplanung
tests/                       Python-Offline- und Web-Sicherheitstests
docs/                        Diese zusammenhängende Projektdokumentation
```

## Dokumentation aktuell halten

Bei Änderungen an Routen, DTOs, Cacheverhalten, Authentifizierung, Plattformumfang oder Migrationsstatus die betroffenen Seiten hier und den zuständigen Plan unter `plaene/` gemeinsam aktualisieren. Alle Aussagen müssen durch Quellcode oder Tests im aktuellen Checkout gedeckt sein; geplante, nur teilweise vorhandene oder Demo-Funktionen entsprechend kennzeichnen.
