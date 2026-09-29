import EduFlow
import Foundation
import Testing

/// Paket-0-Tests (offline, stubbendes URL-Protokoll, kein echtes Login).
///
/// Prüfen Fehler-Vokabular, Fehlermapping, Seitendaten und Routenform
/// des Kerns. Jedes Paket testet seine Routen selbst (Regeln, §7).
/// Serialisiert: der Stub-Handler ist geteilter Zustand.
@Suite(.serialized)
struct CoreTests {

    @Test("Fehlercodes stimmen mit api/core.py überein")
    func errorCodesMatchBackend() {
        #expect(ErrorCodes.all == [
            "VALIDATION", "TOKEN_INVALID", "TOKEN_EXPIRED",
            "PENDING_INVALID", "INVALID_CODE", "BAD_CREDENTIALS",
            "EDUPAGE_2FA", "CAPTCHA_REQUIRED", "NOT_FOUND",
            "RATE_LIMITED", "CONFIG_MISSING", "UPSTREAM",
        ])
    }

    @Test("Deutsche Rückfalltexte sind gesetzt und leerfrei")
    func germanFallbacksPresent() {
        for code in ErrorCodes.all {
            let text = APIError.germanFallback(for: code)
            #expect(!text.isEmpty)
        }
        #expect(!APIError.germanFallback(for: "UNBEKANNT").isEmpty)
    }

    @Test("Sitzungsfehler führen zum Login")
    func sessionErrorsNeedReLogin() {
        let expired = APIError(code: "TOKEN_EXPIRED", message: "x", httpStatus: 401)
        #expect(expired.isSessionExpired)
        #expect(expired.needsReLogin)
        let invalid = APIError(code: "TOKEN_INVALID", message: "x", httpStatus: 401)
        #expect(invalid.needsReLogin)
        let second = APIError(code: "EDUPAGE_2FA", message: "x", httpStatus: 401)
        #expect(!second.isSessionExpired)
        #expect(second.needsReLogin)
        let upstream = APIError(code: "UPSTREAM", message: "x", httpStatus: 502)
        #expect(!upstream.needsReLogin)
    }

    @Test("Fehlerkörper ist tolerant (leere und fremde Felder)")
    func errorBodyTolerant() throws {
        let empty = try APIClient.decode(
            APIErrorBody.self,
            from: Data("{}".utf8)
        )
        #expect(empty.code == ErrorCodes.upstream)
        #expect(empty.error.isEmpty)
        let full = try APIClient.decode(
            APIErrorBody.self,
            from: Data(#"{"error":"Falsch.","code":"BAD_CREDENTIALS","neu":1}"#.utf8)
        )
        #expect(full.code == "BAD_CREDENTIALS")
        #expect(full.error == "Falsch.")
    }

    @Test("Seite dekodiert Hülle mit Zählern")
    func pageDecodesEnvelope() throws {
        struct Item: Decodable, Sendable {
            let id: Int
        }
        let page = try APIClient.decode(
            Page<Item>.self,
            from: Data(#"{"items":[{"id":7}],"total":1,"limit":50,"offset":0}"#.utf8)
        )
        #expect(page.total == 1)
        #expect(page.items.first?.id == 7)
    }

    @Test("Gesundheit dekodiert Status und Version")
    func healthDecodes() throws {
        let health = try APIClient.decode(
            Health.self,
            from: Data(#"{"status":"ok","version":"v1"}"#.utf8)
        )
        #expect(health.status == "ok")
        #expect(health.version == "v1")
    }

    @Test("401 mit Code wird als APIError geworfen")
    func unauthorizedMapsToAPIError() async throws {
        MockURLProtocol.handler = { request in
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer abc")
            let body = #"{"error":"Abgelaufen.","code":"TOKEN_EXPIRED"}"#.data(using: .utf8)!
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 401,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (body, response)
        }
        let client = APIClient(
            baseURL: { "http://127.0.0.1:8000/api/v1/" },
            token: { "abc" },
            session: MockURLProtocol.session()
        )
        do {
            _ = try await client.get(APIClient.Paths.me)
            Issue.record("Fehler erwartet")
        } catch let error as APIError {
            #expect(error.code == "TOKEN_EXPIRED")
            #expect(error.httpStatus == 401)
            #expect(error.message == "Abgelaufen.")
        }
    }

    @Test("Login-Pfad sendet keinen Token, Fehlertext vom Server bleibt")
    func loginSendsNoToken() async throws {
        MockURLProtocol.handler = { request in
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
            let body = #"{"error":"Falsch.","code":"BAD_CREDENTIALS"}"#.data(using: .utf8)!
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 401,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (body, response)
        }
        let client = APIClient(
            baseURL: { "http://127.0.0.1:8000/api/v1/" },
            token: { "abc" },
            session: MockURLProtocol.session()
        )
        do {
            _ = try await client.post(APIClient.Paths.login, body: Data("{}".utf8))
            Issue.record("Fehler erwartet")
        } catch let error as APIError {
            #expect(error.code == "BAD_CREDENTIALS")
            #expect(error.message == "Falsch.")
        }
    }

    @Test("Netzfehler wird zu UPSTREAM ohne Interna")
    func networkErrorMapsToUpstream() async throws {
        MockURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        let client = APIClient(
            baseURL: { "http://127.0.0.1:8000/api/v1/" },
            token: { nil },
            session: MockURLProtocol.session()
        )
        do {
            _ = try await client.get(APIClient.Paths.health, authenticated: false)
            Issue.record("Fehler erwartet")
        } catch let error as APIError {
            #expect(error.code == "UPSTREAM")
            #expect(!error.message.isEmpty)
        }
    }

    @Test("Standard-Basis-URL zeigt auf lokalen Server")
    func defaultBaseURLIsLocal() {
        #expect(TokenStore.defaultBaseURL == "http://127.0.0.1:3000/api/v1/")
    }

    @Test("Topbar-Standard enthält alle Bereiche außer Termine")
    func topBarDefaultExcludesSchool() {
        #expect(TopBarConfig.defaultVisible == [.overview, .messages, .homework, .grades, .timetable])
        #expect(!TopBarConfig.defaultVisible.contains(.school))
        #expect(TopBarSection.allCases.contains(.school))
        for section in TopBarSection.allCases {
            #expect(!section.title.isEmpty)
            #expect(section.route != .settings)
            #expect(section.route != .devices)
            #expect(section.route != .login)
        }
        #expect(TopBarSection.school.route == .school)
    }

    @Test("Topbar-Ablage wird bereinigt (unbekannt, Duplikate, leer)")
    func topBarSanitize() {
        #expect(TopBarConfig.sanitize(nil) == TopBarConfig.defaultVisible)
        #expect(TopBarConfig.sanitize([]) == TopBarConfig.defaultVisible)
        #expect(TopBarConfig.sanitize(["overview", "nope", "messages", "messages"]) == [.overview, .messages])
        #expect(TopBarConfig.sanitize(["school"]) == [.school])
    }

    @Test("Topbar-Umsortieren bewegt Einträge, ungültig bleibt stabil")
    func topBarMove() {
        let order: [TopBarSection] = [.overview, .messages, .homework]
        #expect(TopBarConfig.move(order, from: 2, by: -2) == [.homework, .overview, .messages])
        #expect(TopBarConfig.move(order, from: 0, by: -1) == order)
        #expect(TopBarConfig.move(order, from: 2, by: 5) == order)
        #expect(TopBarConfig.move(order, from: 9, by: 1) == order)
        #expect(TopBarConfig.move([], from: 0, by: 1) == [])
    }

    @Test("Topbar-Auswahl wird gespeichert und gelesen")
    func topBarSaveRoundtrip() {
        let key = TopBarConfig.storageKey
        let saved = UserDefaults.standard.stringArray(forKey: key)
        defer {
            if let saved {
                UserDefaults.standard.set(saved, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
            NotificationCenter.default.post(name: .topBarConfigDidChange, object: nil)
        }
        UserDefaults.standard.removeObject(forKey: key)
        #expect(TopBarConfig.visible == TopBarConfig.defaultVisible)
        TopBarConfig.save([.school, .overview])
        #expect(TopBarConfig.visible == [.school, .overview])
        TopBarConfig.save([])
        #expect(TopBarConfig.visible == TopBarConfig.defaultVisible)
    }

    @Test("Paginierung entspricht Backend (Standard 50, max 200)")
    func pageLimitsMatchBackend() {
        #expect(PageLimits.defaultLimit == 50)
        #expect(PageLimits.maxLimit == 200)
    }

    @Test("Alle Routenpfade sind gesetzt")
    func allRoutePathsPresent() {
        let paths = [
            APIClient.Paths.health, APIClient.Paths.openAPI,
            APIClient.Paths.login, APIClient.Paths.twoFA,
            APIClient.Paths.logout, APIClient.Paths.refresh,
            APIClient.Paths.me, APIClient.Paths.devices,
            APIClient.Paths.device("abc"), APIClient.Paths.settings,
            APIClient.Paths.cacheClear, APIClient.Paths.messages,
            APIClient.Paths.thread(7), APIClient.Paths.markRead,
            APIClient.Paths.recipients, APIClient.Paths.sendMessage,
            APIClient.Paths.reply(7), APIClient.Paths.attachment(7, 0),
            APIClient.Paths.downloadToken, APIClient.Paths.homework, APIClient.Paths.homeworkDone(3),
            APIClient.Paths.homeworkTrash(3), APIClient.Paths.grades,
            APIClient.Paths.timetableDay, APIClient.Paths.timetableWeek,
            APIClient.Paths.schoolAgenda, APIClient.Paths.substitutionsWeek,
            APIClient.Paths.wetter, APIClient.Paths.wetterSuche,
        ]
        #expect(paths.count == 29)
        #expect(Set(paths).count == 29)
        for path in paths {
            #expect(!path.isEmpty)
            #expect(!path.hasPrefix("/"))
        }
    }
}

/// Stubbendes URL-Protokoll (offline, kein Netz, kein Login).
final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (Data, HTTPURLResponse))?

    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        do {
            let (data, response) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
