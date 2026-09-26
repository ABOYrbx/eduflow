package de.eduflow.android.ui.overview

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ChevronLeft
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.AcUnit
import androidx.compose.material.icons.filled.Cloud
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Thunderstorm
import androidx.compose.material.icons.filled.WaterDrop
import androidx.compose.material.icons.filled.WbSunny
import androidx.compose.material.icons.filled.Tune
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import de.eduflow.android.data.dto.ErrorCodes
import de.eduflow.android.data.dto.EssenDays
import de.eduflow.android.data.dto.HomeworkDto
import de.eduflow.android.data.dto.LessonDto
import de.eduflow.android.data.dto.MessageDto
import de.eduflow.android.ui.common.AppHeader
import de.eduflow.android.ui.common.EduCard
import de.eduflow.android.ui.common.ScreenHead
import de.eduflow.android.ui.common.SectionLabel
import de.eduflow.android.ui.timetable.AuthAwareError
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.format.DateTimeFormatter
import kotlinx.coroutines.delay

/**
 * Übersicht — Startseite (Paket G, PNG-Stil wie Pakete A–F).
 *
 * Header, „Home"-Titel + Datum, Uhr-Karte, Jetzt-Karte in
 * Primär-Farbe (Jetzt / Als Nächstes), Wetterkarte (nur wenn
 * `ov_wetter` an), neueste Nachrichten (`ov_unread`-Limit), offene
 * Hausaufgaben (`ov_homework`-Limit), Mittagessen mit ‹ ›-Pager
 * (Mo–Fr, Start heute). Inhalte wie `/` (Web-Übersicht, Logik im
 * ViewModel — hier nur Anzeige); Abschnittsköpfe verlinken auf die
 * Listen; 401-Verhalten → Login.
 */
@Composable
fun OverviewScreen(
    viewModel: OverviewViewModel,
    onMessages: () -> Unit,
    onHomework: () -> Unit,
    onTimetable: () -> Unit,
    onGrades: () -> Unit,
    onSettings: () -> Unit,
    onReLogin: () -> Unit,
    onOpenSettings: () -> Unit = {},
    onLogout: () -> Unit = {},
    modifier: Modifier = Modifier,
) {
    val state by viewModel.state.collectAsState()
    var showOrderEditor by remember { mutableStateOf(false) }
    var draftOrder by remember(state.settings.ovOrder) {
        mutableStateOf(OverviewOrder.parse(state.settings.ovOrder))
    }
    val todayLabel = remember {
        try {
            LocalDate.now().format(DateTimeFormatter.ofPattern("EEEE, dd.MM.yyyy"))
        } catch (_: Exception) {
            ""
        }
    }

    Column(modifier = modifier.fillMaxSize().padding(16.dp)) {
        AppHeader(
            onSettings = onOpenSettings,
            onLogout = onLogout,
        )
        Spacer(Modifier.height(12.dp))
        ScreenHead(title = "Home", subtitle = todayLabel)
        TextButton(onClick = {
            draftOrder = OverviewOrder.parse(state.settings.ovOrder)
            showOrderEditor = true
        }) {
            Icon(Icons.Filled.Tune, contentDescription = null, modifier = Modifier.size(16.dp))
            Text("Übersicht anpassen")
        }
        Spacer(Modifier.height(12.dp))

        state.error?.let { err ->
            AuthAwareError(
                message = "${err.message} (${err.code})",
                needsReLogin = err.code in
                    listOf(ErrorCodes.TOKEN_INVALID, ErrorCodes.TOKEN_EXPIRED, ErrorCodes.EDUPAGE_2FA),
                onReLogin = onReLogin,
                onDismiss = viewModel::dismissError,
                modifier = Modifier.padding(bottom = 8.dp),
            )
        }

        if (state.isLoading && state.messages.isEmpty() && state.homework.isEmpty()
            && state.lessonsToday.isEmpty() && state.essen == null
        ) {
            Row(
                modifier = Modifier.fillMaxWidth().padding(32.dp),
                horizontalArrangement = Arrangement.Center,
            ) { CircularProgressIndicator() }
        } else {
            LazyColumn(
                verticalArrangement = Arrangement.spacedBy(10.dp),
                modifier = Modifier.weight(1f),
            ) {
                item { LiveClockCard(onRefresh = viewModel::refresh, refreshing = state.isLoading) }
                item {
                    NowCard(
                        current = state.currentLesson,
                        next = state.nextLesson,
                        onTimetable = onTimetable,
                    )
                }
                items(OverviewOrder.parse(state.settings.ovOrder), key = { it }) { section ->
                    when (section) {
                        "weather" -> if (state.settings.ovWetter) {
                            WetterCard(
                                city = state.wetterCity,
                                wetter = state.wetter,
                                loading = state.wetterLoading,
                                error = state.wetterError?.let { "${it.message} (${it.code})" },
                                onLoad = viewModel::loadWetter,
                                onConfigure = onOpenSettings,
                            )
                        }
                        "messages" -> MessagesOverviewSection(state.messages, state.messagesTotal, onMessages)
                        "homework" -> HomeworkOverviewSection(state.homework, state.homeworkCounts, onHomework)
                        "lunch" -> LunchOverviewSection(state, viewModel, onTimetable)
                    }
                }
                if (state.cacheInfo.isNotBlank()) {
                    item {
                        Text(
                            state.cacheInfo,
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
                item { Spacer(Modifier.height(88.dp)) }
            }
        }
    }

    if (showOrderEditor) {
        AlertDialog(
            onDismissRequest = { if (!state.savingOverviewOrder) showOrderEditor = false },
            title = { Text("Übersicht anpassen") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("Lege fest, welche Bereiche zuerst erscheinen.", style = MaterialTheme.typography.bodySmall)
                    draftOrder.forEachIndexed { index, key ->
                        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
                            Text(OverviewOrder.labels[key].orEmpty(), modifier = Modifier.weight(1f))
                            IconButton(onClick = { draftOrder = OverviewOrder.move(draftOrder, index, -1) }, enabled = index > 0) {
                                Icon(Icons.Filled.KeyboardArrowUp, contentDescription = "Nach oben")
                            }
                            IconButton(onClick = { draftOrder = OverviewOrder.move(draftOrder, index, 1) }, enabled = index < draftOrder.lastIndex) {
                                Icon(Icons.Filled.KeyboardArrowDown, contentDescription = "Nach unten")
                            }
                        }
                    }
                }
            },
            confirmButton = {
                TextButton(
                    enabled = !state.savingOverviewOrder,
                    onClick = {
                        viewModel.saveOverviewOrder(draftOrder)
                        showOrderEditor = false
                    },
                ) { Text(if (state.savingOverviewOrder) "Speichert …" else "Speichern") }
            },
            dismissButton = {
                TextButton(onClick = { showOrderEditor = false }, enabled = !state.savingOverviewOrder) {
                    Text("Abbrechen")
                }
            },
        )
    }
}

@Composable
private fun MessagesOverviewSection(messages: List<MessageDto>, total: Int, onMessages: () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        SectionHeadRow(label = "Nachrichten · $total", action = "Alle", onAction = onMessages)
        if (messages.isEmpty()) {
            Text("Keine neuen Nachrichten.", style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(horizontal = 4.dp))
        } else messages.forEach { MessageRow(msg = it) }
    }
}

@Composable
private fun HomeworkOverviewSection(
    homework: List<HomeworkDto>, counts: de.eduflow.android.data.dto.HomeworkCounts, onHomework: () -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        SectionHeadRow(label = "${counts.offen} offen · ${counts.ueberfaellig} überfällig",
            action = "Alle Aufgaben", onAction = onHomework)
        if (homework.isEmpty()) {
            Text("Keine offenen Hausaufgaben. Sehr gut.", style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(horizontal = 4.dp))
        } else homework.forEach { HomeworkRow(hw = it) }
    }
}

@Composable
private fun LunchOverviewSection(state: OverviewUiState, viewModel: OverviewViewModel, onTimetable: () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        SectionHeadRow(label = "Mittagessen", action = "Stundenplan", onAction = onTimetable)
        EssenPager(
            label = state.essen?.label.orEmpty(), sourceUrl = state.essen?.source_url.orEmpty(),
            cacheInfo = state.essen?.cache_info.orEmpty(),
            dayName = EssenDays.ORDER.getOrNull(state.essenIndex).orEmpty(),
            date = state.essen?.days?.get(EssenDays.ORDER.getOrNull(state.essenIndex))?.date.orEmpty(),
            dishes = state.essen?.days?.get(EssenDays.ORDER.getOrNull(state.essenIndex))?.dishes.orEmpty(),
            note = state.essen?.days?.get(EssenDays.ORDER.getOrNull(state.essenIndex))?.note.orEmpty(),
            canPrev = state.essenIndex > 0, canNext = state.essenIndex < EssenDays.ORDER.size - 1,
            onPrev = { viewModel.stepEssen(-1) }, onNext = { viewModel.stepEssen(1) },
        )
    }
}

/** Uhr-Karte (live, jede Sekunde, deutsches Format) + Aktualisieren. */
@Composable
private fun LiveClockCard(
    onRefresh: () -> Unit,
    refreshing: Boolean,
) {
    var now by remember { mutableStateOf(LocalDateTime.now()) }
    LaunchedEffect(Unit) {
        while (true) {
            delay(1000)
            now = LocalDateTime.now()
        }
    }
    val timeFmt = remember { DateTimeFormatter.ofPattern("HH:mm") }
    EduCard(modifier = Modifier.fillMaxWidth()) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.fillMaxWidth().padding(16.dp),
        ) {
            Column(Modifier.weight(1f)) {
                Text(
                    "UHRZEIT",
                    fontSize = 10.sp,
                    fontWeight = FontWeight.Bold,
                    letterSpacing = 1.1.sp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Text(
                    try {
                        now.format(timeFmt)
                    } catch (_: Exception) {
                        "--:--"
                    },
                    fontSize = 32.sp,
                    fontWeight = FontWeight.ExtraBold,
                    color = MaterialTheme.colorScheme.onSurface,
                )
            }
            IconButton(onClick = onRefresh, enabled = !refreshing) {
                Icon(Icons.Filled.Refresh, contentDescription = "Neu laden")
            }
        }
    }
}

/** Aktuelle/nächste Stunde — Karte in Primär-Farbe (wie Noten-Schnitt). */
@Composable
private fun NowCard(
    current: LessonDto?,
    next: LessonDto?,
    onTimetable: () -> Unit,
) {
    val scheme = MaterialTheme.colorScheme
    Surface(
        shape = RoundedCornerShape(16.dp),
        color = scheme.primary,
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(
                "STUNDEN HEUTE",
                fontSize = 11.sp,
                fontWeight = FontWeight.Bold,
                letterSpacing = 1.2.sp,
                color = scheme.onPrimary.copy(alpha = 0.7f),
            )
            if (current == null && next == null) {
                Text(
                    "Schulfrei — kein Unterricht heute.",
                    fontSize = 15.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = scheme.onPrimary,
                )
            } else {
                current?.let {
                    Text(
                        "Jetzt: ${it.title} (${it.period}. Std · ${it.time})",
                        fontSize = 15.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = scheme.onPrimary,
                    )
                }
                next?.let {
                    Text(
                        "Als Nächstes: ${it.title} (${it.period}. Std · ${it.time}" +
                            (if (it.rooms.isNotBlank()) " · Raum ${it.rooms}" else "") + ")",
                        fontSize = 13.sp,
                        color = scheme.onPrimary.copy(alpha = 0.75f),
                    )
                }
            }
            TextButton(
                onClick = onTimetable,
                colors = ButtonDefaults.textButtonColors(
                    contentColor = scheme.onPrimary,
                ),
            ) { Text("Stundenplan") }
        }
    }
}

/** Wetterkarte (Schlüssel bleibt serverseitig; Ort per Stadt). */
@Composable
private fun WetterCard(
    city: String,
    wetter: de.eduflow.android.data.dto.WetterResponse?,
    loading: Boolean,
    error: String?,
    onLoad: () -> Unit,
    onConfigure: () -> Unit,
) {
    val scheme = MaterialTheme.colorScheme
    EduCard(modifier = Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text(
                        "WETTER",
                        fontSize = 11.sp,
                        fontWeight = FontWeight.Bold,
                        letterSpacing = 1.2.sp,
                        color = scheme.onSurfaceVariant,
                    )
                    Text(
                        wetter?.city?.ifBlank { city }?.ifBlank { "Dein Standort" } ?: "Wetterübersicht",
                        fontSize = 16.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = scheme.onSurface,
                    )
                }
                IconButton(onClick = onLoad, enabled = !loading && city.isNotBlank()) {
                    if (loading) {
                        CircularProgressIndicator(modifier = Modifier.size(20.dp), strokeWidth = 2.dp)
                    } else {
                        Icon(Icons.Filled.Refresh, contentDescription = "Wetter aktualisieren")
                    }
                }
            }
            if (wetter == null) {
                if (city.isBlank()) {
                    Text(
                        "Lege deinen Ort in den Einstellungen fest, damit hier die Vorhersage erscheint.",
                        fontSize = 13.sp,
                        color = scheme.onSurfaceVariant,
                    )
                    TextButton(onClick = onConfigure) { Text("Ort in Einstellungen festlegen") }
                } else {
                    Text(
                        error ?: "Wetterdaten für $city werden geladen.",
                        fontSize = 13.sp,
                        color = if (error != null) scheme.error else scheme.onSurfaceVariant,
                    )
                    TextButton(onClick = onLoad, enabled = !loading) {
                        Text(if (loading) "Wird geladen …" else "Erneut laden")
                    }
                }
            } else {
                val t = wetter.today
                Surface(
                    color = scheme.primaryContainer,
                    shape = RoundedCornerShape(20.dp),
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Row(
                        modifier = Modifier.padding(horizontal = 16.dp, vertical = 14.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(14.dp),
                    ) {
                        Surface(
                            color = scheme.onPrimaryContainer.copy(alpha = 0.08f),
                            shape = RoundedCornerShape(18.dp),
                            modifier = Modifier.size(64.dp),
                        ) {
                            Box(contentAlignment = Alignment.Center) {
                                WetterIcon(icon = t.icon, modifier = Modifier.size(40.dp))
                            }
                        }
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(1.dp)) {
                            Row(verticalAlignment = Alignment.Bottom) {
                                Text(
                                    t.temp?.let { "$it°" } ?: "–",
                                    fontSize = 48.sp,
                                    lineHeight = 50.sp,
                                    fontWeight = FontWeight.Bold,
                                    letterSpacing = (-2).sp,
                                    color = scheme.onPrimaryContainer,
                                )
                                Text(
                                    "  HEUTE",
                                    modifier = Modifier.padding(bottom = 7.dp),
                                    fontSize = 10.sp,
                                    fontWeight = FontWeight.Bold,
                                    letterSpacing = 1.sp,
                                    color = scheme.onPrimaryContainer.copy(alpha = 0.65f),
                                )
                            }
                            Text(
                                t.desc.replaceFirstChar { it.uppercase() }.ifBlank { "Aktuelles Wetter" },
                                fontSize = 14.sp,
                                fontWeight = FontWeight.SemiBold,
                                color = scheme.onPrimaryContainer,
                                maxLines = 1,
                            )
                            Text(
                                "H ${t.max?.let { "$it°" } ?: "–"}  ·  T ${t.min?.let { "$it°" } ?: "–"}",
                                fontSize = 12.sp,
                                color = scheme.onPrimaryContainer.copy(alpha = 0.7f),
                            )
                        }
                    }
                }

                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    WetterMetric(
                        label = "REGEN",
                        value = t.pop?.let { "$it %" } ?: "–",
                        icon = Icons.Filled.WaterDrop,
                        modifier = Modifier.weight(1f),
                    )
                    WetterMetric(
                        label = "GEFÜHLT",
                        value = wetter.details.feels_like?.let { "$it°" } ?: "–",
                        icon = Icons.Filled.WbSunny,
                        modifier = Modifier.weight(1f),
                    )
                    WetterMetric(
                        label = "WIND",
                        value = wetter.details.wind_kmh?.let { "$it km/h" } ?: "–",
                        icon = Icons.Filled.Cloud,
                        modifier = Modifier.weight(1f),
                    )
                }

                Text(
                    "DIE NÄCHSTEN TAGE",
                    fontSize = 10.sp,
                    fontWeight = FontWeight.Bold,
                    letterSpacing = 1.1.sp,
                    color = scheme.onSurfaceVariant,
                )
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    WetterForecastDay(
                        label = "Heute",
                        icon = t.icon,
                        high = t.max,
                        low = t.min,
                        modifier = Modifier.weight(1f),
                    )
                    WetterForecastDay(
                        label = wetter.tomorrow.label.ifBlank { "Morgen" },
                        icon = wetter.tomorrow.icon,
                        high = wetter.tomorrow.max,
                        low = wetter.tomorrow.min,
                        modifier = Modifier.weight(1f),
                    )
                    WetterForecastDay(
                        label = wetter.day3.label.ifBlank { "Übermorgen" },
                        icon = wetter.day3.icon,
                        high = wetter.day3.max,
                        low = wetter.day3.min,
                        modifier = Modifier.weight(1f),
                    )
                }

                error?.let {
                    Text(
                        it,
                        style = MaterialTheme.typography.bodySmall,
                        color = scheme.error,
                    )
                }
            }
        }
    }
}

@Composable
private fun WetterMetric(
    label: String,
    value: String,
    icon: ImageVector,
    modifier: Modifier = Modifier,
) {
    val scheme = MaterialTheme.colorScheme
    Surface(
        color = scheme.surfaceContainerLow,
        shape = RoundedCornerShape(14.dp),
        modifier = modifier,
    ) {
        Column(
            modifier = Modifier.padding(horizontal = 10.dp, vertical = 9.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                Icon(icon, contentDescription = null, tint = scheme.onSurfaceVariant, modifier = Modifier.size(13.dp))
                Text(label, fontSize = 9.sp, fontWeight = FontWeight.Bold, letterSpacing = .4.sp, color = scheme.onSurfaceVariant)
            }
            Text(value, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = scheme.onSurface, maxLines = 1)
        }
    }
}

@Composable
private fun WetterForecastDay(
    label: String,
    icon: String,
    high: Int?,
    low: Int?,
    modifier: Modifier = Modifier,
) {
    val scheme = MaterialTheme.colorScheme
    Surface(color = scheme.surfaceContainerLow, shape = RoundedCornerShape(14.dp), modifier = modifier) {
        Column(
            modifier = Modifier.padding(vertical = 9.dp, horizontal = 6.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(3.dp),
        ) {
            Text(label, fontSize = 11.sp, fontWeight = FontWeight.SemiBold, color = scheme.onSurfaceVariant, maxLines = 1)
            WetterIcon(icon = icon, modifier = Modifier.size(24.dp))
            Text(
                "${high?.let { "$it°" } ?: "–"}  ${low?.let { "$it°" } ?: "–"}",
                fontSize = 11.sp,
                fontWeight = FontWeight.SemiBold,
                color = scheme.onSurface,
                maxLines = 1,
            )
        }
    }
}

@Composable
private fun WetterIcon(icon: String, modifier: Modifier = Modifier) {
    val scheme = MaterialTheme.colorScheme
    val image = when {
        icon.startsWith("01") -> Icons.Filled.WbSunny
        icon.startsWith("09") || icon.startsWith("10") -> Icons.Filled.WaterDrop
        icon.startsWith("11") -> Icons.Filled.Thunderstorm
        icon.startsWith("13") -> Icons.Filled.AcUnit
        else -> Icons.Filled.Cloud
    }
    Icon(image, contentDescription = null, tint = scheme.onPrimaryContainer, modifier = modifier)
}

/** Abschnittskopf: Zähler-Label + Aktion (wie andere Paket-Screens). */
@Composable
private fun SectionHeadRow(
    label: String,
    action: String,
    onAction: () -> Unit,
) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        SectionLabel(label, modifier = Modifier.weight(1f))
        TextButton(onClick = onAction) { Text(action) }
    }
}

/** Kompakte Nachrichtenzeile (Autor, Zeit, Text). */
@Composable
private fun MessageRow(msg: MessageDto) {
    val scheme = MaterialTheme.colorScheme
    EduCard(modifier = Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(
                msg.author.ifBlank { "–" },
                fontSize = 15.sp,
                fontWeight = FontWeight.SemiBold,
                color = scheme.onSurface,
            )
            Text(
                listOf(msg.timestamp, msg.type_label).filter { it.isNotBlank() }.joinToString(" · "),
                fontSize = 13.sp,
                color = scheme.onSurfaceVariant,
            )
            Text(
                msg.text.take(220) + if (msg.text.length > 220) "…" else "",
                style = MaterialTheme.typography.bodyMedium,
                color = scheme.onSurface,
            )
        }
    }
}

/** Kompakte Hausaufgabenzeile (Titel, Status, fällig). */
@Composable
private fun HomeworkRow(hw: HomeworkDto) {
    val scheme = MaterialTheme.colorScheme
    EduCard(modifier = Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(
                hw.title.ifBlank { "Hausaufgabe #${hw.id}" },
                fontSize = 15.sp,
                fontWeight = FontWeight.SemiBold,
                color = scheme.onSurface,
            )
            Text(
                "${hw.status}" + (if (hw.due_display.isNotBlank()) " · fällig: ${hw.due_display}" else "") +
                    (if (hw.subject.isNotBlank()) " · ${hw.subject}" else ""),
                fontSize = 13.sp,
                color = scheme.onSurfaceVariant,
            )
        }
    }
}

/** Essens-Pager (‹ ›-Blätterer, Mo–Fr, wie im Web). */
@Composable
private fun EssenPager(
    label: String,
    sourceUrl: String,
    cacheInfo: String,
    dayName: String,
    date: String,
    dishes: List<de.eduflow.android.data.dto.EssenDish>,
    note: String,
    canPrev: Boolean,
    canNext: Boolean,
    onPrev: () -> Unit,
    onNext: () -> Unit,
) {
    val scheme = MaterialTheme.colorScheme
    EduCard(modifier = Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            if (label.isNotBlank()) {
                Text(
                    label,
                    style = MaterialTheme.typography.labelMedium,
                    color = scheme.onSurfaceVariant,
                )
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                IconButton(onClick = onPrev, enabled = canPrev) {
                    Icon(Icons.Filled.ChevronLeft, contentDescription = "Vorheriger Tag")
                }
                Text(
                    "$dayName${if (date.isNotBlank()) " · $date" else ""}",
                    fontSize = 15.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = scheme.onSurface,
                    modifier = Modifier.weight(1f),
                )
                IconButton(onClick = onNext, enabled = canNext) {
                    Icon(Icons.Filled.ChevronRight, contentDescription = "Nächster Tag")
                }
            }
            if (dishes.isEmpty()) {
                Text(
                    "Kein Essen für diesen Tag.",
                    style = MaterialTheme.typography.bodyMedium,
                    color = scheme.onSurfaceVariant,
                )
            } else {
                dishes.forEach { dish ->
                    Text(
                        "• ${dish.text}" + (if (dish.price.isNotBlank()) " — ${dish.price}" else ""),
                        style = MaterialTheme.typography.bodyMedium,
                        color = scheme.onSurface,
                    )
                }
            }
            if (note.isNotBlank()) {
                Text(
                    note,
                    style = MaterialTheme.typography.bodySmall,
                    color = scheme.onSurfaceVariant,
                )
            }
            if (sourceUrl.isNotBlank()) {
                Text(
                    "PDF-Link vorhanden",
                    style = MaterialTheme.typography.labelSmall,
                    color = scheme.onSurfaceVariant,
                )
            }
            if (cacheInfo.isNotBlank()) {
                Text(
                    cacheInfo,
                    style = MaterialTheme.typography.labelSmall,
                    color = scheme.onSurfaceVariant,
                )
            }
        }
    }
}
