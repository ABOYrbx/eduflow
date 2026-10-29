import Foundation
import SwiftUI

/// Tageshelfer für den Schulalltag (UTC wie Backend und Web):
/// Wochenstart ist Montag (`(Wochentag + 6) % 7` Tage zurück),
/// das Agenda-Fenster sind −30/+60 Tage um den gewählten Tag.
public enum SchoolDates: Sendable {
    public static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        if let gmt = TimeZone(secondsFromGMT: 0) {
            calendar.timeZone = gmt
        }
        return calendar
    }

    public static func isoDay(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }

    public static func monday(of date: Date) -> Date {
        let weekday = utc.component(.weekday, from: date)
        let offset = (weekday + 5) % 7
        return utc.date(byAdding: .day, value: -offset, to: utc.startOfDay(for: date)) ?? date
    }

    public static func shifted(_ date: Date, days: Int) -> Date {
        utc.date(byAdding: .day, value: days, to: date) ?? date
    }
}

/// Fehlertolerantes Lesen einzelner Werte (unbekannte Felder ignoriert
/// der Decoder ohnehin; falsche Typen fallen auf Defaults zurück).
private func lenientString<K: CodingKey>(_ box: KeyedDecodingContainer<K>, _ key: K) -> String {
    let text: String? = try? box.decodeIfPresent(String.self, forKey: key)
    if let text {
        return text
    }
    let number: Int? = try? box.decodeIfPresent(Int.self, forKey: key)
    if let number {
        return String(number)
    }
    let flag: Bool? = try? box.decodeIfPresent(Bool.self, forKey: key)
    if let flag {
        return flag ? "true" : "false"
    }
    return ""
}

private func lenientInt<K: CodingKey>(_ box: KeyedDecodingContainer<K>, _ key: K) -> Int {
    let number: Int? = try? box.decodeIfPresent(Int.self, forKey: key)
    if let number {
        return number
    }
    let text: String? = try? box.decodeIfPresent(String.self, forKey: key)
    if let text, let parsed = Int(text) {
        return parsed
    }
    return 0
}

/// Agenda-Eintrag 1:1 zum Backend (`event_to_dict` bzw.
/// `homework_to_dict` plus `kind`/`date`); der Titel fällt auf Text
/// bzw. Typ-Label zurück wie in der Web-Agenda.
public struct SchoolAgendaItem: Decodable, Identifiable, Sendable {
    public var id = 0
    public var kind = "event"
    public var date = ""
    public var title = ""
    public var text = ""
    public var subject = ""
    public var typeLabel = ""
    public var author = ""

    public init() {}

    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        id = lenientInt(box, .id)
        kind = lenientString(box, .kind)
        if kind.isEmpty {
            kind = "event"
        }
        date = lenientString(box, .date)
        title = lenientString(box, .title)
        text = lenientString(box, .text)
        subject = lenientString(box, .subject)
        typeLabel = lenientString(box, .typeLabel)
        author = lenientString(box, .author)
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, date, title, text, subject, typeLabel
        case author
    }
}

public struct SchoolAgendaResponse: Decodable, Sendable {
    public var items: [SchoolAgendaItem] = []
    public var total = 0

    public init() {}

    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        items = (try? box.decodeIfPresent([SchoolAgendaItem].self, forKey: .items)) ?? []
        total = lenientInt(box, .total)
    }

    private enum CodingKeys: String, CodingKey {
        case items, total
    }
}

/// Vertretungszeile 1:1 zum Backend (`change_to_dict` mit `class`,
/// `lesson`, `title`, `action`); Zahlen-Stunden werden als Text gelesen.
public struct SchoolSubstitution: Decodable, Identifiable, Sendable {
    public var schoolClass = ""
    public var lesson = ""
    public var title = ""
    public var action = ""

    public var id: String { "\(schoolClass)-\(lesson)-\(title)-\(action)" }

    public init() {}

    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        schoolClass = lenientString(box, .schoolClass)
        lesson = lenientString(box, .lesson)
        title = lenientString(box, .title)
        action = lenientString(box, .action)
    }

    private enum CodingKeys: String, CodingKey {
        case schoolClass = "class"
        case lesson, title, action
    }
}

public struct SchoolSubstitutionDay: Decodable, Identifiable, Sendable {
    public var date = ""
    public var dayLabel = ""
    public var changes: [SchoolSubstitution] = []
    public var id: String { date }

    public init() {}

    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        date = lenientString(box, .date)
        dayLabel = lenientString(box, .dayLabel)
        changes = (try? box.decodeIfPresent([SchoolSubstitution].self, forKey: .changes)) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case date, dayLabel, changes
    }
}

public struct SchoolSubstitutionResponse: Decodable, Sendable {
    public var days: [SchoolSubstitutionDay] = []

    public init() {}

    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        days = (try? box.decodeIfPresent([SchoolSubstitutionDay].self, forKey: .days)) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case days
    }
}

/// Schulalltag-Repository (nur gegen Paket 0): Kalenderfenster und
/// Vertretungswoche wie die Web-Agenda (`school/agenda`,
/// `substitutions/week`).
public struct SchoolRepository: Sendable {
    public let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    public func agenda(day: Date, refresh: Bool = false) async throws -> CachedAgenda {
        var query = [
            URLQueryItem(name: "since", value: SchoolDates.isoDay(SchoolDates.shifted(day, days: -30))),
            URLQueryItem(name: "until", value: SchoolDates.isoDay(SchoolDates.shifted(day, days: 60))),
        ]
        if refresh {
            query.append(URLQueryItem(name: "refresh", value: "1"))
        }
        let payload = try await client.getCached(
            APIClient.Paths.schoolAgenda, query: query, as: SchoolAgendaResponse.self
        )
        let response = try APIClient.decode(SchoolAgendaResponse.self, from: payload.data)
        return CachedAgenda(items: response.items, savedAt: payload.savedAt)
    }

    /// Termine plus Zeitpunkt (nil = frisch vom Server).
    ///
    /// `RandomAccessCollection` statt einzelner Durchreicher-Eigenschaften:
    /// damit bekommen Aufrufer `count`, `isEmpty`, `first` und `first(where:)`
    /// aus der Standardbibliothek und alle bisherigen Stellen bleiben
    /// unverändert — ein eigenes `first` würde `Array.first(where:)`
    /// verdecken.
    public struct CachedAgenda: RandomAccessCollection, Sendable {
        public let items: [SchoolAgendaItem]
        public let savedAt: Date?

        public init(items: [SchoolAgendaItem], savedAt: Date?) {
            self.items = items
            self.savedAt = savedAt
        }

        public var startIndex: Int { items.startIndex }
        public var endIndex: Int { items.endIndex }
        public func index(after i: Int) -> Int { items.index(after: i) }
        public subscript(position: Int) -> SchoolAgendaItem { items[position] }
        public var isFromCache: Bool { savedAt != nil }
    }

    public func substitutions(day: Date) async throws -> CachedSubstitutions {
        let query = [URLQueryItem(name: "day", value: SchoolDates.isoDay(day))]
        let payload = try await client.getCached(
            APIClient.Paths.substitutionsWeek, query: query, as: SchoolSubstitutionResponse.self
        )
        let response = try APIClient.decode(SchoolSubstitutionResponse.self, from: payload.data)
        return CachedSubstitutions(days: response.days, savedAt: payload.savedAt)
    }

    /// Vertretungswoche plus Zeitpunkt (nil = frisch vom Server).
    public struct CachedSubstitutions: RandomAccessCollection, Sendable {
        public let days: [SchoolSubstitutionDay]
        public let savedAt: Date?

        public init(days: [SchoolSubstitutionDay], savedAt: Date?) {
            self.days = days
            self.savedAt = savedAt
        }

        public var startIndex: Int { days.startIndex }
        public var endIndex: Int { days.endIndex }
        public func index(after i: Int) -> Int { days.index(after: i) }
        public subscript(position: Int) -> SchoolSubstitutionDay { days[position] }
        public var isFromCache: Bool { savedAt != nil }
    }
}

@MainActor
@Observable
private final class SchoolViewModel {
    var agenda: [SchoolAgendaItem] = []
    var substitutions: [SchoolSubstitutionDay] = []
    /// Ältester Cache-Zeitpunkt der geladenen Bereiche (nil = frisch).
    var cachedAt: Date?
    var error: APIError?
    var isLoading = false
    var selectedDay = SchoolDates.monday(of: Date())
    private let store: TokenStore

    init(store: TokenStore) { self.store = store }

    func load(refresh: Bool = false, onSessionExpired: () -> Void) async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        let repo = SchoolRepository(client: store.makeClient())
        let selectedDay = self.selectedDay
        async let agendaResult = Self.capture { try await repo.agenda(day: selectedDay, refresh: refresh) }
        async let substitutionResult = Self.capture { try await repo.substitutions(day: selectedDay) }
        let (agenda, substitutions) = await (agendaResult, substitutionResult)
        switch agenda {
        case .success(let value):
            self.agenda = value.items
            noteCached(value.savedAt)
        case .failure(let apiError): self.error = apiError
        }
        switch substitutions {
        case .success(let value):
            self.substitutions = value.days
            noteCached(value.savedAt)
        case .failure(let apiError): self.error = self.error ?? apiError
        }
        if let error, SessionRecovery.forceLogout(error: error, isLoggedIn: store.isLoggedIn) {
            store.clear()
            onSessionExpired()
        }
    }

    func moveWeek(_ offset: Int, onSessionExpired: () -> Void) async {
        selectedDay = SchoolDates.shifted(selectedDay, days: offset * 7)
        await load(onSessionExpired: onSessionExpired)
    }

    /// Merkt sich den ältesten Cache-Zeitpunkt (die schlechteste sichtbare
    /// Zahl bestimmt, was angezeigt wird).
    private func noteCached(_ savedAt: Date?) {
        guard let savedAt else { return }
        cachedAt = cachedAt.map { min($0, savedAt) } ?? savedAt
    }

    private static func capture<T: Sendable>(
        _ work: @Sendable () async throws -> T
    ) async -> Result<T, APIError> {
        do { return .success(try await work()) }
        catch let error as APIError { return .failure(error) }
        catch { return .failure(APIError(code: ErrorCodes.upstream,
                                        message: APIError.englishFallback(for: ErrorCodes.upstream))) }
    }
}

private enum SchoolTab: String, CaseIterable, Identifiable {
    case agenda = "Calendar"
    case substitutions = "Substitutions"
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .agenda: return NSLocalizedString("school_tab_agenda", value: "Calendar", comment: "Schule: Tab Kalender")
        case .substitutions: return NSLocalizedString("school_tab_substitutions", value: "Substitutions", comment: "Schule: Tab Vertretungen")
        }
    }
}

struct SchoolView: View {
    @Environment(\.colorScheme) private var scheme
    @State private var vm: SchoolViewModel
    @State private var tab: SchoolTab = .agenda
    private let onSessionExpired: () -> Void

    init(store: TokenStore, onSessionExpired: @escaping () -> Void) {
        _vm = State(initialValue: SchoolViewModel(store: store))
        self.onSessionExpired = onSessionExpired
    }

    var body: some View {
        ScrollView {
            ScrollOffsetSentinel()
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("School life").font(UberFont.text(26, weight: .heavy))
                        Text("Events and schedule changes")
                            .font(UberFont.text(14)).foregroundStyle(EduFlowPalette.inkMuted(scheme))
                    }
                    Spacer()
                    IconButton(
                        icon: "arrow.clockwise",
                        label: NSLocalizedString("common_refresh", value: "Refresh", comment: "Aktion: neu laden"),
                        disabled: vm.isLoading
                    ) {
                        Task { await vm.load(refresh: true, onSessionExpired: onSessionExpired) }
                    }
                }
                UberSegmented(options: SchoolTab.allCases, selection: $tab) { $0.displayName }
                // Offline-Hinweis: Termine bleiben lesbar, nur ihre
                // Herkunft wird benannt.
                if vm.cachedAt != nil {
                    OfflineNotice(savedAt: vm.cachedAt)
                }
                if let error = vm.error {
                    Text(error.message)
                        .font(UberFont.text(13, weight: .medium))
                        .foregroundStyle(.red)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.red.opacity(0.08))
                        .clipShape(.rect(cornerRadius: 12))
                }
                if tab == .substitutions {
                    HStack {
                        PillButton(NSLocalizedString("school_prev_week", value: "← Previous week", comment: "Schule: Woche zurück"), style: .smallLight) {
                            Task { await vm.moveWeek(-1, onSessionExpired: onSessionExpired) }
                        }
                        Spacer()
                        Text(weekLabel(vm.selectedDay)).font(UberFont.text(12, weight: .semibold))
                        Spacer()
                        PillButton(NSLocalizedString("school_next_week", value: "Next →", comment: "Schule: Woche weiter"), style: .smallLight) {
                            Task { await vm.moveWeek(1, onSessionExpired: onSessionExpired) }
                        }
                    }
                }
                if vm.isLoading && vm.agenda.isEmpty && vm.substitutions.isEmpty {
                    ProgressView().frame(maxWidth: .infinity).padding(40)
                } else if tab == .agenda {
                    agendaContent
                } else {
                    substitutionsContent
                }
            }
            .padding(22)
            .frame(maxWidth: 1100, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(EduFlowPalette.canvas(scheme))
        .navigationTitle(NSLocalizedString("school_nav", value: "Events & substitutions", comment: "Schule: Titel"))
        .task { await vm.load(onSessionExpired: onSessionExpired) }
        .refreshable { await vm.load(refresh: true, onSessionExpired: onSessionExpired) }
    }

    @ViewBuilder private var agendaContent: some View {
        if vm.agenda.isEmpty {
            emptyCard(NSLocalizedString("No school events or exams in this period.", value: "No school events or exams in this period.", comment: "Schule: keine Termine"))
        } else {
            ForEach(vm.agenda) { item in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(kindTitle(item.kind)).font(UberFont.text(10, weight: .bold)).tracking(1)
                            .foregroundStyle(EduFlowPalette.inkMuted(scheme))
                        Spacer()
                        Text(item.date).font(UberFont.text(12, weight: .semibold))
                    }
                    Text(item.title.isEmpty ? (item.text.isEmpty ? item.typeLabel : item.text) : item.title)
                        .font(UberFont.text(15, weight: .semibold))
                    let details = [item.subject, item.typeLabel, item.author]
                        .filter { !$0.isEmpty }.joined(separator: " · ")
                    if !details.isEmpty {
                        Text(details).font(UberFont.text(12)).foregroundStyle(EduFlowPalette.inkMuted(scheme))
                    }
                }
                .padding(15)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(EduFlowPalette.card(scheme))
                .clipShape(.rect(cornerRadius: 14))
                .overlay { RoundedRectangle(cornerRadius: 14).stroke(EduFlowPalette.border(scheme), lineWidth: 1) }
            }
        }
    }

    @ViewBuilder private var substitutionsContent: some View {
        let daysWithChanges = vm.substitutions.filter { !$0.changes.isEmpty }
        if daysWithChanges.isEmpty {
            emptyCard(NSLocalizedString("No substitutions scheduled for this week.", value: "No substitutions scheduled for this week.", comment: "Schule: keine Vertretungen"))
        } else {
            ForEach(daysWithChanges) { day in
                VStack(alignment: .leading, spacing: 8) {
                    Text(day.dayLabel).font(UberFont.text(13, weight: .bold))
                    ForEach(day.changes) { change in
                        HStack(spacing: 12) {
                            Text(change.lesson).font(UberFont.text(12, weight: .heavy))
                                .frame(width: 54, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(change.title).font(UberFont.text(14, weight: .semibold))
                                Text(change.schoolClass.isEmpty
                                    ? NSLocalizedString("school_plan_change", value: "Timetable change", comment: "Schule: Änderung ohne Klasse")
                                    : String(format: NSLocalizedString("school_class_format", value: "Class %@", comment: "Schule: Klasse"), change.schoolClass)).font(UberFont.text(12))
                                    .foregroundStyle(EduFlowPalette.inkMuted(scheme))
                            }
                            Spacer()
                            Text(actionLabel(change.action)).font(UberFont.text(10, weight: .bold))
                                .foregroundStyle(change.action == "remove" ? .red : EduFlowPalette.inkMuted(scheme))
                        }
                        .padding(12)
                        .background(EduFlowPalette.card(scheme))
                        .clipShape(.rect(cornerRadius: 12))
                    }
                }
            }
        }
    }

    private func emptyCard(_ text: String) -> some View {
        Text(LocalizedStringKey(text)).font(UberFont.text(14)).foregroundStyle(EduFlowPalette.inkMuted(scheme))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(EduFlowPalette.card(scheme))
            .clipShape(.rect(cornerRadius: 14))
    }

    private func kindTitle(_ kind: String) -> String {
        switch kind {
        case "exam": return NSLocalizedString("school_kind_exam", value: "TEST / EXAM", comment: "Schule: Prüfungsart")
        case "attendance": return NSLocalizedString("school_kind_attendance", value: "ATTENDANCE", comment: "Schule: Anwesenheit")
        default: return NSLocalizedString("school_kind_event", value: "SCHOOL EVENT", comment: "Schule: Schultermin")
        }
    }

    private func actionLabel(_ action: String) -> String {
        switch action {
        case "add": return NSLocalizedString("school_action_add", value: "NEW", comment: "Schule: neu")
        case "remove": return NSLocalizedString("school_action_remove", value: "CANCELLED", comment: "Schule: entfällt")
        default: return NSLocalizedString("school_action_changed", value: "CHANGED", comment: "Schule: geändert")
        }
    }

    private func weekLabel(_ day: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "dd.MM.yyyy"
        return String(format: NSLocalizedString("school_week_from", value: "Week of %@", comment: "Schule: Wochenlabel"), formatter.string(from: day))
    }
}
