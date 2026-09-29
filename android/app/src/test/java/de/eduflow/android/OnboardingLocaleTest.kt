package de.eduflow.android

import de.eduflow.android.ui.auth.AppLocale
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

    @Test
    fun coverage_defaultsUnknownToZero() {
        val unknown = AppLocale.coverageFor("xx")
        assertEquals(0, unknown.percent)
        assertEquals("xx", unknown.code)
        assertEquals(100, AppLocale.coverageFor("de").percent)
        assertEquals(100, AppLocale.coverageFor("en").percent)
    }
}
