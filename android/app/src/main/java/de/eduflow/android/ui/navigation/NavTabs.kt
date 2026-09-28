package de.eduflow.android.ui.navigation

import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Assignment
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.Event
import androidx.compose.material.icons.filled.Grade
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.MailOutline
import androidx.compose.ui.res.stringResource
import de.eduflow.android.R

/**
 * Editierbare Navigationsleisten-Tabs (Paket F): Der Nutzer wählt in den
 * Einstellungen, welche Bereiche als Buttons erscheinen, und sortiert sie
 * um. Gespeichert als kommagetrennte Routen in DataStore (gerätemeutral
 * lesbar, gerätelokal — kein Server-State). Der Mehr-Tab ist fest
 * angepinnt (Abmelden/Geräte bleiben erreichbar) und zählt nicht zum Limit.
 */
object NavTabs {
    /** Alle umschaltbaren Inhalte (ohne den festen Mehr-Tab). */
    val candidates = listOf(
        Routes.OVERVIEW,
        Routes.HOMEWORK,
        Routes.MESSAGES,
        Routes.TIMETABLE,
        Routes.GRADES,
        Routes.SCHOOL,
    )

    /** Mehr als fünf Inhalte passen nicht sinnvoll in die Pille. */
    const val MAX_CONTENT = 5

    val labelRes = mapOf(
        Routes.OVERVIEW to R.string.bottom_home,
        Routes.HOMEWORK to R.string.bottom_tasks,
        Routes.MESSAGES to R.string.bottom_messages,
        Routes.TIMETABLE to R.string.bottom_plan,
        Routes.GRADES to R.string.bottom_grades,
        Routes.SCHOOL to R.string.bottom_school,
    )

    fun iconFor(route: String): ImageVector = when (route) {
        Routes.OVERVIEW -> Icons.Filled.Home
        Routes.HOMEWORK -> Icons.AutoMirrored.Filled.Assignment
        Routes.MESSAGES -> Icons.Filled.MailOutline
        Routes.TIMETABLE -> Icons.Filled.CalendarMonth
        Routes.GRADES -> Icons.Filled.Grade
        Routes.SCHOOL -> Icons.Filled.Event
        else -> Icons.Filled.Home
    }

    @Composable
    fun label(route: String): String = stringResource(labelRes[route] ?: R.string.bottom_home)

    /** Standard: Home, Aufgaben, Nachr., Plan (Mehr ist immer angepinnt). */
    val default: List<String> = listOf(
        Routes.OVERVIEW,
        Routes.HOMEWORK,
        Routes.MESSAGES,
        Routes.TIMETABLE,
    )

    /**
     * Roh-String säubern: nur bekannte Routen, keine Doppelten, höchstens
     * [MAX_CONTENT]. Leere Auswahl fällt auf [default] zurück (leere Leiste
     * wäre unbedienbar).
     */
    fun parse(raw: String?): List<String> {
        val parsed = (raw ?: "").split(',').map(String::trim)
            .filter { it in candidates }.distinct().take(MAX_CONTENT)
        return parsed.ifEmpty { default }
    }

    fun serialize(routes: List<String>): String = parse(routes.joinToString(",")).joinToString(",")

    fun move(routes: List<String>, from: Int, by: Int): List<String> {
        val target = (from + by).coerceIn(0, routes.lastIndex)
        if (target == from) return routes
        return routes.toMutableList().apply { add(target, removeAt(from)) }
    }
}
