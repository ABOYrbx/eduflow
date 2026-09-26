package de.eduflow.android.ui.timetable

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import de.eduflow.android.data.ApiException
import de.eduflow.android.data.ErrorMapper
import de.eduflow.android.data.TimetableRepository
import de.eduflow.android.data.dto.TimetableDayResponse
import de.eduflow.android.data.dto.TimetableView
import de.eduflow.android.data.dto.TimetableWeekResponse
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.time.LocalDate

/** UI-Zustand, spiegelt Web (templates/timetable.html, ?view=day|week). */
data class TimetableUiState(
    val view: String = TimetableView.DAY,
    /** Angezeigter Tag (YYYY-MM-DD); in der Woche ein Tag daraus. */
    val day: String = LocalDate.now().toString(),
    val dayData: TimetableDayResponse? = null,
    val weekData: TimetableWeekResponse? = null,
    val isLoading: Boolean = false,
    val error: ApiException? = null,
)

private fun Throwable.toApiException(): ApiException =
    (this as? ApiException) ?: ApiException("UPSTREAM", ErrorMapper.messageFor("UPSTREAM"))

/**
 * Stundenplan-ViewModel (Paket D).
 *
 * - Tag/Woche-Umschalter wie im Web (?view=), Tages-Navigation
 *   (Zurück / Heute / Weiter; in der Woche ±7 Tage).
 * - Lernzeit-Blöcke, Entfall-/Online-Kennzeichen kommen bereits
 *   zusammengefasst vom Server (merge_lernzeit, wie im Web).
 * - Cache zuerst, Aktualisieren lädt frisch (refresh=1).
 */
class TimetableViewModel(
    private val repository: TimetableRepository,
) : ViewModel() {
    private val _state = MutableStateFlow(TimetableUiState(isLoading = true))
    val state: StateFlow<TimetableUiState> = _state.asStateFlow()

    init {
        load(refresh = false)
    }

    fun load(refresh: Boolean) {
        viewModelScope.launch {
            _state.update { it.copy(isLoading = true, error = null) }
            val s = _state.value
            if (s.view == TimetableView.WEEK) {
                repository.week(day = s.day, refresh = refresh).onSuccess { week ->
                    _state.update { it.copy(weekData = week, isLoading = false) }
                }.onFailure { e ->
                    _state.update { it.copy(isLoading = false, error = e.toApiException()) }
                }
            } else {
                repository.day(day = s.day, refresh = refresh).onSuccess { day ->
                    _state.update { it.copy(dayData = day, isLoading = false) }
                }.onFailure { e ->
                    _state.update { it.copy(isLoading = false, error = e.toApiException()) }
                }
            }
        }
    }

    fun refresh() = load(refresh = true)

    fun setView(view: String) {
        if (view != TimetableView.DAY && view != TimetableView.WEEK) return
        if (view == _state.value.view) return
        _state.update { it.copy(view = view, isLoading = true, error = null) }
        load(refresh = false)
    }

    fun setDay(day: String) {
        _state.update { it.copy(day = day, isLoading = true, error = null) }
        load(refresh = false)
    }

    fun goToday() = setDay(LocalDate.now().toString())

    /** Einen Tag (Tagansicht) bzw. eine Woche (Wochenansicht) blättern. */
    fun step(days: Int) {
        val step = if (_state.value.view == TimetableView.WEEK) days * 7 else days
        val next = try {
            LocalDate.parse(_state.value.day).plusDays(step.toLong()).toString()
        } catch (_: Exception) {
            LocalDate.now().toString()
        }
        setDay(next)
    }

    fun dismissError() {
        _state.update { it.copy(error = null) }
    }
}
