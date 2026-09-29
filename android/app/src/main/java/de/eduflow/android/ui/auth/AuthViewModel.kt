package de.eduflow.android.ui.auth

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import de.eduflow.android.R
import de.eduflow.android.data.ApiException
import de.eduflow.android.data.AuthRepository
import de.eduflow.android.data.ErrorMapper
import de.eduflow.android.data.dto.ErrorCodes
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch

sealed interface LoginUiState {
    data object Idle : LoginUiState
    data object Loading : LoginUiState
    data class TwoFa(val pendingToken: String, val message: String) : LoginUiState
    /**
     * Clientseitige Validierung (leere Felder) setzt [messageRes] auf den
     * übersetzten String; Compose löst per stringResource auf, sonst gilt
     * [message] (deutscher Fallback für kontextfreie Unit-Tests).
     */
    data class Error(val message: String, val code: String, val messageRes: Int? = null) : LoginUiState
}

sealed interface TwoFaUiState {
    data object Idle : TwoFaUiState
    data object Loading : TwoFaUiState
    data class Error(val message: String, val code: String, val messageRes: Int? = null) : TwoFaUiState
}

class AuthViewModel(private val repo: AuthRepository) : ViewModel() {

    private val _login = MutableStateFlow<LoginUiState>(LoginUiState.Idle)
    val login: StateFlow<LoginUiState> = _login

    private val _twoFa = MutableStateFlow<TwoFaUiState>(TwoFaUiState.Idle)
    val twoFa: StateFlow<TwoFaUiState> = _twoFa

    private val _loggedOut = MutableStateFlow(false)
    val loggedOut: StateFlow<Boolean> = _loggedOut

    fun login(username: String, password: String, device: String = "") {
        if (username.isBlank() || password.isBlank()) {
            _login.value = LoginUiState.Error(
                "Bitte Benutzername und Passwort angeben.", ErrorCodes.VALIDATION,
                R.string.auth_error_credentials,
            )
            return
        }
        _login.value = LoginUiState.Loading
        viewModelScope.launch {
            try {
                // Subdomain leer: Server löst die Schule automatisch auf.
                when (val r = repo.login(username, password, "", device)) {
                    is de.eduflow.android.data.LoginResult.LoggedIn -> {
                        _login.value = LoginUiState.Idle
                    }
                    is de.eduflow.android.data.LoginResult.TwoFaRequired -> {
                        _login.value = LoginUiState.TwoFa(r.pendingToken, r.message)
                    }
                }
            } catch (e: ApiException) {
                _login.value = LoginUiState.Error(e.message, e.code)
            } catch (_: Exception) {
                _login.value = LoginUiState.Error(
                    ErrorMapper.messageFor("UPSTREAM"), "UPSTREAM",
                )
            }
        }
    }

    fun submit2fa(pendingToken: String, code: String, onDone: () -> Unit) {
        if (code.isBlank()) {
            _twoFa.value = TwoFaUiState.Error(
                "Bitte Code angeben.", ErrorCodes.VALIDATION,
                R.string.twofa_error_empty,
            )
            return
        }
        _twoFa.value = TwoFaUiState.Loading
        viewModelScope.launch {
            try {
                repo.submit2fa(pendingToken, code)
                _twoFa.value = TwoFaUiState.Idle
                onDone()
            } catch (e: ApiException) {
                _twoFa.value = TwoFaUiState.Error(e.message, e.code)
            } catch (_: Exception) {
                _twoFa.value = TwoFaUiState.Error(
                    ErrorMapper.messageFor("UPSTREAM"), "UPSTREAM",
                )
            }
        }
    }

    fun logout(onDone: () -> Unit) {
        viewModelScope.launch {
            try {
                repo.logout()
            } finally {
                _loggedOut.value = true
                onDone()
            }
        }
    }

    fun consumeLoginError() {
        if (_login.value is LoginUiState.Error) _login.value = LoginUiState.Idle
    }

    /**
     * TwoFa-Navigation konsumieren: Ohne Reset würde der Login-Screen nach
     * „Zurück" aus der 2FA sofort wieder dorthin navigieren (staler State).
     */
    fun consumeTwoFaState() {
        if (_login.value is LoginUiState.TwoFa) _login.value = LoginUiState.Idle
    }
}
