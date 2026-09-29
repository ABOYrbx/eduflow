package de.eduflow.android.data

import de.eduflow.android.R
import de.eduflow.android.data.dto.ApiErrorDto
import de.eduflow.android.data.dto.ErrorCodes
import kotlinx.serialization.json.Json
import retrofit2.Response

/** Geworfene API-Fehler mit stabilem Code (api/core.py ERROR_CODES). */
class ApiException(
    val code: String,
    override val message: String,
    val httpStatus: Int = 0,
    /**
     * Optionale String-Ressource für die lokalisierte Anzeige (Compose löst
     * sie per stringResource auf, sonst gilt [message] als Fallback).
     * Für Server-Fehler null — Backend-Texte haben Vorrang.
     */
    val messageRes: Int? = null,
) : RuntimeException(message)

/**
 * Deutsche Fallback-Texte je Code (Backend-Texte haben Vorrang).
 *
 * Dokumentierte Ausnahme: Diese Ebene bleibt bewusst kontextfrei (kein
 * Context), damit Unit-Tests offline laufen. Die übersetzten
 * `error_*`-Strings (values/strings.xml) werden an den Call-Sites per
 * [stringResFor] + `localizedApiMessage` (ui/timetable/DayScreen.kt)
 * aufgelöst, sobald die Meldung aus diesem Fallback stammt.
 */
object ErrorMapper {
    fun messageFor(code: String): String = when (code) {
        ErrorCodes.VALIDATION -> "Ungültige Eingabe. Bitte prüfen und erneut versuchen."
        ErrorCodes.TOKEN_INVALID -> "Sitzung ungültig. Bitte erneut anmelden."
        ErrorCodes.TOKEN_EXPIRED -> "Sitzung abgelaufen. Bitte erneut anmelden."
        ErrorCodes.PENDING_INVALID -> "Zwischenschritt abgelaufen. Bitte erneut anmelden."
        ErrorCodes.INVALID_CODE -> "Der Code wurde nicht akzeptiert. Bitte erneut versuchen."
        ErrorCodes.BAD_CREDENTIALS -> "Falsche Anmeldedaten. Bitte Benutzername, Passwort und Subdomain prüfen."
        ErrorCodes.EDUPAGE_2FA -> "EduPage verlangt erneut einen Code. Bitte neu anmelden."
        ErrorCodes.CAPTCHA_REQUIRED ->
            "EduPage verlangt ein Captcha. Bitte einmal im Browser anmelden."
        ErrorCodes.NOT_FOUND -> "Nicht gefunden."
        ErrorCodes.RATE_LIMITED -> "Zu viele Versuche. Bitte später erneut versuchen."
        ErrorCodes.CONFIG_MISSING -> "Server-Schlüssel fehlt. Bitte später erneut versuchen."
        else -> "Anmeldung fehlgeschlagen. Bitte später erneut versuchen."
    }

    /**
     * Code -> übersetzter `error_*`-String (values/strings.xml).
     * Kontextfrei (nur Res-ID, kein Context) — Compose löst per
     * stringResource auf. Unbekannte Codes fallen auf error_upstream,
     * parallel zu [messageFor].
     */
    fun stringResFor(code: String): Int = when (code) {
        ErrorCodes.VALIDATION -> R.string.error_validation
        ErrorCodes.TOKEN_INVALID -> R.string.error_token_invalid
        ErrorCodes.TOKEN_EXPIRED -> R.string.error_token_expired
        ErrorCodes.PENDING_INVALID -> R.string.error_pending_invalid
        ErrorCodes.INVALID_CODE -> R.string.error_invalid_code
        ErrorCodes.BAD_CREDENTIALS -> R.string.error_bad_credentials
        ErrorCodes.EDUPAGE_2FA -> R.string.error_edupage_2fa
        ErrorCodes.CAPTCHA_REQUIRED -> R.string.error_captcha_required
        ErrorCodes.NOT_FOUND -> R.string.error_not_found
        ErrorCodes.RATE_LIMITED -> R.string.error_rate_limited
        ErrorCodes.CONFIG_MISSING -> R.string.error_config_missing
        else -> R.string.error_upstream
    }

    private val lenient = Json { ignoreUnknownKeys = true; isLenient = true }

    fun parseErrorBody(raw: String?): Pair<String, String> {
        if (raw.isNullOrBlank()) return "UPSTREAM" to messageFor("UPSTREAM")
        return try {
            val dto = lenient.decodeFromString(ApiErrorDto.serializer(), raw)
            val code = dto.code.ifBlank { "UPSTREAM" }
            val msg = dto.error.ifBlank { messageFor(code) }
            code to msg
        } catch (_: Exception) {
            "UPSTREAM" to messageFor("UPSTREAM")
        }
    }
}

/** Erfolgreiche Antwort auspacken oder ApiException mit (code, message, status) werfen. */
suspend fun <T> Response<T>.unwrap(): T {
    if (isSuccessful) {
        return body() ?: throw ApiException("UPSTREAM", ErrorMapper.messageFor("UPSTREAM"), code())
    }
    val raw = try { errorBody()?.string() } catch (_: Exception) { null }
    val (code, message) = ErrorMapper.parseErrorBody(raw)
    throw ApiException(code, message, code())
}
