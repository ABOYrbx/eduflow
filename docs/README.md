# EduFlow – Projektdokumentation

Diese Dokumentation beschreibt den im Repository sichtbaren Aufbau und Funktionsumfang von EduFlow. Sie ergänzt die Arbeitsregeln und Detailpläne; sie ersetzt keine davon. Sie ist am **26. September 2026** anhand des Quellcodes und der vorhandenen Pläne zusammengestellt.

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
2. **TypeScript-Migration:** NestJS unter `apps/api/`, Next.js unter `apps/web/` und gemeinsame Verträge unter `packages/contracts/`. Sie enthält einen Fake-Schulprovider für lokale Demo und UI-Arbeit. Ein echter EduPage-Adapter fehlt; diese Migration ist noch **nicht funktionsgleich und nicht für echte EduPage-Konten verwendbar**.

`./run.sh` startet ausdrücklich die TypeScript-Demo mit Fake-Provider auf Port 8101 und die Next.js-Weboberfläche. Die Python-Anwendung startet getrennt mit `python3 app.py` auf Port 8000. Die beiden Modi nicht verwechseln; Details: [Entwicklung](ENTWICKLUNG.md) und [Migration](MIGRATION.md).

## Arbeitsregeln und Quellenhierarchie

Vor Codeänderungen immer die [Projektregeln in `AGENTS.md`](../AGENTS.md) beachten. Besonders wichtig: Secrets, Cache-Dateien und Zugangsdaten niemals lesen, protokollieren oder committen; sichtbare Strings sind kurz und deutsch; API-Antworten und Helper-Signaturen kompatibel halten; Tests ohne echte Zugangsdaten ausführen. Android und macOS sowie Web haben Vorrang. iOS ist zurückgestellt.

Wenn Angaben voneinander abweichen, gilt diese Reihenfolge:

1. `AGENTS.md` und die dort genannten verbindlichen Bereichspläne
2. Implementierung und Tests des betroffenen Bereichs
3. Weitere Dateien unter [`plaene/`](../plaene/README.md)
4. Diese Überblicksdokumentation
5. Das ältere [`README.md`](../README.md), das noch historische Projektbeschreibungen enthält

Die verbindlichen Pläne sind [Backend](../plaene/BACKEND.md), [Android](../plaene/ANDROID.md), [macOS](../plaene/MACOS.md), [iOS](../plaene/IOS.md), [iOS-Gesamtplan](../plaene/IOS_APP_PLAN.md), [Funktionslücken](../plaene/EDUPAGE_LUECKENPLAN.md) und [Demo](../plaene/DEMO.md).

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
