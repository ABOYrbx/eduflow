package de.eduflow.android

import de.eduflow.android.data.ApiClient
import de.eduflow.android.data.ApiException
import de.eduflow.android.data.ApiService
import de.eduflow.android.data.ErrorMapper
import de.eduflow.android.data.SettingsRepository
import de.eduflow.android.data.dto.CacheClearResponse
import de.eduflow.android.data.dto.DeviceDto
import de.eduflow.android.data.dto.DevicesDto
import de.eduflow.android.data.dto.ErrorCodes
import de.eduflow.android.data.dto.LoginRequest
import de.eduflow.android.data.dto.LoginResponse
import de.eduflow.android.data.dto.MeDto
import de.eduflow.android.data.dto.SettingsResponse
import de.eduflow.android.data.dto.StatusDto
import de.eduflow.android.data.dto.TwoFaRequest
import de.eduflow.android.data.dto.typedValues
import de.eduflow.android.data.unwrap
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.ResponseBody
import okhttp3.ResponseBody.Companion.toResponseBody
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import retrofit2.Response
import kotlinx.serialization.json.JsonObject

/**
 * Paket A — Offline-Tests (ANDROID.md §2/§7).
 *
 * Kein echtes Login, kein Netz: Fake-[ApiService], nur Routenform,
 * Fehlercodes und 401-Verhalten. AuthRepository ist hier nicht direkt
 * testbar (braucht TokenStore/Context) — abgedeckt sind DTOs,
 * [ErrorMapper], [unwrap] und [SettingsRepository].
 */
class AuthPackageTest {

    // ---- DTO: Login-Antwort (api/auth.py: ok vs. 2fa_required) ----

    @Test
    fun loginResponseFlags_ok() {
        val res = LoginResponse(status = "ok", token = "t", expires = "e")
        assertTrue(res.isOk)
        assertFalse(res.isTwoFa)
    }

    @Test
    fun loginResponseFlags_twoFa() {
        val res = LoginResponse(status = "2fa_required", pending_token = "p")
        assertTrue(res.isTwoFa)
        assertFalse(res.isOk)
    }

    // ---- Fehler-Vokabular 1:1 aus api/core.py ERROR_CODES ----

    @Test
    fun errorCodes_matchBackend() {
        val expected = setOf(
            "VALIDATION", "TOKEN_INVALID", "TOKEN_EXPIRED",
            "PENDING_INVALID", "INVALID_CODE", "BAD_CREDENTIALS",
            "EDUPAGE_2FA", "CAPTCHA_REQUIRED", "NOT_FOUND",
            "RATE_LIMITED", "CONFIG_MISSING", "UPSTREAM",
        )
        val actual = setOf(
            ErrorCodes.VALIDATION, ErrorCodes.TOKEN_INVALID,
            ErrorCodes.TOKEN_EXPIRED, ErrorCodes.PENDING_INVALID,
            ErrorCodes.INVALID_CODE, ErrorCodes.BAD_CREDENTIALS,
            ErrorCodes.EDUPAGE_2FA, ErrorCodes.CAPTCHA_REQUIRED,
            ErrorCodes.NOT_FOUND, ErrorCodes.RATE_LIMITED,
            ErrorCodes.CONFIG_MISSING, ErrorCodes.UPSTREAM,
        )
        assertEquals(expected, actual)
    }

    @Test
    fun errorTexts_areGermanAndShort() {
        // 401-Verhalten (→ Login): Texte verweisen aufs Neuanmelden,
        // enthalten aber nie Token/Secrets/Stacktraces.
        val relogin = listOf(
            ErrorCodes.TOKEN_INVALID, ErrorCodes.TOKEN_EXPIRED,
            ErrorCodes.BAD_CREDENTIALS, ErrorCodes.EDUPAGE_2FA,
        )
        relogin.forEach { code ->
            val msg = ErrorMapper.messageFor(code)
            assertTrue("$code ohne Text", msg.isNotBlank())
            assertTrue("$code ohne Anmelde-Hinweis: $msg", "meld" in msg.lowercase())
            assertFalse("$code mit Secret: $msg", "Bearer" in msg || "token " in msg.lowercase())
        }
        assertTrue("429 mit Hinweis", "später" in ErrorMapper.messageFor(ErrorCodes.RATE_LIMITED))
        assertTrue(
            "Captcha mit Browser-Hinweis",
            "Browser" in ErrorMapper.messageFor(ErrorCodes.CAPTCHA_REQUIRED),
        )
    }

    @Test
    fun errorResMapping_coversAllCodes() {
        // stringResFor: kontextfreie Code->error_*-Abbildung für Compose
        // (R-IDs sind Compilezeit-Konstanten, daher offline testbar).
        val expected = mapOf(
            ErrorCodes.VALIDATION to R.string.error_validation,
            ErrorCodes.TOKEN_INVALID to R.string.error_token_invalid,
            ErrorCodes.TOKEN_EXPIRED to R.string.error_token_expired,
            ErrorCodes.PENDING_INVALID to R.string.error_pending_invalid,
            ErrorCodes.INVALID_CODE to R.string.error_invalid_code,
            ErrorCodes.BAD_CREDENTIALS to R.string.error_bad_credentials,
            ErrorCodes.EDUPAGE_2FA to R.string.error_edupage_2fa,
            ErrorCodes.CAPTCHA_REQUIRED to R.string.error_captcha_required,
            ErrorCodes.NOT_FOUND to R.string.error_not_found,
            ErrorCodes.RATE_LIMITED to R.string.error_rate_limited,
            ErrorCodes.CONFIG_MISSING to R.string.error_config_missing,
            ErrorCodes.UPSTREAM to R.string.error_upstream,
        )
        expected.forEach { (code, res) ->
            assertEquals(code, res, ErrorMapper.stringResFor(code))
        }
        // Unbekannte Codes fallen wie messageFor auf UPSTREAM.
        assertEquals(R.string.error_upstream, ErrorMapper.stringResFor("E328"))
        assertEquals(R.string.error_upstream, ErrorMapper.stringResFor(""))
    }

    @Test
    fun apiException_messageResOptional() {
        // Default null = Server-Fehler (Backend-Text hat Vorrang);
        // gesetzt = clientseitige Validierung (Compose löst per stringResource).
        assertNull(ApiException("UPSTREAM", "x").messageRes)
        val e = ApiException("VALIDATION", "x", messageRes = R.string.auth_error_credentials)
        assertEquals(R.string.auth_error_credentials, e.messageRes)
    }

    @Test
    fun parseErrorBody_keepsStableCodes() {
        val codes = listOf(
            "BAD_CREDENTIALS", "CAPTCHA_REQUIRED", "PENDING_INVALID",
            "INVALID_CODE", "RATE_LIMITED", "VALIDATION",
            "TOKEN_INVALID", "TOKEN_EXPIRED",
        )
        codes.forEach { code ->
            val (parsed, msg) = ErrorMapper.parseErrorBody(
                "{\"error\":\"Backend-Text\",\"code\":\"$code\"}",
            )
            assertEquals(code, parsed)
            // Backend-Text hat Vorrang vor Fallback.
            assertEquals("Backend-Text", msg)
        }
    }

    @Test
    fun parseErrorBody_tolerant() {
        assertEquals("UPSTREAM", ErrorMapper.parseErrorBody(null).first)
        assertEquals("UPSTREAM", ErrorMapper.parseErrorBody("").first)
        assertEquals("UPSTREAM", ErrorMapper.parseErrorBody("kein-json{{{").first)
        // Leerer Code fällt auf UPSTREAM, leere Meldung auf Fallback.
        val (code, msg) = ErrorMapper.parseErrorBody("{\"error\":\"\",\"code\":\"\"}")
        assertEquals("UPSTREAM", code)
        assertTrue(msg.isNotBlank())
    }

    // ---- unwrap(): stabile Codes + HTTP-Status (Paket-A-Routen) ----

    private fun <T> err(status: Int, code: String, msg: String = "Backend-Text"): Response<T> =
        Response.error(
            status,
            "{\"error\":\"$msg\",\"code\":\"$code\"}"
                .toResponseBody("application/json".toMediaType()),
        )

    private fun expectApi(status: Int, code: String, block: suspend () -> Unit) = runBlocking {
        try {
            block()
            fail("ApiException($code) erwartet")
        } catch (e: ApiException) {
            assertEquals(code, e.code)
            assertEquals(status, e.httpStatus)
        }
    }

    @Test
    fun unwrap_successReturnsBody() = runBlocking {
        val body = LoginResponse(status = "ok", token = "t")
        assertEquals("t", Response.success(body).unwrap().token)
    }

    @Test
    fun unwrap_badCredentials401() = expectApi(401, "BAD_CREDENTIALS") {
        err<LoginResponse>(401, "BAD_CREDENTIALS").unwrap()
    }

    @Test
    fun unwrap_captcha403() = expectApi(403, "CAPTCHA_REQUIRED") {
        err<LoginResponse>(403, "CAPTCHA_REQUIRED").unwrap()
    }

    @Test
    fun unwrap_rateLimited429() = expectApi(429, "RATE_LIMITED") {
        err<LoginResponse>(429, "RATE_LIMITED").unwrap()
    }

    @Test
    fun unwrap_tokenInvalid401() = expectApi(401, "TOKEN_INVALID") {
        err<MeDto>(401, "TOKEN_INVALID").unwrap()
    }

    @Test
    fun unwrap_tokenExpired401() = expectApi(401, "TOKEN_EXPIRED") {
        err<MeDto>(401, "TOKEN_EXPIRED").unwrap()
    }

    @Test
    fun unwrap_pendingInvalid401() = expectApi(401, "PENDING_INVALID") {
        err<LoginResponse>(401, "PENDING_INVALID").unwrap()
    }

    @Test
    fun unwrap_invalidCode401() = expectApi(401, "INVALID_CODE") {
        err<LoginResponse>(401, "INVALID_CODE").unwrap()
    }

    @Test
    fun unwrap_validation400() = expectApi(400, "VALIDATION") {
        err<LoginResponse>(400, "VALIDATION").unwrap()
    }

    // ---- Einstellungen: Defaults/Clamping wie app.py SETTINGS_SCHEMA ----

    private fun settingsResponse(vararg pairs: Pair<String, String>): SettingsResponse =
        SettingsResponse(
            schema = emptyList(),
            values = buildJsonObject {
                pairs.forEach { (k, v) -> put(k, JsonPrimitive(v)) }
            },
        )

    @Test
    fun settingsTypedValues_invalidFallBackToDefaults() {
        val values = settingsResponse(
            "landing" to "gibts-nicht",
            "hw_status" to "gibts-nicht",
            "ov_unread" to "999",
            "ov_homework" to "-5",
        ).typedValues()
        assertEquals("uebersicht", values.landing)
        assertEquals("alle", values.hwStatus)
        assertEquals(50, values.ovUnread)
        assertEquals(1, values.ovHomework)
        assertTrue(values.ovWetter) // Default: Wetterkarte an
        assertEquals("", values.wetterCity)
    }

    @Test
    fun settingsTypedValues_wetter() {
        val values = SettingsResponse(
            values = buildJsonObject {
                put("ov_wetter", JsonPrimitive(false))
                put("wetter_city", JsonPrimitive("  Wien\n"))
            },
        ).typedValues()
        assertFalse(values.ovWetter)
        assertEquals("Wien", values.wetterCity)
        // Überlange Stadt wird auf 100 Zeichen gekürzt (wie _coerce_setting).
        val long = SettingsResponse(
            values = buildJsonObject {
                put("wetter_city", JsonPrimitive("x".repeat(150)))
            },
        ).typedValues()
        assertEquals(100, long.wetterCity.length)
    }

    @Test
    fun settingsTypedValues_boolForms() {
        val fromForm = settingsResponse("hw_tests" to "1").typedValues()
        assertTrue(fromForm.hwTests)
        val fromJson = SettingsResponse(
            values = buildJsonObject { put("hw_tests", JsonPrimitive(true)) },
        ).typedValues()
        assertTrue(fromJson.hwTests)
    }

    // ---- SettingsRepository gegen Fake-ApiService ----

    @Test
    fun settingsLoad_parity() = runBlocking {
        val fake = FakeApi(
            settingsGet = SettingsResponse(
                values = buildJsonObject {
                    put("landing", JsonPrimitive("dashboard"))
                    put("ov_unread", JsonPrimitive(7))
                },
            ),
        )
        val repo = SettingsRepository(api = { fake })
        val (_, values) = repo.load()
        assertEquals("dashboard", values.landing)
        assertEquals(7, values.ovUnread)
        assertEquals("alle", values.hwStatus) // Rest: Defaults
        Unit
    }

    @Test
    fun settingsSave_sendsRealJsonBools() = runBlocking {
        // Backend PUT liefert {status, values} OHNE schema (api/settings.py)
        // — muss trotzdem parsen (ignoreUnknownKeys + Defaults).
        val fake = FakeApi(
            settingsPutResult = SettingsResponse(
                values = buildJsonObject {
                    put("landing", JsonPrimitive("noten"))
                    put("hw_tests", JsonPrimitive(true))
                },
            ),
        )
        val repo = SettingsRepository(api = { fake })
        val saved = repo.save(
            de.eduflow.android.data.dto.SettingsValues(
                landing = "noten", hwTests = true,
            ),
        )
        val sent = checkNotNull(fake.capturedPut) { "PUT-Body fehlt" }
        // Booleans als echte JSON-bools, keine "1"/"0"-Strings.
        val hwTests = sent["hw_tests"]!!.jsonPrimitive
        assertFalse("Bool darf kein String sein", hwTests.isString)
        assertEquals(true, hwTests.booleanOrNull)
        // Wetter-Einstellungen werden mitgespeichert (sonst setzt PUT sie
        // serverseitig auf Defaults zurück).
        assertEquals(true, sent["ov_wetter"]!!.jsonPrimitive.booleanOrNull)
        assertEquals("", sent["wetter_city"]!!.jsonPrimitive.content)
        assertEquals("noten", saved.landing)
        assertTrue(saved.hwTests)
        Unit
    }

    @Test
    fun settingsSave_validationError() {
        val fake = FakeApi(
            putError = 400 to "{\"error\":\"Ungültige Anfrage.\",\"code\":\"VALIDATION\"}",
        )
        val repo = SettingsRepository(api = { fake })
        expectApi(400, "VALIDATION") {
            repo.save(de.eduflow.android.data.dto.SettingsValues())
        }
    }

    @Test
    fun settingsLoad_tokenExpired401() {
        val fake = FakeApi(
            getError = 401 to "{\"error\":\"Abgelaufen.\",\"code\":\"TOKEN_EXPIRED\"}",
        )
        val repo = SettingsRepository(api = { fake })
        // 401-Verhalten: Repository wirft stabilen Code, ViewModel
        // leert den Store und navigiert zum Login.
        expectApi(401, "TOKEN_EXPIRED") { repo.load() }
    }

    @Test
    fun clearCache_shape() = runBlocking {
        val fake = FakeApi(clearResult = CacheClearResponse(status = "ok", cleared = 3))
        assertEquals(3, SettingsRepository(api = { fake }).clearCache().cleared)
        Unit
    }

    // ---- Geräte: keine Secrets in DTOs, unbekannte Felder tolerant ----

    @Test
    fun devicesDto_ignoresUnknownSecretFields() {
        // Server liefert nur {id, short, device, created, expires}
        // (api/core.py list_user_tokens) — selbst falls je ein
        // Secret-Feld auftaucht, darf es nicht ins DTO.
        val parsed = de.eduflow.android.data.EduFlowJson.decodeFromString(
            DevicesDto.serializer(),
            "{\"items\":[{\"id\":\"abc\",\"short\":\"…bc\",\"device\":\"Pixel\"," +
                "\"created\":\"c\",\"expires\":\"e\"," +
                "\"token\":\"SECRET\",\"pwd_enc\":\"SECRET\"}],\"total\":1}",
        )
        assertEquals(1, parsed.total)
        val encoded = de.eduflow.android.data.EduFlowJson.encodeToString(
            DeviceDto.serializer(), parsed.items.first(),
        )
        assertFalse("Secret im DTO: $encoded", "SECRET" in encoded)
        assertFalse("Token-Feld im DTO", "token" in encoded.lowercase())
    }

    // ---- Basis-URL: trimEnd('/')-Roundtrip (TokenStore/LoginScreen) ----

    @Test
    fun baseUrl_withAndWithoutTrailingSlash() {
        // ApiClient.create normalisiert (Paket 0) — beide Formen ok.
        listOf(
            "http://10.0.2.2:8000/api/v1/",
            "http://10.0.2.2:8000/api/v1",
        ).forEach { base ->
            // Wirft bei ungültiger Basis-URL (Retrofit verlangt Host + /-Suffix).
            assertNotNull(ApiClient.create(base) { null })
        }
    }
}

/**
 * Fake-[ApiService] für Paket A: nur Auth/Settings/Cache funktional,
 * Rest wirft (Pakete B–D testen ihre Routen selbst).
 */
private class FakeApi(
    var settingsGet: SettingsResponse = SettingsResponse(),
    var settingsPutResult: SettingsResponse = SettingsResponse(),
    var clearResult: CacheClearResponse = CacheClearResponse(),
    var getError: Pair<Int, String>? = null,
    var putError: Pair<Int, String>? = null,
    var capturedPut: JsonObject? = null,
) : ApiService {
    private fun <T> failure(err: Pair<Int, String>?): Response<T>? =
        err?.let {
            Response.error(
                it.first,
                it.second.toResponseBody("application/json".toMediaType()),
            )
        }

    override suspend fun health(): Response<JsonObject> =
        throw UnsupportedOperationException("Paket A nutzt health nicht")

    override suspend fun login(body: LoginRequest): Response<LoginResponse> =
        throw UnsupportedOperationException("Offline-Test ohne Login-Aufruf")

    override suspend fun submit2fa(body: TwoFaRequest): Response<LoginResponse> =
        throw UnsupportedOperationException("Offline-Test ohne 2FA-Aufruf")

    override suspend fun logout(): Response<StatusDto> = Response.success(StatusDto())

    override suspend fun refresh(): Response<LoginResponse> =
        throw UnsupportedOperationException("Paket A-Test ohne Refresh")

    override suspend fun me(): Response<MeDto> =
        throw UnsupportedOperationException("Paket A-Test ohne me()")

    override suspend fun devices(): Response<DevicesDto> =
        Response.success(DevicesDto())

    override suspend fun revokeDevice(id: String): Response<StatusDto> =
        Response.success(StatusDto())

    override suspend fun getSettings(): Response<SettingsResponse> =
        failure<SettingsResponse>(getError) ?: Response.success(settingsGet)

    override suspend fun putSettings(values: JsonObject): Response<SettingsResponse> {
        capturedPut = values
        return failure<SettingsResponse>(putError) ?: Response.success(settingsPutResult)
    }

    override suspend fun clearCache(): Response<CacheClearResponse> =
        Response.success(clearResult)

    override suspend fun messages(
        since: String?,
        type: String?,
        q: String?,
        limit: Int?,
        offset: Int?,
        refresh: Int?,
    ): Response<JsonObject> = throw UnsupportedOperationException("Paket B")

    override suspend fun messageThread(id: Long, refresh: Int?): Response<JsonObject> =
        throw UnsupportedOperationException("Paket B")

    override suspend fun markRead(): Response<JsonObject> =
        throw UnsupportedOperationException("Paket B")

    override suspend fun recipients(limit: Int?, offset: Int?): Response<JsonObject> =
        throw UnsupportedOperationException("Paket B")

    override suspend fun sendMessage(body: JsonObject): Response<JsonObject> =
        throw UnsupportedOperationException("Paket B")

    override suspend fun replyMessage(id: Long, body: JsonObject): Response<JsonObject> =
        throw UnsupportedOperationException("Paket B")

    override suspend fun attachment(
        id: Long,
        idx: Int,
        token: String?,
        dl: String?,
    ): Response<ResponseBody> = throw UnsupportedOperationException("Paket B")

    override suspend fun downloadToken(body: JsonObject): Response<JsonObject> =
        throw UnsupportedOperationException("Paket B")

    override suspend fun homework(
        since: String?,
        status: String?,
        includeTests: Int?,
        q: String?,
        limit: Int?,
        offset: Int?,
        refresh: Int?,
    ): Response<JsonObject> = throw UnsupportedOperationException("Paket C")

    override suspend fun homeworkDone(id: Long, body: JsonObject): Response<JsonObject> =
        throw UnsupportedOperationException("Paket C")

    override suspend fun homeworkTrash(id: Long, body: JsonObject): Response<JsonObject> =
        throw UnsupportedOperationException("Paket C")

    override suspend fun grades(
        limit: Int?,
        offset: Int?,
        refresh: Int?,
    ): Response<JsonObject> = throw UnsupportedOperationException("Paket C")

    override suspend fun timetableDay(day: String?, refresh: Int?): Response<JsonObject> =
        throw UnsupportedOperationException("Paket D")

    override suspend fun timetableWeek(day: String?, refresh: Int?): Response<JsonObject> =
        throw UnsupportedOperationException("Paket D")

    override suspend fun schoolAgenda(
        since: String,
        until: String,
        refresh: Int?,
    ): Response<JsonObject> = throw UnsupportedOperationException("Schulalltag")

    override suspend fun substitutionsWeek(day: String): Response<JsonObject> =
        throw UnsupportedOperationException("Schulalltag")

    override suspend fun wetter(
        lat: Double?,
        lon: Double?,
        city: String?,
    ): Response<JsonObject> = throw UnsupportedOperationException("Paket D")

    override suspend fun searchWetterCities(query: String): Response<JsonObject> =
        throw UnsupportedOperationException("Wetter-Ortssuche")
}
