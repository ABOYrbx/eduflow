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

    /** Übersetzungsstand (statisch, per Skript aus Crowdin-Splits berechnet). */
    data class LocaleCoverage(val code: String, val translated: Int, val total: Int) {
        val percent: Int get() = if (total <= 0) 100 else (translated * 100 / total).coerceIn(0, 100)
    }

    private val coverage = mapOf(
        "de" to LocaleCoverage("de", 300, 300),
        "en" to LocaleCoverage("en", 300, 300),
    )
    private const val fallbackTotal = 300

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
