package de.eduflow.android.ui.messages

import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewmodel.compose.LocalViewModelStoreOwner
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.NavController
import androidx.navigation.NavGraphBuilder
import androidx.navigation.NavType
import androidx.navigation.compose.composable
import androidx.navigation.navArgument
import de.eduflow.android.data.ApiService
import de.eduflow.android.data.MessagesRepository
import de.eduflow.android.data.TokenStore
import de.eduflow.android.ui.navigation.Routes
import kotlinx.coroutines.launch

/** Unter-Routen der Nachrichten (additiv zu Routes.MESSAGES, Web: /dashboard). */
const val MESSAGES_THREAD_ROUTE = "messages/{id}/thread"
const val MESSAGES_COMPOSE_ROUTE = "messages/send"

fun messageThreadRoute(id: Int) = "messages/$id/thread"

/** Liste lädt nach dem Senden neu (Backend liefert die Nachricht synchron). */
private const val REFRESH_KEY = "messages_refresh"

private class MessagesViewModelFactory(
    private val repository: MessagesRepository,
    private val store: TokenStore,
) : ViewModelProvider.Factory {
    @Suppress("UNCHECKED_CAST")
    override fun <T : ViewModel> create(modelClass: Class<T>): T {
        return MessagesViewModel(repository, store) as T
    }
}

private class ThreadViewModelFactory(
    private val repository: MessagesRepository,
    private val messageId: Int,
) : ViewModelProvider.Factory {
    @Suppress("UNCHECKED_CAST")
    override fun <T : ViewModel> create(modelClass: Class<T>): T {
        return ThreadViewModel(repository, messageId) as T
    }
}

private class ComposeViewModelFactory(
    private val repository: MessagesRepository,
) : ViewModelProvider.Factory {
    @Suppress("UNCHECKED_CAST")
    override fun <T : ViewModel> create(modelClass: Class<T>): T {
        return ComposeViewModel(repository) as T
    }
}

/**
 * Paket-B-Ziele für den frozen NavGraph (ui/navigation/NavGraph.kt).
 * Nutzt die eingefrorene Route [Routes.MESSAGES] und den geteilten
 * [ApiService] — kein eigener Client, keine eigenen Kern-Routen.
 *
 * Liste (Routes.MESSAGES) -> Thread -> Verfassen. Anhänge meldet
 * [onAttachment] als fertige Download-URL (Kurzzeit-Token `?dl=`, per
 * Bearer-Header ausgestellt — das langlebige API-Token steht nie in der
 * URL). Abgelaufene Sitzung meldet [onReLogin] (401-Verhalten → Login).
 */
fun NavGraphBuilder.messagesDestination(
    api: () -> ApiService,
    baseUrl: String,
    nav: NavController,
    store: TokenStore,
    onReLogin: () -> Unit,
    onOpenSettings: () -> Unit = {},
    onLogout: () -> Unit = {},
    onAttachment: (String) -> Unit = {},
) {
    composable(Routes.MESSAGES) { backStack ->
        val repository = remember(api, baseUrl) {
            MessagesRepository(api, baseUrl)
        }
        val scope = rememberCoroutineScope()
        // VM an der Listen-Route verankern (eigener Eintrag): Der Thread
        // unten nutzt dieselbe Instanz (Header + kein Doppel-Request).
        val owner = remember(nav) {
            runCatching { nav.getBackStackEntry(Routes.MESSAGES) }.getOrNull()
        } ?: checkNotNull(LocalViewModelStoreOwner.current)
        val vm: MessagesViewModel = viewModel(
            key = "messages",
            viewModelStoreOwner = owner,
            factory = MessagesViewModelFactory(repository, store),
        )
        val refreshSignal by backStack.savedStateHandle
            .getStateFlow(REFRESH_KEY, false)
            .collectAsState()
        LaunchedEffect(refreshSignal) {
            if (refreshSignal) {
                backStack.savedStateHandle[REFRESH_KEY] = false
                vm.refresh()
            }
        }
        MessagesScreen(
            viewModel = vm,
            onOpenThread = { id -> nav.navigate(messageThreadRoute(id)) },
            onCompose = { nav.navigate(MESSAGES_COMPOSE_ROUTE) },
            onAttachment = { id, idx ->
                scope.launch {
                    repository.attachmentUrl(id, idx)
                        .onSuccess(onAttachment)
                        .onFailure(vm::showDownloadError)
                }
            },
            onOpenSettings = onOpenSettings,
            onLogout = onLogout,
            onReLogin = onReLogin,
        )
    }
    composable(
        MESSAGES_THREAD_ROUTE,
        arguments = listOf(navArgument("id") { type = NavType.IntType }),
    ) { backStack ->
        val id = backStack.arguments?.getInt("id", 0) ?: 0
        val repository = remember(api, baseUrl) {
            MessagesRepository(api, baseUrl)
        }
        val scope = rememberCoroutineScope()
        // Dieselbe Listen-Instanz wie in der Liste oben: Thread-Header aus
        // geladenen Daten, kein zweiter Listen-Request (eine eigene VM
        // hätte leere Items und würde erneut laden).
        val listOwner = remember(nav) {
            runCatching { nav.getBackStackEntry(Routes.MESSAGES) }.getOrNull()
        } ?: checkNotNull(LocalViewModelStoreOwner.current)
        val listVm: MessagesViewModel = viewModel(
            key = "messages",
            viewModelStoreOwner = listOwner,
            factory = MessagesViewModelFactory(repository, store),
        )
        val vm: ThreadViewModel = viewModel(
            key = "thread-$id",
            factory = ThreadViewModelFactory(repository, id),
        )
        val listState by listVm.state.collectAsState()
        val message = listState.items.firstOrNull { it.id == id }
        ThreadScreen(
            viewModel = vm,
            message = message,
            onAttachment = { mid, idx ->
                scope.launch {
                    repository.attachmentUrl(mid, idx)
                        .onSuccess(onAttachment)
                        .onFailure(vm::showDownloadError)
                }
            },
            onBack = { nav.popBackStack() },
            onReLogin = onReLogin,
        )
    }
    composable(MESSAGES_COMPOSE_ROUTE) {
        val repository = remember(api, baseUrl) {
            MessagesRepository(api, baseUrl)
        }
        val vm: ComposeViewModel = viewModel(
            factory = ComposeViewModelFactory(repository),
        )
        ComposeScreen(
            viewModel = vm,
            onSent = {
                nav.previousBackStackEntry?.savedStateHandle?.set(REFRESH_KEY, true)
                nav.popBackStack()
            },
            onBack = { nav.popBackStack() },
            onReLogin = onReLogin,
        )
    }
}

/** Direkteinstieg (z. B. für Previews) ohne NavController. */
@Composable
fun MessagesEntry(
    api: () -> ApiService,
    store: TokenStore,
    baseUrl: String = "",
    onReLogin: () -> Unit = {},
    onAttachment: (String) -> Unit = {},
) {
    val repository = remember(api, baseUrl) {
        MessagesRepository(api, baseUrl)
    }
    val scope = rememberCoroutineScope()
    val vm: MessagesViewModel = viewModel(
        key = "messages",
        factory = MessagesViewModelFactory(repository, store),
    )
    MessagesScreen(
        viewModel = vm,
        onOpenThread = {},
        onCompose = {},
        onAttachment = { id, idx ->
            scope.launch {
                repository.attachmentUrl(id, idx)
                    .onSuccess(onAttachment)
                    .onFailure(vm::showDownloadError)
            }
        },
        onReLogin = onReLogin,
    )
}
