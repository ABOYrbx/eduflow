package de.eduflow.android.data.repository

import de.eduflow.android.data.ApiService
import de.eduflow.android.data.EduFlowJson
import de.eduflow.android.data.dto.GradesListResponse
import de.eduflow.android.data.unwrap
import kotlinx.serialization.json.decodeFromJsonElement

/**
 * Noten-Repository (Paket C, nur gegen frozen [ApiService]).
 *
 * Parameter 1:1 wie die API (api/grades.py):
 * limit (1..200), offset, refresh (0/1).
 * Keine neuen Filter/Sortierung — Gruppierung (Halbjahr, Fach, Schnitt)
 * passiert clientseitig im ViewModel wie in der Web-Route noten().
 */
class GradesRepository(
    private val api: () -> ApiService,
) {
    suspend fun list(
        limit: Int = 50,
        offset: Int = 0,
        refresh: Boolean = false,
    ): Result<GradesListResponse> = runCatching {
        val raw = api().grades(
            limit = limit.coerceIn(1, 200),
            offset = offset.coerceAtLeast(0),
            refresh = if (refresh) 1 else 0,
        ).unwrap()
        EduFlowJson.decodeFromJsonElement(GradesListResponse.serializer(), raw)
    }
}
