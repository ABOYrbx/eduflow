# TypeScript-Migration: Status und Abgrenzung

## Ziel

Die schrittweise Migration soll den Flask-Monolithen durch NestJS, PostgreSQL/Prisma und Next.js ersetzen, **ohne** die existierenden Web-Funktionen oder Android-/macOS-Clients zu brechen. Die API bleibt unter demselben `/api/v1`-Präfix. Die Paritätspakete N0–NI sind umgesetzt; der Cutover (N-J) mit Live-Abgleich steht noch aus, daher bleibt Python bis zur Abnahme das Live-Backend.

Die ausführliche Ausgangs- und Phasenplanung liegt in `migration/README.md` (repo-intern, Stand vor N-A–NI); maßgeblich für den aktuellen Stand ist der Node-Paritätsplan `plaene/NODE_PARITAET.md`. Verbindliche Grenzen stehen weiter in `AGENTS.md` (repo-intern, nicht Teil dieser Website).

## Bestand im Repository

| Bereich | Ort | Technischer Stand |
| --- | --- | --- |
| API | `apps/api/` | NestJS 11, TypeScript 6, Controller/Services und alle `/api/v1`-Routen; echter EduPage-Anbieter plus Fake-Demo. |
| Persistenz | `apps/api/prisma/` | PostgreSQL-Schema (`UserAccount`, `CredentialVault`, `ApiToken`, `PendingSecondFactor`, Präferenzen, Zustände, Caches, Audit) und versionierte Migrationen; Prisma Client. |
| Schulprovider | `apps/api/src/edupage/`, `apps/api/src/school/demo-school.service.ts` | Echter Anbieter (Protokoll, Sitzung, Timeline, Bereiche N-A–NI) plus Fake-Anbieter nur für Demo (`EDUFLOW_PROVIDER=fake`, Logins `demo`/`demo`). |
| Web | `apps/web/` | Next.js 16, React 19, provider-neutrale Server-API-Routen, HttpOnly-Session-Cookies und Dashboard-Oberfläche. |
| Contracts | `packages/contracts/` | API-Präfix, Fehlercodes, Page-Typ und Type-Guard. |
| Installer/Demo | `install.sh`, `run.sh`, `migration/` | Interaktiver lokaler Setup-Assistent und Start der Fake-Demo (API 8101, Web 3000). |

Der Stack ist drahtkompatibel zu Python-`/api/v1` (gleiche Routen, DTOs, Fehlercodes und Auth-Abläufe im Echtpfad). `EDUFLOW_PROVIDER=fake` bleibt eine bewusste Demo-Grenze: Nur dort gelten synthetische Daten und Demo-Logins; jeder andere Wert wählt den echten EduPage-Anbieter.

## Umsetzungsstand: Pakete N0–NI fertig

- **N0 Fundament:** Paginierungs-Parität plus Routenmatrix-Test gegen alle 30 Python-Pfade.
- **N-A Auth echt:** EduPage-Login/2FA/Rate-Limit/Geräte, opake Bearer- plus Pending- und DL-Tokens, `/me`, `/devices` — drahtkompatibel zu Python.
- **N-B Nachrichten:** Liste/Thread/Senden/Antworten/Likes, lokal getracktes Ungelesen, Empfänger, Anhänge plus DL-Tokens.
- **N-C Hausaufgaben:** Filter, done/trash, Zähler, DTO-Parität.
- **N-D Stundenplan:** Tag/Woche, Lernzeit-Blöcke, Ganztags-Filter.
- **N-E Noten:** Notenprotokoll, Fachabbildung, Cache.
- **N-F Einstellungen:** Schema-Parität, Präferenzen, Cache-Clear.
- **N-G Meta:** Mensa-PDF-Parser in TypeScript plus Wochen-Cache, Wetter-Proxy plus Suche.
- **N-H Schulalltag:** Vertretungen plus Agenda.
- **N-I Web:** Next.js provider-neutral (Sitzungen ohne Refresh-Token-Abhängigkeit).

## Offen: N-J Cutover

Live-DTO-Abgleiche Python↔Node brauchen einen Staging-Server mit echten Zugangsdaten (nicht offline machbar); danach folgen App-Umschaltung und Python-Archivierung. **Kein Löschen ohne explizite Freigabe.**

Die Fake-Funktionalität darf nicht als echte Schul- oder Live-Wetterfunktion dokumentiert werden. Die Python-App und nativen Clients bleiben erhalten, bis alle Funktions- und Vertragsprüfungen bestanden sind.

## Aktuelle Auth-/Persistenzform

Das Prisma-Schema definiert Modelle für `UserAccount`, `CredentialVault`, `ApiToken`, `PendingSecondFactor`, `UserPreference`, `LocalResourceState`, `ResourceCache` und `AuditEvent`. Konto-Präferenzen, tokenbezogene Metadaten, lokale Zustände und Cache-Platzhalter sind damit relational abgebildet.

Der Anbieter bestimmt die Auth-Form: Im Fake-Modus stellt der Demo-Service JWT-Zugangs- und Refresh-Token aus; im Echtpfad meldet der EduPage-Anbieter an (inklusive 2FA-`pending_token` mit zehn Minuten TTL) und stellt opake Bearer-Token aus — Antwortformen, TTLs und Rate-Limit wie Python. Der Fake-Schulservice hält versendete Demo-Nachrichten im Service-Speicher; persönliche Einstellungen und lokale Aufgabenstatus werden dagegen über Prisma-Modelle geschrieben.

Die Next-Weboberfläche hält Sitzungen in HttpOnly-Cookies und leitet API-Aufrufe serverseitig weiter (provider-neutral, ohne Refresh-Token-Abhängigkeit).

## Restabweichungen gegenüber Python

Der Echtpfad teilt Routen, DTOs, Fehlercodes und Auth-Abläufe mit Python. Bekannte Restunterschiede:

- TypeScript bietet `POST /devices` zur Ausstellung eines weiteren Gerätetokens. Die Python-API v1 hat diese Route nicht; Web-Tokens werden dort über `/einstellungen/api-token` erstellt.
- Nur der Fake-Modus gibt JWT-Zugangstoken **und** Refresh-Token zurück und erwartet den Refresh-Token im JSON-Body; der Echtpfad nutzt wie Python opake Bearer-Token.
- Die handgepflegte OpenAPI-Antwort beider Server ist nicht voll typisiert; der Routenmatrix-Test prüft alle 30 Python-Pfade, ersetzt aber keinen Live-Abgleich.

Vor der Client-Umschaltung (N-J) gilt weiter: Test-Fixtures aus den Python-Responses erstellen und Android/macOS-Decoding offline prüfen.

## Lokal starten und testen

Voraussetzungen, Installer-Verhalten und Befehle stehen vollständig unter [Entwicklung und Tests](ENTWICKLUNG.md). Kurzfassung:

```bash
./install.sh
./run.sh
```

Der dokumentierte Start bleibt die Fake-Demo: `./install.sh` richtet PostgreSQL und lokale API-Konfiguration ein, `./run.sh` prüft Abhängigkeiten und Datenbankkonfiguration, startet die Fake-API auf Port 8101 (wartet auf `/api/v1/health`) und danach die Weboberfläche, normalerweise Port 3000. `Ctrl+C` beendet beide. Demo-Konten: `demo` / `demo`; 2FA-Demo: `demo-2fa` / `demo`, Code `123456`. Ausschließlich synthetische Demodaten verwenden. `run.sh` setzt `API_SERVER_URL` für Next.js dabei auf `http://127.0.0.1:8101`.

Für Qualitätsprüfungen aus dem Stamm:

```bash
npm run typecheck
npm test
npm run build
```

Die Tests verwenden Fakes/Stubs und Fixtures aus dem EduPage-Protokollnachbau; der Live-Abgleich gegen echte EduPage-Konten (N-J) steht aus, und ein solcher darf keine realen Zugangsdaten in die Test-Suite übernehmen.

## Abschlusskriterien der Migration

Die Python-Referenz darf erst nach ausdrücklicher Funktionsabnahme entfernt oder ersetzt werden. Stand der Kriterien: echter EduPage-Adapter (N-A) und Bereichsparität (N-B–NI) sind implementiert; ausstehend sind der Live-Abgleich aller Routen/DTOs gegen echte Konten, die Client-Umschaltung von Android/macOS und der nachgewiesene Rückbau des Python-Pfads. Im Einzelnen:

1. ein sicherer echter EduPage-Adapter für alle freigegebenen Lese-/Schreibabläufe implementiert ist;
2. alle dokumentierten API-Routen, Statuscodes, DTOs, Filter, Paginierung, Cache-/State-Regeln und Downloads kompatibel oder ausdrücklich versioniert sind;
3. Web-Login, 2FA, Sitzungswechsel, Einstellungen, Fehler-/Ladezustände und jede bestehende Web-Funktion automatisiert geprüft sind;
4. PostgreSQL-Setup und additive Migrationen auf einer frischen lokalen Datenbank getestet sind;
5. Android und macOS ihre bestehenden Offline-Verträge und simulierten UI-Flows gegen die neue API bestehen;
6. Tests keine echten Passwörter, Schlüssel, Tokens oder persönlichen Schuldaten enthalten;
7. der Rückbau des Python-Pfads ohne Funktionsverlust nachgewiesen ist.

iOS bleibt bis zu einem ausdrücklichen Projektauftrag zurückgestellt. Rollen-/Verwaltungsfunktionen, öffentliche Produktivbereitstellung und andere in `AGENTS.md` ausgeschlossene Ziele sind nicht Teil dieser Migration.
