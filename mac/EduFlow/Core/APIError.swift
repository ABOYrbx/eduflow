import Foundation

/// Einheitlicher API-Fehler (Paket 0, eingefroren).
///
/// Abbildung des kanonischen Fehler-Vokabulars aus `api/core.py`
/// (`ERROR_CODES`): Jede Fehlerantwort hat die Form `{error, code}`;
/// dazu kommt der HTTP-Status. Deutsche Kurztexte, keine Secrets,
/// keine Stacktraces, keine Token.
public struct APIError: LocalizedError, Sendable {
    public let code: String
    public let message: String
    public let httpStatus: Int

    public init(code: String, message: String, httpStatus: Int = 0) {
        self.code = code
        self.message = message
        self.httpStatus = httpStatus
    }

    public var errorDescription: String? { message }

    /// Sitzung ungültig oder abgelaufen → Login (Speicher leeren).
    public var isSessionExpired: Bool {
        code == ErrorCodes.tokenInvalid || code == ErrorCodes.tokenExpired
    }

    /// Zurück zum Login (inklusive erneuter Zwei-Faktor-Pflicht serverseitig).
    public var needsReLogin: Bool {
        isSessionExpired || code == ErrorCodes.edupage2FA
    }

    /// Deutsche Rückfalltexte je Code (Backend-Texte haben Vorrang).
    public static func germanFallback(for code: String) -> String {
        switch code {
        case ErrorCodes.validation:
            return "Ungültige Eingabe. Bitte prüfen und erneut versuchen."
        case ErrorCodes.tokenInvalid:
            return "Sitzung ungültig. Bitte erneut anmelden."
        case ErrorCodes.tokenExpired:
            return "Sitzung abgelaufen. Bitte erneut anmelden."
        case ErrorCodes.pendingInvalid:
            return "Zwischenschritt abgelaufen. Bitte erneut anmelden."
        case ErrorCodes.invalidCode:
            return "Der Code wurde nicht akzeptiert. Bitte erneut versuchen."
        case ErrorCodes.badCredentials:
            return "Falscher Benutzername, Passwort oder Subdomain."
        case ErrorCodes.edupage2FA:
            return "EduPage verlangt erneut einen Code. Bitte neu anmelden."
        case ErrorCodes.captchaRequired:
            return "EduPage verlangt ein Captcha. Bitte einmal im Browser anmelden."
        case ErrorCodes.notFound:
            return "Nicht gefunden."
        case ErrorCodes.rateLimited:
            return "Zu viele Versuche. Bitte später erneut versuchen."
        case ErrorCodes.configMissing:
            return "Server-Schlüssel fehlt. Bitte später erneut versuchen."
        default:
            return "Anfrage fehlgeschlagen. Bitte später erneut versuchen."
        }
    }
}
