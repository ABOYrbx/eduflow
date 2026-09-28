import Foundation

/// Wetter-Repository (Paket D, nur gegen Paket 0).
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
                    message: NSLocalizedString("overview_city_missing", value: "Bitte eine Stadt in den Einstellungen eintragen.", comment: "Übersicht: Stadt fehlt")
                )
            }
            items.append(URLQueryItem(name: "city", value: trimmed))
        }
        let data = try await client.get(APIClient.Paths.wetter, query: items)
        return try APIClient.decode(WetterResponse.self, from: data)
    }
}
