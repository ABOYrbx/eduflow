package de.eduflow.android.data

import de.eduflow.android.data.dto.DeviceDto
import de.eduflow.android.data.dto.LoginRequest
import de.eduflow.android.data.dto.LoginResponse
import de.eduflow.android.data.dto.MeDto
import de.eduflow.android.data.dto.TwoFaRequest

/**
 * Lesbarer Gerätebezeichner; Emulator-Builds liefern sonst interne SDK-Namen.
 *
 * Dokumentierte Ausnahme: [emulatorLabel] defaultet deutsch
 * ("Android-Emulator"), weil das Repository keinen Context hat. Die UI
 * übergibt den übersetzten `device_default_name`-String (LoginScreen);
 * der Name landet auf dem Server und in der Geräte-Liste.
 */
internal fun defaultDeviceName(emulatorLabel: String = "Android-Emulator"): String {
    val model = android.os.Build.MODEL.orEmpty().trim()
    return if (model.isBlank() || model.startsWith("sdk_gphone", ignoreCase = true)) {
        emulatorLabel
    } else {
        model
    }
}

/** Ergebnis des Login-Ablaufs (normal oder 2FA-Pflicht). */
sealed interface LoginResult {
    data class LoggedIn(val response: LoginResponse) : LoginResult
    data class TwoFaRequired(val pendingToken: String, val message: String) : LoginResult
}

/** EduPage-Login-Ablauf über /api/v1 (Paket A). */
class AuthRepository(
    private val api: () -> ApiService,
    private val store: TokenStore,
) {
    suspend fun login(username: String, password: String, subdomain: String, deviceName: String = ""): LoginResult {
        val device = deviceName.trim().ifBlank { defaultDeviceName() }
        val res = api().login(LoginRequest(username.trim(), password, subdomain.trim(), device)).unwrap()
        if (res.isTwoFa) {
            return LoginResult.TwoFaRequired(res.pending_token, res.message)
        }
        store.save(res.token, res.expires, res.subdomain, username.trim())
        return LoginResult.LoggedIn(res)
    }

    suspend fun submit2fa(pendingToken: String, code: String): LoginResponse {
        val res = api().submit2fa(TwoFaRequest(pendingToken.trim(), code.trim())).unwrap()
        store.save(res.token, res.expires, res.subdomain, res.username)
        return res
    }

    suspend fun me(): MeDto = api().me().unwrap()

    suspend fun devices(): List<DeviceDto> = api().devices().unwrap().items

    /** Logout: Server widerrufen (best-effort) + lokalen Store immer leeren. */
    suspend fun logout() {
        try {
            api().logout()
        } catch (_: Exception) {
            // Best-effort: lokaler Logout gilt auch bei Netz-/Token-Fehler.
        } finally {
            store.clear()
        }
    }

    /** Token rotieren (alt → neu), Sitzung aktualisieren. */
    suspend fun refresh(): LoginResponse {
        val res = api().refresh().unwrap()
        store.save(res.token, res.expires, res.subdomain, res.username)
        return res
    }

    suspend fun revokeDevice(id: String) {
        api().revokeDevice(id).unwrap()
    }
}
