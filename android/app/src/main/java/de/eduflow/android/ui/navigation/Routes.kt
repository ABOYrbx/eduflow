package de.eduflow.android.ui.navigation

/** Routen-Namen (Paket 0, eingefroren — Pakete A–G hängen hier an). */
object Routes {
    const val LOGIN = "login"
    const val ONBOARDING = "onboarding"
    const val TWO_FA = "twofa?pending={pending}"
    const val OVERVIEW = "overview"
    const val MESSAGES = "messages"
    const val HOMEWORK = "homework"
    const val TIMETABLE = "timetable"
    const val SCHOOL = "school"
    const val GRADES = "grades"
    const val SETTINGS = "settings"
    const val DEVICES = "devices"
    /** Mehr-Tab (Redesign-PNG): Noten, Einstellungen, Geräte, Server, … */
    const val MORE = "more"

    fun twoFa(pending: String) = "twofa?pending=$pending"

    /** Startseite nach Anmeldung (landing-Setting aus GET /settings, wie Web-/). */
    fun landingRoute(landing: String): String = when (landing) {
        "dashboard" -> MESSAGES
        "hausaufgaben" -> HOMEWORK
    "noten" -> GRADES
        "stundenplan" -> TIMETABLE
        else -> OVERVIEW
    }
}
