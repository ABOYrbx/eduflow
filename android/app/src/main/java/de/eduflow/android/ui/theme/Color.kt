package de.eduflow.android.ui.theme

import androidx.compose.ui.graphics.Color

// EduFlow-Palette 1:1 aus static/uber.css (:root + [data-theme="dark"]).
// Light: weiße Fläche, Schwarz als einzige Markenfarbe.
val LightCanvas = Color(0xFFFFFFFF)
val LightSurface1 = Color(0xFFF6F6F6)
val LightSurface2 = Color(0xFFEEEEEE)
val LightInk = Color(0xFF000000)
val LightInkSoft = Color(0xFF1A1A1A)
val LightInkMuted = Color(0xFF6B6B6B)
val LightInkDim = Color(0xFF9E9E9E)
val LightBorder = Color(0xFFE2E2E2)
val LightBorderSoft = Color(0xFFEEEEEE)
val LightBorderStrong = Color(0xFFCFCFCF)

// Dark: schwarze Fläche, Weiß als Standard-Akzent.
val DarkCanvas = Color(0xFF000000)
val DarkSurface1 = Color(0xFF161616)
val DarkSurface2 = Color(0xFF262626)
val DarkInk = Color(0xFFFFFFFF)
val DarkInkSoft = Color(0xFFEDEDED)
val DarkInkMuted = Color(0xFFA3A3A3)
val DarkInkDim = Color(0xFF737373)
val DarkBorder = Color(0xFF262626)
val DarkBorderSoft = Color(0xFF1C1C1C)
val DarkBorderStrong = Color(0xFF525252)

// Karten-Hintergrund wie im Web (.card, .mail-detail, .auth-card).
val LightCard = Color(0xFFFFFFFF)
val DarkCard = Color(0xFF101010)

// 8 Akzentfarben wie im Web (templates/settings.html, theme.js data-accent).
// Schwarz = Standard (kein Attribut), Rest mit Hover-Ton aus uber.css.
data class AccentOption(
    val key: String,
    val color: Color,
    val label: String,
)

val Accents = listOf(
    AccentOption("black", Color(0xFF000000), "Black"),
    AccentOption("blue", Color(0xFF2563EB), "Blue"),
    AccentOption("violet", Color(0xFF7C3AED), "Lilac"),
    AccentOption("teal", Color(0xFF0E7490), "Teal"),
    AccentOption("green", Color(0xFF16A34A), "Green"),
    AccentOption("orange", Color(0xFFEA580C), "Orange"),
    AccentOption("red", Color(0xFFDC2626), "Red"),
    AccentOption("pink", Color(0xFFDB2777), "Pink"),
)

fun accentByKey(key: String): AccentOption =
    Accents.firstOrNull { it.key == key } ?: Accents.first()

/** Swatch im Menü: Schwarz wird im Dark Mode weiß (wie --accent im Web). */
fun AccentOption.swatchColor(dark: Boolean): Color =
    if (key == "black" && dark) Color.White else color

// Status-Farben wie im Web (.tag-red/.tag-amber/.tag-blue/.tag-green,
// .hw.st-*, Swipe-Aktionen).
val StatusRed = Color(0xFFDC2626)
val StatusAmber = Color(0xFFD97706)
val StatusBlue = Color(0xFF2563EB)
val StatusGreen = Color(0xFF16A34A)
val StatusGray = Color(0xFF6B6B6B)

// Noten-Chips wie im Web (.chip.g12/.g3/.g4/.g56/.gx).
val GradeGreen = Color(0xFF16A34A)
val GradeBlue = Color(0xFF2563EB)
val GradeAmber = Color(0xFFD97706)
val GradeRed = Color(0xFFDC2626)
val GradeGray = Color(0xFF6B6B6B)

// Text-Highlight wie im Web (.text mark).
val MarkLight = Color(0xFFFEF08A)
val MarkDarkBg = Color(0xFF854D0E)
val MarkDarkInk = Color(0xFFFEFCE8)

// Redesign-Tokens aus templates/EduFlow · Weitere App Screens.png
// (Paket 0). Light: grauer Canvas, weiße Karten. Dark: schwarz.
val RBgLight = Color(0xFFF4F4F5)
val RCardLight = Color(0xFFFFFFFF)
val RCardBorderLight = Color(0xFFE4E4E4)
val RInkLight = Color(0xFF111111)
val RMutedLight = Color(0xFF6E6E6E)
val RSecondaryLight = Color(0xFFECECEE)
val RBgDark = Color(0xFF000000)
val RCardDark = Color(0xFF161616)
val RCardBorderDark = Color(0xFF262626)
val RInkDark = Color(0xFFFFFFFF)
val RMutedDark = Color(0xFFA3A3A3)
val RSecondaryDark = Color(0xFF262626)

// Status-Dots aus dem PNG (Aufgaben-Liste).
val RDotOrange = Color(0xFFE8930C)
val RDotRed = Color(0xFFD92D20)
val RDotBlue = Color(0xFF2470E0)
