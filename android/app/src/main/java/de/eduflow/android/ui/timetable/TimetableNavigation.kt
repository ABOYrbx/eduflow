package de.eduflow.android.ui.timetable

import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.NavGraphBuilder
import androidx.navigation.compose.composable
import de.eduflow.android.data.ApiService
import de.eduflow.android.data.TimetableRepository
import de.eduflow.android.ui.navigation.Routes

private class TimetableViewModelFactory(
    private val repository: TimetableRepository,
) : ViewModelProvider.Factory {
    @Suppress("UNCHECKED_CAST")
    override fun <T : ViewModel> create(modelClass: Class<T>): T {
        return TimetableViewModel(repository) as T
    }
}

/**
 * Paket-D-Ziel für den frozen NavGraph (ui/navigation/NavGraph.kt).
 * Nutzt die eingefrorene Route [Routes.TIMETABLE] und den geteilten
 * [ApiService] — kein eigener Client, keine eigene Route.
 * Tag/Woche-Umschalter liegt im Screen (wie Web ?view=).
 */
fun NavGraphBuilder.timetableDestination(
    api: () -> ApiService,
    onReLogin: () -> Unit,
    onOpenSettings: () -> Unit = {},
    onLogout: () -> Unit = {},
) {
    composable(Routes.TIMETABLE) {
        val repository = remember(api) { TimetableRepository(api) }
        val vm: TimetableViewModel = viewModel(
            key = "timetable",
            factory = TimetableViewModelFactory(repository),
        )
        TimetableScreen(
            viewModel = vm,
            onReLogin = onReLogin,
            onOpenSettings = onOpenSettings,
            onLogout = onLogout,
        )
    }
}

/** Direkteinstieg (z. B. für Previews) ohne NavController. */
@Composable
fun TimetableEntry(
    api: () -> ApiService,
    onReLogin: () -> Unit = {},
    onOpenSettings: () -> Unit = {},
    onLogout: () -> Unit = {},
) {
    val repository = remember(api) { TimetableRepository(api) }
    val vm: TimetableViewModel = viewModel(
        key = "timetable",
        factory = TimetableViewModelFactory(repository),
    )
    TimetableScreen(
        viewModel = vm,
        onReLogin = onReLogin,
        onOpenSettings = onOpenSettings,
        onLogout = onLogout,
    )
}
