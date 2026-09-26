# Plattformen und Oberflächen

## Python-Weboberfläche (Referenz)

Die Flask-Oberfläche liegt in `app.py`, serverseitige HTML-Seiten unter `templates/`, Styling und Browserverhalten unter `static/`. Die aktuell sichtbaren HTML-Seiten sind Login, 2FA, Übersicht, Nachrichten-Dashboard, Verfassen, Hausaufgaben, Noten, Stundenplan, Einstellungen und Termine. Die Anzahl/Dateiliste ist bei Änderungen maßgeblich.

| Seite / Pfad | Inhalt |
| --- | --- |
| `/` | Login ohne Sitzung; nach Anmeldung konfigurierte Startseite oder Übersicht. |
| `/login`, `/2fa` | EduPage-Anmeldung und optionaler Zwei-Faktor-Abschluss. |
| `/overview` | Übersicht (wird auch direkt als Startseite gerendert); enthält Uhr, Plan, Nachrichten, Aufgaben, Wetter und Essen. |
| `/dashboard` | Timeline-/Nachrichten-Dashboard mit Filtern, Verlauf und Threads. |
| `/nachrichten/neu` | Empfängersuche und Verfassen. |
| `/hausaufgaben` (`/homework` als Alias) | Aufgaben, Filter, Tests, Done-Status und lokaler Papierkorb. |
| `/stundenplan` | Tag oder Woche. |
| `/noten` (`/grades` als Alias) | Halbjahre, Fächer, Gewichtung und Schnitt. |
| `/termine` | Termine, Prüfungen, Anwesenheit und Vertretungen. |
| `/einstellungen` | Account-Einstellungen und API-Tokenverwaltung. |

Weitere Webaktionen umfassen Antworten, Likes/Threads, Anhang-Proxy, Empfänger-JSON, Wetter-/Essens-JSON, Gelesen-Status und Cache-Leeren. Schreibende Web-Routen sind durch CSRF-Schutz und POST-Methoden geschützt.

`static/uber.css` ist das Web-Designsystem. `static/theme.js` steuert lokale Hell-/Dunkelwahl und Akzentfarbe; `static/profile-menu.js` das Profilmenü. Die Android-/iOS-Designs orientieren sich dagegen an der PNG-Referenz `templates/EduFlow · Weitere App Screens.png`; macOS verwendet bewusst den Web-Stil.

## TypeScript-Webclient (Migration)

`apps/web/` enthält eine provider-neutrale Next.js-/React-Oberfläche. Das Dashboard implementiert Übersicht, Nachrichten, Hausaufgaben, Noten, Stundenplan, Termine und Einstellungen. `/login` bietet den Anmeldeablauf. Inhalte werden über serverseitige Next-API-Routen an `apps/api` weitergereicht; Sitzungswerte liegen in HttpOnly-Cookies, nicht im Client-JavaScript.

Der dokumentierte Demo-Start läuft mit dem Fake-Provider (synthetische Daten für Demo-/UI-Prüfungen). Der Echtpfad mit echten EduPage-Daten ist implementiert (Parität N-A–NI), aber erst nach der Cutover-Abnahme freigegeben. Der Client ersetzt die Flask-Oberfläche erst nach Funktions- und API-Parität plus Umschaltung (N-J).

## Android

- **Technik:** Kotlin, Jetpack Compose/Material 3, Navigation Compose, Retrofit/OkHttp, Kotlin Serialization und DataStore.
- **Einstieg:** `android/app/src/main/java/de/eduflow/android/MainActivity.kt`; Navigation in `ui/navigation/NavGraph.kt` und `BottomBar.kt`.
- **Hauptnavigation:** fünf Tabs Home, Aufgaben, Nachrichten, Plan und Mehr. Mehr führt zu Noten, Einstellungen, Termine/Vertretungen, Geräte, Server-URL, Cache und Abmelden.
- **Bereiche:** Login/2FA, Übersicht, Nachrichten/Thread/Verfassen/Anhänge, Aufgaben/Status/Papierkorb, Stundenplan Tag/Woche, Noten und Schulalltag; zusätzlich API-gestützte Einstellungen und Wetter-/Essensmodule.
- **Netz:** ein Retrofit-`ApiService`, ein `ApiClient` und ein `TokenStore`. Bearer-Token werden zentral angehängt. JSON-Dekodierung ignoriert unbekannte Schlüssel. Downloads sollen Kurzzeit-`dl`-Tokens verwenden.
- **Sitzung/Design:** DataStore mit Korruptions-Handler speichert Sitzung, Server-URL und lokale Darstellung. Standard-API-URL ist `http://10.0.2.2:8000/api/v1/` für einen Android-Emulator; ein physisches Gerät benötigt eine erreichbare, vom Gerät aus gültige Serveradresse. Hell/Dunkel folgt standardmäßig dem System.
- **Tests/Build:** Offline-Unit-Tests mit Fake-`ApiService`; die Bereichspläne nennen 59 Android-Tests. Siehe [Entwicklung](ENTWICKLUNG.md) für den Build-Hinweis zum fehlenden Gradle-Wrapper.

Die Projektvorgabe hält `/api/v1` und das Daten-Interface stabil; Features bauen auf Repository/ViewModel/Screen pro Bereich. Neue Navigation soll nicht unabhängig vom zentralen `NavGraph` verdrahtet werden.

## macOS

- **Technik:** Swift 5, SwiftUI, URLSession/async-await; keine externen Abhängigkeiten vorgesehen.
- **Einstieg:** `mac/EduFlow/EduFlowApp.swift` und `ContentView.swift`; Kern in `Core/`, Ziele in `Navigation/Route.swift`.
- **Tatsächliche Navigation:** schwebende Pillen-Navigation oben (Web-Stil), nicht eine klassische Sidebar: Übersicht, Nachrichten, Aufgaben, Noten, Stundenplan und Schulalltag. Einstellungen und Geräte sind im Profilmenü/Sheet erreichbar.
- **Bereiche:** Onboarding/Login/2FA, Übersicht, Nachrichten/Threads/Verfassen, Aufgaben, Noten, Stundenplan, Schultermine/Vertretungen sowie Einstellungen und Geräteverwaltung.
- **Netz:** ein `APIClient`, ein `TokenStore`, tolerant konfigurierter JSON-Decoder und zentrale Fehlerbehandlung. Das aktive Token liegt in einer Datei unter Application Support; das Verzeichnis wird mit Modus 0700 und Token-Datei mit 0600 angelegt. Server-URL und angezeigte Kontodaten liegen in UserDefaults. Es wird bewusst nicht die Keychain genutzt, um wiederholte Schlüsselbunddialoge bei Ad-hoc-Signierung zu vermeiden.
- **Tests/Build:** Swift Testing mit URL-Protocol-Stubs. Die vorhandene Projektdokumentation weicht bei der Testzahl zwischen 52 und 53 ab; maßgeblich ist der aktuelle Lauf von `xcodebuild test`.

Der lokal laufende Python-Server wird auf demselben Mac typischerweise mit `http://127.0.0.1:8000/api/v1/` angesprochen.

## iOS (zurückgestellt)

Der iOS-Client ist im Repository unter `ios/` vorhanden und umfasst SwiftUI, Anmeldung/2FA, Übersicht, Nachrichten, Hausaufgaben, Noten, Stundenplan und Einstellungen. Er verwendet System-Frameworks, einen API-Client und speichert das aktive Token aktuell über UserDefaults (nicht in der Keychain). Die bestehenden Bereichspläne nennen 41 Offline-Tests.

**Laut `AGENTS.md` (repo-intern) ist iOS derzeit ausdrücklich zurückgestellt.** Ohne expliziten Auftrag keine neuen iOS-Funktionen oder Designangleichungen beginnen. Bestehende Abweichungen zur PNG-Designreferenz sind im repo-internen iOS-Plan `plaene/IOS.md` dokumentiert.

## Gemeinsame Client-Regeln

- Ein zentraler API-Client und Token-Speicher pro App; Ressourcenmodule duplizieren keine Authentifizierung.
- API-DTOs tolerieren unbekannte Felder und übernehmen Python-Response-Strukturen.
- Auf `TOKEN_INVALID`/`TOKEN_EXPIRED` zum Login zurückkehren; `EDUPAGE_2FA` erfordert erneute Anmeldung.
- Alle UI-Texte deutsch; keine Token, Passwörter, Stacktraces oder internen Pfade in UI/Logs.
- Native Tests verwenden Fakes/Stubs und benötigen keine echten Schulzugänge.
- Vor Änderungen den passenden repo-internen Android- (`plaene/ANDROID.md`) oder macOS-Plan (`plaene/MACOS.md`) beachten.
