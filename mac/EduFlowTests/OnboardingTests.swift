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
    func showsOnlyOnFirstLaunch() {
        withCleanFlag {
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

    @Test("Sprachwahl schreibt Override und System leert ihn")
    func appLanguageOverride() {
        let keys = ["de.eduflow.appLanguage", "AppleLanguages"]
        let saved = keys.map { UserDefaults.standard.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, saved) {
                if let value {
                    UserDefaults.standard.set(value, forKey: key)
                } else {
                    UserDefaults.standard.removeObject(forKey: key)
                }
            }
            // Live-Überlagerung auf den vorherigen Stand zurücksetzen.
            // Wichtig: Suite-übergreifend — ohne Reset bleiben deutsche
            // Labels in anderen Suites (Bundle-Override ist global).
            BundleLanguageOverride.activate(code: nil)
        }
        for key in keys { UserDefaults.standard.removeObject(forKey: key) }
        #expect(AppLanguage.override == nil)
        AppLanguage.set("fr")
        #expect(AppLanguage.override == "fr")
        #expect(AppLanguage.current == "fr")
        AppLanguage.set(nil)
        #expect(AppLanguage.override == nil)
    }

    @Test("Sprachwahl wird sofort aktiv und meldet den Wechsel")
    func appLanguageAppliesLive() async {
        let keys = ["de.eduflow.appLanguage", "AppleLanguages"]
        let saved = keys.map { UserDefaults.standard.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, saved) {
                if let value {
                    UserDefaults.standard.set(value, forKey: key)
                } else {
                    UserDefaults.standard.removeObject(forKey: key)
                }
            }
            BundleLanguageOverride.activate(code: nil)
        }
        for key in keys { UserDefaults.standard.removeObject(forKey: key) }
        await confirmation("Wechsel gemeldet", expectedCount: 2) { confirm in
            let observer = NotificationCenter.default.addObserver(
                forName: .appLanguageDidChange,
                object: nil,
                queue: nil
            ) { _ in confirm() }
            defer { NotificationCenter.default.removeObserver(observer) }
            AppLanguage.set("en")
            #expect(AppLanguage.override == "en")
            #expect(AppLanguage.current == "en")
            AppLanguage.set(nil)
            #expect(AppLanguage.override == nil)
        }
    }

    @Test("Live-Lookup liest synthetisches Sprachbundle, sonst nil")
    func liveLookupSyntheticBundle() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let lproj = root.appendingPathComponent("xx.lproj", isDirectory: true)
        try FileManager.default.createDirectory(at: lproj, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let strings: [String: String] = ["live_key": "Live-Wert", "other_key": "Anderer Wert"]
        let data = try PropertyListSerialization.data(fromPropertyList: strings, format: .xml, options: 0)
        try data.write(to: lproj.appendingPathComponent("Localizable.strings"))
        guard let bundle = Bundle(path: root.path) else {
            Issue.record("Synthetisches Bundle erwartet")
            return
        }
        #expect(BundleLanguageOverride.lookup(key: "live_key", table: nil, in: bundle, code: "xx") == "Live-Wert")
        #expect(BundleLanguageOverride.lookup(key: "live_key", table: "Localizable", in: bundle, code: "xx") == "Live-Wert")
        #expect(BundleLanguageOverride.lookup(key: "missing_key", table: nil, in: bundle, code: "xx") == nil)
        #expect(BundleLanguageOverride.lookup(key: "live_key", table: "Other", in: bundle, code: "xx") == nil)
        #expect(BundleLanguageOverride.lookup(key: "live_key", table: nil, in: bundle, code: "yy") == nil)
    }

    @Test("Coverage-Daten sind konsistent (Prozente, Eigennamen)")
    func localeCoverageData() {
        #expect(!localeCoverage.isEmpty)
        for row in localeCoverage {
            #expect(row.percent >= 0 && row.percent <= 100)
            #expect(row.translated <= row.total && row.total > 0)
            #expect(!AppLanguage.nativeName(row.code).isEmpty)
        }
        #expect(localeCoverage.contains { $0.code == "de" && $0.percent == 100 })
    }

    @Test("Sprachcodes werden gefiltert und sortiert erkannt")
    func availableCodesFiltering() {
        #expect(AppLocalizations.availableCodes(from: ["en", "fr", "Base", "zh-Hans", "", "pt-BR"]) == ["en", "fr"])
        #expect(AppLocalizations.availableCodes(from: []) == [])
    }

    @Test("Zufallszyklus ohne direkten Wiederholer")
    func shuffledCycle() {
        #expect(AppLocalizations.shuffledCycle(count: 0, notStartingWith: nil) == [])
        #expect(AppLocalizations.shuffledCycle(count: 1, notStartingWith: 0) == [0])
        for _ in 0..<50 {
            let order = AppLocalizations.shuffledCycle(count: 5, notStartingWith: 2)
            #expect(order.sorted() == [0, 1, 2, 3, 4])
            #expect(order.first != 2)
        }
    }

    @Test("Coverage liest echte Bundle-Sprachen mit Prozentzahl")
    func coverageFromBundle() {
        let rows = AppLocalizations.coverage()
        #expect(!rows.isEmpty)
        for row in rows {
            #expect(row.percent >= 0 && row.percent <= 100)
            #expect(row.total > 0)
            #expect(row.translated <= row.total)
            // Prozent = gerundeter Anteil der übersetzten Texte.
            #expect(row.percent == Int((Double(row.translated) / Double(row.total) * 100).rounded()))
        }
        // Quelle (Englisch) ist immer vollständig.
        if let english = rows.first(where: { $0.code == "en" }) {
            #expect(english.percent == 100)
        }
        // Katalog-Sprachen haben lesbare Tabellen und einen Eigennamen.
        #expect(!AppLocalizations.availableCodes().isEmpty)
        for code in AppLocalizations.availableCodes() {
            #expect(!AppLanguage.nativeName(code).isEmpty)
        }
    }

    @Test("Sprachliste trägt Namen, Prozent und Fortschritt")
    func languageEntries() {
        let entries = LanguageEntry.fromBundle()
        #expect(!entries.isEmpty)
        for entry in entries {
            #expect(!entry.code.isEmpty)
            #expect(!entry.name.isEmpty)
            #expect(entry.total > 0)
            #expect(entry.translated <= entry.total)
            #expect(entry.percent >= 0 && entry.percent <= 100)
        }
        // Nach Eigenname sortiert, keine Dubletten.
        let names = entries.map(\.name)
        #expect(names == names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending })
        #expect(Set(entries.map(\.code)).count == entries.count)
    }

    @Test("Topbar wird beim Scrollen nach unten klein, oben immer groß")
    @MainActor
    func topBarCollapsesOnScrollDown() {
        let state = TopBarCollapseState()
        #expect(!state.isCompact)
        // Scrollen nach unten: Leiste wird klein.
        state.update(offset: 200)
        #expect(state.isCompact)
        // Scrollen nach oben: wieder groß.
        state.update(offset: 120)
        #expect(!state.isCompact)
        state.update(offset: 260)
        #expect(state.isCompact)
        // Ganz oben ist sie immer groß, auch nach kleinem Zappeln.
        state.update(offset: 0)
        #expect(!state.isCompact)
        state.update(offset: -30)
        #expect(!state.isCompact)
        // Winzige Bewegungen (< Mindestbewegung) ändern nichts.
        state.update(offset: 400)
        state.update(offset: 401)
        #expect(state.isCompact)
        // Seitenwechsel setzt zurück: neue Seite beginnt oben.
        state.reset()
        #expect(!state.isCompact)
    }

    @Test("Jeder Topbar-Reiter hat ein Symbol und einen Titel")
    func topBarSectionsHaveIcons() {
        for section in TopBarSection.allCases {
            #expect(!section.icon.isEmpty)
            #expect(!section.title.isEmpty)
        }
        #expect(Set(TopBarSection.allCases.map(\.icon)).count == TopBarSection.allCases.count)
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
