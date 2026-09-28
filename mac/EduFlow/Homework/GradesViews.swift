import SwiftUI

/// Noten im EduPage-Stil wie `/noten`: Halbjahr-Tabs, Fächer mit Chips,
/// Schnitt rechts, aufklappbare Detailtabelle.
public struct GradesView: View {
    @Environment(\.colorScheme) private var scheme
    @State private var vm: GradesViewModel
    private let onSessionExpired: () -> Void

    public init(store: TokenStore, onSessionExpired: @escaping () -> Void) {
        _vm = State(initialValue: GradesViewModel(store: store))
        self.onSessionExpired = onSessionExpired
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                PageHead(
                    "Noten",
                    stats: String(format: NSLocalizedString("grades_average_stats", value: "Schnitt: %@", comment: "Noten: Schnitt"), GradesAverage.display(vm.tabAverage))
                )
                toolsBar
                if let error = vm.error, vm.items.isEmpty {
                    ErrorView(message: error.message) {
                        Task { await vm.load(onSessionExpired: onSessionExpired) }
                    }
                } else if vm.isLoading && vm.items.isEmpty {
                    ProgressView()
                        .controlSize(.large)
                        .frame(maxWidth: .infinity)
                        .padding(48)
                } else if vm.visible.isEmpty {
                    Text("Keine Noten.")
                        .font(UberFont.text(15))
                        .foregroundStyle(EduFlowPalette.inkMuted(scheme))
                        .frame(maxWidth: .infinity)
                        .padding(48)
                } else {
                    ForEach(Array(vm.visible.enumerated()), id: \.offset) { index, group in
                        subjectCard(group)
                            .riseIn(delay: Double(min(index, 8)) * 0.06)
                    }
                    if vm.canLoadMore {
                        Button(vm.isLoadingMore ? NSLocalizedString("Lädt …", value: "Lädt …", comment: "Noten: lädt") : String(format: NSLocalizedString("grades_load_more", value: "Mehr laden (%d/%d)", comment: "Noten: mehr laden"), vm.items.count, vm.total)) {
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
        .navigationTitle(NSLocalizedString("grades_nav", value: "Noten", comment: "Noten: Titel"))
        .task { await vm.load(onSessionExpired: onSessionExpired) }
        .refreshable { await vm.load(refresh: true, onSessionExpired: onSessionExpired) }
    }

    /// Werkzeugleiste (`.grades-bar`): Tabs, Suche.
    private var toolsBar: some View {
        HStack(spacing: 10) {
            Picker(NSLocalizedString("grades_picker_halfyear", value: "Halbjahr", comment: "Noten: Halbjahrfilter"), selection: $vm.tab) {
                ForEach(vm.tabs, id: \.self) { tab in
                    Text(tab.label).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            TextField(NSLocalizedString("grades_search_placeholder", value: "Suchen", comment: "Noten: Suche Platzhalter"), text: $vm.search)
                .uberInput()
                .frame(minWidth: 180, maxWidth: 260)
                .autocorrectionDisabled()
            Spacer()
        }
    }

    /// Fach-Karte (`.subj`): Kopf mit Titel, Anzahl und großem Schnitt,
    /// darunter Noten-Chips und aufklappbare Tabelle.
    private func subjectCard(_ group: (subject: String, grades: [GradeDTO], average: Double?)) -> some View {
        UberCard {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(group.subject)
                            .font(UberFont.text(18, weight: .heavy))
                            .tracking(-0.3)
                        Text(String(format: NSLocalizedString("grades_subject_count", value: "%d Noten", comment: "Noten: Fachanzahl"), group.grades.count))
                            .font(UberFont.text(13))
                            .foregroundStyle(EduFlowPalette.inkMuted(scheme))
                    }
                    Spacer()
                    Text(GradesAverage.display(group.average))
                        .font(UberFont.text(26, weight: .heavy))
                        .tracking(-0.8)
                        .monospacedDigit()
                        .foregroundStyle(group.average == nil ? EduFlowPalette.inkDim(scheme) : EduFlowPalette.ink(scheme))
                }
                HStack(spacing: 8) {
                    ForEach(group.grades, id: \.uid) { grade in
                        GradeChip(grade: grade)
                    }
                }
                .padding(.top, 10)
                DisclosureGroup("Details") {
                    GradeTable(grades: group.grades)
                        .padding(.top, 10)
                }
                .font(UberFont.text(13, weight: .semibold))
                .tint(EduFlowPalette.inkMuted(scheme))
            }
        }
    }
}

/// Noten-Chip (`.chip`): farbig nach Badge (g12 grün, g3 blau,
/// g4 orange, g56 rot, gx grau), Datum darunter.
private struct GradeChip: View {
    let grade: GradeDTO

    var body: some View {
        VStack(spacing: 1) {
            Text(verbatim: grade.gradeDisplay ?? "–")
                .font(UberFont.text(16, weight: .heavy))
                .monospacedDigit()
            Text(verbatim: shortDate(grade.dateDisplay))
                .font(UberFont.text(10, weight: .bold))
                .opacity(0.85)
        }
        .foregroundStyle(.white)
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .frame(minWidth: 46)
        .background(chipColor)
        .clipShape(.rect(cornerRadius: 10))
    }

    private var chipColor: Color {
        switch grade.badge {
        case "g12": return EduFlowPalette.green
        case "g3": return EduFlowPalette.blue
        case "g4": return EduFlowPalette.amber
        case "g56": return EduFlowPalette.red
        default: return Color(red: 0x6B / 255, green: 0x6B / 255, blue: 0x6B / 255)
        }
    }

    private func shortDate(_ display: String?) -> String {
        let parts = (display ?? "").split(separator: ".")
        guard parts.count >= 2 else { return display ?? "" }
        return "\(parts[0]).\(parts[1])."
    }
}

/// Detailtabelle (`.g-table`): Titel, Note, Datum, Zusatz, Schnitt.
private struct GradeTable: View {
    @Environment(\.colorScheme) var scheme
    let grades: [GradeDTO]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Titel")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Note").frame(width: 60)
                Text("Datum").frame(width: 90)
                Text("Zusatz").frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(UberFont.text(11, weight: .bold))
            .tracking(0.6)
            .foregroundStyle(EduFlowPalette.inkMuted(scheme))
            .textCase(.uppercase)
            .padding(.vertical, 8)
            Divider()
            ForEach(grades, id: \.uid) { grade in
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        (grade.title == nil ? Text("Note") : Text(verbatim: grade.title!))
                            .font(UberFont.text(13, weight: .semibold))
                        if let teacher = grade.teacher, !teacher.isEmpty {
                            Text(teacher)
                                .font(UberFont.text(12))
                                .foregroundStyle(EduFlowPalette.inkMuted(scheme))
                        }
                        if let comment = grade.comment, !comment.isEmpty {
                            Text(comment)
                                .font(UberFont.text(12))
                                .foregroundStyle(EduFlowPalette.inkMuted(scheme))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Text(verbatim: grade.gradeDisplay ?? "–")
                        .font(UberFont.text(13, weight: .bold))
                        .frame(width: 60)
                    Text(verbatim: grade.dateDisplay ?? "–")
                        .font(UberFont.text(12))
                        .foregroundStyle(EduFlowPalette.inkMuted(scheme))
                        .frame(width: 90)
                    Text(verbatim: grade.gradeSub ?? "")
                        .font(UberFont.text(12))
                        .foregroundStyle(EduFlowPalette.inkMuted(scheme))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 8)
                Divider()
            }
        }
    }
}
