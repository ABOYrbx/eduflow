package de.eduflow.android.data.dto

import kotlinx.serialization.KSerializer
import kotlinx.serialization.Serializable
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.JsonDecoder
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.longOrNull

/**
 * Note 1:1 zum Web-Bauer (app.py grade_to_dict).
 *
 * Liste: GET /api/v1/grades -> GradesListResponse (Cache-Reihenfolge,
 * keine neuen Filter/Sortierung, siehe api/grades.py, BACKEND.md §7).
 * Gruppierung (Halbjahr-Tabs, Fächer, Schnitt) passiert clientseitig
 * wie in der Web-Route noten() (grade_term_key, grades_average).
 */
object FlexibleStringSerializer : KSerializer<String> {
    override val descriptor: SerialDescriptor =
        PrimitiveSerialDescriptor("FlexibleString", PrimitiveKind.STRING)

    override fun deserialize(decoder: Decoder): String {
        val element = (decoder as? JsonDecoder)?.decodeJsonElement()
            ?: return decoder.decodeString()
        if (element is JsonPrimitive) {
            element.longOrNull?.let { return it.toString() }
            element.doubleOrNull?.let {
                return if (it % 1.0 == 0.0) it.toLong().toString() else it.toString()
            }
            element.booleanOrNull?.let { return it.toString() }
            if (element.isString) return element.content
        }
        return element.toString()
    }

    override fun serialize(encoder: Encoder, value: String) {
        encoder.encodeString(value)
    }
}

@Serializable
data class GradeDto(
    @Serializable(with = FlexibleStringSerializer::class)
    val id: String = "",
    val title: String = "",
    val subject: String = "Sonstiges",
    val teacher: String = "",
    val date_display: String = "",
    val date_iso: String = "",
    val sort_key: String = "",
    val comment: String = "",
    val grade_display: String = "",
    val grade_num: Double? = null,
    val weight: Double = 1.0,
    val weight_display: String = "",
    val grade_sub: String = "",
    val badge: String = "gx",
    val class_avg: Double? = null,
    val class_avg_display: String = "",
    val is_classic: Boolean = false,
)

/** Listen-Antwort: Page-Hülle + Cache-Info (api/grades.py). */
@Serializable
data class GradesListResponse(
    val items: List<GradeDto> = emptyList(),
    val total: Int = 0,
    val limit: Int = 50,
    val offset: Int = 0,
    val cache_info: String = "",
)

/** Halbjahr-Tab wie im Web (Noten-Seite, "alle" = Gesamt). */
@Serializable
data class GradeTerm(
    val key: String = "alle",
    val label: String = "Gesamt",
    val count: Int = 0,
)

/** Fachgruppe wie im Web (Fächer alphabetisch, Noten neueste zuerst). */
data class GradeSubjectGroup(
    val subject: String,
    val items: List<GradeDto>,
    val avg: Double?,
    val avgDisplay: String,
)

/** Zahl mit deutschem Dezimalkomma (app.py _de_num). */
fun deNum(value: Double?): String {
    if (value == null) return "–"
    val s = if (value % 1.0 == 0.0) value.toLong().toString() else value.toString()
    return s.replace(".", ",")
}

/** Gewichteter Schnitt über klassische 1–6-Noten (app.py grades_average). */
fun gradesAverage(items: List<GradeDto>): Double? {
    var total = 0.0
    var weights = 0.0
    for (i in items) {
        val v = i.grade_num ?: continue
        if (v < 1.0 || v > 6.0) continue
        val w = i.weight.takeIf { it > 0.0 } ?: 1.0
        total += v * w
        weights += w
    }
    if (weights <= 0.0) return null
    return kotlin.math.round(total / weights * 100.0) / 100.0
}

/** Aktueller Halbjahr-Key (app.py _current_term_key, Schuljahr Sept–Aug). */
fun currentTermKey(year: Int, month: Int): String {
    val sy = if (month >= 9) year else year - 1
    val half = if (month >= 9 || month == 1) 1 else 2
    return "$sy-H$half"
}

/** Notendatum -> Halbjahr-Key "2025-H1" (app.py grade_term_key). */
fun gradeTermKey(dateIso: String, fallback: String): String {
    val parts = dateIso.trim().split("-")
    if (parts.size < 3) return fallback
    val y = parts[0].toIntOrNull() ?: return fallback
    val m = parts[1].toIntOrNull() ?: return fallback
    if (m !in 1..12) return fallback
    return currentTermKey(y, m)
}

/** Halbjahr-Key -> deutsche Bezeichnung (app.py grade_term_label). */
fun gradeTermLabel(key: String): String {
    val parts = key.split("-H")
    if (parts.size != 2) return key
    val sy = parts[0].toIntOrNull() ?: return key
    val half = parts[1].toIntOrNull() ?: return key
    return "$half. Halbjahr ${sy.toString().takeLast(2)}/${(sy + 1).toString().takeLast(2)}"
}

/**
 * Halbjahre aus den geladenen Noten ableiten (neuestes zuerst) + "alle"
 * (app.py noten(): term_keys + Gesamt-Anhang).
 */
fun buildGradeTerms(items: List<GradeDto>, fallback: String): List<GradeTerm> {
    val counts = linkedMapOf<String, Int>()
    for (g in items) {
        val k = gradeTermKey(g.date_iso, fallback)
        counts[k] = (counts[k] ?: 0) + 1
    }
    val terms = counts.entries.sortedByDescending { it.key }.map { (k, c) ->
        GradeTerm(k, gradeTermLabel(k), c)
    } + GradeTerm("alle", "Gesamt", items.size)
    return terms
}

/** Nach Fach gruppieren wie im Web (alphabetisch, Noten neueste zuerst). */
fun groupGradesBySubject(items: List<GradeDto>): List<GradeSubjectGroup> {
    return items.groupBy { it.subject.ifBlank { "Sonstiges" } }
        .toSortedMap(String.CASE_INSENSITIVE_ORDER)
        .map { (subject, group) ->
            val sorted = group.sortedByDescending { it.sort_key }
            val avg = gradesAverage(sorted)
            GradeSubjectGroup(subject, sorted, avg, deNum(avg))
        }
}
