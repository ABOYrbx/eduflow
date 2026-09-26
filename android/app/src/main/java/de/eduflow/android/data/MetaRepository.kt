package de.eduflow.android.data

import de.eduflow.android.data.dto.EssenResponse
import de.eduflow.android.data.dto.WetterResponse
import kotlinx.serialization.json.decodeFromJsonElement

/**
 * Essen/Wetter-Repository (Paket D, nur gegen frozen [ApiService]).
 *
 * Essen: GET /essen (refresh=1 lädt das PDF neu). Braucht kein
 * EduPage-Login (öffentliche Quelle plus Wochen-Cache).
 * Wetter: GET /wetter mit ?lat=..&lon=.. oder ?city=.. (Schlüssel
 * bleibt serverseitig). Fehlercodes wie im Backend (api/meta.py):
 * VALIDATION ohne Ort, CONFIG_MISSING ohne Schlüssel, UPSTREAM sonst.
 */
class MetaRepository(
    private val api: () -> ApiService,
) {
    suspend fun essen(
        refresh: Boolean = false,
    ): Result<EssenResponse> = runCatching {
        val raw = api().essen(
            refresh = if (refresh) 1 else null,
        ).unwrap()
        EduFlowJson.decodeFromJsonElement(EssenResponse.serializer(), raw)
    }

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
