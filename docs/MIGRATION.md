# TypeScript-Migration: Status und Abgrenzung

## Ziel

Die schrittweise Migration soll den Flask-Monolithen durch NestJS, PostgreSQL/Prisma und Next.js ersetzen, **ohne** die existierenden Web-Funktionen oder Android-/macOS-Clients zu brechen. Die API bleibt zunächst unter demselben `/api/v1`-Präfix. Es gibt noch keinen Beleg, dass der Python-Server vollständig ersetzt werden kann.

Die ausführliche Ausgangs- und Phasenplanung liegt in `migration/README.md` (repo-intern); verbindliche Grenzen stehen weiter in `AGENTS.md` und `plaene/BACKEND.md` (repo-intern, nicht Teil dieser Website).

## Bestand im Repository

| Bereich | Ort | Technischer Stand |
| --- | --- | --- |
| API | `apps/api/` | NestJS 11, TypeScript 6, JWT-basierte Demo-Authentifizierung, Controller/Services und API-Routen. |
| Persistenz | `apps/api/prisma/` | PostgreSQL-Schema und versionierte Migrationen; Prisma Client. |
| Schulprovider | `apps/api/src/school/demo-school.service.ts` | Synthetische Nachrichten, Aufgaben, Noten, Stunden, Schultermine, Essen und Wetter für Tests/Demo. Kein echter EduPage-Provider. |
| Web | `apps/web/` | Next.js 16, React 19, Server-API-Routen, HttpOnly-Session-Cookies und Dashboard-Oberfläche. |
| Contracts | `packages/contracts/` | API-Präfix, Fehlercodes, Page-Typ und Type-Guard. Noch keine vollständigen DTOs aller Ressourcen. |
| Installer/Demo | `install.sh`, `run.sh`, `migration/` | Interaktiver lokaler Setup-Assistent und Start der Fake-API/Web-App. |

Der beschriebene Stack ist für lokale Entwicklung, synthetische Daten und UI-/API-Arbeit gedacht. `EDUFLOW_PROVIDER=fake` ist eine bewusste Sicherheitsgrenze. Ist der Fake-Provider nicht eingeschaltet, melden Authentifizierung und Schulressourcen derzeit, dass der Anbieter nicht konfiguriert ist.

## Was noch fehlt

**Der echte EduPage-Adapter ist nicht implementiert.** Es fehlen insbesondere:

- tatsächliche EduPage-Anmeldung, persistente/erneuerbare upstream Session und automatische Subdomain-Ermittlung;
- Wiederverwendung der bisherigen Bibliothekslogik, Fehlerübersetzung für echte EduPage-Antworten, Captcha und EduPage-2FA;
- Live-Abruf und unterstützte Schreiboperationen für Nachrichten, Aufgaben, Stundenplan, Noten, Vertretungen und Schultermine;
- echter Mensa-PDF-Download und -Parser sowie OpenWeather-Integration;
- systematischer DTO-/OpenAPI-Abgleich mit `api/` und Dekodierung in Kotlin/Swift;
- vollständige Browser-E2E-Tests, PostgreSQL-Integrationsmatrix und native UI-Smoke-Tests gegen die neue API.

Die vorhandene Fake-Funktionalität darf nicht als echte Schul- oder Live-Wetterfunktion dokumentiert werden. Die Python-App und nativen Clients bleiben erhalten, bis alle Funktions- und Vertragsprüfungen bestanden sind.

## Aktuelle Auth-/Persistenzform

Das Prisma-Schema definiert Modelle für `UserAccount`, `CredentialVault`, `ApiToken`, `PendingSecondFactor`, `UserPreference`, `LocalResourceState`, `ResourceCache` und `AuditEvent`. Konto-Präferenzen, tokenbezogene Metadaten, lokale Demo-Zustände und Cache-Platzhalter sind damit relational vorgesehen.

Der Fake-Auth-Service stellt JWT-Zugangs- und Refresh-Token aus und persistiert deren Hashes in `ApiToken`; Login-Daten sind künstlich. Das Vorhandensein von `CredentialVault` im Schema bedeutet **nicht**, dass ein echter EduPage-Credential-Flow bereits implementiert ist. Der Fake-Schulservice hält versendete Demo-Nachrichten im Service-Speicher; persönliche Einstellungen und lokale Aufgabenstatus werden dagegen über Prisma-Modelle geschrieben.

Die Next-Weboberfläche setzt Zugang und Refresh-Token in HttpOnly-Cookies und leitet API-Aufrufe serverseitig weiter. Der Web-Proxy versucht bei 401, das Refresh-Token zu rotieren. Vor Client-Migration muss dieses Verhalten mit dem Python-Tokenvertrag vereinheitlicht werden.

## Vertragslücken gegenüber Python

Die beiden Systeme teilen ein Routeninventar, aber nicht in jedem Detail dieselbe Semantik:

- Python stellt im dokumentierten API v1 Login mit einem opaken API-Token bereit; der aktuelle TypeScript-Fake gibt JWT-Zugangstoken **und** Refresh-Token zurück.
- Python-Refresh authentifiziert mit dem Bearer-Token und prüft EduPage-Zugangsdaten erneut. TypeScript erwartet bevorzugt einen separaten Refresh-Token im JSON-Body und hat keinen echten EduPage-Recheck.
- TypeScript bietet `POST /devices` zur Ausstellung eines weiteren Tokenpaars. Die Python-API v1 hat diese Route nicht; Web-Tokens werden dort über `/einstellungen/api-token` erstellt.
- TypeScript-Fake-Daten und Fehlertexte sind synthetisch. Ebenso sind sein Wetter und Essensplan keine Live-Antworten.
- Die handgepflegte OpenAPI-Antwort beider Server ist nicht voll typisiert; Routenpräsenz ist noch kein Nachweis, dass DTOs, Fehlercodes, Listenhüllen, Datenschutz oder Seiteneffekte übereinstimmen.

Vor jeder Aktivierung für echte Clients gilt: Vertrag vereinheitlichen oder explizit versionieren, Test-Fixtures aus den Python-Responses erstellen und Android/macOS-Decoding offline prüfen.

## Lokal starten und testen

Voraussetzungen, Installer-Verhalten und Befehle stehen vollständig unter [Entwicklung und Tests](ENTWICKLUNG.md). Kurzfassung:

```bash
./install.sh
./run.sh
```

Der Fake-Server läuft auf Port 8101; die Weboberfläche normalerweise auf 3000. Demo-Konten: `demo` / `demo`; 2FA-Demo: `demo-2fa` / `demo`, Code `123456`. Ausschließlich synthetische Demodaten verwenden. **Achtung:** `run.sh` setzt `API_SERVER_URL` für Next.js aktuell nicht auf 8101; die Web-API-Routen fallen auf Port 8001 zurück. Ohne extern gesetztes `API_SERVER_URL=http://127.0.0.1:8101` kann der Browser die Demo-API daher verfehlen (siehe [Entwicklung](ENTWICKLUNG.md)).

Für Qualitätsprüfungen aus dem Stamm:

```bash
npm run typecheck
npm test
npm run build
```

Die Tests verwenden Fakes/Stubs; es gibt noch keine vollständige E2E-Abnahme gegen ein echtes EduPage-Konto, und eine solche darf keine realen Zugangsdaten in die Test-Suite übernehmen.

## Abschlusskriterien der Migration

Die Python-Referenz darf erst nach ausdrücklicher Funktionsabnahme entfernt oder ersetzt werden, wenn:

1. ein sicherer echter EduPage-Adapter für alle freigegebenen Lese-/Schreibabläufe implementiert ist;
2. alle dokumentierten API-Routen, Statuscodes, DTOs, Filter, Paginierung, Cache-/State-Regeln und Downloads kompatibel oder ausdrücklich versioniert sind;
3. Web-Login, 2FA, Sitzungswechsel, Einstellungen, Fehler-/Ladezustände und jede bestehende Web-Funktion automatisiert geprüft sind;
4. PostgreSQL-Setup und additive Migrationen auf einer frischen lokalen Datenbank getestet sind;
5. Android und macOS ihre bestehenden Offline-Verträge und simulierten UI-Flows gegen die neue API bestehen;
6. Tests keine echten Passwörter, Schlüssel, Tokens oder persönlichen Schuldaten enthalten;
7. der Rückbau des Python-Pfads ohne Funktionsverlust nachgewiesen ist.

iOS bleibt bis zu einem ausdrücklichen Projektauftrag zurückgestellt. Rollen-/Verwaltungsfunktionen, öffentliche Produktivbereitstellung und andere in `AGENTS.md` ausgeschlossene Ziele sind nicht Teil dieser Migration.
