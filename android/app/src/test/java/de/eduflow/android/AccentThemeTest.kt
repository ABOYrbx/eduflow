package de.eduflow.android

import androidx.compose.ui.graphics.Color
import de.eduflow.android.ui.theme.contentOnAccent
import de.eduflow.android.ui.theme.effectiveAccent
import de.eduflow.android.ui.theme.mix
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Akzent-Theme (Theme.kt-Helfer): Standard bleibt PNG-treu, echte
 * Akzent-Wahl gilt in beiden Modi, Schrift per WCAG-Kontrast.
 */
class AccentThemeTest {

    @Test
    fun effectiveAccent_defaultStaysPng() {
        assertEquals(Color.Black, effectiveAccent(Color.Black, darkTheme = false))
        assertEquals(Color.White, effectiveAccent(Color.Black, darkTheme = true))
    }

    @Test
    fun effectiveAccent_customKeptBothModes() {
        val blue = Color(0xFF2563EB)
        assertEquals(blue, effectiveAccent(blue, darkTheme = false))
        assertEquals(blue, effectiveAccent(blue, darkTheme = true))
    }

    @Test
    fun contentOnAccent_wcagContrast() {
        assertEquals(Color.White, contentOnAccent(Color.Black))
        assertEquals(Color.Black, contentOnAccent(Color.White))
        // Gesättigte Akzente → weiße Schrift, helles Grün → schwarz.
        assertEquals(Color.White, contentOnAccent(Color(0xFF2563EB)))
        assertEquals(Color.White, contentOnAccent(Color(0xFFDC2626)))
        assertEquals(Color.Black, contentOnAccent(Color(0xFF16A34A)))
    }

    @Test
    fun mix_clampedAndOpaque() {
        val mid = Color.White.mix(Color.Black, 0.5f)
        assertEquals(0.5f, mid.red, 0.01f)
        assertEquals(1f, mid.alpha, 0f)
        assertEquals(Color.White, Color.White.mix(Color.Black, 0f))
        assertEquals(Color.Black, Color.White.mix(Color.Black, 1f))
    }
}
