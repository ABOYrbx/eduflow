import SwiftUI

/// Einstellungen wie `/einstellungen`: Karten-Abschnitte mit Titel,
/// Radio-Cards für Startseite und Filter, Schalter, Stufen, Akzent-Dots,
/// Server-URL, Cache und Abmelden (nie Sackgasse).
public struct SettingsView: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(TokenStore.self) private var store
    @State private var vm: SettingsViewModel
    @State private var accent = Accent.stored
    @State private var topBarOrder: [TopBarSection] = TopBarConfig.visible
    @AppStorage("de.eduflow.developerOptionsEnabledV1") private var developerOptionsEnabled = false
    private let onSessionExpired: () -> Void
    private let onDevices: () -> Void
    private let onLogout: () -> Void

    public init(
        store: TokenStore,
        onSessionExpired: @escaping () -> Void,
        onDevices: @escaping () -> Void,
        onLogout: @escaping () -> Void
    ) {
        _vm = State(initialValue: SettingsViewModel(store: store))
        self.onSessionExpired = onSessionExpired
        self.onDevices = onDevices
        self.onLogout = onLogout
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                PageHead("Settings")
                if vm.isLoading && vm.error == nil {
                    ProgressView()
                        .controlSize(.large)
                        .frame(maxWidth: .infinity)
                        .padding(48)
                } else {
                    startSection
                    navigationSection
                    homeworkSection
                    overviewSection
                    appearanceSection
                    serverSection
                    developerSection
                    if let error = vm.error {
                        Notice(error.message)
                    }
                    if let message = vm.clearMessage {
                        Text(message)
                            .font(UberFont.text(13))
                            .foregroundStyle(EduFlowPalette.inkMuted(scheme))
                    }
                    actionsSection
                }
            }
            .padding(20)
            .frame(maxWidth: 800)
            .frame(maxWidth: .infinity)
        }
        .background(EduFlowPalette.canvas(scheme))
        .navigationTitle(NSLocalizedString("settings_nav", value: "Settings", comment: "Einstellungen: Titel"))
        .task { await vm.load(onSessionExpired: onSessionExpired) }
    }

    // MARK: - Abschnitte

    private var startSection: some View {
        UberCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Start page after sign-in")
                    .font(UberFont.text(19, weight: .heavy))
                    .tracking(-0.4)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    RadioCard(title: NSLocalizedString("Overview", value: "Overview", comment: "Einstellungen: Startseite Übersicht"), desc: NSLocalizedString("settings_landing_overview_desc", value: "Clock, messages, weather", comment: "Einstellungen: Startseite Übersicht Beschreibung"), value: "uebersicht", selection: $vm.values.landing)
                    RadioCard(title: NSLocalizedString("messages_nav_list", value: "Messages", comment: "Einstellungen: Startseite Nachrichten"), desc: NSLocalizedString("settings_landing_messages_desc", value: "Go straight to messages", comment: "Einstellungen: Startseite Nachrichten Beschreibung"), value: "dashboard", selection: $vm.values.landing)
                    RadioCard(title: NSLocalizedString("Homework", value: "Homework", comment: "Einstellungen: Startseite Aufgaben"), desc: NSLocalizedString("settings_landing_homework_desc", value: "Go straight to homework", comment: "Einstellungen: Startseite Aufgaben Beschreibung"), value: "hausaufgaben", selection: $vm.values.landing)
                    RadioCard(title: NSLocalizedString("grades_nav", value: "Grades", comment: "Einstellungen: Startseite Noten"), desc: NSLocalizedString("settings_landing_grades_desc", value: "Go straight to grades", comment: "Einstellungen: Startseite Noten Beschreibung"), value: "noten", selection: $vm.values.landing)
                    RadioCard(title: NSLocalizedString("Timetable", value: "Timetable", comment: "Einstellungen: Startseite Stundenplan"), desc: NSLocalizedString("settings_landing_timetable_desc", value: "Go straight to timetable", comment: "Einstellungen: Startseite Stundenplan Beschreibung"), value: "stundenplan", selection: $vm.values.landing)
                }
            }
        }
    }

    private var navigationSection: some View {
        UberCard {
            VStack(alignment: .leading, spacing: 10) {
                Text(NSLocalizedString("settings_navbar_title", value: "Navigation bar", comment: "Einstellungen: Navigationsleiste Titel"))
                    .font(UberFont.text(19, weight: .heavy))
                    .tracking(-0.4)
                Text(NSLocalizedString("settings_navbar_desc", value: "Choose which sections appear on top and in which order. Events stay reachable via the profile menu even without a tab.", comment: "Einstellungen: Navigationsleiste Beschreibung"))
                    .font(UberFont.text(13))
                    .foregroundStyle(EduFlowPalette.inkMuted(scheme))
                ForEach(Array(topBarOrder.enumerated()), id: \.element.id) { index, section in
                    HStack(spacing: 4) {
                        Text(LocalizedStringKey(section.title))
                            .font(UberFont.text(14, weight: .semibold))
                        Spacer()
                        IconButton(icon: "chevron.up", label: "Move up", help: "Move section up", disabled: index == 0) {
                            topBarOrder = TopBarConfig.move(topBarOrder, from: index, by: -1)
                            TopBarConfig.save(topBarOrder)
                        }
                        IconButton(icon: "chevron.down", label: "Move down", help: "Move section down", disabled: index == topBarOrder.count - 1) {
                            topBarOrder = TopBarConfig.move(topBarOrder, from: index, by: 1)
                            TopBarConfig.save(topBarOrder)
                        }
                        IconButton(icon: "minus", label: "Remove", help: "Remove section from the bar") {
                            topBarOrder = topBarOrder.filter { $0 != section }
                            TopBarConfig.save(topBarOrder)
                        }
                    }
                    .padding(.vertical, 4)
                }
                let hidden = TopBarSection.allCases.filter { !topBarOrder.contains($0) }
                if !hidden.isEmpty {
                    Text(NSLocalizedString("settings_navbar_available", value: "Available", comment: "Einstellungen: verfügbare Bereiche"))
                        .font(UberFont.text(13, weight: .bold))
                        .tracking(0.8)
                        .textCase(.uppercase)
                        .foregroundStyle(EduFlowPalette.inkMuted(scheme))
                        .padding(.top, 4)
                    ForEach(hidden) { section in
                        HStack(spacing: 4) {
                            Text(LocalizedStringKey(section.title))
                                .font(UberFont.text(14, weight: .semibold))
                                .foregroundStyle(EduFlowPalette.inkMuted(scheme))
                            Spacer()
                            IconButton(icon: "plus", label: "Add", help: "Add section to the bar") {
                                topBarOrder = topBarOrder + [section]
                                TopBarConfig.save(topBarOrder)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }

    private var homeworkSection: some View {
        UberCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Homework")
                    .font(UberFont.text(19, weight: .heavy))
                    .tracking(-0.4)
                Text("Default filter")
                    .font(UberFont.text(13, weight: .bold))
                    .tracking(0.8)
                    .textCase(.uppercase)
                    .foregroundStyle(EduFlowPalette.inkMuted(scheme))
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    RadioCard(title: NSLocalizedString("homework_filter_all", value: "All", comment: "Einstellungen: Filter alle"), desc: NSLocalizedString("settings_filter_all_desc", value: "Show everything", comment: "Einstellungen: Filter alle Beschreibung"), value: "alle", selection: $vm.values.hwStatus)
                    RadioCard(title: NSLocalizedString("settings_filter_open_title", value: "Only open", comment: "Einstellungen: Filter offene"), desc: NSLocalizedString("settings_filter_open_desc", value: "Without done", comment: "Einstellungen: Filter offene Beschreibung"), value: "offen", selection: $vm.values.hwStatus)
                    RadioCard(title: NSLocalizedString("settings_filter_overdue_title", value: "Only past due", comment: "Einstellungen: Filter überfällige"), desc: NSLocalizedString("settings_filter_overdue_desc", value: "Past due", comment: "Einstellungen: Filter überfällige Beschreibung"), value: "überfällig", selection: $vm.values.hwStatus)
                    RadioCard(title: NSLocalizedString("settings_filter_done_title", value: "Only completed", comment: "Einstellungen: Filter erledigte"), desc: NSLocalizedString("settings_filter_done_desc", value: "Completed tasks", comment: "Einstellungen: Filter erledigte Beschreibung"), value: "erledigt", selection: $vm.values.hwStatus)
                    RadioCard(title: NSLocalizedString("homework_filter_trash", value: "Recycle bin", comment: "Einstellungen: Filter Papierkorb"), desc: NSLocalizedString("settings_filter_trash_desc", value: "Hidden", comment: "Einstellungen: Filter Papierkorb Beschreibung"), value: "papierkorb", selection: $vm.values.hwStatus)
                }
                Toggle(NSLocalizedString("settings_toggle_hw_tests", value: "Include tests and exams", comment: "Einstellungen: Tests einbeziehen"), isOn: $vm.values.hwTests)
                    .font(UberFont.text(14, weight: .medium))
                    .tint(accent.resolved(scheme))
            }
        }
    }

    private var overviewSection: some View {
        UberCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Overview")
                    .font(UberFont.text(19, weight: .heavy))
                    .tracking(-0.4)
                Stepper(String(format: NSLocalizedString("settings_max_unread", value: "Max. unread messages: %d", comment: "Einstellungen: ungelesene Nachrichten"), vm.values.ovUnread), value: $vm.values.ovUnread, in: 1...50)
                    .font(UberFont.text(14, weight: .medium))
                Stepper(String(format: NSLocalizedString("settings_max_homework", value: "Max. open homework: %d", comment: "Einstellungen: offene Hausaufgaben"), vm.values.ovHomework), value: $vm.values.ovHomework, in: 1...50)
                    .font(UberFont.text(14, weight: .medium))
                Toggle(NSLocalizedString("settings_toggle_wetter_map", value: "Show weather map", comment: "Einstellungen: Wetterkarte"), isOn: $vm.values.ovWetter)
                    .font(UberFont.text(14, weight: .medium))
                    .tint(accent.resolved(scheme))
                TextField(NSLocalizedString("settings_wetter_city_placeholder", value: "Weather: city (optional)", comment: "Einstellungen: Wetterstadt Platzhalter"), text: $vm.values.wetterCity)
                    .uberInput()
                    .autocorrectionDisabled()
                Text(NSLocalizedString("settings_ov_order_title", value: "Section order", comment: "Einstellungen: Reihenfolge Titel"))
                    .font(UberFont.text(13, weight: .bold))
                    .tracking(0.8)
                    .textCase(.uppercase)
                    .foregroundStyle(EduFlowPalette.inkMuted(scheme))
                    .padding(.top, 4)
                let order = parsedOverviewOrder()
                ForEach(Array(order.enumerated()), id: \.offset) { index, key in
                    HStack(spacing: 4) {
                        Text(LocalizedStringKey(Self.overviewOrderLabels[key] ?? key))
                            .font(UberFont.text(14, weight: .semibold))
                        Spacer()
                        IconButton(icon: "chevron.up", label: "Move up", help: "Move section up", disabled: index == 0) {
                            moveOverviewOrder(from: index, by: -1)
                        }
                        IconButton(icon: "chevron.down", label: "Move down", help: "Move section down", disabled: index == order.count - 1) {
                            moveOverviewOrder(from: index, by: 1)
                        }
                    }
                    .padding(.vertical, 4)
                }
                Text(NSLocalizedString("settings_ov_order_hint", value: "Applied when you save.", comment: "Einstellungen: Reihenfolge Hinweis"))
                    .font(UberFont.text(12))
                    .foregroundStyle(EduFlowPalette.inkMuted(scheme))
            }
        }
    }

    private var appearanceSection: some View {
        UberCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Appearance")
                    .font(UberFont.text(19, weight: .heavy))
                    .tracking(-0.4)
                Text("Light and dark follow the system. Accent color:")
                    .font(UberFont.text(13))
                    .foregroundStyle(EduFlowPalette.inkMuted(scheme))
                HStack(spacing: 12) {
                    ForEach(Accent.allCases) { option in
                        Button {
                            accent = option
                            Accent.stored = option
                        } label: {
                            Circle()
                                .fill(option == .black ? EduFlowPalette.ink(scheme) : option.color)
                                .frame(width: 26, height: 26)
                                .overlay {
                                    Circle().stroke(EduFlowPalette.borderStrong(scheme), lineWidth: 1)
                                }
                                .overlay {
                                    if accent == option {
                                        Circle()
                                            .stroke(EduFlowPalette.ink(scheme), lineWidth: 2)
                                            .padding(-4)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .hoverLift()
                        .help(option.displayName)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var serverSection: some View {
        UberCard {
            VStack(alignment: .leading, spacing: 10) {
                (store.isDemo ? Text("Demo-Modus") : Text("Server"))
                    .font(UberFont.text(19, weight: .heavy))
                    .tracking(-0.4)
                if store.isDemo {
                    Text("Only synthetic sample data is loaded from the local demo server.")
                        .font(UberFont.text(13))
                        .foregroundStyle(EduFlowPalette.inkMuted(scheme))
                } else {
                    TextField(NSLocalizedString("settings_baseurl_placeholder", value: "Base URL", comment: "Einstellungen: Basis-URL Platzhalter"), text: $vm.baseURL)
                        .uberInput()
                        .autocorrectionDisabled()
                    Button(NSLocalizedString("Apply", value: "Apply", comment: "UI-Literal")) { vm.applyBaseURL() }
                        .buttonStyle(UberButtonStyle(.smallLight))
                        .hoverLift()
                }
            }
        }
    }

    /// Reihenfolge der Übersichts-Bereiche (gehört fachlich hierher, nicht in
    /// die Übersicht selbst; gespeichert wird per „Speichern" via `ov_order`).
    private static let overviewOrderLabels = [
        "messages": "Messages",
        "homework": "Homework",
        "weather": "Weather",
    ]
    private static let overviewOrderKeys = ["messages", "homework", "weather"]

    private func parsedOverviewOrder() -> [String] {
        let parsed = vm.values.ovOrder
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { Self.overviewOrderKeys.contains($0) }
        return parsed + Self.overviewOrderKeys.filter { !parsed.contains($0) }
    }

    private func moveOverviewOrder(from: Int, by offset: Int) {
        let order = parsedOverviewOrder()
        guard order.indices.contains(from) else { return }
        let target = min(max(from + offset, 0), order.count - 1)
        guard target != from else { return }
        var result = order
        let item = result.remove(at: from)
        result.insert(item, at: target)
        vm.values.ovOrder = result.joined(separator: ",")
    }

    private var developerSection: some View {
        UberCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Developer options")
                    .font(UberFont.text(19, weight: .heavy))
                    .tracking(-0.4)
                Toggle(NSLocalizedString("settings_toggle_dev_options", value: "Enable developer options", comment: "Einstellungen: Entwickleroptionen"), isOn: $developerOptionsEnabled)
                    .font(UberFont.text(14, weight: .medium))
                    .tint(accent.resolved(scheme))

                if developerOptionsEnabled {
                    Text("Signs you out and restarts the introduction.")
                        .font(UberFont.text(12))
                        .foregroundStyle(EduFlowPalette.inkMuted(scheme))
                    Button(vm.isLoggingOut ? NSLocalizedString("Signing out …", value: "Signing out …", comment: "UI-Literal") : NSLocalizedString("Run onboarding again", value: "Run onboarding again", comment: "UI-Literal")) {
                        guard !vm.isLoggingOut else { return }
                        OnboardingState.reset()
                        Task {
                            await vm.logout()
                            onLogout()
                        }
                    }
                    .buttonStyle(UberButtonStyle(.smallLight))
                    .hoverLift()
                    .disabled(vm.isLoggingOut)
                    .foregroundStyle(EduFlowPalette.red)
                }
            }
        }
    }

    private var actionsSection: some View {
        VStack(spacing: 10) {
            PillButton(vm.isSaving ? NSLocalizedString("Saving …", value: "Saving …", comment: "Einstellungen: Speichern läuft") : NSLocalizedString("Save", value: "Save", comment: "Einstellungen: Speichern")) {
                Task { await vm.save(onSessionExpired: onSessionExpired) }
            }
            .disabled(vm.isSaving || vm.isLoading)
            HStack(spacing: 10) {
                Button(NSLocalizedString("Reload", value: "Reload", comment: "UI-Literal")) {
                    Task { await vm.load(onSessionExpired: onSessionExpired) }
                }
                .buttonStyle(UberButtonStyle(.smallLight))
                .hoverLift()
                .disabled(vm.isLoading)
                Button(vm.isClearing ? NSLocalizedString("settings_cache_clear_busy", value: "Clearing cache …", comment: "Einstellungen: Cache leeren läuft") : NSLocalizedString("settings_cache_clear", value: "Clear cache", comment: "Einstellungen: Cache leeren")) {
                    Task { await vm.clearCache(onSessionExpired: onSessionExpired) }
                }
                .buttonStyle(UberButtonStyle(.smallLight))
                .hoverLift()
                .disabled(vm.isClearing)
                Button(NSLocalizedString("Manage devices", value: "Manage devices", comment: "UI-Literal"), action: onDevices)
                    .buttonStyle(UberButtonStyle(.smallLight))
                    .hoverLift()
            }
            Button(vm.isLoggingOut ? NSLocalizedString("Signing out …", value: "Signing out …", comment: "Einstellungen: Abmelden läuft") : NSLocalizedString("Sign out", value: "Sign out", comment: "Einstellungen: Abmelden")) {
                Task {
                    await vm.logout()
                    onLogout()
                }
            }
            .buttonStyle(UberButtonStyle(.smallLight))
            .hoverLift()
            .disabled(vm.isLoggingOut)
            .foregroundStyle(EduFlowPalette.red)
        }
    }
}

/// Radio-Karte (`.radio-card`): gewählt mit Tinten-Rahmen und Fläche.
private struct RadioCard: View {
    @Environment(\.colorScheme) var scheme
    @State private var hovering = false
    let title: String
    let desc: String
    let value: String
    @Binding var selection: String

    var body: some View {
        Button {
            selection = value
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(UberFont.text(14, weight: .heavy))
                Text(desc)
                    .font(UberFont.text(12))
                    .foregroundStyle(EduFlowPalette.inkMuted(scheme))
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                selection == value ? EduFlowPalette.surface1(scheme)
                    : (hovering ? EduFlowPalette.surface1(scheme) : Color.clear)
            )
            .clipShape(.rect(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        EduFlowPalette.ink(scheme),
                        lineWidth: selection == value ? 2 : 0
                    )
            }
            .overlay {
                if selection != value {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(EduFlowPalette.borderStrong(scheme), lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}
