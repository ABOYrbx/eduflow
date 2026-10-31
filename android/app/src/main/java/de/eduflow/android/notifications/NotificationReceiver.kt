package de.eduflow.android.notifications

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.core.content.ContextCompat
import de.eduflow.android.data.ApiClient
import de.eduflow.android.data.TokenStore
import de.eduflow.android.R
import de.eduflow.android.data.dto.bodyLine
import de.eduflow.android.data.dto.HomeworkListResponse
import de.eduflow.android.data.dto.MessagesListResponse
import de.eduflow.android.data.dto.GradesListResponse
import de.eduflow.android.data.EduFlowJson
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.serialization.decodeFromString

class NotificationReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val pendingResult = goAsync()
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
        scope.launch {
            try {
                checkForUpdates(context)
            } catch (_: Exception) {
                // Best-effort: never crash the receiver.
            } finally {
                pendingResult.finish()
            }
        }
    }

    private suspend fun checkForUpdates(context: Context) {
        val store = TokenStore(context)
        val session = store.currentSession()
        if (!session.isLoggedIn) return

        NotificationHelper.ensureChannel(context)
        val api = ApiClient.create(session.baseUrl) { session.token }

        // Messages
        try {
            val resp = api.messages(limit = 30)
            val body = resp.body()
            if (resp.isSuccessful && body != null) {
                val parsed = EduFlowJson.decodeFromString<MessagesListResponse>(body.toString())
                val initialized = store.notifInitialized()
                val last = store.notifLastMessageIds()
                val newItems = if (initialized) parsed.items.filter { it.id !in last } else emptyList()
                for (msg in newItems) {
                    val title = msg.author.ifBlank { context.getString(R.string.notif_new_message_title) }
                    val text = msg.bodyLine(120).ifBlank { context.getString(R.string.notif_new_message_fallback) }
                    NotificationHelper.post(context, 1000 + msg.id, title, text)
                }
                store.setNotifLastMessageIds(parsed.items.map { it.id }.toSet())
            }
        } catch (_: Exception) { }

        // Homework
        try {
            val resp = api.homework(limit = 30)
            val body = resp.body()
            if (resp.isSuccessful && body != null) {
                val parsed = EduFlowJson.decodeFromString<HomeworkListResponse>(body.toString())
                val initialized = store.notifInitialized()
                val last = store.notifLastHomeworkIds()
                val newItems = if (initialized) parsed.items.filter { it.id !in last } else emptyList()
                for (hw in newItems) {
                    val title = context.getString(R.string.notif_new_homework_title)
                    val text = hw.title.ifBlank { hw.subject }
                    NotificationHelper.post(context, 2000 + hw.id.toInt(), title, text)
                }
                store.setNotifLastHomeworkIds(parsed.items.map { it.id }.toSet())
            }
        } catch (_: Exception) { }

        // Grades
        try {
            val resp = api.grades(limit = 30)
            val body = resp.body()
            if (resp.isSuccessful && body != null) {
                val parsed = EduFlowJson.decodeFromString<GradesListResponse>(body.toString())
                val initialized = store.notifInitialized()
                val last = store.notifLastGradeIds()
                val newItems = if (initialized) parsed.items.filter { it.id !in last } else emptyList()
                for (g in newItems) {
                    val title = context.getString(R.string.notif_new_grade_title)
                    val text = "${g.subject}: ${g.grade_display}".trim()
                    NotificationHelper.post(context, 3000 + (g.id.hashCode() and 0x7fffffff), title, text)
                }
                store.setNotifLastGradeIds(parsed.items.map { it.id }.toSet())
            }
        } catch (_: Exception) { }

        if (!store.notifInitialized()) {
            store.setNotifInitialized(true)
        }
    }
}
