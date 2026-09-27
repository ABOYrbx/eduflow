package de.eduflow.android.data

import de.eduflow.android.data.dto.CacheClearResponse
import de.eduflow.android.data.dto.DevicesDto
import de.eduflow.android.data.dto.LoginRequest
import de.eduflow.android.data.dto.LoginResponse
import de.eduflow.android.data.dto.MeDto
import de.eduflow.android.data.dto.SettingsResponse
import de.eduflow.android.data.dto.StatusDto
import de.eduflow.android.data.dto.TwoFaRequest
import kotlinx.serialization.json.JsonObject
import okhttp3.ResponseBody
import retrofit2.Response
import retrofit2.http.Body
import retrofit2.http.DELETE
import retrofit2.http.GET
import retrofit2.http.POST
import retrofit2.http.PUT
import retrofit2.http.Path
import retrofit2.http.Query
import retrofit2.http.Streaming

/**
 * EduFlow API v1 — eingefrorene Schnittstelle (Paket 0).
 * 1:1 zu GET /api/v1/openapi.json. Alle Ressourcen-Pakete (A–D)
 * programmieren nur gegen dieses Interface, sonst nichts.
 *
 * Paket A nutzt: auth/..., me, devices, settings, cache-clear, health.
 * Pakete B–D nutzen: messages, homework, timetable, grades, wetter
 * (Payloads als JsonObject = Web-Dicts 1:1, keine eigenen Serializer).
 */
interface ApiService {

    // ---- System (ohne Auth) ----
    @GET("health")
    suspend fun health(): Response<JsonObject>

    // ---- Paket A: Auth ----
    @POST("auth/login")
    suspend fun login(@Body body: LoginRequest): Response<LoginResponse>

    @POST("auth/2fa")
    suspend fun submit2fa(@Body body: TwoFaRequest): Response<LoginResponse>

    @POST("auth/logout")
    suspend fun logout(): Response<StatusDto>

    @POST("auth/refresh")
    suspend fun refresh(): Response<LoginResponse>

    @GET("me")
    suspend fun me(): Response<MeDto>

    @GET("devices")
    suspend fun devices(): Response<DevicesDto>

    @DELETE("devices/{id}")
    suspend fun revokeDevice(@Path("id") id: String): Response<StatusDto>

    // ---- Paket A/G: Einstellungen + Cache ----
    @GET("settings")
    suspend fun getSettings(): Response<SettingsResponse>

    @PUT("settings")
    suspend fun putSettings(@Body values: JsonObject): Response<SettingsResponse>

    @POST("cache-clear")
    suspend fun clearCache(): Response<CacheClearResponse>

    // ---- Paket B: Nachrichten (DTOs definiert Paket B) ----
    @GET("messages")
    suspend fun messages(
        @Query("since") since: String? = null,
        @Query("type") type: String? = null,
        @Query("q") q: String? = null,
        @Query("limit") limit: Int? = null,
        @Query("offset") offset: Int? = null,
        @Query("refresh") refresh: Int? = null,
    ): Response<JsonObject>

    @GET("messages/{id}/thread")
    suspend fun messageThread(
        @Path("id") id: Long,
        @Query("refresh") refresh: Int? = null,
    ): Response<JsonObject>

    @POST("messages/read")
    suspend fun markRead(): Response<JsonObject>

    @GET("recipients")
    suspend fun recipients(
        @Query("limit") limit: Int? = null,
        @Query("offset") offset: Int? = null,
    ): Response<JsonObject>

    @POST("messages/send")
    suspend fun sendMessage(@Body body: JsonObject): Response<JsonObject>

    @POST("messages/{id}/reply")
    suspend fun replyMessage(
        @Path("id") id: Long,
        @Body body: JsonObject,
    ): Response<JsonObject>

    @Streaming
    @GET("messages/{id}/attachments/{idx}")
    suspend fun attachment(
        @Path("id") id: Long,
        @Path("idx") idx: Int,
        @Query("token") token: String? = null,
        @Query("dl") dl: String? = null,
    ): Response<ResponseBody>

    @POST("messages/download-token")
    suspend fun downloadToken(@Body body: JsonObject): Response<JsonObject>

    // ---- Paket C: Hausaufgaben + Noten ----
    @GET("homework")
    suspend fun homework(
        @Query("since") since: String? = null,
        @Query("status") status: String? = null,
        @Query("include_tests") includeTests: Int? = null,
        @Query("q") q: String? = null,
        @Query("limit") limit: Int? = null,
        @Query("offset") offset: Int? = null,
        @Query("refresh") refresh: Int? = null,
    ): Response<JsonObject>

    @POST("homework/{id}/done")
    suspend fun homeworkDone(
        @Path("id") id: Long,
        @Body body: JsonObject,
    ): Response<JsonObject>

    @POST("homework/{id}/trash")
    suspend fun homeworkTrash(
        @Path("id") id: Long,
        @Body body: JsonObject,
    ): Response<JsonObject>

    @GET("grades")
    suspend fun grades(
        @Query("limit") limit: Int? = null,
        @Query("offset") offset: Int? = null,
        @Query("refresh") refresh: Int? = null,
    ): Response<JsonObject>

    // ---- Paket D: Stundenplan + Wetter ----
    @GET("timetable/day")
    suspend fun timetableDay(
        @Query("day") day: String? = null,
        @Query("refresh") refresh: Int? = null,
    ): Response<JsonObject>

    @GET("timetable/week")
    suspend fun timetableWeek(
        @Query("day") day: String? = null,
        @Query("refresh") refresh: Int? = null,
    ): Response<JsonObject>

    @GET("school/agenda")
    suspend fun schoolAgenda(
        @Query("since") since: String,
        @Query("until") until: String,
        @Query("refresh") refresh: Int? = null,
    ): Response<JsonObject>

    @GET("substitutions/week")
    suspend fun substitutionsWeek(
        @Query("day") day: String,
    ): Response<JsonObject>

    @GET("wetter")
    suspend fun wetter(
        @Query("lat") lat: Double? = null,
        @Query("lon") lon: Double? = null,
        @Query("city") city: String? = null,
    ): Response<JsonObject>

    @GET("wetter/suche")
    suspend fun searchWetterCities(
        @Query("q") query: String,
    ): Response<JsonObject>

    companion object {
        /** Pfade ohne Bearer-Token (System + Login-Ablauf). */
        val NO_AUTH_SUFFIXES = listOf("health", "openapi.json", "auth/login", "auth/2fa")
    }
}
