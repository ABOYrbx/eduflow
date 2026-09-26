import Foundation

/// Kanonische Fehlercodes 1:1 aus `api/core.py` (`ERROR_CODES`).
public enum ErrorCodes {
    public static let validation = "VALIDATION"
    public static let tokenInvalid = "TOKEN_INVALID"
    public static let tokenExpired = "TOKEN_EXPIRED"
    public static let pendingInvalid = "PENDING_INVALID"
    public static let invalidCode = "INVALID_CODE"
    public static let badCredentials = "BAD_CREDENTIALS"
    public static let edupage2FA = "EDUPAGE_2FA"
    public static let captchaRequired = "CAPTCHA_REQUIRED"
    public static let notFound = "NOT_FOUND"
    public static let rateLimited = "RATE_LIMITED"
    public static let configMissing = "CONFIG_MISSING"
    public static let upstream = "UPSTREAM"

    /// Alle Codes (Parität mit dem Backend-Set, für Tests).
    public static let all: Set<String> = [
        validation, tokenInvalid, tokenExpired, pendingInvalid,
        invalidCode, badCredentials, edupage2FA, captchaRequired,
        notFound, rateLimited, configMissing, upstream,
    ]
}

/// Hüllobjekt aller Listen: `{items, total, limit, offset}` (`BACKEND.md` §1).
public struct Page<T: Decodable & Sendable>: Decodable, Sendable {
    public let items: [T]
    public let total: Int
    public let limit: Int
    public let offset: Int

    public init(items: [T] = [], total: Int = 0, limit: Int = 50, offset: Int = 0) {
        self.items = items
        self.total = total
        self.limit = limit
        self.offset = offset
    }
}

/// Kanonische Fehlerantwort: `{error, code}` (`api/core.py`, tolerant).
public struct APIErrorBody: Decodable, Sendable {
    public let error: String
    public let code: String

    public init(error: String = "", code: String = ErrorCodes.upstream) {
        self.error = error
        self.code = code
    }

    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        error = (try? box.decodeIfPresent(String.self, forKey: .error)) ?? ""
        code = (try? box.decodeIfPresent(String.self, forKey: .code))
            ?? ErrorCodes.upstream
    }

    private enum CodingKeys: String, CodingKey {
        case error, code
    }
}

/// Gesundheitsantwort: `GET /api/v1/health` → `{status, version}`.
public struct Health: Decodable, Sendable {
    public let status: String
    public let version: String
}

/// Minimaler Nachrichten-Kopf als Navigationswert (Paket B).
///
/// Die Thread-Route trägt die Nachricht als Wert mit (kein Extraload,
/// kein geteiltes ViewModel). Das volle Nachrichten-Objekt definiert
/// Paket B und kann in diesen Kopf umgewandelt werden.
public struct MessageHeader: Codable, Hashable, Sendable {
    public let id: Int
    public let author: String
    public let text: String
    public let timestamp: String
    public let attachmentNames: [String]

    public init(id: Int = 0, author: String = "", text: String = "", timestamp: String = "", attachmentNames: [String] = []) {
        self.id = id
        self.author = author
        self.text = text
        self.timestamp = timestamp
        self.attachmentNames = attachmentNames
    }
}
