import Foundation
import XCTest

@testable import EduFlow

// MARK: - Paket-B-Tests (offline, ohne Zugangsdaten)
//
// Prüfen Routenform-nahe Dekodierung (DTOs 1:1 zu den Web-Dicts),
// Fehlercodes, Validierung und das 401-Verhalten — ohne Netzwerk.

final class MessagesTests: XCTestCase {

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try Self.decoder.decode(T.self, from: Data(json.utf8))
    }

    // MARK: Thread-Dekodierung (api/messages.py _thread_payload)

    func testThreadDecoding() throws {
        let thread = try decode(ThreadResponse.self, """
        {"likes": [{"name": "A. Lehrerin", "date": "01.01. 10:00"}],
         "replies": [{"name": "B. Schüler", "date": "02.01. 11:00", "text": "Hallo"}],
         "reply_ids": ["42"],
         "summary": {"total": 3, "likes": 1, "replies": 1, "seen": 1},
         "cached": true}
        """)
        XCTAssertEqual(thread.likes.count, 1)
        XCTAssertEqual(thread.likes.first?.name, "A. Lehrerin")
        XCTAssertEqual(thread.replies.first?.text, "Hallo")
        XCTAssertEqual(thread.replyIds, ["42"])
        XCTAssertEqual(thread.summary?.seen, 1)
        XCTAssertTrue(thread.cached)
    }

    func testThreadDecodingTolerant() throws {
        // Optionale Felder dürfen fehlen (Like ohne Datum, Antwort ohne Text).
        let thread = try decode(ThreadResponse.self, """
        {"likes": [{"name": "A. Lehrerin"}],
         "replies": [{"name": "B. Schüler"}],
         "reply_ids": [],
         "summary": {"total": 2, "likes": 1, "replies": 1, "seen": 0},
         "cached": false}
        """)
        XCTAssertNil(thread.likes.first?.date)
        XCTAssertNil(thread.replies.first?.text)
        XCTAssertFalse(thread.cached)
    }

    // MARK: Nachrichtenliste (nur Top-Level, Page-Hülle BACKEND.md §1)

    func testMessagesPageDecoding() throws {
        let page = try decode(Page<MessageItem>.self, """
        {"items": [{"id": 7, "author": "A. Lehrerin", "type_label": "Nachricht",
                    "text": "Info", "reaction_count": 2,
                    "attachments": [{"name": "a.pdf", "url": "https://x.edupage.org/f"}]}],
         "total": 1, "limit": 50, "offset": 0}
        """)
        XCTAssertEqual(page.total, 1)
        XCTAssertEqual(page.items.first?.uid, "7")
        XCTAssertEqual(page.items.first?.reactionCount, 2)
        XCTAssertEqual(page.items.first?.attachments?.first?.name, "a.pdf")
    }

    func testMessageIDTolerant() throws {
        // ID als String (FlexibleID: Zahl oder String).
        let page = try decode(Page<MessageItem>.self, """
        {"items": [{"id": "abc-1", "text": "x"}], "total": 1, "limit": 50, "offset": 0}
        """)
        XCTAssertEqual(page.items.first?.uid, "abc-1")
    }

    // MARK: Empfänger (app.py get_recipients, _RECIPIENT_ID_RE)

    func testRecipientsDecoding() throws {
        let page = try decode(Page<RecipientItem>.self, """
        {"items": [{"id": "Teacher7", "name": "A. Lehrerin", "kind": "Lehrer"}],
         "total": 1, "limit": 50, "offset": 0}
        """)
        XCTAssertEqual(page.items.first?.id, "Teacher7")
        XCTAssertEqual(page.items.first?.kind, "Lehrer")
    }

    func testRecipientIDs() {
        XCTAssertTrue(RecipientIDs.isValid("Teacher7"))
        XCTAssertTrue(RecipientIDs.isValid("student42"))
        XCTAssertTrue(RecipientIDs.isValid("Ucitel3"))
        XCTAssertFalse(RecipientIDs.isValid(""))
        XCTAssertFalse(RecipientIDs.isValid("Lehrer7"))
        XCTAssertFalse(RecipientIDs.isValid("Teacher"))
        XCTAssertEqual(RecipientIDs.clean(["Teacher7", " Teacher7 ", " Quatsch ", "Student1"]),
                       ["Teacher7", "Student1"])
    }

    // MARK: Gelesen-Markierung (POST messages/read → {marked})

    func testMarkReadDecoding() throws {
        let res = try decode(MarkReadResponse.self, "{\"marked\": 5}")
        XCTAssertEqual(res.marked, 5)
    }

    // MARK: Download-Token (POST messages/download-token → {download_token, expires_in})

    func testDownloadTokenDecoding() throws {
        let res = try decode(DownloadTokenResponse.self,
                             "{\"download_token\": \"abc123\", \"expires_in\": 300}")
        XCTAssertEqual(res.downloadToken, "abc123")
        XCTAssertEqual(res.expiresIn, 300)
    }

    func testDownloadURLUsesShortLivedToken() {
        // `?dl=` (Kurzzeit-Token) statt `?token=` (langlebig, nur Kompatibilität).
        let client = APIClient(
            baseURL: URL(string: "http://127.0.0.1:8000/api/v1/")!,
            tokenProvider: { "LANGLEBIG" })
        let url = client.attachmentDownloadURL(messageID: "7", index: 0, dlToken: "KURZ")
        let s = url?.absoluteString ?? ""
        XCTAssertTrue(s.contains("messages/7/attachments/0"), s)
        XCTAssertTrue(s.contains("dl=KURZ"), s)
        XCTAssertFalse(s.contains("LANGLEBIG"), s)
        XCTAssertFalse(s.contains("token="), s)
        XCTAssertNil(client.attachmentDownloadURL(messageID: "7", index: 0, dlToken: ""))
    }

    // MARK: Compose-Validierung (wie api/messages.py, serverseitig)

    func testComposeValidation() {
        XCTAssertEqual(
            MessageCompose.validate(recipients: [], body: "Hallo")?.code,
            "VALIDATION")
        XCTAssertEqual(
            MessageCompose.validate(recipients: ["Quatsch"], body: "Hallo")?.code,
            "VALIDATION")
        XCTAssertEqual(
            MessageCompose.validate(recipients: ["Teacher7"], body: "   ")?.code,
            "VALIDATION")
        XCTAssertNil(
            MessageCompose.validate(recipients: ["Teacher7"], body: "Hallo"))
    }

    // MARK: Fehlercodes (api/core.py ERROR_CODES, deutsche Fallbacks)

    func testErrorMapping() {
        XCTAssertEqual(APIError.message(for: "BAD_CREDENTIALS"),
                       "Falscher Benutzername, Passwort oder Subdomain.")
        XCTAssertFalse(APIError.message(for: "UPSTREAM").isEmpty)
        // Fehlerbody {error, code} wie der Server ihn sendet.
        let dto = try? Self.decoder.decode(
            APIErrorDTO.self, from: Data("{\"error\": \"X.\", \"code\": \"NOT_FOUND\"}".utf8))
        XCTAssertEqual(dto?.code, "NOT_FOUND")
    }

    func testNeedsReLogin() {
        for code in ["TOKEN_INVALID", "TOKEN_EXPIRED", "EDUPAGE_2FA"] {
            XCTAssertTrue(APIError(code: code, message: "x", httpStatus: 401).needsReLogin, code)
        }
        XCTAssertFalse(APIError(code: "VALIDATION", message: "x", httpStatus: 400).needsReLogin)
        XCTAssertFalse(APIError(code: "UPSTREAM", message: "x", httpStatus: 502).needsReLogin)
    }

    // MARK: Typfilter (app.py MESSAGE_TYPES + TYPE_LABELS)

    func testMessageTypes() {
        XCTAssertEqual(MessageTypes.label("sprava"), "Nachricht")
        XCTAssertEqual(MessageTypes.label(""), "Alle")
        XCTAssertTrue(MessageTypes.all.contains("chat"))
    }

    // MARK: Betreff/Vorschau (Paket C, PNG-Karte)

    func testMessageBodyLine() throws {
        let m = try Self.decoder.decode(
            MessageItem.self,
            from: Data("{\"type_label\":\"Nachricht\",\"text\":\"Unterrichtsausfall morgen\\nDie erste Stunde entfällt.\"}".utf8))
        XCTAssertEqual(m.bodyLine, "Unterrichtsausfall morgen Die erste Stunde entfällt.")
        let empty = try Self.decoder.decode(
            MessageItem.self,
            from: Data("{\"type_label\":\"Mitteilung\",\"text\":\"   \"}".utf8))
        XCTAssertEqual(empty.bodyLine, "Mitteilung")
    }
}
