package de.eduflow.android.ui.navigation

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Assignment
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.MailOutline
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.res.stringResource
import de.eduflow.android.R
import de.eduflow.android.ui.theme.LocalEduFlowDark
import de.eduflow.android.ui.theme.LocalReducedMotion

// PNG-Design: fünf gleich breite Tabs; die aktive Auswahl gleitet in einer
// weichen, runden Glaskapsel unter Icon und Bezeichnung.
data class BottomTab(val route: String, val labelRes: Int, val icon: ImageVector)

val BottomTabs = listOf(
    BottomTab(Routes.OVERVIEW, R.string.bottom_home, Icons.Filled.Home),
    BottomTab(Routes.HOMEWORK, R.string.bottom_tasks, Icons.AutoMirrored.Filled.Assignment),
    BottomTab(Routes.MESSAGES, R.string.bottom_messages, Icons.Filled.MailOutline),
    BottomTab(Routes.TIMETABLE, R.string.bottom_plan, Icons.Filled.CalendarMonth),
    BottomTab(Routes.MORE, R.string.bottom_more, Icons.Filled.MoreHoriz),
)

/** Aktiver Tab zur Route (Thread/Verfassen zählen zu Nachrichten,
 * Noten/Einstellungen/Geräte zu Mehr). */
fun tabForRoute(route: String?): String? = when {
    route == null -> null
    route == Routes.OVERVIEW -> Routes.OVERVIEW
    route == Routes.HOMEWORK -> Routes.HOMEWORK
    route == Routes.TIMETABLE -> Routes.TIMETABLE
    route.startsWith(Routes.MESSAGES) -> Routes.MESSAGES
    route == Routes.GRADES || route == Routes.SCHOOL || route == Routes.SETTINGS ||
        route == Routes.DEVICES || route == Routes.MORE -> Routes.MORE
    else -> null
}

@Composable
fun EduFlowBottomBar(
    currentRoute: String?,
    onSection: (String) -> Unit,
    modifier: Modifier = Modifier,
    collapsed: Boolean = false,
) {
    val scheme = MaterialTheme.colorScheme
    val darkTheme = LocalEduFlowDark.current
    val activeIndex = BottomTabs.indexOfFirst { it.route == tabForRoute(currentRoute) }
    val reduceMotion = LocalReducedMotion.current
    val slotColor = if (darkTheme) Color(0xFF262626) else Color(0xFFECECEE)

    // Scroll-Collapse: runter = nur Icons, hoch = voll mit Labels.
    // Gleiche Feder wie die Pillen-Animation (bzw. Sprung bei Reduced Motion).
    val heightSpec = if (reduceMotion) tween<Dp>(1) else
        spring<Dp>(dampingRatio = 0.74f, stiffness = 370f)
    val barHeight by animateDpAsState(
        if (collapsed) 44.dp else 56.dp, heightSpec, label = "bottom-bar-height",
    )
    val pillHeight by animateDpAsState(
        if (collapsed) 42.dp else 54.dp, heightSpec, label = "bottom-bar-pill",
    )
    val slotHeight by animateDpAsState(
        if (collapsed) 36.dp else 46.dp, heightSpec, label = "bottom-bar-slot",
    )

    Box(modifier = modifier.fillMaxWidth().padding(horizontal = 5.dp, vertical = 4.dp)) {
        BoxWithConstraints(Modifier.fillMaxWidth().height(barHeight)) {
            val slotWidth = maxWidth / BottomTabs.size
            val targetOffset = if (activeIndex >= 0) slotWidth * activeIndex + 5.dp else -slotWidth
            val animatedOffset by animateDpAsState(
                targetValue = targetOffset,
                animationSpec = if (reduceMotion) tween(1) else
                    spring(dampingRatio = 0.74f, stiffness = 370f),
                label = "bottom-tab-pill-slide",
            )

            Surface(
                shape = CircleShape,
                color = (if (darkTheme) Color(0xFF1C1C1E) else Color.White)
                    .copy(alpha = if (darkTheme) 0.48f else 0.64f),
                border = BorderStroke(
                    1.dp,
                    (if (darkTheme) Color.White else Color(0xFFBFC0C4))
                        .copy(alpha = if (darkTheme) 0.12f else 0.28f),
                ),
                modifier = Modifier.align(Alignment.Center)
                    .fillMaxWidth().height(pillHeight)
                    .shadow(8.dp, CircleShape).clip(CircleShape),
            ) {}

            if (activeIndex >= 0) {
                Surface(
                    shape = CircleShape,
                    color = slotColor.copy(alpha = if (darkTheme) 0.82f else 0.76f),
                    border = BorderStroke(
                        1.dp,
                        (if (darkTheme) Color.White else Color.White).copy(alpha = if (darkTheme) 0.13f else 0.88f),
                    ),
                    modifier = Modifier.align(Alignment.CenterStart)
                        .offset(x = animatedOffset)
                        .width(slotWidth - 10.dp)
                        .height(slotHeight)
                        .shadow(4.dp, CircleShape)
                        .clip(CircleShape),
                ) {}
            }

            Row(Modifier.fillMaxWidth().height(barHeight)) {
                BottomTabs.forEach { tab ->
                    val selected = tab.route == tabForRoute(currentRoute)
                    BottomTabItem(
                        tab = tab,
                        selected = selected,
                        onClick = { onSection(tab.route) },
                        modifier = Modifier.weight(1f),
                        contentHeight = barHeight,
                        collapsed = collapsed,
                    )
                }
            }
        }
    }
}

@Composable
private fun BottomTabItem(
    tab: BottomTab,
    selected: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    contentHeight: Dp = 56.dp,
    collapsed: Boolean = false,
) {
    val scheme = MaterialTheme.colorScheme
    val label = stringResource(tab.labelRes)
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
        modifier = modifier.height(contentHeight).clip(CircleShape).clickable(onClick = onClick)
            .padding(horizontal = 2.dp, vertical = 3.dp),
    ) {
        Icon(
            tab.icon,
            contentDescription = label,
            tint = if (selected) scheme.onSurface else scheme.onSurfaceVariant,
            modifier = Modifier.size(18.dp),
        )
        AnimatedVisibility(
            visible = !collapsed,
            enter = fadeIn() + expandVertically(),
            exit = fadeOut() + shrinkVertically(),
        ) {
            Text(
                label,
                fontSize = 9.sp,
                lineHeight = 11.sp,
                fontWeight = if (selected) FontWeight.Bold else FontWeight.Medium,
                color = if (selected) scheme.onSurface else scheme.onSurfaceVariant,
                maxLines = 1,
                modifier = Modifier.padding(top = 2.dp),
            )
        }
    }
}
