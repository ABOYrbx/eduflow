import Foundation

// MARK: - API-Fehler mit stabilem Code (Paket 0)
//
// 1:1 aus api/core.py (ERROR_CODES). Deutsche Fallback-Texte je Code
// (Backend-Texte haben Vorrang). Keine Secrets/Stacktraces in UI/Logs.

struct APIError: Error, LocalizedError {
    let code: String
    let message: String
    let httpStatus: Int

    var errorDescription: String? { message }

    /// 401-Verhalten: Sitzung ungültig/abgelaufen oder EduPage-2FA → Login.
    var needsReLogin: Bool {
        code == "TOKEN_INVALID" || code == "TOKEN_EXPIRED" || code == "EDUPAGE_2FA"
    }

    static func message(for code: String) -> String {
        switch code {
        case "VALIDATION":
            return "Ungültige Eingabe. Bitte prüfen und erneut versuchen."
        case "TOKEN_INVALID":
            return "Sitzung ungültig. Bitte erneut anmelden."
        case "TOKEN_EXPIRED":
            return "Sitzung abgelaufen. Bitte erneut anmelden."
        case "PENDING_INVALID":
            return "Zwischenschritt abgelaufen. Bitte erneut anmelden."
        case "INVALID_CODE":
            return "Der Code wurde nicht akzeptiert. Bitte erneut versuchen."
        case "BAD_CREDENTIALS":
            return "Falscher Benutzername, Passwort oder Subdomain."
        case "EDUPAGE_2FA":
            return "EduPage verlangt erneut einen Code. Bitte neu anmelden."
        case "CAPTCHA_REQUIRED":
            return "EduPage verlangt ein Captcha. Bitte einmal im Browser anmelden."
        case "NOT_FOUND":
            return "Nicht gefunden."
        case "RATE_LIMITED":
            return "Zu viele Versuche. Bitte später erneut versuchen."
        case "CONFIG_MISSING":
            return "Server-Schlüssel fehlt. Bitte später erneut versuchen."
        default:
            return "Anfrage fehlgeschlagen. Bitte später erneut versuchen."
        }
    }
}
