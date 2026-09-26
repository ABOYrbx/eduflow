package de.eduflow.android.data.dto

import kotlinx.serialization.Serializable

/**
 * Stunde 1:1 zum Web-Bauer (app.py lesson_to_dict + merge_lernzeit).
 *
 * Tag: GET /api/v1/timetable/day -> TimetableDayResponse
 * Woche: GET /api/v1/timetable/week -> TimetableWeekResponse
 * (siehe api/timetable.py, BACKEND.md §6 / Paket D).
 *
 * Lernzeit-Blöcke kommen bereits zusammengefasst vom Server
 * (period "2–3", rowspan > 1, wie im Web).
 */
@Serializable
data class LessonDto(
    val period: String = "",
    val time: String = "",
    val title: String = "",
    val is_lernzeit: Boolean = false,
    val teachers: String = "",
    val rooms: String = "",
    val is_cancelled: Boolean = false,
    val is_event: Boolean = false,
    val is_online: Boolean = false,
    val row_period: String = "",
    val rowspan: Int = 1,
)

/** Tagesansicht: Tag, deutsche Bezeichnung, Vor-/Folgetag, Stunden. */
@Serializable
data class TimetableDayResponse(
    val day: String = "",
    val day_label: String = "",
    val prev_day: String = "",
    val next_day: String = "",
    val today: String = "",
    val lessons: List<LessonDto> = emptyList(),
    val cache_info: String = "",
)

/** Ein Wochentag in der Wochenansicht (Mo–Fr, Events herausgefiltert). */
@Serializable
data class TimetableWeekDay(
    val date: String = "",
    val day_name: String = "",
    val day_date: String = "",
    val is_today: Boolean = false,
    val lessons: List<LessonDto> = emptyList(),
)

/** Wochenansicht: Montag, Wochenbezeichnung, Mo–Fr mit Tagesobjekten. */
@Serializable
data class TimetableWeekResponse(
    val day: String = "",
    val monday: String = "",
    val week_label: String = "",
    val days: List<TimetableWeekDay> = emptyList(),
    val cache_info: String = "",
)

/** Ansichten wie im Web (/stundenplan?view=day|week). */
object TimetableView {
    const val DAY = "day"
    const val WEEK = "week"
}
