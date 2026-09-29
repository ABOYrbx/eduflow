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

    /// Englische Rückfalltexte je Code (Backend-Texte haben Vorrang).
    public static func englishFallback(for code: String) -> String {
        switch code {
        case ErrorCodes.validation:
            return NSLocalizedString("common_error_validation", value: "Invalid input. Please check and try again.", comment: "Fehler: ungültige Eingabe")
        case ErrorCodes.tokenInvalid:
            return NSLocalizedString("common_error_token_invalid", value: "Session invalid. Please sign in again.", comment: "Fehler: Sitzung ungültig")
        case ErrorCodes.tokenExpired:
            return NSLocalizedString("common_error_token_expired", value: "Session expired. Please sign in again.", comment: "Fehler: Sitzung abgelaufen")
        case ErrorCodes.pendingInvalid:
            return NSLocalizedString("common_error_pending_invalid", value: "Intermediate step expired. Please sign in again.", comment: "Fehler: Zwischenschritt abgelaufen")
        case ErrorCodes.invalidCode:
            return NSLocalizedString("common_error_invalid_code", value: "The code was not accepted. Please try again.", comment: "Fehler: Code nicht akzeptiert")
        case ErrorCodes.badCredentials:
            return NSLocalizedString("common_error_bad_credentials", value: "Wrong username, password or subdomain.", comment: "Fehler: falsche Zugangsdaten")
        case ErrorCodes.edupage2FA:
            return NSLocalizedString("common_error_edupage_2fa", value: "EduPage requires a code again. Please sign in again.", comment: "Fehler: EduPage verlangt Code")
        case ErrorCodes.captchaRequired:
            return NSLocalizedString("common_error_captcha_required", value: "EduPage requires a captcha. Please sign in via browser once.", comment: "Fehler: Captcha erforderlich")
        case ErrorCodes.notFound:
            return NSLocalizedString("common_error_not_found", value: "Not found.", comment: "Fehler: nicht gefunden")
        case ErrorCodes.rateLimited:
            return NSLocalizedString("common_error_rate_limited", value: "Too many attempts. Please try again later.", comment: "Fehler: zu viele Versuche")
        case ErrorCodes.configMissing:
            return NSLocalizedString("common_error_config_missing", value: "Server key missing. Please try again later.", comment: "Fehler: Server-Schlüssel fehlt")
        default:
            return NSLocalizedString("common_error_upstream", value: "Request failed. Please try again later.", comment: "Fehler: Anfrage fehlgeschlagen")
        }
    }
}
