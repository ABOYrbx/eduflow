package de.eduflow.android.data.dto

import kotlinx.serialization.Serializable

@Serializable
data class LoginRequest(
    val username: String,
    val password: String,
    val subdomain: String = "",
    val device: String = "",
)

@Serializable
data class TwoFaRequest(
    val pending_token: String,
    val code: String,
)

/**
 * Login-Antwort: entweder ok (token, expires, subdomain, username)
 * oder 2fa_required (pending_token, message). Ein DTO für beide Fälle,
 * unterschieden über [status] — wie api/auth.py.
 */
@Serializable
data class LoginResponse(
    val status: String = "ok",
    val token: String = "",
    val expires: String = "",
    val subdomain: String = "",
    val username: String = "",
    val pending_token: String = "",
    val message: String = "",
) {
    val isOk: Boolean get() = status == "ok"
    val isTwoFa: Boolean get() = status == "2fa_required"
}

@Serializable
data class MeDto(
    val subdomain: String = "",
    val username: String = "",
)

@Serializable
data class DeviceDto(
    val id: String = "",
    val short: String = "",
    val device: String = "",
    val created: String = "",
    val expires: String = "",
)

@Serializable
data class DevicesDto(
    val items: List<DeviceDto> = emptyList(),
    val total: Int = 0,
)
