package de.eduflow.android.ui.theme

import android.provider.Settings
import androidx.compose.animation.EnterTransition
import androidx.compose.animation.ExitTransition
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.keyframes
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.dp
import androidx.compose.runtime.getValue
import kotlinx.coroutines.launch

/** Wie prefers-reduced-motion im Web (static/uber.css). */
val LocalReducedMotion = staticCompositionLocalOf { false }

/** Effektives Farbschema der App (nicht nur System). */
val LocalEduFlowDark = staticCompositionLocalOf { false }

val EduFlowRiseEasing = CubicBezierEasing(0.22f, 0.8f, 0.32f, 1.12f)

@Composable
fun rememberReducedMotion(): Boolean {
    val context = LocalContext.current
    return remember(context) {
        try {
            val resolver = context.contentResolver
            val anim = Settings.Global.getFloat(resolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f)
            val trans = Settings.Global.getFloat(resolver, Settings.Global.TRANSITION_ANIMATION_SCALE, 1f)
            anim == 0f || trans == 0f
        } catch (_: Exception) {
            false
        }
    }
}

/**
 * Entrance wie `.anim-in` / `@keyframes rise-in` im Web:
 * von unten, leichtes Overshoot, Staffel-Delay.
 */
fun Modifier.riseIn(index: Int = 0): Modifier = composed {
    val reduced = LocalReducedMotion.current
    val density = LocalDensity.current
    val alpha = remember { Animatable(if (reduced) 1f else 0f) }
    val offsetPx = with(density) { 22.dp.toPx() }
    val offset = remember { Animatable(if (reduced) 0f else offsetPx) }
    val scale = remember { Animatable(if (reduced) 1f else 0.985f) }
    LaunchedEffect(reduced) {
        if (reduced) {
            alpha.snapTo(1f)
            offset.snapTo(0f)
            scale.snapTo(1f)
            return@LaunchedEffect
        }
        kotlinx.coroutines.delay(index * 45L)
        launch {
            alpha.animateTo(
                1f,
                tween(durationMillis = 550, easing = EduFlowRiseEasing),
            )
        }
        launch {
            offset.animateTo(
                0f,
                tween(durationMillis = 550, easing = EduFlowRiseEasing),
            )
        }
        launch {
            scale.animateTo(
                1f,
                keyframes {
                    durationMillis = 550
                    0.985f at 0
                    1.002f at 330
                    1f at 550
                },
            )
        }
    }
    graphicsLayer {
        this.alpha = alpha.value
        translationY = offset.value
        scaleX = scale.value
        scaleY = scale.value
    }
}

fun eduFlowEnter(): EnterTransition {
    val spec = tween<Float>(280, easing = FastOutSlowInEasing)
    return fadeIn(spec) + slideInHorizontally(animationSpec = tween(280, easing = FastOutSlowInEasing)) { it / 16 }
}

fun eduFlowExit(): ExitTransition {
    val spec = tween<Float>(200, easing = FastOutSlowInEasing)
    return fadeOut(spec) + slideOutHorizontally(animationSpec = tween(200, easing = FastOutSlowInEasing)) { -it / 24 }
}

fun eduFlowPopEnter(): EnterTransition {
    val spec = tween<Float>(280, easing = FastOutSlowInEasing)
    return fadeIn(spec) + slideInHorizontally(animationSpec = tween(280, easing = FastOutSlowInEasing)) { -it / 16 }
}

fun eduFlowPopExit(): ExitTransition {
    val spec = tween<Float>(200, easing = FastOutSlowInEasing)
    return fadeOut(spec) + slideOutHorizontally(animationSpec = tween(200, easing = FastOutSlowInEasing)) { it / 24 }
}

/** Pulsierender Punkt wie `.now-dot` auf der Übersicht. */
@Composable
fun NowDot(
    modifier: Modifier = Modifier,
    color: androidx.compose.ui.graphics.Color = MaterialTheme.colorScheme.onBackground,
) {
    val reduced = LocalReducedMotion.current
    val alpha = if (reduced) {
        1f
    } else {
        val t = rememberInfiniteTransition(label = "now-dot")
        t.animateFloat(
            initialValue = 1f,
            targetValue = 0.35f,
            animationSpec = infiniteRepeatable(
                animation = tween(1000, easing = FastOutSlowInEasing),
                repeatMode = RepeatMode.Reverse,
            ),
            label = "now-dot-alpha",
        ).value
    }
    Surface(
        modifier = modifier.size(7.dp).graphicsLayer { this.alpha = alpha },
        shape = CircleShape,
        color = color,
    ) {}
}
