package de.eduflow.android.ui.grades

import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.NavGraphBuilder
import androidx.navigation.compose.composable
import de.eduflow.android.data.ApiService
import de.eduflow.android.data.repository.GradesRepository
import de.eduflow.android.ui.navigation.Routes

private class GradesViewModelFactory(
    private val repository: GradesRepository,
) : ViewModelProvider.Factory {
    @Suppress("UNCHECKED_CAST")
    override fun <T : ViewModel> create(modelClass: Class<T>): T {
        return GradesViewModel(repository) as T
    }
}

/**
 * Paket-C-Ziel für den frozen NavGraph (ui/navigation/NavGraph.kt).
 * Nutzt die eingefrorene Route [Routes.GRADES] und den geteilten
 * [ApiService] — kein eigener Client, keine eigene Route.
 * Abgelaufene Sitzung meldet [onReLogin] (401-Verhalten → Login).
 */
fun NavGraphBuilder.gradesDestination(
    api: () -> ApiService,
    onReLogin: () -> Unit = {},
    onOpenSettings: () -> Unit = {},
    onLogout: () -> Unit = {},
) {
    composable(Routes.GRADES) {
        val repository = remember(api) { GradesRepository(api) }
        val vm: GradesViewModel = viewModel(
            key = "grades",
            factory = GradesViewModelFactory(repository),
        )
        GradesScreen(
            viewModel = vm,
            onReLogin = onReLogin,
            onOpenSettings = onOpenSettings,
            onLogout = onLogout,
        )
    }
}

/** Direkteinstieg (z. B. für Previews) ohne NavController. */
@Composable
fun GradesEntry(
    api: () -> ApiService,
    onReLogin: () -> Unit = {},
    onOpenSettings: () -> Unit = {},
    onLogout: () -> Unit = {},
) {
    val repository = remember(api) { GradesRepository(api) }
    val vm: GradesViewModel = viewModel(
        key = "grades",
        factory = GradesViewModelFactory(repository),
    )
    GradesScreen(
        viewModel = vm,
        onReLogin = onReLogin,
        onOpenSettings = onOpenSettings,
        onLogout = onLogout,
    )
}
