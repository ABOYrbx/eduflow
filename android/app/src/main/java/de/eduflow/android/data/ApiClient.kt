package de.eduflow.android.data

import de.eduflow.android.BuildConfig
import retrofit2.converter.kotlinx.serialization.asConverterFactory
import kotlinx.serialization.json.Json
import okhttp3.Interceptor
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.logging.HttpLoggingInterceptor
import retrofit2.Retrofit

/** Geteilte kotlinx.serialization-Konfiguration (tolerant wie der Web-Cache). */
val EduFlowJson = Json {
    ignoreUnknownKeys = true
    isLenient = true
    explicitNulls = false
    coerceInputValues = true
}

/**
 * Retrofit-Bau (Paket 0). Genau eine Stelle für Client-Erzeugung.
 * Auth-Interceptor hängt das Bearer-Token an, außer auf NO_AUTH_SUFFIXES.
 */
object ApiClient {
    fun create(baseUrl: String, tokenProvider: () -> String?): ApiService {
        // Bereits gespeicherte URLs ohne Scheme (ältere App-Versionen)
        // dürfen nie wieder zum Start-Crash führen.
        val normalized = normalizeBaseUrl(baseUrl)
        val auth = Interceptor { chain ->
            val req = chain.request()
            val path = req.url.encodedPath
            val needsAuth = ApiService.NO_AUTH_SUFFIXES.none { path.endsWith(it) }
            val token = tokenProvider()
            if (needsAuth && !token.isNullOrBlank()) {
                chain.proceed(
                    req.newBuilder()
                        .header("Authorization", "Bearer $token")
                        .build(),
                )
            } else {
                chain.proceed(req)
            }
        }
        // HTTP-Log nur in Debug-Builds: BASIC loggt Request-URLs —
        // darunter Datei-Downloads mit ?token= (BACKEND.md §1 erlaubt den
        // Query-Token für native Downloader). Im Release dürfte der Token
        // sonst im Logcat landen. Keine Signaturänderung (Paket 0 frozen).
        val clientBuilder = OkHttpClient.Builder()
            .addInterceptor(auth)
        if (BuildConfig.DEBUG) {
            clientBuilder.addInterceptor(
                HttpLoggingInterceptor().apply {
                    level = HttpLoggingInterceptor.Level.BASIC
                },
            )
        }
        val client = clientBuilder.build()
        return Retrofit.Builder()
            .baseUrl(normalized)
            .client(client)
            .addConverterFactory(
                EduFlowJson.asConverterFactory("application/json".toMediaType()),
            )
            .build()
            .create(ApiService::class.java)
    }
}
