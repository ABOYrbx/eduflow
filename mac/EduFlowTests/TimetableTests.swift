import EduFlow
import Foundation
import Testing

/// Paket-D-Tests (offline, stubbendes URL-Protokoll, kein echtes Login).
///
/// Prüfen Routenform aller drei Endpunkte (Tages- und Wochenschlüssel,
/// Wetter-Payload), Lernzeit-Blöcke
/// und Kennzeichen gegen Stub wie im Web, Zeit- und Datumsableitungen
/// gegen bekannte Werte, aktuelle und nächste Stunde gegen feste Zeiten,
/// Wetter-Fehlercodes, Paginierung wo vorhanden und 401-Verhalten.
/// Serialisiert: der Stub-Handler ist geteilter Zustand.
@Suite(.serialized)
struct TimetableTests {

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

    @Test("Tagesansicht mit Lernzeit-Block und Kennzeichen")
    func dayDecodes() async throws {
        MockURLProtocol.handler = { request in
            #expect(request.url?.path.hasSuffix("timetable/day") == true)
            let url = try #require(request.url)
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            #expect(query.first(where: { $0.name == "day" })?.value == "2024-09-02")
            #expect(query.first(where: { $0.name == "refresh" })?.value == "1")
            let data = #"{"day":"2024-09-02","day_label":"Montag 02.09.2024","prev_day":"2024-09-01","next_day":"2024-09-03","today":"2024-09-02","lessons":[{"period":"2–3","time":"08:50–10:30","title":"Lernzeit","is_lernzeit":true,"teachers":"Mu","rooms":"A1","is_cancelled":false,"is_event":false,"is_online":false,"row_period":"2","rowspan":2},{"period":"4","time":"10:40–11:25","title":"Mathe","is_cancelled":true}],"cache_info":"Cache"}"#
                .data(using: .utf8)!
            let response = HTTPURLResponse(
                url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (data, response)
        }
        let day = try await TimetableRepository(client: client())
            .day("2024-09-02", refresh: true)
        #expect(day.dayLabel == "Montag 02.09.2024")
        #expect(day.lessons.count == 2)
        #expect(day.lessons.first?.rowspan == 2)
        #expect(day.lessons.first?.isLernzeit == true)
        #expect(day.lessons.last?.isCancelled == true)
    }

    @Test("Wochenansicht mit fünf Tagen")
    func weekDecodes() async throws {
        stub(status: 200, body: #"{"day":"2024-09-04","monday":"2024-09-02","week_label":"Woche 02.09. – 06.09.2024","days":[{"date":"2024-09-02","day_name":"Montag","day_date":"02.09.","is_today":false,"lessons":[]}],"cache_info":"frisch"}"#)
        let week = try await TimetableRepository(client: client()).week("2024-09-04")
        #expect(week.monday == "2024-09-02")
        #expect(week.weekLabel.contains("Woche"))
        #expect(week.days.first?.dayName == "Montag")
    }

    @Test("Ungültiges Tagesdatum meldet Validierung")
    func invalidDayValidation() async throws {
        stub(status: 400, body: #"{"error":"Ungültiges Datum.","code":"VALIDATION"}"#)
        do {
            _ = try await TimetableRepository(client: client()).day("falsch")
            Issue.record("Fehler erwartet")
        } catch let error as APIError {
            #expect(error.code == "VALIDATION")
        }
    }

    @Test("Zeitspanne und aktuelle/nächste Stunde gegen feste Zeiten")
    func currentAndNext() {
        #expect(CurrentLesson.range(of: "07:45–08:30")?.start == 465)
        #expect(CurrentLesson.range(of: "07:45–08:30")?.end == 510)
        #expect(CurrentLesson.range(of: "falsch") == nil)
        func lesson(_ time: String, cancelled: Bool = false, event: Bool = false) -> Lesson {
            var item = Lesson()
            item.time = time
            item.title = "T"
            item.isCancelled = cancelled
            item.isEvent = event
            return item
        }
        let lessons = [
            lesson("07:45–08:30"),
            lesson("08:50–09:35", cancelled: true),
            lesson("09:40–10:25"),
            lesson("10:30–11:15", event: true),
        ]
        let running = CurrentLesson.of(lessons, nowMinutes: 8 * 60)
        #expect(running.current?.time == "07:45–08:30")
        #expect(running.next?.time == "09:40–10:25")
        let before = CurrentLesson.of(lessons, nowMinutes: 7 * 60)
        #expect(before.current == nil)
        #expect(before.next?.time == "07:45–08:30")
        let evening = CurrentLesson.of(lessons, nowMinutes: 20 * 60)
        #expect(evening.current == nil)
        #expect(evening.next == nil)
    }

    @Test("Wetter-Payload und Fehlercodes")
    func wetter() async throws {
        let repo = MetaRepository(client: client())
        do {
            _ = try await repo.wetter(city: "   ")
            Issue.record("Fehler erwartet")
        } catch let error as APIError {
            #expect(error.code == "VALIDATION")
        }
        MockURLProtocol.handler = { request in
            let url = try #require(request.url)
            #expect(url.path.hasSuffix("wetter"))
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            #expect(query.first(where: { $0.name == "city" })?.value == "Berlin")
            let data = #"{"city":"Berlin","today":{"temp":12,"max":15,"min":8,"desc":"Bewölkt"},"tomorrow":{"max":16,"min":9},"day3":{},"hourly":[],"details":{"humidity":70}}"#
                .data(using: .utf8)!
            let response = HTTPURLResponse(
                url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (data, response)
        }
        let wetter = try await repo.wetter(city: "Berlin")
        #expect(wetter.city == "Berlin")
        #expect(wetter.today?.temp == 12)
        #expect(wetter.details?.humidity == 70)
        stub(status: 503, body: #"{"error":"Kein Schlüssel.","code":"CONFIG_MISSING"}"#)
        do {
            _ = try await repo.wetter(city: "Berlin")
            Issue.record("Fehler erwartet")
        } catch let error as APIError {
            #expect(error.code == "CONFIG_MISSING")
            #expect(error.httpStatus == 503)
        }
    }

    @Test("Datumshilfen für Navigation")
    func dateHelpers() {
        #expect(TimetableDates.shifted("2024-09-02", days: 1) == "2024-09-03")
        #expect(TimetableDates.shifted("2024-09-02", days: -1) == "2024-09-01")
        #expect(TimetableDates.shifted("falsch", days: 1) == "falsch")
        #expect(TimetableDates.today().count == 10)
    }

    @Test("Woche sendet Tages- und Aktualisierungs-Schalter")
    func weekRefreshFlag() async throws {
        MockURLProtocol.handler = { request in
            let url = try #require(request.url)
            #expect(url.path.hasSuffix("timetable/week"))
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            #expect(query.first(where: { $0.name == "day" })?.value == "2024-09-04")
            #expect(query.first(where: { $0.name == "refresh" })?.value == "1")
            let data = #"{"day":"2024-09-04","monday":"2024-09-02","week_label":"Woche 02.09. – 06.09.2024","days":[],"cache_info":"frisch"}"#
                .data(using: .utf8)!
            let response = HTTPURLResponse(
                url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (data, response)
        }
        let week = try await TimetableRepository(client: client()).week("2024-09-04", refresh: true)
        #expect(week.days.isEmpty)
    }

    @Test("401 meldet abgelaufene Sitzung (Stundenplan und Wetter)")
    func unauthorized() async throws {
        stub(status: 401, body: #"{"error":"Token ist abgelaufen. Bitte erneut anmelden.","code":"TOKEN_INVALID"}"#)
        do {
            _ = try await TimetableRepository(client: client()).day("2024-09-02")
            Issue.record("Fehler erwartet")
        } catch let error as APIError {
            #expect(error.code == "TOKEN_INVALID")
            #expect(error.httpStatus == 401)
        }
        do {
            _ = try await MetaRepository(client: client()).wetter(city: "Berlin")
            Issue.record("Fehler erwartet")
        } catch let error as APIError {
            #expect(error.code == "TOKEN_INVALID")
            #expect(error.httpStatus == 401)
        }
    }

    @Test("Upstream-Fehler laufen durch")
    func upstream() async throws {
        stub(status: 502, body: #"{"error":"EduPage antwortet nicht.","code":"UPSTREAM"}"#)
        do {
            _ = try await TimetableRepository(client: client()).week("2024-09-04")
            Issue.record("Fehler erwartet")
        } catch let error as APIError {
            #expect(error.code == "UPSTREAM")
            #expect(error.httpStatus == 502)
        }
    }

    @Test("Wetter mit Koordinaten statt Stadt")
    func wetterCoords() async throws {
        MockURLProtocol.handler = { request in
            let url = try #require(request.url)
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            #expect(query.first(where: { $0.name == "lat" })?.value == "52.52")
            #expect(query.first(where: { $0.name == "lon" })?.value == "13.405")
            #expect(query.first(where: { $0.name == "city" }) == nil)
            let data = #"{"city":"Berlin","today":{"temp":18}}"#.data(using: .utf8)!
            let response = HTTPURLResponse(
                url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (data, response)
        }
        let wetter = try await MetaRepository(client: client()).wetter(city: "", lat: 52.52, lon: 13.405)
        #expect(wetter.city == "Berlin")
    }

    @Test("Zeitspanne: Bindestrich ungültig, Ende inklusive, Entfall übersprungen")
    func timeEdges() {
        #expect(CurrentLesson.range(of: "07:45-08:30") == nil)
        #expect(CurrentLesson.range(of: "07:45–08:30")?.start == 465)
        func lesson(_ time: String, cancelled: Bool = false) -> Lesson {
            var item = Lesson()
            item.time = time
            item.title = "T"
            item.isCancelled = cancelled
            return item
        }
        let lessons = [lesson("07:45–08:30", cancelled: true), lesson("08:50–09:35")]
        let duringCancelled = CurrentLesson.of(lessons, nowMinutes: 8 * 60)
        #expect(duringCancelled.current == nil)
        #expect(duringCancelled.next?.time == "08:50–09:35")
        let atStart = CurrentLesson.of(lessons, nowMinutes: 8 * 60 + 50)
        #expect(atStart.current?.time == "08:50–09:35")
        #expect(atStart.next == nil)
        let atEnd = CurrentLesson.of([lesson("07:45–08:30")], nowMinutes: 8 * 60 + 30)
        #expect(atEnd.current?.time == "07:45–08:30")
    }
}
