package de.eduflow.android.ui.auth

import android.app.Activity
import android.content.Context
import android.content.res.Configuration
import de.eduflow.android.R
import java.util.Locale

/**
 * App-Sprache als Override der Systemsprache.
 *
 * DataStore scheidet aus (async; attachBaseContext braucht synchronen
 * Zugriff) — daher wie NotifyPrefs eigene SharedPreferences. Auswahl per
 * [set]: speichern + Activity neu erstellen (Sandbox-sicher, ohne Neustart
 * der App). `null` heißt Systemsprache. Sprachen und Begrüßungen kommen zur
 * Laufzeit aus installierten Splits — neue Crowdin-Sprachen erscheinen
 * automatisch, ohne Code-Änderung.
 */
object AppLocale {
    private const val FILE = "eduflow_locale"
    private const val KEY = "app_locale"

    /** Gespeicherte Wahl (`null` = Systemsprache). */
    fun current(context: Context): String? =
        context.getSharedPreferences(FILE, Context.MODE_PRIVATE)
            .getString(KEY, null)?.takeIf { it.matches(Regex("^[a-z]{2}$")) }

    /** Context mit Override-Sprache (für MainActivity.attachBaseContext). */
    fun wrap(context: Context): Context {
        val code = current(context) ?: return context
        val conf = Configuration(context.resources.configuration)
        conf.setLocale(Locale(code))
        return context.createConfigurationContext(conf)
    }

    /** Speichern + Activity neu erstellen (Sprache greift sofort). */
    fun set(activity: Activity, code: String?) {
        val normalized = code?.takeIf { it.matches(Regex("^[a-z]{2}$")) }
        activity.getSharedPreferences(FILE, Context.MODE_PRIVATE).edit()
            .putString(KEY, normalized).apply()
        activity.recreate()
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

    /** Begrüßung in der Sprache (Fallback: aktuelle Ressourcen). */
    fun greetingFor(code: String, context: Context): String {
        if (code == "en") {
            return context.getString(R.string.onboarding_greeting)
        }
        return runCatching {
            val conf = Configuration(context.resources.configuration)
            conf.setLocale(Locale(code))
            context.createConfigurationContext(conf)
                .getString(R.string.onboarding_greeting)
        }.getOrDefault(context.getString(R.string.onboarding_greeting))
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
        "en" to LocaleCoverage("en", 316, 316),
        "af" to LocaleCoverage("af", 278, 316),
        "ar" to LocaleCoverage("ar", 125, 316),
        "ca" to LocaleCoverage("ca", 278, 316),
        "cs" to LocaleCoverage("cs", 288, 316),
        "da" to LocaleCoverage("da", 279, 316),
        "de" to LocaleCoverage("de", 289, 316),
        "el" to LocaleCoverage("el", 284, 316),
        "es" to LocaleCoverage("es", 291, 316),
        "fi" to LocaleCoverage("fi", 291, 316),
        "fr" to LocaleCoverage("fr", 280, 316),
        "hu" to LocaleCoverage("hu", 278, 316),
        "it" to LocaleCoverage("it", 275, 316),
        "iw" to LocaleCoverage("iw", 278, 316),
        "ja" to LocaleCoverage("ja", 283, 316),
        "ko" to LocaleCoverage("ko", 278, 316),
        "nl" to LocaleCoverage("nl", 277, 316),
        "no" to LocaleCoverage("no", 290, 316),
        "pl" to LocaleCoverage("pl", 287, 316),
        "pt" to LocaleCoverage("pt", 294, 316),
        "ro" to LocaleCoverage("ro", 287, 316),
        "ru" to LocaleCoverage("ru", 295, 316),
        "sr" to LocaleCoverage("sr", 278, 316),
        "sv" to LocaleCoverage("sv", 284, 316),
        "tr" to LocaleCoverage("tr", 278, 316),
        "uk" to LocaleCoverage("uk", 283, 316),
        "vi" to LocaleCoverage("vi", 278, 316),
        "zh" to LocaleCoverage("zh", 300, 316),
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
