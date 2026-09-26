package de.eduflow.android.data

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
}
