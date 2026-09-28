package de.eduflow.android

import de.eduflow.android.ui.navigation.BottomTabs
import de.eduflow.android.ui.navigation.NavTabs
import de.eduflow.android.ui.navigation.Routes
import de.eduflow.android.ui.navigation.tabForRoute
import de.eduflow.android.ui.navigation.tabsForSelection
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Editierbare Navigationsleiste — reine Logik, offline: parsen,
 * begrenzen, sortieren, Tab-Auflösung mit Mehr-Rückfall.
 */
class NavBarTest {

    @Test
    fun parse_defaultIgnoresUnknownAndDuplicates() {
        assertEquals(
            listOf(Routes.OVERVIEW, Routes.HOMEWORK),
            NavTabs.parse("overview, homework, overview, login, twofa"),
        )
    }

    @Test
    fun parse_emptyFallsBackToDefault() {
        assertEquals(NavTabs.default, NavTabs.parse(""))
        assertEquals(NavTabs.default, NavTabs.parse(null))
        assertEquals(NavTabs.default, NavTabs.parse("login"))
    }

    @Test
    fun parse_capsAtMaxContent() {
        val parsed = NavTabs.parse("overview,homework,messages,timetable,grades,school")
        assertEquals(NavTabs.MAX_CONTENT, parsed.size)
        assertEquals(
            listOf(Routes.OVERVIEW, Routes.HOMEWORK, Routes.MESSAGES, Routes.TIMETABLE, Routes.GRADES),
            parsed,
        )
    }

    @Test
    fun serialize_roundTripsAndCleans() {
        assertEquals(
            "overview,homework",
            NavTabs.serialize(listOf(Routes.OVERVIEW, Routes.HOMEWORK)),
        )
        assertEquals(NavTabs.default.joinToString(","), NavTabs.serialize(emptyList()))
    }

    @Test
    fun move_reordersWithinBounds() {
        val order = listOf(Routes.OVERVIEW, Routes.HOMEWORK, Routes.MESSAGES)
        assertEquals(
            listOf(Routes.HOMEWORK, Routes.OVERVIEW, Routes.MESSAGES),
            NavTabs.move(order, 0, 1),
        )
        assertEquals(order, NavTabs.move(order, 0, -5))
        assertEquals(order, NavTabs.move(order, 2, 5))
    }

    @Test
    fun tabsForSelection_pinsMoreLast() {
        val tabs = tabsForSelection(listOf(Routes.GRADES, Routes.OVERVIEW))
        assertEquals(listOf(Routes.GRADES, Routes.OVERVIEW, Routes.MORE), tabs.map { it.route })
    }

    @Test
    fun tabsForSelection_defaultMatchesBottomTabs() {
        val tabs = tabsForSelection(NavTabs.default)
        assertEquals(BottomTabs.map { it.route }, tabs.map { it.route })
    }

    @Test
    fun tabForRoute_mapsDirectTabs() {
        val tabs = tabsForSelection(NavTabs.parse("overview,grades"))
        assertEquals(Routes.OVERVIEW, tabForRoute(Routes.OVERVIEW, tabs))
        assertEquals(Routes.GRADES, tabForRoute(Routes.GRADES, tabs))
        // Nachrichten-Thread ohne sichtbaren Nachrichten-Tab → Mehr.
        assertEquals(Routes.MORE, tabForRoute("messages/12", tabs))
    }

    @Test
    fun tabForRoute_fallsBackToMore() {
        val tabs = tabsForSelection(NavTabs.default)
        assertEquals(Routes.MORE, tabForRoute(Routes.GRADES, tabs))
        assertEquals(Routes.MORE, tabForRoute(Routes.SETTINGS, tabs))
        assertEquals(Routes.MORE, tabForRoute(Routes.MORE, tabs))
    }

    @Test
    fun tabForRoute_unknownRoutesStayNull() {
        val tabs = tabsForSelection(NavTabs.default)
        assertNull(tabForRoute(null, tabs))
        assertNull(tabForRoute(Routes.LOGIN, tabs))
        assertNull(tabForRoute("twofa?pending=x", tabs))
    }

    @Test
    fun candidates_coverAllContentTabs() {
        assertTrue(NavTabs.candidates.containsAll(NavTabs.default))
        assertTrue(NavTabs.candidates.contains(Routes.GRADES))
        assertTrue(NavTabs.candidates.contains(Routes.SCHOOL))
    }
}
