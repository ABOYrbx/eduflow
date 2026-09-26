import Foundation

/// Einstellungs- und Geräte-Repository (Paket A, nur gegen Paket 0).
public struct SettingsRepository: Sendable {
    public let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    /// Einstellungen lesen (Schema plus typisierte Werte mit Defaults).
    public func load() async throws -> (schema: [SettingSpec], values: SettingsValues) {
        let data = try await client.get(APIClient.Paths.settings)
        let response = try APIClient.decode(SettingsResponse.self, from: data)
        return (response.schema, SettingsValues.from(response.values))
    }

    /// Einstellungen speichern (Booleans als echte JSON-Bools, wie
    /// `api/settings.py`; Antwort ohne Schema wird toleriert).
    @discardableResult
    public func save(_ values: SettingsValues) async throws -> SettingsValues {
        let body = try APIClient.jsonData([
            "landing": values.landing,
            "hw_status": values.hwStatus,
            "hw_tests": values.hwTests,
            "ov_unread": values.ovUnread,
            "ov_homework": values.ovHomework,
            "ov_order": values.ovOrder,
            "ov_wetter": values.ovWetter,
            "wetter_city": values.wetterCity,
        ] as [String: Any])
        let data = try await client.put(APIClient.Paths.settings, body: body)
        let response = try APIClient.decode(SettingsResponse.self, from: data)
        return SettingsValues.from(response.values)
    }

    /// Cache leeren (meldet die Anzahl, Einstellungen bleiben erhalten).
    @discardableResult
    public func clearCache() async throws -> Int {
        let data = try await client.post(APIClient.Paths.cacheClear)
        return try APIClient.decode(CacheClearResult.self, from: data).cleared
    }

    /// Eigene Geräte (Tokens ohne Secrets, neueste zuerst).
    public func devices() async throws -> [DeviceInfo] {
        let data = try await client.get(APIClient.Paths.devices)
        return try APIClient.decode(DevicesResponse.self, from: data).items
    }

    /// Gerät gezielt widerrufen (Besitzschutz serverseitig).
    public func revokeDevice(id: String) async throws {
        let data = try await client.delete(APIClient.Paths.device(id))
        _ = try APIClient.decode(StatusResponse.self, from: data)
    }
}
