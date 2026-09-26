# Architektur und Datenfluss

## Überblick

```text
                         ┌─────────────────────────────────────────┐
                         │ EduPage + externe Quellen               │
                         │ EduPage-API · SWS-Mensa-PDF · OpenWeather│
                         └───────────────────┬─────────────────────┘
                                             │
┌───────────────────────────────┐  ┌─────────▼────────────────────┐
│ Browser: Flask-Weboberfläche  │  │ Python-Anwendung            │
│ templates/ + static/          ├─►│ app.py · cache.py · essen.py │
└───────────────────────────────┘  └─────────┬────────────────────┘
                                             │
                                    /api/v1 (JSON)
                         ┌───────────────────┴───────────────────┐
                         │                                       │
                  Android-Client                            macOS-Client
                    Kotlin/Compose                            SwiftUI

Separater Migrationspfad (kein Ersatz im Livebetrieb):
Next.js-Web ──HTTP──► NestJS-API ──► Prisma/PostgreSQL
                          │
                          └── Fake-Schulprovider (nur lokale Demo)
```

Android und macOS verwenden die Python-API als gemeinsamen Datenvertrag. Der TypeScript-Stack ist eine parallel entwickelte Migration und für die Demo konfiguriert; er verbindet sich nicht mit EduPage. iOS ist implementiert, wird nach Projektvorgabe derzeit aber nicht aktiv weitergebaut.

## Python-Referenzanwendung

### Zuständigkeiten

- `app.py`: Flask-Einstiegspunkt; HTML-Routen, Login und 2FA, EduPage-Sitzungsaufbau, DTO-/Template-Helper, Übersicht, Einstellungen sowie gemeinsame Fachlogik.
- `api/__init__.py`: erstellt den einzigen Flask-Blueprint `api_v1` und bindet die API-Teilmodule ein. `app.py` registriert diesen Blueprint einmal mit `/api/v1`.
- `api/core.py`: API-Token, Auth-Decorator, Fehlerformat, Fehlercodes und Listen-Paginierung.
- `api/auth.py`, `messages.py`, `homework.py`, `timetable.py`, `grades.py`, `meta.py`, `settings.py`, `school.py`, `system.py`: Routen pro Bereich. Die meisten Teilmodule importieren Web-Helper erst innerhalb eines Requests, damit kein Importzyklus entsteht.
- `cache.py`: dateibasierte Cache- und persönliche Statusablage.
- `essen.py`: Mensa-Wochenplan laden und PDF-Inhalt in ein gemeinsames JSON-Format umwandeln.

Die API-Pakete verwenden die vorhandenen Helper und DTO-Bauer aus `app.py`, statt für Web und Apps parallele Datenformate zu erfinden. Schultermine und Prüfungen werden über `api/school.py` aus der Timeline gebaut. Die API bleibt additiv zur Weboberfläche; bestehende Web-Routen sind kein Ersatz für API-Routen.

### Request-Flüsse

**Web:** Der Browser besitzt eine signierte Flask-Sitzung. Passwörter werden vor dem Speichern in der Sitzung Fernet-verschlüsselt. Bei geschützten Seiten wird damit eine EduPage-Sitzung aufgebaut oder, falls möglich, eine vorhandene PHP-Sitzung wiederverwendet. Die Webrouten rendern HTML-Templates; POST-Formulare und Fetch-Schreiboperationen müssen den CSRF-Token mitsenden.

**Native App → Python API:**

1. `POST /api/v1/auth/login` prüft die EduPage-Anmeldung. Falls nötig folgt `POST /auth/2fa`.
2. Die App speichert das ausgegebene opake Token lokal und hängt es als `Authorization: Bearer …` an geschützte Aufrufe.
3. `api/core.py` prüft den Token-Hash und entschlüsselt die gespeicherten Zugangsdaten nur für den Request-Kontext.
4. Der Ressourcen-Handler meldet sich bei EduPage an beziehungsweise verwendet eine kurzlebig gecachte EduPage-Sitzung, ruft die Quelldaten ab und baut die gleiche Art Anzeigeobjekt wie das Web.
5. Antworten verwenden JSON; Listen enthalten eine gemeinsame Paginierungshülle. Abgelaufene oder nicht mehr gültige Sitzungen melden stabile Codes.

Der API-Token ist opak, nicht die EduPage-PHP-Sitzung. Im **serverseitigen Python-Token-Speicher** liegt der Hash des API-Tokens und das EduPage-Passwort verschlüsselt, nicht der API-Token im Klartext. Ein autorisierter Client muss den ausgegebenen Token lokal speichern und bei Requests mitsenden: Android verwendet DataStore, macOS eine nur für den Eigentümer lesbare Token-Datei. Der API-Download kann zusätzlich kurzlebige, an Benutzer und Datei gebundene `?dl=`-Tokens verwenden.

## Datenquellen und lokaler Zustand

EduPage ist die Quelle für Nachrichten, Aufgaben, Noten, Stundenplan, Vertretungen, Kalender-/Prüfungs- und Anwesenheitsereignisse. Essens- und Wetterdaten kommen aus getrennten externen Quellen. Die lokalen JSON-Dateien sind Caches oder UI-Zustand und keine Kopie der autoritativen Schulverwaltung.

| Zustand | Ablage / Standardverhalten | Bemerkung |
| --- | --- | --- |
| Timeline | ein Cache pro gehashtem Benutzer; frisch 15 Minuten | Bei altem Cache werden standardmäßig sofort alte Daten angezeigt und das letzte 60-Tage-Fenster im Hintergrund neu geladen. |
| Stundenplan | Cache pro Benutzer und Datum | Vergangene Tage: 7 Tage; Heute: 10 Minuten; Zukunft: 1 Stunde. |
| Noten | ein Cache pro Benutzer; 1 Stunde | Frischer Cache kann ohne EduPage-Login beantwortet werden. |
| Nachrichten-Threads | ein Cache pro Benutzer und Event; 1 Stunde | Speichert Likes, Antworten und Zusammenfassung. |
| Mittagessen | gemeinsamer Wochen-Cache; 6 Stunden | Bei Netz-/Quellfehlern wird ein vorhandener alter Wochenstand bevorzugt. |
| Gelesen-Status | IDs pro Benutzer | EduPage stellt für diesen Zweck kein Ungelesen-Flag bereit. |
| Aufgaben-Papierkorb | IDs pro Benutzer | Ausschließlich lokal; löscht die Aufgabe nicht bei EduPage. |
| Einstellungen | Werte pro Benutzer | Absichtlich vom Befehl „Cache leeren“ ausgenommen. |

Die Cache-Dateien liegen im ignorierten Verzeichnis `.cache/`; niemals manuell öffnen, in Fehlerausgaben kopieren oder committen. Details zu einstellbaren Laufzeiten stehen unter [Entwicklung](ENTWICKLUNG.md).

## Authentifizierung und Sicherheit

### Python/Web

- Die Web-Sitzung verwendet ein signiertes Flask-Cookie; das gespeicherte EduPage-Passwort liegt darin verschlüsselt.
- Eine 2FA-Challenge liegt nur vorübergehend im serverseitigen Speicher. Die Standard-TTL ist zehn Minuten.
- Schreibende Web-Requests werden mit einem Synchronizer-CSRF-Token geschützt. Logout und Cache-Leeren akzeptieren POST.
- „Angemeldet bleiben“ bestimmt die Web-Cookie-Laufzeit; bei aktivierter Option sind es 30 Tage.

### Python/API

- API-Token sind standardmäßig 30 Tage gültig. Der Tokenwert wird gehasht gespeichert; das EduPage-Passwort wird mit Fernet verschlüsselt.
- Login-Rate-Limit: standardmäßig 20 Versuche je zehn Minuten und Client-IP. `X-Forwarded-For` wird nur nach ausdrücklicher Proxy-Konfiguration vertraut.
- 2FA-Pending-Token sind zehn Minuten gültig. Download-`dl`-Tokens sind standardmäßig fünf Minuten gültig und gelten für eine konkrete Datei.
- Header-/Download-Token sollen nie geloggt werden. Werkzeug-Request-Logs maskieren `token=` und `dl=`-Querywerte.
- **Bekannte native Debug-Risikoabweichung:** Android hängt in Debug-Builds einen OkHttp-`BASIC`-Logger an, der Request-URLs protokolliert. Download-URLs können kurzlebige `dl`-Tokens enthalten; deshalb Debug-Logcat als vertraulich behandeln und nicht teilen. Das widerspricht dem Projektziel, Tokens nicht zu protokollieren, und sollte bei einer späteren Codeänderung bereinigt werden. Release-Builds aktivieren diesen Interceptor nicht.
- Wetter-Schlüssel bleibt serverseitig. Datei-Downloads werden auf `*.edupage.org` eingeschränkt und durch die EduPage-Sitzung weitergereicht.

### Grenzen

Das Projekt ist als lokales Werkzeug konzipiert, nicht als öffentlicher Mehrbenutzer-Dienst. Den Entwicklungsserver nicht öffentlich ins Internet exponieren. Secrets und persönliche Daten gehören nicht in Logs, Screenshots, Fixtures, Dokumentation oder Commits. Projektweit gilt: `.env`, Cache, Schlüssel und API-Token-Speicher nicht lesen/loggen/committen.

## TypeScript-Migrationsarchitektur

`apps/api/` ist ein NestJS-Modul-Monolith: Controller → Service → Prisma/PostgreSQL. `apps/web/` ist eine Next.js-/React-Oberfläche. Gemeinsame TypeScript-Grundverträge liegen in `packages/contracts/`. Der Next.js-Server hält Zugangstokens in HttpOnly-Cookies und leitet `/api/v1/*` serverseitig an die API weiter.

Der derzeitige Provider ist ein künstlicher Schulprovider. Er erzeugt synthetische Daten für Demo und Tests; echte EduPage-Anmeldung, Sitzungen, Upstream-2FA/Captcha und Abfrage-/Schreiboperationen sind nicht implementiert. Daher ist dieser Stack noch keine produktive Datenquelle und die Python-Implementierung bleibt die Referenz. Siehe [Migrationsstatus](MIGRATION.md). Der macOS-Client speichert das aktive Token aktuell lokal im Application-Support-Verzeichnis mit Nur-Besitzer-Rechten; iOS verwendet aktuell UserDefaults und ist zurückgestellt.
