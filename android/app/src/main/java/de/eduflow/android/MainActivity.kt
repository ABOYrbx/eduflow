package de.eduflow.android

import android.os.Bundle
import android.os.Build
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.navigation.compose.rememberNavController
import de.eduflow.android.data.ApiClient
import de.eduflow.android.data.TokenStore
import de.eduflow.android.ui.navigation.EduFlowNav
import de.eduflow.android.ui.theme.EduFlowTheme
import de.eduflow.android.ui.theme.accentByKey

class MainActivity : ComponentActivity() {

    private lateinit var store: TokenStore

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        androidx.core.view.WindowCompat.setDecorFitsSystemWindows(window, false)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            window.isNavigationBarContrastEnforced = false
            window.navigationBarDividerColor = android.graphics.Color.TRANSPARENT
        }
        store = TokenStore(applicationContext)
        setContent {
            val nav = rememberNavController()
            val session by store.sessionFlow.collectAsState(initial = null)
            // ApiService pro Basis-URL + aktuellem Token (neu bei Wechsel,
            // sonst hielte der Provider einen stalen Token).
            val api = remember(session?.baseUrl, session?.token) {
                val token = session?.token
                val base = session?.baseUrl ?: TokenStore.DEFAULT_BASE_URL
                val service = ApiClient.create(base) { token }
                return@remember { service }
            }
            // Aussehen wie im Web (static/theme.js): "system" folgt dem
            // System live, "light"/"dark" ist explizit; Akzent wie data-accent.
            val themeChoice by store.themeFlow.collectAsState(initial = TokenStore.THEME_SYSTEM)
            val accentKey by store.accentFlow.collectAsState(initial = TokenStore.ACCENT_DEFAULT)
            val systemDark = isSystemInDarkTheme()
            val dark = when (themeChoice) {
                TokenStore.THEME_LIGHT -> false
                TokenStore.THEME_DARK -> true
                else -> systemDark
            }
            EduFlowTheme(
                darkTheme = dark,
                accent = accentByKey(accentKey).color,
            ) {
                EduFlowNav(nav = nav, store = store, api = api)
            }
        }
    }
}
