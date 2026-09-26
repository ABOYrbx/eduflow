import SwiftUI

// MARK: - App-Einstieg (Redesign-PNG, Paket 0)
//
// Bottom-Tabs: Home, Aufgaben, Nachr., Plan, Mehr. Dark Mode folgt dem
// System. Alle Strings deutsch.

@main
struct EduFlowApp: App {
    @StateObject private var store = TokenStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var store: TokenStore
    @State private var client: APIClient?

    var body: some View {
        Group {
            if store.isLoggedIn, let client {
                MainTabs(client: client)
                    .environmentObject(store)
                    .preferredColorScheme(colorScheme(for: store.appearance))
            } else {
                LoginView()
                    .environmentObject(store)
                    .preferredColorScheme(colorScheme(for: store.appearance))
            }
        }
        .onAppear {
            let base = URL(string: store.baseURL)
                ?? URL(string: TokenStore.defaultBaseURL)!
            client = APIClient(baseURL: base, tokenProvider: { store.currentToken() })
        }
        .onChange(of: store.baseURL) { _, newURL in
            let base = URL(string: newURL) ?? URL(string: TokenStore.defaultBaseURL)!
            client = APIClient(baseURL: base, tokenProvider: { store.currentToken() })
        }
    }

    /// Erscheinungsbild-Wahl aus den Einstellungen (Paket F):
    /// Hell/Dunkel explizit, sonst folgt die App dem System.
    private func colorScheme(for appearance: String) -> ColorScheme? {
        switch appearance {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }
}

struct MainTabs: View {
    @EnvironmentObject var store: TokenStore
    @StateObject private var landing: LandingState
    let client: APIClient

    init(client: APIClient) {
        self.client = client
        _landing = StateObject(wrappedValue: LandingState(
            service: SettingsService(client: { client })))
    }

    var body: some View {
        TabView(selection: $landing.selected) {
            OverviewView(client: client)
                .tabItem { Label("Home", systemImage: "house") }
                .tag(LandingState.Tab.overview)
            HomeworkView(service: HomeworkService(client: { client }))
                .tabItem { Label("Aufgaben", systemImage: "checklist") }
                .tag(LandingState.Tab.homework)
            MessagesView(service: MessagesService(client: { client }))
                .tabItem { Label("Nachr.", systemImage: "envelope") }
                .tag(LandingState.Tab.messages)
            TimetableView(service: TimetableService(client: { client }))
                .tabItem { Label("Plan", systemImage: "calendar") }
                .tag(LandingState.Tab.timetable)
            MoreView(client: client)
                .tabItem { Label("Mehr", systemImage: "ellipsis.circle") }
                .tag(LandingState.Tab.more)
        }
        .task { await landing.resolve() }
    }
}

// MARK: - Mehr-Tab (Redesign-PNG, Paket F)

/// Sammelstelle für Noten, Einstellungen, Geräte, Server-URL,
/// Cache leeren und Abmelden.
struct MoreView: View {
    @EnvironmentObject var store: TokenStore
    let client: APIClient
    @State private var serverDraft = ""
    @State private var showServer = false
    @State private var notice: String?
    @State private var error: APIError?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ScreenHead(title: "Mehr",
                               subtitle: "Weitere Bereiche")
                    NavigationLink {
                        GradesView(service: GradesService(client: { client }))
                    } label: {
                        MoreRow(icon: "chart.bar", title: "Noten",
                                subtitle: "Deine Leistungen nach Fach")
                    }
                    .buttonStyle(.plain)
                    NavigationLink {
                        SettingsView(client: client).environmentObject(store)
                    } label: {
                        MoreRow(icon: "gearshape", title: "Einstellungen",
                                subtitle: "Darstellung, Konto und Server")
                    }
                    .buttonStyle(.plain)
                    NavigationLink {
                        DevicesView(client: client).environmentObject(store)
                    } label: {
                        MoreRow(icon: "iphone", title: "Geräte",
                                subtitle: "Angemeldete Geräte verwalten")
                    }
                    .buttonStyle(.plain)
                    Button { showServer = true } label: {
                        MoreRow(icon: "server.rack", title: "Server-URL",
                                subtitle: store.baseURL)
                    }
                    .buttonStyle(.plain)
                    Button { Task { await clearCache() } } label: {
                        MoreRow(icon: "trash", title: "Cache leeren",
                                subtitle: notice ?? "Zwischengespeicherte Daten löschen")
                    }
                    .buttonStyle(.plain)
                    Button(role: .destructive) {
                        Task { await AuthService(client: { client }, store: store).logout() }
                    } label: {
                        MoreRow(icon: "rectangle.portrait.and.arrow.right",
                                title: "Abmelden",
                                subtitle: "Von diesem Gerät abmelden",
                                destructive: true)
                    }
                    .buttonStyle(.plain)
                    if let error {
                        AuthAwareError(error: error,
                                       onReLogin: { Task { await reLogin() } },
                                       onDismiss: { self.error = nil })
                    }
                }
                .padding(16)
            }
            .background(Color.rBackground)
            .navigationTitle("Mehr")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { serverDraft = store.baseURL }
            .sheet(isPresented: $showServer) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Server-URL")
                        .font(RFont.screenTitle)
                        .foregroundStyle(Color.rInk)
                    Text("Server für API-Anfragen (…/api/v1/).")
                        .font(RFont.cardSub)
                        .foregroundStyle(Color.rMuted)
                    TextField("Server-URL", text: $serverDraft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(12)
                        .background(Color.rCard)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.rCardBorder, lineWidth: 1))
                    PrimaryButton(text: "Übernehmen", action: {
                        let trimmed = serverDraft.trimmingCharacters(
                            in: .whitespacesAndNewlines).trimmingCharacters(
                                in: CharacterSet(charactersIn: "/"))
                        store.setBaseURL(trimmed.isEmpty
                                         ? TokenStore.defaultBaseURL : trimmed)
                        showServer = false
                    })
                    Button("Abbrechen") { showServer = false }
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .padding(20)
                .background(Color.rBackground)
            }
        }
    }

    private func clearCache() async {
        self.error = nil
        do {
            let res = try await SettingsService(client: { client }).clearCache()
            notice = "\(res.cleared) Datei(en) gelöscht"
        } catch let e as APIError {
            self.error = e
        } catch {
            self.error = APIError(code: "UPSTREAM", message: APIError.message(for: "UPSTREAM"), httpStatus: 0)
        }
    }

    private func reLogin() async {
        await AuthService(client: { client }, store: store).logout()
    }
}

/// Mehr-Zeile: Icon + Titel/Sub + Chevron (Abmelden rot).
struct MoreRow: View {
    let icon: String
    let title: String
    let subtitle: String
    var destructive = false

    var body: some View {
        EduCard {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundStyle(destructive ? Color.red : Color.rMuted)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(destructive ? Color.red : Color.rInk)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Color.rMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .foregroundStyle(Color.rMuted)
            }
        }
    }
}

// MARK: - Geteilte UI-Bausteine (wie Android CommonUi)

/// Fehler mit 401-Verhalten: abgelaufene/ungültige Sitzung führt zum
/// Login, alle anderen Fehler sind nur verwerfbar (deutsche Kurztexte).
struct AuthAwareError: View {
    let error: APIError
    let onReLogin: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(error.message) (\(error.code)")
                .font(.footnote)
                .foregroundStyle(.red)
            HStack {
                if error.needsReLogin {
                    Button("Anmelden", action: onReLogin)
                } else {
                    Button("OK", action: onDismiss)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct CountChip: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.secondary.opacity(0.15))
            .clipShape(Capsule())
    }
}

struct SectionHead: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.headline)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
