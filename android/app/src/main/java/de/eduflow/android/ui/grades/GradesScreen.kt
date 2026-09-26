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
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import de.eduflow.android.data.dto.ErrorCodes
import de.eduflow.android.data.dto.GradeDto
import de.eduflow.android.data.dto.GradeSubjectGroup
import de.eduflow.android.ui.common.AppHeader
import de.eduflow.android.ui.common.EduCard
import de.eduflow.android.ui.common.FilterChips
import de.eduflow.android.ui.common.ScreenHead
import de.eduflow.android.ui.common.SearchPill
import de.eduflow.android.ui.common.SectionLabel
import de.eduflow.android.ui.common.StatusPill
import de.eduflow.android.ui.theme.GradeAmber
import de.eduflow.android.ui.theme.GradeBlue
import de.eduflow.android.ui.theme.GradeGray
import de.eduflow.android.ui.theme.GradeGreen
import de.eduflow.android.ui.theme.GradeRed
import de.eduflow.android.ui.timetable.AuthAwareError

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

    Column(modifier = modifier.fillMaxSize().padding(16.dp)) {
        AppHeader(
            onSettings = onOpenSettings,
            onLogout = onLogout,
        )
        Spacer(Modifier.height(12.dp))
        ScreenHead(
            title = "Noten",
            subtitle = "Deine Leistungen nach Fach",
        )
        Spacer(Modifier.height(12.dp))
        AverageCard(avgDisplay = state.avgDisplay)
        Spacer(Modifier.height(12.dp))
        SearchPill(
            value = state.query,
            onValueChange = viewModel::onQuery,
            placeholder = "Fach, Titel oder Lehrkraft",
        )
        if (state.terms.size > 1) {
            Spacer(Modifier.height(10.dp))
            val labels = state.terms.map { "${it.label} (${it.count})" }
            val selected = state.terms.firstOrNull { it.key == state.term }
                ?.let { "${it.label} (${it.count})" }.orEmpty()
            FilterChips(
                options = labels,
                selected = selected,
                onSelect = { label ->
                    state.terms.firstOrNull { "${it.label} (${it.count})" == label }
                        ?.let { viewModel.onTerm(it.key) }
                },
            )
        }
        Spacer(Modifier.height(4.dp))
        Row(verticalAlignment = Alignment.CenterVertically) {
            SectionLabel(
                "Fächer",
                modifier = Modifier.weight(1f),
            )
            IconButton(onClick = viewModel::refresh, enabled = !state.isLoading) {
                Icon(Icons.Filled.Refresh, contentDescription = "Aktualisieren")
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
                message = "${err.message} (${err.code})",
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
                    "Keine Noten in diesem Zeitraum.",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                TextButton(onClick = viewModel::refresh) { Text("Neu laden") }
            }
        } else {
            LazyColumn(
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
                            Text("Mehr laden (${state.allItems.size}/${state.total})")
                        }
                    }
                }
                item {
                    Text(
                        "Zuletzt synchronisierte Einträge",
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

/** Schnitt-Karte in Primär-Farbe (Light schwarz / Dark weiß, wie im PNG). */
@Composable
private fun AverageCard(avgDisplay: String) {
    val scheme = MaterialTheme.colorScheme
    Surface(
        shape = RoundedCornerShape(16.dp),
        color = scheme.primary,
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(Modifier.padding(20.dp)) {
            Text(
                "GESAMTSCHNITT",
                fontSize = 11.sp,
                fontWeight = FontWeight.Bold,
                letterSpacing = 1.2.sp,
                color = scheme.onPrimary.copy(alpha = 0.7f),
            )
            Spacer(Modifier.height(4.dp))
            Text(
                avgDisplay,
                fontSize = 34.sp,
                fontWeight = FontWeight.ExtraBold,
                color = scheme.onPrimary,
            )
            Spacer(Modifier.height(2.dp))
            Text(
                "Deine Noten im Überblick",
                fontSize = 13.sp,
                color = scheme.onPrimary.copy(alpha = 0.7f),
            )
        }
    }
}

/** Fach-Zeile: Fach + neueste „Art · Datum", Pill rechts, Tap = Details. */
@Composable
private fun SubjectRow(group: GradeSubjectGroup) {
    var expanded by remember(group.subject) { mutableStateOf(false) }
    val scheme = MaterialTheme.colorScheme
    val newest = group.items.firstOrNull()
    EduCard(
        onClick = { expanded = !expanded },
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(Modifier.fillMaxWidth().padding(16.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text(
                        group.subject,
                        fontSize = 15.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = scheme.onSurface,
                    )
                    Spacer(Modifier.height(2.dp))
                    Text(
                        newestSub(newest),
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
                        "Ø ${group.avgDisplay} · ${group.items.size} " +
                            if (group.items.size == 1) "Note" else "Noten",
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

private fun newestSub(grade: GradeDto?): String {
    if (grade == null) return "Noch keine Note"
    val title = grade.title.ifBlank { "Note" }
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
                Text(grade.title.ifBlank { "Note" }, fontWeight = FontWeight.SemiBold)
                Text(
                    "${grade.date_display.ifBlank { "–" }}" +
                        (if (grade.grade_sub.isNotBlank()) " · ${grade.grade_sub}" else "") +
                        " · Gewichtung ${grade.weight_display.ifBlank { "×1" }}",
                    style = MaterialTheme.typography.bodySmall,
                )
                val meta = buildString {
                    if (grade.teacher.isNotBlank()) append("Lehrer: ${grade.teacher}")
                    if (grade.class_avg_display.isNotBlank()) {
                        if (isNotEmpty()) append(" · ")
                        append("Klasse Ø ${grade.class_avg_display}")
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
