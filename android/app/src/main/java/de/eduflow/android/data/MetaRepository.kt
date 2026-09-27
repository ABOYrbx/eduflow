package de.eduflow.android.data

import de.eduflow.android.data.dto.WetterResponse
import kotlinx.serialization.json.decodeFromJsonElement

/**
 * Wetter-Repository (Paket D, nur gegen frozen [ApiService]).
 *
 * Wetter: GET /wetter mit ?lat=..&lon=.. oder ?city=.. (Schlüssel
 * bleibt serverseitig). Fehlercodes wie im Backend (api/meta.py):
 * VALIDATION ohne Ort, CONFIG_MISSING ohne Schlüssel, UPSTREAM sonst.
 */
class MetaRepository(
    private val api: () -> ApiService,
) {
    suspend fun wetter(
        lat: Double? = null,
        lon: Double? = null,
        city: String? = null,
    ): Result<WetterResponse> = runCatching {
        val raw = api().wetter(
            lat = lat,
            lon = lon,
            city = city?.takeIf { it.isNotBlank() },
        ).unwrap()
        EduFlowJson.decodeFromJsonElement(WetterResponse.serializer(), raw)
    }
}
