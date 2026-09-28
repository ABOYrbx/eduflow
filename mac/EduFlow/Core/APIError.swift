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
            return NSLocalizedString("common_error_validation", value: "Ungültige Eingabe. Bitte prüfen und erneut versuchen.", comment: "Fehler: ungültige Eingabe")
        case ErrorCodes.tokenInvalid:
            return NSLocalizedString("common_error_token_invalid", value: "Sitzung ungültig. Bitte erneut anmelden.", comment: "Fehler: Sitzung ungültig")
        case ErrorCodes.tokenExpired:
            return NSLocalizedString("common_error_token_expired", value: "Sitzung abgelaufen. Bitte erneut anmelden.", comment: "Fehler: Sitzung abgelaufen")
        case ErrorCodes.pendingInvalid:
            return NSLocalizedString("common_error_pending_invalid", value: "Zwischenschritt abgelaufen. Bitte erneut anmelden.", comment: "Fehler: Zwischenschritt abgelaufen")
        case ErrorCodes.invalidCode:
            return NSLocalizedString("common_error_invalid_code", value: "Der Code wurde nicht akzeptiert. Bitte erneut versuchen.", comment: "Fehler: Code nicht akzeptiert")
        case ErrorCodes.badCredentials:
            return NSLocalizedString("common_error_bad_credentials", value: "Falscher Benutzername oder Passwort.", comment: "Fehler: falsche Zugangsdaten")
        case ErrorCodes.edupage2FA:
            return NSLocalizedString("common_error_edupage_2fa", value: "EduPage verlangt erneut einen Code. Bitte neu anmelden.", comment: "Fehler: EduPage verlangt Code")
        case ErrorCodes.captchaRequired:
            return NSLocalizedString("common_error_captcha_required", value: "EduPage verlangt ein Captcha. Bitte einmal im Browser anmelden.", comment: "Fehler: Captcha erforderlich")
        case ErrorCodes.notFound:
            return NSLocalizedString("common_error_not_found", value: "Nicht gefunden.", comment: "Fehler: nicht gefunden")
        case ErrorCodes.rateLimited:
            return NSLocalizedString("common_error_rate_limited", value: "Zu viele Versuche. Bitte später erneut versuchen.", comment: "Fehler: zu viele Versuche")
        case ErrorCodes.configMissing:
            return NSLocalizedString("common_error_config_missing", value: "Server-Schlüssel fehlt. Bitte später erneut versuchen.", comment: "Fehler: Server-Schlüssel fehlt")
        default:
            return NSLocalizedString("common_error_upstream", value: "Anfrage fehlgeschlagen. Bitte später erneut versuchen.", comment: "Fehler: Anfrage fehlgeschlagen")
        }
    }
}
