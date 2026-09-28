package de.eduflow.android.ui.overview

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import de.eduflow.android.data.ApiException
import de.eduflow.android.data.ApiService
import de.eduflow.android.data.EduFlowJson
import de.eduflow.android.data.ErrorMapper
import de.eduflow.android.data.MetaRepository
import de.eduflow.android.data.SettingsRepository
import de.eduflow.android.data.TimetableRepository
import de.eduflow.android.data.dto.EssenDays
import de.eduflow.android.data.dto.EssenResponse
import de.eduflow.android.data.dto.HomeworkCounts
import de.eduflow.android.data.dto.HomeworkDto
import de.eduflow.android.data.dto.LessonDto
import de.eduflow.android.data.dto.MessageDto
import de.eduflow.android.data.dto.MessagesListResponse
import de.eduflow.android.data.dto.SettingsValues
import de.eduflow.android.data.dto.WetterResponse
import de.eduflow.android.data.repository.HomeworkRepository
import de.eduflow.android.data.unwrap
import kotlinx.coroutines.async
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.serialization.json.decodeFromJsonElement
import java.time.LocalTime

/** UI-Zustand, spiegelt Web (templates/overview.html). */
data class OverviewUiState(
    val settings: SettingsValues = SettingsValues(),
    val messages: List<MessageDto> = emptyList(),
    val messagesTotal: Int = 0,
    val homework: List<HomeworkDto> = emptyList(),
    val homeworkCounts: HomeworkCounts = HomeworkCounts(),
    val lessonsToday: List<LessonDto> = emptyList(),
    val currentLesson: LessonDto? = null,
    val nextLesson: LessonDto? = null,
    val essen: EssenResponse? = null,
    /** Pager-Position im Essensplan (Mo–Fr, Start: heute). */
    val essenIndex: Int = 0,
    val wetter: WetterResponse? = null,
    val wetterCity: String = "",
    val wetterLoading: Boolean = false,
    val wetterError: ApiException? = null,
    val isLoading: Boolean = false,
    val error: ApiException? = null,
    val cacheInfo: String = "",
)

private fun Throwable.toApiException(): ApiException =
    (this as? ApiException) ?: ApiException("UPSTREAM", ErrorMapper.messageFor("UPSTREAM"))

/**
 * Übersicht-ViewModel (Paket D, Startseite).
 *
 * Wiederverwendet die Listen aus B/C gegen das frozen [ApiService]:
 * neueste Nachrichten (ov_unread-Limit), offene Hausaufgaben
 * (ov_homework-Limit, überfällig zuerst wie im Web), heutige Stunden
 * (aktuelle/nächste wie im Web), Essen-heute, Wetterkarte.
 */
class OverviewViewModel(
    private val api: () -> ApiService,
    private val settingsRepo: SettingsRepository,
    private val homeworkRepo: HomeworkRepository,
    private val timetableRepo: TimetableRepository,
    private val metaRepo: MetaRepository,
) : ViewModel() {
    private val _state = MutableStateFlow(OverviewUiState(isLoading = true))
    val state: StateFlow<OverviewUiState> = _state.asStateFlow()

    init {
        refresh()
    }

    fun refresh() {
        viewModelScope.launch {
            _state.update { it.copy(isLoading = true, error = null) }
            val settings = try {
                settingsRepo.load().second
            } catch (e: Exception) {
                _state.update { it.copy(isLoading = false, error = e.toApiException()) }
                return@launch
            }
            val city = settings.wetterCity.trim()
            _state.update {
                it.copy(
                    settings = settings,
                    wetterCity = settings.wetterCity,
                    wetter = null,
                    wetterLoading = settings.ovWetter && city.isNotEmpty(),
                    wetterError = null,
                )
            }

            val messagesJob = async {
                runCatching {
                    val raw = api().messages(
                        limit = settings.ovUnread.coerceIn(1, 50),
                        offset = 0,
                    ).unwrap()
                    EduFlowJson.decodeFromJsonElement(MessagesListResponse.serializer(), raw)
                }
            }
            val homeworkJob = async {
                homeworkRepo.list(
                    status = "alle",
                    includeTests = settings.hwTests,
                    limit = 50,
                    offset = 0,
                )
            }
            val timetableJob = async { timetableRepo.day() }
            val essenJob = async { metaRepo.essen() }
            // Wetter nur bei Anzeige-Wunsch und gespeicherter Stadt laden.
            // Der Ort wird ausschließlich in den Account-Einstellungen gepflegt.
            val wetterJob = async {
                if (!settings.ovWetter) return@async null
                if (city.isEmpty()) return@async null
                metaRepo.wetter(city = city)
            }

            var firstError: ApiException? = null
            messagesJob.await().onSuccess { page ->
                _state.update { it.copy(messages = page.items, messagesTotal = page.total) }
            }.onFailure { e -> firstError = firstError ?: e.toApiException() }
            homeworkJob.await().onSuccess { page ->
                val open = page.items.filter { !it.is_done && !it.is_hidden }
                    .take(settings.ovHomework.coerceIn(1, 50))
                _state.update {
                    it.copy(homework = open, homeworkCounts = page.counts, cacheInfo = page.cache_info)
                }
            }.onFailure { e -> firstError = firstError ?: e.toApiException() }
            timetableJob.await().onSuccess { day ->
                val lessons = day.lessons.filter { !it.is_event }
                val (current, next) = currentAndNext(lessons)
                _state.update {
                    it.copy(lessonsToday = lessons, currentLesson = current, nextLesson = next)
                }
            }.onFailure { e -> firstError = firstError ?: e.toApiException() }
            essenJob.await().onSuccess { menu ->
                val start = menu.today?.let { EssenDays.ORDER.indexOf(it) }?.takeIf { it >= 0 } ?: 0
                _state.update { it.copy(essen = menu, essenIndex = start) }
            }.onFailure { e -> firstError = firstError ?: e.toApiException() }
            wetterJob.await()?.onSuccess { wetter ->
                _state.update { it.copy(wetter = wetter, wetterLoading = false, wetterError = null) }
            }?.onFailure { e ->
                val weatherError = e.toApiException()
                _state.update { it.copy(wetterLoading = false, wetterError = weatherError) }
                firstError = firstError ?: weatherError
            }

            _state.update { it.copy(isLoading = false, error = firstError) }
        }
    }

    /** Essens-Pager (‹ › unten, wie im Web, Mo–Fr). */
    fun stepEssen(delta: Int) {
        _state.update {
            it.copy(essenIndex = (it.essenIndex + delta).coerceIn(0, EssenDays.ORDER.size - 1))
        }
    }

    /** Wetter laden (Ort per Stadt; Schlüssel bleibt serverseitig). */
    fun loadWetter() {
        val city = _state.value.wetterCity.trim()
        if (city.isEmpty()) {
            _state.update {
                it.copy(wetterError = ApiException("VALIDATION", "Bitte eine Stadt eingeben."))
            }
            return
        }
        viewModelScope.launch {
            _state.update { it.copy(wetterLoading = true, wetterError = null) }
            metaRepo.wetter(city = city).onSuccess { wetter ->
                _state.update { it.copy(wetter = wetter, wetterLoading = false) }
            }.onFailure { e ->
                _state.update { it.copy(wetterLoading = false, wetterError = e.toApiException()) }
            }
        }
    }

    fun dismissError() {
        _state.update { it.copy(error = null) }
    }

    companion object {
        /**
         * Aktuelle/nächste Stunde wie im Web (uebersicht): laufende nicht
         * entfallene Stunde, sonst nächste kommende (keine Events).
         * `now` ist injizierbar, damit Tests mit fester Uhrzeit laufen
         * (relativ zu now() wäre der Mitternachtsumbruch flaky).
         */
        fun currentAndNext(
            lessons: List<LessonDto>,
            now: LocalTime = LocalTime.now(),
        ): Pair<LessonDto?, LessonDto?> {
            var current: LessonDto? = null
            var next: LessonDto? = null
            for (lesson in lessons) {
                val (start, end) = lessonRange(lesson) ?: continue
                if (lesson.is_cancelled) continue
                if (current == null && !start.isAfter(now) && !end.isBefore(now)) {
                    current = lesson
                }
                if (next == null && start.isAfter(now)) {
                    next = lesson
                    if (current != null) break
                }
            }
            return current to next
        }

        private fun lessonRange(lesson: LessonDto): Pair<LocalTime, LocalTime>? {
            return try {
                val parts = lesson.time.split("–", "-").map { it.trim() }
                if (parts.size != 2) return null
                LocalTime.parse(parts[0]) to LocalTime.parse(parts[1])
            } catch (_: Exception) {
                null
            }
        }
    }
}
