import Foundation
import SwiftUI

struct SchoolAgendaItem: Decodable, Identifiable, Sendable {
    var id: Int = 0
    var kind = "event"
    var date = ""
    var title = ""
    var text = ""
    var subject = ""
    var typeLabel = ""
    var author = ""

    private enum CodingKeys: String, CodingKey {
        case id, kind, date, title, text, subject, typeLabel
        case author
    }
}

private struct SchoolAgendaResponse: Decodable, Sendable {
    var items: [SchoolAgendaItem] = []
    var total = 0
}

struct SchoolSubstitution: Decodable, Identifiable, Sendable {
    var schoolClass = ""
    var lesson = ""
    var title = ""
    var action = ""

    var id: String { "\(schoolClass)-\(lesson)-\(title)-\(action)" }

    private enum CodingKeys: String, CodingKey {
        case schoolClass = "class"
        case lesson, title, action
    }
}

struct SchoolSubstitutionDay: Decodable, Identifiable, Sendable {
    var date = ""
    var dayLabel = ""
    var changes: [SchoolSubstitution] = []
    var id: String { date }
}

private struct SchoolSubstitutionResponse: Decodable, Sendable {
    var days: [SchoolSubstitutionDay] = []
}

private struct SchoolRepository: Sendable {
    let client: APIClient

    func agenda(day: Date, refresh: Bool) async throws -> [SchoolAgendaItem] {
        let start = Calendar.current.date(byAdding: .day, value: -30, to: day) ?? day
        let end = Calendar.current.date(byAdding: .day, value: 60, to: day) ?? day
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        let data = try await client.get(APIClient.Paths.schoolAgenda, query: [
            URLQueryItem(name: "since", value: formatter.string(from: start)),
            URLQueryItem(name: "until", value: formatter.string(from: end)),
            URLQueryItem(name: "refresh", value: refresh ? "1" : "0"),
        ])
        return try APIClient.decode(SchoolAgendaResponse.self, from: data).items
    }

    func substitutions(day: Date) async throws -> [SchoolSubstitutionDay] {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        let data = try await client.get(APIClient.Paths.substitutionsWeek, query: [
            URLQueryItem(name: "day", value: formatter.string(from: day)),
        ])
        return try APIClient.decode(SchoolSubstitutionResponse.self, from: data).days
    }
}

@MainActor
@Observable
private final class SchoolViewModel {
    var agenda: [SchoolAgendaItem] = []
    var substitutions: [SchoolSubstitutionDay] = []
    var error: APIError?
    var isLoading = false
    var selectedDay = Calendar.current.dateInterval(of: .weekOfYear, for: Date())?.start
        ?? Calendar.current.startOfDay(for: Date())
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
        case .success(let value): self.agenda = value
        case .failure(let apiError): self.error = apiError
        }
        switch substitutions {
        case .success(let value): self.substitutions = value
        case .failure(let apiError): self.error = self.error ?? apiError
        }
        if let error, SessionRecovery.forceLogout(error: error, isLoggedIn: store.isLoggedIn) {
            store.clear()
            onSessionExpired()
        }
    }

    func moveWeek(_ offset: Int, onSessionExpired: () -> Void) async {
        selectedDay = Calendar.current.date(byAdding: .weekOfYear, value: offset, to: selectedDay) ?? selectedDay
        await load(onSessionExpired: onSessionExpired)
    }

    private static func capture<T: Sendable>(
        _ work: @Sendable () async throws -> T
    ) async -> Result<T, APIError> {
        do { return .success(try await work()) }
        catch let error as APIError { return .failure(error) }
        catch { return .failure(APIError(code: ErrorCodes.upstream,
                                        message: APIError.germanFallback(for: ErrorCodes.upstream))) }
    }
}

private enum SchoolTab: String, CaseIterable, Identifiable {
    case agenda = "Kalender"
    case substitutions = "Vertretungen"
    var id: String { rawValue }
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
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Schulalltag").font(UberFont.text(26, weight: .heavy))
                        Text("Termine und Planänderungen")
                            .font(UberFont.text(14)).foregroundStyle(EduFlowPalette.inkMuted(scheme))
                    }
                    Spacer()
                    Button { Task { await vm.load(refresh: true, onSessionExpired: onSessionExpired) } } label: {
                        Image(systemName: "arrow.clockwise").font(.system(size: 15, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                    .disabled(vm.isLoading)
                }
                Picker("Bereich", selection: $tab) {
                    ForEach(SchoolTab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
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
                        Button("← Vorwoche") { Task { await vm.moveWeek(-1, onSessionExpired: onSessionExpired) } }
                        Spacer()
                        Text(weekLabel(vm.selectedDay)).font(UberFont.text(12, weight: .semibold))
                        Spacer()
                        Button("Nächste →") { Task { await vm.moveWeek(1, onSessionExpired: onSessionExpired) } }
                    }
                    .buttonStyle(.bordered)
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
        .navigationTitle("Termine & Vertretungen")
        .task { await vm.load(onSessionExpired: onSessionExpired) }
        .refreshable { await vm.load(refresh: true, onSessionExpired: onSessionExpired) }
    }

    @ViewBuilder private var agendaContent: some View {
        if vm.agenda.isEmpty {
            emptyCard("Keine Schultermine oder Prüfungen in diesem Zeitraum.")
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
            emptyCard("Für diese Woche sind keine Vertretungen eingetragen.")
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
                                Text("Klasse \(change.schoolClass)").font(UberFont.text(12))
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
        Text(text).font(UberFont.text(14)).foregroundStyle(EduFlowPalette.inkMuted(scheme))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(EduFlowPalette.card(scheme))
            .clipShape(.rect(cornerRadius: 14))
    }

    private func kindTitle(_ kind: String) -> String {
        switch kind {
        case "exam": "TEST / PRÜFUNG"
        case "attendance": "ANWESENHEIT"
        default: "SCHULTERMIN"
        }
    }

    private func actionLabel(_ action: String) -> String {
        switch action {
        case "add": "NEU"
        case "remove": "ENTFÄLLT"
        default: "GEÄNDERT"
        }
    }

    private func weekLabel(_ day: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "dd.MM.yyyy"
        return "Woche ab " + formatter.string(from: day)
    }
}
