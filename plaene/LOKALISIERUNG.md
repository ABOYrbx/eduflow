# Lokalisierung (Crowdin) — Stand und Reihenfolge

Quelle für Design-/Plattformregeln: `AGENTS.md` (dort gelten weiterhin alle
Projektgrenzen). iOS ist ausgenommen (zurückgestellt).

## Stand: Englisch ist Source-Sprache und Fallback

Englisch ist überall Source-Sprache **und** Fallback. Alle nutzersichtbaren
UI-Strings liegen auf Englisch in den Quelldateien und erscheinen nach dem
nächsten Sync in Crowdin. Deutsch liegt als vollständige Übersetzung daneben
(`de.json`, `values-de/`, xcstrings-`de`). Die API-Fehler-`code`s werden nie
übersetzt — nur die `error`-Texte.

Alle Clients lesen Englisch als Standard: Web via `t()` (`src/lib/i18n.ts`,
Fallback `en`), Backend via `t()` (`src/i18n.ts`), Android via `values/`
(Fallback, Deutsch in `values-de/`), macOS via String-Katalog
(`sourceLanguage: en`). Ausgenommen bleiben nur die unten dokumentierten
Fälle (Protokoll-Strings/Status, Datumsformate, Demo-Daten) — diese bleiben
bewusst deutsch.

## Dateizuordnung (`crowdin.yml` im Root)

| Plattform | Quelle im Repo (englisch) | Übersetzung via Crowdin |
|---|---|---|
| Web (Next.js) | `apps/web/messages/en.json` (`t()` aus `src/lib/i18n.ts`) | `apps/web/messages/<locale>.json` |
| Backend (NestJS) | `apps/api/src/messages/en.json` (`t()` aus `src/i18n.ts`) | `apps/api/src/messages/<locale>.json` |
| Android | `android/app/src/main/res/values/strings.xml` (`stringResource`) | `res/values-<android_code>/strings.xml` |
| macOS | `mac/EduFlow/Resources/Localizable.xcstrings` (Source `en`, im Bundle registriert) | gleiche Datei (String Catalog) |

Kennzahlen: Web 296 Keys (13 Gruppen, inkl. `theme.language`), Backend
111 Keys (Fehlertexte, Settings-Schema, API-Docs), Android 288 Strings +
3 Plurals, macOS 338 Katalog-Keys (Source-Sprache `en`).

## Sync-Ablauf

- Quellen → Crowdin: automatisch, die GitHub-App syncet `main` laufend.
  (Die frühere Sync-Action ist entfernt, die App macht alles allein.)
- Übersetzungen → Repo: automatisch per Sync-Schedule der GitHub-App als PR
  (Review-Pflicht, kein Auto-Merge).
- `update_option: update_as_unapproved` erhält Übersetzungen bei kleinen
  Quelltext-Korrekturen (z. B. Tippfehler).
- Sync-Commits der App enthalten `[ci skip]` (Crowdin-Standard).
- Secrets: `CROWDIN_PROJECT_ID` + `CROWDIN_TOKEN` als GitHub-Secrets, nie im
  Repo, nie in `.env` committen.

## Was du manuell in Crowdin / GitHub tun musst

1. Crowdin-Projekt anlegen (privat, Source-Sprache Englisch). ✅ (erledigt)
2. Crowdin-GitHub-App für `ABOYrbx/eduflow` installieren (nur `main`,
   Service-Branch `l10n_main`, Sync-Schedule täglich). ✅ (erledigt)
3. In GitHub unter Settings → Secrets: `CROWDIN_PROJECT_ID` und
   `CROWDIN_TOKEN` (feingranular, nur das eine Projekt) anlegen. ⏳ (offen)
4. Erste Zielsprache freischalten, Sync in Actions prüfen, ersten
   Übersetzungs-PR reviewen und mergen.

## Bewusst ausgenommen (kein Übersetzungsbedarf)

- **Protokoll-Strings:** Hausaufgaben-Status (`überfällig`, `heute fällig`,
  …), Typ-Codes und `code`-Vokabular steuern Filter/Vergleiche in allen
  Clients — sie bleiben deutsch und stabil. Echte Mehrsprachigkeit braucht
  später Status-Codes als eigenes Feld (Follow-up, API-Änderung).
- **Datums-/Zeitformate** (`Mittwoch · 20:01`, `Woche …`, `day_label`):
  werden pro Locale formatiert (Follow-up: `Intl`), nicht übersetzt.
- **EduPage-Domain-Labels** (`TYPE_LABELS`, Monats-/Wochentagsnamen,
  `serializers.ts`): Daten-Mapping, kein UI-Text.
- **Demo-Inhalte** (Fake-Provider, `demo-data.ts`): simulierte Schul-Daten.
- **Wetterbeschreibungen** (`desc`): Fremddaten von OpenWeather.
- **Android-ViewModel-Fallbacks** (`ErrorMapper`, `*ViewModel`): brauchen
  Context; Tests laufen mit englischem Standardkatalog.
- **macOS-`value:`-Fallbacks:** identischer englischer Text, greift nur wenn
  der Katalog fehlt.

## Regeln für neue Strings (PR-Checkliste)

1. Neue UI-Strings gehören immer **auf Englisch** in die Quelldatei der Plattform
   (keine Hardcodings): Web → `messages/en.json`, Backend → `src/messages/en.json`,
   Android → `values/strings.xml`, macOS → `xcstrings` (+ `NSLocalizedString`
   bei dynamischen Stellen). Deutsche Übersetzung jeweils daneben pflegen
   (`de.json`, `values-de/`, xcstrings-`de`).
2. `code`-Vokabular und Status-/Typ-Werte stabil halten (siehe oben).
3. Web: Neue Crowdin-Sprache = Import + Eintrag in `apps/web/src/lib/locales.ts`
   ergänzen (sonst fällt `t()` auf Englisch zurück); Katalog-Änderungen brauchen
   einen Web-Rebuild (JSONs sind gebündelt). Neue UI-Strings brauchen nur
   `en.json` (+ `de.json`) — andere Kataloge fallen pro Key auf Englisch zurück.
   Der Übersetzungsstand (`src/lib/locale-coverage.generated.ts` für die
   Sprachauswahl auf der Login-Seite) erzeugt sich vor jedem Build neu
   (`npm run locales:stats`, siehe `prebuild` in `apps/web/package.json`).
4. Abnahmen: `npm test` + `npm run typecheck` (Root), Gradle
   `:app:assembleDebug :app:testDebugUnitTest`, `xcodebuild … test`.
