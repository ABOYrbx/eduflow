package de.eduflow.android.ui.timetable

import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
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
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.res.stringResource
import de.eduflow.android.R
import de.eduflow.android.data.dto.ErrorCodes
import de.eduflow.android.data.dto.TimetableView
import de.eduflow.android.ui.common.AppHeader
import de.eduflow.android.ui.common.ScreenHead
import de.eduflow.android.ui.common.StatusPill
import de.eduflow.android.ui.theme.RDotBlue

/**
 * Wochenansicht (Paket D, Redesign-PNG Screen 03 im gleichen Stil).
 *
 * - Mo–Fr mit denselben Tagesobjekten wie die Tagesansicht
 *   (ganztägige Events herausgefiltert, wie im Web).
 * - Wochen-Navigation (±7 Tage), Heute springt in die aktuelle Woche.
 * - Stunden-Zeilen wie in der Tagesansicht ([LessonCard]), „JETZT"-Pill
 *   in der heutigen Spalte an der laufenden Stunde.
 */
@Composable
fun WeekScreen(
    viewModel: TimetableViewModel,
    onReLogin: () -> Unit,
    onOpenSettings: () -> Unit = {},
    onLogout: () -> Unit = {},
    modifier: Modifier = Modifier,
) {
    val state by viewModel.state.collectAsState()
    val week = state.weekData

    Column(modifier = modifier.fillMaxSize().padding(16.dp).swipeToStep(viewModel::step)) {
        AppHeader(
            onSettings = onOpenSettings,
            onLogout = onLogout,
        )
        Spacer(Modifier.height(12.dp))
        ScreenHead(
            title = stringResource(R.string.timetable_title),
            subtitle = week?.week_label ?: state.day,
        )
        Spacer(Modifier.height(12.dp))
        TimetableSegmented(view = state.view, onView = viewModel::setView)
        Spacer(Modifier.height(12.dp))

        DayHeadRow(
            label = week?.week_label ?: state.day,
            count = if (week != null) {
                stringResource(R.string.timetable_week_count_format, week.days.sumOf { it.lessons.size })
            } else "",
            onPrev = { viewModel.step(-1) },
            onNext = { viewModel.step(1) },
            onRefresh = viewModel::refresh,
            refreshing = state.isLoading,
        )
        Spacer(Modifier.height(8.dp))
        TodayRow(onClick = viewModel::goToday)
        if (week != null && week.cache_info.isNotBlank()) {
            Spacer(Modifier.height(4.dp))
            Text(
                week.cache_info,
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

        if (state.isLoading && week == null) {
            Row(
                modifier = Modifier.fillMaxWidth().padding(32.dp),
                horizontalArrangement = Arrangement.Center,
            ) { CircularProgressIndicator() }
        } else if (week == null) {
            Column(
                modifier = Modifier.fillMaxWidth().padding(24.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Text(
                    stringResource(R.string.timetable_empty_week),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                TextButton(onClick = viewModel::refresh) { Text(stringResource(R.string.common_reload)) }
            }
        } else {
            LazyColumn(
                verticalArrangement = Arrangement.spacedBy(12.dp),
                modifier = Modifier.weight(1f),
            ) {
                items(week.days, key = { it.date }) { day ->
                    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text(
                                "${day.day_name} ${day.day_date}",
                                fontSize = 15.sp,
                                fontWeight = FontWeight.SemiBold,
                                color = if (day.is_today) MaterialTheme.colorScheme.primary
                                else MaterialTheme.colorScheme.onBackground,
                                modifier = Modifier.weight(1f),
                            )
                            if (day.is_today) StatusPill(text = stringResource(R.string.timetable_today), dot = RDotBlue)
                        }
                        if (day.lessons.isEmpty()) {
                            Text(
                                stringResource(R.string.timetable_no_lessons_day),
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        } else {
                            val nowUid =
                                if (day.is_today) runningUid(day.lessons) else null
                            day.lessons.forEach { lesson ->
                                LessonCard(
                                    lesson = lesson,
                                    isNow = lessonKey(lesson) == nowUid,
                                )
                            }
                        }
                    }
                }
                item { Spacer(Modifier.height(88.dp)) }
            }
        }
    }
}

/**
 * Stundenplan-Einstieg mit Tag/Woche-Umschalter (ein Ziel für
 * Routes.TIMETABLE, wie Web /stundenplan?view=).
 */
@Composable
fun TimetableScreen(
    viewModel: TimetableViewModel,
    onReLogin: () -> Unit,
    onOpenSettings: () -> Unit = {},
    onLogout: () -> Unit = {},
    modifier: Modifier = Modifier,
) {
    val state by viewModel.state.collectAsState()
    if (state.view == TimetableView.WEEK) {
        WeekScreen(
            viewModel = viewModel,
            onReLogin = onReLogin,
            onOpenSettings = onOpenSettings,
            onLogout = onLogout,
            modifier = modifier,
        )
    } else {
        DayScreen(
            viewModel = viewModel,
            onReLogin = onReLogin,
            onOpenSettings = onOpenSettings,
            onLogout = onLogout,
            modifier = modifier,
        )
    }
}
