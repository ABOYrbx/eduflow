package de.eduflow.android.ui.theme

import androidx.compose.material3.Typography
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp

// Redesign-PNG (Paket 0): Systemschrift, fette Titel, Kapitälchen-Labels.
// (res/font/inter.ttf bleibt als Reserve liegen, wird nicht verwendet.)

private fun TextStyle.withInter(
    weight: FontWeight? = null,
    size: Int? = null,
    letterSpacingEm: Float? = null,
): TextStyle {
    var out = copy(fontFamily = FontFamily.Default)
    if (weight != null) out = out.copy(fontWeight = weight)
    if (size != null) {
        out = out.copy(fontSize = size.sp)
        if (letterSpacingEm != null) out = out.copy(letterSpacing = (size * letterSpacingEm).sp)
    } else if (letterSpacingEm != null) {
        out = out.copy(letterSpacing = (out.fontSize.value * letterSpacingEm).sp)
    }
    return out
}

// Typografie im Web-Stil: Inter überall, fette enge Headlines
// (letter-spacing negativ wie .page-head h1, .msg h3, .tag).
// Lauftext 15sp wie .text.
val EduFlowTypography = Typography(
    displayLarge = Typography().displayLarge.withInter(FontWeight.ExtraBold, 52, -0.035f),
    displayMedium = Typography().displayMedium.withInter(FontWeight.ExtraBold, 44, -0.04f),
    displaySmall = Typography().displaySmall.withInter(FontWeight.ExtraBold, 34, -0.05f),
    headlineLarge = Typography().headlineLarge.withInter(FontWeight.ExtraBold, 30, -0.04f),
    headlineMedium = Typography().headlineMedium.withInter(FontWeight.ExtraBold, 24, -0.03f),
    headlineSmall = Typography().headlineSmall.withInter(FontWeight.ExtraBold, 20, -0.025f),
    titleLarge = Typography().titleLarge.withInter(FontWeight.ExtraBold, 19, -0.02f),
    titleMedium = Typography().titleMedium.withInter(FontWeight.SemiBold, 17, -0.018f),
    titleSmall = Typography().titleSmall.withInter(FontWeight.Bold, 15, -0.01f),
    bodyLarge = Typography().bodyLarge.withInter(null, 16),
    bodyMedium = Typography().bodyMedium.withInter(null, 15),
    bodySmall = Typography().bodySmall.withInter(null, 13),
    labelLarge = Typography().labelLarge.withInter(FontWeight.SemiBold, 14),
    labelMedium = Typography().labelMedium.withInter(FontWeight.SemiBold, 12),
    labelSmall = Typography().labelSmall.withInter(FontWeight.Bold, 11),
)
