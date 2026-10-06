package de.eduflow.android

import de.eduflow.android.data.TokenStore
import de.eduflow.android.data.dto.GradeDto
import de.eduflow.android.data.dto.LessonDto
import de.eduflow.android.data.dto.MessageDto
import de.eduflow.android.data.dto.MessageTypes
import de.eduflow.android.data.dto.RecipientIds
import de.eduflow.android.data.dto.bodyLine
import de.eduflow.android.data.dto.buildGradeTerms
import de.eduflow.android.data.dto.currentTermKey
import de.eduflow.android.data.dto.deNum
import de.eduflow.android.data.dto.displayGradeTermLabel
import de.eduflow.android.data.dto.gradeTermKey
import de.eduflow.android.data.dto.gradeTermLabel
import de.eduflow.android.data.dto.gradesAverage
import de.eduflow.android.data.dto.groupGradesBySubject
import de.eduflow.android.ui.overview.OverviewOrder
import de.eduflow.android.ui.overview.OverviewViewModel
import java.time.LocalTime
import java.time.format.DateTimeFormatter
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.assertFalse
import org.junit.Test

/**
 * Pakete B–D — reine Logik, offline (kein Netz, kein Context,
 * kein Main-Dispatcher): aktuelle/nächste Stunde, Noten-Schnitt/
 * Halbjahre/Gruppierung, Empfänger-IDs, Typ-Labels.
 * Web-Parität zu app.py (lesson time, grades_average, grade_term_key,
 * _current_term_key, grade_term_label, _RECIPIENT_ID_RE, TYPE_LABELS).
 */
class LogicPackageTest {

    private val fmt = DateTimeFormatter.ofPattern("HH:mm")

    private fun lesson(title: String, startMin: Long, endMin: Long, cancelled: Boolean = false): LessonDto {
        val now = LocalTime.now()
        val s = now.plusMinutes(startMin).format(fmt)
        val e = now.plusMinutes(endMin).format(fmt)
        return LessonDto(period = "1", time = "$s–$e", title = title, is_cancelled = cancelled)
    }

    @Test
    fun currentAndNext_runningAndUpcoming() {
        // Feste Uhrzeit statt now(): relativ gebaut wäre der Test zwischen
        // 23:00 und 24:00 am Mitternachtsumbruch flaky.
        val now = LocalTime.of(10, 0)
        val running = LessonDto(period = "1", time = "09:30–10:30", title = "Mathe")
        val later = LessonDto(period = "1", time = "11:00–12:00", title = "Deutsch")
        val (current, next) = OverviewViewModel.currentAndNext(listOf(running, later), now)
        assertEquals("Mathe", current?.title)
        assertEquals("Deutsch", next?.title)
    }

    @Test
    fun currentAndNext_skipsCancelled() {
        val cancelled = lesson("Bio", -30, 30, cancelled = true)
        val (current, next) = OverviewViewModel.currentAndNext(listOf(cancelled))
        assertNull(current)
        assertNull(next)
    }

    @Test
    fun currentAndNext_emptyAndMalformed() {
        assertEquals(null to null, OverviewViewModel.currentAndNext(emptyList()))
        val bad = LessonDto(period = "–", time = "keine Zeit", title = "Event")
        assertEquals(null to null, OverviewViewModel.currentAndNext(listOf(bad)))
    }

    @Test
    fun currentAndNext_hyphenSeparator() {
        // Backend nutzt –, aber auch "-" darf nicht crashen (feste Uhrzeit
        // wie oben, kein Mitternachts-Flaky).
        val l = LessonDto(period = "2", time = "09:50-10:10", title = "Englisch")
        val (current, _) = OverviewViewModel.currentAndNext(listOf(l), LocalTime.of(10, 0))
        assertEquals("Englisch", current?.title)
    }

    // ---- Übersichts-Reihenfolge (ov_order) ----

    @Test
    fun overviewOrder_parseKeepsKnownKeysOnly() {
        assertEquals(
            listOf("homework", "messages", "weather"),
            OverviewOrder.parse("homework,messages"),
        )
    }

    @Test
    fun overviewOrder_parseAppendsMissingAndIgnoresGarbage() {
        // Unbekanntes raus, Vorhandenes in der Wunschreihenfolge, fehlende
        // Sektionen hinten anfügen — sonst verschwände eine Sektion.
        assertEquals(
            listOf("weather", "messages", "homework"),
            OverviewOrder.parse("weather,bogus,messages"),
        )
        assertEquals(OverviewOrder.keys, OverviewOrder.parse(""))
    }

    @Test
    fun overviewOrder_moveClampsAndReorders() {
        val base = listOf("messages", "homework", "weather")
        assertEquals(listOf("homework", "messages", "weather"), OverviewOrder.move(base, 0, 1))
        assertEquals(listOf("messages", "weather", "homework"), OverviewOrder.move(base, 1, 1))
        assertEquals(listOf("messages", "weather", "homework"), OverviewOrder.move(base, 2, -1))
        // Weit über das Ende hinaus → kein Absturz, das Ziel wird geklemmt.
        assertEquals(base, OverviewOrder.move(base, 0, -5))
        assertEquals(base, OverviewOrder.move(base, 2, 5))
    }

    @Test
    fun overviewOrder_serializeIsStableRoundTrip() {
        val base = OverviewOrder.keys
        assertEquals(base, OverviewOrder.parse(OverviewOrder.serialize(base)))
        // Duplikate und Fremdwerte dürfen nicht in den String geraten.
        assertEquals(
            listOf("messages", "homework", "weather"),
            OverviewOrder.parse(OverviewOrder.serialize(listOf("messages", "messages", "nope", "homework"))),
        )
    }

    // ---- Noten ----

    private fun grade(subject: String, num: Double?, weight: Double = 1.0, iso: String = "2025-11-03"): GradeDto =
        GradeDto(subject = subject, title = "KA", grade_num = num, weight = weight, date_iso = iso, sort_key = iso)

    @Test
    fun gradesAverage_weighted() {
        val items = listOf(grade("M", 2.0), grade("M", 4.0, weight = 3.0))
        // (2*1 + 4*3) / 4 = 3.5
        assertEquals(3.5, gradesAverage(items)!!, 0.0)
    }

    @Test
    fun gradesAverage_ignoresNonClassic() {
        val items = listOf(
            grade("M", null),
            grade("M", 0.5), // Punkte → raus
            grade("M", 6.5), // außerhalb 1..6 → raus
            grade("M", 1.0),
        )
        assertEquals(1.0, gradesAverage(items)!!, 0.0)
        assertNull(gradesAverage(listOf(grade("M", null))))
        assertNull(gradesAverage(emptyList()))
    }

    @Test
    fun gradesAverage_zeroWeightCountsOnce() {
        assertEquals(3.0, gradesAverage(listOf(grade("M", 3.0, weight = 0.0)))!!, 0.0)
    }

    @Test
    fun deNum_germanComma() {
        assertEquals("2,5", deNum(2.5))
        assertEquals("2", deNum(2.0))
        assertEquals("–", deNum(null))
    }

    @Test
    fun termKeys_matchBackend() {
        // app.py: Sept–Jan = H1, Feb–Aug = H2 (Schuljahr Sept–Aug).
        assertEquals("2025-H1", currentTermKey(2025, 9))
        assertEquals("2025-H1", currentTermKey(2026, 1))
        assertEquals("2025-H2", currentTermKey(2026, 2))
        assertEquals("2025-H2", currentTermKey(2026, 8))
        assertEquals("2025-H1", gradeTermKey("2025-11-03", "fallback"))
        assertEquals("2025-H2", gradeTermKey("2026-03-01", "fallback"))
        assertEquals("fallback", gradeTermKey("kein-datum", "fallback"))
    }

    @Test
    fun termLabel_matchBackend() {
        assertEquals("1. Halbjahr 25/26", gradeTermLabel("2025-H1"))
        assertEquals("2. Halbjahr 25/26", gradeTermLabel("2025-H2"))
        assertEquals("kaputt", gradeTermLabel("kaputt"))
    }

    @Test
    fun termLabel_customFormat() {
        // UI übergibt das übersetzte grades_term_label_format (Platzhalter
        // %1$d = Halbjahr, %2$s/%3$s = Kurzjahre).
        assertEquals("Semester 1 25/26", gradeTermLabel("2025-H1", "Semester %1\$d %2\$s/%3\$s"))
        assertEquals("kaputt", gradeTermLabel("kaputt", "Semester %1\$d %2\$s/%3\$s"))
        // Kaputtes Format fällt auf Deutsch zurück, crasht nie.
        assertEquals("1. Halbjahr 25/26", gradeTermLabel("2025-H1", "%q-nonsens"))
    }

    @Test
    fun displayTermLabel_allAndTerms() {
        assertEquals("Gesamt", displayGradeTermLabel("alle"))
        assertEquals("All", displayGradeTermLabel("alle", "All", "Semester %1\$d %2\$s/%3\$s"))
        assertEquals("Semester 2 25/26", displayGradeTermLabel("2025-H2", "All", "Semester %1\$d %2\$s/%3\$s"))
    }

    @Test
    fun buildGradeTerms_customLabels() {
        val items = listOf(
            grade("M", 2.0, iso = "2025-11-03"),
            grade("D", 3.0, iso = "2026-03-01"),
        )
        val terms = buildGradeTerms(items, "2025-H1", allLabel = "All", termFormat = "Semester %1\$d %2\$s/%3\$s")
        assertEquals(listOf("2025-H2", "2025-H1", "alle"), terms.map { it.key })
        assertEquals("Semester 2 25/26", terms.first().label)
        assertEquals("All", terms.last().label)
    }

    @Test
    fun groupGradesBySubject_customOtherLabel() {
        val items = listOf(
            grade("", 1.0, iso = "2025-11-02"),
        )
        val groups = groupGradesBySubject(items, otherLabel = "Other")
        assertEquals(listOf("Other"), groups.map { it.subject })
    }

    @Test
    fun buildGradeTerms_newestFirstPlusAlle() {
        val items = listOf(
            grade("M", 2.0, iso = "2025-11-03"),
            grade("D", 3.0, iso = "2026-03-01"),
            grade("D", 4.0, iso = "2026-04-01"),
        )
        val terms = buildGradeTerms(items, "2025-H1")
        assertEquals(listOf("2025-H2", "2025-H1", "alle"), terms.map { it.key })
        assertEquals(2, terms.first().count)
        assertEquals(3, terms.last().count)
    }

    @Test
    fun groupGradesBySubject_sortedAndAveraged() {
        val items = listOf(
            grade("Mathe", 4.0, iso = "2025-10-01"),
            grade("Deutsch", 2.0, iso = "2025-11-01"),
            grade("", 1.0, iso = "2025-11-02"),
            grade("Mathe", 2.0, iso = "2025-11-03"),
        )
        val groups = groupGradesBySubject(items)
        assertEquals(listOf("Deutsch", "Mathe", "Sonstiges"), groups.map { it.subject })
        val mathe = groups.first { it.subject == "Mathe" }
        // Neueste zuerst (sort_key desc), Schnitt (4+2)/2 = 3.
        assertEquals("2025-11-03", mathe.items.first().date_iso)
        assertEquals(3.0, mathe.avg!!, 0.0)
        assertEquals("3", mathe.avgDisplay)
    }

    // ---- Empfänger + Typen (Paket B) ----

    @Test
    fun recipientIds_matchBackendRegex() {
        assertTrue(RecipientIds.isValid("Teacher7"))
        assertTrue(RecipientIds.isValid("student12"))
        assertTrue(RecipientIds.isValid("Ucitel3"))
        assertFalse(RecipientIds.isValid("Lehrer7"))
        assertFalse(RecipientIds.isValid("Teacher"))
        assertFalse(RecipientIds.isValid(""))
        assertEquals(
            listOf("Teacher7", "Student3"),
            RecipientIds.clean(listOf(" Teacher7 ", "Student3", "Teacher7", "nonsense")),
        )
        assertEquals(listOf("Teacher7"), RecipientIds.clean("Teacher7, Quatsch"))
    }

    @Test
    fun messageTypeLabels() {
        assertEquals("Nachricht", MessageTypes.label("sprava"))
        assertEquals("Alle", MessageTypes.label(""))
        assertEquals("Alle", MessageTypes.label("unbekannt"))
        assertTrue(MessageTypes.ALL.containsAll(listOf("sprava", "news", "anketa", "chat", "genotif")))
    }

    // ---- Kartentext (Paket C, PNG-Karte ohne Betreff) ----

    @Test
    fun messageBodyLine() {
        val m = MessageDto(type_label = "Nachricht", text = "Unterrichtsausfall morgen\nDie erste Stunde entfällt.")
        assertEquals("Unterrichtsausfall morgen Die erste Stunde entfällt.", m.bodyLine())
        val empty = MessageDto(type_label = "Mitteilung", text = "   ")
        assertEquals("Mitteilung", empty.bodyLine())
        val long = MessageDto(text = "x".repeat(300))
        assertEquals(221, long.bodyLine().length) // 220 + …
        assertTrue(long.bodyLine().endsWith("…"))
    }

    // ---- Demo-Erkennung (Paket A: automatisch per Server-URL, kein Schalter) ----

    @Test
    fun demoServerUrlDetection() {
        assertTrue(TokenStore.isDemoServerUrl(TokenStore.DEMO_BASE_URL))
        assertTrue(TokenStore.isDemoServerUrl("http://10.0.2.2:3100/api/v1"))
        assertTrue(TokenStore.isDemoServerUrl("10.0.2.2:3100/api/v1/"))
        assertFalse(TokenStore.isDemoServerUrl(TokenStore.DEFAULT_BASE_URL))
        assertFalse(TokenStore.isDemoServerUrl("http://10.0.2.2:3000/api/v1/"))
        assertFalse(TokenStore.isDemoServerUrl(""))
    }

    @Test
    fun demoServerUrlDetectionFollowsPortNotHost() {
        // Ohne Port-Eingabe erkannt, weil :3100 der Demo-Port ist.
        assertTrue(TokenStore.isDemoServerUrl("10.0.2.2:3100"))
        // Entscheidend: ein Demo-Server im WLAN (Handy gegen den Mac) ist
        // auch ein Demo — die Host-IP weicht von DEMO_BASE_URL ab, der
        // Vergleich lief vorher ueber die volle URL und wuerde scheitern.
        assertTrue(TokenStore.isDemoServerUrl("192.168.1.5:3100"))
        // Gleicher Host, anderer Port -> kein Demo.
        assertFalse(TokenStore.isDemoServerUrl("192.168.1.5:3000"))
        assertFalse(TokenStore.isDemoServerUrl("192.168.1.5"))
        // Hostname statt IP zaehlt genauso.
        assertTrue(TokenStore.isDemoServerUrl("mein-mac.local:3100"))
    }
}
