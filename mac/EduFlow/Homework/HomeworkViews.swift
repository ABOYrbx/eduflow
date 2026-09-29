import SwiftUI

/// Hausaufgaben wie `/hausaufgaben`: Seitenkopf, Filter-Karte,
/// Statistik-Karten und Karten mit 6px Status-Kante (`.hw.st-*`).
public struct HomeworkView: View {
    @Environment(\.colorScheme) private var scheme
    @State private var vm: HomeworkViewModel
    private let onSessionExpired: () -> Void

    public init(store: TokenStore, onSessionExpired: @escaping () -> Void) {
        _vm = State(initialValue: HomeworkViewModel(store: store))
        self.onSessionExpired = onSessionExpired
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                PageHead(
                    "Hausaufgaben",
                    stats: vm.total == 0 ? nil : String(format: NSLocalizedString("homework_count", value: "%d Aufgaben", comment: "Hausaufgaben: Anzahl"), vm.total)
                )
                controlsCard
                statGrid
                if let error = vm.error, vm.items.isEmpty {
                    ErrorView(message: error.message) {
                        Task { await vm.load(onSessionExpired: onSessionExpired) }
                    }
                } else if vm.isLoading && vm.items.isEmpty {
                    ProgressView()
                        .controlSize(.large)
                        .frame(maxWidth: .infinity)
                        .padding(48)
                } else if vm.items.isEmpty {
                    Text("Keine Hausaufgaben.")
                        .font(UberFont.text(15))
                        .foregroundStyle(EduFlowPalette.inkMuted(scheme))
                        .frame(maxWidth: .infinity)
                        .padding(48)
                } else {
                    ForEach(Array(vm.items.enumerated()), id: \.element.id) { index, item in
                        HomeworkCard(status: item.status, isDone: item.isDone, isHidden: item.isHidden) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(item.title)
                                    .font(UberFont.text(17, weight: .heavy))
                                    .tracking(-0.3)
                                    .strikethrough(item.isHidden)
                                HStack(spacing: 8) {
                                    Tag(item.status, style: statusTag(item.status))
                                    if item.isHidden {
                                        Tag(NSLocalizedString("Gelöscht", value: "Gelöscht", comment: "Hausaufgaben: gelöscht"), style: .muted)
                                    }
                                    (Text("fällig: ")
                                        + Text(item.dueDisplay).bold())
                                        .font(UberFont.text(13))
                                    if !item.subject.isEmpty {
                                        Text(item.subject)
                                            .font(UberFont.text(13))
                                            .foregroundStyle(EduFlowPalette.inkMuted(scheme))
                                    }
                                    Text(item.author)
                                        .font(UberFont.text(13))
                                        .foregroundStyle(EduFlowPalette.inkMuted(scheme))
                                }
                                (item.description.isEmpty ? Text("(keine Beschreibung)") : Text(verbatim: item.description))
                                    .font(UberFont.text(15))
                                    .lineSpacing(4)
                                HStack(spacing: 8) {
                                    Button(item.isDone ? NSLocalizedString("Wieder öffnen", value: "Wieder öffnen", comment: "Hausaufgaben: wieder öffnen") : NSLocalizedString("Fertig", value: "Fertig", comment: "Hausaufgaben: fertig")) {
                                        Task { await vm.toggleDone(item, onSessionExpired: onSessionExpired) }
                                    }
                                    .buttonStyle(UberButtonStyle(.smallPrimary))
                                    .hoverLift()
                                    Button(item.isHidden ? NSLocalizedString("Zurückholen", value: "Zurückholen", comment: "Hausaufgaben: zurückholen") : NSLocalizedString("Papierkorb", value: "Papierkorb", comment: "Hausaufgaben: Papierkorb")) {
                                        Task { await vm.toggleTrash(item, onSessionExpired: onSessionExpired) }
                                    }
                                    .buttonStyle(UberButtonStyle(.smallLight))
                                    .hoverLift()
                                }
                                .padding(.top, 4)
                            }
                        }
                        .contextMenu {
                            Button(item.isDone ? NSLocalizedString("Wieder öffnen", value: "Wieder öffnen", comment: "Hausaufgaben: wieder öffnen") : NSLocalizedString("Als erledigt markieren", value: "Als erledigt markieren", comment: "Hausaufgaben: als erledigt markieren")) {
                                Task { await vm.toggleDone(item, onSessionExpired: onSessionExpired) }
                            }
                            Button(item.isHidden ? NSLocalizedString("Zurückholen (als offen)", value: "Zurückholen (als offen)", comment: "Hausaufgaben: zurückholen") : NSLocalizedString("In den Papierkorb", value: "In den Papierkorb", comment: "Hausaufgaben: in den Papierkorb")) {
                                Task { await vm.toggleTrash(item, onSessionExpired: onSessionExpired) }
                            }
                        }
                        .riseIn(delay: Double(min(index, 8)) * 0.06)
                    }
                    if vm.canLoadMore {
                        Button(vm.isLoadingMore ? NSLocalizedString("Lädt …", value: "Lädt …", comment: "Hausaufgaben: lädt") : String(format: NSLocalizedString("grades_load_more", value: "Mehr laden (%d/%d)", comment: "Hausaufgaben: mehr laden"), vm.items.count, vm.total)) {
                            Task { await vm.loadMore(onSessionExpired: onSessionExpired) }
                        }
                        .buttonStyle(UberButtonStyle(.smallLight))
                        .hoverLift()
                        .disabled(vm.isLoadingMore)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                }
                if let info = vm.cacheInfo, !info.isEmpty {
                    Text(info)
                        .font(UberFont.text(12))
                        .foregroundStyle(EduFlowPalette.inkDim(scheme))
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(20)
            .frame(maxWidth: 1000)
            .frame(maxWidth: .infinity)
        }
        .background(EduFlowPalette.canvas(scheme))
        .navigationTitle(NSLocalizedString("Hausaufgaben", value: "Hausaufgaben", comment: "Hausaufgaben: Titel"))
        .task { await vm.load(onSessionExpired: onSessionExpired) }
        .refreshable { await vm.load(refresh: true, onSessionExpired: onSessionExpired) }
    }

    /// Filter-Karte (`.controls`).
    private var controlsCard: some View {
        UberCard {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Status")
                        .font(UberFont.text(12, weight: .bold))
                        .foregroundStyle(EduFlowPalette.inkMuted(scheme))
                    Picker(NSLocalizedString("Status", value: "Status", comment: "Hausaufgaben: Statusfilter"), selection: $vm.status) {
                        ForEach(HomeworkStatusFilter.all, id: \.self) { status in
                            Text(HomeworkStatusFilter.displayName(status)).tag(status)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 200)
                    .onChange(of: vm.status) {
                        Task { await vm.load(onSessionExpired: onSessionExpired) }
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Suche")
                        .font(UberFont.text(12, weight: .bold))
                        .foregroundStyle(EduFlowPalette.inkMuted(scheme))
                    TextField(NSLocalizedString("grades_search_placeholder", value: "Suchen", comment: "Hausaufgaben: Suche Platzhalter"), text: $vm.query)
                        .uberInput()
                        .autocorrectionDisabled()
                        .onSubmit {
                            Task { await vm.load(onSessionExpired: onSessionExpired) }
                        }
                }
                Toggle(NSLocalizedString("homework_toggle_tests", value: "Tests einbeziehen", comment: "Hausaufgaben: Tests einbeziehen"), isOn: $vm.includeTests)
                    .font(UberFont.text(14, weight: .medium))
                    .onChange(of: vm.includeTests) {
                        Task { await vm.load(onSessionExpired: onSessionExpired) }
                    }
            }
        }
    }

    /// Vier Kennzahlen (`.stat-grid`).
    private var statGrid: some View {
        HStack(spacing: 14) {
            StatCard("\(vm.counts.offen)", label: "Offen")
            StatCard("\(vm.counts.ueberfaellig)", label: "Überfällig", tone: .danger)
            StatCard("\(vm.counts.erledigt)", label: "Erledigt", tone: .ok)
            StatCard("\(vm.counts.papierkorb)", label: "Papierkorb")
        }
    }

    private func statusTag(_ status: String) -> TagStyle {
        switch status {
        case HomeworkItemStatus.ueberfaellig: return .red
        case HomeworkItemStatus.heute: return .amber
        case HomeworkItemStatus.offen: return .blue
        case HomeworkItemStatus.erledigt: return .green
        default: return .gray
        }
    }
}
