import Foundation
import XCTest

@testable import EduFlow

// MARK: - Kern-/Auth-/Stundenplan-Tests (offline, ohne Zugangsdaten)
//
// Prüfen Dekodierung (DTOs 1:1 zu den Web-Dicts), Settings-Fallbacks,
// Start-Tab-Abbildung und Fehlercodes — ohne Netzwerk.

final class CoreTests: XCTestCase {

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try Self.decoder.decode(T.self, from: Data(json.utf8))
    }

    // MARK: Login-Antworten (api/auth.py: ok oder 2fa_required)

    func testLoginResponseOK() throws {
        let raw = try decode(RawLoginResponse.self, """
        {"status": "ok", "token": "abc", "expires": "2030-01-01 00:00:00",
         "subdomain": "schule", "username": "nutzer"}
        """)
        XCTAssertEqual(raw.status, "ok")
        XCTAssertEqual(raw.token, "abc")
    }

    func testLoginResponse2FA() throws {
        let raw = try decode(RawLoginResponse.self, """
        {"status": "2fa_required", "pending_token": "p1", "message": "Code eingeben"}
        """)
        XCTAssertEqual(raw.status, "2fa_required")
        XCTAssertEqual(raw.pendingToken, "p1")
    }

    func testDevicesDecoding() throws {
        let dto = try decode(DevicesDTO.self, """
        {"items": [{"id": "h1", "short": "…abcdef", "device": "iPhone",
                    "created": "2026-01-01 10:00:00", "expires": "2030-01-01 10:00:00"}],
         "total": 1}
        """)
        XCTAssertEqual(dto.total, 1)
        XCTAssertEqual(dto.items.first?.short, "…abcdef")
    }

    // MARK: Einstellungen (Parität mit SETTINGS_SCHEMA, Fallbacks)

    func testSettingsValuesFallbacks() {
        let values = SettingsValues.from([
            "landing": .string("unbekannt"),
            "hw_status": .string("offen"),
            "hw_tests": .bool(true),
            "ov_unread": .int(99),
            "ov_homework": .int(0),
        ])
        XCTAssertEqual(values.landing, "uebersicht")
        XCTAssertEqual(values.hwStatus, "offen")
        XCTAssertTrue(values.hwTests)
        XCTAssertEqual(values.ovUnread, 50)
        XCTAssertEqual(values.ovHomework, 1)
    }

    func testSettingsResponseDecoding() throws {
        let res = try decode(SettingsResponse.self, """
        {"schema": [{"key": "landing", "kind": "select", "label": "Start",
                     "options": [["uebersicht", "Übersicht"]]}],
         "values": {"landing": "stundenplan", "hw_tests": true, "ov_unread": 5}}
        """)
        let values = SettingsValues.from(res.values)
        XCTAssertEqual(values.landing, "stundenplan")
        XCTAssertTrue(values.hwTests)
        XCTAssertEqual(values.ovUnread, 5)
        XCTAssertEqual(values.ovHomework, 10)
    }

    // MARK: Start-Tab (landing → Tab, Fallback Übersicht)

    func testLandingTab() {
        XCTAssertEqual(LandingState.tab(for: "dashboard"), .messages)
        XCTAssertEqual(LandingState.tab(for: "hausaufgaben"), .homework)
        XCTAssertEqual(LandingState.tab(for: "noten"), .more)
        XCTAssertEqual(LandingState.tab(for: "stundenplan"), .timetable)
        XCTAssertEqual(LandingState.tab(for: "uebersicht"), .overview)
        XCTAssertEqual(LandingState.tab(for: "quatsch"), .overview)
    }

    // MARK: Stundenplan (api/timetable.py: merge_lernzeit serverseitig)

    func testTimetableDayDecoding() throws {
        let day = try decode(TimetableDayResponse.self, """
        {"day": "2026-09-24", "day_label": "Donnerstag 24.09.2026",
         "prev_day": "2026-09-23", "next_day": "2026-09-25",
         "today": "2026-09-24",
         "lessons": [{"period": "2–3", "time": "08:35–10:20", "title": "Lernzeit",
                      "is_lernzeit": true, "rowspan": 2, "is_cancelled": false},
                     {"period": "4", "time": "10:25–11:10", "title": "Englisch",
                      "is_cancelled": true, "is_online": false}],
         "cache_info": "aus Cache"}
        """)
        XCTAssertEqual(day.lessons.count, 2)
        XCTAssertEqual(day.lessons.first?.rowspan, 2)
        XCTAssertTrue(day.lessons.last?.isCancelled == true)
    }

    func testTimetableWeekDecoding() throws {
        let week = try decode(TimetableWeekResponse.self, """
        {"day": "2026-09-24", "monday": "2026-09-21",
         "week_label": "Woche 21.09. – 25.09.2026",
         "days": [{"date": "2026-09-21", "day_name": "Montag",
                   "day_date": "21.09.", "is_today": false, "lessons": []}],
         "cache_info": "Woche aus Cache (0 API-Requests)"}
        """)
        XCTAssertEqual(week.days.count, 1)
        XCTAssertTrue(week.weekLabel.hasPrefix("Woche "))
    }

    // MARK: Wetter

    func testWetterDecoding() throws {
        let wetter = try decode(WetterResponse.self, """
        {"city": "Berlin",
         "today": {"temp": 18, "max": 20, "min": 12, "desc": "Leicht bewölkt",
                   "icon": "02d", "pop": null},
         "details": {"feels_like": 17, "wind_kmh": 14, "wind_dir": null,
                     "visibility_km": 10.0, "sunrise": "06:58", "sunset": null}}
        """)
        XCTAssertEqual(wetter.city, "Berlin")
        XCTAssertEqual(wetter.today?.temp, 18)
        XCTAssertNil(wetter.today?.pop)
        XCTAssertNil(wetter.details?.windDir)
        XCTAssertEqual(wetter.details?.visibilityKm, 10.0)
    }

    // MARK: Aktuelle/nächste Stunde (wie Web uebersicht)

    func testCurrentAndNextEmpty() {
        let (current, next) = ISODate.currentAndNext([])
        XCTAssertNil(current)
        XCTAssertNil(next)
    }
}
