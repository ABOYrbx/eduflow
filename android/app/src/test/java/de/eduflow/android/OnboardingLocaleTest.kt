package de.eduflow.android

import de.eduflow.android.ui.auth.AppLocale
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Onboarding-Sprachauswahl + Hallo-Zyklus — reine Logik, offline
 * (kein Context, kein Main-Dispatcher).
 */
class OnboardingLocaleTest {

    @Test
    fun availableFromAssets_filtersAndSorts() {
        assertEquals(
            listOf("en", "fr"),
            AppLocale.availableFromAssets(listOf("en-rUS", "fr", "Base", "zh-Hans", "", "pt-BR")),
        )
        assertEquals(emptyList<String>(), AppLocale.availableFromAssets(emptyList()))
    }

    @Test
    fun shuffledCycle_coversAllWithoutImmediateRepeat() {
        assertEquals(emptyList<Int>(), AppLocale.shuffledCycle(0, null))
        assertEquals(listOf(0), AppLocale.shuffledCycle(1, 0))
        repeat(50) {
            val order = AppLocale.shuffledCycle(5, 2)
            assertEquals(listOf(0, 1, 2, 3, 4), order.sorted())
            assertTrue(order.first() != 2)
        }
    }

    /**
     * Pro Sprache darf es nur EINEN Katalog geben: Android gewinnt bei
     * `values-de-rDE` gegen `values-de`, weil der Sprachcode spezifischer ist.
     * Eine maschinelle `values-de-rDE` überschreibt dadurch das handgepflegte
     * Deutsch (sichtbar als „Zuhause" statt „Home", „DEUT" statt „DEMO").
     */
    @Test
    fun oneCatalogPerLanguage() {
        val res = resDir()
        val bare = mutableSetOf<String>()
        val variants = mutableMapOf<String, String>()
        res.listFiles { f: File -> f.isDirectory && f.name.startsWith("values-") }.orEmpty()
            .forEach { dir ->
                if (!File(dir, "strings.xml").isFile) return@forEach
                val qualifier = dir.name.removePrefix("values-")
                val base = qualifier.substringBefore('-')
                if (qualifier == base) bare += base else variants.putIfAbsent(base, qualifier)
            }
        assertEquals(
            "Regionale Varianten, die den Basis-Katalog verdecken: " +
                "${variants.filterKeys { it in bare }}",
            emptyMap<String, String>(),
            variants.filterKeys { it in bare },
        )
    }

    @Test
    fun coverage_defaultsUnknownToZero() {
        val unknown = AppLocale.coverageFor("xx")
        assertEquals(0, unknown.percent)
        assertEquals("xx", unknown.code)
        // Quellsprache ist immer vollständig.
        assertEquals(100, AppLocale.coverageFor("en").percent)
    }

    /**
     * Die Coverage-Tabelle in AppLocale.kt wird per
     * `python3 tools/update_locale_coverage.py` aus den Sprachdateien erzeugt.
     * Dieser Test verhindert, dass sie nach einem Crowdin-Sync veraltet bleibt
     * (sonst zeigt die Sprachauswahl wieder 0 % für fast alle Sprachen).
     */
    @Test
    fun coverage_matchesResourceFiles() {
        val res = resDir()
        val source = strings(File(res, "values/strings.xml"))

        // Je Sprache die Vereinigung aller Varianten (`de` + `de-rDE`): ein Key
        // zählt als übersetzt, sobald ihn mindestens eine Variante übersetzt hat.
        val translated = sortedMapOf<String, MutableSet<String>>()
        res.listFiles { f: File -> f.isDirectory && f.name.startsWith("values-") }.orEmpty()
            .forEach { dir ->
                val file = File(dir, "strings.xml")
                if (!file.isFile) return@forEach
                val code = dir.name.removePrefix("values-").substringBefore('-')
                if (code == "en") return@forEach
                val done = translated.getOrPut(code) { mutableSetOf() }
                strings(file).forEach { (name, text) ->
                    val original = source[name]
                    if (original != null && original != text) done += name
                }
            }

        val expected = sortedMapOf<String, Pair<Int, Int>>()
        expected["en"] = source.size to source.size
        translated.forEach { (code, done) -> expected[code] = done.size to source.size }

        // Jede installierte Sprache ist auch in der Tabelle bekannt.
        val known = AppLocale.knownLocaleCodes()
        assertEquals(
            "Sprachen ohne Coverage-Eintrag: ${expected.keys - known}",
            emptySet<String>(),
            expected.keys - known,
        )

        // Und die Prozentwerte stimmen mit den Dateien überein.
        expected.forEach { (code, translatedToTotal) ->
            val (translated, total) = translatedToTotal
            val actual = AppLocale.coverageFor(code)
            assertEquals("$code übersetzte Keys", translated, actual.translated)
            assertEquals("$code Gesamt", total, actual.total)
        }
    }

    private fun resDir(): File {
        var dir = File("").absoluteFile
        while (true) {
            val candidate = File(dir, "app/src/main/res")
            if (candidate.isDirectory) return candidate
            dir = dir.parentFile ?: error("res-Ordner nicht gefunden")
        }
    }

    /**
     * Liest `<string>`, `<string-array>` und `<plurals>` als Name -> Text.
     * Bei mehrteiligen Werten (plurals/arrays) werden die Teile mit Leerraum
     * verbunden — vergleichbar mit `itertext()` im Python-Generator.
     */
    private fun strings(file: File): Map<String, String> {
        val body = file.readText()
        val out = linkedMapOf<String, String>()
        fun collect(tag: String) =
            Regex("""<$tag name="([^"]+)"[^>]*>(.*?)</$tag>""", RegexOption.DOT_MATCHES_ALL)
                .findAll(body)
                .forEach { out[it.groupValues[1]] = normalize(innerText(it.groupValues[2])) }
        collect("string")
        collect("string-array")
        collect("plurals")
        return out
    }

    /** Innerer XML-Inhalt ohne Tags. */
    private fun innerText(fragment: String): String = TAG
        .replace(fragment, " ")
        .replace(Regex("""<item[^>]*/>"""), " ")

    /** Entities auflösen, Leerraum vereinheitlichen (wie im Python-Generator). */
    private fun normalize(text: String): String = text
        .replace("&lt;", "<").replace("&gt;", ">")
        .replace("&quot;", "\"").replace("&apos;", "'")
        .replace("&amp;", "&")
        .split(Regex("\\s+"))
        .joinToString(" ")
        .trim()

    private companion object {
        val TAG = Regex("""<[^>]*>""")
    }
}
