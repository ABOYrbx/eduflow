package de.eduflow.android.ui.auth

import android.content.Context
import android.content.res.Configuration
import androidx.annotation.StringRes
import de.eduflow.android.R
import java.util.Locale
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

/**
 * App-Sprache als Override der Systemsprache.
 *
 * DataStore scheidet aus (async; attachBaseContext braucht synchronen
 * Zugriff) — daher wie NotifyPrefs eigene SharedPreferences. Die Wahl wird
 * zusätzlich in einem [StateFlow] gehalten, damit die Umschaltung sofort
 * wirkt: [MainActivity] liefert daraus Context und Configuration an die
 * Composables, ein Activity-Neustart ist nicht mehr nötig. `null` heißt
 * Systemsprache. Sprachen und Begrüßungen kommen zur Laufzeit aus den
 * installierten Katalogen — neue Crowdin-Sprachen erscheinen automatisch,
 * ohne Code-Änderung.
 */
object AppLocale {
    private const val FILE = "eduflow_locale"
    private const val KEY = "app_locale"
    private val CODE = Regex("^[a-z]{2}$")

    private val selection = MutableStateFlow<String?>(null)
    private var loaded = false

    /**
     * Gespeicherte Wahl als Flow; liest beim ersten Zugriff einmalig aus den
     * SharedPreferences. Ohne diesen Lesezeitpunkt wäre der Flow im neuen
     * Prozess zunächst leer und die Sprache flackerte kurz.
     */
    fun selectionFlow(context: Context): StateFlow<String?> {
        if (!loaded) {
            loaded = true
            selection.value = prefs(context).getString(KEY, null)?.takeIf { it.matches(CODE) }
        }
        return selection
    }

    /** Gespeicherte Wahl, einmalig gelesen (`null` = Systemsprache). */
    fun current(context: Context): String? = selectionFlow(context).value

    /** Auswahl setzen — wirkt sofort, ohne die Activity neu zu erstellen. */
    fun set(context: Context, code: String?) {
        val normalized = code?.takeIf { it.matches(CODE) }
        prefs(context).edit().putString(KEY, normalized).apply()
        selection.value = normalized
    }

    private fun prefs(context: Context) =
        context.getSharedPreferences(FILE, Context.MODE_PRIVATE)

    /** Context mit gespeicherter Sprache (für MainActivity.attachBaseContext). */
    fun wrap(context: Context): Context = localized(context, current(context))

    /** Context in einer bestimmten Sprache; leer = unverändert. */
    fun localized(context: Context, code: String?): Context {
        if (code.isNullOrBlank()) return context
        val conf = Configuration(context.resources.configuration)
        conf.setLocale(Locale(code))
        return context.createConfigurationContext(conf)
    }

    /** Installierte Sprachen (Englisch immer dabei, System-Default inklusive). */
    fun availableLocales(context: Context): List<String> =
        availableFromAssets(context.assets.locales.toList())

    /** Roh-Asset-Sprachen auf 2-Buchstaben-Codes normalisieren (reine Logik). */
    fun availableFromAssets(locales: List<String>): List<String> {
        val normalized = locales.map { it.substringBefore("-r").lowercase() }
            .filter { it.matches(Regex("^[a-z]{2}$")) }
            .distinct()
            .sorted()
        // Englisch ist immer wählbar (Fallback-Katalog) — aber nur, wenn
        // überhaupt Splits installiert sind.
        return if (normalized.isEmpty()) emptyList()
        else (normalized + "en").distinct().sorted()
    }

    /** Eigenname der Sprache (`fr` → „français", Fallback: Code). */
    fun nativeName(code: String): String =
        Locale(code).getDisplayLanguage(Locale(code)).replaceFirstChar { it.uppercase() }

    /**
     * Systemsprache als 2-Buchstaben-Code, aber nur wenn wir sie auch
     * ausliefern. Sonst würde die Sprachauswahl einen Eintrag markieren, den
     * es gar nicht gibt.
     */
    fun systemCode(available: List<String>): String? =
        Locale.getDefault().language.takeIf { it in available }

    /**
     * Vorauswahl der Sprachliste: eine gespeicherte Wahl gewinnt, sonst die
     * erkannte Systemsprache. Damit entfällt der separate „System"-Eintrag —
     * der Systemsprache-Eintrag ist einfach schon markiert.
     */
    fun initialSelection(current: String?, system: String?): String? =
        current ?: system

    /**
     * Sprachliste für die Auswahl: Systemsprache zuerst, danach alphabetisch
     * nach Eigenname. Reine Logik, damit testbar.
     */
    fun orderedLanguages(available: List<String>, system: String?): List<String> =
        available.sortedWith(
            compareBy({ it != system }, { nativeName(it).lowercase() }),
        )

    /**
     * Filtert [candidates] nach Suchbegriff: der Eigenname zählt mit Präfix
     * („deut" findet Deutsch, „fran" findet Français), der Sprachcode bei
     * exakter Übereinstimmung. Kein reines Teilstring — sonst fände „de" auch
     * „Nederlands" und „Slovenščina"; Präfix ist für ein Suchfeld das
     * erwartete Verhalten. Reine Logik.
     */
    fun filterLanguages(candidates: List<String>, query: String): List<String> {
        val needle = query.trim().lowercase()
        if (needle.isEmpty()) return candidates
        return candidates.filter { code ->
            nativeName(code).lowercase().startsWith(needle) ||
                code.equals(needle, ignoreCase = true)
        }
    }

    /**
     * Text einer Ressource in einer anderen Sprache (Fallback: aktuelle
     * Ressourcen, also die App-Sprache). Wird für die Begrüßung und den
     * Weiter-Knopf im Onboarding benutzt, damit beides dieselbe Sprache zeigt.
     */
    fun stringFor(code: String, @StringRes res: Int, context: Context): String {
        if (code.isBlank() || code == "en") {
            return context.getString(res)
        }
        return runCatching {
            val conf = Configuration(context.resources.configuration)
            conf.setLocale(Locale(code))
            context.createConfigurationContext(conf).getString(res)
        }.getOrDefault(context.getString(res))
    }

    /** Begrüßung in der Sprache (Fallback: aktuelle Ressourcen). */
    fun greetingFor(code: String, context: Context): String =
        stringFor(code, R.string.onboarding_greeting, context)

    /**
     * Sprachcode + Begrüßung als Paare. Sprachen mit identischem Text fallen
     * zusammen (der erste Code gewinnt) — sonst würde dieselbe Begrüßung
     * mehrfach im Zyklus erscheinen. Reine Logik, damit testbar.
     */
    fun greetingEntries(
        codes: List<String>,
        greetingOf: (String) -> String,
    ): List<Pair<String, String>> {
        val seen = mutableSetOf<String>()
        return codes.mapNotNull { code ->
            val text = greetingOf(code)
            if (text.isBlank() || !seen.add(text)) null else code to text
        }
    }

    /**
     * Übersetzungsstand je Sprache — wird per `tools/update_locale_coverage.py`
     * aus den Sprachdateien unter `res` erzeugt. Nach jedem Crowdin-Sync laufen:
     * `python3 tools/update_locale_coverage.py` (bzw. `--check` für CI).
     */
    data class LocaleCoverage(val code: String, val translated: Int, val total: Int) {
        val percent: Int get() = if (total <= 0) 100 else (translated * 100 / total).coerceIn(0, 100)
    }

    private val coverage = mapOf(
        "en" to LocaleCoverage("en", 322, 322),
        "af" to LocaleCoverage("af", 278, 322),
        "ar" to LocaleCoverage("ar", 125, 322),
        "ca" to LocaleCoverage("ca", 278, 322),
        "cs" to LocaleCoverage("cs", 288, 322),
        "da" to LocaleCoverage("da", 279, 322),
        "de" to LocaleCoverage("de", 294, 322),
        "el" to LocaleCoverage("el", 284, 322),
        "es" to LocaleCoverage("es", 291, 322),
        "fi" to LocaleCoverage("fi", 291, 322),
        "fr" to LocaleCoverage("fr", 280, 322),
        "hu" to LocaleCoverage("hu", 278, 322),
        "it" to LocaleCoverage("it", 275, 322),
        "iw" to LocaleCoverage("iw", 278, 322),
        "ja" to LocaleCoverage("ja", 283, 322),
        "ko" to LocaleCoverage("ko", 278, 322),
        "nl" to LocaleCoverage("nl", 277, 322),
        "no" to LocaleCoverage("no", 290, 322),
        "pl" to LocaleCoverage("pl", 287, 322),
        "pt" to LocaleCoverage("pt", 294, 322),
        "ro" to LocaleCoverage("ro", 287, 322),
        "ru" to LocaleCoverage("ru", 295, 322),
        "sr" to LocaleCoverage("sr", 278, 322),
        "sv" to LocaleCoverage("sv", 284, 322),
        "tr" to LocaleCoverage("tr", 278, 322),
        "uk" to LocaleCoverage("uk", 283, 322),
        "vi" to LocaleCoverage("vi", 278, 322),
        "zh" to LocaleCoverage("zh", 300, 322),
    )
    /** Nenner für Sprachen ohne Eintrag (entspricht dem Stand der Source). */
    private const val fallbackTotal = 316

    /** Sprachen mit gemessener Übersetzung (für Anzeige und Tests). */
    fun knownLocaleCodes(): Set<String> = coverage.keys

    fun coverageFor(code: String): LocaleCoverage =
        coverage[code] ?: LocaleCoverage(code, 0, fallbackTotal)

    /**
     * Zufallsreihenfolge ohne direkten Wiederholer am Rundenübergang
     * (reine Logik, für Hallo-Zyklus).
     */
    fun shuffledCycle(size: Int, notStartingAt: Int?): List<Int> {
        if (size <= 0) return emptyList()
        val order = (0 until size).shuffled()
        if (order.size > 1 && order[0] == notStartingAt) {
            return order.toMutableList().also { it[0] = it[1]; it[1] = order[0] }
        }
        return order
    }
}
