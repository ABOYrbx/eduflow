# JSON-API `/api/v1`

Diese Seite beschreibt den **Python-Referenzvertrag** aus `api/`. Er ist die bestehende Schnittstelle für Android und macOS. Die TypeScript-Migration hat noch Abweichungen; sie wird in [MIGRATION.md](MIGRATION.md) beschrieben.

## Allgemeine Regeln

- Präfix: `/api/v1`; JSON über Flask-Blueprint `api_v1`, zentral einmal in `app.py` registriert.
- Für alle geschützten Ressourcen ist ein Bearer-Token erforderlich: `Authorization: Bearer <token>`. Keine Web-Cookie-Authentifizierung in der API.
- Kein Token ist erforderlich für `GET /health`, `GET /openapi.json`, `POST /auth/login` und `POST /auth/2fa`.
- Erfolgreiche Listen verwenden `{items, total, limit, offset}`; Standardlimit 50, Maximum 200, Offset ab 0. Hausaufgaben/Noten ergänzen Cache-/Zählerfelder; die Agenda hat ihre eigene Bereichshülle.
- Fehler haben immer `{error, code}`. Das kanonische Fehler-Vokabular ist in `api/core.py` definiert.
- Datumsparameter sind `YYYY-MM-DD`; erfolgreiche Ressourcendaten folgen den vorhandenen Web-Dicts.
- Der vollständige, aber bewusst knappe Vertrag ist unter `GET /api/v1/openapi.json` abrufbar. Die Implementierung und die API-Tests bleiben für Detailfelder maßgeblich.

## Routen

### System und Anmeldung

| Methode und Pfad | Auth | Zweck / Eingaben |
| --- | --- | --- |
| `GET /health` | Nein | Liveness: `{status: "ok", version: "v1"}`. |
| `GET /openapi.json` | Nein | Minimale OpenAPI-3.0-Spezifikation. |
| `POST /auth/login` | Nein | JSON `{username, password, subdomain?, device?}`. Antwort entweder `status: "ok"` mit Token und Kontodaten oder `status: "2fa_required"` mit `pending_token`. |
| `POST /auth/2fa` | Nein | JSON `{pending_token, code}`; tauscht eine gültige Zwischenanmeldung gegen normales Token. |
| `POST /auth/logout` | Bearer | Widerruft genau das verwendete Token. |
| `POST /auth/refresh` | Bearer | Prüft die gespeicherten EduPage-Zugangsdaten erneut, gibt ein rotiertes Token zurück und widerruft das alte. |
| `GET /me` | Bearer | Subdomain und Benutzername des Token-Inhabers. |
| `GET /devices` | Bearer | Eigene Tokens/Geräte ohne Passwort oder Token-Klartext. |
| `DELETE /devices/{token_hash}` | Bearer | Widerruft ein eigenes Gerät anhand des Datensatz-Hashes; fremde Hashes werden nicht gelöscht. |

### Nachrichten und Anhänge

| Methode und Pfad | Auth | Zweck / Eingaben |
| --- | --- | --- |
| `GET /messages` | Bearer | Nachrichtenliste. `since` (Standard `2000-01-01`), `type`, `q` (alle Suchwörter), `limit`, `offset`, `refresh=1`; zeigt Top-Level-Einträge. |
| `GET /messages/{event_id}/thread` | Bearer | Likes, Antworten, Antwort-IDs, Zusammenfassung; optional `refresh=1`. |
| `POST /messages/read` | Bearer | Markiert aktuelle Nachrichtentypen im lokalen Gelesen-Status; Antwort `{marked}`. |
| `GET /recipients` | Bearer | Lehrer und Mitschüler, sortiert nach Namen; `limit`, `offset`. |
| `POST /messages/send` | Bearer | JSON `{recipients: [id, ...], body}`; Empfänger und Text werden geprüft, Text wird auf 5000 Zeichen begrenzt. |
| `POST /messages/{event_id}/reply` | Bearer | JSON `{body}`; antwortet an den Thread. |
| `POST /messages/download-token` | Bearer | JSON `{event_id, idx}`; erstellt kurzlebiges, dateigebundenes Token. |
| `GET /messages/{event_id}/attachments/{idx}` | Bearer oder Download-Token | Lädt einen erlaubten EduPage-Anhang als Proxy. `?dl=` ist für Apps bevorzugt; `?token=` bleibt als Kompatibilität verfügbar. |

### Hausaufgaben

| Methode und Pfad | Auth | Zweck / Eingaben |
| --- | --- | --- |
| `GET /homework` | Bearer | `since` (Standard `2000-01-01`), `status`, `include_tests`, `q`, `limit`, `offset`, `refresh=1`; liefert zusätzlich Zähler und `cache_info`. |
| `POST /homework/{event_id}/done` | Bearer | JSON `{done: true/false}`; setzt das EduPage-Done-Flag und aktualisiert den Cache. |
| `POST /homework/{event_id}/trash` | Bearer | JSON `{hide: true/false}`; `trash` ist Alias. Nur lokaler Papierkorb; Wiederherstellen einer Hausaufgabe markiert sie als offen. |

Erlaubte `status`-Werte: `alle`, `offen`, `überfällig`, `erledigt`, `papierkorb`. Zähler heißen `offen`, `ueberfaellig`, `erledigt`, `papierkorb`.

### Stundenplan und Schulalltag

| Methode und Pfad | Auth | Zweck / Eingaben |
| --- | --- | --- |
| `GET /timetable/day` | Bearer | Tagesplan mit `day` (Standard heute), `refresh=1`, Stunden und Navigationstagen. |
| `GET /timetable/week` | Bearer | Montag-bis-Freitag-Woche für `day`; liefert je Tag denselben Stundenobjekttyp. |
| `GET /substitutions/week` | Bearer | Vertretungsänderungen Montag bis Freitag für die Woche von `day` (Standard heute). |
| `GET /school/agenda` | Bearer | Schulereignisse, Prüfungen und Anwesenheitsereignisse; `since`, `until`, `refresh=1`. Standard: 30 Tage zurück bis 60 Tage voraus; Zeitraum höchstens 366 Tage. Antwort `{items, total, since, until, cache_info}`. |

### Noten, Essen, Wetter und Einstellungen

| Methode und Pfad | Auth | Zweck / Eingaben |
| --- | --- | --- |
| `GET /grades` | Bearer | Notenliste mit `limit`, `offset`, `refresh=1`, `cache_info`. |
| `GET /essen` | Bearer | Aktueller Mensa-Wochenplan; `refresh=1` umgeht den Cache. |
| `GET /wetter` | Bearer | Wetter per `city` oder per Paar `lat` + `lon`; ohne Ort `VALIDATION`. |
| `GET /wetter/suche` | Bearer | Ortssuche mit `q`; unter zwei Zeichen leere Ergebnisliste. |
| `GET /settings` | Bearer | Gemeinsames Schema und gespeicherte Werte. |
| `PUT /settings` | Bearer | Account-Einstellungen validiert gegen dasselbe Schema wie das Web; JSON-Booleans verwenden. |
| `POST /cache-clear` | Bearer | Löscht Cache-Dateien des Accounts und Mensa-Wochen-Caches; Einstellungen bleiben erhalten. |

## Standardantworten und Fehler

| Code | HTTP | Bedeutung |
| --- | ---: | --- |
| `VALIDATION` | 400 | Fehlendes JSON, ungültiger Parameter, Datum oder Listenlimit. |
| `TOKEN_INVALID` | 401 | Fehlendes, unbekanntes oder widerrufenes Token. |
| `TOKEN_EXPIRED` | 401 | Bekanntes, abgelaufenes Token. |
| `PENDING_INVALID` | 401 | Unbekannte oder abgelaufene 2FA-Zwischenanmeldung. |
| `INVALID_CODE` | 401 | 2FA-Code wurde abgelehnt. |
| `BAD_CREDENTIALS` | 401 | EduPage-Zugangsdaten sind falsch oder nicht mehr gültig. |
| `EDUPAGE_2FA` | 401 | EduPage verlangt beim Re-Login erneut 2FA; frisch anmelden. |
| `CAPTCHA_REQUIRED` | 403 | EduPage verlangt ein Captcha; Anmeldung einmal im Browser lösen. |
| `NOT_FOUND` | 404 | Nachricht, Aufgabe, Gerät oder Datei nicht gefunden. |
| `RATE_LIMITED` | 429 | Zu viele Authentifizierungsversuche. |
| `CONFIG_MISSING` | 503 | Erforderliche Serverkonfiguration fehlt, beispielsweise Wetter-Key. |
| `UPSTREAM` | 502 | EduPage-, Datei-, Wetter- oder Netzwerkfehler. |

## Download-Sicherheit

Native Downloader unterstützen nicht immer einen Authorization-Header. Daher kann der Client zuerst `POST /messages/download-token` aufrufen und anschließend die Download-Route mit `?dl=<kurzlebiger-wert>` verwenden. Dieser Wert ist an ein Konto und genau eine Event-/Datei-Kombination gebunden und standardmäßig fünf Minuten gültig. Der langlebige `?token=`-Mechanismus ist nur für Kompatibilität; Token in URLs können in Logs oder Browserhistorien geraten.

Downloads sind auf Hosts unter `*.edupage.org` beschränkt und laufen über die eingeloggte EduPage-Sitzung. Datei-Uploads sind nicht vorgesehen.

## Python und TypeScript nicht vermischen

Die Python-API ist Referenz. In der TypeScript-Migration gibt es aktuell unter anderem `POST /devices` (neues Gerätetoken), getrennte Zugangs- und Refresh-Tokens sowie andere Refresh-Details. Diese Erweiterungen bzw. Abweichungen sind noch kein Beleg für API-Parität; vor nativen Clientwechseln muss der Vertrag vereinheitlicht und getestet werden.
