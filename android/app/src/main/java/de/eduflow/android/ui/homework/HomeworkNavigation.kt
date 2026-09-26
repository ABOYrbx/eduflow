package de.eduflow.android.ui.homework

import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.NavGraphBuilder
import androidx.navigation.compose.composable
import de.eduflow.android.data.ApiService
import de.eduflow.android.data.repository.HomeworkRepository
import de.eduflow.android.ui.navigation.Routes

private class HomeworkViewModelFactory(
    private val repository: HomeworkRepository,
) : ViewModelProvider.Factory {
    @Suppress("UNCHECKED_CAST")
    override fun <T : ViewModel> create(modelClass: Class<T>): T {
        return HomeworkViewModel(repository) as T
    }
}

/**
 * Paket-B-Ziel für den NavGraph (ui/navigation/NavGraph.kt, Redesign-PNG
 * Screen 01). Nutzt die eingefrorene Route [Routes.HOMEWORK] und den
 * geteilten [ApiService] — kein eigener Client, keine eigene Route.
 * Abgelaufene Sitzung meldet [onReLogin] (401-Verhalten → Login).
 */
fun NavGraphBuilder.homeworkDestination(
    api: () -> ApiService,
    onReLogin: () -> Unit = {},
    onOpenSettings: () -> Unit = {},
    onLogout: () -> Unit = {},
) {
    composable(Routes.HOMEWORK) {
        val repository = remember(api) { HomeworkRepository(api) }
        val vm: HomeworkViewModel = viewModel(
            key = "homework",
            factory = HomeworkViewModelFactory(repository),
        )
        HomeworkScreen(
            viewModel = vm,
            onOpenSettings = onOpenSettings,
            onLogout = onLogout,
            onReLogin = onReLogin,
        )
    }
}

/** Direkteinstieg (z. B. für Previews) ohne NavController. */
@Composable
fun HomeworkEntry(
    api: () -> ApiService,
    onReLogin: () -> Unit = {},
    onOpenSettings: () -> Unit = {},
    onLogout: () -> Unit = {},
) {
    val repository = remember(api) { HomeworkRepository(api) }
    val vm: HomeworkViewModel = viewModel(
        key = "homework",
        factory = HomeworkViewModelFactory(repository),
    )
    HomeworkScreen(
        viewModel = vm,
        onOpenSettings = onOpenSettings,
        onLogout = onLogout,
        onReLogin = onReLogin,
    )
}
