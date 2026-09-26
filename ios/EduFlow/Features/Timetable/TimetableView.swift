import SwiftUI

// MARK: - Stundenplan Tag/Woche (Paket D, Redesign-PNG Screen 03)
//
// Header, Titel „Stundenplan" + Datum als Untertitel, Segmented
// Tag/Woche, Tages-Kopf (Datum + „N STUNDEN") mit ‹ ›-Blättern,
// „Heute"-Zeile mit Chevron, Stunden-Zeilen: Startzeit links grau,
// Trennstrich, Fach fett + „Lehrer · Raum" darunter, „JETZT"-Pill an
// der laufenden Stunde (nur wenn der angezeigte Tag heute ist).
// Entfallene Stunden stehen als ausgegraute Einzeiler
// („08:00 · Sport entfällt"). Tag-Navi: ‹ › (±1 Tag, ±7 in der Woche)
// + Heute-Zeile. Logik (Tag/Woche, refresh=1) wie im Web.

struct TimetableView: View {
    @EnvironmentObject var store: TokenStore
    @StateObject private var viewModel: TimetableViewModel

    init(service: TimetableService) {
        _viewModel = StateObject(wrappedValue: TimetableViewModel(service: service))
    }

    private func client() -> APIClient {
        let base = URL(string: store.baseURL) ?? URL(string: TokenStore.defaultBaseURL)!
        return APIClient(baseURL: base, tokenProvider: { store.currentToken() })
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 10) {
                AppHeader(client: client())
                ScreenHead(title: "Stundenplan",
                           subtitle: viewModel.view == .day
                            ? (viewModel.dayData?.dayLabel.nilIfEmpty ?? viewModel.day)
                            : (viewModel.weekData?.weekLabel.nilIfEmpty ?? viewModel.day))
                Picker("Ansicht", selection: Binding(
                    get: { viewModel.view },
                    set: { view in Task { await viewModel.setView(view) } }
                )) {
                    Text("Tag").tag(TimetableViewModel.View.day)
                    Text("Woche").tag(TimetableViewModel.View.week)
                }
                .pickerStyle(.segmented)

                if viewModel.view == .day {
                    dayBody
                } else {
                    weekBody
                }
            }
            .padding(16)
            .background(Color.rBackground)
            .navigationTitle("Stundenplan")
            .refreshable { await viewModel.load(refresh: true) }
            .task { await viewModel.load() }
        }
    }

    // MARK: Tag

    @ViewBuilder
    private var dayBody: some View {
        let day = viewModel.dayData
        let isTodayShown = isToday(day?.day, serverToday: day?.today)
        let nowUid = isTodayShown && day != nil
            ? ISODate.currentAndNext(day!.lessons).0?.uid : nil

        DayHeadRow(
            label: day?.dayLabel.nilIfEmpty ?? viewModel.day,
            count: day.map { "\($0.lessons.count) Stunden" } ?? "",
            onPrev: { Task { await viewModel.step(-1) } },
            onNext: { Task { await viewModel.step(1) } },
            onRefresh: { Task { await viewModel.load(refresh: true) } },
            refreshing: viewModel.isLoading
        )
        TodayRow { Task { await viewModel.goToday() } }
        if let info = day?.cacheInfo, !info.isEmpty {
            Text(info).font(.caption).foregroundStyle(Color.rMuted)
        }
        if let error = viewModel.error {
            AuthAwareError(error: error, onReLogin: { Task { await reLogin() } },
                           onDismiss: { viewModel.error = nil })
        }
        if viewModel.isLoading && day == nil {
            ProgressView().frame(maxWidth: .infinity, alignment: .center).padding(32)
        } else if let day {
            if day.lessons.isEmpty {
                VStack(spacing: 8) {
                    EmptyBox(message: isWeekend(viewModel.day)
                        ? "Schulfrei — kein Unterricht an diesem Tag."
                        : "Kein Unterricht an diesem Tag.")
                    Button("Neu laden") { Task { await viewModel.load(refresh: true) } }
                        .font(.callout)
                }
                .frame(maxWidth: .infinity)
                .padding(24)
            } else {
                List {
                    ForEach(day.lessons, id: \.uid) { lesson in
                        LessonCard(lesson: lesson, isNow: lesson.uid == nowUid)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 5, leading: 0, bottom: 5, trailing: 0))
                            .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Color.rBackground)
                .refreshable { await viewModel.load(refresh: true) }
            }
        }
    }

    // MARK: Woche (Mo–Fr, Events herausgefiltert wie im Web)

    @ViewBuilder
    private var weekBody: some View {
        let week = viewModel.weekData

        DayHeadRow(
            label: week?.weekLabel.nilIfEmpty ?? viewModel.day,
            count: week.map { "\($0.days.reduce(0) { $0 + $1.lessons.count }) Stunden diese Woche" } ?? "",
            onPrev: { Task { await viewModel.step(-1) } },
            onNext: { Task { await viewModel.step(1) } },
            onRefresh: { Task { await viewModel.load(refresh: true) } },
            refreshing: viewModel.isLoading
        )
        TodayRow { Task { await viewModel.goToday() } }
        if let info = week?.cacheInfo, !info.isEmpty {
            Text(info).font(.caption).foregroundStyle(Color.rMuted)
        }
        if let error = viewModel.error {
            AuthAwareError(error: error, onReLogin: { Task { await reLogin() } },
                           onDismiss: { viewModel.error = nil })
        }
        if viewModel.isLoading && week == nil {
            ProgressView().frame(maxWidth: .infinity, alignment: .center).padding(32)
        } else if let week {
            List {
                ForEach(week.days) { day in
                    Section {
                        ForEach(day.lessons, id: \.uid) { lesson in
                            let nowUid = day.isToday
                                ? ISODate.currentAndNext(day.lessons).0?.uid : nil
                            LessonCard(lesson: lesson, isNow: lesson.uid == nowUid)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 5, leading: 0, bottom: 5, trailing: 0))
                                .listRowBackground(Color.clear)
                        }
                        if day.lessons.isEmpty {
                            Text("Kein Unterricht.")
                                .font(.caption)
                                .foregroundStyle(Color.rMuted)
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                        }
                    } header: {
                        HStack {
                            Text("\(day.dayName) \(day.dayDate)")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(day.isToday ? Color.rPrimary : Color.rInk)
                            Spacer()
                            if day.isToday {
                                StatusPill(text: "Heute", dot: Color.rDotBlue)
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.rBackground)
            .refreshable { await viewModel.load(refresh: true) }
        }
    }

    // MARK: Geteilt

    private func reLogin() async {
        await AuthService(client: { client() }, store: store).logout()
    }
}

// MARK: - Tages-Kopf (PNG Screen 03)

/// ‹ Datum + Zähler › + Aktualisieren.
struct DayHeadRow: View {
    let label: String
    let count: String
    let onPrev: () -> Void
    let onNext: () -> Void
    let onRefresh: () -> Void
    var refreshing = false

    var body: some View {
        HStack {
            Button(action: onPrev) {
                Image(systemName: "chevron.left")
                    .foregroundStyle(Color.rInk)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.rInk)
                if !count.isEmpty {
                    SectionLabel(text: count)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
                    .foregroundStyle(Color.rInk)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .disabled(refreshing)
            Button(action: onNext) {
                Image(systemName: "chevron.right")
                    .foregroundStyle(Color.rInk)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
        }
    }
}

/// „Heute"-Zeile mit Chevron (springt auf heute).
struct TodayRow: View {
    let action: () -> Void

    var body: some View {
        EduCard {
            Button(action: action) {
                HStack {
                    Text("Heute")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.rInk)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(Color.rMuted)
                }
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Stunden-Karte (PNG: Zeit, Trennstrich, Fach + Sub, JETZT-Pill)

struct LessonCard: View {
    let lesson: Lesson
    var isNow = false

    private var sub: String {
        let meta = [lesson.teachers?.nilIfEmpty,
                    (lesson.rooms?.nilIfEmpty).map { "Raum \($0)" }]
            .compactMap { $0 }.joined(separator: " · ")
        var flags: [String] = []
        if lesson.isOnline == true { flags.append("Online") }
        if lesson.isLernzeit == true {
            if (lesson.rowspan ?? 1) > 1 {
                flags.append("Lernzeit (\(lesson.rowspan ?? 1) Std.)")
            } else {
                flags.append("Lernzeit")
            }
        }
        if lesson.isEvent == true { flags.append("Veranstaltung") }
        return ([meta] + [flags.joined(separator: " · ")])
            .filter { !$0.isEmpty }.joined(separator: " · ")
    }

    var body: some View {
        EduCard {
            if lesson.isCancelled == true {
                Text(cancelledLine(lesson))
                    .font(.system(size: 14))
                    .foregroundStyle(Color.rMuted)
            } else {
                HStack(alignment: .top, spacing: 12) {
                    Text(startOf(lesson.time) ?? "–")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.rMuted)
                        .padding(.top, 2)
                        .frame(width: 52, alignment: .leading)
                    Rectangle()
                        .fill(Color.rCardBorder)
                        .frame(width: 1, height: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(lesson.title?.nilIfEmpty ?? "–")
                            .font(RFont.cardTitle)
                            .foregroundStyle(Color.rInk)
                        if !sub.isEmpty {
                            Text(sub)
                                .font(RFont.cardSub)
                                .foregroundStyle(Color.rMuted)
                        }
                    }
                    .layoutPriority(1)
                    Spacer()
                    if isNow {
                        StatusPill(text: "Jetzt", dot: Color.rDotBlue)
                    }
                }
            }
        }
    }
}

// MARK: - Helfer (Anzeige, keine Logikänderung)

private func startOf(_ time: String?) -> String? {
    guard let time, !time.isEmpty else { return nil }
    if let idx = time.firstIndex(where: { $0 == "–" || $0 == "-" }) {
        return String(time[..<idx]).trimmingCharacters(in: .whitespaces)
    }
    return time
}

private func cancelledLine(_ lesson: Lesson) -> String {
    let title = lesson.title?.nilIfEmpty ?? "Unterricht"
    if let start = startOf(lesson.time), !start.isEmpty {
        return "\(start) · \(title) entfällt"
    }
    return "\(title) entfällt"
}

/// Angezeigter Tag ist heute (Server-Heute oder Geräte-Datum).
private func isToday(_ day: String?, serverToday: String?) -> Bool {
    guard let day, !day.isEmpty else { return false }
    if let serverToday, !serverToday.isEmpty, day == serverToday { return true }
    return day == ISODate.today
}

/// Wochenende (Sa/So) aus YYYY-MM-DD.
private func isWeekend(_ iso: String) -> Bool {
    let f = DateFormatter()
    f.calendar = Calendar(identifier: .iso8601)
    f.dateFormat = "yyyy-MM-dd"
    guard let date = f.date(from: iso) else { return false }
    let weekday = Calendar(identifier: .iso8601).component(.weekday, from: date)
    return weekday == 1 || weekday == 7
}
