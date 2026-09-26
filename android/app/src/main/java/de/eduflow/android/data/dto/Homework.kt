package de.eduflow.android.data.dto

import kotlinx.serialization.Serializable

/**
 * Hausaufgabe 1:1 zum Web-Bauer (app.py homework_to_dict + mark_hidden).
 *
 * Liste: GET /api/v1/homework -> HomeworkListResponse
 * Schreiben: POST /homework/{id}/done -> HomeworkDto,
 *            POST /homework/{id}/trash -> HomeworkDto
 * (siehe api/homework.py, BACKEND.md §5 / Paket C).
 */
@Serializable
data class HomeworkDto(
    val id: Long = 0L,
    val type: String = "",
    val type_label: String = "",
    val title: String = "",
    val description: String = "",
    val subject: String = "",
    val author: String = "",
    val recipient: String = "",
    val assigned: String = "",
    val assigned_iso: String = "",
    val due: String = "",
    val due_display: String = "",
    val due_raw: String = "",
    val status: String = "",
    val status_class: String = "",
    val tag_class: String = "",
    val is_done: Boolean = false,
    val done_at: String = "",
    val is_starred: Boolean = false,
    val is_hidden: Boolean = false,
    val extra: String = "",
)

/**
 * Zähler wie im Web (api/homework.py _build_view):
 * offen zählt offen + heute fällig, ohne Papierkorb.
 * ACHTUNG: JSON-Key ist ascii "ueberfaellig" (ohne Umlaut).
 */
@Serializable
data class HomeworkCounts(
    val offen: Int = 0,
    val ueberfaellig: Int = 0,
    val erledigt: Int = 0,
    val papierkorb: Int = 0,
)

/** Listen-Antwort: Page-Hülle + Zähler + Cache-Info. */
@Serializable
data class HomeworkListResponse(
    val items: List<HomeworkDto> = emptyList(),
    val total: Int = 0,
    val limit: Int = 50,
    val offset: Int = 0,
    val counts: HomeworkCounts = HomeworkCounts(),
    val cache_info: String = "",
)

/** Statusfilter wie Web + API (?status=...). */
object HomeworkStatus {
    const val ALLE = "alle"
    const val OFFEN = "offen"
    const val UEBERFAELLIG = "überfällig"
    const val ERLEDIGT = "erledigt"
    const val PAPIERKORB = "papierkorb"

    val ALL = listOf(ALLE, OFFEN, UEBERFAELLIG, ERLEDIGT, PAPIERKORB)
}

/** Item-Statuswerte aus homework_to_dict (inkl. "heute fällig", "ohne Datum"). */
object HomeworkItemStatus {
    const val UEBERFAELLIG = "überfällig"
    const val HEUTE = "heute fällig"
    const val OFFEN = "offen"
    const val ERLEDIGT = "erledigt"
    const val OHNE_DATUM = "ohne Datum"
}
