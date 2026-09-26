import Foundation
import XCTest

@testable import EduFlow

// MARK: - Paket-C-Tests (offline, ohne Zugangsdaten)
//
// Prüfen Dekodierung (DTOs 1:1 zu den Web-Dicts), Zähler, Sortier- und
// Statuswerte sowie Schnitt-Berechnung — ohne Netzwerk.

final class HomeworkTests: XCTestCase {

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try Self.decoder.decode(T.self, from: Data(json.utf8))
    }

    // MARK: Hausaufgabenliste (api/homework.py: Page + counts + cache_info)

    func testHomeworkListDecoding() throws {
        let list = try decode(HomeworkListResponse.self, """
        {"items": [{"id": 11, "title": "Vokabeln", "status": "überfällig",
                    "due_display": "Mo 01.01.", "subject": "Englisch",
                    "is_done": false, "is_hidden": false}],
         "total": 1, "limit": 50, "offset": 0,
         "counts": {"offen": 1, "ueberfaellig": 1, "erledigt": 0, "papierkorb": 0},
         "cache_info": "aus Cache"}
        """)
        XCTAssertEqual(list.total, 1)
        XCTAssertEqual(list.items.first?.uid, "11")
        XCTAssertEqual(list.items.first?.status, HomeworkItemStatus.ueberfaellig)
        XCTAssertEqual(list.counts?.offen, 1)
        XCTAssertEqual(list.counts?.ueberfaellig, 1)
        XCTAssertEqual(list.cacheInfo, "aus Cache")
    }

    func testHomeworkStatusFilters() {
        XCTAssertEqual(HomeworkStatusFilter.all,
                       ["alle", "offen", "überfällig", "erledigt", "papierkorb"])
        XCTAssertEqual(HomeworkItemStatus.heute, "heute fällig")
    }

    // MARK: Notenliste (api/grades.py: Page + cache_info, Cache-Reihenfolge)

    func testGradesListDecoding() throws {
        let list = try decode(GradesListResponse.self, """
        {"items": [{"id": "g1", "title": "Test", "subject": "Mathe",
                    "grade_display": "2", "grade_num": 2.0, "weight": 1.0,
                    "badge": "g12", "is_classic": true},
                   {"id": "g2", "title": "Referat", "subject": "Deutsch",
                    "grade_display": "Sehr gut", "grade_num": null,
                    "weight": 1.0, "badge": "gx", "is_classic": false}],
         "total": 2, "limit": 50, "offset": 0, "cache_info": "frisch geladen"}
        """)
        XCTAssertEqual(list.total, 2)
        XCTAssertEqual(list.items.first?.subject, "Mathe")
        XCTAssertEqual(list.items.first?.gradeNum, 2.0)
        XCTAssertNil(list.items.last?.gradeNum)
        XCTAssertEqual(list.cacheInfo, "frisch geladen")
    }

    // MARK: Schnitt (wie grades_average in app.py: gewichtet, nur klassisch)

    func testGradesAverage() throws {
        let list = try decode(GradesListResponse.self, """
        {"items": [{"id": "g1", "grade_num": 2.0, "weight": 1.0, "is_classic": true},
                   {"id": "g2", "grade_num": 4.0, "weight": 3.0, "is_classic": true},
                   {"id": "g3", "grade_num": null, "weight": 1.0, "is_classic": false}],
         "total": 3, "limit": 50, "offset": 0}
        """)
        // (2*1 + 4*3) / 4 = 3,5 — verbale Note zählt nicht mit.
        XCTAssertEqual(GradesAverage.of(list.items) ?? 0, 3.5, accuracy: 0.001)
        XCTAssertEqual(GradesAverage.display(3.5), "3,50")
        XCTAssertEqual(GradesAverage.display(nil), "–")
        XCTAssertNil(GradesAverage.of([]))
    }
}
