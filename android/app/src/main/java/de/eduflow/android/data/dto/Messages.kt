package de.eduflow.android.data.dto

import kotlinx.serialization.Serializable

/**
 * Nachricht 1:1 zum Web-Bauer (app.py event_to_dict).
 *
 * Liste: GET /api/v1/messages -> MessagesListResponse (nur Top-Level,
 * Antworten via textReply sind ausgeschlossen, neueste zuerst).
 * Senden: POST /messages/send -> MessageDto (die neue Nachricht).
 * (siehe api/messages.py, BACKEND.md §4 / Paket B).
 */
@Serializable
data class MessageDto(
    val id: Int = 0,
    val timestamp: String = "",
    val timestamp_iso: String = "",
    val sort_key: String = "",
    val author: String = "",
    val recipient: String = "",
    val type: String = "",
    val type_label: String = "",
    val text: String = "",
    val is_starred: Boolean = false,
    val is_done: Boolean = false,
    val reaction_count: Int = 0,
    val extra: String = "",
    val attachments: List<MessageAttachment> = emptyList(),
)

@Serializable
data class MessageAttachment(
    val name: String = "",
    val url: String = "",
)

/** Listen-Antwort: Page-Hülle wie alle Listen (BACKEND.md §1). */
@Serializable
data class MessagesListResponse(
    val items: List<MessageDto> = emptyList(),
    val total: Int = 0,
    val limit: Int = 50,
    val offset: Int = 0,
)

// ------------------------------------------------------------ Thread

@Serializable
data class ThreadLike(
    val name: String = "",
    val date: String = "",
)

@Serializable
data class ThreadReply(
    val name: String = "",
    val date: String = "",
    val text: String = "",
)

@Serializable
data class ThreadSummary(
    val total: Int = 0,
    val likes: Int = 0,
    val replies: Int = 0,
    val seen: Int = 0,
)

/**
 * Thread-Antwort: GET /messages/{id}/thread und POST /messages/{id}/reply.
 * (Likes, Antworten, Zusammenfassung aus app.py get_message_likes.)
 */
@Serializable
data class ThreadResponse(
    val likes: List<ThreadLike> = emptyList(),
    val replies: List<ThreadReply> = emptyList(),
    val reply_ids: List<String> = emptyList(),
    val summary: ThreadSummary = ThreadSummary(),
    val cached: Boolean = false,
)

// ------------------------------------------------------------ Empfänger

/**
 * Empfänger für den Verfassen-Dialog: Lehrer + Mitschüler (app.py get_recipients).
 * Liste: GET /api/v1/recipients (Page-Hülle, nach Name sortiert).
 */
@Serializable
data class RecipientDto(
    val id: String = "",
    val name: String = "",
    val kind: String = "",
)

@Serializable
data class RecipientsListResponse(
    val items: List<RecipientDto> = emptyList(),
    val total: Int = 0,
    val limit: Int = 50,
    val offset: Int = 0,
)

// ------------------------------------------------------------ Schreiben

/** POST /messages/send — Body {recipients, body} (IDs wie Teacher7). */
@Serializable
data class SendMessageRequest(
    val recipients: List<String>,
    val body: String,
)

/** POST /messages/{id}/reply — Body {body} (geht an alle im Thread). */
@Serializable
data class ReplyRequest(
    val body: String,
)

/** POST /messages/read — alle aktuellen Nachrichten als gelesen. */
@Serializable
data class MarkReadResponse(
    val marked: Int = 0,
)

/**
 * Kurzzeit-Download-Token: POST /messages/download-token —
 * Body {event_id, idx} → ein wenige Minuten gültiges Token für genau
 * diese Datei (statt langlebigem API-Token in der Download-URL).
 */
@Serializable
data class DownloadTokenResponse(
    val download_token: String = "",
    val expires_in: Int = 0,
)

/**
 * Kartentext: einzeilig normalisierter Nachrichtentext (max. 220 Zeichen).
 * (Kein Betreff — die API liefert kein Betreff-Feld.)
 */
fun MessageDto.bodyLine(max: Int = 220): String {
    val flat = text.split("\r\n", "\n", "\r").joinToString(" ").trim().replace(Regex("\\s+"), " ")
    if (flat.isEmpty()) return type_label.ifBlank { type }
    return flat.take(max) + if (flat.length > max) "…" else ""
}

/**
 * Listen-Filter aus dem Redesign-PNG (Screen 02):
 * Alle / Ungelesen (lokal, nicht in seen-Dateien) / Mit Dateien.
 * Der Server-Typfilter bleibt in der API, die UI nutzt diese Chips.
 */
enum class MsgFilter(val label: String) {
    ALLE("Alle"),
    UNGELESEN("Ungelesen"),
    MIT_DATEIEN("Mit Dateien"),
}

/**
 * Nachrichtentypen mit deutschem Label (app.py MESSAGE_TYPES + TYPE_LABELS).
 * Leerer Typ = alle nachrichtenartigen Typen (Web-Default).
 */
object MessageTypes {
    const val ALLE = ""
    const val SPRAVA = "sprava"
    const val NEWS = "news"
    const val ANKETA = "anketa"
    const val CHAT = "chat"
    const val GENOTIF = "genotif"

    val ALL = listOf(ALLE, SPRAVA, NEWS, ANKETA, CHAT, GENOTIF)

    fun label(type: String): String = when (type) {
        SPRAVA -> "Nachricht"
        NEWS -> "Neuigkeit"
        ANKETA -> "Umfrage"
        CHAT -> "Chat"
        GENOTIF -> "Mitteilung"
        else -> "Alle"
    }
}

/**
 * Empfänger-ID-Format wie serverseitig erwartet (Teacher|Student|… + Schlüssel).
 * Reine Format-Referenz für Tests — kein Sende-Gate: Die Auswahl stammt aus
 * der Server-Empfängerliste, der Server prüft Mitgliedschaft (dbi-Schlüssel
 * sind nicht überall rein numerisch).
 */
object RecipientIds {
    private val PATTERN =
        Regex("^(Teacher|Student|StudentOnly|Parent|Rodic|Ucitel)\\d+$", RegexOption.IGNORE_CASE)

    fun isValid(id: String): Boolean = PATTERN.matches(id.trim())

    fun clean(raw: Any?): List<String> {
        val list: List<String> = when (raw) {
            is String -> raw.split(",")
            is List<*> -> raw.filterIsInstance<String>()
            else -> return emptyList()
        }
        val seen = LinkedHashSet<String>()
        for (entry in list) {
            val id = entry.trim()
            if (id.isNotEmpty() && isValid(id)) seen.add(id)
        }
        return seen.toList()
    }
}
