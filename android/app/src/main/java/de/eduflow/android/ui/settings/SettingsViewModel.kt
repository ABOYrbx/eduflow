package de.eduflow.android.ui.settings

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import de.eduflow.android.data.ApiException
import de.eduflow.android.data.AuthRepository
import de.eduflow.android.data.ErrorMapper
import de.eduflow.android.data.SettingsRepository
import de.eduflow.android.data.TokenStore
import de.eduflow.android.data.dto.DeviceDto
import de.eduflow.android.data.dto.ErrorCodes
import de.eduflow.android.data.dto.SettingsValues
import de.eduflow.android.data.dto.WetterCitySuggestion
import de.eduflow.android.data.Session
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

data class SettingsUiState(
    val loading: Boolean = true,
    val values: SettingsValues = SettingsValues(),
    val error: String? = null,
    val saved: Boolean = false,
    val cleared: Int? = null,
    val devices: List<DeviceDto> = emptyList(),
    val devicesLoading: Boolean = false,
    val weatherCitySuggestions: List<WetterCitySuggestion> = emptyList(),
    val weatherCitySearchLoading: Boolean = false,
    val weatherCitySearchComplete: Boolean = false,
    val weatherCitySearchError: String? = null,
    /** 401-Verhalten (→ Login): Token ungültig/abgelaufen, Store ist geleert. */
    val sessionExpired: Boolean = false,
)

class SettingsViewModel(
    private val settingsRepo: SettingsRepository,
    private val authRepo: AuthRepository,
    private val store: TokenStore,
) : ViewModel() {

    private var weatherCitySearchJob: Job? = null

    private val _state = MutableStateFlow(SettingsUiState())
    val state: StateFlow<SettingsUiState> = _state

    /** Aussehen wie im Web (static/theme.js, lokal gespeichert). */
    val themeChoice: StateFlow<String> = store.themeFlow
        .stateIn(viewModelScope, SharingStarted.Eagerly, TokenStore.THEME_SYSTEM)
    val accentKey: StateFlow<String> = store.accentFlow
        .stateIn(viewModelScope, SharingStarted.Eagerly, TokenStore.ACCENT_DEFAULT)
    val developerOptions: StateFlow<Boolean> = store.developerOptionsFlow
        .stateIn(viewModelScope, SharingStarted.Eagerly, false)

    /** Navigationsleisten-Belegung (gerätelokal, Mehr immer angepinnt). */
    val navTabs: StateFlow<String> = store.navTabsFlow
        .stateIn(viewModelScope, SharingStarted.Eagerly, "")

    fun setNavTabs(routes: List<String>) {
        viewModelScope.launch { store.setNavTabs(routes) }
    }

    /** Sitzung für die Profil-Karte (Name, Schule – nie den Token zeigen). */
    val session: StateFlow<Session> = store.sessionFlow
        .stateIn(viewModelScope, SharingStarted.Eagerly, Session())

    fun setTheme(theme: String) {
        viewModelScope.launch { store.setTheme(theme) }
    }

    fun setAccent(accent: String) {
        viewModelScope.launch { store.setAccent(accent) }
    }

    fun setDeveloperOptions(enabled: Boolean) {
        viewModelScope.launch { store.setDeveloperOptions(enabled) }
    }

    /** Logout best-effort and clear the local session before restarting onboarding. */
    fun restartOnboarding(onDone: () -> Unit) {
        viewModelScope.launch {
            try { authRepo.logout() } catch (_: Exception) { }
            try {
                store.clear()
                store.resetOnboarding()
            } finally {
                onDone()
            }
        }
    }

    init {
        // Der NavGraph erzeugt dieses VM eager bei jedem App-Start — ohne
        // Sitzung keine authentifizierten Requests feuern (sonst 401-Rauschen
        // im Server-Log, z. B. GET /devices). Die Screens laden beim Öffnen
        // frisch (LaunchedEffect in SettingsScreen/DevicesScreen).
        viewModelScope.launch {
            if (store.currentSession().isLoggedIn) {
                reload()
                reloadDevices()
            } else {
                _state.value = _state.value.copy(loading = false)
            }
        }
    }

    fun reload() {
        weatherCitySearchJob?.cancel()
        _state.value = _state.value.copy(
            loading = true, error = null, saved = false, sessionExpired = false,
            weatherCitySuggestions = emptyList(),
            weatherCitySearchLoading = false,
            weatherCitySearchComplete = false,
            weatherCitySearchError = null,
        )
        viewModelScope.launch {
            try {
                val (_, values) = settingsRepo.load()
                _state.value = _state.value.copy(loading = false, values = values)
            } catch (e: ApiException) {
                if (!noteAuthFailure(e)) {
                    _state.value = _state.value.copy(loading = false, error = e.message)
                }
            } catch (_: Exception) {
                _state.value = _state.value.copy(
                    loading = false, error = ErrorMapper.messageFor("UPSTREAM"),
                )
            }
        }
    }

    fun update(values: SettingsValues) {
        weatherCitySearchJob?.cancel()
        _state.value = _state.value.copy(
            values = values,
            saved = false,
            error = null,
            weatherCitySuggestions = emptyList(),
            weatherCitySearchLoading = false,
            weatherCitySearchComplete = false,
            weatherCitySearchError = null,
        )
    }

    /** Debounced Stadtsuche; Treffer bleiben bis zur Auswahl im Server-Ergebnis. */
    fun searchWeatherCities(rawQuery: String) {
        weatherCitySearchJob?.cancel()
        val query = rawQuery.trim().take(100)
        if (query.length < 2) {
            _state.value = _state.value.copy(
                weatherCitySuggestions = emptyList(),
                weatherCitySearchLoading = false,
                weatherCitySearchComplete = false,
                weatherCitySearchError = null,
            )
            return
        }
        weatherCitySearchJob = viewModelScope.launch {
            delay(250)
            if (_state.value.values.wetterCity.trim() != query) return@launch
            _state.value = _state.value.copy(
                weatherCitySearchLoading = true,
                weatherCitySearchComplete = false,
                weatherCitySearchError = null,
                weatherCitySuggestions = emptyList(),
            )
            try {
                val matches = settingsRepo.searchWetterCities(query)
                if (_state.value.values.wetterCity.trim() == query) {
                    _state.value = _state.value.copy(
                        weatherCitySuggestions = matches,
                        weatherCitySearchLoading = false,
                        weatherCitySearchComplete = true,
                    )
                }
            } catch (e: ApiException) {
                if (!noteAuthFailure(e) && _state.value.values.wetterCity.trim() == query) {
                    _state.value = _state.value.copy(
                        weatherCitySearchLoading = false,
                        weatherCitySearchComplete = true,
                        weatherCitySearchError = e.message,
                    )
                }
            } catch (_: Exception) {
                if (_state.value.values.wetterCity.trim() == query) {
                    _state.value = _state.value.copy(
                        weatherCitySearchLoading = false,
                        weatherCitySearchComplete = true,
                        weatherCitySearchError = ErrorMapper.messageFor("UPSTREAM"),
                    )
                }
            }
        }
    }

    fun clearWeatherCitySuggestions() {
        weatherCitySearchJob?.cancel()
        _state.value = _state.value.copy(
            weatherCitySuggestions = emptyList(),
            weatherCitySearchLoading = false,
            weatherCitySearchComplete = false,
            weatherCitySearchError = null,
        )
    }

    fun save() {
        weatherCitySearchJob?.cancel()
        _state.value = _state.value.copy(
            weatherCitySuggestions = emptyList(),
            weatherCitySearchLoading = false,
        )
        viewModelScope.launch {
            try {
                val saved = settingsRepo.save(_state.value.values)
                _state.value = _state.value.copy(values = saved, saved = true)
            } catch (e: ApiException) {
                if (!noteAuthFailure(e)) {
                    _state.value = _state.value.copy(error = e.message)
                }
            } catch (_: Exception) {
                _state.value = _state.value.copy(error = ErrorMapper.messageFor("UPSTREAM"))
            }
        }
    }

    /**
     * 401-Verhalten (→ Login, ANDROID.md §1): TOKEN_INVALID/TOKEN_EXPIRED
     * leert den Store und setzt [SettingsUiState.sessionExpired], damit die
     * Screens zum Login navigieren. Gilt nur mit gespeicherter Sitzung —
     * ohne Login (z. B. Eager-Load im NavGraph) ist es nur ein Fehlertext.
     * Der Store wird direkt geleert (kein Server-Logout: ein toter Token
     * ließe sich serverseitig eh nicht widerrufen und loggt nur ein
     * weiteres 401). Returns true, wenn der Expired-Pfad genommen wurde.
     */
    private suspend fun noteAuthFailure(e: ApiException): Boolean {
        if (e.code != ErrorCodes.TOKEN_INVALID && e.code != ErrorCodes.TOKEN_EXPIRED) {
            return false
        }
        if (!store.currentSession().isLoggedIn) return false
        try {
            store.clear()
        } catch (_: Exception) {
        }
        _state.value = _state.value.copy(
            loading = false, devicesLoading = false,
            error = null, sessionExpired = true,
        )
        return true
    }

    fun reloadDevices() {
        _state.value = _state.value.copy(devicesLoading = true)
        viewModelScope.launch {
            try {
                // Wichtig: erst das Ergebnis abwarten, dann den State lesen.
                // Ein `copy(devices = authRepo.devices(), …)` liest _state.value
                // VOR dem Suspend und schreibt danach eine Kopie des alten
                // Zustands zurück — dabei riss es das zwischenzeitlich auf
                // loading=false gesetzte Feld wieder auf true und der Screen
                // blieb dauerhaft im Lade-Spinner (Settings, ~1 s nach /devices).
                val devices = authRepo.devices()
                _state.value = _state.value.copy(devices = devices, devicesLoading = false)
            } catch (e: ApiException) {
                if (!noteAuthFailure(e)) {
                    _state.value = _state.value.copy(devicesLoading = false)
                }
            } catch (_: Exception) {
                _state.value = _state.value.copy(devicesLoading = false)
            }
        }
    }

    fun revokeDevice(id: String) {
        viewModelScope.launch {
            try {
                authRepo.revokeDevice(id)
            } catch (e: ApiException) {
                if (noteAuthFailure(e)) return@launch
            } catch (_: Exception) {
            } finally {
                if (!_state.value.sessionExpired) reloadDevices()
            }
        }
    }

    fun clearCache() {
        viewModelScope.launch {
            try {
                val res = settingsRepo.clearCache()
                _state.value = _state.value.copy(cleared = res.cleared)
            } catch (e: ApiException) {
                if (!noteAuthFailure(e)) {
                    _state.value = _state.value.copy(error = e.message)
                }
            } catch (_: Exception) {
                _state.value = _state.value.copy(error = ErrorMapper.messageFor("UPSTREAM"))
            }
        }
    }

    fun setBaseUrl(url: String) {
        viewModelScope.launch {
            val normalized = url.trim().trimEnd('/')
                .ifBlank { TokenStore.DEFAULT_BASE_URL.trimEnd('/') }
            store.setBaseUrl(normalized)
        }
    }

    fun logout(onDone: () -> Unit) {
        viewModelScope.launch {
            try {
                authRepo.logout()
            } finally {
                // Abmelden heißt: wieder durchs Onboarding. Sonst landet der
                // nächste Start direkt im Login (Flag bleibt sonst gesetzt).
                runCatching { store.resetOnboarding() }
                onDone()
            }
        }
    }
}
