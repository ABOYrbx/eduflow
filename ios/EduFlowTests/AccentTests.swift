import Foundation
import SwiftUI
import UIKit
import XCTest

@testable import EduFlow

// MARK: - Akzent + Darstellung (Paket F/G, offline, ohne Zugangsdaten)
//
// Prüft die 8er-Palette (wie Web/Android), den Dark-Swatch und die
// Persistenz/Validierung der Prefs — ohne Netzwerk.

final class AccentTests: XCTestCase {

    // MARK: Palette (theme.js data-accent, Android Color.kt Accents)

    func testAccentOptionsKeys() {
        XCTAssertEqual(AccentOptions.all.count, 8)
        XCTAssertEqual(AccentOptions.all.map(\.key),
            ["black", "blue", "violet", "teal", "green", "orange", "red", "pink"])
        XCTAssertEqual(Set(AccentOptions.all.map(\.key)).count, 8)
        XCTAssertFalse(AccentOptions.all.contains(where: { $0.label.isEmpty }))
    }

    func testAccentOptionFallback() {
        XCTAssertEqual(AccentOptions.option(for: "blue").label, "Blau")
        XCTAssertEqual(AccentOptions.option(for: "quatsch").key, "black")
    }

    func testAccentSwatch() {
        // Schwarz wird im Dark Mode weiß (wie Web/Android swatchColor).
        XCTAssertEqual(rgb(AccentOptions.option(for: "black").swatch(dark: false)), RGB(0, 0, 0))
        XCTAssertEqual(rgb(AccentOptions.option(for: "black").swatch(dark: true)), RGB(255, 255, 255))
        // Bunte Akzente sind in beiden Modi gleich.
        let blue = AccentOptions.option(for: "blue")
        XCTAssertEqual(rgb(blue.swatch(dark: false)), rgb(blue.swatch(dark: true)))
        XCTAssertEqual(rgb(blue.swatch(dark: false)), RGB(0x25, 0x63, 0xEB))
    }

    // MARK: Prefs (TokenStore, UserDefaults — Originale wiederherstellen)

    func testAccentPersistedAndValidated() async {
        let d = UserDefaults.standard
        let orig = d.string(forKey: "eduflow.accent")
        addTeardownBlock {
            if let o = orig { d.set(o, forKey: "eduflow.accent") }
            else { d.removeObject(forKey: "eduflow.accent") }
        }
        d.set("VIOLET", forKey: "eduflow.accent")
        let store = await TokenStore()
        let initial = await store.accent
        XCTAssertEqual(initial, "violet")
        await store.setAccent(" RED ")
        let red = await store.accent
        XCTAssertEqual(red, "red")
        XCTAssertEqual(d.string(forKey: "eduflow.accent"), "red")
        await store.setAccent("quatsch")
        let fallback = await store.accent
        XCTAssertEqual(fallback, "black")
        await store.setAccent("")
        let blank = await store.accent
        XCTAssertEqual(blank, "black")
    }

    func testAppearanceAndNotifications() async {
        let d = UserDefaults.standard
        let origApp = d.string(forKey: "eduflow.appearance")
        let hadNotif = d.object(forKey: "eduflow.notifications")
        addTeardownBlock {
            if let o = origApp { d.set(o, forKey: "eduflow.appearance") }
            else { d.removeObject(forKey: "eduflow.appearance") }
            if let n = hadNotif { d.set(n, forKey: "eduflow.notifications") }
            else { d.removeObject(forKey: "eduflow.notifications") }
        }
        d.set("dark", forKey: "eduflow.appearance")
        d.removeObject(forKey: "eduflow.notifications")
        let store = await TokenStore()
        let appearance = await store.appearance
        XCTAssertEqual(appearance, "dark")
        let notifDefault = await store.notificationsEnabled
        XCTAssertTrue(notifDefault)
        await store.setAppearance("hell")
        let appearanceFallback = await store.appearance
        XCTAssertEqual(appearanceFallback, "system")
        await store.setNotificationsEnabled(false)
        let notifOff = await store.notificationsEnabled
        XCTAssertFalse(notifOff)
        XCTAssertEqual(d.bool(forKey: "eduflow.notifications"), false)
    }

    // MARK: Helfer

    private struct RGB: Equatable {
        let r, g, b: Int
        init(_ r: Int, _ g: Int, _ b: Int) { self.r = r; self.g = g; self.b = b }
    }

    private func rgb(_ color: Color) -> RGB {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        return RGB(Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }
}
