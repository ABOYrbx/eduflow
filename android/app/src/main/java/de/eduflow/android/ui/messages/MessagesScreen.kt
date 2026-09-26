package de.eduflow.android.ui.messages

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.AttachFile
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Snackbar
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.ButtonDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import de.eduflow.android.data.dto.ErrorCodes
import de.eduflow.android.data.dto.MessageDto
import de.eduflow.android.data.dto.MsgFilter
import de.eduflow.android.data.dto.bodyLine
import de.eduflow.android.ui.common.AppHeader
import de.eduflow.android.ui.common.AvatarDot
import de.eduflow.android.ui.common.EduCard
import de.eduflow.android.ui.common.FilterChips
import de.eduflow.android.ui.common.PrimaryButton
import de.eduflow.android.ui.common.ScreenHead
import de.eduflow.android.ui.common.SearchPill
import de.eduflow.android.ui.common.SectionLabel

private const val BODY_MAX = 5000

private fun initialsOf(name: String): String =
    name.split(" ", " ").mapNotNull { it.firstOrNull()?.toString() }.take(2).joinToString("")

/**
 * Nachrichten-Screen (Paket C, Redesign-PNG Screen 02).
 *
 * Header, Titel + Untertitel, Suche, Chips Alle/Ungelesen/Mit Dateien,
 * Avatar-Karten (Name + Zeit, Betreff fett, Vorschau grau, Punkt bei
 * ungelesen), FAB zum Verfassen.
 */
@Composable
fun MessagesScreen(
    viewModel: MessagesViewModel,
    onOpenThread: (Int) -> Unit,
    onCompose: () -> Unit,
    onAttachment: (Int, Int) -> Unit,
    onOpenSettings: () -> Unit = {},
    onLogout: () -> Unit = {},
    onReLogin: () -> Unit = {},
    modifier: Modifier = Modifier,
) {
    val state by viewModel.state.collectAsState()
    val visible = state.visible

    Box(modifier = modifier.fillMaxSize()) {
        Column(Modifier.fillMaxSize().padding(16.dp)) {
            AppHeader(
                    onSettings = onOpenSettings,
                onLogout = onLogout,
            )
            Spacer(Modifier.height(12.dp))
            ScreenHead(
                title = "Nachrichten",
                subtitle = "Mitteilungen aus deiner Schule",
            )
            Spacer(Modifier.height(12.dp))
            SearchPill(
                value = state.query,
                onValueChange = viewModel::onQuery,
                placeholder = "Nachrichten durchsuchen",
            )
            Spacer(Modifier.height(10.dp))
            FilterChips(
                options = MsgFilter.entries.map { it.label },
                selected = state.filter.label,
                onSelect = { label ->
                    MsgFilter.entries.firstOrNull { it.label == label }
                        ?.let(viewModel::onFilter)
                },
            )
            Spacer(Modifier.height(10.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                SectionLabel(
                    "${visible.size} von ${state.total} Nachrichten",
                    modifier = Modifier.weight(1f),
                )
                TextButton(onClick = viewModel::markRead) { Text("Alle gelesen") }
                IconButton(onClick = viewModel::refresh, enabled = !state.isLoading) {
                    Icon(Icons.Filled.Refresh, contentDescription = "Neu laden")
                }
            }
            if (state.marked > 0) {
                Text(
                    "${state.marked} als gelesen markiert.",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            Spacer(Modifier.height(4.dp))

            state.error?.let { err ->
                MessageAuthError(
                    message = "${err.message} (${err.code})",
                    code = err.code,
                    onReLogin = onReLogin,
                    onDismiss = viewModel::dismissError,
                )
            }

            if (state.isLoading && state.items.isEmpty()) {
                Row(
                    modifier = Modifier.fillMaxWidth().padding(32.dp),
                    horizontalArrangement = Arrangement.Center,
                ) { CircularProgressIndicator() }
            } else if (visible.isEmpty()) {
                Column(
                    modifier = Modifier.fillMaxWidth().padding(24.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Text(
                        when (state.filter) {
                            MsgFilter.UNGELESEN -> "Alles gelesen. Sehr gut."
                            MsgFilter.MIT_DATEIEN -> "Keine Nachrichten mit Dateien."
                            MsgFilter.ALLE -> "Keine Nachrichten gefunden."
                        },
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    TextButton(onClick = viewModel::refresh) { Text("Neu laden") }
                }
            } else {
                LazyColumn(
                    verticalArrangement = Arrangement.spacedBy(10.dp),
                    modifier = Modifier.weight(1f),
                ) {
                    items(visible, key = { it.id }) { item ->
                        MessageCard(
                            item = item,
                            unread = item.id !in state.seenIds,
                            onOpenThread = {
                                viewModel.openThread(item.id)
                                onOpenThread(item.id)
                            },
                            onAttachment = { idx -> onAttachment(item.id, idx) },
                        )
                    }
                    if (state.canLoadMore) {
                        item {
                            TextButton(
                                onClick = viewModel::loadMore,
                                enabled = !state.isLoadingMore,
                                modifier = Modifier.fillMaxWidth(),
                            ) {
                                if (state.isLoadingMore) {
                                    CircularProgressIndicator(
                                        modifier = Modifier.size(16.dp)
                                            .padding(end = 8.dp),
                                    )
                                }
                                Text("Mehr laden (${state.items.size}/${state.total})")
                            }
                        }
                    }
                    item { Spacer(Modifier.height(88.dp)) }
                }
            }
        }
        FloatingActionButton(
            onClick = onCompose,
            shape = CircleShape,
            containerColor = MaterialTheme.colorScheme.primary,
            contentColor = MaterialTheme.colorScheme.onPrimary,
            modifier = Modifier.align(Alignment.BottomEnd).padding(16.dp).size(56.dp),
        ) {
            Icon(Icons.Filled.Add, contentDescription = "Neue Nachricht")
        }
    }
}

/** Nachrichtenkarte wie im PNG: Avatar, Name + Zeit, Betreff, Vorschau. */
@Composable
fun MessageCard(
    item: MessageDto,
    onOpenThread: () -> Unit,
    onAttachment: (Int) -> Unit,
    unread: Boolean = false,
) {
    val scheme = MaterialTheme.colorScheme
    EduCard(
        modifier = Modifier.fillMaxWidth()
            .clip(MaterialTheme.shapes.medium)
            .clickable(onClick = onOpenThread),
    ) {
        Row(modifier = Modifier.fillMaxWidth()) {
            AvatarDot(initials = initialsOf(item.author.ifBlank { "–" }))
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        item.author.ifBlank { "–" },
                        fontWeight = FontWeight.SemiBold,
                        style = MaterialTheme.typography.bodyMedium,
                        modifier = Modifier.weight(1f),
                    )
                    Text(
                        item.timestamp.ifBlank { item.timestamp_iso },
                        style = MaterialTheme.typography.labelSmall,
                        color = scheme.onSurfaceVariant,
                    )
                }
                Text(
                    item.bodyLine(),
                    style = MaterialTheme.typography.bodyMedium,
                    color = scheme.onSurfaceVariant,
                )
                if (item.attachments.isNotEmpty()) {
                    Spacer(Modifier.height(6.dp))
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        item.attachments.forEachIndexed { idx, att ->
                            TextButton(onClick = { onAttachment(idx) }) {
                                Icon(
                                    Icons.Filled.AttachFile,
                                    contentDescription = null,
                                    modifier = Modifier.size(14.dp),
                                )
                                Spacer(Modifier.width(2.dp))
                                Text(
                                    att.name.ifBlank { "Datei ${idx + 1}" },
                                    fontSize = 12.sp,
                                )
                            }
                        }
                    }
                }
                if (item.reaction_count > 0) {
                    Text(
                        "♥ ${item.reaction_count}",
                        style = MaterialTheme.typography.labelMedium,
                        color = scheme.onSurfaceVariant,
                        modifier = Modifier.padding(top = 2.dp),
                    )
                }
            }
            if (unread) {
                Box(
                    modifier = Modifier.padding(start = 8.dp, top = 4.dp).size(8.dp)
                        .clip(CircleShape)
                        .background(scheme.primary)
                        .clickable(onClick = onOpenThread),
                )
            }
        }
    }
}

/**
 * Thread-Screen (Paket C): Nachricht + Likes/Antworten + Antwort schreiben.
 * Antwort geht an alle im Thread (wie Web, recipient="" serverseitig).
 */
@Composable
fun ThreadScreen(
    viewModel: ThreadViewModel,
    message: MessageDto?,
    onAttachment: (Int, Int) -> Unit,
    onBack: () -> Unit,
    onReLogin: () -> Unit = {},
    modifier: Modifier = Modifier,
) {
    val state by viewModel.state.collectAsState()
    val thread = state.thread

    Column(modifier = modifier.fillMaxSize().padding(16.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = onBack) {
                Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Zurück")
            }
            ScreenHead(
                title = "Thread",
                subtitle = message?.author.orEmpty(),
                modifier = Modifier.weight(1f),
            )
            IconButton(onClick = viewModel::refresh, enabled = !state.isLoading) {
                Icon(Icons.Filled.Refresh, contentDescription = "Neu laden")
            }
        }

        Spacer(Modifier.height(8.dp))

        state.error?.let { err ->
            MessageAuthError(
                message = "${err.message} (${err.code})",
                code = err.code,
                onReLogin = onReLogin,
                onDismiss = viewModel::dismissError,
            )
        }

        if (thread?.cached == true) {
            Text(
                "Aus Cache geladen.",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Spacer(Modifier.height(4.dp))
        }

        if (state.isLoading && thread == null) {
            Row(
                modifier = Modifier.fillMaxWidth().padding(32.dp),
                horizontalArrangement = Arrangement.Center,
            ) { CircularProgressIndicator() }
            return
        }

        LazyColumn(
            verticalArrangement = Arrangement.spacedBy(10.dp),
            modifier = Modifier.weight(1f),
        ) {
            message?.let {
                item {
                    MessageCard(
                        item = it,
                        onOpenThread = {},
                        onAttachment = { idx -> onAttachment(it.id, idx) },
                    )
                }
            }
            val atts = message?.attachments.orEmpty()
            if (atts.isNotEmpty()) {
                item {
                    SectionLabel("Dateien (${atts.size})")
                }
                atts.forEachIndexed { idx, att ->
                    item {
                        EduCard(
                            modifier = Modifier.fillMaxWidth()
                                .clip(MaterialTheme.shapes.medium)
                                .clickable {
                                    message?.id?.let { id -> onAttachment(id, idx) }
                                },
                        ) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Icon(
                                    Icons.Filled.AttachFile,
                                    contentDescription = null,
                                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                                    modifier = Modifier.size(20.dp),
                                )
                                Spacer(Modifier.width(10.dp))
                                Text(
                                    att.name.ifBlank { "Datei ${idx + 1}" },
                                    style = MaterialTheme.typography.bodyMedium,
                                    modifier = Modifier.weight(1f),
                                )
                                Text(
                                    "Laden",
                                    style = MaterialTheme.typography.labelLarge,
                                    color = MaterialTheme.colorScheme.primary,
                                )
                            }
                        }
                    }
                }
            }
            if (!thread?.likes.isNullOrEmpty()) {
                item {
                    SectionLabel("Likes (${thread?.summary?.likes ?: thread?.likes?.size ?: 0})")
                }
                thread?.likes?.forEach { like ->
                    item {
                        Text(
                            "♥ ${like.name} · ${like.date}",
                            style = MaterialTheme.typography.bodyMedium,
                            modifier = Modifier.padding(horizontal = 4.dp),
                        )
                    }
                }
            }
            item {
                SectionLabel(
                    "Antworten (${thread?.summary?.replies ?: thread?.replies?.size ?: 0})",
                )
            }
            thread?.replies?.forEach { reply ->
                item {
                    EduCard(modifier = Modifier.fillMaxWidth()) {
                        Column(Modifier.fillMaxWidth()) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                AvatarDot(initials = initialsOf(reply.name))
                                Spacer(Modifier.width(10.dp))
                                Column(Modifier.weight(1f)) {
                                    Text(reply.name, fontWeight = FontWeight.SemiBold)
                                    Text(
                                        reply.date,
                                        style = MaterialTheme.typography.labelSmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    )
                                }
                            }
                            Spacer(Modifier.height(6.dp))
                            Text(reply.text, style = MaterialTheme.typography.bodyMedium)
                        }
                    }
                }
            }
            if (thread != null && thread.likes.isEmpty() && thread.replies.isEmpty()) {
                item {
                    Text(
                        "Noch keine Likes oder Antworten.",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(8.dp),
                    )
                }
            }
        }

        Spacer(Modifier.height(8.dp))

        OutlinedTextField(
            value = state.replyBody,
            onValueChange = viewModel::onReplyBody,
            placeholder = { Text("Antworten …") },
            modifier = Modifier.fillMaxWidth(),
            singleLine = false,
            minLines = 2,
            shape = RoundedCornerShape(16.dp),
            textStyle = MaterialTheme.typography.bodyMedium,
            colors = OutlinedTextFieldDefaults.colors(
                focusedContainerColor = MaterialTheme.colorScheme.surface,
                unfocusedContainerColor = MaterialTheme.colorScheme.surface,
                unfocusedBorderColor = MaterialTheme.colorScheme.outlineVariant,
                focusedBorderColor = MaterialTheme.colorScheme.primary,
                cursorColor = MaterialTheme.colorScheme.primary,
            ),
        )
        Spacer(Modifier.height(8.dp))
        PrimaryButton(
            text = if (state.isSending) "Wird gesendet …" else "Antworten",
            onClick = viewModel::sendReply,
            enabled = state.replyBody.isNotBlank() && !state.isSending,
        )
    }
}

/**
 * Verfassen-Screen (Paket C): Empfänger wählen + Text + Senden.
 * Nach Erfolg meldet [onSent] die neue Nachrichten-ID (Liste lädt neu).
 */
@Composable
fun ComposeScreen(
    viewModel: ComposeViewModel,
    onSent: (Int) -> Unit,
    onBack: () -> Unit,
    onReLogin: () -> Unit = {},
    modifier: Modifier = Modifier,
) {
    val state by viewModel.state.collectAsState()
    var filter by remember { mutableStateOf("") }

    val sentId = state.sentId
    LaunchedEffect(sentId) {
        if (sentId != null) onSent(sentId)
    }

    val visible = remember(state.recipients, filter) {
        if (filter.isBlank()) state.recipients
        else state.recipients.filter { it.name.contains(filter, ignoreCase = true) }
    }

    Column(modifier = modifier.fillMaxSize().padding(16.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = onBack) {
                Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Zurück")
            }
            ScreenHead(
                title = "Neue Nachricht",
                subtitle = "Lehrer und Mitschüler wählen",
            )
        }

        Spacer(Modifier.height(12.dp))

        state.error?.let { err ->
            MessageAuthError(
                message = "${err.message} (${err.code})",
                code = err.code,
                onReLogin = onReLogin,
                onDismiss = viewModel::dismissError,
            )
        }

        SearchPill(
            value = filter,
            onValueChange = { filter = it },
            placeholder = "Empfänger suchen",
        )

        Spacer(Modifier.height(8.dp))

        SectionLabel("${state.selectedIds.size} Empfänger gewählt")

        if (state.isLoadingRecipients) {
            Row(
                modifier = Modifier.fillMaxWidth().padding(16.dp),
                horizontalArrangement = Arrangement.Center,
            ) { CircularProgressIndicator() }
        } else {
            LazyColumn(
                modifier = Modifier.weight(1f).padding(top = 4.dp),
                verticalArrangement = Arrangement.spacedBy(2.dp),
            ) {
                items(visible, key = { it.id }) { rec ->
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Checkbox(
                            checked = rec.id in state.selectedIds,
                            onCheckedChange = { viewModel.toggleRecipient(rec.id) },
                        )
                        AvatarDot(initials = initialsOf(rec.name))
                        Spacer(Modifier.width(10.dp))
                        Column(Modifier.weight(1f)) {
                            Text(rec.name, fontWeight = FontWeight.Medium)
                            Text(
                                rec.kind,
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                }
            }
        }

        OutlinedTextField(
            value = state.body,
            onValueChange = { viewModel.onBody(it.take(BODY_MAX)) },
            placeholder = { Text("Nachrichtentext") },
            modifier = Modifier.fillMaxWidth(),
            singleLine = false,
            minLines = 3,
            shape = RoundedCornerShape(16.dp),
            textStyle = MaterialTheme.typography.bodyMedium,
            colors = OutlinedTextFieldDefaults.colors(
                focusedContainerColor = MaterialTheme.colorScheme.surface,
                unfocusedContainerColor = MaterialTheme.colorScheme.surface,
                unfocusedBorderColor = MaterialTheme.colorScheme.outlineVariant,
                focusedBorderColor = MaterialTheme.colorScheme.primary,
                cursorColor = MaterialTheme.colorScheme.primary,
            ),
        )
        Text(
            "${state.body.length}/$BODY_MAX",
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.align(Alignment.End),
        )
        Spacer(Modifier.height(4.dp))
        PrimaryButton(
            text = if (state.isSending) "Wird gesendet …" else "Senden",
            onClick = viewModel::send,
            enabled = !state.isSending,
        )
    }
}

/** Convenience-Überladung für Previews/Tests ohne manuelles ViewModel. */
@Composable
fun MessagesPreviewContent(items: List<MessageDto>) {
    LazyColumn(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        items(items, key = { it.id }) { item ->
            MessageCard(item = item, onOpenThread = {}, onAttachment = {})
        }
    }
}

/**
 * Fehler mit 401-Verhalten: abgelaufene/ungültige Sitzung (TOKEN_INVALID,
 * TOKEN_EXPIRED, EDUPAGE_2FA) führt zurück zum Login, alle anderen Fehler
 * sind nur verwerfbar (deutsche Kurztexte, keine Secrets).
 */
@Composable
private fun MessageAuthError(
    message: String,
    code: String,
    onReLogin: () -> Unit,
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val needsReLogin = code in
        listOf(ErrorCodes.TOKEN_INVALID, ErrorCodes.TOKEN_EXPIRED, ErrorCodes.EDUPAGE_2FA)
    Snackbar(
        action = {
            if (needsReLogin) {
                TextButton(
                    onClick = onReLogin,
                    colors = ButtonDefaults.textButtonColors(contentColor = Color.White),
                ) { Text("Anmelden") }
            } else {
                TextButton(
                    onClick = onDismiss,
                    colors = ButtonDefaults.textButtonColors(contentColor = Color.White),
                ) { Text("OK") }
            }
        },
        modifier = modifier.padding(bottom = 8.dp),
    ) { Text(message) }
}
