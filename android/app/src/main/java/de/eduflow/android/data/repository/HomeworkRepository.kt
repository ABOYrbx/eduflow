package de.eduflow.android.data.repository

import de.eduflow.android.data.ApiService
import de.eduflow.android.data.EduFlowJson
import de.eduflow.android.data.dto.HomeworkDto
import de.eduflow.android.data.dto.HomeworkListResponse
import de.eduflow.android.data.unwrap
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.decodeFromJsonElement

/**
 * Hausaufgaben-Repository (Paket C, nur gegen frozen [ApiService]).
 *
 * Parameter 1:1 wie die API (api/homework.py):
 * since (YYYY-MM-DD), status, includeTests (0/1), q (Suche),
 * limit (1..200), offset, refresh (0/1).
 * Antwort-Dicts werden tolerant in typisierte DTOs
 * (data/dto/Homework.kt) dekodiert; Fehler via ApiException
 * (data/ErrorMapper.kt unwrap).
 */
class HomeworkRepository(
    private val api: () -> ApiService,
) {
    suspend fun list(
        since: String? = null,
        status: String = "alle",
        includeTests: Boolean = false,
        q: String = "",
        limit: Int = 50,
        offset: Int = 0,
        refresh: Boolean = false,
    ): Result<HomeworkListResponse> = runCatching {
        val raw = api().homework(
            since = since?.takeIf { it.isNotBlank() },
            status = status,
            includeTests = if (includeTests) 1 else 0,
            q = q.takeIf { it.isNotBlank() },
            limit = limit.coerceIn(1, 200),
            offset = offset.coerceAtLeast(0),
            refresh = if (refresh) 1 else 0,
        ).unwrap()
        EduFlowJson.decodeFromJsonElement(HomeworkListResponse.serializer(), raw)
    }

    suspend fun setDone(id: Long, done: Boolean): Result<HomeworkDto> = runCatching {
        val body = buildJsonObject { put("done", JsonPrimitive(done)) }
        val raw = api().homeworkDone(id, body).unwrap()
        EduFlowJson.decodeFromJsonElement(HomeworkDto.serializer(), raw)
    }

    suspend fun setTrash(id: Long, hide: Boolean): Result<HomeworkDto> = runCatching {
        val body = buildJsonObject { put("hide", JsonPrimitive(hide)) }
        val raw = api().homeworkTrash(id, body).unwrap()
        EduFlowJson.decodeFromJsonElement(HomeworkDto.serializer(), raw)
    }
}
