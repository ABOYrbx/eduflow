import EduFlow
import Foundation
import Testing

/// Schulalltag-Tests (offline, stubbendes URL-Protokoll, kein echtes Login).
///
/// Prüfen Routenform beider Endpunkte (Agenda-Fenster −30/+60 Tage,
/// Aktualisierungs-Schalter, Wochentag), tolerante DTOs (fehlende,
/// fremde und falsch typisierte Felder), Wochen-Montag und 401-Verhalten.
/// Serialisiert: der Stub-Handler ist geteilter Zustand.
@Suite(.serialized)
struct SchoolTests {

    private func client() -> APIClient {
        APIClient(
            baseURL: { "http://127.0.0.1:8000/api/v1/" },
            token: { "abc" },
            session: MockURLProtocol.session()
        )
    }

    private func day(_ iso: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return try #require(formatter.date(from: iso))
    }

    private func query(_ request: URLRequest) throws -> [URLQueryItem] {
        let url = try #require(request.url)
        return URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    }

    @Test("Agenda sendet Fenster und Schalter wie das Web")
    func agendaSendsWindow() async throws {
        let selected = try day("2026-09-16")
        MockURLProtocol.handler = { request in
            #expect(request.url?.path.hasSuffix("school/agenda") == true)
            let items = try self.query(request)
            func value(_ name: String) -> String? {
                items.first(where: { $0.name == name })?.value
            }
            #expect(value("since") == "2026-08-17")
            #expect(value("until") == "2026-11-15")
            #expect(value("refresh") == nil)
            let data = #"{"items":[{"id":7102,"kind":"exam","date":"2026-09-21","title":"Lernzielkontrolle","subject":"Physik","type_label":"Test","author":"Lehrer","fremd":1}],"total":1,"since":"2026-08-17","until":"2026-11-15","cache_info":"frisch"}"#
                .data(using: .utf8)!
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (data, response)
        }
        let items = try await SchoolRepository(client: client()).agenda(day: selected)
        #expect(items.count == 1)
        #expect(items.first?.kind == "exam")
        #expect(items.first?.subject == "Physik")
        MockURLProtocol.handler = { request in
            let items = try self.query(request)
            #expect(items.first(where: { $0.name == "refresh" })?.value == "1")
            let data = #"{"items":[],"total":0}"#.data(using: .utf8)!
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (data, response)
        }
        let refreshed = try await SchoolRepository(client: client())
            .agenda(day: selected, refresh: true)
        #expect(refreshed.isEmpty)
    }

    @Test("Vertretungswoche sendet Tag und liest Tage mit Änderungen")
    func substitutionsWeek() async throws {
        let selected = try day("2026-09-16")
        MockURLProtocol.handler = { request in
            #expect(request.url?.path.hasSuffix("substitutions/week") == true)
            let items = try self.query(request)
            #expect(items.first(where: { $0.name == "day" })?.value == "2026-09-16")
            let data = #"{"monday":"2026-09-14","week_label":"Woche 14.09. – 18.09.2026","days":[{"date":"2026-09-14","day_label":"Montag 14.09.2026","changes":[]},{"date":"2026-09-15","day_label":"Dienstag 15.09.2026","changes":[{"class":"8A","lesson":"4","title":"Raumänderung","action":"changeroom"}]}]}"#
                .data(using: .utf8)!
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (data, response)
        }
        let days = try await SchoolRepository(client: client()).substitutions(day: selected)
        #expect(days.count == 2)
        #expect(days.first(where: { !$0.changes.isEmpty })?.changes.first?.schoolClass == "8A")
        #expect(days.first(where: { !$0.changes.isEmpty })?.changes.first?.lesson == "4")
    }

    @Test("DTOs sind tolerant (fehlend, fremd, falsch typisiert)")
    func tolerantDTOs() throws {
        let empty = try APIClient.decode(SchoolAgendaItem.self, from: Data("{}".utf8))
        #expect(empty.id == 0)
        #expect(empty.kind == "event")
        #expect(empty.title.isEmpty)
        let coerced = try APIClient.decode(
            SchoolAgendaItem.self,
            from: Data(#"{"id":"7102","kind":"exam","date":"2026-09-21","neu":true}"#.utf8)
        )
        #expect(coerced.id == 7102)
        #expect(coerced.kind == "exam")
        let change = try APIClient.decode(
            SchoolSubstitution.self,
            from: Data(#"{"class":"8A","lesson":4,"title":"Vertretung","action":"add","neu":1}"#.utf8)
        )
        #expect(change.schoolClass == "8A")
        #expect(change.lesson == "4")
        #expect(change.action == "add")
        let bare = try APIClient.decode(SchoolSubstitutionDay.self, from: Data("{}".utf8))
        #expect(bare.changes.isEmpty)
        let week = try APIClient.decode(
            SchoolSubstitutionResponse.self,
            from: Data(#"{"monday":"2026-09-14","week_label":"Woche","days":[]}"#.utf8)
        )
        #expect(week.days.isEmpty)
    }

    @Test("Montag-Ableitung wie das Backend")
    func mondayMapping() throws {
        let wednesday = try day("2026-09-16")
        #expect(SchoolDates.isoDay(SchoolDates.monday(of: wednesday)) == "2026-09-14")
        let sunday = try day("2026-09-20")
        #expect(SchoolDates.isoDay(SchoolDates.monday(of: sunday)) == "2026-09-14")
        let monday = try day("2026-09-14")
        #expect(SchoolDates.isoDay(SchoolDates.monday(of: monday)) == "2026-09-14")
    }

    @Test("Abgelaufene Sitzung führt zum Login")
    func expiredSessionNeedsLogin() async throws {
        let selected = try day("2026-09-16")
        MockURLProtocol.handler = { request in
            let data = #"{"error":"Abgelaufen.","code":"TOKEN_EXPIRED"}"#.data(using: .utf8)!
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (data, response)
        }
        do {
            _ = try await SchoolRepository(client: client()).agenda(day: selected)
            Issue.record("Fehler erwartet")
        } catch let error as APIError {
            #expect(error.needsReLogin)
        }
        do {
            _ = try await SchoolRepository(client: client()).substitutions(day: selected)
            Issue.record("Fehler erwartet")
        } catch let error as APIError {
            #expect(error.needsReLogin)
        }
    }
}
