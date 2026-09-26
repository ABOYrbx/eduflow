package de.eduflow.android.data

import de.eduflow.android.data.dto.TimetableDayResponse
import de.eduflow.android.data.dto.TimetableWeekResponse
import kotlinx.serialization.json.decodeFromJsonElement

/**
 * Stundenplan-Repository (Paket D, nur gegen frozen [ApiService]).
 *
 * Parameter 1:1 wie die API (api/timetable.py):
 * day (YYYY-MM-DD, Standard heute), refresh (0/1).
 * Antwort-Dicts werden tolerant in typisierte DTOs
 * (data/dto/Timetable.kt) dekodiert; Fehler via ApiException
 * (data/ErrorMapper.kt unwrap).
 */
class TimetableRepository(
    private val api: () -> ApiService,
) {
    suspend fun day(
        day: String? = null,
        refresh: Boolean = false,
    ): Result<TimetableDayResponse> = runCatching {
        val raw = api().timetableDay(
            day = day?.takeIf { it.isNotBlank() },
            refresh = if (refresh) 1 else null,
        ).unwrap()
        EduFlowJson.decodeFromJsonElement(TimetableDayResponse.serializer(), raw)
    }

    suspend fun week(
        day: String? = null,
        refresh: Boolean = false,
    ): Result<TimetableWeekResponse> = runCatching {
        val raw = api().timetableWeek(
            day = day?.takeIf { it.isNotBlank() },
            refresh = if (refresh) 1 else null,
        ).unwrap()
        EduFlowJson.decodeFromJsonElement(TimetableWeekResponse.serializer(), raw)
    }
}
