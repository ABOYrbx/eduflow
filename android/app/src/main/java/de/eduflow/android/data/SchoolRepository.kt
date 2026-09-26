package de.eduflow.android.data

import de.eduflow.android.data.dto.SchoolAgendaResponseDto
import de.eduflow.android.data.dto.SubstitutionWeekDto
import kotlinx.serialization.json.decodeFromJsonElement

class SchoolRepository(private val api: () -> ApiService) {
    suspend fun agenda(since: String, until: String, refresh: Boolean = false): Result<SchoolAgendaResponseDto> =
        runCatching {
            val raw = api().schoolAgenda(
                since = since,
                until = until,
                refresh = if (refresh) 1 else null,
            ).unwrap()
            EduFlowJson.decodeFromJsonElement(SchoolAgendaResponseDto.serializer(), raw)
        }

    suspend fun substitutions(day: String): Result<SubstitutionWeekDto> = runCatching {
        val raw = api().substitutionsWeek(day).unwrap()
        EduFlowJson.decodeFromJsonElement(SubstitutionWeekDto.serializer(), raw)
    }
}
