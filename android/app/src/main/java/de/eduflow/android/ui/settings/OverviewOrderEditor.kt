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
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material.icons.filled.Restaurant
import androidx.compose.material.icons.filled.WbSunny
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
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
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.zIndex
import de.eduflow.android.R
import de.eduflow.android.ui.overview.OverviewOrder

/**
 * Slot-Geometrie der Editor-Liste, eingefroren beim Start einer Geste.
 *
 * `tops` = Oberkante je Slot, `centers` = Mitte je Slot. Alles in Pixeln
 * relativ zum Listenanfang; `measured` ist false, solange noch keine
 * Zeile gemessen wurde.
 */
private data class SlotGeometry(
    val tops: FloatArray,
    val centers: FloatArray,
    val measured: Boolean,
)

/**
 * Reihenfolge-Editor für die Übersichts-Bereiche: Vorschau-Karten per
 * Gedrückthalten am Griff ziehen; die Liste sortiert live um (reine
 * Umordnung via [OverviewOrder.move], Speichern bleibt beim Aufrufer).
 *
 * Slot-Geometrie aus den *gemessenen* Zeilenhöhen statt aus einer
 * angenommenen Schrittweite: die Karten können unterschiedlich hoch
 * sein (langer Titel bricht um), und eine feste Schrittweite liefe
 * dann seitlich aus dem Takt. Während des Ziehens merkt sich
 * [dragStartTop] die Oberkante des Startslots als Wert — die live
 * mitgewanderten Slot-Oberkanten dürfen die Startposition nicht
 * überschreiben, sonst hüpfte die Karte beim Umrutschen.
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

    // Oberkante jedes Slots aus den gemessenen Höhen. `rowHeights` wird
    // hier in der Komposition gelesen, das erste onSizeChanged löst also
    // eine Neuberechnung aus.
    val slotTops = ArrayList<Float>(order.size)
    val slotCenters = ArrayList<Float>(order.size)
    var accumulated = 0f
    var measured = true
    for (key in order) {
        val height = rowHeights[key] ?: 0
        if (height <= 0) measured = false
        slotTops += accumulated
        slotCenters += accumulated + height / 2f
        accumulated += height + spacingPx
    }
    // In die Gesten-Handler spiegeln: der PointerInput-Block läuft
    // außerhalb der Komposition und würde sonst auf die Slot-Werte des
    // letzten Durchlaufs zugreifen (bzw. auf veraltete, wenn `order`
    // zwischenzeitlich wechselte).
    val geometry = rememberUpdatedState(
        SlotGeometry(slotTops.toFloatArray(), slotCenters.toFloatArray(), measured),
    )

    LazyColumn(
        modifier = modifier,
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        items(order, key = { it }) { key ->
            val index = order.indexOf(key)
            val height = rowHeights[key] ?: 0
            val dragging = key == draggedKey && index >= 0 && index < slotTops.size
            // Die gezogene Karte folgt dem Finger (`dragOffsetPx` ist relativ
            // zu ihrem aktuellen Slot). Alle anderen Karten weichen um
            // genau eine Slot-Höhe aus, sobald die gezogene Karte über
            // ihnen steht — sonst bliebe zwischen ihnen eine Lücke, weil
            // der LazyColumn die umsortierte Liste ohne Lücke abbildet.
            val translation = when {
                dragging -> dragOffsetPx
                dragFromIndex >= 0 && index in (dragFromIndex + 1)..slotCenters.lastIndex &&
                    dragOffsetPx < 0f -> -(height + spacingPx)
                dragFromIndex >= 0 && index in 0 until dragFromIndex &&
                    dragOffsetPx > 0f -> height + spacingPx
                else -> 0f
            }
            Box(
                modifier = Modifier
                    .onSizeChanged { rowHeights[key] = it.height }
                    .graphicsLayer { translationY = translation }
                    .zIndex(if (dragging) 1f else 0f),
            ) {
                OrderPreviewRow(
                    sectionKey = key,
                    elevated = dragging,
                    onMoveUp = {
                        val current = orderState.indexOf(key)
                        if (current > 0) onOrderChange(OverviewOrder.move(orderState, current, -1))
                    },
                    onMoveDown = {
                        val current = orderState.indexOf(key)
                        if (current in 0 until orderState.lastIndex) {
                            onOrderChange(OverviewOrder.move(orderState, current, 1))
                        }
                    },
                    moveUpEnabled = index > 0,
                    moveDownEnabled = index < order.lastIndex,
                    handleModifier = Modifier.pointerInput(key) {
                        detectDragGesturesAfterLongPress(
                            onDragStart = {
                                val geo = geometry.value
                                val current = orderState.indexOf(key)
                                if (geo.measured && current in geo.tops.indices) {
                                    draggedKey = key
                                    dragFromIndex = current
                                    dragOffsetPx = 0f
                                }
                            },
                            onDragEnd = { draggedKey = null; dragFromIndex = -1; dragOffsetPx = 0f },
                            onDragCancel = { draggedKey = null; dragFromIndex = -1; dragOffsetPx = 0f },
                            onDrag = { change, amount ->
                                change.consume()
                                // Vor dem ersten Messdurchlauf gibt es keine
                                // belastbaren Slots — dann nur mitziehen.
                                val geo = geometry.value
                                if (!geo.measured || geo.centers.isEmpty()) return@detectDragGesturesAfterLongPress
                                dragOffsetPx += amount.y
                                val current = orderState.indexOf(key)
                                if (current < 0 || current !in geo.centers.indices) return@detectDragGesturesAfterLongPress
                                // Gemessen wird der Weg ab dem Slot, in dem die Karte
                                // gerade steht: `dragOffsetPx` ist, wie weit sie
                                // seit dem letzten Slotwechsel von ihrer
                                // Slot-Mitte gewandert ist. Getauscht wird,
                                // sobald sie die Mitte des Nachbarn passiert —
                                // also pro halber Slot-Höhe ein Platz. Absolut
                                // rechnen (Slot-Mitte ± Gesamtversatz) stapelte
                                // die Distanz nach jedem Sprung und rutschte
                                // deshalb immer zwei Plätze weiter.
                                val stride = (geo.centers.getOrNull(1) ?: 0f) -
                                    (geo.centers.getOrNull(0) ?: 0f)
                                val steps = if (stride > 0f) {
                                    (dragOffsetPx / (stride / 2f)).toInt()
                                } else {
                                    0
                                }
                                val target = (current + steps).coerceIn(0, orderState.lastIndex)
                                if (target != current) {
                                    onOrderChange(OverviewOrder.move(orderState, current, target - current))
                                    dragFromIndex = target
                                    // Überschuss über die neue Slot-Mitte hinaus
                                    // mitnehmen, damit die Karte nicht springt.
                                    dragOffsetPx -= (target - current) * stride
                                }
                            },
                        )
                    },
                )
            }
        }
    }
}

/**
 * Vorschau-Karte eines Bereichs: Drag-Griff (ziehen) plus Auf/Ab-Knöpfe.
 *
 * Die Knöpfe sind kein Duplikat, sondern der Zugang für Screenreader und
 * für Nutzer:innen, die nicht lange drücken können (Motorik). Beide Wege
 * ändern dieselbe Liste, das Speichern bleibt beim Aufrufer.
 */
@Composable
private fun OrderPreviewRow(
    sectionKey: String,
    elevated: Boolean,
    onMoveUp: () -> Unit,
    onMoveDown: () -> Unit,
    moveUpEnabled: Boolean,
    moveDownEnabled: Boolean,
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
            modifier = Modifier.padding(start = 12.dp, end = 4.dp, top = 12.dp, bottom = 12.dp),
        ) {
            Icon(
                Icons.Filled.DragHandle,
                contentDescription = stringResource(R.string.overview_drag_handle_desc),
                tint = scheme.onSurfaceVariant,
                modifier = handleModifier.size(24.dp),
            )
            Spacer(Modifier.width(10.dp))
            Icon(
                sectionIcon(sectionKey),
                contentDescription = null,
                tint = scheme.primary,
                modifier = Modifier.size(22.dp),
            )
            Spacer(Modifier.width(10.dp))
            Text(
                OverviewOrder.label(sectionKey),
                fontSize = 15.sp,
                fontWeight = FontWeight.SemiBold,
                color = scheme.onSurface,
                // Eine Zeile reicht: die Sektionsnamen sind alle kurz
                // („Hausaufgaben" ist der längste). Ohne maxLines brach der
                // Text um, weil Griff, Icon und zwei Knöpfe den Platz
                // schmaler machen als die Zeile wirkt.
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f),
            )
            IconButton(onClick = onMoveUp, enabled = moveUpEnabled) {
                Icon(
                    Icons.Filled.KeyboardArrowUp,
                    contentDescription = stringResource(R.string.overview_move_up_desc),
                    tint = scheme.onSurfaceVariant,
                    modifier = Modifier.size(20.dp),
                )
            }
            IconButton(onClick = onMoveDown, enabled = moveDownEnabled) {
                Icon(
                    Icons.Filled.KeyboardArrowDown,
                    contentDescription = stringResource(R.string.overview_move_down_desc),
                    tint = scheme.onSurfaceVariant,
                    modifier = Modifier.size(20.dp),
                )
            }
        }
    }
}

private fun sectionIcon(key: String): ImageVector = when (key) {
    "messages" -> Icons.Filled.Email
    "homework" -> Icons.Filled.Checklist
    "weather" -> Icons.Filled.WbSunny
    else -> Icons.Filled.Restaurant
}
