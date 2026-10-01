import SwiftUI

/// Startseite: Uhr + Jetzt-Karte oben (nebeneinander auf breiten
/// Fenstern), Kennzahlen-Band zur sichtbaren Auswahl, darunter
/// Nachrichten und Hausaufgaben als Spalten; Wetter läuft kompakt als
/// Streifen und verdrängt keine Inhalte.
public struct OverviewView: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.uberAccent) private var accent
    @State private var vm: OverviewViewModel
    @State private var now = Date()
    @State private var lessonIndex = 0
    @State private var showWetter = false
    @State private var showLayoutEditor = false
    @State private var layoutDraft = ["messages", "homework", "weather"]
    private let onNavigate: (Route) -> Void
    private let onSessionExpired: () -> Void

    private static let clock24: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private static let clock12: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "h:mm:ss a"
        return formatter
    }()

    private static func clockString(from date: Date, timeFormat: String) -> String {
        (timeFormat == "12h" ? clock12 : clock24).string(from: date)
    }

    private static let dateLine: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "EEEE, d. MMMM yyyy"
        return formatter
    }()

    public init(
        store: TokenStore,
        onNavigate: @escaping (Route) -> Void,
        onSessionExpired: @escaping () -> Void
    ) {
        _vm = State(initialValue: OverviewViewModel(store: store))
        self.onNavigate = onNavigate
        self.onSessionExpired = onSessionExpired
    }

    public var body: some View {
        ScrollView {
            ScrollOffsetSentinel()
            VStack(alignment: .leading, spacing: 20) {
                topRow
                statsBand
                    .riseIn(delay: 0.12)
                layoutRow
                // Wetter bleibt kompakt und verdrängt nichts: Steht es in
                // der Reihenfolge zuerst, erscheint es als schmaler Streifen
                // oben, sonst unten. Hausaufgaben und Nachrichten stehen
                // immer als Spalten nebeneinander (bzw. untereinander auf
                // schmalen Fenstern).
                if orderedSections.first == "weather" {
                    weatherStrip
                }
                mainColumns(order: orderedSections)
                if orderedSections.first != "weather" {
                    weatherStrip
                }
                footer
            }
            .padding(20)
            .frame(maxWidth: 1280)
            .frame(maxWidth: .infinity)
        }
        .background(EduFlowPalette.canvas(scheme))
        .navigationTitle(NSLocalizedString("Overview", value: "Overview", comment: "Übersicht: Titel"))
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { now = $0 }
        .task { await vm.load(onSessionExpired: onSessionExpired) }
        .refreshable { await vm.load(refresh: true, onSessionExpired: onSessionExpired) }
        .sheet(isPresented: $showWetter) {
            WetterSheet(wetter: vm.wetter)
        }
        .sheet(isPresented: $showLayoutEditor) {
            OverviewOrderEditor(order: $layoutDraft, saving: vm.isSavingOrder, error: vm.orderSaveError) {
                let saved = await vm.saveOverviewOrder(layoutDraft, onSessionExpired: onSessionExpired)
                if saved { showLayoutEditor = false }
                return saved
            }
        }
    }

    // MARK: - Obere Reihe (`.ov-top`)

    /// Uhr und Jetzt-Karte nebeneinander auf breiten Fenstern,
    /// untereinander auf schmalen.
    private var topRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 16) {
                clockCard
                    .frame(minWidth: 240, maxWidth: 340)
                nowCard
                    .frame(minWidth: 320, maxWidth: .infinity)
            }
            VStack(spacing: 16) {
                clockCard
                nowCard
            }
        }
        .riseIn()
    }

    /// Kennzahlen-Band über die sichtbare Auswahl (konsistent mit den
    /// Listen darunter, keine globalen Zähler).
    private var statsBand: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 12)], spacing: 12) {
            StatCard("\(vm.messagesTotal)", label: "Messages")
            StatCard("\(vm.homeworkOpen)", label: "Open")
            StatCard(
                "\(vm.homeworkOverdue)",
                label: "Overdue",
                tone: vm.homeworkOverdue > 0 ? .danger : .plain
            )
        }
    }

    private var layoutRow: some View {
        HStack {
            Spacer()
            Button(NSLocalizedString("Customize overview", value: "Customize overview", comment: "UI-Literal")) {
                layoutDraft = Self.normalizedOrder(vm.settings.ovOrder)
                showLayoutEditor = true
            }
            .buttonStyle(UberButtonStyle(.smallLight))
        }
    }

    /// Hausaufgaben und Nachrichten in der vom Nutzer gewählten
    /// Reihenfolge (erste links/oben), Wetter läuft separat als Streifen.
    private func mainColumns(order: [String]) -> some View {
        let homeworkFirst = (order.firstIndex(of: "homework") ?? 1) < (order.firstIndex(of: "messages") ?? 0)
        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 16) {
                if homeworkFirst {
                    homeworkColumn.frame(minWidth: 320, maxWidth: .infinity, alignment: .top)
                    messagesColumn.frame(minWidth: 320, maxWidth: .infinity, alignment: .top)
                } else {
                    messagesColumn.frame(minWidth: 320, maxWidth: .infinity, alignment: .top)
                    homeworkColumn.frame(minWidth: 320, maxWidth: .infinity, alignment: .top)
                }
            }
            VStack(spacing: 16) {
                if homeworkFirst {
                    homeworkColumn
                    messagesColumn
                } else {
                    messagesColumn
                    homeworkColumn
                }
            }
        }
    }

    /// Kompakter Wetter-Streifen (verdrängt keine Inhalte, keine fixe Höhe).
    @ViewBuilder
    private var weatherStrip: some View {
        if vm.settings.ovWetter {
            if let error = vm.wetterError, vm.wetter.today == nil {
                Notice(error.message)
            } else if vm.wetter.today != nil {
                weatherCard
            }
        }
    }

    private var clockCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Spacer()
            Text(Self.clockString(from: now, timeFormat: vm.settings.timeFormat))
                .font(UberFont.text(44, weight: .heavy))
                .tracking(-1.5)
                .monospacedDigit()
            Text(Self.dateLine.string(from: now))
                .font(UberFont.text(14, weight: .semibold))
                .foregroundStyle(EduFlowPalette.inkMuted(scheme))
            Spacer()
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 26)
        .frame(minWidth: 200)
        .background(EduFlowPalette.card(scheme))
        .clipShape(.rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(EduFlowPalette.border(scheme), lineWidth: 1)
        }
    }

    private var weatherCard: some View {
        Button { showWetter = vm.wetter.today != nil } label: {
            HStack(spacing: 0) {
                WetterDayCard(
                    label: "Today",
                    big: vm.wetter.today.map { "\($0.temp ?? 0)°" } ?? "–",
                    cond: [vm.wetter.today?.desc, vm.wetter.today.map { "· \($0.max ?? 0)°/\($0.min ?? 0)°" }].compactMap { $0 }.joined(separator: " "),
                    icon: vm.wetter.today?.icon,
                    pop: vm.wetter.today?.pop
                )
                Divider()
                WetterDayCard(
                    label: "Tomorrow",
                    big: vm.wetter.tomorrow.map { "\($0.max ?? 0)°" } ?? "–",
                    cond: [vm.wetter.tomorrow?.desc, vm.wetter.tomorrow.map { "· \($0.max ?? 0)°/\($0.min ?? 0)°" }].compactMap { $0 }.joined(separator: " "),
                    icon: vm.wetter.tomorrow?.icon,
                    pop: vm.wetter.tomorrow?.pop
                )
                Divider()
                WetterDayCard(
                    label: vm.wetter.day3?.label ?? NSLocalizedString("Day after tomorrow", value: "Day after tomorrow", comment: "Übersicht: Übermorgen"),
                    big: vm.wetter.day3.map { "\($0.max ?? 0)°" } ?? "–",
                    cond: [vm.wetter.day3?.desc, vm.wetter.day3.map { "· \($0.max ?? 0)°/\($0.min ?? 0)°" }].compactMap { $0 }.joined(separator: " "),
                    icon: vm.wetter.day3?.icon,
                    pop: vm.wetter.day3?.pop
                )
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 22)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.plain)
        .background(EduFlowPalette.card(scheme))
        .clipShape(.rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(EduFlowPalette.border(scheme), lineWidth: 1)
        }
    }

    /// Schwarze Jetzt-Karte mit Stunden-Karussell (`.now-card`).
    private var nowCard: some View {
        let slides = vm.lessons.filter { !$0.isEvent }
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Classes today")
                    .font(UberFont.text(11, weight: .bold))
                    .tracking(1.6)
                    .opacity(0.6)
                Spacer()
                if slides.count > 1 {
                    Text(verbatim: "\(lessonIndex + 1) / \(slides.count)")
                        .font(UberFont.text(11, weight: .heavy))
                        .tracking(0.6)
                        .padding(.vertical, 3)
                        .padding(.horizontal, 10)
                        .background(.white.opacity(0.12))
                        .clipShape(.capsule)
                }
            }
            if slides.isEmpty {
                Text("No school")
                    .font(UberFont.text(30, weight: .heavy))
                    .tracking(-0.8)
                    .padding(.vertical, 4)
                Text("no classes today")
                    .font(UberFont.text(13, weight: .medium))
                    .opacity(0.75)
            } else {
                let lesson = slides[min(lessonIndex, slides.count - 1)]
                let pair = vm.currentAndNext(now: now)
                VStack(alignment: .leading, spacing: 2) {
                    Text(lesson.title)
                        .font(UberFont.text(30, weight: .heavy))
                        .tracking(-0.8)
                        .lineLimit(1)
                        .padding(.vertical, 4)
                    Text(String(
                        format: NSLocalizedString("overview_lesson_detail", value: "%@. period · %@%@%@", comment: "Übersicht: Stundendetail"),
                        lesson.period, lesson.time,
                        lesson.rooms.isEmpty ? "" : String(format: NSLocalizedString("overview_lesson_room", value: " · Room %@", comment: "Übersicht: Raum"), lesson.rooms),
                        lesson.teachers.isEmpty ? "" : String(format: NSLocalizedString("overview_lesson_teachers", value: " · %@", comment: "Übersicht: Lehrkraft"), lesson.teachers)
                    ))
                        .font(UberFont.text(13, weight: .medium))
                        .opacity(0.75)
                    HStack(spacing: 6) {
                        if isNow(lesson, pair: pair) {
                            HStack(spacing: 6) {
                                PulseDot()
                                Text("Now")
                                    .font(UberFont.text(11, weight: .bold))
                            }
                            .padding(.vertical, 5)
                            .padding(.horizontal, 12)
                            .background(accent.resolved(scheme))
                            .foregroundStyle(accent.resolvedInk(scheme))
                            .clipShape(.capsule)
                        }
                        if lesson.isCancelled {
                            Tag(NSLocalizedString("Cancelled", value: "Cancelled", comment: "Übersicht: entfällt"), style: .muted)
                        }
                    }
                    .padding(.top, 8)
                }
                .id(lesson.uid)
                .transition(
                    .asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    )
                )
            }
            Spacer()
            HStack {
                NowArrow("‹") { stepLesson(-1, count: slides.count) }
                Spacer()
                Button(NSLocalizedString("Timetable", value: "Timetable", comment: "Einstellungen: Startseite Stundenplan / Stundenplan: Titel")) { onNavigate(.timetable) }
                    .font(UberFont.text(13, weight: .bold))
                    .opacity(0.75)
                Spacer()
                NowArrow("›") { stepLesson(1, count: slides.count) }
            }
            .padding(.top, 10)
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, minHeight: 170)
        .background(nowBackground)
        .foregroundStyle(.white)
        .clipShape(.rect(cornerRadius: 14))
        .overlay {
            if scheme == .dark {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(EduFlowPalette.border(scheme), lineWidth: 1)
            }
        }
        .onChange(of: vm.lessons) {
            lessonIndex = startLessonIndex(slides: slides)
        }
    }

    private var nowBackground: Color {
        scheme == .dark
            ? EduFlowPalette.card(scheme)
            : Color(red: 0, green: 0, blue: 0)
    }

    private func isNow(_ lesson: Lesson, pair: (current: Lesson?, next: Lesson?)) -> Bool {
        pair.current?.uid == lesson.uid
    }

    private func startLessonIndex(slides: [Lesson]) -> Int {
        let pair = vm.currentAndNext(now: now)
        if let current = pair.current,
            let index = slides.firstIndex(where: { $0.uid == current.uid })
        {
            return index
        }
        if let next = pair.next,
            let index = slides.firstIndex(where: { $0.uid == next.uid })
        {
            return index
        }
        return 0
    }

    private func stepLesson(_ delta: Int, count: Int) {
        guard count > 0 else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            lessonIndex = min(max(lessonIndex + delta, 0), count - 1)
        }
    }

    // MARK: - Spalten (`.ov-grid`)

    private var messagesColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(String(format: NSLocalizedString("overview_messages_total", value: "Messages · %d", comment: "Übersicht: Nachrichtenzahl"), vm.messagesTotal))
                    .font(UberFont.text(20, weight: .heavy))
                Spacer()
                Button(NSLocalizedString("All messages", value: "All messages", comment: "UI-Literal")) { onNavigate(.messages) }
                    .buttonStyle(UberButtonStyle(.smallLight))
            }
            if let error = vm.messagesError {
                Notice(error.message)
            } else if vm.shownMessages.isEmpty {
                Text(NSLocalizedString("overview_messages_empty", value: "No new messages.", comment: "Übersicht: keine Nachrichten"))
                    .font(UberFont.text(14))
                    .foregroundStyle(EduFlowPalette.inkMuted(scheme))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .background(EduFlowPalette.card(scheme))
                    .clipShape(.rect(cornerRadius: 14))
            } else {
                ForEach(vm.shownMessages, id: \.id) { message in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            (message.author.isEmpty ? Text("School") : Text(verbatim: message.author))
                                .font(UberFont.text(14, weight: .bold))
                            Spacer()
                            Text(message.timestamp)
                                .font(UberFont.text(11, weight: .medium))
                                .foregroundStyle(EduFlowPalette.inkMuted(scheme))
                        }
                        Text(message.text.isEmpty ? message.typeLabel : message.text)
                            .font(UberFont.text(13))
                            .lineLimit(3)
                            .foregroundStyle(EduFlowPalette.inkMuted(scheme))
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(EduFlowPalette.card(scheme))
                    .clipShape(.rect(cornerRadius: 14))
                    .overlay { RoundedRectangle(cornerRadius: 14).stroke(EduFlowPalette.border(scheme), lineWidth: 1) }
                }
                if vm.messagesHasMore {
                    Button(String(format: NSLocalizedString("overview_more_messages", value: "+ %d more", comment: "Übersicht: weitere Nachrichten"), vm.messagesMoreCount)) {
                        onNavigate(.messages)
                    }
                    .buttonStyle(UberButtonStyle(.smallLight))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var orderedSections: [String] {
        Self.normalizedOrder(vm.settings.ovOrder)
    }

    private static func normalizedOrder(_ raw: String) -> [String] {
        let valid = ["messages", "homework", "weather"]
        let parsed = raw.split(separator: ",").map(String.init).filter { valid.contains($0) }
        let unique = parsed.reduce(into: [String]()) { result, key in
            if !result.contains(key) { result.append(key) }
        }
        return unique + valid.filter { !unique.contains($0) }
    }

    private var homeworkColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Homework")
                        .font(UberFont.text(20, weight: .heavy))
                        .tracking(-0.5)
                    Text(String(format: NSLocalizedString("overview_homework_sub", value: "%d open · %d overdue", comment: "Übersicht: Hausaufgaben-Totale"), vm.homeworkTotalOpen, vm.homeworkTotalOverdue))
                        .font(UberFont.text(13, weight: .medium))
                        .foregroundStyle(EduFlowPalette.inkMuted(scheme))
                }
                Spacer()
                Button(NSLocalizedString("All homework", value: "All homework", comment: "UI-Literal")) { onNavigate(.homework) }
                    .buttonStyle(UberButtonStyle(.smallPrimary))
                    .hoverLift()
            }
            .frame(minHeight: 36)
            if let error = vm.homeworkError {
                Notice(error.message)
            } else if vm.homework.isEmpty {
                // Leere Liste ehrlich erklären: Alle Zahlen stammen aus
                // denselben Server-Totalen wie die Kopfzeile.
                if vm.homeworkRelevantTotal > 0 {
                    Text(NSLocalizedString("overview_homework_more_available", value: "More tasks available — view all.", comment: "Übersicht: weitere Aufgaben vorhanden"))
                        .font(UberFont.text(15))
                        .foregroundStyle(EduFlowPalette.inkMuted(scheme))
                        .frame(maxWidth: .infinity)
                        .padding(48)
                } else if vm.homeworkDone > 0 {
                    Text(NSLocalizedString("overview_homework_all_done", value: "All homework done. Well done.", comment: "Übersicht: alles erledigt"))
                        .font(UberFont.text(15))
                        .foregroundStyle(EduFlowPalette.inkMuted(scheme))
                        .frame(maxWidth: .infinity)
                        .padding(48)
                } else {
                    Text(NSLocalizedString("overview_homework_none", value: "No homework available.", comment: "Übersicht: keine Aufgaben"))
                        .font(UberFont.text(15))
                        .foregroundStyle(EduFlowPalette.inkMuted(scheme))
                        .frame(maxWidth: .infinity)
                        .padding(48)
                }
            } else {
                ForEach(Array(vm.homework.enumerated()), id: \.element.id) { index, item in
                    HomeworkCard(status: item.status, isDone: item.isDone, isHidden: false) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(item.title)
                                .font(UberFont.text(17, weight: .heavy))
                                .tracking(-0.3)
                            HStack(spacing: 8) {
                                Tag(item.status, style: statusTag(item.status))
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
                        }
                    }
                    .riseIn(delay: Double(min(index, 8)) * 0.06)
                }
                if vm.homeworkHasMore {
                    Button(String(format: NSLocalizedString("overview_more_homework", value: "+ %d more", comment: "Übersicht: weitere Aufgaben"), vm.homeworkMoreCount)) {
                        onNavigate(.homework)
                    }
                    .buttonStyle(UberButtonStyle(.smallLight))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
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

    /// Knöpfe zu allen Bereichen (Nachrichten, Hausaufgaben, Stundenplan,
    /// Noten, Einstellungen) plus lokale Kennzeichnung.
    private var footer: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Button(NSLocalizedString("Messages", value: "Messages", comment: "Übersicht: Bereich Nachrichten")) { onNavigate(.messages) }
                    .buttonStyle(UberButtonStyle(.smallLight))
                Button(NSLocalizedString("Homework", value: "Homework", comment: "Übersicht: Bereich Hausaufgaben")) { onNavigate(.homework) }
                    .buttonStyle(UberButtonStyle(.smallLight))
                Button(NSLocalizedString("Timetable", value: "Timetable", comment: "Übersicht: Bereich Stundenplan")) { onNavigate(.timetable) }
                    .buttonStyle(UberButtonStyle(.smallLight))
                Button(NSLocalizedString("grades_nav", value: "Grades", comment: "Übersicht: Bereich Noten")) { onNavigate(.grades) }
                    .buttonStyle(UberButtonStyle(.smallLight))
                Button(NSLocalizedString("Settings", value: "Settings", comment: "Übersicht: Bereich Einstellungen")) { onNavigate(.settings) }
                    .buttonStyle(UberButtonStyle(.smallLight))
            }
            Text("EduFlow Dashboard · local")
                .font(UberFont.text(12))
                .foregroundStyle(EduFlowPalette.inkDim(scheme))
                .frame(maxWidth: .infinity)
        }
        .padding(.top, 16)
    }
}

// MARK: - Bausteine

private struct OverviewOrderEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @Binding var order: [String]
    let saving: Bool
    let error: String?
    let onSave: () async -> Bool

    private let labels = [
        "messages": NSLocalizedString("Messages", value: "Messages", comment: "Übersicht: Bereich Nachrichten"),
        "homework": NSLocalizedString("Homework", value: "Homework", comment: "Übersicht: Bereich Aufgaben"),
        "weather": NSLocalizedString("Weather", value: "Weather", comment: "Übersicht: Bereich Wetter"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Customize overview")
                .font(UberFont.text(24, weight: .heavy))
            Text("Choose which sections appear first.")
                .font(UberFont.text(14))
                .foregroundStyle(.secondary)
            ForEach(order.indices, id: \.self) { index in
                HStack {
                    Text(LocalizedStringKey(labels[order[index]] ?? order[index]))
                        .font(UberFont.text(15, weight: .semibold))
                    Spacer()
                    Button("↑") { order = OverviewOrderEditor.move(order, from: index, by: -1) }
                        .disabled(index == 0)
                    Button("↓") { order = OverviewOrderEditor.move(order, from: index, by: 1) }
                        .disabled(index == order.count - 1)
                }
                .padding(12)
                .background(EduFlowPalette.card(scheme))
                .clipShape(.rect(cornerRadius: 12))
            }
            if let error {
                Text(error)
                    .font(UberFont.text(13, weight: .semibold))
                    .foregroundStyle(EduFlowPalette.red)
            }
            HStack {
                Button(NSLocalizedString("Cancel", value: "Cancel", comment: "UI-Literal")) { dismiss() }
                    .buttonStyle(UberButtonStyle(.smallLight))
                Spacer()
                Button(saving ? NSLocalizedString("Saving overview …", value: "Saving overview …", comment: "Übersicht: speichert") : NSLocalizedString("Save", value: "Save", comment: "Übersicht: speichern")) {
                    Task { _ = await onSave() }
                }
                    .buttonStyle(UberButtonStyle(.smallPrimary))
                    .disabled(saving)
            }
            .padding(.top, 4)
        }
        .padding(24)
        .frame(minWidth: 420, minHeight: 360)
    }

    private static func move(_ order: [String], from: Int, by offset: Int) -> [String] {
        let target = min(max(from + offset, 0), order.count - 1)
        guard target != from else { return order }
        var result = order
        let item = result.remove(at: from)
        result.insert(item, at: target)
        return result
    }
}

/// Wetter-Tag (`.wx-day`): Label, Icon, Temperatur, Bedingung, Regen.
private struct WetterDayCard: View {
    @Environment(\.colorScheme) var scheme
    let label: String
    let big: String
    let cond: String
    let icon: String?
    let pop: Int?

    var body: some View {
        VStack(spacing: 2) {
            Text(LocalizedStringKey(label))
                .textCase(.uppercase)
                .font(UberFont.text(11, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(EduFlowPalette.inkMuted(scheme))
            if let icon, !icon.isEmpty {
                AsyncImage(url: URL(string: "https://openweathermap.org/img/wn/\(icon)@2x.png")) { image in
                    image.resizable()
                } placeholder: {
                    Color.clear
                }
                .frame(width: 52, height: 52)
            }
            Text(verbatim: big)
                .font(UberFont.text(24, weight: .heavy))
                .tracking(-0.5)
                .monospacedDigit()
            Text(verbatim: cond)
                .font(UberFont.text(12, weight: .semibold))
                .foregroundStyle(EduFlowPalette.inkMuted(scheme))
            Text(verbatim: "☂ \(pop.map { "\($0) %" } ?? "–")")
                .font(UberFont.text(12, weight: .semibold))
                .foregroundStyle(EduFlowPalette.inkMuted(scheme))
        }
        .frame(maxWidth: .infinity)
    }
}

/// Runder Pfeil in der Jetzt-Karte (`.now-arrow`).
private struct NowArrow: View {
    let title: String
    let action: () -> Void

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(verbatim: title)
                .font(.system(size: 18))
                .frame(width: 32, height: 32)
                .background(.white.opacity(0.001))
                .clipShape(.circle)
                .overlay { Circle().stroke(.white.opacity(0.4), lineWidth: 1) }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
    }
}

/// Wetter-Details als Sheet (`.wx-modal`): Stunden + Details.
private struct WetterSheet: View {
    @Environment(\.colorScheme) var scheme
    @Environment(\.dismiss) var dismiss
    let wetter: WetterResponse

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Spacer()
                    Button(NSLocalizedString("Close", value: "Close", comment: "UI-Literal")) { dismiss() }
                        .buttonStyle(UberButtonStyle(.smallLight))
                        .hoverLift()
                }
                if let city = wetter.city, !city.isEmpty {
                    Text(String(format: NSLocalizedString("overview_weather_in_city", value: "Weather in %@", comment: "Übersicht: Wetterstadt"), city).uppercased())
                        .font(UberFont.text(11, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(EduFlowPalette.inkMuted(scheme))
                }
                if let today = wetter.today {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(verbatim: "\(today.temp ?? 0)°")
                            .font(UberFont.text(44, weight: .heavy))
                            .tracking(-1)
                        Text(verbatim: "\(today.desc ?? "") · \(today.max ?? 0)°/\(today.min ?? 0)°")
                            .font(UberFont.text(14))
                            .foregroundStyle(EduFlowPalette.inkMuted(scheme))
                    }
                }
                if let hours = wetter.hourly, !hours.isEmpty {
                    Text("Next 24 hours")
                        .font(UberFont.text(14, weight: .heavy))
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(hours.indices, id: \.self) { index in
                                let hour = hours[index]
                                VStack(spacing: 2) {
                                    (index == 0 ? Text("Now") : Text(verbatim: hour.time ?? ""))
                                        .font(UberFont.text(11, weight: .bold))
                                        .tracking(1.2)
                                        .foregroundStyle(EduFlowPalette.inkMuted(scheme))
                                    Text(verbatim: "\(hour.temp ?? 0)°")
                                        .font(UberFont.text(16, weight: .heavy))
                                    Text(verbatim: "☂ \(hour.pop.map { "\($0) %" } ?? "–")")
                                        .font(UberFont.text(12, weight: .semibold))
                                        .foregroundStyle(EduFlowPalette.inkMuted(scheme))
                                }
                                .padding(8)
                                .frame(minWidth: 64)
                                .background(EduFlowPalette.card(scheme))
                                .clipShape(.rect(cornerRadius: 12))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(EduFlowPalette.border(scheme), lineWidth: 1)
                                }
                            }
                        }
                    }
                }
                if let details = wetter.details {
                    Text("Details")
                        .font(UberFont.text(14, weight: .heavy))
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        WetterDetail(label: "Feels like", value: details.feelsLike.map { "\($0)°" } ?? "–")
                        WetterDetail(
                            label: "Wind",
                            value: [details.windKmh.map { "\($0) km/h" }, details.windDir].compactMap { $0 }.joined(separator: " ")
                        )
                        WetterDetail(label: "Humidity", value: details.humidity.map { "\($0) %" } ?? "–")
                        WetterDetail(label: "Pressure", value: details.pressure.map { "\($0) hPa" } ?? "–")
                        WetterDetail(label: "Clouds", value: details.clouds.map { "\($0) %" } ?? "–")
                        WetterDetail(label: "View", value: details.visibilityKm.map { "\($0) km" } ?? "–")
                        WetterDetail(label: "Sunrise", value: details.sunrise ?? "–")
                        WetterDetail(label: "Sunset", value: details.sunset ?? "–")
                    }
                }
            }
            .padding(20)
        }
        .frame(minWidth: 340, minHeight: 400)
        .background(EduFlowPalette.canvas(scheme))
    }
}

private struct WetterDetail: View {
    @Environment(\.colorScheme) var scheme
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(LocalizedStringKey(label))
                .textCase(.uppercase)
                .font(UberFont.text(11, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(EduFlowPalette.inkMuted(scheme))
            Text(verbatim: value.isEmpty ? "–" : value)
                .font(UberFont.text(16, weight: .heavy))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(EduFlowPalette.card(scheme))
        .clipShape(.rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(EduFlowPalette.border(scheme), lineWidth: 1)
        }
    }
}
