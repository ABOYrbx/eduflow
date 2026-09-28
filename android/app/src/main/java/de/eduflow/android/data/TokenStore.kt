package de.eduflow.android.data

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.core.handlers.ReplaceFileCorruptionHandler
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.emptyPreferences
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map

/**
 * Korrupte Prefs-Datei darf nie wieder zum Start-Crash führen
 * (CorruptionException in DataStore-Init → FATAL): Bei unlesbarer Datei
 * von vorne mit Defaults beginnen (Benutzer muss sich neu anmelden).
 */
private val Context.tokenDataStore: DataStore<Preferences> by preferencesDataStore(
    name = "eduflow_auth",
    corruptionHandler = ReplaceFileCorruptionHandler(
        produceNewData = { emptyPreferences() },
    ),
)

/**
 * Basis-URL normalisieren (Paket 0): Scheme ergänzen, wenn es fehlt
 * (sonst stürzt Retrofit mit IllegalArgumentException ab), Blank → Default.
 * `localhost` bleibt bewusst wörtlich erhalten — im Emulator gilt
 * `10.0.2.2` für den Host (siehe Hinweis im Login-Screen).
 */
internal fun normalizeBaseUrl(raw: String): String {
    var base = raw.trim().trimEnd('/')
    if (base.isBlank()) return TokenStore.DEFAULT_BASE_URL
    if ("://" !in base) base = "http://$base"
    return if (base.endsWith("/")) base else "$base/"
}

/** Auf dem Gerät gespeicherte Sitzung (Token nie loggen, nie in UI zeigen). */
data class Session(
    val token: String = "",
    val expires: String = "",
    val subdomain: String = "",
    val username: String = "",
    val baseUrl: String = TokenStore.DEFAULT_BASE_URL,
    val isDemo: Boolean = false,
) {
    val isLoggedIn: Boolean get() = token.isNotBlank()
}

/**
 * Token-Ablage (Paket 0, eingefroren). Einzige Stelle für
 * Speichern/Lesen/Löschen der Sitzung + Basis-URL.
 */
class TokenStore(private val context: Context) {

    private object Keys {
        val TOKEN = stringPreferencesKey("token")
        val EXPIRES = stringPreferencesKey("expires")
        val SUBDOMAIN = stringPreferencesKey("subdomain")
        val USERNAME = stringPreferencesKey("username")
        val BASE_URL = stringPreferencesKey("base_url")
        // Gelesene Nachrichten-IDs (Paket C, „Ungelesen"-Chip): Der Server
        // kennt kein Ungelesen-Flag, darum lokal (kommagetrennt, max. 2000).
        val SEEN_MESSAGES = stringPreferencesKey("seen_messages")
        // Aussehen, lokal wie localStorage im Web (static/theme.js):
        // "system" = System folgen (Standard), "light"/"dark" = explizit.
        val THEME = stringPreferencesKey("theme")
        // Akzent-Schlüssel wie im Web (theme.js data-accent), Standard black.
        val ACCENT = stringPreferencesKey("accent")
        val ONBOARDING_COMPLETED = booleanPreferencesKey("onboarding_completed")
        val ONBOARDING_VERSION = intPreferencesKey("onboarding_version")
        val DEVELOPER_OPTIONS = booleanPreferencesKey("developer_options")
        val DEMO_MODE = booleanPreferencesKey("demo_mode")
        // Navigationsleisten-Belegung (Paket F, gerätelokal wie Theme/Akzent):
        // kommagetrennte Routen der Inhalte, Mehr ist immer angepinnt.
        val NAV_TABS = stringPreferencesKey("nav_tabs")
    }

    /** Aussehen-Wahl: "system" (Standard), "light" oder "dark". */
    val themeFlow: Flow<String> = context.tokenDataStore.data.map { prefs ->
        prefs[Keys.THEME] ?: THEME_SYSTEM
    }

    /** Akzent-Schlüssel (z. B. "black", "blue"), Standard "black". */
    val accentFlow: Flow<String> = context.tokenDataStore.data.map { prefs ->
        prefs[Keys.ACCENT] ?: ACCENT_DEFAULT
    }

    val onboardingCompletedFlow: Flow<Boolean> = context.tokenDataStore.data.map { prefs ->
        (prefs[Keys.ONBOARDING_COMPLETED] ?: false) &&
            (prefs[Keys.ONBOARDING_VERSION] ?: 0) >= CURRENT_ONBOARDING_VERSION
    }

    val developerOptionsFlow: Flow<Boolean> = context.tokenDataStore.data.map { prefs ->
        prefs[Keys.DEVELOPER_OPTIONS] ?: false
    }

    suspend fun completeOnboarding() {
        context.tokenDataStore.edit {
            it[Keys.ONBOARDING_COMPLETED] = true
            it[Keys.ONBOARDING_VERSION] = CURRENT_ONBOARDING_VERSION
        }
    }

    suspend fun resetOnboarding() {
        context.tokenDataStore.edit { it[Keys.ONBOARDING_COMPLETED] = false }
    }

    /** Belegte Navigations-Tabs (Inhalte ohne Mehr, Standard Home/Aufgaben/Nachr./Plan). */
    val navTabsFlow: Flow<String> = context.tokenDataStore.data.map { prefs ->
        prefs[Keys.NAV_TABS] ?: ""
    }

    suspend fun setNavTabs(routes: List<String>) {
        context.tokenDataStore.edit { prefs ->
            prefs[Keys.NAV_TABS] = routes.joinToString(",")
        }
    }

    suspend fun setDeveloperOptions(enabled: Boolean) {
        context.tokenDataStore.edit { it[Keys.DEVELOPER_OPTIONS] = enabled }
    }

    val sessionFlow: Flow<Session> = context.tokenDataStore.data.map { prefs ->
        Session(
            token = prefs[Keys.TOKEN].orEmpty(),
            expires = prefs[Keys.EXPIRES].orEmpty(),
            subdomain = prefs[Keys.SUBDOMAIN].orEmpty(),
            username = prefs[Keys.USERNAME].orEmpty(),
            baseUrl = prefs[Keys.BASE_URL] ?: DEFAULT_BASE_URL,
            isDemo = prefs[Keys.DEMO_MODE] ?: false,
        )
    }

    suspend fun save(token: String, expires: String, subdomain: String, username: String) {
        context.tokenDataStore.edit { prefs ->
            prefs[Keys.TOKEN] = token
            prefs[Keys.EXPIRES] = expires
            prefs[Keys.SUBDOMAIN] = subdomain
            prefs[Keys.USERNAME] = username
        }
    }

    suspend fun clear() {
        context.tokenDataStore.edit { prefs ->
            val wasDemo = prefs[Keys.DEMO_MODE] == true
            prefs.remove(Keys.TOKEN)
            prefs.remove(Keys.EXPIRES)
            prefs.remove(Keys.SUBDOMAIN)
            prefs.remove(Keys.USERNAME)
            prefs.remove(Keys.DEMO_MODE)
            if (wasDemo) prefs.remove(Keys.BASE_URL)
        }
    }

    suspend fun setDemoMode(enabled: Boolean) {
        context.tokenDataStore.edit { prefs ->
            prefs[Keys.DEMO_MODE] = enabled
            if (enabled) prefs[Keys.BASE_URL] = DEMO_BASE_URL.trimEnd('/')
            else if (prefs[Keys.BASE_URL] == DEMO_BASE_URL.trimEnd('/')) prefs.remove(Keys.BASE_URL)
        }
    }

    suspend fun setBaseUrl(baseUrl: String) {
        context.tokenDataStore.edit { prefs ->
            prefs[Keys.BASE_URL] = if (prefs[Keys.DEMO_MODE] == true) DEMO_BASE_URL.trimEnd('/')
            else normalizeBaseUrl(baseUrl).trimEnd('/')
        }
    }

    /** Gesehene Nachrichten-IDs (für den „Ungelesen"-Filter). */
    val seenMessagesFlow: Flow<Set<Int>> = context.tokenDataStore.data.map { prefs ->
        prefs[Keys.SEEN_MESSAGES]?.split(",")?.mapNotNull { it.toIntOrNull() }?.toSet()
            ?: emptySet()
    }

    suspend fun markMessagesSeen(ids: Collection<Int>) {
        if (ids.isEmpty()) return
        context.tokenDataStore.edit { prefs ->
            val cur = prefs[Keys.SEEN_MESSAGES]?.split(",")
                ?.mapNotNull { it.toIntOrNull() }?.toMutableSet() ?: mutableSetOf()
            cur.addAll(ids)
            val trimmed = if (cur.size > 2000) cur.toList().takeLast(2000).toSet() else cur
            prefs[Keys.SEEN_MESSAGES] = trimmed.joinToString(",")
        }
    }

    suspend fun setTheme(theme: String) {
        val value = theme.trim().lowercase()
            .takeIf { it == THEME_LIGHT || it == THEME_DARK } ?: THEME_SYSTEM
        context.tokenDataStore.edit { prefs ->
            prefs[Keys.THEME] = value
        }
    }

    suspend fun setAccent(accent: String) {
        context.tokenDataStore.edit { prefs ->
            prefs[Keys.ACCENT] = accent.trim().lowercase().ifBlank { ACCENT_DEFAULT }
        }
    }

    suspend fun currentToken(): String? =
        context.tokenDataStore.data.first()[Keys.TOKEN]?.takeIf { it.isNotBlank() }

    suspend fun currentSession(): Session = sessionFlow.first()

    companion object {
        /** Default aus android/gradle.properties (eduflow.defaultBaseUrl). */
        const val DEFAULT_BASE_URL = "http://10.0.2.2:3000/api/v1/"
        const val DEMO_BASE_URL = "http://10.0.2.2:8101/api/v1/"

        /** Aussehen-Werte wie im Web (static/theme.js: system/light/dark). */
        const val THEME_SYSTEM = "system"
        const val THEME_LIGHT = "light"
        const val THEME_DARK = "dark"

        /** Standard-Akzent wie im Web (kein data-accent-Attribut). */
        const val ACCENT_DEFAULT = "black"
        // Diese Überarbeitung des Einstiegs einmalig auch auf bereits
        // installierten, abgemeldeten Geräten zeigen.
        private const val CURRENT_ONBOARDING_VERSION = 2
    }
}
