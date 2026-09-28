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
import androidx.compose.foundation.layout.navigationBarsPadding
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
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import de.eduflow.android.R
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
                title = stringResource(R.string.messages_title),
                subtitle = stringResource(R.string.messages_subtitle),
            )
            Spacer(Modifier.height(12.dp))
            SearchPill(
                value = state.query,
                onValueChange = viewModel::onQuery,
                placeholder = stringResource(R.string.messages_search_placeholder),
            )
            Spacer(Modifier.height(10.dp))
            val filterAll = stringResource(R.string.homework_filter_all)
            val filterUnread = stringResource(R.string.messages_filter_unread)
            val filterFiles = stringResource(R.string.messages_filter_files)
            val filterOptions = listOf(filterAll, filterUnread, filterFiles)
            val filterSelected = when (state.filter) {
                MsgFilter.UNGELESEN -> filterUnread
                MsgFilter.MIT_DATEIEN -> filterFiles
                MsgFilter.ALLE -> filterAll
            }
            FilterChips(
                options = filterOptions,
                selected = filterSelected,
                onSelect = { label ->
                    when (label) {
                        filterUnread -> viewModel.onFilter(MsgFilter.UNGELESEN)
                        filterFiles -> viewModel.onFilter(MsgFilter.MIT_DATEIEN)
                        else -> viewModel.onFilter(MsgFilter.ALLE)
                    }
                },
            )
            Spacer(Modifier.height(10.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                SectionLabel(
                    stringResource(R.string.messages_count_format, visible.size, state.total),
                    modifier = Modifier.weight(1f),
                )
                TextButton(onClick = viewModel::markRead) { Text(stringResource(R.string.messages_mark_all)) }
                IconButton(onClick = viewModel::refresh, enabled = !state.isLoading) {
                    Icon(Icons.Filled.Refresh, contentDescription = stringResource(R.string.common_reload))
                }
            }
            if (state.marked > 0) {
                Text(
                    stringResource(R.string.messages_marked_format, state.marked),
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
                            MsgFilter.UNGELESEN -> stringResource(R.string.messages_empty_unread)
                            MsgFilter.MIT_DATEIEN -> stringResource(R.string.messages_empty_files)
                            MsgFilter.ALLE -> stringResource(R.string.messages_empty_all)
                        },
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    TextButton(onClick = viewModel::refresh) { Text(stringResource(R.string.common_reload)) }
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
                                Text(stringResource(R.string.common_load_more_format, state.items.size, state.total))
                            }
                        }
                    }
                    item { Spacer(Modifier.height(88.dp)) }
                }
            }
        }
        // Über der Bottom-Bar (Pille + Systemleiste): 88dp frei, passend
        // zum Listen-Spacer am Ende — der Knopf liegt nie unter der Bar.
        FloatingActionButton(
            onClick = onCompose,
            shape = CircleShape,
            containerColor = MaterialTheme.colorScheme.primary,
            contentColor = MaterialTheme.colorScheme.onPrimary,
            modifier = Modifier.align(Alignment.BottomEnd)
                .navigationBarsPadding()
                .padding(end = 16.dp, bottom = 88.dp)
                .size(56.dp),
        ) {
            Icon(Icons.Filled.Add, contentDescription = stringResource(R.string.messages_new_desc))
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
                                    att.name.ifBlank { stringResource(R.string.messages_file_format, idx + 1) },
                                    fontSize = 12.sp,
                                )
                            }
                        }
                    }
                }
                if (item.reaction_count > 0) {
                    Text(
                        stringResource(R.string.messages_like_format, item.reaction_count),
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
                Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = stringResource(R.string.common_back))
            }
            ScreenHead(
                title = stringResource(R.string.messages_thread_title),
                subtitle = message?.author.orEmpty(),
                modifier = Modifier.weight(1f),
            )
            IconButton(onClick = viewModel::refresh, enabled = !state.isLoading) {
                Icon(Icons.Filled.Refresh, contentDescription = stringResource(R.string.common_reload))
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
                stringResource(R.string.messages_cached),
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
                    SectionLabel(stringResource(R.string.messages_files_format, atts.size))
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
                                    att.name.ifBlank { stringResource(R.string.messages_file_format, idx + 1) },
                                    style = MaterialTheme.typography.bodyMedium,
                                    modifier = Modifier.weight(1f),
                                )
                                Text(
                                    stringResource(R.string.messages_load),
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
                    SectionLabel(stringResource(R.string.messages_likes_format, thread?.summary?.likes ?: thread?.likes?.size ?: 0))
                }
                thread?.likes?.forEach { like ->
                    item {
                        Text(
                            stringResource(R.string.messages_like_detail_format, like.name, like.date),
                            style = MaterialTheme.typography.bodyMedium,
                            modifier = Modifier.padding(horizontal = 4.dp),
                        )
                    }
                }
            }
            item {
                SectionLabel(
                    stringResource(R.string.messages_replies_format, thread?.summary?.replies ?: thread?.replies?.size ?: 0),
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
                        stringResource(R.string.messages_no_activity),
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
            placeholder = { Text(stringResource(R.string.messages_reply_placeholder)) },
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
            text = if (state.isSending) stringResource(R.string.messages_sending) else stringResource(R.string.messages_reply_send),
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

    // Verfassen läuft ohne Bottom-Bar (NavGraph blendet sie auf dieser
    // Route aus); Systemleiste unten per navigationBarsPadding freihalten.
    Column(modifier = modifier.fillMaxSize().navigationBarsPadding().padding(16.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = onBack) {
                Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = stringResource(R.string.common_back))
            }
            ScreenHead(
                title = stringResource(R.string.messages_new_desc),
                subtitle = stringResource(R.string.messages_compose_subtitle),
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
            placeholder = stringResource(R.string.messages_recipient_search),
        )

        Spacer(Modifier.height(8.dp))

        SectionLabel(stringResource(R.string.messages_recipients_format, state.selectedIds.size))

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
            placeholder = { Text(stringResource(R.string.messages_body_placeholder)) },
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
            text = if (state.isSending) stringResource(R.string.messages_sending) else stringResource(R.string.messages_compose_send),
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
                ) { Text(stringResource(R.string.auth_login)) }
            } else {
                TextButton(
                    onClick = onDismiss,
                    colors = ButtonDefaults.textButtonColors(contentColor = Color.White),
                ) { Text(stringResource(R.string.common_ok)) }
            }
        },
        modifier = modifier.padding(bottom = 8.dp),
    ) { Text(message) }
}
