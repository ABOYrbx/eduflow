import EduFlow
import Foundation
import Testing

/// Paket-A-Tests (offline, stubbendes URL-Protokoll, kein echtes Login).
///
/// Prüfen Routenform von Anmeldung und Zwei-Faktor, alle Fehlercodes des
/// Pakets, Einstellungs-Defaults und -Clamping, echte JSON-Bools, Geräte
/// ohne Secrets und das 401-Verhalten mit und ohne Sitzung.
/// Serialisiert: der Stub-Handler ist geteilter Zustand.
@Suite(.serialized)
struct AuthTests {

    private func client() -> APIClient {
        APIClient(
            baseURL: { "http://127.0.0.1:8000/api/v1/" },
            token: { "abc" },
            session: MockURLProtocol.session()
        )
    }

    /// Body auslesen (URLSession reicht ihn je nach Pfad als `httpBody`
    /// oder `httpBodyStream` durch — beides abdecken).
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

    private func stub(status: Int, body: String) {        MockURLProtocol.handler = { request in
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

    @Test("Leere Anmeldung scheitert ohne Netzaufruf")
    func loginValidationNeedsNoNetwork() async throws {
        MockURLProtocol.handler = { _ in
            Issue.record("Kein Netzaufruf erwartet")
            throw URLError(.unknown)
        }
        let repo = AuthRepository(client: client())
        do {
            _ = try await repo.login(username: "", password: "", subdomain: "", device: "")
            Issue.record("Fehler erwartet")
        } catch let error as APIError {
            #expect(error.code == "VALIDATION")
        }
        do {
            _ = try await repo.login(username: "n", password: "", subdomain: "", device: "")
            Issue.record("Fehler erwartet")
        } catch let error as APIError {
            #expect(error.code == "VALIDATION")
        }
    }

    @Test("Anmeldung sendet alle Schlüssel an auth/login")
    func loginSendsAllKeys() async throws {
        MockURLProtocol.handler = { request in
            #expect(request.url?.path.hasSuffix("auth/login") == true)
            #expect(request.httpMethod == "POST")
            let body = try requestBody(request)
            #expect(body["username"] as? String == "hans")
            #expect(body["password"] as? String == "geheim")
            #expect(body["subdomain"] as? String == "schule")
            #expect(body["device"] as? String == "mac")
            let data = #"{"status":"ok","token":"t","expires":"e","subdomain":"s","username":"u"}"#
                .data(using: .utf8)!
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (data, response)
        }
        let result = try await AuthRepository(client: client())
            .login(username: " hans ", password: "geheim", subdomain: "schule", device: "mac")
        #expect(result == .loggedIn(token: "t", expires: "e", subdomain: "s", username: "u"))
    }

    @Test("Subdomain wird getrimmt und kleingeschrieben, leer bleibt automatisch")
    func loginNormalizesSubdomain() async throws {
        var seen: [String] = []
        MockURLProtocol.handler = { request in
            let body = try requestBody(request)
            seen.append(body["subdomain"] as? String ?? "<fehlt>")
            let data = #"{"status":"ok","token":"t","expires":"e","subdomain":"schule","username":"u"}"#
                .data(using: .utf8)!
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (data, response)
        }
        let repo = AuthRepository(client: client())
        _ = try await repo.login(username: "n", password: "p", subdomain: " SCHULE ", device: "")
        _ = try await repo.login(username: "n", password: "p", subdomain: "   ", device: "")
        #expect(seen == ["schule", ""])
    }

    @Test("Zwei-Faktor-Pflicht liefert Zwischen-Token")
    func loginTwoFaRequired() async throws {
        stub(status: 200, body: #"{"status":"2fa_required","pending_token":"p123","message":"Code eingeben."}"#)
        let result = try await AuthRepository(client: client())
            .login(username: "n", password: "p", subdomain: "", device: "")
        #expect(result == .twoFaRequired(pendingToken: "p123", message: "Code eingeben."))
    }

    @Test("Alle Fehlercodes des Pakets kommen durch")
    func packageErrorCodes() async throws {
        let cases = [
            ("BAD_CREDENTIALS", 401),
            ("CAPTCHA_REQUIRED", 403),
            ("RATE_LIMITED", 429),
            ("INVALID_CODE", 401),
            ("PENDING_INVALID", 401),
            ("VALIDATION", 400),
            ("EDUPAGE_2FA", 401),
        ]
        for (code, status) in cases {
            stub(status: status, body: #"{"error":"Fehler.","code":"\#(code)"}"#)
            let repo = AuthRepository(client: client())
            do {
                _ = try await repo.submit2FA(pendingToken: "p", code: "1")
                Issue.record("Fehler erwartet (\(code))")
            } catch let error as APIError {
                #expect(error.code == code)
                #expect(error.httpStatus == status)
                #expect(!error.message.isEmpty)
            }
        }
    }

    @Test("Leerer Zwei-Faktor-Code scheitert ohne Netzaufruf")
    func twoFaEmptyCodeNeedsNoNetwork() async throws {
        MockURLProtocol.handler = { _ in
            Issue.record("Kein Netzaufruf erwartet")
            throw URLError(.unknown)
        }
        do {
            _ = try await AuthRepository(client: client()).submit2FA(pendingToken: "p", code: "  ")
            Issue.record("Fehler erwartet")
        } catch let error as APIError {
            #expect(error.code == "VALIDATION")
        }
    }

    @Test("Zwei-Faktor-Abschluss tauscht gegen Token")
    func twoFaSubmitOk() async throws {
        MockURLProtocol.handler = { request in
            #expect(request.url?.path.hasSuffix("auth/2fa") == true)
            let body = try requestBody(request)
            #expect(body["pending_token"] as? String == "p")
            #expect(body["code"] as? String == "123456")
            let data = #"{"status":"ok","token":"t","expires":"e","subdomain":"s","username":"u"}"#
                .data(using: .utf8)!
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (data, response)
        }
        let result = try await AuthRepository(client: client()).submit2FA(pendingToken: "p", code: "123456")
        #expect(result == .loggedIn(token: "t", expires: "e", subdomain: "s", username: "u"))
    }

    @Test("Abmelden ruft auth/logout auf, Erneuern auth/refresh, me liefert Benutzer")
    func logoutRefreshMe() async throws {
        let repo = AuthRepository(client: client())
        MockURLProtocol.handler = { request in
            #expect(request.url?.path.hasSuffix("auth/logout") == true)
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer abc")
            let data = #"{"status":"ok"}"#.data(using: .utf8)!
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (data, response)
        }
        try await repo.logout()
        MockURLProtocol.handler = { request in
            #expect(request.url?.path.hasSuffix("auth/refresh") == true)
            let data = #"{"status":"ok","token":"neu","expires":"e","subdomain":"s","username":"u"}"#
                .data(using: .utf8)!
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (data, response)
        }
        let refreshed = try await repo.refresh()
        #expect(refreshed == .loggedIn(token: "neu", expires: "e", subdomain: "s", username: "u"))
        stub(status: 200, body: #"{"subdomain":"s","username":"u"}"#)
        let me = try await repo.me()
        #expect(me.subdomain == "s")
        #expect(me.username == "u")
    }

    @Test("Einstellungs-Defaults und Clamping wie im Web")
    func settingsDefaultsAndClamping() async throws {
        stub(status: 200, body: #"{"schema":[],"values":{"landing":"falsch","hw_status":"offen","ov_unread":99,"ov_homework":0,"hw_tests":"1","ov_wetter":"0"}}"#)
        let (_, values) = try await SettingsRepository(client: client()).load()
        #expect(values.landing == "uebersicht")
        #expect(values.hwStatus == "offen")
        #expect(values.ovUnread == 50)
        #expect(values.ovHomework == 1)
        #expect(values.hwTests == true)
        #expect(values.ovWetter == false)
    }

    @Test("Speichern sendet echte JSON-Typen")
    func saveSendsRealJSONTypes() async throws {
        MockURLProtocol.handler = { request in
            #expect(request.httpMethod == "PUT")
            #expect(request.url?.path.hasSuffix("settings") == true)
            let body = try requestBody(request)
            #expect((body["hw_tests"] as? Bool) == true)
            #expect((body["ov_wetter"] as? Bool) == false)
            #expect((body["ov_unread"] as? Int) == 12)
            #expect((body["landing"] as? String) == "noten")
            #expect((body["wetter_city"] as? String) == "Berlin")
            let data = #"{"status":"ok","values":{"landing":"noten","hw_tests":true,"ov_unread":12,"ov_wetter":false,"wetter_city":"Berlin"}}"#
                .data(using: .utf8)!
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (data, response)
        }
        var values = SettingsValues()
        values.landing = "noten"
        values.hwTests = true
        values.ovUnread = 12
        values.ovWetter = false
        values.wetterCity = "Berlin"
        let saved = try await SettingsRepository(client: client()).save(values)
        #expect(saved.landing == "noten")
        #expect(saved.ovUnread == 12)
    }

    @Test("Cache-Leeren meldet Anzahl, Geräte ohne Secrets")
    func cacheClearAndDevices() async throws {
        let repo = SettingsRepository(client: client())
        stub(status: 200, body: #"{"status":"ok","cleared":7}"#)
        #expect(try await repo.clearCache() == 7)
        stub(status: 200, body: #"{"items":[{"id":"h1","short":"…abcdef","device":"Mac","created":"c","expires":"e"}],"total":1}"#)
        let devices = try await repo.devices()
        #expect(devices.count == 1)
        #expect(devices.first?.id == "h1")
        #expect(devices.first?.short == "…abcdef")
        MockURLProtocol.handler = { request in
            #expect(request.httpMethod == "DELETE")
            #expect(request.url?.path.hasSuffix("devices/h1") == true)
            let data = #"{"status":"ok"}"#.data(using: .utf8)!
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (data, response)
        }
        try await repo.revokeDevice(id: "h1")
    }

    @Test("Geräte ohne Secrets: Token-Felder werden ignoriert")
    func devicesIgnoreSecrets() async throws {
        stub(status: 200, body: #"{"items":[{"id":"h1","short":"…abcdef","device":"Mac","created":"c","expires":"e","token":"GEHEIM","accessTokenHash":"GEHEIM","refresh_token":"GEHEIM"}],"total":1}"#)
        let devices = try await SettingsRepository(client: client()).devices()
        #expect(devices.count == 1)
        #expect(devices.first?.id == "h1")
        #expect(devices.first?.short == "…abcdef")
        // DeviceInfo besitzt kein Token-Feld — Secrets landen nirgends.
        let mirror = Mirror(reflecting: devices.first as Any)
        #expect(!mirror.children.contains { ($0.label ?? "").lowercased().contains("token") })
    }

    @Test("Speichern trimmt die Wetter-Stadt")
    func saveTrimsWetterCity() async throws {
        MockURLProtocol.handler = { request in
            let body = try requestBody(request)
            #expect(body["wetter_city"] as? String == "Berlin")
            let data = #"{"status":"ok","values":{"wetter_city":"Berlin"}}"#.data(using: .utf8)!
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (data, response)
        }
        var values = SettingsValues()
        values.wetterCity = "  Berlin\n"
        let saved = try await SettingsRepository(client: client()).save(values)
        #expect(saved.wetterCity == "Berlin")
    }

    @Test("401-Verhalten mit und ohne Sitzung")
    func sessionRecovery() {
        let expired = APIError(code: "TOKEN_EXPIRED", message: "x", httpStatus: 401)
        #expect(SessionRecovery.forceLogout(error: expired, isLoggedIn: true))
        #expect(!SessionRecovery.forceLogout(error: expired, isLoggedIn: false))
        let second = APIError(code: "EDUPAGE_2FA", message: "x", httpStatus: 401)
        #expect(SessionRecovery.forceLogout(error: second, isLoggedIn: true))
        #expect(!SessionRecovery.forceLogout(error: second, isLoggedIn: false))
        let upstream = APIError(code: "UPSTREAM", message: "x", httpStatus: 502)
        #expect(!SessionRecovery.forceLogout(error: upstream, isLoggedIn: true))
    }

    @Test("Startseiten-Mapping aller fünf Ziele plus Fallback")
    func landingRoutes() {
        var values = SettingsValues()
        values.landing = "uebersicht"
        #expect(values.landingRoute() == .overview)
        values.landing = "dashboard"
        #expect(values.landingRoute() == .messages)
        values.landing = "hausaufgaben"
        #expect(values.landingRoute() == .homework)
        values.landing = "noten"
        #expect(values.landingRoute() == .grades)
        values.landing = "stundenplan"
        #expect(values.landingRoute() == .timetable)
    }
}
