package de.eduflow.android.data.dto

import kotlinx.serialization.Serializable

/**
 * Wetter 1:1 zu den Web-Dicts (app.py get_wetter_payload).
 *
 * Wetter: GET /api/v1/wetter -> WetterResponse (Schlüssel bleibt
 * serverseitig; ohne Ort VALIDATION, ohne Schlüssel CONFIG_MISSING).
 * (siehe api/meta.py, BACKEND.md §8 / Paket F).
 */
@Serializable
data class WetterDay(
    val max: Int? = null,
    val min: Int? = null,
    val desc: String = "",
    val icon: String = "",
    val pop: Int? = null,
    val label: String = "",
)

@Serializable
data class WetterToday(
    val temp: Int? = null,
    val max: Int? = null,
    val min: Int? = null,
    val desc: String = "",
    val icon: String = "",
    val pop: Int? = null,
)

@Serializable
data class WetterHour(
    val time: String = "",
    val temp: Int? = null,
    val icon: String = "",
    val desc: String = "",
    val pop: Int? = null,
)

@Serializable
data class WetterDetails(
    val feels_like: Int? = null,
    val humidity: Int? = null,
    val pressure: Int? = null,
    val wind_kmh: Int? = null,
    val wind_dir: String? = null,
    val clouds: Int? = null,
    val visibility_km: Double? = null,
    val sunrise: String? = null,
    val sunset: String? = null,
)

@Serializable
data class WetterResponse(
    val city: String = "",
    val today: WetterToday = WetterToday(),
    val tomorrow: WetterDay = WetterDay(),
    val day3: WetterDay = WetterDay(),
    val hourly: List<WetterHour> = emptyList(),
    val details: WetterDetails = WetterDetails(),
)

/** Treffer der serverseitigen OpenWeather-Ortssuche. */
@Serializable
data class WetterCitySuggestion(
    val name: String = "",
    val state: String = "",
    val country: String = "",
    val label: String = "",
    /** Abfragewert für die Wetter-API, wird als Account-Einstellung gespeichert. */
    val query: String = "",
)
