# Lokale Entwicklung, Konfiguration und Tests

## Sicherheitsregeln zuerst

Die [Projektregeln in `AGENTS.md`](../AGENTS.md) sind verbindlich. Lokale Secrets, Login-Daten, API-Token und Inhalte in `.cache/` oder anderen Cache-/Login-Dateien niemals lesen, loggen, in Tests einchecken, Screenshots aufnehmen oder committen. Vorlagen wie `.env.example` sind Beispiele; echte `.env`-Dateien bleiben lokal. Keine echten EduPage-Konten für Tests verwenden.

EduFlow ist ein **lokales Entwicklungswerkzeug**. Flask und die TypeScript-Demo binden standardmäßig an Loopback-Adressen. Diese Server nicht öffentlich freigeben und nicht als Produktionsdienst betreiben.

## Python-Anwendung (EduPage-Referenz)

Im Repository-Stamm:

```bash
pip install -r requirements.txt
python3 app.py
```

Die Flask-App lauscht standardmäßig auf `http://127.0.0.1:8000`; ein anderer Port lässt sich über `PORT` setzen. Port 5000 wird wegen möglicher macOS-Belegung gemieden. Python-Pakete: Flask, `edupage-api`, cryptography, requests und pypdf; siehe `requirements.txt`.

Wetter ist optional. Für Live-Wetter den Schlüssel `OPENWEATHER_KEY` in einer lokalen `.env` konfigurieren. Optional: `WEATHER_LAT` und `WEATHER_LON` oder alternativ `WEATHER_CITY`. Ohne Schlüssel ist der Rest der Python-App weiter nutzbar; die Wetterkarte meldet „nicht verfügbar“. Den Schlüssel nie in Quellcode, Dokumentation oder Tests aufnehmen.

### Python-Version

`AGENTS.md` und die Backend-Pläne setzen Python 3.9 als Mindestversion. Die in `app.py` verwendete Annotation `Exception | None` steht auf einer lokalen Variablen innerhalb einer Funktion und wird nicht zur Laufzeit ausgewertet; sie stellt daher für sich genommen keinen Python-3.9-Laufzeitkonflikt dar. Bei Änderungen an der Mindestversion sind auch Quellcode und Abhängigkeiten auf Kompatibilität zu prüfen.

## TypeScript-Demo (Migration)

Die Migration benötigt Node.js 20.9+ und npm. `package-lock.json` und npm-Workspaces sind vorhanden. Der empfohlene Setup-Assistent ist interaktiv:

```bash
./install.sh
./run.sh
```

Der Installer fragt nach PostgreSQL oder richtet eine lokale Datenbank ein, erstellt bei Bedarf eine lokale API-Konfiguration mit restriktiven Dateirechten, installiert npm-Abhängigkeiten, generiert Prisma Client und spielt versionierte Migrationen ein. Auf unterstützten Systemen (macOS/Homebrew oder Debian/Ubuntu/apt) kann die automatische PostgreSQL-Einrichtung Systempakete und Dienste installieren. Nur bewusst starten und die Fragen prüfen. `./install.sh -debug` zeigt detailliertere Setup-Ausgaben.

`./run.sh` startet die TypeScript-NestJS-API **explizit mit Fake-Provider** auf Port 8101 und danach die Next.js-Weboberfläche, normalerweise Port 3000. Next.js wählt bei belegtem Port automatisch einen Folgeport. Demo-Login: `demo` / `demo`; der separate 2FA-Pfad nutzt `demo-2fa` / `demo`, Code `123456`. Das sind synthetische Demo-Zugänge, keine EduPage-Konten.

Weitere Befehle im Repository-Stamm:

```bash
npm run typecheck
npm test
npm run build
```

- `typecheck`: TypeScript-Prüfung der API, Web-App und Verträge.
- `test`: Jest-Tests der API und Node-Testläufe der Contracts. Der Contracts-Test läuft auf `packages/contracts/dist/*.test.js`; bei einem sauberen Checkout zunächst `npm run build --workspace @eduflow/contracts` oder `npm run build` ausführen, falls die kompilierten Dateien fehlen.
- `build`: Contracts, NestJS und Next.js bauen.
- `npm run dev:api`: NestJS im Watch-Modus; API-Standardport 8001, sofern `PORT` nicht gesetzt ist.
- `npm run dev:web`: Next.js-Entwicklungsserver.
- `npm run db:generate`, `npm run db:migrate`, `npm run db:deploy`: Prisma Client erzeugen bzw. Datenbankmigrationen verwalten. Diese Befehle verändern eine Datenbank; nur in einer bewusst lokalen Entwicklungsumgebung ausführen.

Das Setup benötigt PostgreSQL-Konfiguration unter `apps/api/.env.local` oder `apps/api/.env` (ignoriert). Keine bestehenden lokalen Konfigurationen überschreiben. Die Fake-API braucht die Datenbank für die Authentifizierung und lokale Zustände. Die erwarteten Variablen umfassen:

| Variable | Verwendung |
| --- | --- |
| `DATABASE_URL` | Verbindung zur lokalen PostgreSQL-Datenbank. |
| `PORT` | API-Port: standardmäßig 8001, im `run.sh`-Demo-Start 8101. |
| `JWT_ACCESS_SECRET` | Geheimer Schlüssel zum Signieren der Demo-JWTs; mindestens 32 Byte. |
| `CREDENTIAL_ENCRYPTION_KEY` | Separater 32-Byte-Schlüssel (64 Hex-Zeichen) für die geplante Credential-Vault-Verschlüsselung; ein echter EduPage-Credential-Flow ist noch nicht implementiert. |
| `EDUFLOW_PROVIDER` | Für den Fake-Schulprovider muss der Wert explizit `fake` sein. |
| `API_SERVER_URL` | NestJS-Ursprung für die Next.js-Serverrouten; deren Fallback ist `http://127.0.0.1:8001`. |

**Bekannte Demo-Konfigurationsabweichung:** `run.sh` startet die API auf Port 8101, während die Next.js-API-Routen ohne gesetztes `API_SERVER_URL` auf Port 8001 zeigen. Das Skript setzt `API_SERVER_URL` derzeit nicht explizit für den Web-Prozess. Bei einer Standardinstallation kann der Browser-Webclient deshalb die gestartete Demo-API verfehlen; für einen verlässlichen Web-Demoaufruf muss die Zieladresse auf `http://127.0.0.1:8101` gesetzt oder der Startpfad korrigiert werden. Dies ist eine Codeprüfung, keine Aussage über einen hier ausgeführten Browser-Ende-zu-Ende-Test.

## Tests und Builds

### Python

Die Tests sind eigenständige Offline-Skripte, kein gemeinsamer pytest-Einstieg. Einzelne Dateien direkt aus dem Stamm starten, zum Beispiel:

```bash
python3 tests/test_api_e2e.py
python3 tests/test_api_hardening.py
python3 tests/test_web_csrf.py
python3 tests/test_api_messages.py
python3 tests/test_api_homework.py
python3 tests/test_api_timetable.py
python3 tests/test_api_grades.py
python3 tests/test_api_meta.py
python3 tests/test_api_settings.py
```

`test_api_e2e.py` ist der zentrale Web-/API-Paritätstest; `test_api_hardening.py` prüft unter anderem Auth-Härtung und Rate-Limit; `test_web_csrf.py` prüft den Schutz der Web-Schreibaktionen. Weitere gezielte Suiten sind `test_api_auth.py`, `test_api_core.py` und `test_web_api_token.py`. Tests faken den EduPage-Login und arbeiten mit synthetischen Fixtures. Manche Tests erzeugen vorübergehend lokalen Cache-/Token-Testzustand; Testcode soll unmodifiziert bleiben und echte Geheimnisse dürfen nie in Testdaten gelangen.

### Android, macOS, iOS

- Android-Projekt: `android/`; geplanter Offline-Lauf ist `:app:assembleDebug` und `:app:testDebugUnitTest`. Im Checkout ist kein startfähiger Gradle-Wrapper (`gradlew`/Wrapper-JAR) vorhanden; Gradle und Android-SDK müssen lokal eingerichtet sein. Bereichspläne nennen Gradle 8.7 und 59 Unit-Tests.
- macOS: `xcodebuild -project mac/EduFlow.xcodeproj -scheme EduFlow -destination 'platform=macOS' test`. URL-Protocol-Stubs halten Tests offline. Die Dokumentationsdateien nennen widersprüchlich 52 beziehungsweise 53 Tests; Anzahl beim aktuellen Testlauf ermitteln.
- iOS: Projekt und Tests sind vorhanden, Arbeiten daran sind aber laut `AGENTS.md` zurückgestellt. Nur auf ausdrücklichen Auftrag bauen/ändern.

### TypeScript

Die Monorepo-Kommandos aus `package.json` sind maßgeblich. API-Tests sind Jest-Tests mit Fake-/Prisma-Stubs; im Repository ist keine vollständige Browser-E2E-Matrix eingerichtet. Der in `migration/README.md` beschriebene Zustand weist darauf hin, dass native UI-Flows gegen den neuen NestJS-Server nicht durch die vorhandenen Offline-Tests bewiesen sind.

## Wichtige Konfigurationsvariablen (Python)

Standardwerte folgen dem Code; nur Werte ändern, wenn das Verhalten gezielt getunt werden soll.

| Variable | Standard / Wirkung |
| --- | --- |
| `PORT` | `8000`; lokaler Flask-Port. |
| `OPENWEATHER_KEY` | Kein Standard-Key; schaltet Live-Wetter und Ortssuche frei. |
| `WEATHER_LAT`, `WEATHER_LON`, `WEATHER_CITY` | Optionale Standard-Ortswahl fürs Wetter. |
| `ESSEN_BASE_URL` | `https://www.sws-schulen.de`; Quelle für Mensa-PDFs. |
| `EDUFLOW_ESSEN_TTL` | `21600` Sekunden (6 Stunden). |
| `EDUFLOW_TIMELINE_TTL` | `900` Sekunden; Frische der Timeline. |
| `EDUFLOW_TIMELINE_WINDOW_DAYS` | `60`; inkrementelles Timeline-Refreshfenster. |
| `EDUFLOW_BG_REFRESH` | Standard aktiviert; stale-while-revalidate für Timeline. |
| `EDUFLOW_SESSION_TTL` | `1800` Sekunden; Wiederverwendung der EduPage-Sitzung, `0` deaktiviert. |
| `EDUFLOW_GRADES_TTL`, `EDUFLOW_LIKES_TTL` | Je `3600` Sekunden. |
| `EDUFLOW_TT_TTL_PAST` | `604800` Sekunden; Stundenplan vergangener Tage. |
| `EDUFLOW_TT_TTL_TODAY` | `600` Sekunden; heutiger Stundenplan. |
| `EDUFLOW_TT_TTL_FUTURE` | `3600` Sekunden; zukünftige Stundenpläne. |
| `EDUFLOW_API_TOKEN_DAYS` | `30` Tage. |
| `EDUFLOW_PENDING_TTL` | `600` Sekunden; 2FA-Zwischenanmeldung. |
| `EDUFLOW_DL_TTL` | `300` Sekunden; Download-Token. |
| `EDUFLOW_LOGIN_LIMIT`, `EDUFLOW_LOGIN_WINDOW` | `20` Versuche in `600` Sekunden. |
| `EDUFLOW_TRUST_PROXY` | Standard aus. Nur hinter einem vertrauenswürdigen Proxy aktivieren, der Forwarded-Header korrekt bereinigt. |
| `FLASK_SECRET_KEY`, `EDUFLOW_KEY` | Optionale geheime Schlüsselüberschreibungen; Werte geheim halten. |

Andere Variablen und ihre konkreten Nutzungspunkte stehen bei Bedarf in `app.py`, `api/` und `cache.py`. `.env`, API-Token-Dateien und `.cache/` nicht lesen oder dokumentieren.

## Häufige lokale Ursachen für Fehler

- **Android-Emulator erreicht Python-Server nicht:** Client-Default nutzt `10.0.2.2`; `localhost` im Emulator ist nicht der Host-Mac. Ein echtes Gerät braucht eine vom Gerät erreichbare Serveradresse.
- **Wetter fehlt:** `OPENWEATHER_KEY` nicht gesetzt oder Upstream nicht erreichbar. Andere Bereiche sollten davon unabhängig bleiben.
- **Mensa-Plan fehlt:** PDF-Quelle/Netzwerk nicht erreichbar; ein vorhandener Wochen-Cache kann als Rückfall dienen.
- **TypeScript-API startet nicht:** PostgreSQL, lokale API-Konfiguration, Prisma Client oder Port prüfen. Fake-Provider erfordert `EDUFLOW_PROVIDER=fake`.
- **TypeScript-Demo liefert keine EduPage-Daten:** Erwartetes Verhalten: es ist ausdrücklich ein Fake-Provider; echter Provider fehlt.
- **Test hängt von echtem Konto ab:** Test abbrechen und durch Offline-Fake/Fixture ersetzen; echte Zugangsdaten sind in Tests nicht zulässig.
