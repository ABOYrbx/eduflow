import EduFlow
import Foundation
import Testing

/// Paket-B-Tests (offline, stubbendes URL-Protokoll, kein echtes Login).
///
/// Prüfen Routenform aller Nachrichten-Endpunkte (Parameter- und
/// Body-Schlüssel wie in `api/messages.py`), Thread mit Likes und
/// Antworten, Senden und Antworten, Download mit Kurzzeit-Token,
/// Empfänger-Prüfung, Paginierung und 401-Verhalten.
/// Serialisiert: der Stub-Handler ist geteilter Zustand.
@Suite(.serialized)
struct MessageTests {

    private func client() -> APIClient {
        APIClient(
            baseURL: { "http://127.0.0.1:8000/api/v1/" },
            token: { "abc" },
            session: MockURLProtocol.session()
        )
    }

    private func stub(status: Int, body: String) {
        MockURLProtocol.handler = { request in
            let data = body.data(using: .utf8)!
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (data, response)
        }
    }

    private func requestBody(_ request: URLRequest) throws -> [String: Any] {
        if let body = request.httpBody, !body.isEmpty {
            return try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        }
        if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var data = Data()
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
            defer { buffer.deallocate() }
            while stream.hasBytesAvailable {
                let count = stream.read(buffer, maxLength: 4096)
                if count <= 0 { break }
                data.append(buffer, count: count)
            }
            return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        }
        throw URLError(.cannotParseResponse)
    }

    @Test("Liste sendet Web-Parameter und dekodiert Hülle")
    func listSendsWebParameters() async throws {
        MockURLProtocol.handler = { request in
            #expect(request.url?.path.hasSuffix("messages") == true)
            let url = try #require(request.url)
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            func value(_ name: String) -> String? {
                query.first(where: { $0.name == name })?.value
            }
            #expect(value("since") == "2024-01-01")
            #expect(value("type") == "sprava")
            #expect(value("q") == "test")
            #expect(value("limit") == "50")
            #expect(value("offset") == "50")
            #expect(value("refresh") == "1")
            let data = #"{"items":[{"id":7,"author":"A","text":"Hallo","type":"sprava","type_label":"Nachricht"}],"total":51,"limit":50,"offset":50}"#
                .data(using: .utf8)!
            let response = HTTPURLResponse(
                url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (data, response)
        }
        let page = try await MessagesRepository(client: client())
            .list(since: "2024-01-01", type: "sprava", query: "test", offset: 50, refresh: true)
        #expect(page.total == 51)
        #expect(page.items.count == 1)
        #expect(page.items.first?.id == 7)
        #expect(page.items.first?.typeLabel == "Nachricht")
    }

    @Test("Thread mit Likes, Antworten und Cache-Hinweis")
    func threadDecodes() async throws {
        MockURLProtocol.handler = { request in
            #expect(request.url?.path.hasSuffix("messages/7/thread") == true)
            let data = #"{"likes":[{"name":"L","date":"d"}],"replies":[{"name":"R","date":"d","text":"Ja"}],"reply_ids":[],"summary":{"total":3,"likes":1,"replies":1,"seen":1},"cached":true}"#
                .data(using: .utf8)!
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (data, response)
        }
        let thread = try await MessagesRepository(client: client()).thread(id: 7)
        #expect(thread.likes.count == 1)
        #expect(thread.replies.first?.text == "Ja")
        #expect(thread.summary.total == 3)
        #expect(thread.cached)
    }

    @Test("Gelesen-Markierung meldet Zähler")
    func markReadCounts() async throws {
        MockURLProtocol.handler = { request in
            #expect(request.url?.path.hasSuffix("messages/read") == true)
            #expect(request.httpMethod == "POST")
            let data = #"{"marked":12}"#.data(using: .utf8)!
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (data, response)
        }
        #expect(try await MessagesRepository(client: client()).markRead() == 12)
    }

    @Test("Empfänger-Prüfung folgt dem Server-Muster")
    func recipientIDsFollowServerPattern() {
        #expect(RecipientIDs.isValid("Teacher12"))
        #expect(RecipientIDs.isValid("student7"))
        #expect(RecipientIDs.isValid("StudentOnly3"))
        #expect(RecipientIDs.isValid("Parent9"))
        #expect(RecipientIDs.isValid("Rodic4"))
        #expect(RecipientIDs.isValid("Ucitel5"))
        #expect(!RecipientIDs.isValid("Lehrer12"))
        #expect(!RecipientIDs.isValid("Teacher"))
        #expect(!RecipientIDs.isValid(""))
        #expect(!RecipientIDs.isValid("Teacher12x"))
        #expect(RecipientIDs.clean([" Teacher1 ", "teacher1", "Quatsch", "", "Student2"])
            == ["Teacher1", "teacher1", "Student2"])
    }

    @Test("Senden braucht Empfänger und Text")
    func sendNeedsRecipientsAndBody() async throws {
        MockURLProtocol.handler = { _ in
            Issue.record("Kein Netzaufruf erwartet")
            throw URLError(.unknown)
        }
        let repo = MessagesRepository(client: client())
        do {
            _ = try await repo.send(recipients: [], body: "Hallo")
            Issue.record("Fehler erwartet")
        } catch let error as APIError {
            #expect(error.code == "VALIDATION")
        }
        do {
            _ = try await repo.send(recipients: ["Teacher1"], body: "   ")
            Issue.record("Fehler erwartet")
        } catch let error as APIError {
            #expect(error.code == "VALIDATION")
        }
        // Unbekannte IDs schickt der Client unverändert mit; der Server
        // lehnt sie per Mitgliedschaft in der Empfängerliste ab.
        stub(status: 400, body: #"{"error":"Bitte mindestens einen gültigen Empfänger angeben.","code":"VALIDATION"}"#)
        do {
            _ = try await repo.send(recipients: ["Quatsch"], body: "Hallo")
            Issue.record("Fehler erwartet")
        } catch let error as APIError {
            #expect(error.code == "VALIDATION")
        }
    }

    @Test("Senden nutzt Empfängerliste plus Text und liefert Nachricht")
    func sendSendsKeys() async throws {
        MockURLProtocol.handler = { request in
            #expect(request.url?.path.hasSuffix("messages/send") == true)
            let body = try requestBody(request)
            #expect((body["recipients"] as? [String]) == ["Teacher1"])
            #expect(body["body"] as? String == "Hallo")
            let data = #"{"id":9,"author":"Ich","text":"Hallo","type":"sprava"}"#
                .data(using: .utf8)!
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (data, response)
        }
        let sent = try await MessagesRepository(client: client())
            .send(recipients: ["Teacher1"], body: "Hallo")
        #expect(sent.id == 9)
        #expect(sent.text == "Hallo")
    }

    @Test("Antwort braucht Text und liefert frischen Thread")
    func replyNeedsBody() async throws {
        let repo = MessagesRepository(client: client())
        MockURLProtocol.handler = { _ in
            Issue.record("Kein Netzaufruf erwartet")
            throw URLError(.unknown)
        }
        do {
            _ = try await repo.reply(id: 7, body: "  ")
            Issue.record("Fehler erwartet")
        } catch let error as APIError {
            #expect(error.code == "VALIDATION")
        }
        MockURLProtocol.handler = { request in
            #expect(request.url?.path.hasSuffix("messages/7/reply") == true)
            let body = try requestBody(request)
            #expect(body["body"] as? String == "Danke")
            #expect(body["recipients"] == nil)
            let data = #"{"likes":[],"replies":[{"name":"Ich","text":"Danke"}],"summary":{"replies":1}}"#
                .data(using: .utf8)!
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (data, response)
        }
        let thread = try await repo.reply(id: 7, body: "Danke")
        #expect(thread.replies.count == 1)
    }

    @Test("Download nutzt Kurzzeit-Token statt langlebigem Token")
    func downloadUsesShortLivedToken() async throws {
        MockURLProtocol.handler = { request in
            let path = request.url?.path ?? ""
            if path.hasSuffix("messages/download-token") {
                let data = #"{"download_token":"kurz","expires_in":300}"#.data(using: .utf8)!
                let response = HTTPURLResponse(
                    url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (data, response)
            }
            #expect(path.hasSuffix("messages/7/attachments/0"))
            let query = URLComponents(
                url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
            #expect(query.first(where: { $0.name == "dl" })?.value == "kurz")
            #expect(query.first(where: { $0.name == "token" })?.value == nil)
            let data = "datei".data(using: .utf8)!
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (data, response)
        }
        let file = try await MessagesRepository(client: client())
            .downloadAttachment(eventId: 7, index: 0)
        #expect((try? Data(contentsOf: file)) == "datei".data(using: .utf8))
    }

    @Test("Typ-Labels und Fehlercodes wie im Web")
    func labelsAndErrors() async throws {
        #expect(MessageTypes.label("sprava") == "Nachricht")
        #expect(MessageTypes.label("news") == "Neuigkeit")
        #expect(MessageTypes.label("anketa") == "Umfrage")
        #expect(MessageTypes.label("chat") == "Chat")
        #expect(MessageTypes.label("genotif") == "Mitteilung")
        #expect(MessageTypes.label("") == "Alle")
        stub(status: 400, body: #"{"error":"Unbekannter Typ.","code":"VALIDATION"}"#)
        do {
            _ = try await MessagesRepository(client: client()).list(type: "falsch")
            Issue.record("Fehler erwartet")
        } catch let error as APIError {
            #expect(error.code == "VALIDATION")
        }
        stub(status: 404, body: #"{"error":"Nicht gefunden.","code":"NOT_FOUND"}"#)
        do {
            _ = try await MessagesRepository(client: client()).thread(id: 1)
            Issue.record("Fehler erwartet")
        } catch let error as APIError {
            #expect(error.code == "NOT_FOUND")
            #expect(error.httpStatus == 404)
        }
    }

    @Test("Abgelaufene Sitzung meldet 401 für Login")
    func unauthorizedMapsToLogin() async throws {
        stub(status: 401, body: #"{"error":"Ungültiges oder fehlendes Token.","code":"TOKEN_INVALID"}"#)
        do {
            _ = try await MessagesRepository(client: client()).list()
            Issue.record("Fehler erwartet")
        } catch let error as APIError {
            #expect(error.code == "TOKEN_INVALID")
            #expect(error.httpStatus == 401)
            #expect(error.needsReLogin)
            #expect(SessionRecovery.forceLogout(error: error, isLoggedIn: true))
            #expect(!SessionRecovery.forceLogout(error: error, isLoggedIn: false))
        }
        stub(status: 401, body: #"{"error":"Erneute Zwei-Faktor-Pflicht.","code":"EDUPAGE_2FA"}"#)
        do {
            _ = try await MessagesRepository(client: client()).thread(id: 7)
            Issue.record("Fehler erwartet")
        } catch let error as APIError {
            #expect(error.code == "EDUPAGE_2FA")
            #expect(SessionRecovery.forceLogout(error: error, isLoggedIn: true))
        }
    }

    @Test("Falsches Datumsformat meldet Validierung")
    func badSinceMapsToValidation() async throws {
        stub(status: 400, body: #"{"error":"Datum muss im Format JJJJ-MM-TT sein.","code":"VALIDATION"}"#)
        do {
            _ = try await MessagesRepository(client: client()).list(since: "gestern")
            Issue.record("Fehler erwartet")
        } catch let error as APIError {
            #expect(error.code == "VALIDATION")
        }
    }

    @Test("Paginierung sendet Limit und Offset")
    func paginationSendsLimitAndOffset() async throws {
        MockURLProtocol.handler = { request in
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
            func value(_ name: String) -> String? {
                query.first(where: { $0.name == name })?.value
            }
            if request.url?.path.hasSuffix("recipients") == true {
                #expect(value("limit") == "200")
                #expect(value("offset") == "200")
                let data = #"{"items":[],"total":201,"limit":200,"offset":200}"#
                    .data(using: .utf8)!
                let response = HTTPURLResponse(
                    url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (data, response)
            }
            #expect(request.url?.path.hasSuffix("messages") == true)
            #expect(value("since") == "2000-01-01")
            #expect(value("limit") == "10")
            #expect(value("offset") == "20")
            let data = #"{"items":[],"total":0,"limit":10,"offset":20}"#
                .data(using: .utf8)!
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (data, response)
        }
        let page = try await MessagesRepository(client: client())
            .list(limit: 10, offset: 20)
        #expect(page.total == 0)
        #expect(page.limit == 10)
        let recipients = try await MessagesRepository(client: client())
            .recipients(limit: 200, offset: 200)
        #expect(recipients.total == 201)
    }

    @Test("Thread-Aktualisierung sendet Refresh-Schalter")
    func threadRefreshSendsFlag() async throws {
        MockURLProtocol.handler = { request in
            #expect(request.url?.path.hasSuffix("messages/7/thread") == true)
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
            #expect(query.first(where: { $0.name == "refresh" })?.value == "1")
            let data = #"{"likes":[],"replies":[],"reply_ids":[],"summary":{},"cached":false}"#
                .data(using: .utf8)!
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (data, response)
        }
        let thread = try await MessagesRepository(client: client()).thread(id: 7, refresh: true)
        #expect(!thread.cached)
    }

    @Test("Download behält den Dateinamen aus den Nachrichtendaten")
    func downloadKeepsFilename() async throws {
        MockURLProtocol.handler = { request in
            let path = request.url?.path ?? ""
            if path.hasSuffix("messages/download-token") {
                let data = #"{"download_token":"kurz","expires_in":300}"#.data(using: .utf8)!
                let response = HTTPURLResponse(
                    url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (data, response)
            }
            let data = "datei".data(using: .utf8)!
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (data, response)
        }
        let file = try await MessagesRepository(client: client())
            .downloadAttachment(eventId: 7, index: 0, filename: "Packliste.pdf")
        #expect(file.lastPathComponent == "Packliste.pdf")
        #expect((try? Data(contentsOf: file)) == "datei".data(using: .utf8))
        #expect(MessagesRepository.safeFilename("../geheim.txt", index: 0) == ".._geheim.txt")
        #expect(MessagesRepository.safeFilename("   ", index: 2) == "Datei 3")
        #expect(MessagesRepository.safeFilename(".", index: 0) == "Datei 1")
    }
}
