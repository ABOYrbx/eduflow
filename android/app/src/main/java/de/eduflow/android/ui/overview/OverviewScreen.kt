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
import androidx.compose.material.ExperimentalMaterialApi
import androidx.compose.material.pullrefresh.PullRefreshIndicator
import androidx.compose.material.pullrefresh.pullRefresh
import androidx.compose.material.pullrefresh.rememberPullRefreshState
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import de.eduflow.android.R
import de.eduflow.android.data.dto.ErrorCodes
import de.eduflow.android.data.dto.EssenDays
import de.eduflow.android.data.dto.HomeworkDto
import de.eduflow.android.data.dto.LessonDto
import de.eduflow.android.data.dto.MessageDto
import de.eduflow.android.ui.common.AppHeader
import de.eduflow.android.ui.common.EduCard
import de.eduflow.android.ui.common.ScreenHead
import de.eduflow.android.ui.common.SectionLabel
import de.eduflow.android.ui.theme.LocalEduFlowDark
import de.eduflow.android.ui.timetable.AuthAwareError
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.format.DateTimeFormatter
import java.util.Locale
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
 * Listen; 401-Verhalten → Login. Aktualisieren läuft über
 * Pull-to-Refresh (von oben ziehen) über den gesamten Inhalt.
 */
@OptIn(ExperimentalMaterialApi::class)
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
    // Wochentag immer deutsch (System-Sprache wird ignoriert, wie macOS
    // mit de_DE); Muster kommt aus strings.xml und ist damit via Crowdin
    // pro Sprache anpassbar.
    val datePattern = stringResource(R.string.home_date_format)
    val todayLabel = remember(datePattern) {
        try {
            LocalDate.now().format(DateTimeFormatter.ofPattern(datePattern, Locale.GERMAN))
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
        ScreenHead(title = stringResource(R.string.bottom_home), subtitle = todayLabel)
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
            val pullState = rememberPullRefreshState(
                refreshing = state.isLoading,
                onRefresh = viewModel::refresh,
            )
            Box(modifier = Modifier.weight(1f).pullRefresh(pullState)) {
                LazyColumn(
                    verticalArrangement = Arrangement.spacedBy(10.dp),
                    modifier = Modifier.fillMaxSize(),
                ) {
                item { LiveClockCard() }
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
                PullRefreshIndicator(
                    refreshing = state.isLoading,
                    state = pullState,
                    modifier = Modifier.align(Alignment.TopCenter),
                )
            }
        }
    }
}

@Composable
private fun MessagesOverviewSection(messages: List<MessageDto>, total: Int, onMessages: () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        SectionHeadRow(
            label = stringResource(R.string.overview_messages_count_format, total),
            action = stringResource(R.string.overview_action_all),
            onAction = onMessages,
        )
        if (messages.isEmpty()) {
            Text(
                stringResource(R.string.overview_messages_empty),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(horizontal = 4.dp),
            )
        } else messages.forEach { MessageRow(msg = it) }
    }
}

@Composable
private fun HomeworkOverviewSection(
    homework: List<HomeworkDto>, counts: de.eduflow.android.data.dto.HomeworkCounts, onHomework: () -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        SectionHeadRow(
            label = stringResource(R.string.overview_homework_count_format, counts.offen, counts.ueberfaellig),
            action = stringResource(R.string.overview_action_all_tasks),
            onAction = onHomework,
        )
        if (homework.isEmpty()) {
            Text(
                stringResource(R.string.overview_homework_empty),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(horizontal = 4.dp),
            )
        } else homework.forEach { HomeworkRow(hw = it) }
    }
}

@Composable
private fun LunchOverviewSection(state: OverviewUiState, viewModel: OverviewViewModel, onTimetable: () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        SectionHeadRow(
            label = stringResource(R.string.overview_section_lunch),
            action = stringResource(R.string.overview_action_timetable),
            onAction = onTimetable,
        )
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

/** Uhr-Karte (live, jede Sekunde, deutsches Format). */
@Composable
private fun LiveClockCard() {
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
                    stringResource(R.string.overview_clock_label),
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
    // Dark: schwarze Karte statt weißer Primär-Fläche (Light bleibt
    // PNG-schwarz) — weiße Schrift dazu statt onPrimary.
    val dark = LocalEduFlowDark.current
    val cardColor = if (dark) Color.Black else scheme.primary
    val contentColor = if (dark) Color.White else scheme.onPrimary
    Surface(
        shape = RoundedCornerShape(16.dp),
        color = cardColor,
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(
                stringResource(R.string.overview_today_hours),
                fontSize = 11.sp,
                fontWeight = FontWeight.Bold,
                letterSpacing = 1.2.sp,
                color = contentColor.copy(alpha = 0.7f),
            )
            if (current == null && next == null) {
                Text(
                    stringResource(R.string.overview_no_school),
                    fontSize = 15.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = contentColor,
                )
            } else {
                current?.let {
                    Text(
                        stringResource(R.string.overview_now_format, it.title, it.period, it.time),
                        fontSize = 15.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = contentColor,
                    )
                }
                next?.let {
                    Text(
                        if (it.rooms.isNotBlank()) stringResource(
                            R.string.overview_next_room_format,
                            it.title,
                            it.period,
                            it.time,
                            it.rooms,
                        )
                        else stringResource(R.string.overview_next_format, it.title, it.period, it.time),
                        fontSize = 13.sp,
                        color = contentColor.copy(alpha = 0.75f),
                    )
                }
            }
            TextButton(
                onClick = onTimetable,
                colors = ButtonDefaults.textButtonColors(
                    contentColor = contentColor,
                ),
            ) { Text(stringResource(R.string.overview_action_timetable)) }
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
                        stringResource(R.string.overview_weather_title),
                        fontSize = 11.sp,
                        fontWeight = FontWeight.Bold,
                        letterSpacing = 1.2.sp,
                        color = scheme.onSurfaceVariant,
                    )
                    Text(
                        wetter?.city?.ifBlank { city }?.ifBlank { stringResource(R.string.overview_weather_default_city) }
                            ?: stringResource(R.string.overview_weather_default_title),
                        fontSize = 16.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = scheme.onSurface,
                    )
                }
                IconButton(onClick = onLoad, enabled = !loading && city.isNotBlank()) {
                    if (loading) {
                        CircularProgressIndicator(modifier = Modifier.size(20.dp), strokeWidth = 2.dp)
                    } else {
                        Icon(Icons.Filled.Refresh, contentDescription = stringResource(R.string.overview_weather_refresh_desc))
                    }
                }
            }
            if (wetter == null) {
                if (city.isBlank()) {
                    Text(
                        stringResource(R.string.overview_weather_set_location),
                        fontSize = 13.sp,
                        color = scheme.onSurfaceVariant,
                    )
                    TextButton(onClick = onConfigure) { Text(stringResource(R.string.overview_weather_set_location_action)) }
                } else {
                    Text(
                        error ?: stringResource(R.string.overview_weather_loading_format, city),
                        fontSize = 13.sp,
                        color = if (error != null) scheme.error else scheme.onSurfaceVariant,
                    )
                    TextButton(onClick = onLoad, enabled = !loading) {
                        Text(
                            if (loading) stringResource(R.string.overview_weather_loading)
                            else stringResource(R.string.overview_weather_retry),
                        )
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
                                    stringResource(R.string.overview_weather_today_label),
                                    modifier = Modifier.padding(bottom = 7.dp),
                                    fontSize = 10.sp,
                                    fontWeight = FontWeight.Bold,
                                    letterSpacing = 1.sp,
                                    color = scheme.onPrimaryContainer.copy(alpha = 0.65f),
                                )
                            }
                            Text(
                                t.desc.replaceFirstChar { it.uppercase() }.ifBlank { stringResource(R.string.overview_weather_current_fallback) },
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
                        label = stringResource(R.string.overview_weather_rain),
                        value = t.pop?.let { "$it %" } ?: "–",
                        icon = Icons.Filled.WaterDrop,
                        modifier = Modifier.weight(1f),
                    )
                    WetterMetric(
                        label = stringResource(R.string.overview_weather_feels),
                        value = wetter.details.feels_like?.let { "$it°" } ?: "–",
                        icon = Icons.Filled.WbSunny,
                        modifier = Modifier.weight(1f),
                    )
                    WetterMetric(
                        label = stringResource(R.string.overview_weather_wind),
                        value = wetter.details.wind_kmh?.let { "$it km/h" } ?: "–",
                        icon = Icons.Filled.Cloud,
                        modifier = Modifier.weight(1f),
                    )
                }

                Text(
                    stringResource(R.string.overview_weather_next_days),
                    fontSize = 10.sp,
                    fontWeight = FontWeight.Bold,
                    letterSpacing = 1.1.sp,
                    color = scheme.onSurfaceVariant,
                )
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    WetterForecastDay(
                        label = stringResource(R.string.overview_weather_today),
                        icon = t.icon,
                        high = t.max,
                        low = t.min,
                        modifier = Modifier.weight(1f),
                    )
                    WetterForecastDay(
                        label = wetter.tomorrow.label.ifBlank { stringResource(R.string.overview_weather_tomorrow) },
                        icon = wetter.tomorrow.icon,
                        high = wetter.tomorrow.max,
                        low = wetter.tomorrow.min,
                        modifier = Modifier.weight(1f),
                    )
                    WetterForecastDay(
                        label = wetter.day3.label.ifBlank { stringResource(R.string.overview_weather_day3) },
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
    val titleFallback = stringResource(R.string.homework_title_format, hw.id)
    val dueSuffix = if (hw.due_display.isNotBlank()) stringResource(R.string.overview_due_suffix_format, hw.due_display) else ""
    val subjectSuffix = if (hw.subject.isNotBlank()) stringResource(R.string.overview_subject_suffix_format, hw.subject) else ""
    EduCard(modifier = Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(
                hw.title.ifBlank { titleFallback },
                fontSize = 15.sp,
                fontWeight = FontWeight.SemiBold,
                color = scheme.onSurface,
            )
            Text(
                "${hw.status}" + dueSuffix + subjectSuffix,
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
                    Icon(Icons.Filled.ChevronLeft, contentDescription = stringResource(R.string.overview_prev_day_desc))
                }
                Text(
                    if (date.isNotBlank()) stringResource(R.string.overview_day_date_format, dayName, date) else dayName,
                    fontSize = 15.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = scheme.onSurface,
                    modifier = Modifier.weight(1f),
                )
                IconButton(onClick = onNext, enabled = canNext) {
                    Icon(Icons.Filled.ChevronRight, contentDescription = stringResource(R.string.overview_next_day_desc))
                }
            }
            if (dishes.isEmpty()) {
                Text(
                    stringResource(R.string.overview_no_food),
                    style = MaterialTheme.typography.bodyMedium,
                    color = scheme.onSurfaceVariant,
                )
            } else {
                dishes.forEach { dish ->
                    val priceSuffix = if (dish.price.isNotBlank()) stringResource(R.string.overview_dish_price_format, dish.price) else ""
                    Text(
                        stringResource(R.string.overview_dish_format, dish.text) + priceSuffix,
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
                    stringResource(R.string.overview_pdf_available),
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
