import Combine
import Foundation

// MARK: - Noten-ViewModel (Paket E, Cache-Reihenfolge + Schnitt)
//
// Liste in Cache-Reihenfolge vom Server (keine eigenen Filter an die
// API — Gruppierung clientseitig wie Web-noten()). Paginierung:
// initial limit=50, Mehr laden via offset. Halbjahr-Tabs + Suche
// filtern die geladenen Einträge lokal (wie Android).

/// Fachgruppe (Fächer alphabetisch, Noten neueste zuerst).
struct SubjectGroup: Identifiable {
    let subject: String
    let items: [GradeItem]
    let avg: Double?

    var id: String { subject }
}

@MainActor
final class GradesViewModel: ObservableObject {
    @Published var items: [GradeItem] = []
    @Published var total = 0
    @Published var cacheInfo = ""
    @Published var terms: [GradeTerm] = [GradeTerm()]
    @Published var term = "alle"
    @Published var query = ""
    @Published var isLoading = false
    @Published var isLoadingMore = false
    @Published var error: APIError?
    @Published var canLoadMore = false

    let fallbackTerm: String

    /// Geladene Einträge nach Halbjahr + Suche (Fach/Thema/Lehrer).
    var filtered: [GradeItem] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return items.filter { item in
            (term == "alle" || GradeTerms.key(for: item.dateIso, fallback: fallbackTerm) == term) &&
            (q.isEmpty ||
                [item.subject, item.title, item.teacher].compactMap { $0 }
                    .joined(separator: " ").lowercased().contains(q))
        }
    }

    var groups: [SubjectGroup] {
        let grouped = Dictionary(grouping: filtered) {
            ($0.subject?.nilIfEmpty) ?? "Sonstiges"
        }
        return grouped.keys
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            .map { subject in
                let sorted = (grouped[subject] ?? []).sorted {
                    ($0.sortKey ?? $0.dateIso ?? "") > ($1.sortKey ?? $1.dateIso ?? "")
                }
                return SubjectGroup(subject: subject, items: sorted,
                                    avg: GradesAverage.of(sorted))
            }
    }

    var average: Double? { GradesAverage.of(filtered) }

    private let service: GradesService
    private static let pageSize = 50

    init(service: GradesService) {
        self.service = service
        self.fallbackTerm = GradeTerms.currentFallback
    }

    func refresh() async {
        isLoading = true
        self.error = nil
        do {
            let page = try await service.list(limit: Self.pageSize, offset: 0, refresh: true)
            apply(page: page)
        } catch let e as APIError {
            self.error = e
        } catch {
            self.error = APIError(code: "UPSTREAM", message: APIError.message(for: "UPSTREAM"), httpStatus: 0)
        }
        isLoading = false
    }

    func loadMore() async {
        guard !isLoading, !isLoadingMore, canLoadMore else { return }
        isLoadingMore = true
        do {
            let page = try await service.list(limit: Self.pageSize, offset: items.count)
            items += page.items
            total = page.total
            cacheInfo = page.cacheInfo ?? ""
            rebuildTerms()
            canLoadMore = items.count < page.total
        } catch let e as APIError {
            self.error = e
        } catch {
            self.error = APIError(code: "UPSTREAM", message: APIError.message(for: "UPSTREAM"), httpStatus: 0)
        }
        isLoadingMore = false
    }

    private func apply(page: GradesListResponse) {
        items = page.items
        total = page.total
        cacheInfo = page.cacheInfo ?? ""
        rebuildTerms()
        isLoading = false
        canLoadMore = page.items.count < page.total
    }

    private func rebuildTerms() {
        terms = GradeTerms.build(from: items, fallback: fallbackTerm)
        let keys = Set(terms.map(\.key))
        // Wie Web: ungültiges/aktuelles Halbjahr ohne Noten → neuestes mit Noten.
        if !keys.contains(term) {
            if keys.contains(fallbackTerm) {
                term = fallbackTerm
            } else {
                term = terms.first(where: { $0.key != "alle" })?.key ?? "alle"
            }
        }
    }
}
