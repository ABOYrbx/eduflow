package de.eduflow.android.ui.theme

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.view.View
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.snap
import androidx.compose.animation.core.tween
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.ColorScheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Shapes
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.unit.dp
import androidx.core.view.WindowCompat

// Geometrie aus dem Redesign-PNG: Karten 16dp, Chips/Tags vollrund.
val EduFlowShapes = Shapes(
    extraSmall = RoundedCornerShape(8.dp),
    small = CircleShape,
    medium = RoundedCornerShape(16.dp),
    large = RoundedCornerShape(16.dp),
    extraLarge = RoundedCornerShape(20.dp),
)

@Composable
fun EduFlowTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    accent: Color = Color.Black,
    content: @Composable () -> Unit,
) {
    val reduced = rememberReducedMotion()
    // Akzent global: "black" (Standard) bleibt PNG-schwarz/weiß, jede andere
    // Wahl färbt primary/secondary/tertiary + Container-Tönung. onPrimary etc.
    // per WCAG-Kontrast (Weiß/Schwarz), Container-Texte bleiben Tinte.
    val eff = effectiveAccent(accent, darkTheme)
    val onEff = contentOnAccent(eff)
    val surface = if (darkTheme) RCardDark else RCardLight
    val ink = if (darkTheme) RInkDark else RInkLight
    val tint = surface.mix(eff, 0.16f)
    val isDefault = eff == (if (darkTheme) Color.White else Color.Black)
    // Default exakt wie bisher (PNG), sonst Akzent-Variante.
    val light = lightColorScheme(
        primary = eff,
        onPrimary = onEff,
        primaryContainer = if (isDefault) RSecondaryLight else tint,
        onPrimaryContainer = RInkLight,
        secondary = if (isDefault) RMutedLight else eff,
        onSecondary = if (isDefault) RCardLight else onEff,
        secondaryContainer = if (isDefault) RSecondaryLight else tint,
        onSecondaryContainer = RInkLight,
        tertiary = if (isDefault) RMutedLight else eff,
        onTertiary = if (isDefault) RCardLight else onEff,
        tertiaryContainer = if (isDefault) RSecondaryLight else tint,
        onTertiaryContainer = RInkLight,
        background = RBgLight,
        onBackground = RInkLight,
        surface = RCardLight,
        onSurface = RInkLight,
        surfaceVariant = RSecondaryLight,
        onSurfaceVariant = RMutedLight,
        surfaceContainerLowest = RBgLight,
        surfaceContainerLow = RSecondaryLight,
        surfaceContainer = RSecondaryLight,
        surfaceContainerHigh = RSecondaryLight,
        surfaceContainerHighest = RCardBorderLight,
        outline = RMutedLight,
        outlineVariant = RCardBorderLight,
        surfaceTint = RCardLight,
        error = StatusRed,
        onError = Color.White,
    )
    val dark = darkColorScheme(
        primary = eff,
        onPrimary = onEff,
        primaryContainer = if (isDefault) RSecondaryDark else tint,
        onPrimaryContainer = RInkDark,
        secondary = if (isDefault) RMutedDark else eff,
        onSecondary = if (isDefault) RBgDark else onEff,
        secondaryContainer = if (isDefault) RSecondaryDark else tint,
        onSecondaryContainer = RInkDark,
        tertiary = if (isDefault) RMutedDark else eff,
        onTertiary = if (isDefault) RBgDark else onEff,
        tertiaryContainer = if (isDefault) RSecondaryDark else tint,
        onTertiaryContainer = RInkDark,
        background = RBgDark,
        onBackground = RInkDark,
        surface = RCardDark,
        onSurface = RInkDark,
        surfaceVariant = RSecondaryDark,
        onSurfaceVariant = RMutedDark,
        surfaceContainerLowest = RBgDark,
        surfaceContainerLow = RSecondaryDark,
        surfaceContainer = RSecondaryDark,
        surfaceContainerHigh = RSecondaryDark,
        surfaceContainerHighest = RCardBorderDark,
        outline = RMutedDark,
        outlineVariant = RCardBorderDark,
        surfaceTint = RCardDark,
        error = StatusRed,
        onError = Color.White,
    )
    val scheme = (if (darkTheme) dark else light).animated(reduced)
    val view = LocalView.current
    if (!view.isInEditMode) {
        SideEffect { applySystemBars(view, darkTheme, scheme.background) }
    }
    CompositionLocalProvider(
        LocalEduFlowDark provides darkTheme,
        LocalReducedMotion provides reduced,
    ) {
        MaterialTheme(
            colorScheme = scheme,
            typography = EduFlowTypography,
            shapes = EduFlowShapes,
            content = content,
        )
    }
}

/**
 * Effektiver Akzent: "black" (Standard, [Color.Black]) bleibt PNG-treu
 * (Light Schwarz, Dark Weiß), jede andere Wahl gilt in beiden Modi.
 * MainActivity übergibt accentByKey(key).color, daher ist Black hier
 * gleichbedeutend mit "kein Akzent gewählt".
 */
fun effectiveAccent(accent: Color, darkTheme: Boolean): Color =
    if (accent == Color.Black && darkTheme) Color.White else accent

/**
 * Lesbare Schrift auf dem Akzent: Weiß oder Schwarz, je nachdem was nach
 * WCAG (relative Luminanz) mehr Kontrast bietet.
 */
fun contentOnAccent(accent: Color): Color {
    fun lin(c: Float): Double {
        val v = c.toDouble()
        return if (v <= 0.04045) v / 12.92 else Math.pow((v + 0.055) / 1.055, 2.4)
    }
    val lum = 0.2126 * lin(accent.red) + 0.7152 * lin(accent.green) + 0.0722 * lin(accent.blue)
    val contrastWhite = 1.05 / (lum + 0.05)
    val contrastBlack = (lum + 0.05) / 0.05
    return if (contrastWhite >= contrastBlack) Color.White else Color.Black
}

/** Opaque Mischung zweier Farben (Anteil von [other], 0..1). */
fun Color.mix(other: Color, fraction: Float): Color {
    val f = fraction.coerceIn(0f, 1f)
    return Color(
        red = red * (1 - f) + other.red * f,
        green = green * (1 - f) + other.green * f,
        blue = blue * (1 - f) + other.blue * f,
        alpha = 1f,
    )
}

@Composable
private fun ColorScheme.animated(reduced: Boolean): ColorScheme {
    @Composable
    fun Color.anim(): Color {
        val value by animateColorAsState(
            targetValue = this,
            animationSpec = if (reduced) snap() else tween(220),
            label = "scheme",
        )
        return value
    }
    return copy(
        primary = primary.anim(),
        onPrimary = onPrimary.anim(),
        primaryContainer = primaryContainer.anim(),
        onPrimaryContainer = onPrimaryContainer.anim(),
        secondary = secondary.anim(),
        onSecondary = onSecondary.anim(),
        secondaryContainer = secondaryContainer.anim(),
        onSecondaryContainer = onSecondaryContainer.anim(),
        tertiary = tertiary.anim(),
        onTertiary = onTertiary.anim(),
        tertiaryContainer = tertiaryContainer.anim(),
        onTertiaryContainer = onTertiaryContainer.anim(),
        background = background.anim(),
        onBackground = onBackground.anim(),
        surface = surface.anim(),
        onSurface = onSurface.anim(),
        surfaceVariant = surfaceVariant.anim(),
        onSurfaceVariant = onSurfaceVariant.anim(),
        surfaceContainerLowest = surfaceContainerLowest.anim(),
        surfaceContainerLow = surfaceContainerLow.anim(),
        surfaceContainer = surfaceContainer.anim(),
        surfaceContainerHigh = surfaceContainerHigh.anim(),
        surfaceContainerHighest = surfaceContainerHighest.anim(),
        outline = outline.anim(),
        outlineVariant = outlineVariant.anim(),
        surfaceTint = surfaceTint.anim(),
        error = error.anim(),
        onError = onError.anim(),
    )
}

private fun applySystemBars(view: View, darkTheme: Boolean, background: Color) {
    val activity = view.context.findActivity() ?: return
    val window = activity.window
    val argb = background.toArgb()
    window.statusBarColor = argb
    window.navigationBarColor = android.graphics.Color.TRANSPARENT
    val controller = WindowCompat.getInsetsController(window, view)
    controller.isAppearanceLightStatusBars = !darkTheme
    controller.isAppearanceLightNavigationBars = !darkTheme
}

private tailrec fun Context.findActivity(): Activity? = when (this) {
    is Activity -> this
    is ContextWrapper -> baseContext.findActivity()
    else -> null
}
