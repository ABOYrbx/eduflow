import SwiftUI

/// Einziger Einstieg (Paket 0).
///
/// Akzent aus der gespeicherten Wahl (fällt auf Schwarz wie im Web),
/// Hell und Dunkel folgt dem System (SwiftUI-Standard).
@main
struct EduFlowApp: App {
    @State private var store = TokenStore()
    @State private var accent = Accent.stored

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .tint(accent.color)
                .uberAccent(accent)
                .onReceive(NotificationCenter.default.publisher(
                    for: UserDefaults.didChangeNotification
                )) { _ in
                    accent = Accent.stored
                }
        }
        .windowStyle(.hiddenTitleBar)
    }
}
