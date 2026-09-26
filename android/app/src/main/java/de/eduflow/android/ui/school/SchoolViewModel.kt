package de.eduflow.android.ui.school

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import de.eduflow.android.data.ApiException
import de.eduflow.android.data.ErrorMapper
import de.eduflow.android.data.SchoolRepository
import de.eduflow.android.data.dto.SchoolAgendaItemDto
import de.eduflow.android.data.dto.SubstitutionDayDto
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.time.LocalDate

data class SchoolUiState(
    val agenda: List<SchoolAgendaItemDto> = emptyList(),
    val substitutions: List<SubstitutionDayDto> = emptyList(),
    val isLoading: Boolean = false,
    val error: ApiException? = null,
    val selectedDay: LocalDate = LocalDate.now().with(java.time.DayOfWeek.MONDAY),
)

private fun Throwable.toSchoolError(): ApiException =
    (this as? ApiException)
        ?: ApiException("UPSTREAM", ErrorMapper.messageFor("UPSTREAM"))

class SchoolViewModel(private val repository: SchoolRepository) : ViewModel() {
    private val _state = MutableStateFlow(SchoolUiState(isLoading = true))
    val state: StateFlow<SchoolUiState> = _state.asStateFlow()

    init { load() }

    fun load(refresh: Boolean = false, day: LocalDate = _state.value.selectedDay.with(java.time.DayOfWeek.MONDAY)) {
        viewModelScope.launch {
            _state.update { it.copy(isLoading = true, error = null, selectedDay = day) }
            val agendaResult = repository.agenda(
                since = day.minusDays(30).toString(),
                until = day.plusDays(60).toString(),
                refresh = refresh,
            )
            val substitutionResult = repository.substitutions(day.toString())
            val error = agendaResult.exceptionOrNull() ?: substitutionResult.exceptionOrNull()
            _state.value = SchoolUiState(
                agenda = agendaResult.getOrNull()?.items.orEmpty(),
                substitutions = substitutionResult.getOrNull()?.days.orEmpty(),
                isLoading = false,
                error = error?.toSchoolError(),
                selectedDay = day,
            )
        }
    }

    fun dismissError() { _state.update { it.copy(error = null) } }
}
