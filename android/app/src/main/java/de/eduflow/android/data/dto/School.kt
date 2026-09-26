package de.eduflow.android.data.dto

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class SchoolAgendaItemDto(
    val id: Long = 0,
    val kind: String = "event",
    val date: String = "",
    val title: String = "",
    val text: String = "",
    val description: String = "",
    val subject: String = "",
    val type_label: String = "",
    val author: String = "",
    val timestamp: String = "",
)

@Serializable
data class SchoolAgendaResponseDto(
    val items: List<SchoolAgendaItemDto> = emptyList(),
    val total: Int = 0,
    val since: String = "",
    val until: String = "",
    val cache_info: String = "",
)

@Serializable
data class SubstitutionChangeDto(
    @SerialName("class") val schoolClass: String = "",
    val lesson: String = "",
    val title: String = "",
    val action: String = "",
)

@Serializable
data class SubstitutionDayDto(
    val date: String = "",
    val day_label: String = "",
    val changes: List<SubstitutionChangeDto> = emptyList(),
)

@Serializable
data class SubstitutionWeekDto(
    val monday: String = "",
    val week_label: String = "",
    val days: List<SubstitutionDayDto> = emptyList(),
)
