package de.eduflow.android.ui.grades

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import de.eduflow.android.R
import de.eduflow.android.data.dto.ErrorCodes
import de.eduflow.android.data.dto.GradeDto
import de.eduflow.android.data.dto.GradeSubjectGroup
import de.eduflow.android.data.dto.SUBJECT_OTHER_DE
import de.eduflow.android.data.dto.displayGradeTermLabel
import de.eduflow.android.ui.common.AppHeader
import de.eduflow.android.ui.common.EduCard
import de.eduflow.android.ui.common.FilterChips
import de.eduflow.android.ui.common.ScreenHead
import de.eduflow.android.ui.common.SearchPill
import de.eduflow.android.ui.common.SectionLabel
import de.eduflow.android.ui.common.StatusPill
import de.eduflow.android.ui.theme.LocalEduFlowDark
import de.eduflow.android.ui.theme.GradeAmber
import de.eduflow.android.ui.theme.GradeBlue
import de.eduflow.android.ui.theme.GradeGray
import de.eduflow.android.ui.theme.GradeGreen
import de.eduflow.android.ui.theme.GradeRed
import de.eduflow.android.ui.timetable.AuthAwareError
import de.eduflow.android.ui.timetable.localizedApiMessage

/**
 * Noten-Screen (Paket E, Redesign-PNG Screen 04).
 *
 * Header, Titel „Noten" + „Deine Leistungen nach Fach", Schnitt-Karte
 * in Primär-Farbe (Light schwarz / Dark weiß): „GESAMTSCHNITT" + Wert
 * groß + „Deine Noten im Überblick". Suche, Halbjahr-Chips (falls
 * mehrere), Label „FÄCHER", Zeilen: Fach + neueste „Art · Datum"
 * links, Noten-Pill rechts; Tap klappt die Fachdetails auf (alle
 * Noten mit Gewichtung, Lehrer, Klasse Ø, Kommentar). Fuß „Zuletzt
 * synchronisierte Einträge". Schnitt/Gruppierung/Suche/Halbjahre wie
 * Web-noten() (Logik im ViewModel, hier nur Anzeige).
 */
@Composable
fun GradesScreen(
    viewModel: GradesViewModel,
    onReLogin: () -> Unit = {},
    onOpenSettings: () -> Unit = {},
    onLogout: () -> Unit = {},
    modifier: Modifier = Modifier,
) {
    val state by viewModel.state.collectAsState()
    // Schnitt-Karte kollabiert beim Scrollen, damit die Noten Platz haben.
    val listState = rememberLazyListState()
    val collapseTarget =
        if (listState.firstVisibleItemIndex > 0 || listState.firstVisibleItemScrollOffset > 60) 1f else 0f
    val collapseFraction by animateFloatAsState(collapseTarget, tween(220), label = "avg-collapse")

    Column(modifier = modifier.fillMaxSize().padding(16.dp)) {
        AppHeader(
            onSettings = onOpenSettings,
            onLogout = onLogout,
        )
        Spacer(Modifier.height(12.dp))
        ScreenHead(
            title = stringResource(R.string.grades_title),
            subtitle = stringResource(R.string.grades_subtitle),
        )
        Spacer(Modifier.height(12.dp))
        AverageCard(avgDisplay = state.avgDisplay, compactFraction = collapseFraction)
        Spacer(Modifier.height(12.dp))
        SearchPill(
            value = state.query,
            onValueChange = viewModel::onQuery,
            placeholder = stringResource(R.string.grades_search_placeholder),
        )
        if (state.terms.size > 1) {
            Spacer(Modifier.height(10.dp))
            // Anzeige lokalisiert, Abgleich über dieselben Ressourcen-Strings (sprachunabhängig).
            val allLabel = stringResource(R.string.grades_term_all)
            val termFormat = stringResource(R.string.grades_term_label_format)
            val labelByKeyLocalized = state.terms.associate { term ->
                term.key to stringResource(
                    R.string.grades_term_format,
                    displayGradeTermLabel(term.key, allLabel, termFormat),
                    term.count,
                )
            }
            val labels = state.terms.map { labelByKeyLocalized[it.key].orEmpty() }
            val selected = labelByKeyLocalized[state.term].orEmpty()
            FilterChips(
                options = labels,
                selected = selected,
                onSelect = { label ->
                    labelByKeyLocalized.entries.firstOrNull { it.value == label }
                        ?.let { viewModel.onTerm(it.key) }
                },
            )
        }
        Spacer(Modifier.height(4.dp))
        Row(verticalAlignment = Alignment.CenterVertically) {
            SectionLabel(
                stringResource(R.string.grades_section_subjects),
                modifier = Modifier.weight(1f),
            )
            IconButton(onClick = viewModel::refresh, enabled = !state.isLoading) {
                Icon(Icons.Filled.Refresh, contentDescription = stringResource(R.string.common_refresh_desc))
            }
        }
        if (state.cacheInfo.isNotBlank()) {
            Text(
                state.cacheInfo,
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        Spacer(Modifier.height(4.dp))

        state.error?.let { err ->
            AuthAwareError(
                message = "${localizedApiMessage(err.code, err.message, err.messageRes)} (${err.code})",
                needsReLogin = err.code in
                    listOf(ErrorCodes.TOKEN_INVALID, ErrorCodes.TOKEN_EXPIRED, ErrorCodes.EDUPAGE_2FA),
                onReLogin = onReLogin,
                onDismiss = viewModel::dismissError,
                modifier = Modifier.padding(bottom = 8.dp),
            )
        }

        if (state.isLoading && state.allItems.isEmpty()) {
            Row(
                modifier = Modifier.fillMaxWidth().padding(32.dp),
                horizontalArrangement = Arrangement.Center,
            ) { CircularProgressIndicator() }
        } else if (state.groups.isEmpty()) {
            Column(
                modifier = Modifier.fillMaxWidth().padding(24.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Text(
                    stringResource(R.string.grades_empty),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                TextButton(onClick = viewModel::refresh) { Text(stringResource(R.string.common_reload)) }
            }
        } else {
            LazyColumn(
                state = listState,
                verticalArrangement = Arrangement.spacedBy(10.dp),
                modifier = Modifier.weight(1f),
            ) {
                items(state.groups, key = { it.subject }) { group ->
                    SubjectRow(group = group)
                }
                if (state.canLoadMore) {
                    item {
                        TextButton(
                            onClick = viewModel::loadMore,
                            enabled = !state.isLoadingMore,
                            modifier = Modifier.fillMaxWidth(),
                        ) {
                            if (state.isLoadingMore) {
                                CircularProgressIndicator(
                                    modifier = Modifier.size(16.dp).padding(end = 8.dp),
                                )
                            }
                            Text(stringResource(R.string.common_load_more_format, state.allItems.size, state.total))
                        }
                    }
                }
                item {
                    Text(
                        stringResource(R.string.grades_footer),
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.fillMaxWidth().padding(vertical = 8.dp),
                    )
                }
                item { Spacer(Modifier.height(88.dp)) }
            }
        }
    }
}

/** Schnitt-Karte: Light Primär (PNG-schwarz), Dark schwarz statt weißer Fläche.
 * Kollabiert beim Scrollen (compactFraction 0..1): Zahl 34→20sp, weniger
 * Padding, Untertitel blendet aus. */
@Composable
private fun AverageCard(avgDisplay: String, compactFraction: Float = 0f) {
    val scheme = MaterialTheme.colorScheme
    // Wie NowCard auf der Übersicht: Dark schwarze Karte statt weißer
    // Primär-Fläche, weiße Schrift dazu statt onPrimary.
    val dark = LocalEduFlowDark.current
    val cardColor = if (dark) Color.Black else scheme.primary
    val contentColor = if (dark) Color.White else scheme.onPrimary
    val f = compactFraction.coerceIn(0f, 1f)
    Surface(
        shape = RoundedCornerShape(16.dp),
        color = cardColor,
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(Modifier.padding(horizontal = 20.dp, vertical = (20 - 8 * f).dp)) {
            Text(
                stringResource(R.string.grades_avg_title),
                fontSize = 11.sp,
                fontWeight = FontWeight.Bold,
                letterSpacing = 1.2.sp,
                color = contentColor.copy(alpha = 0.7f),
            )
            Spacer(Modifier.height((4 - 2 * f).dp.coerceAtLeast(0.dp)))
            Text(
                avgDisplay,
                fontSize = (34 - 14 * f).sp,
                fontWeight = FontWeight.ExtraBold,
                color = contentColor,
            )
            if (f < 0.5f) {
                Spacer(Modifier.height(2.dp))
                Text(
                    stringResource(R.string.grades_avg_sub),
                    fontSize = 13.sp,
                    color = contentColor.copy(alpha = 0.7f),
                )
            }
        }
    }
}

/** Fach-Zeile: Fach + neueste „Art · Datum", Pill rechts, Tap = Details. */
@Composable
private fun SubjectRow(group: GradeSubjectGroup) {
    var expanded by remember(group.subject) { mutableStateOf(false) }
    val scheme = MaterialTheme.colorScheme
    // Gruppierungs-Fallback lokalisieren (Server/DTO liefern "Sonstiges").
    val subjectLabel =
        if (group.subject == SUBJECT_OTHER_DE) stringResource(R.string.grades_subject_other)
        else group.subject
    val newest = group.items.firstOrNull()
    val newestLine = newestSub(newest)
    val countLine = pluralStringResource(
        R.plurals.grades_notes_count,
        group.items.size,
        group.avgDisplay,
        group.items.size,
    )
    EduCard(
        onClick = { expanded = !expanded },
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(Modifier.fillMaxWidth().padding(16.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text(
                        subjectLabel,
                        fontSize = 15.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = scheme.onSurface,
                    )
                    Spacer(Modifier.height(2.dp))
                    Text(
                        newestLine,
                        fontSize = 13.sp,
                        color = scheme.onSurfaceVariant,
                    )
                }
                Spacer(Modifier.width(8.dp))
                StatusPill(
                    text = newest?.grade_display?.ifBlank { "–" } ?: "–",
                    dot = badgeColor(newest?.badge),
                )
            }
            if (expanded) {
                Spacer(Modifier.height(12.dp))
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(
                        countLine,
                        style = MaterialTheme.typography.labelMedium,
                        color = scheme.onSurfaceVariant,
                    )
                    group.items.forEach { grade ->
                        GradeDetailRow(grade = grade)
                    }
                }
            }
        }
    }
}

@Composable
private fun newestSub(grade: GradeDto?): String {
    if (grade == null) return stringResource(R.string.grades_no_grade)
    val title = grade.title.ifBlank { stringResource(R.string.grades_grade_fallback) }
    val date = grade.date_display.ifBlank { "–" }
    return "$title · $date"
}

// Noten-Chip wie im Web (.chip): farbiger Grund, weißer fetter Text.
@Composable
private fun GradeChip(grade: GradeDto) {
    Surface(
        shape = RoundedCornerShape(10.dp),
        color = badgeColor(grade.badge),
    ) {
        Text(
            grade.grade_display +
                (if (grade.weight_display.isNotBlank()) " ${grade.weight_display}" else ""),
            fontSize = 16.sp,
            fontWeight = FontWeight.ExtraBold,
            color = Color.White,
            modifier = Modifier.padding(horizontal = 10.dp, vertical = 6.dp),
        )
    }
}

private fun badgeColor(badge: String?): Color = when (badge) {
    "g12" -> GradeGreen
    "g3" -> GradeBlue
    "g4" -> GradeAmber
    "g56" -> GradeRed
    else -> GradeGray
}

@Composable
private fun GradeDetailRow(grade: GradeDto) {
    val noteFallback = stringResource(R.string.grades_grade_fallback)
    val weightDefault = stringResource(R.string.grades_weight_default)
    val teacherText = if (grade.teacher.isNotBlank()) stringResource(R.string.grades_teacher_format, grade.teacher) else ""
    val classAvgText = if (grade.class_avg_display.isNotBlank()) stringResource(R.string.grades_class_avg_format, grade.class_avg_display) else ""
    Surface(
        shape = RoundedCornerShape(12.dp),
        color = MaterialTheme.colorScheme.surfaceVariant,
        modifier = Modifier.fillMaxWidth(),
    ) {
        Row(
            verticalAlignment = Alignment.Top,
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            modifier = Modifier.padding(10.dp),
        ) {
            GradeChip(grade = grade)
            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(grade.title.ifBlank { noteFallback }, fontWeight = FontWeight.SemiBold)
                Text(
                    "${grade.date_display.ifBlank { "–" }}" +
                        (if (grade.grade_sub.isNotBlank()) " · ${grade.grade_sub}" else "") +
                        stringResource(R.string.grades_weight_format, grade.weight_display.ifBlank { weightDefault }),
                    style = MaterialTheme.typography.bodySmall,
                )
                val meta = buildString {
                    if (teacherText.isNotBlank()) append(teacherText)
                    if (classAvgText.isNotBlank()) {
                        if (isNotEmpty()) append(" · ")
                        append(classAvgText)
                    }
                    if (grade.comment.isNotBlank()) {
                        if (isNotEmpty()) append(" · ")
                        append(grade.comment)
                    }
                }
                if (meta.isNotEmpty()) {
                    Text(meta, style = MaterialTheme.typography.bodySmall)
                }
            }
        }
    }
}

/** Convenience-Überladung für Previews/Tests ohne manuelles ViewModel. */
@Composable
fun GradesScreenPreviewContent(groups: List<GradeSubjectGroup>) {
    LazyColumn(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        items(groups, key = { it.subject }) { group ->
            SubjectRow(group = group)
        }
    }
}
