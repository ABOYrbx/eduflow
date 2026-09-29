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
                    stats: summaryStats
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
                    EmptyView("Keine Noten.")
                        .padding(48)
                } else {
                    ForEach(Array(vm.visible.enumerated()), id: \.offset) { index, group in
                        subjectCard(group)
                            .riseIn(delay: Double(min(index, 8)) * 0.06)
                    }
                    if vm.canLoadMore {
                        Button(vm.isLoadingMore ? "Lädt …" : String(format: NSLocalizedString("grades_load_more", value: "Mehr laden (%d/%d)", comment: "Noten: mehr laden"), vm.items.count, vm.total)) {
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

    /// Kopf-Statistik: Anzahl, Fächer und Schnitt auf einen Blick.
    private var summaryStats: String {
        let gradeCount = vm.visible.reduce(0) { $0 + $1.grades.count }
        let subjectCount = vm.visible.count
        let average = GradesAverage.display(vm.tabAverage)
        return String(
            format: NSLocalizedString(
                "grades_summary_stats",
                value: "%d Noten · %d Fächer · Schnitt: %@",
                comment: "Noten: Zusammenfassung"
            ),
            gradeCount,
            subjectCount,
            average
        )
    }

    /// Werkzeugleiste (`.grades-bar`): Tabs, Suche. Bricht auf schmalen
    /// Fenstern in zwei Zeilen um statt zu quetschen.
    private var toolsBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                halfYearPicker
                searchField
                    .frame(minWidth: 180, maxWidth: 260)
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 8) {
                halfYearPicker
                searchField
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var halfYearPicker: some View {
        Picker(NSLocalizedString("grades_picker_halfyear", value: "Halbjahr", comment: "Noten: Halbjahrfilter"), selection: $vm.tab) {
            ForEach(vm.tabs, id: \.self) { tab in
                Text(tab.label).tag(tab)
            }
        }
        .pickerStyle(.segmented)
    }

    private var searchField: some View {
        TextField(NSLocalizedString("grades_search_placeholder", value: "Suchen", comment: "Noten: Suche Platzhalter"), text: $vm.search)
            .uberInput()
            .autocorrectionDisabled()
    }

    /// Fach-Karte (`.subj`): Kopf mit Titel, Anzahl und großem Schnitt,
    /// darunter Noten-Chips (mit Gewichtung) und aufklappbare Tabelle
    /// mit Datum, Thema, Gewichtung und Klassenvergleich.
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
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(verbatim: "Ø \(GradesAverage.display(group.average))")
                            .font(UberFont.text(26, weight: .heavy))
                            .tracking(-0.8)
                            .monospacedDigit()
                            .foregroundStyle(group.average == nil ? EduFlowPalette.inkDim(scheme) : EduFlowPalette.ink(scheme))
                        Text(NSLocalizedString("grades_subject_average_caption", value: "Fachschn. gewichtet", comment: "Noten: Fachschnitt-Legende"))
                            .font(UberFont.text(11, weight: .semibold))
                            .foregroundStyle(EduFlowPalette.inkMuted(scheme))
                    }
                }
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 64), spacing: 8)],
                    spacing: 8
                ) {
                    ForEach(group.grades, id: \.uid) { grade in
                        GradeChip(grade: grade)
                    }
                }
                .padding(.top, 10)
                DisclosureGroup("Details") {
                    VStack(alignment: .leading, spacing: 8) {
                        GradeTable(grades: group.grades)
                        Text(NSLocalizedString("grades_average_hint", value: "Schnitt aus klassischen Noten, nach Gewichtung.", comment: "Noten: Schnitt-Hinweis"))
                            .font(UberFont.text(11))
                            .foregroundStyle(EduFlowPalette.inkMuted(scheme))
                    }
                    .padding(.top, 10)
                }
                .font(UberFont.text(13, weight: .semibold))
                .tint(EduFlowPalette.inkMuted(scheme))
            }
        }
    }
}

/// Noten-Chip (`.chip`): farbig nach Badge (g12 grün, g3 blau,
/// g4 orange, g56 rot, gx grau), darunter Datum und — falls von ×1
/// abweichend — die Gewichtung wie im Web (`chip > small`).
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
            if let weight = grade.weightDisplay, !weight.isEmpty {
                Text(verbatim: weight)
                    .font(UberFont.text(10, weight: .bold))
                    .opacity(0.85)
            }
        }
        .foregroundStyle(.white)
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .frame(minWidth: 56)
        .background(chipColor)
        .clipShape(.rect(cornerRadius: 10))
        .help(chipHint)
    }

    /// Tooltip wie im Web: Thema · Datum · Gewichtung (lokalisiert).
    private var chipHint: String {
        let topic = (grade.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let date = (grade.dateDisplay ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let weight = (grade.weightDisplay ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackTopic = NSLocalizedString("Note", value: "Note", comment: "UI-Literal")
        let weightOnce = NSLocalizedString("grades_weight_once", value: "Gewichtung ×1", comment: "Noten: Gewichtung einfach")
        let weightFormat = NSLocalizedString("grades_weight_format", value: "Gewichtung %@", comment: "Noten: Gewichtung mit Wert")
        let parts = [
            topic.isEmpty ? fallbackTopic : topic,
            date.isEmpty ? nil : date,
            weight.isEmpty ? weightOnce : String(format: weightFormat, weight),
        ].compactMap { $0 }
        return parts.joined(separator: " · ")
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

/// Detailtabelle (`.g-table`): Thema, Note (mit Zusatz), Datum,
/// Gewichtung und Klassen-Ø — die Vergleichs-Spalten aus dem Web.
/// Scrollt horizontal statt auf schmalen Fenstern zu brechen.
private struct GradeTable: View {
    @Environment(\.colorScheme) var scheme
    let grades: [GradeDTO]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Thema")
                        .frame(minWidth: 140, maxWidth: .infinity, alignment: .leading)
                    Text("Note").frame(width: 76)
                    Text("Datum").frame(width: 92)
                    Text("Gewichtung").frame(width: 84)
                    Text("Klasse Ø").frame(width: 72)
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
                        .frame(minWidth: 140, maxWidth: .infinity, alignment: .leading)
                        VStack(spacing: 2) {
                            Text(verbatim: grade.gradeDisplay ?? "–")
                                .font(UberFont.text(13, weight: .bold))
                            if let sub = grade.gradeSub, !sub.isEmpty {
                                Text(verbatim: sub)
                                    .font(UberFont.text(11))
                                    .foregroundStyle(EduFlowPalette.inkMuted(scheme))
                                    .lineLimit(2)
                            } else if grade.isClassic == false {
                                Text(NSLocalizedString("grades_not_classic", value: "o. Wertung", comment: "Noten: nicht klassisch"))
                                    .font(UberFont.text(11))
                                    .foregroundStyle(EduFlowPalette.inkMuted(scheme))
                            }
                        }
                        .frame(width: 76)
                        Text(verbatim: grade.dateDisplay ?? "–")
                            .font(UberFont.text(12))
                            .foregroundStyle(EduFlowPalette.inkMuted(scheme))
                            .frame(width: 92)
                        Text(verbatim: weightText(grade))
                            .font(UberFont.text(12, weight: weightIsStandard(grade) ? .regular : .bold))
                            .monospacedDigit()
                            .foregroundStyle(weightIsStandard(grade) ? EduFlowPalette.inkMuted(scheme) : EduFlowPalette.ink(scheme))
                            .frame(width: 84)
                        Text(verbatim: classAvgText(grade))
                            .font(UberFont.text(12))
                            .monospacedDigit()
                            .foregroundStyle(EduFlowPalette.inkMuted(scheme))
                            .frame(width: 72)
                    }
                    .padding(.vertical, 8)
                    Divider()
                }
            }
            .frame(minWidth: 560)
        }
    }

    /// Gewichtung wie im Web: `weight_display`, Fallback `×1`.
    private func weightText(_ grade: GradeDTO) -> String {
        guard let display = grade.weightDisplay, !display.isEmpty else { return "×1" }
        return display
    }

    private func weightIsStandard(_ grade: GradeDTO) -> Bool {
        guard let display = grade.weightDisplay, !display.isEmpty else { return true }
        return false
    }

    private func classAvgText(_ grade: GradeDTO) -> String {
        guard let display = grade.classAvgDisplay, !display.isEmpty else { return "–" }
        return display
    }
}
