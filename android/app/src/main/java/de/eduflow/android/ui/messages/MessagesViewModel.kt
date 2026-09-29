package de.eduflow.android.ui.messages

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import de.eduflow.android.R
import de.eduflow.android.data.ApiException
import de.eduflow.android.data.ErrorMapper
import de.eduflow.android.data.MessagesRepository
import de.eduflow.android.data.TokenStore
import de.eduflow.android.data.dto.MessageDto
import de.eduflow.android.data.dto.MessageTypes
import de.eduflow.android.data.dto.MsgFilter
import de.eduflow.android.data.dto.RecipientDto
import de.eduflow.android.data.dto.RecipientIds
import de.eduflow.android.data.dto.ThreadResponse
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

private fun Throwable.toApiException(): ApiException =
    (this as? ApiException) ?: ApiException("UPSTREAM", ErrorMapper.messageFor("UPSTREAM"))

/** UI-Zustand der Nachrichtenliste (Redesign-PNG, Screen 02). */
data class MessagesUiState(
    val items: List<MessageDto> = emptyList(),
    val total: Int = 0,
    val filter: MsgFilter = MsgFilter.ALLE,
    val query: String = "",
    val seenIds: Set<Int> = emptySet(),
    val marked: Int = 0,
    val isLoading: Boolean = false,
    val isLoadingMore: Boolean = false,
    val error: ApiException? = null,
    val canLoadMore: Boolean = false,
) {
    /** Clientseitige Filterung (Alle/Ungelesen/Mit Dateien, wie im PNG). */
    val visible: List<MessageDto>
        get() = when (filter) {
            MsgFilter.UNGELESEN -> items.filter { it.id !in seenIds }
            MsgFilter.MIT_DATEIEN -> items.filter { it.attachments.isNotEmpty() }
            MsgFilter.ALLE -> items
        }
}

private const val PAGE_SIZE = 50

/**
 * Nachrichten-ViewModel (Paket C).
 *
 * - Liste mit Suche (debounced), Refresh, clientseitigen PNG-Chips.
 * - „Ungelesen" ist lokal (gesehene IDs im TokenStore), weil der Server
 *   kein Ungelesen-Flag kennt; Thread-Öffnen markiert als gesehen.
 * - Paginierung: initial limit=50, Mehr laden via offset.
 * - Alle-als-gelesen: Server-Zähler + lokale IDs (wie im Web).
 */
class MessagesViewModel(
    private val repository: MessagesRepository,
    private val store: TokenStore,
) : ViewModel() {
    private val _state = MutableStateFlow(MessagesUiState(isLoading = true))
    val state: StateFlow<MessagesUiState> = _state.asStateFlow()

    private var searchJob: Job? = null

    init {
        refresh()
        viewModelScope.launch {
            store.seenMessagesFlow.collect { ids ->
                _state.update { it.copy(seenIds = ids) }
            }
        }
    }

    fun refresh() {
        viewModelScope.launch {
            _state.update { it.copy(isLoading = true, error = null) }
            val s = _state.value
            repository.list(
                type = MessageTypes.ALLE,
                q = s.query,
                limit = PAGE_SIZE,
                offset = 0,
                refresh = true,
            ).onSuccess { page ->
                _state.update {
                    it.copy(
                        items = page.items,
                        total = page.total,
                        isLoading = false,
                        canLoadMore = page.items.size < page.total,
                    )
                }
            }.onFailure { e ->
                _state.update { it.copy(isLoading = false, error = e.toApiException()) }
            }
        }
    }

    fun loadFromCache() {
        viewModelScope.launch {
            val s = _state.value
            repository.list(
                type = MessageTypes.ALLE,
                q = s.query,
                limit = PAGE_SIZE,
                offset = 0,
                refresh = false,
            ).onSuccess { page ->
                _state.update {
                    it.copy(
                        items = page.items,
                        total = page.total,
                        isLoading = false,
                        error = null,
                        canLoadMore = page.items.size < page.total,
                    )
                }
            }.onFailure { e ->
                _state.update { it.copy(isLoading = false, error = e.toApiException()) }
            }
        }
    }

    fun loadMore() {
        val s = _state.value
        if (s.isLoading || s.isLoadingMore || !s.canLoadMore) return
        viewModelScope.launch {
            _state.update { it.copy(isLoadingMore = true) }
            repository.list(
                type = MessageTypes.ALLE,
                q = s.query,
                limit = PAGE_SIZE,
                offset = s.items.size,
                refresh = false,
            ).onSuccess { page ->
                _state.update {
                    it.copy(
                        items = it.items + page.items,
                        total = page.total,
                        isLoadingMore = false,
                        canLoadMore = it.items.size + page.items.size < page.total,
                    )
                }
            }.onFailure { e ->
                _state.update { it.copy(isLoadingMore = false, error = e.toApiException()) }
            }
        }
    }

    fun onFilter(filter: MsgFilter) {
        if (filter == _state.value.filter) return
        _state.update { it.copy(filter = filter, error = null) }
    }

    fun onQuery(query: String) {
        _state.update { it.copy(query = query) }
        searchJob?.cancel()
        searchJob = viewModelScope.launch {
            delay(350)
            loadFromCache()
        }
    }

    fun markRead() {
        viewModelScope.launch {
            repository.markRead().onSuccess { res ->
                store.markMessagesSeen(_state.value.items.map { it.id })
                _state.update { it.copy(marked = res.marked, error = null) }
            }.onFailure { e ->
                _state.update { it.copy(error = e.toApiException()) }
            }
        }
    }

    /** Thread-Öffnen markiert die Nachricht lokal als gesehen. */
    fun openThread(id: Int) {
        viewModelScope.launch {
            store.markMessagesSeen(listOf(id))
        }
    }

    /** Download-Fehler (z. B. ?dl=-Ausstellung) in der Liste anzeigen. */
    fun showDownloadError(e: Throwable) {
        _state.update { it.copy(error = e.toApiException()) }
    }

    fun dismissError() {
        _state.update { it.copy(error = null) }
    }
}

/** UI-Zustand des Threads (Likes, Antworten, Antwort schreiben). */
data class ThreadUiState(
    val message: MessageDto? = null,
    val thread: ThreadResponse? = null,
    val replyBody: String = "",
    val isLoading: Boolean = false,
    val isSending: Boolean = false,
    val error: ApiException? = null,
)

/**
 * Thread-ViewModel (Paket B).
 * Lädt den Thread zur Nachricht und schickt Antworten an alle im Thread
 * (wie Web: recipient="" serverseitig).
 */
class ThreadViewModel(
    private val repository: MessagesRepository,
    private val messageId: Int,
) : ViewModel() {
    private val _state = MutableStateFlow(ThreadUiState(isLoading = true))
    val state: StateFlow<ThreadUiState> = _state.asStateFlow()

    init {
        refresh()
    }

    fun refresh() {
        viewModelScope.launch {
            _state.update { it.copy(isLoading = true, error = null) }
            repository.thread(messageId, refresh = true).onSuccess { thread ->
                _state.update { it.copy(thread = thread, isLoading = false) }
            }.onFailure { e ->
                _state.update { it.copy(isLoading = false, error = e.toApiException()) }
            }
        }
    }

    fun onReplyBody(body: String) {
        _state.update { it.copy(replyBody = body) }
    }

    /** Download-Fehler (z. B. ?dl=-Ausstellung) im Thread anzeigen. */
    fun showDownloadError(e: Throwable) {
        _state.update { it.copy(error = e.toApiException()) }
    }

    fun sendReply() {
        val body = _state.value.replyBody.trim()
        if (body.isBlank() || _state.value.isSending) return
        viewModelScope.launch {
            _state.update { it.copy(isSending = true, error = null) }
            repository.reply(messageId, body).onSuccess { thread ->
                _state.update { it.copy(thread = thread, replyBody = "", isSending = false) }
            }.onFailure { e ->
                _state.update { it.copy(isSending = false, error = e.toApiException()) }
            }
        }
    }

    fun dismissError() {
        _state.update { it.copy(error = null) }
    }
}

/** UI-Zustand des Verfassen-Dialogs (Empfänger + Text). */
data class ComposeUiState(
    val recipients: List<RecipientDto> = emptyList(),
    val selectedIds: Set<String> = emptySet(),
    val body: String = "",
    val isLoadingRecipients: Boolean = false,
    val isSending: Boolean = false,
    val sentId: Int? = null,
    val error: ApiException? = null,
)

/**
 * Verfassen-ViewModel (Paket B).
 * Empfängerliste laden, Auswahl + Text prüfen (wie serverseitig:
 * mind. 1 gültige ID, nicht-leerer Text), dann senden.
 */
class ComposeViewModel(
    private val repository: MessagesRepository,
) : ViewModel() {
    private val _state = MutableStateFlow(ComposeUiState(isLoadingRecipients = true))
    val state: StateFlow<ComposeUiState> = _state.asStateFlow()

    init {
        loadRecipients()
    }

    fun loadRecipients() {
        viewModelScope.launch {
            _state.update { it.copy(isLoadingRecipients = true, error = null) }
            repository.recipients(limit = 200, offset = 0).onSuccess { page ->
                _state.update { it.copy(recipients = page.items, isLoadingRecipients = false) }
            }.onFailure { e ->
                _state.update { it.copy(isLoadingRecipients = false, error = e.toApiException()) }
            }
        }
    }

    fun toggleRecipient(id: String) {
        _state.update {
            val next = it.selectedIds.toMutableSet()
            if (!next.add(id)) next.remove(id)
            it.copy(selectedIds = next)
        }
    }

    fun onBody(body: String) {
        _state.update { it.copy(body = body) }
    }

    fun send() {
        val s = _state.value
        // IDs stammen aus der Server-Empfängerliste und werden dort erneut
        // geprüft — hier nur leere/Doppelte entfernen, kein Format-Raten
        // (dbi-Schlüssel sind nicht überall rein numerisch).
        val ids = s.selectedIds.map { it.trim() }.filter { it.isNotEmpty() }.distinct()
        val body = s.body.trim()
        if (ids.isEmpty()) {
            _state.update {
                it.copy(
                    error = ApiException(
                        "VALIDATION", "Bitte mindestens einen gültigen Empfänger wählen.",
                        messageRes = R.string.messages_compose_no_recipient,
                    ),
                )
            }
            return
        }
        if (body.isBlank()) {
            _state.update {
                it.copy(
                    error = ApiException(
                        "VALIDATION", "Bitte einen Nachrichtentext eingeben.",
                        messageRes = R.string.messages_compose_no_body,
                    ),
                )
            }
            return
        }
        if (s.isSending) return
        viewModelScope.launch {
            _state.update { it.copy(isSending = true, error = null) }
            repository.send(ids, body).onSuccess { msg ->
                _state.update { it.copy(sentId = msg.id, isSending = false) }
            }.onFailure { e ->
                _state.update { it.copy(isSending = false, error = e.toApiException()) }
            }
        }
    }

    fun dismissError() {
        _state.update { it.copy(error = null) }
    }
}
