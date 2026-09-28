package de.eduflow.android.ui.navigation

import androidx.compose.animation.EnterTransition
import androidx.compose.animation.ExitTransition
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Modifier
import androidx.compose.ui.Alignment
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import de.eduflow.android.ui.theme.LocalReducedMotion
import de.eduflow.android.ui.theme.eduFlowEnter
import de.eduflow.android.ui.theme.eduFlowExit
import de.eduflow.android.ui.theme.eduFlowPopEnter
import de.eduflow.android.ui.theme.eduFlowPopExit
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.NavHostController
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.navArgument
import de.eduflow.android.data.ApiService
import de.eduflow.android.data.AuthRepository
import de.eduflow.android.data.SettingsRepository
import de.eduflow.android.data.Session
import de.eduflow.android.data.TokenStore
import de.eduflow.android.ui.common.LocalEduFlowSession
import de.eduflow.android.ui.auth.AuthViewModel
import de.eduflow.android.ui.auth.LoginScreen
import de.eduflow.android.ui.auth.OnboardingFlow
import de.eduflow.android.ui.auth.TwoFaScreen
import de.eduflow.android.ui.grades.gradesDestination
import de.eduflow.android.ui.school.schoolDestination
import de.eduflow.android.ui.homework.homeworkDestination
import de.eduflow.android.ui.messages.messagesDestination
import de.eduflow.android.ui.more.MoreScreen
import de.eduflow.android.ui.overview.overviewDestination
import de.eduflow.android.ui.settings.DevicesScreen
import de.eduflow.android.ui.settings.SettingsScreen
import de.eduflow.android.ui.settings.SettingsViewModel
import de.eduflow.android.ui.timetable.timetableDestination
import kotlinx.coroutines.launch

/**
 * NavGraph (Paket 0, eingefroren). Startziel hängt an der Sitzung:
 * ohne Token → Login, mit Token → landing aus den Einstellungen.
 * Navigation über die Bottom-Bar aus dem Redesign-PNG
 * (Home, Aufgaben, Nachr., Plan, Mehr).
 */
@Composable
fun EduFlowNav(
    nav: NavHostController,
    store: TokenStore,
    api: () -> ApiService,
) {
    val session by store.sessionFlow.collectAsState(initial = null)
    val onboardingCompleted by store.onboardingCompletedFlow.collectAsState(initial = false)
    // DataStore-Schreibzugriffe nie per runBlocking auf Main (ANR-Risiko),
    // sondern über den Scope (gilt auch für setBaseUrl unten).
    val scope = rememberCoroutineScope()

    // ViewModels überleben Recompositionen und dürfen nicht die beim ersten
    // Compose-Lauf erzeugte API-Factory festhalten (session == null → kein
    // Bearer-Token). Der stabile Provider liest deshalb bei jedem Request die
    // aktuelle Factory mit der inzwischen geladenen Sitzung.
    val currentApiFactory by rememberUpdatedState(api)
    val apiProvider = remember { { currentApiFactory() } }
    val authRepo = remember { AuthRepository(apiProvider, store) }
    val settingsRepo = remember { SettingsRepository(apiProvider) }
    val authVm: AuthViewModel = viewModel(key = "auth") { AuthViewModel(authRepo) }
    val settingsVm: SettingsViewModel = viewModel(key = "settings") {
        SettingsViewModel(settingsRepo, authRepo, store)
    }
    // Editierbare Belegung aus den Einstellungen (Mehr immer angepinnt).
    val navTabsRaw by settingsVm.navTabs.collectAsState()
    val bottomTabs = remember(navTabsRaw) { tabsForSelection(NavTabs.parse(navTabsRaw)) }

    val start = when {
        session?.isLoggedIn == true -> Routes.OVERVIEW
        // Während DataStore die Sitzung lädt direkt den gewünschten Einstieg
        // zeigen, statt kurz den Login zu rendern und danach umzuschalten.
        session == null -> Routes.ONBOARDING
        onboardingCompleted -> Routes.LOGIN
        else -> Routes.ONBOARDING
    }

    // Nach erfolgreichem Login (Session-Flow) von Login/2FA zur
    // landing-Seite aus den Einstellungen (wie Web-/). Der NavHost-Start
    // bleibt nach Erstellung fix, daher explizit navigieren.
    LaunchedEffect(session, onboardingCompleted) {
        val loadedSession = session ?: return@LaunchedEffect
        val cur = nav.currentBackStackEntry?.destination?.route
        if (loadedSession.isLoggedIn) {
            store.completeOnboarding()
            if (cur == Routes.LOGIN || cur == Routes.ONBOARDING || cur?.startsWith("twofa") == true) {
                val dest = try {
                    Routes.landingRoute(settingsRepo.load().second.landing)
                } catch (_: Exception) {
                    Routes.OVERVIEW
                }
                nav.navigate(dest) {
                    popUpTo(nav.graph.id) { inclusive = true }
                }
            }
        } else if (!onboardingCompleted && cur == Routes.LOGIN) {
            nav.navigate(Routes.ONBOARDING) {
                popUpTo(nav.graph.id) { inclusive = true }
            }
        } else if (onboardingCompleted && cur == Routes.ONBOARDING) {
            nav.navigate(Routes.LOGIN) {
                popUpTo(nav.graph.id) { inclusive = true }
            }
        }
    }

    // Bottom-Bar aus dem Redesign-PNG — nur auf den Haupt-Routen,
    // nicht auf Login/2FA.
    val backStackEntry by nav.currentBackStackEntryAsState()
    val route = backStackEntry?.destination?.route
    val showBar = route != null &&
        route != Routes.LOGIN && route != Routes.ONBOARDING && !route.startsWith("twofa")
    val reducedMotion = LocalReducedMotion.current

    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        contentColor = MaterialTheme.colorScheme.onBackground,
        contentWindowInsets = WindowInsets(0, 0, 0, 0),
    ) { _ ->
        CompositionLocalProvider(LocalEduFlowSession provides (session ?: Session())) {
        Box(Modifier.fillMaxSize()) {
        NavHost(
            navController = nav,
            startDestination = start,
            modifier = Modifier.fillMaxSize().statusBarsPadding(),
            enterTransition = { if (reducedMotion) EnterTransition.None else eduFlowEnter() },
            exitTransition = { if (reducedMotion) ExitTransition.None else eduFlowExit() },
            popEnterTransition = { if (reducedMotion) EnterTransition.None else eduFlowPopEnter() },
            popExitTransition = { if (reducedMotion) ExitTransition.None else eduFlowPopExit() },
        ) {
        composable(Routes.ONBOARDING) {
            OnboardingFlow(
                vm = authVm,
                baseUrl = session?.baseUrl ?: TokenStore.DEFAULT_BASE_URL,
                onBaseUrlChange = { url -> store.setBaseUrl(url) },
                onTwoFa = { pending -> nav.navigate(Routes.twoFa(pending)) },
                onStartDemo = { store.setDemoMode(true) },
                onStopDemo = { store.setDemoMode(false) },
                isDemo = session?.isDemo == true,
            )
        }
        composable(Routes.LOGIN) {
            LoginScreen(
                vm = authVm,
                baseUrl = session?.baseUrl ?: TokenStore.DEFAULT_BASE_URL,
                onBaseUrlChange = { url -> store.setBaseUrl(url) },
                onTwoFa = { pending -> nav.navigate(Routes.twoFa(pending)) },
                onStartDemo = { store.setDemoMode(true) },
                onStopDemo = { store.setDemoMode(false) },
                isDemo = session?.isDemo == true,
            )
        }
        composable(
            Routes.TWO_FA,
            arguments = listOf(navArgument("pending") { type = NavType.StringType; defaultValue = "" }),
        ) { backStack ->
            TwoFaScreen(
                vm = authVm,
                pendingToken = backStack.arguments?.getString("pending").orEmpty(),
                // Keine explizite Navigation: der Session-Flow oben navigiert
                // zur landing-Seite, sobald der Token gespeichert ist.
                onLoggedIn = {},
                onBackToLogin = { nav.popBackStack() },
            )
        }
        // Paket D: Startseite (Uhr, ungelesen, offene HA, Stunden,
        // Essen, Wetter). 401-Verhalten: zurück zum Login.
        overviewDestination(api, nav, onReLogin = {
            settingsVm.logout {
                nav.navigate(Routes.LOGIN) { popUpTo(nav.graph.id) { inclusive = true } }
            }
        },
            onOpenSettings = { nav.navigate(Routes.SETTINGS) },
            onLogout = {
                settingsVm.logout {
                    nav.navigate(Routes.LOGIN) { popUpTo(nav.graph.id) { inclusive = true } }
                }
            },
        )
        messagesDestination(
            api = api,
            baseUrl = session?.baseUrl ?: TokenStore.DEFAULT_BASE_URL,
            nav = nav,
            store = store,
            onReLogin = {
                settingsVm.logout {
                    nav.navigate(Routes.LOGIN) { popUpTo(nav.graph.id) { inclusive = true } }
                }
            },
            onOpenSettings = { nav.navigate(Routes.SETTINGS) },
            onLogout = {
                settingsVm.logout {
                    nav.navigate(Routes.LOGIN) { popUpTo(nav.graph.id) { inclusive = true } }
                }
            },
        )
        homeworkDestination(
            api,
            onReLogin = {
                settingsVm.logout {
                    nav.navigate(Routes.LOGIN) { popUpTo(nav.graph.id) { inclusive = true } }
                }
            },
            onOpenSettings = { nav.navigate(Routes.SETTINGS) },
            onLogout = {
                settingsVm.logout {
                    nav.navigate(Routes.LOGIN) { popUpTo(nav.graph.id) { inclusive = true } }
                }
            },
        )
        // Paket D: Tag/Woche mit Lernzeit-Blöcken, Entfall-/Online-Kennzeichen.
        timetableDestination(
            api,
            onReLogin = {
                settingsVm.logout {
                    nav.navigate(Routes.LOGIN) { popUpTo(nav.graph.id) { inclusive = true } }
                }
            },
            onOpenSettings = { nav.navigate(Routes.SETTINGS) },
            onLogout = {
                settingsVm.logout {
                    nav.navigate(Routes.LOGIN) { popUpTo(nav.graph.id) { inclusive = true } }
                }
            },
        )
        gradesDestination(
            api,
            onReLogin = {
                settingsVm.logout {
                    nav.navigate(Routes.LOGIN) { popUpTo(nav.graph.id) { inclusive = true } }
                }
            },
            onOpenSettings = { nav.navigate(Routes.SETTINGS) },
            onLogout = {
                settingsVm.logout {
                    nav.navigate(Routes.LOGIN) { popUpTo(nav.graph.id) { inclusive = true } }
                }
            },
        )
        schoolDestination(
            api = api,
            onReLogin = {
                settingsVm.logout {
                    nav.navigate(Routes.LOGIN) { popUpTo(nav.graph.id) { inclusive = true } }
                }
            },
            onOpenSettings = { nav.navigate(Routes.SETTINGS) },
            onLogout = {
                settingsVm.logout {
                    nav.navigate(Routes.LOGIN) { popUpTo(nav.graph.id) { inclusive = true } }
                }
            },
        )
        composable(Routes.SETTINGS) {
            SettingsScreen(
                vm = settingsVm,
                baseUrl = session?.baseUrl ?: TokenStore.DEFAULT_BASE_URL,
                isDemo = session?.isDemo == true,
                onBaseUrlChange = { url -> scope.launch { store.setBaseUrl(url) } },
                onDevices = { nav.navigate(Routes.DEVICES) },
                onRestartOnboarding = {
                    nav.navigate(Routes.ONBOARDING) {
                        popUpTo(nav.graph.id) { inclusive = true }
                    }
                },
                onLogout = { nav.navigate(Routes.LOGIN) { popUpTo(nav.graph.id) { inclusive = true } } },
                // 401-Verhalten (→ Login, Paket A): Token ungültig/abgelaufen.
                onSessionExpired = { nav.navigate(Routes.LOGIN) { popUpTo(nav.graph.id) { inclusive = true } } },
                onSettingsSaved = {
                    runCatching {
                        nav.getBackStackEntry(Routes.OVERVIEW)
                            .savedStateHandle["settings_changed"] = true
                    }
                },
            )
        }
        composable(Routes.DEVICES) {
            DevicesScreen(
                vm = settingsVm,
                onSessionExpired = { nav.navigate(Routes.LOGIN) { popUpTo(nav.graph.id) { inclusive = true } } },
            )
        }
        composable(Routes.MORE) {
            MoreScreen(
                onGrades = { nav.navigate(Routes.GRADES) },
                onSchool = { nav.navigate(Routes.SCHOOL) },
                onSettings = { nav.navigate(Routes.SETTINGS) },
                onDevices = { nav.navigate(Routes.DEVICES) },
                onLogout = {
                    settingsVm.logout {
                        nav.navigate(Routes.LOGIN) { popUpTo(nav.graph.id) { inclusive = true } }
                    }
                },
                vm = settingsVm,
                baseUrl = session?.baseUrl ?: TokenStore.DEFAULT_BASE_URL,
                isDemo = session?.isDemo == true,
                onBaseUrlChange = { url -> scope.launch { store.setBaseUrl(url) } },
            )
}
        }
        if (showBar) {
            // Weicher Glas-Saum: Inhalte laufen unter dem Dock weiter und
            // verlieren nach unten Kontrast, statt an einem schwarzen Balken
            // hart abgeschnitten zu werden.
            Box(
                Modifier.align(Alignment.BottomCenter)
                    .fillMaxWidth()
                    .height(96.dp)
                    .background(
                        Brush.verticalGradient(
                            listOf(
                                Color.Transparent,
                                MaterialTheme.colorScheme.background.copy(alpha = 0.12f),
                                MaterialTheme.colorScheme.background.copy(alpha = 0.4f),
                            ),
                        ),
                    ),
            )
            EduFlowBottomBar(
                currentRoute = route,
                onSection = { dest ->
                    nav.navigate(dest) {
                        popUpTo(nav.graph.findStartDestination().id) {
                            saveState = true
                        }
                        launchSingleTop = true
                        restoreState = true
                    }
                },
                modifier = Modifier.align(Alignment.BottomCenter).navigationBarsPadding(),
                tabs = bottomTabs,
            )
        }
        }
        }
    }
}
