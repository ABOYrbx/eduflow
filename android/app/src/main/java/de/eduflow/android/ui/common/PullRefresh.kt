package de.eduflow.android.ui.common

import androidx.compose.foundation.layout.Box
import androidx.compose.material.ExperimentalMaterialApi
import androidx.compose.material.pullrefresh.PullRefreshIndicator
import androidx.compose.material.pullrefresh.pullRefresh
import androidx.compose.material.pullrefresh.rememberPullRefreshState
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier

/**
 * Einheitliches Pull-to-Refresh für alle Listen-Screens (Paket-übergreifend).
 *
 * Nutzt dieselbe BOM-verwaltete Material-PullRefresh-API wie die Übersicht
 * (kein neues Dependency): von oben ziehen ruft [onRefresh] (lädt via
 * ViewModel mit refresh=1, wo die API es kennt). Der Aufrufer gibt Größe/
 * Gewicht über [modifier] vor (z. B. `Modifier.weight(1f)`).
 */
@OptIn(ExperimentalMaterialApi::class)
@Composable
fun PullRefreshBox(
    refreshing: Boolean,
    onRefresh: () -> Unit,
    modifier: Modifier = Modifier,
    content: @Composable () -> Unit,
) {
    val pullState = rememberPullRefreshState(
        refreshing = refreshing,
        onRefresh = onRefresh,
    )
    Box(modifier = modifier.pullRefresh(pullState)) {
        content()
        PullRefreshIndicator(
            refreshing = refreshing,
            state = pullState,
            modifier = Modifier.align(Alignment.TopCenter),
        )
    }
}
