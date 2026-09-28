# EduFlow TypeScript-Migration

## Zweck und Leitplanken

Dieses Verzeichnis begleitet den schrittweisen Ersatz des Python-Webservers durch NestJS, PostgreSQL/Prisma und Next.js. Android und macOS (sowie das zurückgestellte iOS) bleiben kompatibel mit `/api/v1` bis die Ersatzimplementierung denselben Vertrag nachweisbar erfüllt. Die bestehenden Clients bleiben eigenständige Produkte und werden nicht aus dem Repository entfernt.

Es gibt aktuell keine fachliche relationale Datenbank und damit keine vorhandenen Tabellen zu kopieren. EduPage ist die Quelle für Nachrichten, Hausaufgaben, Stundenplan, Noten, Vertretungen und Schultermine. Lokal gespeichert werden überwiegend abgeleitete/temporäre JSON-Caches, persönliche Einstellungen, Gelesen-/Papierkorb-/Like-Zustände, Login-Sitzungen und API-Tokens. Die Migration führt dafür persistente PostgreSQL-Modelle ein und lässt EduPage zunächst die fachliche Quelle bleiben.

## Ist-Architektur

- Flask-Monolith `app.py`: HTML-Webseiten, Session-/2FA-Login, EduPage-Session-Aufbau, Datenaufbereitung, Caching und Aktionen.
- Flask-Blueprint `api/`: JSON-API `/api/v1`, Fehlerformat `{error, code}`, Bearer-Token, Paginierung sowie die Bereiche Auth, Nachrichten, Aufgaben, Stundenplan, Noten, Meta, Einstellungen, Geräte und Schulalltag.
- `cache.py` und JSON unter `.cache/`: Cache und lokale Benutzerzustände. Secret-, Cache- und Login-Dateien sind ausdrücklich außerhalb dieser Analyse und Migration.
- `essen.py`: SWS-PDF-Menüparser und Wochen-Cache. `static/` und `templates/`: Web-UI.
- Native Clients Android/macOS/iOS verwenden `/api/v1`; ihre DTOs sind deshalb ein Kompatibilitätsvertrag. Android und macOS sind aktiv, iOS bleibt laut Projektvorgabe zurückgestellt.

## Datenmodell-Entwurf

| Prisma-Modell | Zweck / Quelle | Migrationshinweis |
| --- | --- | --- |
| `UserAccount` | EduPage-Schulsubdomain und Nutzername | Stabile lokale Kontoidentität; kein EduPage-Passwort im Klartext. |
| `CredentialVault` | verschlüsselte EduPage-Zugangsdaten für Re-Login | Verschlüsselungsschlüssel nur aus Deployment-Secret; nie in DB-Logs oder API-Antworten. |
| `AccessToken` | Geräte-/API-Token-Metadaten und gehashter Access-/Refresh-Token | Token-Rotation und Widerruf pro Gerät; Refresh-Token-Hash mit Ablauf/Reuse-Schutz. |
| `PendingSecondFactor` | kurzlebiger 2FA-Ablauf | TTL und einmalige Einlösung; Upstream-Challenge bleibt serverseitig. |
| `UserPreference` | Schema-Werte der Einstellungen | Unique auf Konto + Schlüssel; validierte JSON-Werte. |
| `LocalResourceState` | gelesen, verborgen, Likes und erledigt-UI-Zustand | Typisierter JSON-Nutzinhalt, Unique auf Konto + Ressource + Schlüssel. |
| `ResourceCache` | optionale Snapshot-Caches für EduPage-Antworten | Ablaufzeit, Cache-Key, JSONB; kein Ersatz für Upstream-Wahrheit. |
| `AuditEvent` | sicherheitsrelevante Login-/Token-Aktionen | Keine Passwörter, Codes, Tokenwerte oder vollständigen Anfrage-Bodies. |

Kein lokal abgeleitetes `Message`, `Grade` oder `Lesson` wird zur autoritativen Wahrheit erklärt. Solche Daten können nur als zeitlich begrenzter Cache gespiegelt werden.

## Schnittstelleninventar

Die Referenz ist der bestehende `api/system.py`-OpenAPI-Endpunkt (`GET /api/v1/openapi.json`) plus die tatsächlichen Handler in `api/`. Die Antwort-DTOs bleiben in der ersten Migrationsstufe unverändert.

| Bereich | Routen |
| --- | --- |
| System | `GET /health`, `GET /openapi.json` |
| Auth/Geräte | `POST /auth/login`, `POST /auth/2fa`, `POST /auth/logout`, `POST /auth/refresh`, `GET /me`, `GET /devices`, `POST /devices`, `DELETE /devices/{token_hash}` |
| Nachrichten | `GET /messages`, `GET /messages/{id}/thread`, `POST /messages/read`, `GET /recipients`, `POST /messages/send`, `POST /messages/{id}/reply`, `POST /messages/download-token`, `GET /messages/{id}/attachments/{idx}` |
| Hausaufgaben | `GET /homework`, `POST /homework/{id}/done`, `POST /homework/{id}/trash` |
| Stundenplan/Schulalltag | `GET /timetable/day`, `GET /timetable/week`, `GET /substitutions/week`, `GET /school/agenda` |
| Noten | `GET /grades` |
| Essen/Wetter | `GET /essen`, `GET /wetter`, `GET /wetter/suche` |
| Einstellungen | `GET /settings`, `PUT /settings`, `POST /cache-clear` |

Abfrageparameter, Fehlercodes und Beispielantworten werden vor einer Route-Migration als Vertrags-Fixtures aus `openapi.json` und dem aktuellen API-Testbestand eingefroren. Erfolgs-DTOs sollen byte-/semantik-kompatibel bleiben, insbesondere für Kotlin-Serialization und Swift Codable.

## Geschäftslogik, die erhalten werden muss

- Login mit automatischer EduPage-Subdomain-Erkennung, Bad-Credentials/Captcha/2FA-Fehlerabbildung, 2FA mit einmaligem Zwischen-Token, Geräteverwaltung, Logout und Refresh-Rotation.
- EduPage-Re-Login je Datenabruf und Wiederverwendung des upstream Authentifizierungs-/Session-Kontexts; niemals echte Zugangsdaten in Test-Fixtures.
- Nachrichten-Historie, Filter/Suche/Paginierung, Thread-Likes/-Antworten, Empfängersuche, Senden/Antworten und eingeschränkte/kurzlebige Anhänge-Downloads.
- Aufgabenstatus, Frist-Berechnung, `include_tests`, Filter/Zähler/Sortierung, serverseitiges `done` und lokaler Papierkorb.
- Tages-/Wochenstundenplan samt zusammengefasster Lernzeit, Cache-/Refresh-Verhalten, Essens-PDF-Auswertung, Wetterdaten und Stadt-Suche.
- Noten nach Fach/Term, Schulkalendar/Prüfungen/Anwesenheit, navigierbare Vertretungswochen sowie Einstellungen und selektives Cache-Leeren.
- Deutsche knappe UI- und Fehlertexte, bestehende Web-Funktionalität und aktuelle mobile Navigation/Interaktionen.

## Zielarchitektur

`apps/api` ist ein NestJS-Modul-Monolith mit Controller → Use Case/Service → Repository/Upstream-Adapter. Prisma ist der einzige persistente Datenzugriff. Ein expliziter EduPage-Adapter kapselt Upstream HTTP/Session/2FA, Fehlerübersetzung, Retry und Rate-Limit. `apps/web` ist Next.js/React mit serverseitigem Session-Zugriff auf die API, responsiven wiederverwendbaren Komponenten und deutschen UI-Strings. `packages/contracts` hält DTOs, Fehlercodes und OpenAPI/Client-Vertrag. PostgreSQL speichert lokale Konten, Token-Metadaten, Zustände und optionale TTL-Caches.

Die Einführung ist strangler-basiert: neue API-Bereiche werden einzeln hinter demselben `/api/v1`-Vertrag ersetzt. Python-Webserver/API werden erst entfernt, nachdem Backend-Parität, alle Clients und Web-Funktionsparität für den Bereich abgenommen sind.

## Umsetzungsstand (2026-09-26)

Der Branch enthält ein installierbares TypeScript-Monorepo, Prisma-Schema und PostgreSQL-Migration, NestJS-Routen für das API-Inventar, JWT-/Refresh-/2FA-Demo-Authentifizierung, einen zustandsbehafteten Fake-Schulprovider sowie eine Next.js-Weboberfläche für Übersicht, Nachrichten, Aufgaben, Noten, Stundenplan, Termine und Einstellungen. Der Fake-Provider ist ausschließlich für lokale Entwicklung und UI-Tests vorgesehen (`EDUFLOW_PROVIDER=fake`; Login `demo` / `demo`).

**Die Migration ist noch nicht funktionsgleich und nicht produktiv verwendbar.** Der echte EduPage-Session-/Login-/Datenadapter einschließlich Captcha, Upstream-2FA und PDF-Menüparser fehlt. Solange er fehlt, liefert der API-Server für Nicht-Demo-Betrieb einen Konfigurationsfehler. Die API-DTOs und `openapi.json` müssen zusätzlich systematisch gegen die Python-Implementierung und native Kotlin-/Swift-Decodierung verglichen werden. Android-, macOS- und iOS-Clients wurden nicht auf den neuen Server umgestellt oder vollständig UI-getestet; der Python-Server und aktuelle Clients sind deshalb absichtlich im Repository belassen. Es gibt bislang Unit-/Vertragstests und manuelle Browser-Smoke-Checks, aber keine vollständige Web-E2E- oder native UI-Testmatrix.

**Prüfstand dieses Arbeitsinkrements (26.09.2026):** API-Typecheck, NestJS-Build und 12 API-Unit-/Vertragstests erfolgreich; Web-Typecheck und Next.js-Produktionsbuild erfolgreich; Android-Debug-Build und 59 Offline-Unit-Tests erfolgreich; macOS 53 und iOS 41 Offline-Tests erfolgreich. Die nativen Tests prüfen ihre vorhandenen Fakes und API-Verträge, nicht die Verbindung zum neuen NestJS-Server. Die Web-Oberfläche wurde manuell auf den Hauptseiten und bei 390 px geprüft; ein automatisierter vollständiger E2E-Lauf fehlt weiterhin.

Lokaler Demo-Start (Node.js 20.9+ und npm erforderlich; PostgreSQL kann der Installer bei Bedarf einrichten):

```sh
./install.sh
./run.sh
```

Der Installer zeigt zuerst das erkannte System und danach kompakte Fortschrittsmeldungen. Für die vollständige Ausgabe, etwa Paket- und Downloadmeldungen, starte ihn mit `./install.sh -debug`.

Der Installer fragt zuerst, ob PostgreSQL bereits installiert/verfügbar ist. Bei „Ja“ fragt er Host, Port, Datenbank, Benutzer und verborgenes Passwort wie bisher ab; diese Datenbank muss bereits angelegt sein. Bei „Nein“ installiert er PostgreSQL 16 über Homebrew auf macOS oder PostgreSQL über apt auf Debian/Ubuntu. Auf macOS versucht er zuerst den Homebrew-Dienst und startet PostgreSQL bei einem LaunchAgent-Fehler direkt über `pg_ctl`. Danach erstellt er lokal `eduflow_dev` samt `eduflow`-Rolle. Das Passwort für diese neue Rolle wird sicher generiert. Bereits existierende Rollen oder Datenbanken werden nicht überschrieben; bei Namenskonflikten bricht der Installer ab.

Anschließend fragt der Installer ein optional selbst gesetztes JWT-Secret und einen optional selbst gesetzten Verschlüsselungsschlüssel ab. Leere Schlüssel-Eingaben werden kryptografisch sicher generiert. Passwörter und Schlüssel werden nicht angezeigt und in `apps/api/.env.local` mit Dateirechten `0600` gespeichert; diese Datei ist von Git ausgeschlossen. Eine bereits vorhandene Konfiguration wird weder gelesen noch überschrieben. Prisma spielt ausschließlich die versionierten Migrationen ein und setzt keine Daten zurück. Bei Bedarf lassen sich Client-Erzeugung und Migration später über `npm run db:generate` und `npm run db:deploy` wiederholen.

Der TypeScript-Demo-Server verwendet derzeit den Fake-EduPage-Anbieter und benötigt keine externen EduPage- oder OpenWeather-API-Keys. EduPage-Benutzernamen und -Passwörter werden nicht abgefragt oder gespeichert. Ein echter EduPage-Adapter ist noch nicht implementiert. `run.sh --demo` startet die Fake-API auf Port 3100 und die Weboberfläche auf Port 8101; wenn der Port belegt ist, wählt Next.js automatisch einen freien Folgeport. Mit `Ctrl+C` werden beide beendet.

Das Demo-Konto lautet `demo` / `demo`; für den 2FA-Durchlauf `demo-2fa` / `demo`, Code `123456`. Diese Logins funktionieren nur im expliziten Fake-Modus. Auf echten Konten/Daten wurden keine Tests ausgeführt.

## Phasen und Abnahmekriterien

1. **Analyse (laufend):** Route-/DTO-Inventar, Feature-Matrix, Sicherheits-/Abhängigkeitsliste und Test-Fixtures ohne sensible Daten.
2. **Architektur:** Monorepo, strikte TS-Konfiguration, Prisma-Modelle/Migrationen, Auth-/Cache-Sicherheitsentwurf, OpenAPI-Vertrag.
3. **Backend:** Auth und alle Bereiche mit Repository/Adapter, bestehendem Fehlerformat und Routenkompatibilität. Für jeden Bereich Contract- und Integrations-Fixtures; Postgres-Integration separat.
4. **Frontend:** Next.js ersetzt sämtliche elf Web-Seiten und Form-/Aktionen. API-Clients, Responsive-Layouts, Login/2FA und leere/Fehler/Ladezustände.
5. **Qualität:** Unit-, Contract-, DB-Integration- und e2e-Tests; Fake-EduPage-Provider/Testkonto ausschließlich in Tests; Android/macOS API-Contract- und UI-Smoke-Tests. Keine Live-Konto-Zugangsdaten in Tests.

Migration gilt erst als abgeschlossen, wenn alle oben gelisteten API-Routen und Web-Funktionen abgedeckt sind, Android/macOS gegen den neuen Server durch ihre bestehenden Test-Suiten und simulierte UI-Flows laufen, die Prisma-Migration auf einer frischen PostgreSQL-DB funktioniert und die Python-Implementierung ohne Funktionsverlust entfernbar ist. Ohne EduPage-Testkonto sind echte Upstream-Anmeldungen nicht beweisbar; Auth- und Oberfläche werden daher gegen einen kontrollierten Fake-Provider geprüft.
