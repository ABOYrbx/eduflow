import EduFlow
import Foundation
import Testing

/// Paket-C-Tests (offline, stubbendes URL-Protokoll, kein echtes Login).
///
/// Prüfen Routenform aller vier Endpunkte (Body-Schlüssel für Erledigt
/// und Papierkorb), Filter, Zähler und Sortierung gegen Stub wie im Web,
/// Statuswechsel, Noten-Schnitt und Halbjahr-Ableitung gegen bekannte
/// Werte, flexible Noten-ID, Paginierung und 401-Verhalten.
/// Serialisiert: der Stub-Handler ist geteilter Zustand.
@Suite(.serialized)
struct HomeworkTests {

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

    @Test("Liste sendet Web-Parameter und Zähler")
    func listSendsWebParameters() async throws {
        MockURLProtocol.handler = { request in
            #expect(request.url?.path.hasSuffix("homework") == true)
            let url = try #require(request.url)
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            func value(_ name: String) -> String? {
                query.first(where: { $0.name == name })?.value
            }
            #expect(value("status") == "offen")
            #expect(value("include_tests") == "1")
            #expect(value("q") == "mathe")
            #expect(value("limit") == "50")
            #expect(value("offset") == "0")
            let data = #"{"items":[{"id":3,"title":"Übung","status":"offen"}],"total":1,"limit":50,"offset":0,"counts":{"offen":1,"ueberfaellig":2,"erledigt":3,"papierkorb":0},"cache_info":"Cache"}"#
                .data(using: .utf8)!
            let response = HTTPURLResponse(
                url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (data, response)
        }
        let response = try await HomeworkRepository(client: client())
            .list(status: "offen", includeTests: true, query: "mathe")
        #expect(response.total == 1)
        #expect(response.items.first?.title == "Übung")
        #expect(response.counts?.ueberfaellig == 2)
        #expect(response.cacheInfo == "Cache")
    }

    @Test("Erledigt- und Papierkorb-Schalter mit Body-Schlüsseln")
    func doneAndTrashSwitches() async throws {
        let repo = HomeworkRepository(client: client())
        MockURLProtocol.handler = { request in
            #expect(request.url?.path.hasSuffix("homework/3/done") == true)
            let body = try requestBody(request)
            #expect((body["done"] as? Bool) == false)
            let data = #"{"id":3,"title":"Übung","status":"offen","is_done":false}"#
                .data(using: .utf8)!
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (data, response)
        }
        let reopened = try await repo.setDone(id: 3, done: false)
        #expect(reopened.status == "offen")
        #expect(!reopened.isDone)
        MockURLProtocol.handler = { request in
            #expect(request.url?.path.hasSuffix("homework/3/trash") == true)
            let body = try requestBody(request)
            #expect((body["hide"] as? Bool) == true)
            let data = #"{"id":3,"title":"Übung","is_hidden":true}"#.data(using: .utf8)!
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (data, response)
        }
        let trashed = try await repo.setTrash(id: 3, hide: true)
        #expect(trashed.isHidden)
    }

    @Test("Ungültiger Status und fehlende Aufgabe melden Fehler")
    func errors() async throws {
        stub(status: 400, body: #"{"error":"Ungültiger Status.","code":"VALIDATION"}"#)
        do {
            _ = try await HomeworkRepository(client: client()).list(status: "falsch")
            Issue.record("Fehler erwartet")
        } catch let error as APIError {
            #expect(error.code == "VALIDATION")
        }
        stub(status: 404, body: #"{"error":"Nicht gefunden.","code":"NOT_FOUND"}"#)
        do {
            _ = try await HomeworkRepository(client: client()).setDone(id: 999)
            Issue.record("Fehler erwartet")
        } catch let error as APIError {
            #expect(error.code == "NOT_FOUND")
        }
    }

    @Test("Noten-ID ist Zahl oder Zeichenkette")
    func flexibleGradeID() throws {
        let numeric = try APIClient.decode(
            GradeDTO.self,
            from: Data(#"{"id":42,"title":"Test"}"#.utf8)
        )
        #expect(numeric.id?.raw == "42")
        let textual = try APIClient.decode(
            GradeDTO.self,
            from: Data(#"{"id":"abc-1","title":"Test"}"#.utf8)
        )
        #expect(textual.id?.raw == "abc-1")
    }

    @Test("Schnitt über klassische Noten mit Gewichtung")
    func averageOverClassicGrades() {
        func grade(_ num: Double?, classic: Bool, weight: Double?) -> GradeDTO {
            var item = GradeDTO()
            item.gradeNum = num
            item.isClassic = classic
            item.weight = weight
            return item
        }
        let items = [
            grade(1.0, classic: true, weight: 1.0),
            grade(3.0, classic: true, weight: 2.0),
            grade(nil, classic: false, weight: 1.0),
            grade(5.0, classic: false, weight: 1.0),
        ]
        #expect(GradesAverage.of(items) == 2.33)
        #expect(GradesAverage.display(GradesAverage.of(items)) == "2,33")
        #expect(GradesAverage.of([]) == nil)
        #expect(GradesAverage.display(nil) == "–")
        #expect(GradesAverage.of([grade(nil, classic: false, weight: 1.0)]) == nil)
    }

    @Test("Halbjahr-Ableitung wie im Web")
    func halfYearMapping() {
        #expect(HalfYear.key(for: "2024-09-15") == .half(yearStart: 2024, half: 1))
        #expect(HalfYear.key(for: "2025-01-20") == .half(yearStart: 2024, half: 1))
        #expect(HalfYear.key(for: "2025-02-03") == .half(yearStart: 2024, half: 2))
        #expect(HalfYear.key(for: "2025-08-30") == .half(yearStart: 2024, half: 2))
        #expect(HalfYear.key(for: nil) == nil)
        #expect(HalfYear.key(for: "falsch") == nil)
        // Labels sind uebersetzt — also gegen die aktive App-Sprache pruefen
        // (Katalog ist mehrsprachig, `value` dient als Quelle).
        #expect(
            HalfYear.half(yearStart: 2024, half: 1).label
                == String(
                    format: NSLocalizedString("grades_halfyear_format", value: "Semester %d (%d/%@)", comment: "Test"),
                    1,
                    2024,
                    "25"
                )
        )
        #expect(HalfYear.all.label == NSLocalizedString("grades_halfyear_all", value: "All", comment: "Test"))
    }

    @Test("Notenliste mit Paginierung und Cache-Info")
    func gradesList() async throws {
        MockURLProtocol.handler = { request in
            #expect(request.url?.path.hasSuffix("grades") == true)
            let url = try #require(request.url)
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            #expect(query.first(where: { $0.name == "limit" })?.value == "50")
            let data = #"{"items":[{"id":1,"title":"Test","subject":"Mathe","grade_display":"2","grade_num":2.0,"is_classic":true}],"total":1,"limit":50,"offset":0,"cache_info":"Cache"}"#
                .data(using: .utf8)!
            let response = HTTPURLResponse(
                url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (data, response)
        }
        let response = try await GradesRepository(client: client()).list()
        #expect(response.total == 1)
        #expect(response.items.first?.gradeDisplay == "2")
        #expect(response.cacheInfo == "Cache")
    }

    @Test("Liste sendet Zeitraum, Umlaut-Status, Paginierung und Refresh")
    func listSendsFullParameterSet() async throws {
        MockURLProtocol.handler = { request in
            #expect(request.url?.path.hasSuffix("homework") == true)
            let url = try #require(request.url)
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            func value(_ name: String) -> String? {
                query.first(where: { $0.name == name })?.value
            }
            #expect(value("since") == "2024-01-01")
            #expect(value("status") == "überfällig")
            #expect(value("limit") == "50")
            #expect(value("offset") == "50")
            #expect(value("refresh") == "1")
            #expect(value("include_tests") == nil)
            let data = #"{"items":[],"total":0,"limit":50,"offset":50,"counts":{"offen":0,"ueberfaellig":0,"erledigt":0,"papierkorb":0}}"#
                .data(using: .utf8)!
            let response = HTTPURLResponse(
                url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (data, response)
        }
        let response = try await HomeworkRepository(client: client()).list(
            since: "2024-01-01", status: "überfällig", offset: 50, refresh: true)
        #expect(response.total == 0)
        #expect(response.items.isEmpty)
    }

    @Test("Hausaufgabe dekodiert alle Schlüssel aus homework_to_dict")
    func homeworkDecodesFullSerializerKeys() throws {
        let json = """
            {"id":11,"type":"homework","type_label":"Hausaufgabe","title":"Lesen",\
            "description":"Seite 12","subject":"Deutsch","author":"Frau A",\
            "recipient":"Klasse 5a","assigned":"2025-01-06 08:00",\
            "assigned_iso":"2025-01-06T08:00:00","due":"2025-01-08",\
            "due_display":"Mi 08.01.2025","due_raw":"08.01.2025",\
            "status":"offen","status_class":"st-offen","tag_class":"tag-blue",\
            "is_done":false,"done_at":"","is_starred":true,\
            "extra":"{}","is_hidden":true}
            """
        let item = try APIClient.decode(HomeworkDTO.self, from: Data(json.utf8))
        #expect(item.id == 11)
        #expect(item.typeLabel == "Hausaufgabe")
        #expect(item.subject == "Deutsch")
        #expect(item.assignedIso == "2025-01-06T08:00:00")
        #expect(item.due == "2025-01-08")
        #expect(item.dueDisplay == "Mi 08.01.2025")
        #expect(item.dueRaw == "08.01.2025")
        #expect(item.statusClass == "st-offen")
        #expect(item.tagClass == "tag-blue")
        #expect(item.isStarred)
        #expect(item.isHidden)
    }

    @Test("Statuswechsel sind in der Antwort sichtbar")
    func statusSwitchesAreVisible() async throws {
        let repo = HomeworkRepository(client: client())
        MockURLProtocol.handler = { request in
            #expect(request.url?.path.hasSuffix("homework/11/done") == true)
            let data = #"{"id":11,"title":"Lesen","status":"erledigt","is_done":true}"#
                .data(using: .utf8)!
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (data, response)
        }
        let done = try await repo.setDone(id: 11, done: true)
        #expect(done.isDone)
        #expect(done.status == "erledigt")
        MockURLProtocol.handler = { request in
            #expect(request.url?.path.hasSuffix("homework/11/trash") == true)
            let body = try requestBody(request)
            #expect((body["hide"] as? Bool) == false)
            let data = #"{"id":11,"title":"Lesen","status":"offen","is_done":false,"is_hidden":false}"#
                .data(using: .utf8)!
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (data, response)
        }
        let restored = try await repo.setTrash(id: 11, hide: false)
        #expect(!restored.isHidden)
        #expect(!restored.isDone)
        #expect(restored.status == "offen")
    }

    @Test("401 bei Hausaufgaben und Noten führt zum Login")
    func unauthorizedLeadsToLogin() async throws {
        stub(status: 401, body: #"{"error":"Sitzung abgelaufen.","code":"TOKEN_EXPIRED"}"#)
        do {
            _ = try await HomeworkRepository(client: client()).list()
            Issue.record("Fehler erwartet")
        } catch let error as APIError {
            #expect(error.code == "TOKEN_EXPIRED")
            #expect(error.httpStatus == 401)
            #expect(SessionRecovery.forceLogout(error: error, isLoggedIn: true))
            #expect(!SessionRecovery.forceLogout(error: error, isLoggedIn: false))
        }
        do {
            _ = try await GradesRepository(client: client()).list()
            Issue.record("Fehler erwartet")
        } catch let error as APIError {
            #expect(error.code == "TOKEN_EXPIRED")
            #expect(error.httpStatus == 401)
            #expect(SessionRecovery.forceLogout(error: error, isLoggedIn: true))
        }
    }

    @Test("Note dekodiert alle Schlüssel aus grade_to_dict")
    func gradeDecodesFullSerializerKeys() throws {
        let json = """
            {"id":7,"title":"Klassenarbeit","subject":"Mathe","teacher":"Frau B",\
            "date_display":"08.01.2025","date_iso":"2025-01-08",\
            "sort_key":"2025-01-08T00:00:00","comment":"Gut","grade_display":"2",\
            "grade_num":2.0,"weight":2.0,"weight_display":"×2",\
            "grade_sub":"Gewichtung ×2","badge":"g12",\
            "class_avg":2.5,"class_avg_display":"2,5","is_classic":true}
            """
        let item = try APIClient.decode(GradeDTO.self, from: Data(json.utf8))
        #expect(item.id?.raw == "7")
        #expect(item.subject == "Mathe")
        #expect(item.dateIso == "2025-01-08")
        #expect(item.sortKey == "2025-01-08T00:00:00")
        #expect(item.gradeDisplay == "2")
        #expect(item.gradeNum == 2.0)
        #expect(item.weight == 2.0)
        #expect(item.weightDisplay == "×2")
        #expect(item.gradeSub == "Gewichtung ×2")
        #expect(item.badge == "g12")
        #expect(item.classAvg == 2.5)
        #expect(item.classAvgDisplay == "2,5")
        #expect(item.isClassic == true)
    }

    @Test("Schnitt schließt ungültige und nicht-klassische Noten aus")
    func averageSkipsInvalidGrades() {
        func grade(_ num: Double?, classic: Bool, weight: Double?) -> GradeDTO {
            var item = GradeDTO()
            item.gradeNum = num
            item.isClassic = classic
            item.weight = weight
            return item
        }
        let items = [
            grade(2.0, classic: true, weight: 1.0),
            grade(0.5, classic: true, weight: 1.0),
            grade(7.0, classic: true, weight: 1.0),
            grade(1.0, classic: false, weight: 1.0),
        ]
        #expect(GradesAverage.of(items) == 2.0)
    }

    @Test("Halbjahr-Tabs: neueste zuerst plus Gesamt-Anhang")
    func halfYearTabsOrder() {
        func grade(_ iso: String) -> GradeDTO {
            var item = GradeDTO()
            item.dateIso = iso
            return item
        }
        let tabs = HalfYear.tabs(for: [grade("2024-10-05"), grade("2025-04-02")])
        #expect(tabs.count == 3)
        #expect(tabs.first == .half(yearStart: 2024, half: 2))
        #expect(tabs.last == .all)
        #expect(HalfYear.tabs(for: []) == [.all])
    }

    @Test("Notenliste meldet Paginierung weiter")
    func gradesListPagination() async throws {
        MockURLProtocol.handler = { request in
            let url = try #require(request.url)
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            #expect(query.first(where: { $0.name == "limit" })?.value == "50")
            #expect(query.first(where: { $0.name == "offset" })?.value == "50")
            #expect(query.first(where: { $0.name == "refresh" })?.value == "1")
            let data = #"{"items":[],"total":60,"limit":50,"offset":50,"cache_info":"Cache"}"#
                .data(using: .utf8)!
            let response = HTTPURLResponse(
                url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (data, response)
        }
        let response = try await GradesRepository(client: client()).list(offset: 50, refresh: true)
        #expect(response.total == 60)
        #expect(response.items.isEmpty)
    }
}
