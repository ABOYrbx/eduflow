import Foundation

/// Wetter-Repository (Paket D, nur gegen Paket 0).
///
/// Essensplan (Paket D): ENTFÄLLT im NestJS-Stand. Das Backend stellt keine
/// Essens-Route bereit (kein `/essen` in `SchoolController`/`openapi.json`,
/// keine Essens-UI im Web); daher gibt es bewusst kein Essens-Repository,
/// keinen Wochenplan mit Preisen/Quelle/PDF-Link und keinen
/// Essen-heute-Pager in der Übersicht. Sollte das Backend je eine
/// Essens-Route liefern, hier ein Repository mit Upstream-Fehler plus
/// Cache-Fallback ergänzen (kein erfundenes Format, kein Backend-Eingriff).
public struct MetaRepository: Sendable {
    public let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    /// Wetter (Stadt aus den Einstellungen; Koordinaten optional wie
    /// im Backend; ohne Ort clientseitig Validierung).
    public func wetter(city: String, lat: Double? = nil, lon: Double? = nil) async throws -> WetterResponse {
        var items: [URLQueryItem] = []
        if let lat, let lon {
            items.append(URLQueryItem(name: "lat", value: String(lat)))
            items.append(URLQueryItem(name: "lon", value: String(lon)))
        } else {
            let trimmed = city.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw APIError(
                    code: ErrorCodes.validation,
                    message: NSLocalizedString("overview_city_missing", value: "Please enter a city in settings.", comment: "Übersicht: Stadt fehlt")
                )
            }
            items.append(URLQueryItem(name: "city", value: trimmed))
        }
        let data = try await client.get(APIClient.Paths.wetter, query: items)
        return try APIClient.decode(WetterResponse.self, from: data)
    }
}
