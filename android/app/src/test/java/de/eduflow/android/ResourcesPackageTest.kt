package de.eduflow.android

import de.eduflow.android.data.ApiException
import de.eduflow.android.data.ApiService
import de.eduflow.android.data.EduFlowJson
import de.eduflow.android.data.MessagesRepository
import de.eduflow.android.data.MetaRepository
import de.eduflow.android.data.TimetableRepository
import de.eduflow.android.data.dto.CacheClearResponse
import de.eduflow.android.data.dto.DevicesDto
import de.eduflow.android.data.dto.LoginRequest
import de.eduflow.android.data.dto.LoginResponse
import de.eduflow.android.data.dto.MeDto
import de.eduflow.android.data.dto.SettingsResponse
import de.eduflow.android.data.dto.StatusDto
import de.eduflow.android.data.dto.TwoFaRequest
import de.eduflow.android.data.repository.GradesRepository
import de.eduflow.android.data.repository.HomeworkRepository
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.ResponseBody
import okhttp3.ResponseBody.Companion.toResponseBody
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import retrofit2.Response

/**
 * Pakete B–D — Repositories offline gegen Fake-[ApiService]
 * (kein Netz, kein Login): Routenform (Parameter/Body-Keys wie im
 * api-Paket), Fehlercodes als ApiException im Result, Paginierung
 * (limit/offset-Clamping 1..200) und 401-Verhalten.
 */
class ResourcesPackageTest {

    // ---- Fake ------------------------------------------------------

    private class FakeResourceApi : ApiService {
        var messagesJson = """{"items":[],"total":0,"limit":50,"offset":0}"""
        var messagesError: Pair<Int, String>? = null
        var lastMessages: Map<String, Any?> = emptyMap()

        var threadJson = """{"likes":[],"replies":[],"reply_ids":[],"summary":{},"cached":false}"""
        var readJson = """{"marked":0}"""
        var recipientsJson = """{"items":[],"total":0,"limit":50,"offset":0}"""
        var sendJson = """{"id":1}"""
        var sendError: Pair<Int, String>? = null
        var lastSend: JsonObject? = null
        var replyJson = """{"likes":[],"replies":[],"reply_ids":[],"summary":{},"cached":false}"""
        var lastReply: JsonObject? = null

        var homeworkJson = """{"items":[],"total":0,"limit":50,"offset":0,"counts":{},"cache_info":""}"""
        var homeworkError: Pair<Int, String>? = null
        var lastHomework: Map<String, Any?> = emptyMap()
        var doneJson = """{"id":1}"""
        var lastDone: JsonObject? = null
        var trashJson = """{"id":1}"""
        var lastTrash: JsonObject? = null

        var gradesJson = """{"items":[],"total":0,"limit":50,"offset":0,"cache_info":""}"""
        var dayJson = """{"day":"","lessons":[]}"""
        var weekJson = """{"day":"","monday":"","days":[]}"""
        var essenJson = """{"week":"","days":{}}"""
        var wetterJson = """{"city":""}"""
        var lastWetter: Map<String, Any?> = emptyMap()

        private fun obj(s: String): JsonObject = EduFlowJson.parseToJsonElement(s).jsonObject

        private fun <T> failWith(err: Pair<Int, String>?): Response<T>? =
            err?.let { Response.error(it.first, it.second.toResponseBody("application/json".toMediaType())) }

        override suspend fun health(): Response<JsonObject> = Response.success(obj("{}"))
        override suspend fun login(body: LoginRequest): Response<LoginResponse> = throw UnsupportedOperationException()
        override suspend fun submit2fa(body: TwoFaRequest): Response<LoginResponse> = throw UnsupportedOperationException()
        override suspend fun logout(): Response<StatusDto> = Response.success(StatusDto())
        override suspend fun refresh(): Response<LoginResponse> = throw UnsupportedOperationException()
        override suspend fun me(): Response<MeDto> = throw UnsupportedOperationException()
        override suspend fun devices(): Response<DevicesDto> = Response.success(DevicesDto())
        override suspend fun revokeDevice(id: String): Response<StatusDto> = Response.success(StatusDto())
        override suspend fun getSettings(): Response<SettingsResponse> = Response.success(SettingsResponse())
        override suspend fun putSettings(values: JsonObject): Response<SettingsResponse> = Response.success(SettingsResponse())
        override suspend fun clearCache(): Response<CacheClearResponse> = Response.success(CacheClearResponse())

        override suspend fun messages(since: String?, type: String?, q: String?, limit: Int?, offset: Int?, refresh: Int?): Response<JsonObject> {
            lastMessages = mapOf("since" to since, "type" to type, "q" to q, "limit" to limit, "offset" to offset, "refresh" to refresh)
            return failWith(messagesError) ?: Response.success(obj(messagesJson))
        }

        override suspend fun messageThread(id: Long, refresh: Int?): Response<JsonObject> =
            Response.success(obj(threadJson))

        override suspend fun markRead(): Response<JsonObject> = Response.success(obj(readJson))

        override suspend fun recipients(limit: Int?, offset: Int?): Response<JsonObject> =
            Response.success(obj(recipientsJson))

        override suspend fun sendMessage(body: JsonObject): Response<JsonObject> {
            lastSend = body
            return failWith(sendError) ?: Response.success(obj(sendJson))
        }

        override suspend fun replyMessage(id: Long, body: JsonObject): Response<JsonObject> {
            lastReply = body
            return Response.success(obj(replyJson))
        }

        override suspend fun attachment(id: Long, idx: Int, token: String?, dl: String?): Response<ResponseBody> =
            throw UnsupportedOperationException()

        var downloadJson = """{"download_token":"","expires_in":300}"""

        override suspend fun downloadToken(body: JsonObject): Response<JsonObject> =
            Response.success(obj(downloadJson))

        override suspend fun homework(since: String?, status: String?, includeTests: Int?, q: String?, limit: Int?, offset: Int?, refresh: Int?): Response<JsonObject> {
            lastHomework = mapOf("since" to since, "status" to status, "includeTests" to includeTests, "q" to q, "limit" to limit, "offset" to offset, "refresh" to refresh)
            return failWith(homeworkError) ?: Response.success(obj(homeworkJson))
        }

        override suspend fun homeworkDone(id: Long, body: JsonObject): Response<JsonObject> {
            lastDone = body
            return Response.success(obj(doneJson))
        }

        override suspend fun homeworkTrash(id: Long, body: JsonObject): Response<JsonObject> {
            lastTrash = body
            return Response.success(obj(trashJson))
        }

        override suspend fun grades(limit: Int?, offset: Int?, refresh: Int?): Response<JsonObject> =
            Response.success(obj(gradesJson))

        override suspend fun timetableDay(day: String?, refresh: Int?): Response<JsonObject> =
            Response.success(obj(dayJson))

        override suspend fun timetableWeek(day: String?, refresh: Int?): Response<JsonObject> =
            Response.success(obj(weekJson))

        override suspend fun schoolAgenda(
            since: String,
            until: String,
            refresh: Int?,
        ): Response<JsonObject> = Response.success(obj("""{"items":[],"total":0}"""))

        override suspend fun substitutionsWeek(day: String): Response<JsonObject> =
            Response.success(obj("""{"days":[]}"""))

        override suspend fun essen(refresh: Int?): Response<JsonObject> = Response.success(obj(essenJson))

        override suspend fun wetter(lat: Double?, lon: Double?, city: String?): Response<JsonObject> {
            lastWetter = mapOf("lat" to lat, "lon" to lon, "city" to city)
            return Response.success(obj(wetterJson))
        }

        override suspend fun searchWetterCities(query: String): Response<JsonObject> =
            Response.success(obj("""{"items":[]}"""))
    }

    private fun apiExceptionOf(result: Result<*>): ApiException {
        val e = result.exceptionOrNull() ?: throw AssertionError("Fehler erwartet, war Erfolg")
        return e as? ApiException ?: throw AssertionError("ApiException erwartet, war: $e")
    }

    // ---- Nachrichten (Paket B) -------------------------------------

    @Test
    fun messagesList_decodesEnvelope() = runBlocking {
        val fake = FakeResourceApi().apply {
            messagesJson = """{"items":[{"id":7,"author":"Frau X","recipient":"5.A","type":"sprava",
                "type_label":"Nachricht","text":"Hallo","timestamp":"3.9.","timestamp_iso":"2026-09-03",
                "sort_key":"2026-09-03","reaction_count":2,
                "attachments":[{"name":"a.pdf","url":"/cloud/a"}]}],"total":1,"limit":50,"offset":0}"""
        }
        val page = MessagesRepository(api = { fake }).list().getOrThrow()
        assertEquals(1, page.total)
        val m = page.items.single()
        assertEquals(7, m.id)
        assertEquals("Frau X", m.author)
        assertEquals(2, m.reaction_count)
        assertEquals("a.pdf", m.attachments.single().name)
        Unit
    }

    @Test
    fun messagesList_paramShape() = runBlocking {
        val fake = FakeResourceApi()
        val repo = MessagesRepository(api = { fake })
        repo.list(since = "2024-01-01", type = "", q = "  ", limit = 500, offset = -3, refresh = true)
        // Blank → null, Clamping 1..200, refresh true → 1 (false → null).
        assertEquals(
            mapOf("since" to "2024-01-01", "type" to null, "q" to null, "limit" to 200, "offset" to 0, "refresh" to 1),
            fake.lastMessages,
        )
        repo.list(refresh = false)
        assertNull(fake.lastMessages["refresh"])
        Unit
    }

    @Test
    fun messagesList_401isApiException() = runBlocking {
        val fake = FakeResourceApi().apply {
            messagesError = 401 to """{"error":"Abgelaufen.","code":"TOKEN_EXPIRED"}"""
        }
        val err = apiExceptionOf(MessagesRepository(api = { fake }).list())
        assertEquals("TOKEN_EXPIRED", err.code)
        assertEquals(401, err.httpStatus)
        Unit
    }

    @Test
    fun thread_decodesLikesAndReplies() = runBlocking {
        val fake = FakeResourceApi().apply {
            threadJson = """{"likes":[{"name":"Max","date":"3.9."}],"replies":[{"name":"Lea","date":"4.9.","text":"OK"}],
                "reply_ids":["9"],"summary":{"total":3,"likes":1,"replies":1,"seen":1},"cached":true}"""
        }
        val t = MessagesRepository(api = { fake }).thread(42).getOrThrow()
        assertEquals("Max", t.likes.single().name)
        assertEquals("OK", t.replies.single().text)
        assertEquals(3, t.summary.total)
        assertTrue(t.cached)
        Unit
    }

    @Test
    fun markRead_decodesMarked() = runBlocking {
        val fake = FakeResourceApi().apply { readJson = """{"marked":12}""" }
        assertEquals(12, MessagesRepository(api = { fake }).markRead().getOrThrow().marked)
        Unit
    }

    @Test
    fun recipients_decodePage() = runBlocking {
        val fake = FakeResourceApi().apply {
            recipientsJson = """{"items":[{"id":"Teacher7","name":"Frau X","kind":"Lehrer"}],"total":1,"limit":50,"offset":0}"""
        }
        val page = MessagesRepository(api = { fake }).recipients().getOrThrow()
        assertEquals("Teacher7", page.items.single().id)
        Unit
    }

    @Test
    fun send_bodyKeysMatchBackend() = runBlocking {
        val fake = FakeResourceApi().apply {
            sendJson = """{"id":99,"author":"Ich","text":"Hi"}"""
        }
        val repo = MessagesRepository(api = { fake })
        val sent = repo.send(listOf("Teacher7"), "Hi").getOrThrow()
        val body = fake.lastSend ?: throw AssertionError("Send-Body fehlt")
        // api/messages.py: {recipients: [IDs], body: Text}
        assertEquals("Teacher7", body["recipients"].toString().trim('[', ']', '"'))
        assertEquals("\"Hi\"", body["body"].toString())
        assertEquals(99, sent.id)
        Unit
    }

    @Test
    fun send_validationWithoutRecipients() = runBlocking {
        val fake = FakeResourceApi().apply {
            sendError = 400 to """{"error":"Bitte mindestens einen gültigen Empfänger angeben.","code":"VALIDATION"}"""
        }
        val err = apiExceptionOf(MessagesRepository(api = { fake }).send(emptyList(), "Hi"))
        assertEquals("VALIDATION", err.code)
        Unit
    }

    @Test
    fun reply_bodyKeyMatchesBackend() = runBlocking {
        val fake = FakeResourceApi()
        MessagesRepository(api = { fake }).reply(5, "Antwort").getOrThrow()
        // api/messages.py: {body: Text}
        assertEquals("\"Antwort\"", fake.lastReply?.get("body").toString())
        Unit
    }

    @Test
    fun attachmentUrl_shape() = runBlocking {
        val fake = FakeResourceApi().apply {
            downloadJson = """{"download_token":"abc123","expires_in":300}"""
        }
        val repo = MessagesRepository(api = { fake }, baseUrl = "http://10.0.2.2:8000/api/v1/")
        assertEquals(
            "http://10.0.2.2:8000/api/v1/messages/5/attachments/0?dl=abc123",
            repo.attachmentUrl(5, 0).getOrThrow(),
        )
        Unit
    }

    // ---- Hausaufgaben + Noten (Paket C) ------------------------------

    @Test
    fun homeworkList_decodesCountsAndCache() = runBlocking {
        val fake = FakeResourceApi().apply {
            homeworkJson = """{"items":[{"id":3,"title":"AB S. 4","type":"homework","status":"überfällig",
                "is_done":false,"is_hidden":false}],"total":1,"limit":50,"offset":0,
                "counts":{"offen":2,"ueberfaellig":1,"erledigt":5,"papierkorb":0},"cache_info":"frisch"}"""
        }
        val page = HomeworkRepository(api = { fake }).list().getOrThrow()
        assertEquals(3L, page.items.single().id)
        assertEquals(1, page.counts.ueberfaellig)
        assertEquals("frisch", page.cache_info)
        Unit
    }

    @Test
    fun homeworkList_paramShape() = runBlocking {
        val fake = FakeResourceApi()
        HomeworkRepository(api = { fake }).list(status = "offen", includeTests = true, q = "Mathe", limit = 500, offset = -1, refresh = true)
        // includeTests bool → 0/1, refresh true → 1 (Homework nutzt 0/1 statt null).
        assertEquals(
            mapOf("since" to null, "status" to "offen", "includeTests" to 1, "q" to "Mathe", "limit" to 200, "offset" to 0, "refresh" to 1),
            fake.lastHomework,
        )
        Unit
    }

    @Test
    fun homeworkList_401isApiException() = runBlocking {
        val fake = FakeResourceApi().apply {
            homeworkError = 401 to """{"error":"Ungültig.","code":"TOKEN_INVALID"}"""
        }
        assertEquals("TOKEN_INVALID", apiExceptionOf(HomeworkRepository(api = { fake }).list()).code)
        Unit
    }

    @Test
    fun homeworkDoneAndTrash_bodyKeys() = runBlocking {
        val fake = FakeResourceApi()
        val repo = HomeworkRepository(api = { fake })
        // api/homework.py: done → {done}, trash → {hide} (Alias {trash} nicht nötig).
        repo.setDone(3, true)
        assertEquals("true", fake.lastDone?.get("done").toString())
        repo.setTrash(3, false)
        assertEquals("false", fake.lastTrash?.get("hide").toString())
        Unit
    }

    @Test
    fun gradesList_numericIdAndCache() = runBlocking {
        val fake = FakeResourceApi().apply {
            gradesJson = """{"items":[{"id":123,"title":"KA","subject":"Mathe","grade_num":2.0,"weight":1.0,
                "date_iso":"2025-11-03","sort_key":"2025-11-03","is_classic":true}],"total":1,"limit":50,"offset":0,"cache_info":"c"}"""
        }
        val page = GradesRepository(api = { fake }).list().getOrThrow()
        // FlexibleStringSerializer: numerische ID → String.
        assertEquals("123", page.items.single().id)
        assertEquals("c", page.cache_info)
        Unit
    }

    // ---- Stundenplan + Essen/Wetter (Paket D) --------------------------

    @Test
    fun timetableDay_decodesLessons() = runBlocking {
        val fake = FakeResourceApi().apply {
            dayJson = """{"day":"2026-09-24","day_label":"Donnerstag 24.09.2026","prev_day":"2026-09-23",
                "next_day":"2026-09-25","today":"2026-09-24",
                "lessons":[{"period":"1","time":"07:40–08:25","title":"Mathe","is_cancelled":false}],"cache_info":""}"""
        }
        val day = TimetableRepository(api = { fake }).day().getOrThrow()
        assertEquals("2026-09-24", day.day)
        assertEquals("Mathe", day.lessons.single().title)
        Unit
    }

    @Test
    fun timetableWeek_decodesDays() = runBlocking {
        val fake = FakeResourceApi().apply {
            weekJson = """{"day":"2026-09-24","monday":"2026-09-21","week_label":"Woche 21.09. – 25.09.2026",
                "days":[{"date":"2026-09-24","day_name":"Donnerstag","day_date":"24.09.","is_today":true,"lessons":[]}],"cache_info":""}"""
        }
        val week = TimetableRepository(api = { fake }).week().getOrThrow()
        assertEquals("2026-09-21", week.monday)
        assertTrue(week.days.single().is_today)
        Unit
    }

    @Test
    fun essen_decodesWeekAndToday() = runBlocking {
        val fake = FakeResourceApi().apply {
            essenJson = """{"week":"2026-W39","label":"KW 39","source_url":"https://x/y.pdf",
                "days":{"Montag":{"date":"2026-09-21","dishes":[{"text":"Pasta","price":"3,50 €"}],"note":""},
                "Dienstag":{"date":"2026-09-22","dishes":[],"note":"Feiertag"}},
                "today":"Montag","cached":false,"cache_info":"frisch"}"""
        }
        val menu = MetaRepository(api = { fake }).essen().getOrThrow()
        assertEquals("Pasta", menu.todayMenu?.dishes?.single()?.text)
        assertEquals("3,50 €", menu.todayMenu?.dishes?.single()?.price)
        Unit
    }

    @Test
    fun wetter_decodesPayloadAndCityParam() = runBlocking {
        val fake = FakeResourceApi().apply {
            wetterJson = """{"city":"Wien","today":{"temp":18,"max":21,"min":12,"desc":"Leicht bewölkt","icon":"02d","pop":10},
                "tomorrow":{"max":22,"min":13,"desc":"Sonne"},"day3":{},"hourly":[],"details":{"humidity":60}}"""
        }
        val repo = MetaRepository(api = { fake })
        val w = repo.wetter(city = "Wien").getOrThrow()
        assertEquals("Wien", w.city)
        assertEquals(18, w.today.temp)
        assertEquals(60, w.details.humidity)
        assertEquals("Wien", fake.lastWetter["city"])
        repo.wetter(city = "   ")
        // Leere Stadt → null (Backend meldet dann VALIDATION statt leere Query).
        assertNull(fake.lastWetter["city"])
        Unit
    }
}
