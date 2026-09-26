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
    // Primär wie im PNG: Light = Schwarz, Dark = Weiß (Buttons invertiert).
    // Der Akzent-Parameter bleibt für die Farb-Dots (Paket F) erhalten.
    val light = lightColorScheme(
        primary = Color.Black,
        onPrimary = Color.White,
        primaryContainer = RSecondaryLight,
        onPrimaryContainer = RInkLight,
        secondary = RMutedLight,
        onSecondary = RCardLight,
        secondaryContainer = RSecondaryLight,
        onSecondaryContainer = RInkLight,
        tertiary = RMutedLight,
        onTertiary = RCardLight,
        tertiaryContainer = RSecondaryLight,
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
        primary = Color.White,
        onPrimary = Color.Black,
        primaryContainer = RSecondaryDark,
        onPrimaryContainer = RInkDark,
        secondary = RMutedDark,
        onSecondary = RBgDark,
        secondaryContainer = RSecondaryDark,
        onSecondaryContainer = RInkDark,
        tertiary = RMutedDark,
        onTertiary = RBgDark,
        tertiaryContainer = RSecondaryDark,
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
