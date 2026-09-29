package de.eduflow.android.ui.grades

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import de.eduflow.android.data.ApiException
import de.eduflow.android.data.ErrorMapper
import de.eduflow.android.data.dto.GradeSubjectGroup
import de.eduflow.android.data.dto.GradeTerm
import de.eduflow.android.data.dto.buildGradeTerms
import de.eduflow.android.data.dto.currentTermKey
import de.eduflow.android.data.dto.deNum
import de.eduflow.android.data.dto.gradesAverage
import de.eduflow.android.data.dto.groupGradesBySubject
import de.eduflow.android.data.dto.gradeTermKey
import de.eduflow.android.data.repository.GradesRepository
import java.time.LocalDate
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/** UI-Zustand, spiegelt Web (templates/grades.html + Route noten()). */
data class GradesUiState(
    val allItems: List<de.eduflow.android.data.dto.GradeDto> = emptyList(),
    val total: Int = 0,
    val cacheInfo: String = "",
    val terms: List<GradeTerm> = listOf(GradeTerm()),
    val term: String = "alle",
    val query: String = "",
    /** Entprellte Suche (350 ms, wie Nachrichten/Aufgaben): erst dieser Wert
     * filtert [shown], damit jeder Tastenschlag keine Listen-Neuaufbauten
     * auslöst. */
    val debouncedQuery: String = "",
    val isLoading: Boolean = false,
    val isLoadingMore: Boolean = false,
    val error: ApiException? = null,
    val canLoadMore: Boolean = false,
    val fallbackTerm: String = "alle",
) {
    /** Geladene Einträge nach Halbjahr + entprellter Suche (Fach/Thema/Lehrer, wie Web). */
    val shown: List<de.eduflow.android.data.dto.GradeDto>
        get() {
            val needle = debouncedQuery.trim().lowercase()
            return allItems.filter { g ->
                (term == "alle" || gradeTermKey(g.date_iso, fallbackTerm) == term) &&
                    (needle.isBlank() ||
                        "${g.subject} ${g.title} ${g.teacher}".lowercase().contains(needle))
            }
        }

    val groups: List<GradeSubjectGroup>
        get() = groupGradesBySubject(shown)

    val avgDisplay: String
        get() = deNum(gradesAverage(shown))
}

private const val PAGE_SIZE = 50

private fun Throwable.toApiException(): ApiException =
    (this as? ApiException) ?: ApiException("UPSTREAM", ErrorMapper.messageFor("UPSTREAM"))

private fun currentTerm(): String {
    return try {
        val today = LocalDate.now()
        currentTermKey(today.year, today.monthValue)
    } catch (_: Exception) {
        "alle"
    }
}

/**
 * Noten-ViewModel (Paket C).
 *
 * - Liste in Cache-Reihenfolge vom Server (keine eigenen Filter/Sortierung
 *   an die API — Gruppierung clientseitig wie Web-noten()).
 * - Paginierung: initial limit=50, Mehr laden via offset.
 * - Halbjahr-Tabs + Suche (350 ms entprellt) filtern die geladenen
 *   Einträge lokal.
 */
class GradesViewModel(
    private val repository: GradesRepository,
) : ViewModel() {
    private val _state = MutableStateFlow(GradesUiState(isLoading = true, fallbackTerm = currentTerm()))
    val state: StateFlow<GradesUiState> = _state.asStateFlow()

    private var searchJob: Job? = null

    init {
        loadFromCache()
    }

    fun refresh() {
        viewModelScope.launch {
            _state.update { it.copy(isLoading = true, error = null) }
            repository.list(limit = PAGE_SIZE, offset = 0, refresh = true)
                .onSuccess { page -> applyPage(page, reset = true) }
                .onFailure { e ->
                    _state.update { it.copy(isLoading = false, error = e.toApiException()) }
                }
        }
    }

    fun loadFromCache() {
        viewModelScope.launch {
            val hadItems = _state.value.allItems.isNotEmpty()
            if (!hadItems) _state.update { it.copy(isLoading = true, error = null) }
            repository.list(limit = PAGE_SIZE, offset = 0, refresh = false)
                .onSuccess { page -> applyPage(page, reset = true) }
                .onFailure { e ->
                    _state.update { it.copy(isLoading = false, error = e.toApiException()) }
                }
        }
    }

    fun loadMore() {
        val s = _state.value
        if (s.isLoading || s.isLoadingMore || !s.canLoadMore) return
        viewModelScope.launch {
            _state.update { it.copy(isLoadingMore = true) }
            repository.list(limit = PAGE_SIZE, offset = s.allItems.size, refresh = false)
                .onSuccess { page ->
                    _state.update {
                        val merged = it.allItems + page.items
                        it.copy(
                            allItems = merged,
                            total = page.total,
                            cacheInfo = page.cache_info,
                            terms = buildGradeTerms(merged, it.fallbackTerm),
                            isLoadingMore = false,
                            canLoadMore = merged.size < page.total,
                        )
                    }
                }
                .onFailure { e ->
                    _state.update { it.copy(isLoadingMore = false, error = e.toApiException()) }
                }
        }
    }

    fun onTerm(term: String) {
        _state.update { it.copy(term = term) }
    }

    fun onQuery(query: String) {
        _state.update { it.copy(query = query) }
        searchJob?.cancel()
        searchJob = viewModelScope.launch {
            delay(350)
            _state.update { it.copy(debouncedQuery = it.query) }
        }
    }

    fun dismissError() {
        _state.update { it.copy(error = null) }
    }

    private fun applyPage(page: de.eduflow.android.data.dto.GradesListResponse, reset: Boolean) {
        _state.update { s ->
            val merged = if (reset) page.items else s.allItems + page.items
            val terms = buildGradeTerms(merged, s.fallbackTerm)
            val keys = terms.map { it.key }.toSet()
            // Wie Web: ungültiges/aktuelles Halbjahr ohne Noten -> neuestes mit Noten.
            val term = when {
                s.term in keys -> s.term
                s.fallbackTerm in keys -> s.fallbackTerm
                else -> terms.firstOrNull { it.key != "alle" }?.key ?: "alle"
            }
            s.copy(
                allItems = merged,
                total = page.total,
                cacheInfo = page.cache_info,
                terms = terms,
                term = term,
                isLoading = false,
                canLoadMore = merged.size < page.total,
                error = null,
            )
        }
    }
}
