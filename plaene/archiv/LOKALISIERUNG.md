# Lokalisierung (Crowdin) — Stand und Reihenfolge

Quelle für Design-/Plattformregeln: `AGENTS.md` (dort gelten weiterhin alle
Projektgrenzen). iOS ist ausgenommen (zurückgestellt).

## Stand: Quellen befüllt, Crowdin kann übersetzen

Englisch ist überall Source-Sprache **und** Fallback; Deutsch ist normale
Zielsprache (Crowdin). Alle nutzersichtbaren UI-Strings liegen in
Quelldateien und erscheinen nach dem nächsten Sync in Crowdin. Der
macOS-Katalog hat Source-Sprache `en` (de/en je 100 %). Die
API-Fehler-`code`s werden nie übersetzt — nur die `error`-Texte.

Android- und macOS-UI sind vollständig auf die Quelldateien umgestellt
(keine Hardcodings mehr): Android nutzt `stringResource` aus
`values/strings.xml`, macOS `LocalizedStringKey` aus dem String-Katalog.
Ausgenommen bleiben nur die unten dokumentierten Fälle
(ViewModel-Fallbacks ohne Context, Protokoll-Strings/Status,
Datumsformate, Demo-Daten) — diese bleiben bewusst deutsch.

## Dateizuordnung (`crowdin.yml` im Root)

| Plattform | Quelle im Repo (deutsch) | Übersetzung via Crowdin |
|---|---|---|
| Web (Next.js) | `apps/web/messages/en.json` (`t()` aus `src/lib/i18n.ts`) | `apps/web/messages/<locale>.json` (inkl. `de.json`) |
| Backend (NestJS) | `apps/api/src/messages/en.json` (`t()` aus `src/i18n.ts`) | `apps/api/src/messages/<locale>.json` (inkl. `de.json`) |
| Android | `android/app/src/main/res/values/strings.xml` (Inhalt englisch, `stringResource`) | `res/values-<android_code>/strings.xml` (inkl. `values-de/`) |
| macOS | `mac/EduFlow/Resources/Localizable.xcstrings` (Source `en`, im Bundle registriert) | gleiche Datei (String Catalog) |

Kennzahlen (Blätter/Entries gezählt, Duplikate vereint): Web 249 Keys
(13 Gruppen), Backend 111 Keys (Fehlertexte, Settings-Schema, API-Docs),
Android 288 Strings + 3 Plurals, macOS 405 Katalog-Keys
(Source-Sprache `en`, de/en je 100 %). Status-/Typ-/Aktions-Codes bleiben bewusst deutsch,
siehe unten.

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

1. Crowdin-Projekt (privat): Source-Sprache in den Projekt-Settings auf
   Englisch umstellen (war Deutsch). ⏳ (offen — solange das nicht
   umgestellt ist, zeigt Crowdin deutsche Ausgangstexte)
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
  Context; Tests erzwingen Deutsch.
- **macOS-`value:`-Fallbacks:** identischer englischer Text (Source-Sprache),
  greift nur wenn der Katalog fehlt.

## Regeln für neue Strings (PR-Checkliste)

1. Neue UI-Strings gehören immer in die Quelldatei der Plattform
   (keine Hardcodings): Web → `messages/en.json`, Backend → `src/messages/en.json`,
   Android → `values/strings.xml`, macOS → `xcstrings` (+ `NSLocalizedString`
   bei dynamischen Stellen). Die deutschen Kataloge (`de.json`, `values-de/`)
   werden von Crowdin verwaltet — dort nicht von Hand editieren (wird beim
   Sync überschrieben).
2. `code`-Vokabular und Status-/Typ-Werte stabil halten (siehe oben).
3. Web: Neue Crowdin-Sprache = Import + Eintrag in `apps/web/src/lib/locales.ts`
   ergänzen (sonst fällt `t()` auf Englisch zurück); Katalog-Änderungen brauchen
   einen Web-Rebuild (JSONs sind gebündelt). Neue UI-Strings brauchen nur
   `en.json` — andere Kataloge fallen pro Key auf Englisch zurück.
4. macOS: Die Sprachauswahl im Onboarding (`OnboardingLanguagePage`,
   Override via `AppleLanguages` + Neustart, Logik in `AppLanguage`) zeigt
   den Stand aus `localeCoverage` in `OnboardingState.swift`. Bei neuen
   Sprachen/Keys dort neu berechnen:
   Nenner = Keys mit de-Wert ungleich en-Wert, Zähler = davon Keys mit
   eigenem Wert in der Sprache (die Quellsprache zählt als vollständig).
   Neue UI-Strings auf der Seite als englische Literale wie auf den
   Nachbarseiten; Katalog-Einträge (de+en) ergänzen.
5. Abnahmen: `npm test` + `npm run typecheck` (Root), Gradle
   `:app:assembleDebug :app:testDebugUnitTest`, `xcodebuild … test`.
