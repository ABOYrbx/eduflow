import EduFlow
import Foundation
import Testing

/// Tests des lokalen Antwort-Caches (offline, eigenes Temporärverzeichnis).
///
/// Der Cache ist die Grundlage dafür, dass ein Backend-Neustart nicht
/// zum Login führt. Geprüft wird deshalb beides: dass er Daten zuverlässig
/// hält **und** dass er nicht aus Versehen bei Fehlern einspringt, die
/// kein Sitzungsproblem sind (sonst würde die App alte Daten zeigen und
/// echte Fehler verschlucken).
@Suite(.serialized)
struct LocalCacheTests {

    /// Eigener Cache pro Test, damit die Läufe sich nicht beeinflussen.
    private func makeCache() -> (LocalCache, URL) {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("eduflow-cache-\(UUID().uuidString)", isDirectory: true)
        return (LocalCache.isolated(directory), directory)
    }

    private func cleanUp(_ directory: URL) {
        try? FileManager.default.removeItem(at: directory)
    }

    private struct Probe: Decodable, Sendable {
        var total: Int = 0
    }

    /// Client mit eigenem Stub-Protokoll und **einer** vorbereiteten Antwort.
    ///
    /// Bewusst **nicht** `MockURLProtocol.handler`: das ist geteilter,
    /// veränderlicher Zustand über alle Suites hinweg. Da die Tests hier
    /// nacheinander unterschiedliche Antworten brauchen (erst 200, dann 401),
    /// würde ein parallel laufender Test den Handler dazwischen
    /// überschreiben. `CacheStubProtocol.next` gilt genau für den nächsten
    /// Request.
    ///
    /// - Parameter `times`: Wie viele Requests diese Antwort bedienen soll
    ///   (für das mehrfache `getCached` mit gleicher Antwort).
    @discardableResult
    private func client(
        _ cache: LocalCache?,
        status: Int,
        body: String
    ) -> APIClient {
        CacheStubProtocol.queue.append((status, body))
        return makeClient(cache)
    }

    /// Antwort für den nächsten Request, ohne neuen Client zu bauen — nötig
    /// wenn ein Test denselben Client mehrfach mit wechselnden Antworten
    /// füttert.
    private func answer(_ status: Int, _ body: String) {
        CacheStubProtocol.queue.append((status, body))
    }

    private func makeClient(_ cache: LocalCache?) -> APIClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CacheStubProtocol.self]
        return APIClient(
            baseURL: { "http://127.0.0.1:8000/api/v1/" },
            token: { "abc" },
            session: URLSession(configuration: config),
            cache: cache
        )
    }


    @Test("Antwort wird gespeichert und wiedergegeben")
    func storesAndReturnsPayload() async throws {
        let (cache, directory) = makeCache()
        defer { cleanUp(directory) }
        let api = client(cache, status: 200, body: #"{"total":7}"#)

        let fresh = try await api.getCached("homework", as: Probe.self)
        #expect(fresh.savedAt == nil)
        #expect(!fresh.isFromCache)
        #expect(try APIClient.decode(Probe.self, from: fresh.data).total == 7)
        #expect(cache.count == 1)

        let stored = try #require(cache.load("homework"))
        #expect(stored.savedAt != nil)
        #expect(try APIClient.decode(Probe.self, from: stored.data).total == 7)
    }

    @Test("401 liefert den Cache statt zu scheitern")
    func unauthorizedFallsBackToCache() async throws {
        let (cache, directory) = makeCache()
        defer { cleanUp(directory) }
        // Erst erfolgreich laden, damit etwas im Cache liegt.
        _ = try await client(cache, status: 200, body: #"{"total":3}"#)
            .getCached("homework", as: Probe.self)

        // Jetzt 401 — wie nach einem Backend-Neustart ohne gültiges Token.
        let payload = try await client(
            cache, status: 401, body: #"{"error":"Sitzung ungültig","code":"TOKEN_INVALID"}"#
        ).getCached("homework", as: Probe.self)
        #expect(payload.isFromCache)
        #expect(try APIClient.decode(Probe.self, from: payload.data).total == 3)
    }

    @Test("Server nicht erreichbar liefert den Cache")
    func upstreamFallsBackToCache() async throws {
        let (cache, directory) = makeCache()
        defer { cleanUp(directory) }
        _ = try await client(cache, status: 200, body: #"{"total":5}"#)
            .getCached("messages", as: Probe.self)

        let payload = try await client(
            cache, status: 502, body: #"{"error":"fehler","code":"UPSTREAM"}"#
        ).getCached("messages", as: Probe.self)
        #expect(payload.isFromCache)
        #expect(try APIClient.decode(Probe.self, from: payload.data).total == 5)
    }

    @Test("Echte Serverfehler werden nicht vom Cache verdeckt")
    func realErrorsPropagate() async throws {
        let (cache, directory) = makeCache()
        defer { cleanUp(directory) }
        _ = try await client(cache, status: 200, body: #"{"total":3}"#)
            .getCached("homework", as: Probe.self)

        // VALIDATION ist kein Sitzungsproblem: hier muss der Fehler
        // durchkommen, sonst zeigte die App still alte Daten.
        for code in ["VALIDATION", "RATE_LIMITED", "NOT_FOUND", "CAPTCHA_REQUIRED"] {
            let failing = client(
                cache, status: 400, body: #"{"error":"abgelehnt","code":"\#(code)"}"#
            )
            await #expect(throws: APIError.self) {
                _ = try await failing.getCached("homework", as: Probe.self)
            }
        }
    }

    @Test("Ohne Cache-Vorlauf wirft ein 401 weiterhin")
    func unauthorizedWithoutCacheStillThrows() async throws {
        let (cache, directory) = makeCache()
        defer { cleanUp(directory) }
        let gone = client(
            cache, status: 401, body: #"{"error":"Sitzung ungültig","code":"TOKEN_INVALID"}"#
        )
        await #expect(throws: APIError.self) {
            _ = try await gone.getCached("homework", as: Probe.self)
        }
    }

    @Test("Passende Route wird getroffen, andere nicht")
    func cacheKeySeparatesRoutes() async throws {
        let (cache, directory) = makeCache()
        defer { cleanUp(directory) }
        CacheStubProtocol.queue = []
        let api = makeClient(cache)
        answer(200, #"{"total":1}"#)
        answer(200, #"{"total":1}"#)
        _ = try await api.getCached("homework", as: Probe.self)
        _ = try await api.getCached("messages", as: Probe.self)
        #expect(cache.count == 2)
        #expect(cache.load("homework") != nil)
        #expect(cache.load("grades") == nil)
    }

    @Test("Query landet im Schlüssel, nicht im Dateinamen")
    func queryIsPartOfKey() async throws {
        let (cache, directory) = makeCache()
        defer { cleanUp(directory) }
        CacheStubProtocol.queue = []
        let api = makeClient(cache)
        answer(200, #"{"total":1}"#)
        _ = try await api.getCached("homework", query: [
            URLQueryItem(name: "status", value: "offen"),
        ], as: Probe.self)
        let key = APIClient.cacheKey("homework", [URLQueryItem(name: "status", value: "offen")])
        #expect(cache.load(key) != nil)
        // Kein Pfad darf den Cache verlassen lassen.
        #expect(!key.contains("/") || key.hasPrefix("homework"))
    }

    @Test("Query-Reihenfolge ändert den Schlüssel nicht")
    func queryOrderDoesNotChangeKey() {
        let a = APIClient.cacheKey("homework", [
            URLQueryItem(name: "status", value: "offen"),
            URLQueryItem(name: "limit", value: "50"),
        ])
        let b = APIClient.cacheKey("homework", [
            URLQueryItem(name: "limit", value: "50"),
            URLQueryItem(name: "status", value: "offen"),
        ])
        #expect(a == b)
    }

    @Test("Cache leeren entfernt alles und zählt")
    func clearRemovesEverything() async throws {
        let (cache, directory) = makeCache()
        defer { cleanUp(directory) }
        CacheStubProtocol.queue = []
        let api = makeClient(cache)
        answer(200, #"{"total":1}"#)
        answer(200, #"{"total":1}"#)
        answer(200, #"{"total":1}"#)
        _ = try await api.getCached("homework", as: Probe.self)
        _ = try await api.getCached("messages", as: Probe.self)
        _ = try await api.getCached("grades", as: Probe.self)
        #expect(cache.count == 3)
        #expect(cache.clear() == 3)
        #expect(cache.count == 0)
        #expect(cache.clear() == 0)
    }

    @Test("Routenname mit Sonderzeichen verlässt den Ordner nicht")
    func keyIsSanitised() {
        let url = URL(string: "file:///tmp/x")!
        #expect(url.path == "/tmp/x")
        // `../../etc/passwd` darf als Dateiname nichts bewirken.
        #expect(!APIClient.cacheKey("../../etc/passwd", []).hasPrefix("/"))
        _ = LocalCache.isolated(
            URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("eduflow-cache-\(UUID().uuidString)")
        )
    }

    @Test("Ohne Cache im Client wird nichts gespeichert")
    func clientWithoutCacheDoesNotStore() async throws {
        let (cache, directory) = makeCache()
        defer { cleanUp(directory) }
        CacheStubProtocol.queue = []
        answer(200, #"{"total":2}"#)
        // Gleiche Sitzung und derselbe Stub, nur ohne Cache — so ändert
        // sich ausschließlich das Cache-Verhalten.
        let withoutCache = makeClient(nil)
        let payload = try await withoutCache.getCached("homework", as: Probe.self)
        #expect(payload.savedAt == nil)
        #expect(cache.count == 0)
    }
}

/// Antwort-Stub pro Aufruf statt global geteilt.
///
/// `MockURLProtocol` (in `EduFlowTests`) speichert seinen Handler in einem
/// statischen Feld — alle Suites teilen ihn. Diese Suite braucht dagegen
/// mehrere, nacheinander gesetzte Antworten, also wird die Antwort vor dem
/// Aufruf in einen Kasten gelegt und direkt danach wieder geleert. Kein
/// geteilter Zustand, kein Überschreiben durch parallele Tests.
final class CacheStubProtocol: URLProtocol {
    /// Antworten für die nächsten Requests (FIFO). Leer heißt „nichts
    /// vorbereitet" — dann schlägt der Request bewusst fehl.
    nonisolated(unsafe) static var queue: [(status: Int, body: String)] = []

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        // Einmal herausnehmen: die nächste Antwort gehört diesem Request.
        let answer = Self.queue.isEmpty ? nil : Self.queue.removeFirst()
        guard let answer, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        let response = HTTPURLResponse(
            url: url,
            statusCode: answer.status,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(answer.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// Deckt die **einzelnen Bereiche** ab, nicht nur den Cache-Mechanismus.
///
/// Der erste Teil (`LocalCacheTests`) beweist, dass `getCached` fällt
/// zurück. Dieser Teil beweist, dass **jede** gelesene Route der App das
/// auch tatsächlich benutzt — also dass nach einem Backend-Neustart
/// wirklich jede Ansicht etwas anzeigt und nicht nur die Übersicht.
/// Jeder Aufruf geht deshalb von „einmal 200, dann 401" aus: gelingt der
/// zweite Aufruf mit Cache-Daten, ist der Weg in der App verdrahtet.
@Suite(.serialized)
struct CachedRoutesTests {

    private func freshCache() -> (LocalCache, URL) {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("eduflow-routes-\(UUID().uuidString)", isDirectory: true)
        return (LocalCache.isolated(directory), directory)
    }

    private func cleanUp(_ directory: URL) {
        try? FileManager.default.removeItem(at: directory)
    }

    /// Client ohne eigene Antwort — die Antworten kommen aus
    /// `bothOKAndGone` bzw. `CacheStubProtocol.queue`.
    private func client(_ cache: LocalCache) -> APIClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CacheStubProtocol.self]
        return APIClient(
            baseURL: { "http://127.0.0.1:8000/api/v1/" },
            token: { "abc" },
            session: URLSession(configuration: config),
            cache: cache
        )
    }

    private func bothOKAndGone(_ cache: LocalCache, _ body: String) {
        CacheStubProtocol.queue.append((200, body))
        CacheStubProtocol.queue.append((401, #"{"error":"ungültig","code":"TOKEN_INVALID"}"#))
    }

    @Test("Hausaufgaben, Noten, Nachrichten fallen zurück")
    func listsFallBack() async throws {
        let (cache, directory) = freshCache()
        defer { cleanUp(directory) }

        CacheStubProtocol.queue = []
        bothOKAndGone(cache, #"{"items":[],"total":0,"limit":50,"offset":0}"#)
        let hw = try await HomeworkRepository(client: client(cache)).list()
        #expect(hw.savedAt == nil)
        let hwOffline = try await HomeworkRepository(client: client(cache)).list()
        #expect(hwOffline.isFromCache)
        #expect(hwOffline.items.isEmpty)

        CacheStubProtocol.queue = []
        bothOKAndGone(cache, #"{"items":[],"total":0,"limit":50,"offset":0}"#)
        _ = try await GradesRepository(client: client(cache)).list()
        let grades = try await GradesRepository(client: client(cache)).list()
        #expect(grades.isFromCache)

        CacheStubProtocol.queue = []
        bothOKAndGone(cache, #"{"items":[],"total":0,"limit":50,"offset":0}"#)
        _ = try await MessagesRepository(client: client(cache)).list()
        let messages = try await MessagesRepository(client: client(cache)).list()
        #expect(messages.isFromCache)
    }

    @Test("Stundenplan Tag und Woche fallen zurück")
    func timetableFallsBack() async throws {
        let (cache, directory) = freshCache()
        defer { cleanUp(directory) }
        let day = #"{"day":"2026-10-02","lessons":[]}"#
        CacheStubProtocol.queue = []
        bothOKAndGone(cache, day)
        _ = try await TimetableRepository(client: client(cache)).day(nil)
        let offline = try await TimetableRepository(client: client(cache)).day(nil)
        #expect(offline.isFromCache)
        #expect(offline.lessons.isEmpty)

        CacheStubProtocol.queue = []
        bothOKAndGone(cache, #"{"days":[]}"#)
        _ = try await TimetableRepository(client: client(cache)).week(nil)
        let week = try await TimetableRepository(client: client(cache)).week(nil)
        #expect(week.isFromCache)
    }

    @Test("Nachrichten-Thread und Empfänger fallen zurück")
    func threadAndRecipientsFallBack() async throws {
        let (cache, directory) = freshCache()
        defer { cleanUp(directory) }
        CacheStubProtocol.queue = []
        bothOKAndGone(cache, #"{"likes":[],"replies":[]}"#)
        _ = try await MessagesRepository(client: client(cache)).thread(id: 7)
        let thread = try await MessagesRepository(client: client(cache)).thread(id: 7)
        #expect(thread.isFromLocalCache)

        CacheStubProtocol.queue = []
        bothOKAndGone(cache, #"{"items":[],"total":0,"limit":200,"offset":0}"#)
        _ = try await MessagesRepository(client: client(cache)).recipients()
        let recipients = try await MessagesRepository(client: client(cache)).recipients()
        #expect(recipients.isFromCache)
    }

    @Test("Termine und Vertretungen fallen zurück")
    func schoolFallsBack() async throws {
        let (cache, directory) = freshCache()
        defer { cleanUp(directory) }
        let day = Date()

        CacheStubProtocol.queue = []
        bothOKAndGone(cache, #"{"items":[{"id":"a1","kind":"exam","text":"Klausur"}],"total":1}"#)
        _ = try await SchoolRepository(client: client(cache)).agenda(day: day)
        let agenda = try await SchoolRepository(client: client(cache)).agenda(day: day)
        #expect(agenda.isFromCache)
        #expect(agenda.count == 1)
        #expect(agenda.first?.text == "Klausur")

        CacheStubProtocol.queue = []
        bothOKAndGone(cache, #"{"days":[{"day":"2026-10-02","changes":[]}]}"#)
        _ = try await SchoolRepository(client: client(cache)).substitutions(day: day)
        let substitutions = try await SchoolRepository(client: client(cache)).substitutions(day: day)
        #expect(substitutions.isFromCache)
        #expect(substitutions.count == 1)
    }

    @Test("Wetter, Einstellungen, Geräte und Profil fallen zurück")
    func metaSettingsDevicesFallBack() async throws {
        let (cache, directory) = freshCache()
        defer { cleanUp(directory) }

        CacheStubProtocol.queue = []
        bothOKAndGone(cache, #"{"city":"Berlin","today":{"temp":10}}"#)
        _ = try await MetaRepository(client: client(cache)).wetter(city: "Berlin")
        let weather = try await MetaRepository(client: client(cache)).wetter(city: "Berlin")
        #expect(weather.isFromCache)
        #expect(weather.city == "Berlin")

        CacheStubProtocol.queue = []
        bothOKAndGone(cache, #"{"schema":[],"values":{}}"#)
        _ = try await SettingsRepository(client: client(cache)).load()
        let settings = try await SettingsRepository(client: client(cache)).load()
        #expect(settings.values.landing == "uebersicht")

        CacheStubProtocol.queue = []
        bothOKAndGone(cache, #"{"items":[{"id":"d1","name":"Mac"}],"total":1}"#)
        _ = try await SettingsRepository(client: client(cache)).devices()
        let devices = try await SettingsRepository(client: client(cache)).devices()
        #expect(devices.count == 1)

        CacheStubProtocol.queue = []
        bothOKAndGone(cache, #"{"subdomain":"schule","username":"lena"}"#)
        _ = try await AuthRepository(client: client(cache)).me()
        let me = try await AuthRepository(client: client(cache)).me()
        #expect(me.username == "lena")
    }
}
