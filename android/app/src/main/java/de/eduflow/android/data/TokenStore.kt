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

/** Pfad, den die App anhaengt — die Routen liegen unter `/api/v1`. */
private const val API_PATH = "/api/v1"

/** Authority als `host` oder `host:port`; Host darf IPv6 in Klammern sein. */
private val AUTHORITY = Regex("""^(\[[^\]]+\]|[^:/?#]+)(:\d+)?$""")

/**
 * Basis-URL normalisieren (Paket 0). Eingabe ist bewusst kurz: die
 * Nutzerin tippt nur die IP des Servers, optional mit Port
 * (`192.168.1.5` oder `192.168.1.5:3100`). Scheme, Port und Pfad
 * ergaenzt die App:
 *
 *     192.168.1.5        -> http://192.168.1.5:3000/api/v1/
 *     192.168.1.5:3100   -> http://192.168.1.5:3100/api/v1/
 *     mein-mac.local     -> http://mein-mac.local:3000/api/v1/
 *
 * Vollstaendige URLs bleiben gueltig (Alteingaben aus aelteren
 * App-Versionen und Werte aus dem Chatverlauf): ein bereits
 * gesetzter Scheme bleibt, ein gesetzter Port bleibt, und ein
 * vorhandenes `/api/v1` wird abgeschnitten, bevor der Pfad erneut
 * angehaengt wird — sonst entstuende `/api/v1/api/v1`.
 *
 * Leer -> interner Notfallwert. Er wird nirgends angezeigt oder
 * vorbelegt, existiert nur, damit Retrofit nie eine leere URL
 * bekommt (das waere ein IllegalArgumentException beim Start).
 */
internal fun normalizeBaseUrl(raw: String): String {
    val input = raw.trim().trimEnd('/')
    if (input.isBlank()) return TokenStore.DEFAULT_BASE_URL

    // Scheme ergaenzen, falls keins da ist.
    val withScheme = if ("://" in input) input else "http://$input"

    val scheme = withScheme.substringBefore("://")
    val rest = withScheme.substringAfter("://")
    // Pfad abtrennen, damit die Authority unten isoliert ist.
    val authority = rest.substringBefore('/')
    val path = rest.substringAfter('/', "")

    // Authority muss host oder host:port sein, sonst nichts aendern:
    // eine kaputte Eingabe soll als Fehler auffallen, nicht still
    // zu einem falschen Server fuehren.
    val match = AUTHORITY.matchEntire(authority) ?: return withScheme
    val host = match.groupValues[1]
    val port = match.groupValues[2].ifEmpty { ":${TokenStore.DEFAULT_PORT}" }

    // Doppelten API-Pfad vermeiden. removeSuffix trifft nur das letzte
    // Vorkommen, darum in einer Schleife — sonst bliebe bei
    // ".../api/v1/api/v1" ein "api/v1" uebrig.
    var cleanPath = path.trim('/')
    // Auch der reine Pfad ohne fuehrenden Slash ("api/v1") muss weg,
    // sonst haette die letzte Runde nichts mehr zu entfernen.
    val bareApiPath = API_PATH.trimStart('/')
    while (cleanPath.endsWith(API_PATH) || cleanPath == bareApiPath) {
        cleanPath = cleanPath.removeSuffix(API_PATH).removeSuffix(bareApiPath).trim('/')
    }

    return buildString {
        append(scheme).append("://").append(host).append(port).append(API_PATH).append('/')
        if (cleanPath.isNotEmpty()) append(cleanPath).append('/')
    }
}

/** Port aus einer beliebigen Server-Eingabe, oder null wenn keiner erkennbar ist. */
private fun portOf(normalized: String): String? =
    normalized.substringAfter("://").substringBefore('/').substringAfterLast(':', "")
        .takeIf { it.isNotEmpty() && it.all { ch -> ch.isDigit() } }

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
        val baseUrl = prefs[Keys.BASE_URL] ?: DEFAULT_BASE_URL
        Session(
            token = prefs[Keys.TOKEN].orEmpty(),
            expires = prefs[Keys.EXPIRES].orEmpty(),
            subdomain = prefs[Keys.SUBDOMAIN].orEmpty(),
            username = prefs[Keys.USERNAME].orEmpty(),
            baseUrl = baseUrl,
            // Demo-Modus gilt automatisch bei Verbindung zum Demo-Server
            // (kein separater Schalter in der UI).
            isDemo = isDemoServerUrl(baseUrl),
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

    /**
     * Server-Adresse speichern. Leere Eingabe ignoriert die App bewusst:
     * ein leeres Feld darf die bestehende Konfiguration nicht ueberschreiben
     * (sonst loescht schon ein Tippen im Feld den Server).
     */
    suspend fun setBaseUrl(baseUrl: String) {
        if (baseUrl.isBlank()) return
        context.tokenDataStore.edit { prefs ->
            if (prefs[Keys.DEMO_MODE] == true) {
                prefs[Keys.BASE_URL] = DEMO_BASE_URL.trimEnd('/')
                prefs[Keys.DEMO_MODE] = true
            } else {
                val normalized = normalizeBaseUrl(baseUrl).trimEnd('/')
                prefs[Keys.BASE_URL] = normalized
                // Demo-Server-Adresse schaltet den Demo-Modus automatisch ein.
                prefs[Keys.DEMO_MODE] = isDemoServerUrl(normalized)
            }
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
        /**
         * Reiner Notfallwert: greift nur, wenn ohne gespeicherten Server
         * und ohne Eingabe ein Client gebaut wird. In der Oberflaeche wird
         * nichts vorbelegt und nichts angezeigt — die Eingabe ist leer,
         * die Nutzerin tippt die IP selbst.
         */
        const val DEFAULT_BASE_URL = "http://10.0.2.2:3000/api/v1/"

        /** Demo-Server des Fake-Providers (`./run.sh --demo`). */
        const val DEMO_BASE_URL = "http://10.0.2.2:3100/api/v1/"

        /** Port, an dem der Demo-Server laeuft. */
        const val DEMO_PORT = 3100

        /**
         * Beispiel fuer das Server-Feld. Ist ein *Hinweis* im Placeholder,
         * kein Wert — das Feld startet leer.
         */
        const val SERVER_PLACEHOLDER = "192.168.1.5"

        /**
         * Port, den die App annimmt, wenn die Eingabe nur eine IP ist. Die
         * Eingabe darf trotzdem einen eigenen Port mitbringen (`IP:Port`) —
         * etwa [DEMO_PORT] fuer den Demo-Server.
         */
        const val DEFAULT_PORT = 3000

        /**
         * Demo-Server erkannt? Der Demo-Modus gilt automatisch, sobald die
         * Adresse auf dem Demo-Port [DEMO_PORT] liegt — bewusst nur nach dem
         * Port und nicht nach der vollen URL: sonst waere ein Demo-Server
         * unter `192.168.1.5:3100` (Handy im WLAN) kein Demo mehr, weil die
         * Host-IP von [DEMO_BASE_URL] abweicht.
         */
        fun isDemoServerUrl(raw: String): Boolean =
            portOf(normalizeBaseUrl(raw)) == DEMO_PORT.toString()

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
