package de.eduflow.android.data

import android.content.ContentValues
import android.content.Context
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import de.eduflow.android.data.dto.DownloadTokenResponse
import de.eduflow.android.data.dto.MarkReadResponse
import de.eduflow.android.data.dto.MessageDto
import de.eduflow.android.data.dto.MessagesListResponse
import de.eduflow.android.data.dto.RecipientsListResponse
import de.eduflow.android.data.dto.ThreadResponse
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.decodeFromJsonElement
import java.io.File
import java.io.InputStream
import java.net.URLDecoder
import java.net.URLEncoder

/**
 * Nachrichten-Repository (Paket B, nur gegen frozen [ApiService]).
 *
 * Parameter 1:1 wie die API (api/messages.py):
 * since (YYYY-MM-DD, Standard 2000-01-01), type (Nachrichtentyp oder
 * leer = alle), q (Textsuche, alle Wörter), limit (1..200), offset,
 * refresh (0/1). Die Liste enthält nur Top-Level-Nachrichten
 * (Antworten filtert das Backend wie im Web via textReply raus).
 * Antwort-Dicts werden tolerant in typisierte DTOs
 * (data/dto/Messages.kt) dekodiert; Fehler via ApiException
 * (data/ErrorMapper.kt unwrap).
 *
 * Download: [attachmentUrl] stellt per Bearer-Header ein Kurzzeit-Token
 * aus und baut die URL für native Downloader mit `?dl=` (nie das
 * langlebige API-Token in der URL — das landete in Server-Logs).
 */
class MessagesRepository(
    private val api: () -> ApiService,
    private val baseUrl: String = "",
) {
    suspend fun list(
        since: String? = null,
        type: String = "",
        q: String = "",
        limit: Int = 50,
        offset: Int = 0,
        refresh: Boolean = false,
    ): Result<MessagesListResponse> = runCatching {
        val raw = api().messages(
            since = since?.takeIf { it.isNotBlank() },
            type = type.takeIf { it.isNotBlank() },
            q = q.takeIf { it.isNotBlank() },
            limit = limit.coerceIn(1, 200),
            offset = offset.coerceAtLeast(0),
            refresh = if (refresh) 1 else null,
        ).unwrap()
        EduFlowJson.decodeFromJsonElement(MessagesListResponse.serializer(), raw)
    }

    suspend fun thread(
        id: Int,
        refresh: Boolean = false,
    ): Result<ThreadResponse> = runCatching {
        val raw = api().messageThread(
            id = id.toLong(),
            refresh = if (refresh) 1 else null,
        ).unwrap()
        EduFlowJson.decodeFromJsonElement(ThreadResponse.serializer(), raw)
    }

    suspend fun markRead(): Result<MarkReadResponse> = runCatching {
        val raw = api().markRead().unwrap()
        EduFlowJson.decodeFromJsonElement(MarkReadResponse.serializer(), raw)
    }

    suspend fun recipients(
        limit: Int = 50,
        offset: Int = 0,
    ): Result<RecipientsListResponse> = runCatching {
        val raw = api().recipients(
            limit = limit.coerceIn(1, 200),
            offset = offset.coerceAtLeast(0),
        ).unwrap()
        EduFlowJson.decodeFromJsonElement(RecipientsListResponse.serializer(), raw)
    }

    suspend fun send(
        recipients: List<String>,
        body: String,
    ): Result<MessageDto> = runCatching {
        val payload = buildJsonObject {
            put("recipients", JsonArray(recipients.map { JsonPrimitive(it) }))
            put("body", JsonPrimitive(body))
        }
        val raw = api().sendMessage(payload).unwrap()
        EduFlowJson.decodeFromJsonElement(MessageDto.serializer(), raw)
    }

    suspend fun reply(
        id: Int,
        body: String,
    ): Result<ThreadResponse> = runCatching {
        val payload = buildJsonObject {
            put("body", JsonPrimitive(body))
        }
        val raw = api().replyMessage(id.toLong(), payload).unwrap()
        EduFlowJson.decodeFromJsonElement(ThreadResponse.serializer(), raw)
    }

    /**
     * Kurzzeit-Token für einen Anhang ausstellen (Bearer-Header, nie URL).
     * Gilt wenige Minuten und nur für genau diese Datei (event_id + idx).
     */
    suspend fun downloadToken(id: Int, idx: Int): Result<DownloadTokenResponse> = runCatching {
        val payload = buildJsonObject {
            put("event_id", JsonPrimitive(id))
            put("idx", JsonPrimitive(idx))
        }
        val raw = api().downloadToken(payload).unwrap()
        EduFlowJson.decodeFromJsonElement(DownloadTokenResponse.serializer(), raw)
    }

    /**
     * Download-URL für einen Anhang (idx = Position in message.attachments).
     * Das Kurzzeit-Token (`?dl=`) ist Absicht: native Download-Komponenten
     * können nicht immer Header setzen, und das langlebige API-Token gehört
     * nicht in URLs/Logs. Die URL zeigt immer auf den eigenen Server
     * (baseUrl); fremde Hosts lehnt das Backend ab (VALIDATION).
     */
    suspend fun attachmentUrl(id: Int, idx: Int): Result<String> = runCatching {
        val dl = downloadToken(id, idx).getOrThrow().download_token
        if (dl.isBlank()) throw ApiException("UPSTREAM", ErrorMapper.messageFor("UPSTREAM"))
        val base = baseUrl.trim().trimEnd('/')
        "$base/messages/$id/attachments/$idx?dl=" + URLEncoder.encode(dl, "UTF-8")
    }

    /**
     * Download an attachment through the API and save it to the device.
     * The backend serves the file from its own cache, so the client never
     * talks to EduPage directly. Returns the display name (or path on
     * Android < 10).
     */
    suspend fun downloadAttachment(context: Context, id: Int, idx: Int): Result<String> = runCatching {
        val dl = downloadToken(id, idx).getOrThrow().download_token
        if (dl.isBlank()) throw ApiException("UPSTREAM", ErrorMapper.messageFor("UPSTREAM"))
        val response = api().attachment(id.toLong(), idx, dl = dl)
        if (!response.isSuccessful) throw ApiException("UPSTREAM", ErrorMapper.messageFor("UPSTREAM"))
        val body = response.body() ?: throw ApiException("UPSTREAM", ErrorMapper.messageFor("UPSTREAM"))
        val filename = attachmentFilename(response.headers()["Content-Disposition"], id, idx)
        val contentType = response.headers()["Content-Type"]
            ?.substringBefore(';')?.trim()
            ?.ifBlank { "application/octet-stream" }
            ?: "application/octet-stream"
        body.use { saveAttachment(context, filename, contentType, it.byteStream()) }
    }

    private fun attachmentFilename(disposition: String?, id: Int, idx: Int): String {
        val fallback = "attachment-$id-$idx"
        if (disposition.isNullOrBlank()) return fallback
        val encoded = Regex("filename\\*=UTF-8''([^;]+)", RegexOption.IGNORE_CASE)
            .find(disposition)?.groupValues?.getOrNull(1)
        val plain = Regex("filename=\"?([^\";]+)\"?", RegexOption.IGNORE_CASE)
            .find(disposition)?.groupValues?.getOrNull(1)
        val raw = (encoded?.let { runCatching { URLDecoder.decode(it, "UTF-8") }.getOrNull() } ?: plain)
            ?.trim()
            ?: fallback
        return raw.replace(Regex("[\\\\/:*?\"<>|\\r\\n]"), "_").ifBlank { fallback }
    }

    private fun saveAttachment(
        context: Context,
        filename: String,
        contentType: String,
        input: InputStream,
    ): String {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, filename)
                put(MediaStore.MediaColumns.MIME_TYPE, contentType)
                put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
            val resolver = context.contentResolver
            val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                ?: throw ApiException("UPSTREAM", ErrorMapper.messageFor("UPSTREAM"))
            try {
                resolver.openOutputStream(uri)?.use { output ->
                    input.use { it.copyTo(output) }
                } ?: throw ApiException("UPSTREAM", ErrorMapper.messageFor("UPSTREAM"))
            } catch (error: Exception) {
                resolver.delete(uri, null, null)
                throw error
            }
            values.clear()
            values.put(MediaStore.MediaColumns.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
            return filename
        }
        val dir = context.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS)
            ?: File(context.filesDir, "downloads")
        if (!dir.exists()) dir.mkdirs()
        val target = uniqueFile(dir, filename)
        input.use { source -> target.outputStream().use { source.copyTo(it) } }
        return target.absolutePath
    }

    private fun uniqueFile(dir: File, filename: String): File {
        val first = File(dir, filename)
        if (!first.exists()) return first
        val dot = filename.lastIndexOf('.')
        val base = if (dot > 0) filename.substring(0, dot) else filename
        val ext = if (dot > 0) filename.substring(dot) else ""
        var n = 1
        while (true) {
            val candidate = File(dir, "$base ($n)$ext")
            if (!candidate.exists()) return candidate
            n += 1
        }
    }
}
