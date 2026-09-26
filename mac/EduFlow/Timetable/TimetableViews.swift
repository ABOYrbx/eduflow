import SwiftUI

/// Stundenplan wie `/stundenplan`: Tag/Woche-Umschalter, Tageskarten
/// und Wochenmatrix (Stunden × Tage) mit Entfall- und Online-Stil.
public struct DayView: View {
    @Environment(\.colorScheme) private var scheme
    @State private var vm: TimetableViewModel
    private let onSessionExpired: () -> Void

    public init(store: TokenStore, onSessionExpired: @escaping () -> Void) {
        _vm = State(initialValue: TimetableViewModel(store: store))
        self.onSessionExpired = onSessionExpired
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                PageHead(
                    "Stundenplan",
                    stats: vm.weekMode ? vm.weekResponse.weekLabel : vm.dayResponse.dayLabel
                )
                VStack(spacing: 8) {
                    HStack(spacing: 2) {
                        Button("Tag") {
                            vm.weekMode = false
                            Task { await vm.load(onSessionExpired: onSessionExpired) }
                        }
                        .buttonStyle(TogglePill(active: !vm.weekMode))
                        Button("Woche") {
                            vm.weekMode = true
                            Task { await vm.load(onSessionExpired: onSessionExpired) }
                        }
                        .buttonStyle(TogglePill(active: vm.weekMode))
                    }
                    .padding(4)
                    .background(EduFlowPalette.surface1(scheme))
                    .clipShape(.capsule)
                    .overlay {
                        Capsule().stroke(EduFlowPalette.border(scheme), lineWidth: 1)
                    }
                    HStack(spacing: 8) {
                        Button("‹ Zurück") {
                            Task { await vm.step(-1, onSessionExpired: onSessionExpired) }
                        }
                        .buttonStyle(UberButtonStyle(.smallLight))
                        .hoverLift()
                        Button("Heute") {
                            Task { await vm.goToday(onSessionExpired: onSessionExpired) }
                        }
                        .buttonStyle(UberButtonStyle(.smallLight))
                        .hoverLift()
                        Button("Weiter ›") {
                            Task { await vm.step(1, onSessionExpired: onSessionExpired) }
                        }
                        .buttonStyle(UberButtonStyle(.smallLight))
                        .hoverLift()
                        Spacer()
                    }
                }
                if let error = vm.error {
                    ErrorView(message: error.message) {
                        Task { await vm.load(onSessionExpired: onSessionExpired) }
                    }
                } else if vm.isLoading
                    && vm.dayResponse.lessons.isEmpty
                    && vm.weekResponse.days.isEmpty
                {
                    ProgressView()
                        .controlSize(.large)
                        .frame(maxWidth: .infinity)
                        .padding(48)
                } else if vm.weekMode {
                    weekMatrix
                } else if vm.dayResponse.lessons.isEmpty {
                    Text("Schulfrei.")
                        .font(UberFont.text(15))
                        .foregroundStyle(EduFlowPalette.inkMuted(scheme))
                        .frame(maxWidth: .infinity)
                        .padding(48)
                } else {
                    dayList(vm.dayResponse.lessons)
                }
                if let info = vm.weekMode ? vm.weekResponse.cacheInfo : vm.dayResponse.cacheInfo,
                    !info.isEmpty
                {
                    Text(info)
                        .font(UberFont.text(12))
                        .foregroundStyle(EduFlowPalette.inkDim(scheme))
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(20)
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
        }
        .background(EduFlowPalette.canvas(scheme))
        .navigationTitle("Stundenplan")
        .task { await vm.load(onSessionExpired: onSessionExpired) }
        .refreshable { await vm.load(refresh: true, onSessionExpired: onSessionExpired) }
    }

    // MARK: - Tagesliste

    private func dayList(_ lessons: [Lesson]) -> some View {
        VStack(spacing: 8) {
            ForEach(Array(lessons.enumerated()), id: \.element.uid) { index, lesson in
                HStack(spacing: 12) {
                    Text(lesson.period)
                        .font(UberFont.text(14, weight: .heavy))
                        .frame(width: 52)
                        .frame(minHeight: 66)
                        .background(EduFlowPalette.surface1(scheme))
                        .clipShape(.rect(cornerRadius: 10))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(EduFlowPalette.border(scheme), lineWidth: 1)
                        }
                    LessonCell(lesson: lesson)
                }
                .riseIn(delay: Double(min(index, 8)) * 0.05)
            }
        }
    }

    // MARK: - Wochenmatrix (`.tt-matrix`)

    private var weekMatrix: some View {
        let days = vm.weekResponse.days
        return ScrollView(.horizontal, showsIndicators: false) {
            LazyVGrid(
                columns: [GridItem(.fixed(52), spacing: 8)] + Array(
                    repeating: GridItem(.flexible(minimum: 128), spacing: 8),
                    count: max(days.count, 1)
                ),
                spacing: 8
            ) {
                Color.clear
                    .frame(height: 10)
                ForEach(days, id: \.date) { day in
                    VStack(spacing: 0) {
                        Text(day.dayName)
                            .font(UberFont.text(14, weight: .heavy))
                            .tracking(-0.3)
                        Text(day.dayDate)
                            .font(UberFont.text(11, weight: .semibold))
                            .foregroundStyle(EduFlowPalette.inkMuted(scheme))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                ForEach(periodRows(days: days), id: \.self) { period in
                    Text(period)
                        .font(UberFont.text(14, weight: .heavy))
                        .frame(minHeight: 66)
                        .frame(maxWidth: .infinity)
                        .background(EduFlowPalette.surface1(scheme))
                        .clipShape(.rect(cornerRadius: 10))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(EduFlowPalette.border(scheme), lineWidth: 1)
                        }
                    ForEach(days, id: \.date) { day in
                        if let lesson = day.lessons.first(where: { $0.period == period || $0.rowPeriod == period }) {
                            LessonCell(lesson: lesson)
                        } else {
                            Text("–")
                                .font(UberFont.text(12))
                                .foregroundStyle(EduFlowPalette.inkDim(scheme))
                                .frame(maxWidth: .infinity, minHeight: 66)
                        }
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }

    private func periodRows(days: [TimetableWeekDay]) -> [String] {
        var seen: [String] = []
        for day in days {
            for lesson in day.lessons {
                let key = lesson.rowPeriod.isEmpty ? lesson.period : lesson.rowPeriod
                if !seen.contains(key) {
                    seen.append(key)
                }
            }
        }
        return seen.sorted {
            (Int($0.prefix(while: { $0.isNumber })) ?? 99) < (Int($1.prefix(while: { $0.isNumber })) ?? 99)
        }
    }
}

/// Umschalter-Pille (`.view-toggle a`): aktiv in Akzent.
private struct TogglePill: ButtonStyle {
    @Environment(\.colorScheme) var scheme
    @Environment(\.uberAccent) var accent
    let active: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(UberFont.text(13, weight: .bold))
            .padding(.vertical, 8)
            .padding(.horizontal, 20)
            .background(active ? accent.resolved(scheme) : Color.clear)
            .foregroundStyle(active ? accent.resolvedInk(scheme) : EduFlowPalette.inkMuted(scheme))
            .clipShape(.capsule)
    }
}

/// Stunden-Zelle (`.tt-cell`) mit Entfall- und Online-Stil.
public struct LessonCell: View {
    @Environment(\.colorScheme) var scheme
    public let lesson: Lesson

    public init(lesson: Lesson) {
        self.lesson = lesson
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(lesson.title)
                .font(UberFont.text(13, weight: .bold))
                .tracking(-0.2)
                .lineLimit(2)
                .strikethrough(lesson.isCancelled)
            Text(lesson.time)
                .font(UberFont.text(11))
                .foregroundStyle(EduFlowPalette.inkMuted(scheme))
            if !lesson.teachers.isEmpty || !lesson.rooms.isEmpty {
                Text([lesson.teachers, lesson.rooms].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(UberFont.text(11))
                    .foregroundStyle(EduFlowPalette.inkMuted(scheme))
                    .lineLimit(1)
            }
            if lesson.isOnline {
                Text("Online")
                    .font(UberFont.text(11, weight: .bold))
                    .foregroundStyle(EduFlowPalette.blue)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 66, alignment: .leading)
        .padding(8)
        .background(lesson.isEvent ? Color(red: 1, green: 0.98, blue: 0.92) : EduFlowPalette.card(scheme))
        .clipShape(.rect(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(lesson.isEvent ? EduFlowPalette.amber : EduFlowPalette.border(scheme), lineWidth: 1)
        }
        .opacity(lesson.isCancelled ? 0.6 : 1)
    }
}

/// Kompakte Stunden-Zeile für die Übersicht (Titel + Zeit + Kennzeichen).
public struct LessonRow: View {
    @Environment(\.colorScheme) var scheme
    public let lesson: Lesson

    public init(_ lesson: Lesson) {
        self.lesson = lesson
    }

    public var body: some View {
        HStack(spacing: 12) {
            Text(lesson.period)
                .font(UberFont.text(14, weight: .heavy))
                .frame(minWidth: 44, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(lesson.title)
                    .font(UberFont.text(14, weight: .bold))
                    .strikethrough(lesson.isCancelled)
                Text("\(lesson.time) · \(lesson.teachers) · \(lesson.rooms)")
                    .font(UberFont.text(12))
                    .foregroundStyle(EduFlowPalette.inkMuted(scheme))
                HStack(spacing: 6) {
                    if lesson.isCancelled {
                        Tag("Entfall", style: .muted)
                    }
                    if lesson.isOnline {
                        Tag("Online", style: .blue)
                    }
                    if lesson.isLernzeit {
                        Tag("Lernzeit", style: .muted)
                    }
                }
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}
