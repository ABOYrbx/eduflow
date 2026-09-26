package de.eduflow.android.data

import de.eduflow.android.data.dto.CacheClearResponse
import de.eduflow.android.data.dto.SettingsResponse
import de.eduflow.android.data.dto.SettingsValues
import de.eduflow.android.data.dto.WetterCitySuggestion
import de.eduflow.android.data.dto.typedValues
import kotlinx.serialization.json.decodeFromJsonElement
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject

/** Einstellungen + Cache (Paket A/G, Parität mit Web). */
class SettingsRepository(private val api: () -> ApiService) {

    suspend fun load(): Pair<SettingsResponse, SettingsValues> {
        val res = api().getSettings().unwrap()
        return res to res.typedValues()
    }

    /** Werte speichern (Booleans als echte JSON-bools, wie api/settings.py). */
    suspend fun save(values: SettingsValues): SettingsValues {
        val body = buildJsonObject {
            put("landing", JsonPrimitive(values.landing))
            put("hw_status", JsonPrimitive(values.hwStatus))
            put("hw_tests", JsonPrimitive(values.hwTests))
            put("ov_unread", JsonPrimitive(values.ovUnread))
            put("ov_homework", JsonPrimitive(values.ovHomework))
            put("ov_order", JsonPrimitive(values.ovOrder))
            put("ov_wetter", JsonPrimitive(values.ovWetter))
            put("wetter_city", JsonPrimitive(values.wetterCity))
        }
        val res = api().putSettings(body).unwrap()
        return res.typedValues()
    }

    /** Live-Suche; Wetterdienst-Schlüssel bleiben vollständig auf dem Server. */
    suspend fun searchWetterCities(query: String): List<WetterCitySuggestion> {
        val raw = api().searchWetterCities(query).unwrap()
        return raw["items"]?.jsonArray.orEmpty().mapNotNull { item ->
            runCatching {
                EduFlowJson.decodeFromJsonElement(WetterCitySuggestion.serializer(), item)
            }.getOrNull()
        }
    }

    suspend fun clearCache(): CacheClearResponse = api().clearCache().unwrap()
}
