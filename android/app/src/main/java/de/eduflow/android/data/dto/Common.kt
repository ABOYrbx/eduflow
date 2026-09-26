package de.eduflow.android.data.dto

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/** Hüllobjekt aller Listen: {items, total, limit, offset} (BACKEND.md §1). */
@Serializable
data class PageDto<T>(
    val items: List<T> = emptyList(),
    val total: Int = 0,
    val limit: Int = 50,
    val offset: Int = 0,
)

/** Kanonische Fehlerantwort: {error, code} (api/core.py ERROR_CODES). */
@Serializable
data class ApiErrorDto(
    val error: String = "",
    val code: String = "UPSTREAM",
)

/** Kanonische Fehlercodes (P0-vereinheitlicht, siehe api/core.py). */
object ErrorCodes {
    const val VALIDATION = "VALIDATION"
    const val TOKEN_INVALID = "TOKEN_INVALID"
    const val TOKEN_EXPIRED = "TOKEN_EXPIRED"
    const val PENDING_INVALID = "PENDING_INVALID"
    const val INVALID_CODE = "INVALID_CODE"
    const val BAD_CREDENTIALS = "BAD_CREDENTIALS"
    const val EDUPAGE_2FA = "EDUPAGE_2FA"
    const val CAPTCHA_REQUIRED = "CAPTCHA_REQUIRED"
    const val NOT_FOUND = "NOT_FOUND"
    const val RATE_LIMITED = "RATE_LIMITED"
    const val CONFIG_MISSING = "CONFIG_MISSING"
    const val UPSTREAM = "UPSTREAM"
}

/** Status-Antwort {status} für logout / cache-clear / revoke. */
@Serializable
data class StatusDto(
    val status: String = "ok",
)
