package de.eduflow.android.ui.settings

import androidx.compose.foundation.gestures.detectDragGesturesAfterLongPress
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Checklist
import androidx.compose.material.icons.filled.DragHandle
import androidx.compose.material.icons.filled.Email
import androidx.compose.material.icons.filled.Restaurant
import androidx.compose.material.icons.filled.WbSunny
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.zIndex
import de.eduflow.android.R
import de.eduflow.android.ui.overview.OverviewOrder
import kotlin.math.roundToInt

/**
 * Reihenfolge-Editor für die Übersichts-Bereiche: Vorschau-Karten per
 * Gedrückthalten am Griff ziehen; die Liste sortiert live um (reine
 * Umordnung via [OverviewOrder.move], Speichern bleibt beim Aufrufer).
 */
@Composable
fun OverviewOrderEditor(
    order: List<String>,
    onOrderChange: (List<String>) -> Unit,
    modifier: Modifier = Modifier,
) {
    val density = LocalDensity.current
    var draggedKey by remember { mutableStateOf<String?>(null) }
    var dragFromIndex by remember { mutableIntStateOf(-1) }
    var dragOffsetPx by remember { mutableFloatStateOf(0f) }
    val rowHeights = remember { mutableStateMapOf<String, Int>() }
    val orderState by rememberUpdatedState(order)
    val spacingPx = with(density) { 8.dp.toPx() }
    LazyColumn(
        modifier = modifier,
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        items(order, key = { it }) { key ->
            val index = order.indexOf(key)
            val rowHeight = rowHeights[key] ?: 0
            val stride = rowHeight + spacingPx
            val translation = if (key == draggedKey && dragFromIndex >= 0 && stride > 0) {
                dragOffsetPx - (index - dragFromIndex) * stride
            } else {
                0f
            }
            Box(
                modifier = Modifier
                    .onSizeChanged { rowHeights[key] = it.height }
                    .graphicsLayer { translationY = translation }
                    .zIndex(if (key == draggedKey) 1f else 0f),
            ) {
                OrderPreviewRow(
                    sectionKey = key,
                    elevated = key == draggedKey,
                    handleModifier = Modifier.pointerInput(key, rowHeight) {
                        detectDragGesturesAfterLongPress(
                            onDragStart = {
                                draggedKey = key
                                dragFromIndex = orderState.indexOf(key)
                                dragOffsetPx = 0f
                            },
                            onDragEnd = {
                                draggedKey = null
                                dragFromIndex = -1
                                dragOffsetPx = 0f
                            },
                            onDragCancel = {
                                draggedKey = null
                                dragFromIndex = -1
                                dragOffsetPx = 0f
                            },
                            onDrag = { change, amount ->
                                change.consume()
                                dragOffsetPx += amount.y
                                val current = orderState.indexOf(key)
                                if (rowHeight > 0 && current >= 0 && dragFromIndex >= 0) {
                                    val target = ((dragFromIndex * stride + dragOffsetPx) / stride)
                                        .roundToInt()
                                        .coerceIn(0, orderState.lastIndex)
                                    if (target != current) {
                                        onOrderChange(
                                            OverviewOrder.move(orderState, current, target - current),
                                        )
                                    }
                                }
                            },
                        )
                    },
                )
            }
        }
    }
}

/** Vorschau-Karte eines Bereichs (Icon + Titel, nicht interaktiv). */
@Composable
private fun OrderPreviewRow(
    sectionKey: String,
    elevated: Boolean,
    handleModifier: Modifier,
) {
    val scheme = MaterialTheme.colorScheme
    Surface(
        shape = RoundedCornerShape(16.dp),
        color = scheme.surfaceVariant,
        tonalElevation = if (elevated) 6.dp else 0.dp,
        shadowElevation = if (elevated) 8.dp else 0.dp,
        modifier = Modifier.fillMaxWidth(),
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.padding(horizontal = 12.dp, vertical = 12.dp),
        ) {
            Icon(
                Icons.Filled.DragHandle,
                contentDescription = stringResource(R.string.overview_drag_handle_desc),
                tint = scheme.onSurfaceVariant,
                modifier = handleModifier.size(24.dp),
            )
            Spacer(Modifier.width(12.dp))
            Icon(
                sectionIcon(sectionKey),
                contentDescription = null,
                tint = scheme.primary,
                modifier = Modifier.size(22.dp),
            )
            Spacer(Modifier.width(12.dp))
            Text(
                OverviewOrder.label(sectionKey),
                fontSize = 15.sp,
                fontWeight = FontWeight.SemiBold,
                color = scheme.onSurface,
                modifier = Modifier.weight(1f),
            )
        }
    }
}

private fun sectionIcon(key: String): ImageVector = when (key) {
    "messages" -> Icons.Filled.Email
    "homework" -> Icons.Filled.Checklist
    "weather" -> Icons.Filled.WbSunny
    else -> Icons.Filled.Restaurant
}
