package de.eduflow.android.ui.overview

import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.NavController
import androidx.navigation.NavGraphBuilder
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import de.eduflow.android.data.ApiService
import de.eduflow.android.data.MetaRepository
import de.eduflow.android.data.SettingsRepository
import de.eduflow.android.data.TimetableRepository
import de.eduflow.android.data.repository.HomeworkRepository
import de.eduflow.android.ui.navigation.Routes

private class OverviewViewModelFactory(
    private val api: () -> ApiService,
    private val settingsRepo: SettingsRepository,
    private val homeworkRepo: HomeworkRepository,
    private val timetableRepo: TimetableRepository,
    private val metaRepo: MetaRepository,
) : ViewModelProvider.Factory {
    @Suppress("UNCHECKED_CAST")
    override fun <T : ViewModel> create(modelClass: Class<T>): T {
        return OverviewViewModel(api, settingsRepo, homeworkRepo, timetableRepo, metaRepo) as T
    }
}

/**
 * Paket-D-Ziel für den frozen NavGraph (ui/navigation/NavGraph.kt).
 * Startseite (landing-Setting beachten — der NavGraph navigiert nach
 * Login bereits dorthin). Nutzt die eingefrorene Route [Routes.OVERVIEW]
 * und den geteilten [ApiService] — kein eigener Client, keine eigene Route.
 */
fun NavGraphBuilder.overviewDestination(
    api: () -> ApiService,
    nav: NavController,
    onReLogin: () -> Unit,
    onOpenSettings: () -> Unit = {},
    onLogout: () -> Unit = {},
) {
    composable(Routes.OVERVIEW) {
        val settingsRepo = remember(api) { SettingsRepository(api) }
        val homeworkRepo = remember(api) { HomeworkRepository(api) }
        val timetableRepo = remember(api) { TimetableRepository(api) }
        val metaRepo = remember(api) { MetaRepository(api) }
        val vm: OverviewViewModel = viewModel(
            key = "overview",
            factory = OverviewViewModelFactory(api, settingsRepo, homeworkRepo, timetableRepo, metaRepo),
        )
        val overviewEntry = remember(nav) { nav.getBackStackEntry(Routes.OVERVIEW) }
        val settingsChanged by overviewEntry.savedStateHandle
            .getStateFlow("settings_changed", false)
            .collectAsState()
        val currentEntry by nav.currentBackStackEntryAsState()
        val overviewIsVisible = currentEntry?.destination?.route == Routes.OVERVIEW
        LaunchedEffect(settingsChanged, overviewIsVisible) {
            // Einstellungen können beim Wechsel aus „Mehr“ gespeichert werden,
            // während diese Destination im Backstack liegt. Die komplette
            // Übersicht erst beim Zurückkehren laden, damit keine parallelen
            // Dashboard-Requests den Einstellungs-/Mehr-Tab ausbremsen.
            if (settingsChanged && overviewIsVisible) {
                overviewEntry.savedStateHandle["settings_changed"] = false
                vm.refresh()
            }
        }
        OverviewScreen(
            viewModel = vm,
            onMessages = { nav.navigate(Routes.MESSAGES) },
            onHomework = { nav.navigate(Routes.HOMEWORK) },
            onTimetable = { nav.navigate(Routes.TIMETABLE) },
            onGrades = { nav.navigate(Routes.GRADES) },
            onSettings = onOpenSettings,
            onReLogin = onReLogin,
            onLogout = onLogout,
        )
    }
}

/** Direkteinstieg (z. B. für Previews) ohne NavController. */
@Composable
fun OverviewEntry(
    api: () -> ApiService,
    onReLogin: () -> Unit = {},
    onOpenSettings: () -> Unit = {},
    onLogout: () -> Unit = {},
) {
    val settingsRepo = remember(api) { SettingsRepository(api) }
    val homeworkRepo = remember(api) { HomeworkRepository(api) }
    val timetableRepo = remember(api) { TimetableRepository(api) }
    val metaRepo = remember(api) { MetaRepository(api) }
    val vm: OverviewViewModel = viewModel(
        key = "overview",
        factory = OverviewViewModelFactory(api, settingsRepo, homeworkRepo, timetableRepo, metaRepo),
    )
    OverviewScreen(
        viewModel = vm,
        onMessages = {},
        onHomework = {},
        onTimetable = {},
        onGrades = {},
        onSettings = {},
        onReLogin = onReLogin,
        onOpenSettings = onOpenSettings,
        onLogout = onLogout,
    )
}
