import SwiftUI

/// Hausaufgaben-Karte mit integriertem Statusstreifen (dateilokal, keine
/// gemeinsame API): 6px-Kante links *innerhalb* des Kartenrechtecks —
/// derselbe 14px-Radius, 1px-Rahmen und 20/22-Innenabstand wie `UberCard`,
/// erledigt blass, Papierkorb gestrichelt mit durchgestrichenem Titel.
/// (Abgleich mit Agent 1: wandert bei Gelegenheit in `HomeworkCard`.)
fileprivate struct HomeworkStatusCard<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    let status: String
    let isDone: Bool
    let isHidden: Bool
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 0) {
            EduFlowPalette.homeworkEdge(status, scheme: scheme)
                .frame(width: 6)
            content
                .padding(.vertical, 20)
                .padding(.horizontal, 22)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(EduFlowPalette.card(scheme))
        .clipShape(.rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(
                    EduFlowPalette.border(scheme),
                    style: StrokeStyle(lineWidth: 1, dash: isHidden ? [6, 4] : [])
                )
        }
        .opacity(isDone ? 0.65 : (isHidden ? 0.55 : 1))
    }
}

/// Schalter-Zeile im Uber-Stil (dateilokal, keine gemeinsame API):
/// Akzent-Kreis mit Haken statt nativem macOS-Toggle.
fileprivate struct CheckRow: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.uberAccent) private var accent
    @Binding var isOn: Bool
    let titleKey: String

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isOn ? accent.resolved(scheme) : EduFlowPalette.inkMuted(scheme))
                Text(LocalizedStringKey(titleKey))
                    .font(UberFont.text(14, weight: .medium))
                    .foregroundStyle(EduFlowPalette.ink(scheme))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isToggle)
        .accessibilityLabel(Text(LocalizedStringKey(titleKey)))
        .accessibilityValue(Text(isOn
            ? NSLocalizedString("common_toggle_on", value: "On", comment: "Schalter: ein")
            : NSLocalizedString("common_toggle_off", value: "Off", comment: "Schalter: aus")))
    }
}

/// Hausaufgaben wie `/hausaufgaben`: Seitenkopf, Filter-Karte,
/// Statistik-Karten und Karten mit integrierter Status-Kante (`.hw.st-*`).
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
                    "Homework",
                    stats: vm.total == 0 ? nil : String(format: NSLocalizedString("homework_count", value: "%d homework", comment: "Hausaufgaben: Anzahl"), vm.total)
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
                    Text(verbatim: emptyText)
                        .font(UberFont.text(15))
                        .foregroundStyle(EduFlowPalette.inkMuted(scheme))
                        .frame(maxWidth: .infinity)
                        .padding(48)
                } else {
                    ForEach(Array(vm.items.enumerated()), id: \.element.id) { index, item in
                        HomeworkStatusCard(status: item.status, isDone: item.isDone, isHidden: item.isHidden) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(item.title)
                                    .font(UberFont.text(17, weight: .heavy))
                                    .tracking(-0.3)
                                    .strikethrough(item.isHidden)
                                HStack(spacing: 8) {
                                    Tag(item.status, style: statusTag(item.status))
                                    if item.isHidden {
                                        Tag(NSLocalizedString("homework_deleted", value: "Deleted", comment: "Hausaufgaben: gelöscht-Tag"), style: .muted)
                                    }
                                    (Text(NSLocalizedString("homework_due_prefix", value: "due: ", comment: "Hausaufgaben: fällig-Präfix"))
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
                                (item.description.isEmpty ? Text(NSLocalizedString("homework_no_description", value: "(no description)", comment: "Hausaufgaben: keine Beschreibung")) : Text(verbatim: item.description))
                                    .font(UberFont.text(15))
                                    .lineSpacing(4)
                                HStack(spacing: 8) {
                                    PillButton(item.isDone ? NSLocalizedString("homework_action_reopen", value: "Reopen", comment: "Hausaufgaben: wieder öffnen") : NSLocalizedString("homework_action_done", value: "Done", comment: "Hausaufgaben: fertig"), style: .smallPrimary) {
                                        Task { await vm.toggleDone(item, onSessionExpired: onSessionExpired) }
                                    }
                                    PillButton(item.isHidden ? NSLocalizedString("homework_action_restore", value: "Restore", comment: "Hausaufgaben: zurückholen") : NSLocalizedString("homework_action_trash", value: "Trash", comment: "Hausaufgaben: Papierkorb"), style: .smallLight) {
                                        Task { await vm.toggleTrash(item, onSessionExpired: onSessionExpired) }
                                    }
                                }
                                .padding(.top, 4)
                            }
                        }
                        .contextMenu {
                            Button(item.isDone ? NSLocalizedString("homework_action_reopen", value: "Reopen", comment: "Hausaufgaben: wieder öffnen") : NSLocalizedString("homework_menu_done", value: "Mark as done", comment: "Hausaufgaben: als erledigt markieren")) {
                                Task { await vm.toggleDone(item, onSessionExpired: onSessionExpired) }
                            }
                            Button(item.isHidden ? NSLocalizedString("homework_menu_restore", value: "Restore (as open)", comment: "Hausaufgaben: zurückholen als offen") : NSLocalizedString("homework_menu_trash", value: "Move to trash", comment: "Hausaufgaben: in den Papierkorb")) {
                                Task { await vm.toggleTrash(item, onSessionExpired: onSessionExpired) }
                            }
                        }
                        .riseIn(delay: Double(min(index, 8)) * 0.06)
                    }
                    if vm.canLoadMore {
                        PillButton(vm.isLoadingMore ? NSLocalizedString("common_loading", value: "Loading …", comment: "Laden läuft") : String(format: NSLocalizedString("homework_load_more", value: "Load more (%d/%d)", comment: "Hausaufgaben: mehr laden"), vm.items.count, vm.total), style: .smallLight) {
                            Task { await vm.loadMore(onSessionExpired: onSessionExpired) }
                        }
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
        .navigationTitle(NSLocalizedString("Homework", value: "Homework", comment: "Hausaufgaben: Titel"))
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
                    Text("Search")
                        .font(UberFont.text(12, weight: .bold))
                        .foregroundStyle(EduFlowPalette.inkMuted(scheme))
                    TextField(NSLocalizedString("grades_search_placeholder", value: "Search", comment: "Hausaufgaben: Suche Platzhalter"), text: $vm.query)
                        .uberInput()
                        .autocorrectionDisabled()
                        .onSubmit {
                            Task { await vm.load(onSessionExpired: onSessionExpired) }
                        }
                }
                CheckRow(isOn: $vm.includeTests, titleKey: "homework_toggle_tests")
                    .onChange(of: vm.includeTests) {
                        Task { await vm.load(onSessionExpired: onSessionExpired) }
                    }
            }
        }
    }

    /// Vier Kennzahlen (`.stat-grid`).
    private var statGrid: some View {
        HStack(spacing: 14) {
            StatCard("\(vm.counts.offen)", label: "Open")
            StatCard("\(vm.counts.ueberfaellig)", label: "Overdue", tone: .danger)
            StatCard("\(vm.counts.erledigt)", label: "Completed", tone: .ok)
            StatCard("\(vm.counts.papierkorb)", label: "Trash")
        }
    }

    /// Leertext je Filter: leerer, erledigter und gemischter Bestand sowie
    /// Papierkorb bekommen je eine passende Aussage (Zähler stehen darüber).
    private var emptyText: String {
        switch vm.status {
        case HomeworkStatusFilter.offen:
            return NSLocalizedString("homework_empty_open", value: "No open tasks.", comment: "Hausaufgaben: keine offenen")
        case HomeworkStatusFilter.ueberfaellig:
            return NSLocalizedString("homework_empty_overdue", value: "Nothing overdue.", comment: "Hausaufgaben: nichts überfällig")
        case HomeworkStatusFilter.erledigt:
            return NSLocalizedString("homework_empty_done", value: "Nothing completed yet.", comment: "Hausaufgaben: nichts erledigt")
        case HomeworkStatusFilter.papierkorb:
            return NSLocalizedString("homework_empty_trash", value: "The trash is empty.", comment: "Hausaufgaben: Papierkorb leer")
        default:
            return NSLocalizedString("homework_empty_all", value: "No homework.", comment: "Hausaufgaben: leer")
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
