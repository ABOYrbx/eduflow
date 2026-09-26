package de.eduflow.android.ui.school

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.ChevronLeft
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.res.stringResource
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.NavGraphBuilder
import androidx.navigation.compose.composable
import de.eduflow.android.R
import de.eduflow.android.data.ApiService
import de.eduflow.android.data.SchoolRepository
import de.eduflow.android.data.dto.ErrorCodes
import de.eduflow.android.data.dto.SchoolAgendaItemDto
import de.eduflow.android.data.dto.SubstitutionChangeDto
import de.eduflow.android.data.dto.SubstitutionDayDto
import de.eduflow.android.ui.common.AppHeader
import de.eduflow.android.ui.common.EduCard
import de.eduflow.android.ui.common.FilterChips
import de.eduflow.android.ui.common.ScreenHead
import de.eduflow.android.ui.common.SectionLabel
import de.eduflow.android.ui.navigation.Routes
import de.eduflow.android.ui.timetable.AuthAwareError
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.Locale

private enum class SchoolSection {
    AGENDA, SUBSTITUTIONS,
}

private class SchoolViewModelFactory(private val api: () -> ApiService) : ViewModelProvider.Factory {
    @Suppress("UNCHECKED_CAST")
    override fun <T : ViewModel> create(modelClass: Class<T>): T =
        SchoolViewModel(SchoolRepository(api)) as T
}

fun NavGraphBuilder.schoolDestination(
    api: () -> ApiService,
    onReLogin: () -> Unit,
    onOpenSettings: () -> Unit,
    onLogout: () -> Unit,
) {
    composable(Routes.SCHOOL) {
        val vm: SchoolViewModel = viewModel(
            key = "school",
            factory = SchoolViewModelFactory(api),
        )
        SchoolScreen(vm, onReLogin, onOpenSettings, onLogout)
    }
}

@Composable
private fun SchoolScreen(
    viewModel: SchoolViewModel,
    onReLogin: () -> Unit,
    onOpenSettings: () -> Unit,
    onLogout: () -> Unit,
) {
    val state by viewModel.state.collectAsState()
    var section by remember { mutableStateOf(SchoolSection.AGENDA) }
    val dateFormatter = remember { DateTimeFormatter.ofPattern("EEEE, d. MMMM", Locale.GERMAN) }
    val agendaCount = state.agenda.size
    val substitutionCount = state.substitutions.sumOf { it.changes.size }
    val tabCalendar = stringResource(R.string.school_tab_calendar_format, agendaCount)
    val tabSubstitutions = stringResource(R.string.school_tab_substitutions_format, substitutionCount)
    val tabOptions = listOf(tabCalendar, tabSubstitutions)
    val selectedTab = if (section == SchoolSection.AGENDA) tabOptions[0] else tabOptions[1]

    Column(Modifier.fillMaxSize().padding(horizontal = 16.dp)) {
        AppHeader(onSettings = onOpenSettings, onLogout = onLogout)
        Spacer(Modifier.height(10.dp))
        Row(verticalAlignment = Alignment.CenterVertically) {
            ScreenHead(
                title = stringResource(R.string.school_title),
                subtitle = stringResource(R.string.school_subtitle),
                modifier = Modifier.weight(1f),
            )
            IconButton(onClick = { viewModel.load(refresh = true) }, enabled = !state.isLoading) {
                Icon(Icons.Filled.Refresh, contentDescription = stringResource(R.string.common_refresh_desc))
            }
        }
        Spacer(Modifier.height(12.dp))
        FilterChips(
            options = tabOptions,
            selected = selectedTab,
            onSelect = { value ->
                section = if (value == tabCalendar) SchoolSection.AGENDA else SchoolSection.SUBSTITUTIONS
            },
        )
        if (section == SchoolSection.SUBSTITUTIONS) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                IconButton(onClick = { viewModel.load(day = state.selectedDay.minusWeeks(1)) }) {
                    Icon(Icons.Filled.ChevronLeft, contentDescription = stringResource(R.string.school_prev_week_desc))
                }
                Text(
                    text = stringResource(
                        R.string.school_week_format,
                        state.selectedDay.with(java.time.DayOfWeek.MONDAY).format(DateTimeFormatter.ofPattern("dd.MM.yyyy")),
                    ),
                    modifier = Modifier.weight(1f),
                    fontSize = 13.sp,
                    fontWeight = FontWeight.Medium,
                )
                IconButton(onClick = { viewModel.load(day = state.selectedDay.plusWeeks(1)) }) {
                    Icon(Icons.Filled.ChevronRight, contentDescription = stringResource(R.string.school_next_week_desc))
                }
            }
        }
        Spacer(Modifier.height(10.dp))
        state.error?.let { error ->
            AuthAwareError(
                message = error.message,
                needsReLogin = error.code in setOf(
                    ErrorCodes.TOKEN_INVALID, ErrorCodes.TOKEN_EXPIRED, ErrorCodes.EDUPAGE_2FA,
                ),
                onReLogin = onReLogin,
                onDismiss = viewModel::dismissError,
            )
        }
        if (state.isLoading && state.agenda.isEmpty() && state.substitutions.isEmpty()) {
            Row(Modifier.fillMaxWidth().padding(32.dp), horizontalArrangement = Arrangement.Center) {
                CircularProgressIndicator()
            }
        } else if (section == SchoolSection.AGENDA) {
            AgendaList(state.agenda, dateFormatter)
        } else {
            SubstitutionList(state.substitutions, dateFormatter)
        }
    }
}

@Composable
private fun ColumnScope.AgendaList(items: List<SchoolAgendaItemDto>, formatter: DateTimeFormatter) {
    if (items.isEmpty()) {
        EmptyMessage(stringResource(R.string.school_empty_agenda))
        return
    }
    LazyColumn(
        modifier = Modifier.weight(1f),
        verticalArrangement = Arrangement.spacedBy(9.dp),
    ) {
        items(items, key = { "${it.kind}-${it.id}-${it.date}" }) { item ->
            val date = runCatching { LocalDate.parse(item.date) }.getOrNull()
            SectionLabel(
                date?.format(formatter)?.replaceFirstChar { it.uppercase(Locale.GERMAN) } ?: item.date,
                modifier = Modifier.padding(top = 6.dp),
            )
            AgendaCard(item)
        }
        item { Spacer(Modifier.height(88.dp)) }
    }
}

@Composable
private fun AgendaCard(item: SchoolAgendaItemDto) {
    val kindLabel = when (item.kind) {
        "exam" -> stringResource(R.string.school_kind_exam)
        "attendance" -> stringResource(R.string.school_kind_attendance)
        else -> stringResource(R.string.school_kind_default)
    }
    val title = item.title.ifBlank { item.text.ifBlank { item.type_label } }
    EduCard(Modifier.fillMaxWidth()) {
        Column(Modifier.fillMaxWidth().padding(15.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(kindLabel, fontSize = 10.sp, fontWeight = FontWeight.Bold,
                letterSpacing = 1.sp, color = MaterialTheme.colorScheme.primary)
            Text(title, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
            val subtitle = listOf(item.subject, item.type_label, item.author)
                .filter { it.isNotBlank() }.distinct().joinToString(" · ")
            if (subtitle.isNotBlank()) Text(subtitle, fontSize = 12.sp,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
private fun ColumnScope.SubstitutionList(days: List<SubstitutionDayDto>, formatter: DateTimeFormatter) {
    val changes = days.flatMap { it.changes.map { change -> it.date to change } }
    if (changes.isEmpty()) {
        EmptyMessage(stringResource(R.string.school_empty_substitutions))
        return
    }
    LazyColumn(
        modifier = Modifier.weight(1f),
        verticalArrangement = Arrangement.spacedBy(9.dp),
    ) {
        items(changes, key = { "${it.first}-${it.second.schoolClass}-${it.second.lesson}-${it.second.title}" }) { (day, change) ->
            val date = runCatching { LocalDate.parse(day) }.getOrNull()
            SectionLabel(
                date?.format(formatter)?.replaceFirstChar { it.uppercase(Locale.GERMAN) } ?: day,
                modifier = Modifier.padding(top = 6.dp),
            )
            SubstitutionCard(change)
        }
        item { Spacer(Modifier.height(88.dp)) }
    }
}

@Composable
private fun SubstitutionCard(change: SubstitutionChangeDto) {
    val status = when (change.action) {
        "add" -> stringResource(R.string.school_change_add)
        "remove" -> stringResource(R.string.school_change_remove)
        else -> stringResource(R.string.school_change_default)
    }
    EduCard(Modifier.fillMaxWidth()) {
        Row(
            Modifier.fillMaxWidth().padding(15.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Surface(shape = CircleShape, color = MaterialTheme.colorScheme.primary.copy(alpha = .1f)) {
                Text(change.lesson, modifier = Modifier.padding(horizontal = 11.dp, vertical = 8.dp),
                    fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.primary)
            }
            Column(Modifier.weight(1f)) {
                Text(change.title, fontWeight = FontWeight.SemiBold)
                Text(
                    stringResource(R.string.school_class_format, change.schoolClass),
                    fontSize = 12.sp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Text(status, fontSize = 9.sp, fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.error)
        }
    }
}

@Composable
private fun ColumnScope.EmptyMessage(text: String) {
    Column(Modifier.weight(1f).fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center) {
        Text(text, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}
