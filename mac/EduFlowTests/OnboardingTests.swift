import EduFlow
import Foundation
import Testing

/// Onboarding-Tests (offline, stubbendes URL-Protokoll, kein echtes Login).
///
/// Prüfen Flag-Logik (nur erster Start), URL-Säuberung, Health-Abfrage
/// des Server-Schritts (ok / Fehler / Netzfehler mit deutschen Texten)
/// und das Prüf-ViewModel. Serialisiert: Stub-Handler und Flag sind
/// geteilter Zustand.
@Suite(.serialized)
struct OnboardingTests {

    private func withCleanFlag(_ work: () throws -> Void) rethrows {
        let hadFlag = UserDefaults.standard.bool(forKey: OnboardingState.flagKey)
        UserDefaults.standard.removeObject(forKey: OnboardingState.flagKey)
        defer {
            if hadFlag {
                UserDefaults.standard.set(true, forKey: OnboardingState.flagKey)
            } else {
                UserDefaults.standard.removeObject(forKey: OnboardingState.flagKey)
            }
        }
        try work()
    }

    @Test("Onboarding nur beim ersten Start ohne Sitzung")
    func showsOnlyOnFirstLaunch() throws {
        try withCleanFlag {
            #expect(OnboardingState.shouldShow(isLoggedIn: false))
            #expect(!OnboardingState.shouldShow(isLoggedIn: true))
            OnboardingState.complete()
            #expect(OnboardingState.completed)
            #expect(!OnboardingState.shouldShow(isLoggedIn: false))
            #expect(!OnboardingState.shouldShow(isLoggedIn: true))
        }
    }

    @Test("Server-URL wird gesäubert, leer fällt auf Default")
    func sanitizesBaseURL() {
        #expect(OnboardingState.sanitizedBaseURL("  http://pi:8000/api/v1/  ") == "http://pi:8000/api/v1/")
        #expect(OnboardingState.sanitizedBaseURL("") == TokenStore.defaultBaseURL)
        #expect(OnboardingState.sanitizedBaseURL("   ") == TokenStore.defaultBaseURL)
    }

    @Test("Health-Abfrage liefert Version gegen Stub")
    func healthCheckOk() async throws {
        MockURLProtocol.handler = { request in
            #expect(request.url?.path.hasSuffix("health") == true)
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
            let body = #"{"status":"ok","version":"v1"}"#.data(using: .utf8)!
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (body, response)
        }
        let client = APIClient(
            baseURL: { "http://127.0.0.1:8000/api/v1/" },
            token: { nil },
            session: MockURLProtocol.session()
        )
        let health = try await client.health()
        #expect(health.status == "ok")
        #expect(health.version == "v1")
    }

    @Test("Health-Fehler trägt deutschen Text und Status")
    func healthCheckFailsGerman() async throws {
        MockURLProtocol.handler = { request in
            let body = #"{"error":"Nicht gefunden.","code":"NOT_FOUND"}"#.data(using: .utf8)!
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 404,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (body, response)
        }
        let client = APIClient(
            baseURL: { "http://127.0.0.1:8000/api/v1/" },
            token: { nil },
            session: MockURLProtocol.session()
        )
        do {
            _ = try await client.health()
            Issue.record("Fehler erwartet")
        } catch let error as APIError {
            #expect(error.code == "NOT_FOUND")
            #expect(error.httpStatus == 404)
            #expect(!error.message.isEmpty)
        }
    }

    @Test("Netzfehler beim Health-Check wird zu UPSTREAM")
    func healthCheckOffline() async throws {
        MockURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        let client = APIClient(
            baseURL: { "http://127.0.0.1:8000/api/v1/" },
            token: { nil },
            session: MockURLProtocol.session()
        )
        do {
            _ = try await client.health()
            Issue.record("Fehler erwartet")
        } catch let error as APIError {
            #expect(error.code == "UPSTREAM")
            #expect(!error.message.isEmpty)
        }
    }

    @Test("Prüf-ViewModel meldet ok und Fehler je nach Antwort")
    @MainActor
    func serverCheckModel() async throws {
        let store = TokenStore()
        MockURLProtocol.handler = { request in
            let body = #"{"status":"ok","version":"v9"}"#.data(using: .utf8)!
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (body, response)
        }
        let model = ServerCheckModel(store: store, session: MockURLProtocol.session())
        await model.check()
        #expect(model.result == .ok(version: "v9"))
        model.resetResult()
        #expect(model.result == .none)
        MockURLProtocol.handler = { _ in throw URLError(.timedOut) }
        await model.check()
        if case .failed(let message) = model.result {
            #expect(!message.isEmpty)
        } else {
            Issue.record("Fehler erwartet")
        }
    }

    @Test("Weiter testet direkt und zeigt bei Erfolg das Häkchen")
    @MainActor
    func proceedTestsConnection() async throws {
        let key = "de.eduflow.baseURL"
        let saved = UserDefaults.standard.string(forKey: key)
        defer {
            if let saved {
                UserDefaults.standard.set(saved, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        let store = TokenStore()
        MockURLProtocol.handler = { request in
            let body = #"{"status":"ok","version":"v9"}"#.data(using: .utf8)!
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (body, response)
        }
        let okModel = ServerCheckModel(store: store, session: MockURLProtocol.session())
        #expect(await okModel.proceed(reduceMotion: true))
        #expect(!okModel.showSuccess)
        #expect(okModel.result == .ok(version: "v9"))
        #expect(await okModel.proceed(reduceMotion: false))
        #expect(okModel.showSuccess)
        MockURLProtocol.handler = { _ in throw URLError(.timedOut) }
        let failModel = ServerCheckModel(store: store, session: MockURLProtocol.session())
        #expect(await !failModel.proceed(reduceMotion: true))
        #expect(!failModel.showSuccess)
        if case .failed(let message) = failModel.result {
            #expect(!message.isEmpty)
        } else {
            Issue.record("Fehler erwartet")
        }
    }
}
