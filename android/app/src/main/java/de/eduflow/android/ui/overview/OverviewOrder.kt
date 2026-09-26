package de.eduflow.android.ui.overview

import de.eduflow.android.data.dto.SettingsDefaults

/** Movable overview sections; the order string is stored with account settings. */
object OverviewOrder {
    val keys = listOf("messages", "homework", "weather", "lunch")
    val labels = mapOf(
        "messages" to "Nachrichten",
        "homework" to "Hausaufgaben",
        "weather" to "Wetter",
        "lunch" to "Mittagessen",
    )

    fun parse(raw: String): List<String> {
        val parsed = raw.split(',').map(String::trim).filter { it in keys }.distinct()
        return parsed + keys.filterNot(parsed::contains)
    }

    fun serialize(keys: List<String>): String = parse(keys.joinToString(",")).joinToString(",")

    fun move(keys: List<String>, from: Int, by: Int): List<String> {
        val target = (from + by).coerceIn(0, keys.lastIndex)
        if (target == from) return keys
        return keys.toMutableList().apply { add(target, removeAt(from)) }
    }

    val default: List<String> = parse(SettingsDefaults.OV_ORDER)
}
