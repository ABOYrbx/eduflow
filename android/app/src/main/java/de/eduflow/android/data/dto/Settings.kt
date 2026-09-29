package de.eduflow.android.data.dto

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonPrimitive

/**
 * Einstellungen 1:1 zum Web-Schema (app.py SETTINGS_SCHEMA).
 * kinds: select / bool / int. Server liefert {schema, values},
 * PUT nimmt ein flaches Objekt (Booleans als echte JSON-bools).
 */
@Serializable
data class SettingsResponse(
    val schema: List<SettingSpec> = emptyList(),
    val values: Map<String, JsonElement> = emptyMap(),
)

@Serializable
data class SettingSpec(
    val key: String = "",
    val kind: String = "text",
    val label: String = "",
    val options: List<List<String>> = emptyList(),
    val default: JsonElement? = null,
    val min: Int? = null,
    val max: Int? = null,
    val hint: String = "",
)

@Serializable
data class CacheClearResponse(
    val status: String = "ok",
    val cleared: Int = 0,
)

/** Clientseitige Defaults = SETTINGS_DEFAULTS (app.py). */
object SettingsDefaults {
    const val LANDING = "uebersicht"
    const val HW_STATUS = "alle"
    const val HW_TESTS = false
    const val OV_UNREAD = 10
    const val OV_HOMEWORK = 10
    const val OV_ORDER = "messages,homework,weather"
    const val OV_WETTER = true
    const val WETTER_CITY = ""
    const val WETTER_CITY_MAX = 100
    const val TIME_FORMAT = "24h"

    val LANDING_OPTIONS = listOf("uebersicht", "dashboard", "hausaufgaben", "noten", "stundenplan")
    val HW_STATUS_OPTIONS = listOf("alle", "offen", "überfällig", "erledigt", "papierkorb")
    val TIME_FORMAT_OPTIONS = listOf("24h", "12h")
}

/** Typisierte Sicht auf die rohen Server-Werte (mit Fallback auf Defaults). */
data class SettingsValues(
    val landing: String = SettingsDefaults.LANDING,
    val hwStatus: String = SettingsDefaults.HW_STATUS,
    val hwTests: Boolean = SettingsDefaults.HW_TESTS,
    val ovUnread: Int = SettingsDefaults.OV_UNREAD,
    val ovHomework: Int = SettingsDefaults.OV_HOMEWORK,
    val ovOrder: String = SettingsDefaults.OV_ORDER,
    val ovWetter: Boolean = SettingsDefaults.OV_WETTER,
    val wetterCity: String = SettingsDefaults.WETTER_CITY,
    val timeFormat: String = SettingsDefaults.TIME_FORMAT,
)

fun SettingsResponse.typedValues(): SettingsValues {
    fun str(key: String, fallback: String, valid: List<String>? = null): String {
        val raw = values[key]?.jsonPrimitive?.content ?: return fallback
        return if (valid == null || raw in valid) raw else fallback
    }
    fun bool(key: String, fallback: Boolean): Boolean {
        val el = values[key] ?: return fallback
        return el.jsonPrimitive.booleanOrNull
            ?: (el.jsonPrimitive.content in listOf("1", "true", "on"))
    }
    fun intClamped(key: String, fallback: Int, min: Int, max: Int): Int {
        val raw = values[key]?.jsonPrimitive?.intOrNull ?: return fallback
        return raw.coerceIn(min, max)
    }
    /** Text wie _coerce_setting (app.py): trimmen, einzeilig, maxlength. */
    fun text(key: String, fallback: String, max: Int): String {
        val raw = try {
            values[key]?.jsonPrimitive?.content
        } catch (_: Exception) {
            null
        } ?: return fallback
        return raw.replace("\n", " ").replace("\r", "").trim().take(max)
    }
    return SettingsValues(
        landing = str("landing", SettingsDefaults.LANDING, SettingsDefaults.LANDING_OPTIONS),
        hwStatus = str("hw_status", SettingsDefaults.HW_STATUS, SettingsDefaults.HW_STATUS_OPTIONS),
        hwTests = bool("hw_tests", SettingsDefaults.HW_TESTS),
        ovUnread = intClamped("ov_unread", SettingsDefaults.OV_UNREAD, 1, 50),
        ovHomework = intClamped("ov_homework", SettingsDefaults.OV_HOMEWORK, 1, 50),
        ovOrder = text("ov_order", SettingsDefaults.OV_ORDER, 100),
        ovWetter = bool("ov_wetter", SettingsDefaults.OV_WETTER),
        wetterCity = text("wetter_city", SettingsDefaults.WETTER_CITY, SettingsDefaults.WETTER_CITY_MAX),
        timeFormat = str("time_format", SettingsDefaults.TIME_FORMAT, SettingsDefaults.TIME_FORMAT_OPTIONS),
    )
}
