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
        "en" to LocaleCoverage("en", 318, 318),
        "af" to LocaleCoverage("af", 278, 318),
        "ar" to LocaleCoverage("ar", 125, 318),
        "ca" to LocaleCoverage("ca", 278, 318),
        "cs" to LocaleCoverage("cs", 288, 318),
        "da" to LocaleCoverage("da", 279, 318),
        "de" to LocaleCoverage("de", 291, 318),
        "el" to LocaleCoverage("el", 284, 318),
        "es" to LocaleCoverage("es", 291, 318),
        "fi" to LocaleCoverage("fi", 291, 318),
        "fr" to LocaleCoverage("fr", 280, 318),
        "hu" to LocaleCoverage("hu", 278, 318),
        "it" to LocaleCoverage("it", 275, 318),
        "iw" to LocaleCoverage("iw", 278, 318),
        "ja" to LocaleCoverage("ja", 283, 318),
        "ko" to LocaleCoverage("ko", 278, 318),
        "nl" to LocaleCoverage("nl", 277, 318),
        "no" to LocaleCoverage("no", 290, 318),
        "pl" to LocaleCoverage("pl", 287, 318),
        "pt" to LocaleCoverage("pt", 294, 318),
        "ro" to LocaleCoverage("ro", 287, 318),
        "ru" to LocaleCoverage("ru", 295, 318),
        "sr" to LocaleCoverage("sr", 278, 318),
        "sv" to LocaleCoverage("sv", 284, 318),
        "tr" to LocaleCoverage("tr", 278, 318),
        "uk" to LocaleCoverage("uk", 283, 318),
        "vi" to LocaleCoverage("vi", 278, 318),
        "zh" to LocaleCoverage("zh", 300, 318),
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
