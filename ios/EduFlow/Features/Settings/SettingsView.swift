import SwiftUI

// MARK: - Einstellungen (Paket F, Redesign-PNG Screen 05)
//
// Titel + „Dein EduFlow-Konto", Profil-Karte (Avatar, Name,
// „Schule · verbunden"), Sektionen DARSTELLUNG (Erscheinungsbild
// Hell/Dunkel/System), BENACHRICHTIGUNGEN (Schalter „Neue
// Nachrichten", lokal), ÜBERSICHT & AUFGABEN (Startseite,
// Statusfilter, Tests-Schalter, Zähler), WETTER (Karte an/aus +
// Stadt), SERVER, KONTO & SICHERHEIT (Geräte + Anzahl, Datenschutz,
// Abmelden rot). Speichern via PUT (echte JSON-bools), Cache leeren
// erhält die Einstellungen, 401 → Login (Abmelden).

struct SettingsView: View {
    @EnvironmentObject var store: TokenStore
    let client: APIClient
    @State private var values = SettingsValues()
    @State private var baseURL = ""
    @State private var devicesCount = 0
    @State private var isLoading = false
    @State private var error: APIError?
    @State private var notice: String?
    @State private var showPrivacy = false

    private func service() -> SettingsService {
        SettingsService(client: { client })
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    AppHeader(client: client)
                    ScreenHead(title: "Einstellungen",
                               subtitle: "Dein EduFlow-Konto")

                    EduCard {
                        HStack(spacing: 12) {
                            AvatarDot(initials: String(store.username.prefix(1)))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(store.username.isEmpty ? "–" : store.username)
                                    .font(RFont.cardTitle)
                                    .foregroundStyle(Color.rInk)
                                Text("\(store.subdomain.isEmpty ? "Schule" : store.subdomain) · verbunden")
                                    .font(RFont.cardSub)
                                    .foregroundStyle(Color.rMuted)
                            }
                            .layoutPriority(1)
                        }
                    }

                    SectionLabel(text: "Darstellung")
                    EduCard {
                        VStack(alignment: .leading, spacing: 4) {
                            AppearanceRow(
                                title: "Hell", subtitle: "Immer helles Design",
                                selected: store.appearance == "light",
                                action: { store.setAppearance("light") })
                            AppearanceRow(
                                title: "Dunkel", subtitle: "Immer dunkles Design",
                                selected: store.appearance == "dark",
                                action: { store.setAppearance("dark") })
                            AppearanceRow(
                                title: "System", subtitle: "Folgt Hell/Dunkel des Geräts",
                                selected: store.appearance == "system",
                                pill: "System",
                                action: { store.setAppearance("system") })
                            Text("Akzentfarbe")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Color.rInk)
                                .padding(.top, 8)
                            AccentDotsRow(
                                selected: store.accent,
                                onSelect: { store.setAccent($0) })
                        }
                    }

                    SectionLabel(text: "Benachrichtigungen")
                    EduCard {
                        Toggle("Neue Nachrichten", isOn: Binding(
                            get: { store.notificationsEnabled },
                            set: { store.setNotificationsEnabled($0) }
                        ))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.rInk)
                    }

                    SectionLabel(text: "Übersicht & Aufgaben")
                    EduCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Startseite nach Anmeldung")
                                .font(.caption.bold())
                                .foregroundStyle(Color.rMuted)
                            Picker("Startseite", selection: $values.landing) {
                                Text("Übersicht").tag("uebersicht")
                                Text("Nachrichten").tag("dashboard")
                                Text("Aufgaben").tag("hausaufgaben")
                                Text("Noten").tag("noten")
                                Text("Plan").tag("stundenplan")
                            }
                            .pickerStyle(.menu)
                            Text("Aufgaben: Standardfilter")
                                .font(.caption.bold())
                                .foregroundStyle(Color.rMuted)
                            Picker("Statusfilter", selection: $values.hwStatus) {
                                Text("Alle").tag("alle")
                                Text("Offen").tag("offen")
                                Text("Überfällig").tag("überfällig")
                                Text("Erledigt").tag("erledigt")
                                Text("Papierkorb").tag("papierkorb")
                            }
                            .pickerStyle(.menu)
                            Toggle("Tests und Prüfungen einbeziehen", isOn: $values.hwTests)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Color.rInk)
                            Stepper("Max. ungelesene Nachrichten: \(values.ovUnread)",
                                    value: $values.ovUnread, in: 1...50)
                                .font(.callout)
                            Stepper("Max. offene Hausaufgaben: \(values.ovHomework)",
                                    value: $values.ovHomework, in: 1...50)
                                .font(.callout)
                        }
                    }

                    SectionLabel(text: "Wetter")
                    EduCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Toggle("Wetterkarte auf der Übersicht", isOn: $values.ovWetter)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Color.rInk)
                            TextField("Stadt (leer = manuell eingeben)", text: $values.wetterCity)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                    PrimaryButton(text: "Speichern") { Task { await save() } }
                        .disabled(isLoading)
                    if let notice {
                        Text(notice)
                            .font(.footnote)
                            .foregroundStyle(Color.rMuted)
                    }
                    if let error {
                        AuthAwareError(error: error,
                                       onReLogin: { Task { await logout() } },
                                       onDismiss: { self.error = nil })
                    }

                    SectionLabel(text: "Server")
                    EduCard {
                        VStack(alignment: .leading, spacing: 10) {
                            TextField("Basis-URL (…/api/v1/)", text: $baseURL)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .textFieldStyle(.roundedBorder)
                            Button("Übernehmen (ohne Rebuild)") {
                                store.setBaseURL(baseURL.isEmpty
                                    ? TokenStore.defaultBaseURL : baseURL)
                                baseURL = store.baseURL
                                notice = "Server-URL übernommen."
                            }
                            .font(.callout)
                            Button("Cache leeren") { Task { await clearCache() } }
                                .font(.callout)
                                .disabled(isLoading)
                        }
                    }

                    SectionLabel(text: "Konto & Sicherheit")
                    EduCard {
                        VStack(alignment: .leading, spacing: 4) {
                            NavigationLink {
                                DevicesView(client: client).environmentObject(store)
                            } label: {
                                SettingsNavRow(
                                    title: "Verbundene Geräte",
                                    subtitle: "\(devicesCount) \(devicesCount == 1 ? "Gerät" : "Geräte")")
                            }
                            .buttonStyle(.plain)
                            Button {
                                showPrivacy = true
                            } label: {
                                SettingsNavRow(title: "Datenschutz",
                                               subtitle: "Sitzungen verwalten")
                            }
                            .buttonStyle(.plain)
                            Button(role: .destructive) { Task { await logout() } } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Abmelden")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(.red)
                                    Text("Von EduFlow abmelden")
                                        .font(RFont.cardSub)
                                        .foregroundStyle(Color.rMuted)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(16)
            }
            .background(Color.rBackground)
            .navigationTitle("Einstellungen")
            .task {
                baseURL = store.baseURL
                await load()
                await loadDevicesCount()
            }
            .alert("Datenschutz", isPresented: $showPrivacy) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Deine Zugangsdaten bleiben auf diesem Gerät. Auf dem Server " +
                    "landen nur kurzzeitige Caches und widerrufbare Tokens — " +
                    "kein Tracking, keine Weitergabe an Dritte.")
            }
        }
    }

    private func load() async {
        isLoading = true
        self.error = nil
        do {
            values = try await service().load().1
        } catch let e as APIError {
            self.error = e
        } catch {
            self.error = APIError(code: "UPSTREAM", message: APIError.message(for: "UPSTREAM"), httpStatus: 0)
        }
        isLoading = false
    }

    private func loadDevicesCount() async {
        do {
            devicesCount = try await AuthService(client: { client }, store: store).devices().total
        } catch {
            devicesCount = 0
        }
    }

    private func save() async {
        isLoading = true
        self.error = nil
        notice = nil
        do {
            values = try await service().save(values)
            notice = "Einstellungen gespeichert."
        } catch let e as APIError {
            self.error = e
        } catch {
            self.error = APIError(code: "UPSTREAM", message: APIError.message(for: "UPSTREAM"), httpStatus: 0)
        }
        isLoading = false
    }

    private func clearCache() async {
        isLoading = true
        self.error = nil
        notice = nil
        do {
            let res = try await service().clearCache()
            notice = "Cache geleert (\(res.cleared) Dateien)."
        } catch let e as APIError {
            self.error = e
        } catch {
            self.error = APIError(code: "UPSTREAM", message: APIError.message(for: "UPSTREAM"), httpStatus: 0)
        }
        isLoading = false
    }

    private func logout() async {
        await AuthService(client: { client }, store: store).logout()
    }
}

// MARK: - Zeilen (PNG Screen 05)

/// Erscheinungsbild-Zeile: Radio + Titel/Sub (+ System-Pill).
struct AppearanceRow: View {
    let title: String
    let subtitle: String
    let selected: Bool
    var pill: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .stroke(selected ? Color.rPrimary : Color.rMuted, lineWidth: 2)
                        .frame(width: 20, height: 20)
                    if selected {
                        Circle()
                            .fill(Color.rPrimary)
                            .frame(width: 10, height: 10)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.rInk)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Color.rMuted)
                }
                .layoutPriority(1)
                Spacer()
                if selected, let pill {
                    StatusPill(text: pill, dot: Color.rDotBlue)
                }
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }
}

/// Akzent-Dots wie im Web (26pt, aktiver Ring, Schwarz im Dark Mode weiß).
struct AccentDotsRow: View {
    @Environment(\.colorScheme) private var scheme
    let selected: String
    let onSelect: (String) -> Void

    var body: some View {
        HStack(spacing: 12) {
            ForEach(AccentOptions.all, id: \.key) { opt in
                let isSel = opt.key == selected
                Circle()
                    .fill(opt.swatch(dark: scheme == .dark))
                    .frame(width: 26, height: 26)
                    .overlay(
                        Circle()
                            .stroke(isSel ? Color.rInk : Color.rMuted,
                                    lineWidth: isSel ? 2 : 1)
                    )
                    .onTapGesture { onSelect(opt.key) }
                    .accessibilityLabel(opt.label)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Navigations-Zeile (Titel + Untertitel, Chevron rechts).
struct SettingsNavRow: View {    let title: String
    let subtitle: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.rInk)
                Text(subtitle)
                    .font(RFont.cardSub)
                    .foregroundStyle(Color.rMuted)
            }
            .layoutPriority(1)
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(Color.rMuted)
        }
        .padding(.vertical, 8)
    }
}
