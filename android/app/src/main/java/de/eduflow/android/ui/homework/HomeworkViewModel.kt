package de.eduflow.android.ui.homework

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import de.eduflow.android.data.ApiException
import de.eduflow.android.data.ErrorMapper
import de.eduflow.android.data.dto.HomeworkCounts
import de.eduflow.android.data.dto.HomeworkDto
import de.eduflow.android.data.dto.HomeworkStatus
import de.eduflow.android.data.repository.HomeworkRepository
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/** UI-Zustand, spiegelt Web (templates/homework.html) + API-Zähler. */
data class HomeworkUiState(
    val items: List<HomeworkDto> = emptyList(),
    val total: Int = 0,
    val counts: HomeworkCounts = HomeworkCounts(),
    val cacheInfo: String = "",
    val status: String = HomeworkStatus.ALLE,
    val query: String = "",
    val includeTests: Boolean = false,
    val isLoading: Boolean = false,
    val isLoadingMore: Boolean = false,
    val error: ApiException? = null,
    val pendingIds: Set<Long> = emptySet(),
    val canLoadMore: Boolean = false,
)

private const val PAGE_SIZE = 50

private fun Throwable.toApiException(): ApiException =
    (this as? ApiException) ?: ApiException("UPSTREAM", ErrorMapper.messageFor("UPSTREAM"))

/**
 * Hausaufgaben-ViewModel (Paket C).
 *
 * - Liste mit Statusfilter, Suche (debounced), Tests-Schalter, Refresh.
 * - Paginierung: initial limit=50, Mehr laden via offset.
 * - done/trash mit Pending-Schutz pro Karte; nach Erfolg Liste
 *   lokal nachpflegen (Server ist Source of Truth beim nächsten Refresh,
 *   wie im Web nach POST + Reload).
 */
class HomeworkViewModel(
    private val repository: HomeworkRepository,
) : ViewModel() {
    private val _state = MutableStateFlow(HomeworkUiState(isLoading = true))
    val state: StateFlow<HomeworkUiState> = _state.asStateFlow()

    private var searchJob: Job? = null

    init {
        refresh()
    }

    fun refresh() {
        viewModelScope.launch {
            _state.update { it.copy(isLoading = true, error = null) }
            val s = _state.value
            repository.list(
                status = s.status,
                includeTests = s.includeTests,
                q = s.query,
                limit = PAGE_SIZE,
                offset = 0,
                refresh = true,
            ).onSuccess { page ->
                _state.update {
                    it.copy(
                        items = page.items,
                        total = page.total,
                        counts = page.counts,
                        cacheInfo = page.cache_info,
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
                status = s.status,
                includeTests = s.includeTests,
                q = s.query,
                limit = PAGE_SIZE,
                offset = 0,
                refresh = false,
            ).onSuccess { page ->
                _state.update {
                    it.copy(
                        items = page.items,
                        total = page.total,
                        counts = page.counts,
                        cacheInfo = page.cache_info,
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
                status = s.status,
                includeTests = s.includeTests,
                q = s.query,
                limit = PAGE_SIZE,
                offset = s.items.size,
                refresh = false,
            ).onSuccess { page ->
                _state.update {
                    it.copy(
                        items = it.items + page.items,
                        total = page.total,
                        counts = page.counts,
                        isLoadingMore = false,
                        canLoadMore = it.items.size + page.items.size < page.total,
                    )
                }
            }.onFailure { e ->
                _state.update { it.copy(isLoadingMore = false, error = e.toApiException()) }
            }
        }
    }

    fun onStatus(status: String) {
        if (status !in HomeworkStatus.ALL || status == _state.value.status) return
        _state.update { it.copy(status = status, isLoading = true, error = null) }
        loadFromCache()
    }

    fun onQuery(query: String) {
        _state.update { it.copy(query = query) }
        searchJob?.cancel()
        searchJob = viewModelScope.launch {
            delay(350)
            loadFromCache()
        }
    }

    fun onIncludeTests(include: Boolean) {
        if (include == _state.value.includeTests) return
        _state.update { it.copy(includeTests = include, isLoading = true) }
        loadFromCache()
    }

    fun dismissError() {
        _state.update { it.copy(error = null) }
    }

    /** Erledigt-Schalter (links wischen im Web = dieser Aufruf). */
    fun toggleDone(item: HomeworkDto) {
        val id = item.id
        if (id in _state.value.pendingIds) return
        viewModelScope.launch {
            _state.update { it.copy(pendingIds = it.pendingIds + id, error = null) }
            repository.setDone(id, !item.is_done).onSuccess { updated ->
                _state.update { s ->
                    s.copy(
                        items = s.items.map { if (it.id == id) updated else it },
                        pendingIds = s.pendingIds - id,
                    )
                }
                // Zähler nach Statuswechsel neu laden (still, ohne Spinner).
                silentRecount()
            }.onFailure { e ->
                _state.update { it.copy(pendingIds = it.pendingIds - id, error = e.toApiException()) }
            }
        }
    }

    /**
     * Papierkorb: hineinlegen bzw. zurückholen.
     * Zurückholen markiert serverseitig gleichzeitig als offen (wie Web).
     */
    fun toggleTrash(item: HomeworkDto) {
        val id = item.id
        if (id in _state.value.pendingIds) return
        viewModelScope.launch {
            _state.update { it.copy(pendingIds = it.pendingIds + id, error = null) }
            repository.setTrash(id, !item.is_hidden).onSuccess { updated ->
                val s = _state.value
                // Im Papierkorb-Filter verschwindet/erscheint die Karte sofort,
                // sonst nur Flag nachpflegen (Web sortiert Papierkorb ans Ende).
                // total bleibt die Server-Zahl (silentRecount korrigiert nach);
                // nur beim Entfernen aus der Papierkorb-Ansicht -1.
                val removed = s.status == HomeworkStatus.PAPIERKORB && !updated.is_hidden
                val next = if (removed) {
                    s.items.filterNot { it.id == id }
                } else {
                    s.items.map { if (it.id == id) updated else it }
                }
                _state.update {
                    it.copy(
                        items = next,
                        total = if (removed) (it.total - 1).coerceAtLeast(0) else it.total,
                        pendingIds = it.pendingIds - id,
                    )
                }
                silentRecount()
            }.onFailure { e ->
                _state.update { it.copy(pendingIds = it.pendingIds - id, error = e.toApiException()) }
            }
        }
    }

    private suspend fun silentRecount() {
        val s = _state.value
        repository.list(
            status = s.status,
            includeTests = s.includeTests,
            q = s.query,
            limit = PAGE_SIZE,
            offset = 0,
            refresh = false,
        ).onSuccess { page ->
            _state.update { it.copy(counts = page.counts, total = page.total) }
        }
    }
}
