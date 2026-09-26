package de.eduflow.android.ui.homework

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberSwipeToDismissBoxState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import de.eduflow.android.R
import de.eduflow.android.data.dto.ErrorCodes
import de.eduflow.android.data.dto.HomeworkDto
import de.eduflow.android.data.dto.HomeworkItemStatus
import de.eduflow.android.data.dto.HomeworkStatus
import de.eduflow.android.ui.common.AppHeader
import de.eduflow.android.ui.common.EduCard
import de.eduflow.android.ui.common.FilterChips
import de.eduflow.android.ui.common.ScreenHead
import de.eduflow.android.ui.common.SearchPill
import de.eduflow.android.ui.common.SectionLabel
import de.eduflow.android.ui.common.StatusPill
import de.eduflow.android.ui.theme.RDotBlue
import de.eduflow.android.ui.theme.RDotOrange
import de.eduflow.android.ui.theme.RDotRed
import de.eduflow.android.ui.theme.StatusGreen
import de.eduflow.android.ui.theme.StatusRed
import de.eduflow.android.ui.timetable.AuthAwareError

/** Chips aus dem PNG (Screen 01); Papierkorb läuft über den Button darunter. */
@Composable
private fun chipOptions(): List<Pair<String, String>> = listOf(
    stringResource(R.string.homework_filter_all) to HomeworkStatus.ALLE,
    stringResource(R.string.homework_filter_open) to HomeworkStatus.OFFEN,
    stringResource(R.string.homework_filter_overdue) to HomeworkStatus.UEBERFAELLIG,
    stringResource(R.string.homework_filter_done) to HomeworkStatus.ERLEDIGT,
)

/**
 * Hausaufgaben-Liste (Paket B, Redesign-PNG Screen 01).
 *
 * Header, Titel + Untertitel, Suche, Chips Alle/Offen/Überfällig/Erledigt,
 * Zähler-Zeile („4 OFFEN · 1 ÜBERFÄLLIG"), Karten: Status-Dot links, Titel
 * + „Fällig · Lehrkraft"-Sub, rechts Status-Pill + Kreis-Checkbox
 * (Tap = erledigt/wieder öffnen). Papierkorb über den Button neben dem
 * Zähler (Zurückholen markiert gleichzeitig als offen, wie im Web).
 * Wischen zur Seite legt in den Papierkorb / holt zurück.
 * Filter/Suche/include_tests + Paginierung (limit 50, offset) +
 * Refresh (refresh=1), Parameter wie im Web.
 */
@Composable
fun HomeworkListScreen(
    viewModel: HomeworkViewModel,
    onOpenSettings: () -> Unit = {},
    onLogout: () -> Unit = {},
    onReLogin: () -> Unit = {},
    modifier: Modifier = Modifier,
) {
    val state by viewModel.state.collectAsState()
    val inTrash = state.status == HomeworkStatus.PAPIERKORB

    Column(modifier = modifier.fillMaxSize().padding(16.dp)) {
        AppHeader(
            onSettings = onOpenSettings,
            onLogout = onLogout,
        )
        Spacer(Modifier.height(12.dp))
        ScreenHead(
            title = stringResource(R.string.homework_title),
            subtitle = stringResource(R.string.homework_subtitle),
        )
        Spacer(Modifier.height(12.dp))
        SearchPill(
            value = state.query,
            onValueChange = viewModel::onQuery,
            placeholder = stringResource(R.string.homework_search_placeholder),
        )
        Spacer(Modifier.height(10.dp))
        val chips = chipOptions()
        FilterChips(
            options = chips.map { it.first },
            selected = chips.firstOrNull { it.second == state.status }?.first.orEmpty(),
            onSelect = { label ->
                chips.firstOrNull { it.first == label }?.let { viewModel.onStatus(it.second) }
            },
        )
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                stringResource(R.string.homework_include_tests),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.weight(1f),
            )
            Switch(checked = state.includeTests, onCheckedChange = viewModel::onIncludeTests)
        }
        Row(verticalAlignment = Alignment.CenterVertically) {
            SectionLabel(
                if (inTrash) stringResource(R.string.homework_section_trash_format, state.total)
                else stringResource(R.string.homework_section_open_format, state.counts.offen, state.counts.ueberfaellig),
                modifier = Modifier.weight(1f),
            )
            TextButton(onClick = {
                viewModel.onStatus(if (inTrash) HomeworkStatus.ALLE else HomeworkStatus.PAPIERKORB)
            }) {
                Text(
                    if (inTrash) stringResource(R.string.common_back)
                    else stringResource(R.string.homework_trash_open_format, state.counts.papierkorb),
                )
            }
            IconButton(onClick = viewModel::refresh, enabled = !state.isLoading) {
                Icon(Icons.Filled.Refresh, contentDescription = stringResource(R.string.common_reload))
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

        if (state.isLoading && state.items.isEmpty()) {
            Row(
                modifier = Modifier.fillMaxWidth().padding(32.dp),
                horizontalArrangement = Arrangement.Center,
            ) { CircularProgressIndicator() }
        } else if (state.items.isEmpty()) {
            Column(
                modifier = Modifier.fillMaxWidth().padding(24.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Text(
                    if (inTrash) stringResource(R.string.homework_empty_trash)
                    else stringResource(R.string.homework_empty),
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
                items(state.items, key = { it.id }) { item ->
                    val pending = item.id in state.pendingIds
                    TrashSwipeRow(
                        item = item,
                        pending = pending,
                        onToggleTrash = { viewModel.toggleTrash(item) },
                    ) {
                        HomeworkCard(
                            item = item,
                            pending = pending,
                            onToggleDone = { viewModel.toggleDone(item) },
                        )
                    }
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
                            Text(stringResource(R.string.common_load_more_format, state.items.size, state.total))
                        }
                    }
                }
                item { Spacer(Modifier.height(88.dp)) }
            }
        }
    }
}

/** Kompatibilitäts-Alias (ältere Verdrahtung nutzte diesen Namen). */
@Composable
fun HomeworkScreen(
    viewModel: HomeworkViewModel,
    onOpenSettings: () -> Unit = {},
    onLogout: () -> Unit = {},
    onReLogin: () -> Unit = {},
    modifier: Modifier = Modifier,
) = HomeworkListScreen(viewModel, onOpenSettings, onLogout, onReLogin, modifier)

/**
 * Wisch-Zeile nur für den Papierkorb (erledigt geht über den Kreis):
 * nach rechts wischen legt hinein bzw. holt zurück — wie im Web.
 * Die Zeile federt zurück; der Erfolg ist über den ViewModel-State sichtbar.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun TrashSwipeRow(
    item: HomeworkDto,
    pending: Boolean,
    onToggleTrash: () -> Unit,
    content: @Composable () -> Unit,
) {
    if (pending) {
        content()
        return
    }
    val dismissState = rememberSwipeToDismissBoxState(
        confirmValueChange = { value ->
            if (value == SwipeToDismissBoxValue.StartToEnd) onToggleTrash()
            false
        },
    )
    SwipeToDismissBox(
        state = dismissState,
        enableDismissFromStartToEnd = true,
        enableDismissFromEndToStart = false,
        backgroundContent = {
            if (dismissState.targetValue == SwipeToDismissBoxValue.StartToEnd) {
                Box(
                    modifier = Modifier.fillMaxSize()
                        .background(StatusRed)
                        .padding(horizontal = 22.dp),
                    contentAlignment = Alignment.CenterStart,
                ) {
                    Text(
                        if (item.is_hidden) stringResource(R.string.homework_swipe_restore) else stringResource(R.string.homework_swipe_trash),
                        fontWeight = FontWeight.ExtraBold,
                        color = Color.White,
                    )
                }
            }
        },
        content = { content() },
    )
}

/** Aufgabenkarte wie im PNG: Status-Dot, Titel + Sub, Pill + Kreis rechts. */
@Composable
private fun HomeworkCard(
    item: HomeworkDto,
    pending: Boolean,
    onToggleDone: () -> Unit,
) {
    val dot = statusDot(item)
    val title = cardTitle(item)
    val pill = pillText(item)
    EduCard(modifier = Modifier.fillMaxWidth()) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.fillMaxWidth().padding(16.dp),
        ) {
            Box(
                modifier = Modifier.size(10.dp)
                    .clip(CircleShape)
                    .background(dot),
            )
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                Text(
                    title,
                    fontSize = 15.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = MaterialTheme.colorScheme.onSurface,
                )
                Spacer(Modifier.height(2.dp))
                Text(
                    cardSub(item),
                    fontSize = 13.sp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            Spacer(Modifier.width(8.dp))
            Column(
                horizontalAlignment = Alignment.End,
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                StatusPill(text = pill, dot = dot)
                DoneCircle(done = item.is_done, pending = pending, onClick = onToggleDone)
            }
        }
    }
}

/** Kreis-Checkbox: Tap schaltet erledigt/wieder öffnen (sofort sichtbar). */
@Composable
private fun DoneCircle(
    done: Boolean,
    pending: Boolean,
    onClick: () -> Unit,
) {
    val scheme = MaterialTheme.colorScheme
    if (pending) {
        CircularProgressIndicator(modifier = Modifier.size(24.dp), strokeWidth = 2.dp)
    } else if (done) {
        Box(
            contentAlignment = Alignment.Center,
            modifier = Modifier.size(24.dp)
                .clip(CircleShape)
                .background(scheme.primary)
                .clickable(onClick = onClick),
        ) {
            Icon(
                Icons.Filled.Check,
                contentDescription = stringResource(R.string.homework_reopen_desc),
                tint = scheme.onPrimary,
                modifier = Modifier.size(16.dp),
            )
        }
    } else {
        Box(
            modifier = Modifier.size(24.dp)
                .clip(CircleShape)
                .border(BorderStroke(1.dp, scheme.outline), CircleShape)
                .clickable(onClick = onClick),
        ) {}
    }
}

@Composable
private fun cardTitle(item: HomeworkDto): String {
    val fallback = stringResource(R.string.homework_title_format, item.id)
    val title = item.title.ifBlank { fallback }
    return if (item.subject.isNotBlank()) "${item.subject} - $title" else title
}

private fun cardSub(item: HomeworkDto): String {
    val whenText = item.due_display.ifBlank { item.status }
    return if (item.author.isNotBlank()) "$whenText · ${item.author}" else whenText
}

@Composable
private fun pillText(item: HomeworkDto): String =
    if (item.is_hidden) stringResource(R.string.homework_status_trash)
    else item.status.ifBlank { stringResource(R.string.homework_status_open) }

@Composable
private fun statusDot(item: HomeworkDto): Color = when {
    item.is_done || item.status == HomeworkItemStatus.ERLEDIGT -> StatusGreen
    item.status == HomeworkItemStatus.UEBERFAELLIG -> RDotRed
    item.status == HomeworkItemStatus.HEUTE -> RDotOrange
    else -> RDotBlue
}

/** Convenience-Überladung für Previews/Tests ohne manuelles ViewModel. */
@Composable
fun HomeworkScreenPreviewContent(items: List<HomeworkDto>) {
    LazyColumn(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        items(items, key = { it.id }) { item ->
            HomeworkCard(item = item, pending = false, onToggleDone = {})
        }
    }
}
