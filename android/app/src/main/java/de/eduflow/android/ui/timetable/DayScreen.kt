package de.eduflow.android.ui.timetable

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ChevronLeft
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Snackbar
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import de.eduflow.android.R
import de.eduflow.android.data.dto.ErrorCodes
import de.eduflow.android.data.dto.LessonDto
import de.eduflow.android.data.dto.TimetableView
import de.eduflow.android.ui.common.AppHeader
import de.eduflow.android.ui.common.EduCard
import de.eduflow.android.ui.common.ScreenHead
import de.eduflow.android.ui.common.SectionLabel
import de.eduflow.android.ui.common.StatusPill
import de.eduflow.android.ui.theme.RDotBlue
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.LocalTime

/**
 * Tagesansicht (Paket D, Redesign-PNG Screen 03).
 *
 * Header, Titel „Stundenplan" + Datum als Untertitel, Segmented
 * Tag/Woche, Tages-Kopf (Datum + „N STUNDEN") mit ‹ ›-Blättern,
 * „Heute"-Zeile mit Chevron, Stunden-Zeilen: Startzeit links grau,
 * Trennstrich, Fach fett + „Lehrer · Raum" darunter, „JETZT"-Pill an
 * der laufenden Stunde (nur wenn der angezeigte Tag heute ist).
 * Entfallene Stunden stehen als ausgegraute Einzeiler
 * („08:00 · Sport entfällt"). Tag-Navi: ‹ › (±1 Tag, ±7 in der Woche)
 * + Heute-Zeile. Logik (Tag/Woche, Paginierung gibt es keine,
 * refresh=1) wie im Web.
 */
@Composable
fun DayScreen(
    viewModel: TimetableViewModel,
    onReLogin: () -> Unit,
    onOpenSettings: () -> Unit = {},
    onLogout: () -> Unit = {},
    modifier: Modifier = Modifier,
) {
    val state by viewModel.state.collectAsState()
    val day = state.dayData
    val isTodayShown = day != null &&
        (day.day == day.today || day.day == LocalDate.now().toString())
    val nowUid = if (isTodayShown && day != null) runningUid(day.lessons) else null

    Column(modifier = modifier.fillMaxSize().padding(16.dp).swipeToStep(viewModel::step)) {
        AppHeader(
            onSettings = onOpenSettings,
            onLogout = onLogout,
        )
        Spacer(Modifier.height(12.dp))
        ScreenHead(
            title = stringResource(R.string.timetable_title),
            subtitle = day?.day_label ?: state.day,
        )
        Spacer(Modifier.height(12.dp))
        TimetableSegmented(view = state.view, onView = viewModel::setView)
        Spacer(Modifier.height(12.dp))

        DayHeadRow(
            label = day?.day_label ?: state.day,
            count = if (day != null) stringResource(R.string.timetable_day_count_format, day.lessons.size) else "",
            onPrev = { viewModel.step(-1) },
            onNext = { viewModel.step(1) },
            onRefresh = viewModel::refresh,
            refreshing = state.isLoading,
        )
        Spacer(Modifier.height(8.dp))
        TodayRow(onClick = viewModel::goToday)
        if (day != null && day.cache_info.isNotBlank()) {
            Spacer(Modifier.height(4.dp))
            Text(
                day.cache_info,
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        Spacer(Modifier.height(4.dp))

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

        if (state.isLoading && day == null) {
            Row(
                modifier = Modifier.fillMaxWidth().padding(32.dp),
                horizontalArrangement = Arrangement.Center,
            ) { CircularProgressIndicator() }
        } else if (day == null) {
            Column(
                modifier = Modifier.fillMaxWidth().padding(24.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Text(
                    stringResource(R.string.timetable_empty_day),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                TextButton(onClick = viewModel::refresh) { Text(stringResource(R.string.common_reload)) }
            }
        } else if (day.lessons.isEmpty()) {
            Column(
                modifier = Modifier.fillMaxWidth().padding(24.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Text(
                    if (isWeekend(state.day)) stringResource(R.string.timetable_no_lessons_weekend)
                    else stringResource(R.string.timetable_no_lessons),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                TextButton(onClick = viewModel::refresh) { Text(stringResource(R.string.common_reload)) }
            }
        } else {
            LazyColumn(
                verticalArrangement = Arrangement.spacedBy(10.dp),
                modifier = Modifier.weight(1f),
            ) {
                items(day.lessons, key = { it.period + it.time + it.title }) { lesson ->
                    LessonCard(
                        lesson = lesson,
                        isNow = lessonKey(lesson) == nowUid,
                    )
                }
                item { Spacer(Modifier.height(88.dp)) }
            }
        }
    }
}

/** Tages-Kopf: ‹ Label + Zähler › + Aktualisieren (PNG Screen 03). */
@Composable
fun DayHeadRow(
    label: String,
    count: String,
    onPrev: () -> Unit,
    onNext: () -> Unit,
    onRefresh: () -> Unit,
    refreshing: Boolean,
) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        IconButton(onClick = onPrev) {
            Icon(Icons.Filled.ChevronLeft, contentDescription = stringResource(R.string.common_back))
        }
        Column(Modifier.weight(1f)) {
            Text(
                label,
                fontSize = 15.sp,
                fontWeight = FontWeight.SemiBold,
                color = MaterialTheme.colorScheme.onBackground,
            )
            if (count.isNotBlank()) SectionLabel(count)
        }
        IconButton(onClick = onRefresh, enabled = !refreshing) {
            Icon(Icons.Filled.Refresh, contentDescription = stringResource(R.string.common_refresh_desc))
        }
        IconButton(onClick = onNext) {
            Icon(Icons.Filled.ChevronRight, contentDescription = stringResource(R.string.common_next))
        }
    }
}

/** „Heute"-Zeile mit Chevron (PNG Screen 03, springt auf heute). */
@Composable
fun TodayRow(onClick: () -> Unit) {
    EduCard(onClick = onClick, modifier = Modifier.fillMaxWidth()) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp),
        ) {
            Text(
                stringResource(R.string.timetable_today),
                fontSize = 15.sp,
                fontWeight = FontWeight.SemiBold,
                color = MaterialTheme.colorScheme.onSurface,
                modifier = Modifier.weight(1f),
            )
            Icon(
                Icons.Filled.ChevronRight,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

/** Tag/Woche-Segmented (graue Pille, aktive Hälfte hell, wie im PNG). */
@Composable
fun TimetableSegmented(
    view: String,
    onView: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    val scheme = MaterialTheme.colorScheme
    Surface(
        shape = CircleShape,
        color = scheme.surfaceVariant,
        modifier = modifier.fillMaxWidth(),
    ) {
        Row(modifier = Modifier.padding(4.dp)) {
            SegmentHalf(
                label = stringResource(R.string.timetable_day_tab),
                active = view == TimetableView.DAY,
                onClick = { onView(TimetableView.DAY) },
                modifier = Modifier.weight(1f),
            )
            SegmentHalf(
                label = stringResource(R.string.timetable_week_tab),
                active = view == TimetableView.WEEK,
                onClick = { onView(TimetableView.WEEK) },
                modifier = Modifier.weight(1f),
            )
        }
    }
}

@Composable
private fun SegmentHalf(
    label: String,
    active: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val scheme = MaterialTheme.colorScheme
    Box(
        contentAlignment = Alignment.Center,
        modifier = modifier.clip(CircleShape)
            .background(if (active) scheme.surface else scheme.surfaceVariant)
            .clickable(onClick = onClick)
            .padding(vertical = 8.dp),
    ) {
        Text(
            label,
            fontSize = 13.sp,
            fontWeight = if (active) FontWeight.Bold else FontWeight.SemiBold,
            color = if (active) scheme.onSurface else scheme.onSurfaceVariant,
        )
    }
}

/**
 * Stunden-Zeile wie im PNG: Startzeit links grau, Trennstrich, Fach
 * fett + „Lehrer · Raum"-Sub (Kennzeichen Online/Lernzeit/
 * Veranstaltung als Suffix), „JETZT"-Pill an der laufenden Stunde.
 * Entfall steht als ausgegrauter Einzeiler („08:00 · Sport entfällt").
 */
@Composable
fun LessonCard(
    lesson: LessonDto,
    isNow: Boolean = false,
    modifier: Modifier = Modifier,
) {
    val scheme = MaterialTheme.colorScheme
    val cancelledText = cancelledLine(lesson)
    val lessonSubText = lessonSub(lesson)
    // Stunden-Zeilen grau wie im PNG (surfaceVariant statt Karten-Weiß).
    Surface(
        shape = RoundedCornerShape(16.dp),
        color = scheme.surfaceVariant,
        modifier = modifier.fillMaxWidth(),
    ) {
        if (lesson.is_cancelled) {
            Text(
                cancelledText,
                fontSize = 14.sp,
                color = scheme.onSurfaceVariant,
                modifier = Modifier.fillMaxWidth().padding(16.dp),
            )
        } else {
            Row(
                verticalAlignment = Alignment.Top,
                modifier = Modifier.fillMaxWidth().padding(16.dp),
            ) {
                Text(
                    startOf(lesson.time).ifBlank { "–" },
                    fontSize = 13.sp,
                    color = scheme.onSurfaceVariant,
                    modifier = Modifier.width(52.dp).padding(top = 2.dp),
                )
                Box(
                    modifier = Modifier.width(1.dp)
                        .height(40.dp)
                        .background(scheme.outlineVariant),
                )
                Spacer(Modifier.width(12.dp))
                Column(Modifier.weight(1f)) {
                    Text(
                        lesson.title.ifBlank { "–" },
                        fontSize = 15.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = scheme.onSurface,
                    )
                    Spacer(Modifier.height(2.dp))
                    if (lessonSubText.isNotBlank()) {
                        Text(
                            lessonSubText,
                            fontSize = 13.sp,
                            color = scheme.onSurfaceVariant,
                        )
                    }
                }
                if (isNow) {
                    Spacer(Modifier.width(8.dp))
                    StatusPill(text = stringResource(R.string.timetable_now), dot = RDotBlue)
                }
            }
        }
    }
}

/**
 * Fehler mit 401-Verhalten: abgelaufene/ungültige Sitzung (TOKEN_INVALID,
 * TOKEN_EXPIRED, EDUPAGE_2FA) führt zurück zum Login, alle anderen Fehler
 * sind nur verwerfbar (deutsche Kurztexte, keine Secrets).
 * (Hier definiert, da auch Paket B es von hier importiert.)
 */
@Composable
fun AuthAwareError(
    message: String,
    needsReLogin: Boolean,
    onReLogin: () -> Unit,
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Snackbar(
        action = {
            if (needsReLogin) {
                TextButton(onClick = onReLogin) { Text(stringResource(R.string.common_relogin)) }
            } else {
                TextButton(onClick = onDismiss) { Text(stringResource(R.string.common_ok)) }
            }
        },
        modifier = modifier.padding(bottom = 8.dp),
    ) { Text(message) }
}

/** Eindeutiger Schlüssel einer Stunde (auch paketweit für die Woche). */
internal fun lessonKey(lesson: LessonDto): String =
    lesson.period + lesson.time + lesson.title

/**
 * Horizontal durch Tage/Woche wischen (links = weiter, rechts = zurück) —
 * zusätzlich zu den ‹ ›-Knöpfen im Kopf.
 */
@Composable
internal fun Modifier.swipeToStep(onStep: (Int) -> Unit): Modifier {
    val thresholdPx = with(LocalDensity.current) { 64.dp.toPx() }
    var dragX by remember { mutableFloatStateOf(0f) }
    return this.pointerInput(Unit) {
        detectHorizontalDragGestures(
            onDragStart = { dragX = 0f },
            onDragEnd = {
                when {
                    dragX <= -thresholdPx -> onStep(1)
                    dragX >= thresholdPx -> onStep(-1)
                }
                dragX = 0f
            },
            onDragCancel = { dragX = 0f },
            onHorizontalDrag = { change, dragAmount ->
                change.consume()
                dragX += dragAmount
            },
        )
    }
}

private fun startOf(time: String): String {
    val idx = listOf(time.indexOf('–'), time.indexOf('-')).filter { it >= 0 }.minOrNull()
    return if (idx == null) time.trim() else time.substring(0, idx).trim()
}

@Composable
private fun cancelledLine(lesson: LessonDto): String {
    val start = startOf(lesson.time)
    val title = lesson.title.ifBlank { stringResource(R.string.timetable_lesson_fallback) }
    return if (start.isNotBlank()) stringResource(R.string.timetable_cancelled_with_time, start, title)
    else stringResource(R.string.timetable_cancelled, title)
}

@Composable
private fun lessonSub(lesson: LessonDto): String {
    val roomText = lesson.rooms.takeIf { it.isNotBlank() }?.let { stringResource(R.string.timetable_room_format, it) }.orEmpty()
    val onlineText = if (lesson.is_online) stringResource(R.string.timetable_flag_online) else ""
    val lernzeitText = if (lesson.is_lernzeit) {
        if (lesson.rowspan > 1) stringResource(R.string.timetable_flag_lernzeit_hours, lesson.rowspan)
        else stringResource(R.string.timetable_flag_lernzeit)
    } else ""
    val eventText = if (lesson.is_event) stringResource(R.string.timetable_flag_event) else ""
    val meta = listOfNotNull(
        lesson.teachers.takeIf { it.isNotBlank() },
        roomText.takeIf { it.isNotBlank() },
    ).joinToString(" · ")
    val flags = listOf(onlineText, lernzeitText, eventText).filter { it.isNotBlank() }.joinToString(" · ")
    return listOf(meta, flags).filter { it.isNotBlank() }.joinToString(" · ")
}

/** Laufende Stunde (nicht entfallen) anhand der Uhrzeit, wie Übersicht. */
internal fun runningUid(lessons: List<LessonDto>): String? {
    val now = LocalTime.now().hour * 60 + LocalTime.now().minute
    for (lesson in lessons) {
        if (lesson.is_cancelled) continue
        val (start, end) = rangeOf(lesson.time) ?: continue
        if (start <= now && now <= end) return lessonKey(lesson)
    }
    return null
}

private fun rangeOf(time: String): Pair<Int, Int>? {
    val sep = if ('–' in time) '–' else '-'
    val parts = time.split(sep).map { it.trim() }
    if (parts.size != 2) return null
    val s = parts[0].toMinutesOrNull() ?: return null
    val e = parts[1].toMinutesOrNull() ?: return null
    return s to e
}

private fun String.toMinutesOrNull(): Int? {
    val p = split(':').mapNotNull { it.toIntOrNull() }
    if (p.size != 2) return null
    return p[0] * 60 + p[1]
}

private fun isWeekend(dayIso: String): Boolean = try {
    val dow = LocalDate.parse(dayIso).dayOfWeek
    dow == DayOfWeek.SATURDAY || dow == DayOfWeek.SUNDAY
} catch (_: Exception) {
    false
}
