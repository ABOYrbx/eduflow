import Foundation
import XCTest

@testable import EduFlow

// MARK: - Halbjahre + Fachgruppierung (Paket E, offline, ohne Zugangsdaten)
//
// Prüft die Halbjahr-Logik (wie Web-noten()/Android Grades.kt),
// die sort_key-Dekodierung und die Gruppierung im ViewModel —
// ohne Netzwerk.

final class GradeTermsTests: XCTestCase {

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try Self.decoder.decode(T.self, from: Data(json.utf8))
    }

    // MARK: Halbjahr-Key (Schuljahr Sept–Aug, wie currentTermKey)

    func testCurrentKey() {
        XCTAssertEqual(GradeTerms.currentKey(year: 2025, month: 9), "2025-H1")
        XCTAssertEqual(GradeTerms.currentKey(year: 2026, month: 1), "2025-H1")
        XCTAssertEqual(GradeTerms.currentKey(year: 2026, month: 2), "2025-H2")
        XCTAssertEqual(GradeTerms.currentKey(year: 2026, month: 8), "2025-H2")
        XCTAssertEqual(GradeTerms.currentKey(year: 2025, month: 8), "2024-H2")
    }

    func testKeyFallback() {
        XCTAssertEqual(GradeTerms.key(for: "2025-11-03", fallback: "fb"), "2025-H1")
        XCTAssertEqual(GradeTerms.key(for: "2026-03-01", fallback: "fb"), "2025-H2")
        XCTAssertEqual(GradeTerms.key(for: "kein-datum", fallback: "fb"), "fb")
        XCTAssertEqual(GradeTerms.key(for: nil, fallback: "fb"), "fb")
    }

    func testLabel() {
        XCTAssertEqual(GradeTerms.label(for: "2025-H1"), "1. Halbjahr 25/26")
        XCTAssertEqual(GradeTerms.label(for: "2025-H2"), "2. Halbjahr 25/26")
        XCTAssertEqual(GradeTerms.label(for: "quatsch"), "quatsch")
    }

    // MARK: Tabs (neuestes zuerst + Gesamt, wie buildGradeTerms)

    func testBuildNewestFirstPlusGesamt() throws {
        let page = try decode(GradesListResponse.self, """
        {"items": [
          {"id": 1, "subject": "Mathematik", "date_iso": "2025-11-01"},
          {"id": 2, "subject": "Deutsch", "date_iso": "2026-02-01"},
          {"id": 3, "subject": "Mathematik", "date_iso": "2026-02-05"}],
         "total": 3, "limit": 50, "offset": 0}
        """)
        let terms = GradeTerms.build(from: page.items, fallback: "2025-H1")
        XCTAssertEqual(terms.map(\.key), ["2025-H2", "2025-H1", "alle"])
        XCTAssertEqual(terms.first?.label, "2. Halbjahr 25/26")
        XCTAssertEqual(terms.last?.count, 3)
    }

    func testBuildEmpty() {
        let terms = GradeTerms.build(from: [], fallback: "2025-H1")
        XCTAssertEqual(terms.map(\.key), ["alle"])
        XCTAssertEqual(terms.first?.count, 0)
    }

    // MARK: sort_key (DTO-Ergänzung für „neueste zuerst")

    func testSortKeyDecoding() throws {
        let withKey = try decode(GradeItem.self, """
        {"id": 1, "subject": "M", "sort_key": "2026-03-01 10:00"}
        """)
        XCTAssertEqual(withKey.sortKey, "2026-03-01 10:00")
        let withoutKey = try decode(GradeItem.self, """
        {"id": 2, "subject": "M"}
        """)
        XCTAssertNil(withoutKey.sortKey)
    }

    // MARK: Gruppierung (Fächer alphabetisch, Noten neueste zuerst)

    func testGroupsAlphabeticalNewestFirst() async throws {
        let page = try decode(GradesListResponse.self, """
        {"items": [
          {"id": 1, "subject": "Mathematik", "title": "Alt",
           "date_iso": "2025-11-01", "sort_key": "2025-11-01",
           "grade_num": 3.0, "is_classic": true, "weight": 1.0},
          {"id": 2, "subject": "Deutsch", "title": "Neu",
           "date_iso": "2026-02-01", "sort_key": "2026-02-01",
           "grade_num": 2.0, "is_classic": true, "weight": 1.0},
          {"id": 3, "subject": "Mathematik", "title": "Neu",
           "date_iso": "2026-02-05", "sort_key": "2026-02-05",
           "grade_num": 1.0, "is_classic": true, "weight": 1.0}],
         "total": 3, "limit": 50, "offset": 0}
        """)
        let vm = await GradesViewModel(service: GradesService(client: {
            APIClient(baseURL: URL(string: "http://127.0.0.1:8000/api/v1/")!,
                      tokenProvider: { nil })
        }))
        await MainActor.run { vm.items = page.items }
        let groups = await MainActor.run { vm.groups }
        XCTAssertEqual(groups.map(\.subject), ["Deutsch", "Mathematik"])
        XCTAssertEqual(groups.last?.items.compactMap { $0.id?.raw }, ["3", "1"])
        let average = await MainActor.run { vm.average }
        XCTAssertEqual(average ?? 0, 2.0, accuracy: 0.001)
    }
}
