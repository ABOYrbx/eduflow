package de.eduflow.android.data

import de.eduflow.android.data.dto.ApiErrorDto
import de.eduflow.android.data.dto.ErrorCodes
import kotlinx.serialization.json.Json
import retrofit2.Response

/** Geworfene API-Fehler mit stabilem Code (api/core.py ERROR_CODES). */
class ApiException(
    val code: String,
    override val message: String,
    val httpStatus: Int = 0,
) : RuntimeException(message)

/** Deutsche Fallback-Texte je Code (Backend-Texte haben Vorrang). */
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
