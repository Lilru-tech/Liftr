package com.lilru.liftr.ui.profile

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.lilru.liftr.data.BackendContracts
import com.lilru.liftr.data.SupabaseResponseDecoding
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.query.Columns
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.time.DayOfWeek
import java.time.Instant
import java.time.LocalDate
import java.time.YearMonth
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

@Serializable
private data class StartedStateRow(
    @SerialName("started_at") val startedAt: String? = null,
    val state: String? = null
)

@Serializable
private data class PIdRow(@SerialName("workout_id") val workoutId: Int)

data class ProfileDayWorkoutUi(
    val id: Int,
    val userId: String,
    val kind: String,
    val title: String? = null,
    val state: String? = null,
    val startedAt: String? = null,
    val isParticipated: Boolean = false,
    val score: Double? = null
)

data class ProfileMonthCalendarUiState(
    val loadingMonth: Boolean = true,
    val yearMonth: YearMonth = YearMonth.now(ZoneId.systemDefault()),
    val ownCountByDay: Map<LocalDate, Int> = emptyMap(),
    val participantCountByDay: Map<LocalDate, Int> = emptyMap(),
    val plannedByDay: Map<LocalDate, Boolean> = emptyMap(),
    val error: String? = null,
    val selectedDay: LocalDate? = null,
    val dayLoading: Boolean = false,
    val dayOwn: List<ProfileDayWorkoutUi> = emptyList(),
    val dayParticipated: List<ProfileDayWorkoutUi> = emptyList()
) {
    fun totalOn(day: LocalDate): Int {
        val o = ownCountByDay[day] ?: 0
        val p = participantCountByDay[day] ?: 0
        return o + p
    }

    fun ownOn(day: LocalDate): Int = ownCountByDay[day] ?: 0
    fun plannedOn(day: LocalDate): Boolean = plannedByDay[day] == true
}

/**
 * Calendario mensual + lista por día, alineado con [Liftr/ProfileView.swift] `calendarView` / `loadMonthActivity` / `DayWorkoutsList.load`.
 */
class ProfileMonthCalendarViewModel(
    private val supabase: SupabaseClient,
    private val profileUserId: String
) : ViewModel() {
    private val zone: ZoneId = ZoneId.systemDefault()
    private val _ui = MutableStateFlow(ProfileMonthCalendarUiState())
    val uiState: StateFlow<ProfileMonthCalendarUiState> = _ui.asStateFlow()

    init {
        loadMonth()
    }

    fun shiftMonth(delta: Int) {
        val cur = _ui.value.yearMonth
        _ui.value = _ui.value.copy(yearMonth = cur.plusMonths(delta.toLong()), selectedDay = null)
        loadMonth()
    }

    fun selectDay(day: LocalDate) {
        _ui.value = _ui.value.copy(selectedDay = day)
        loadDayWorkouts(day)
    }

    private fun loadMonth() {
        viewModelScope.launch {
            val ym = _ui.value.yearMonth
            _ui.value = _ui.value.copy(loadingMonth = true, error = null)
            val monthStart = ym.atDay(1).atStartOfDay(zone).toInstant()
            val monthEnd = ym.plusMonths(1).atDay(1).atStartOfDay(zone).toInstant()
            val iso: (Instant) -> String = { it.toString() }
            runCatching {
                val rOwn = supabase.from(BackendContracts.Tables.WORKOUTS)
                    .select(columns = Columns.raw("started_at, state")) {
                        filter {
                            eq("user_id", profileUserId)
                            gte("started_at", iso(monthStart))
                            lt("started_at", iso(monthEnd))
                        }
                    }
                val rowsOwn = decodeList<StartedStateRow>(rOwn.data)
                val own = HashMap<LocalDate, Int>()
                val part = HashMap<LocalDate, Int>()
                val planned = HashMap<LocalDate, Boolean>()
                for (r in rowsOwn) {
                    val d = parseStartLocalDate(r.startedAt) ?: continue
                    if (YearMonth.from(d) != ym) continue
                    own[d] = (own[d] ?: 0) + 1
                    if ((r.state ?: "published") == "planned") {
                        planned[d] = true
                    }
                }
                val rP = supabase.from(BackendContracts.Tables.WORKOUT_PARTICIPANTS)
                    .select(columns = Columns.raw("workout_id")) {
                        filter { eq("user_id", profileUserId) }
                    }
                val pIds = decodeList<PIdRow>(rP.data).map { it.workoutId }.distinct()
                if (pIds.isNotEmpty()) {
                    val rPartW = supabase.from(BackendContracts.Tables.WORKOUTS)
                        .select(columns = Columns.raw("started_at, state")) {
                            filter {
                                isIn("id", pIds.map { it.toString() })
                                gte("started_at", iso(monthStart))
                                lt("started_at", iso(monthEnd))
                            }
                        }
                    for (r in decodeList<StartedStateRow>(rPartW.data)) {
                        val d = parseStartLocalDate(r.startedAt) ?: continue
                        if (YearMonth.from(d) != ym) continue
                        part[d] = (part[d] ?: 0) + 1
                        if ((r.state ?: "published") == "planned") {
                            planned[d] = true
                        }
                    }
                }
                _ui.value = _ui.value.copy(
                    loadingMonth = false,
                    ownCountByDay = own,
                    participantCountByDay = part,
                    plannedByDay = planned
                )
            }.onFailure { e ->
                _ui.value = _ui.value.copy(
                    loadingMonth = false,
                    error = e.message?.take(300) ?: e::class.java.simpleName
                )
            }
        }
    }

    private fun loadDayWorkouts(day: LocalDate) {
        viewModelScope.launch {
            _ui.value = _ui.value.copy(dayLoading = true, error = null)
            val start = day.atStartOfDay(zone).toInstant()
            val end = day.plusDays(1).atStartOfDay(zone).toInstant()
            val iso: (Instant) -> String = { it.toString() }
            runCatching {
                val rOwn = supabase.from(BackendContracts.Tables.WORKOUTS)
                    .select(
                        columns = Columns.raw("id, user_id, kind, title, state, started_at, calories_kcal")
                    ) {
                        filter {
                            eq("user_id", profileUserId)
                            gte("started_at", iso(start))
                            lt("started_at", iso(end))
                        }
                    }
                val wOwn = decodeList<WorkoutListRow>(rOwn.data)
                val ownIds = wOwn.map { it.id }.toSet()
                val pRes = supabase.from(BackendContracts.Tables.WORKOUT_PARTICIPANTS)
                    .select(columns = Columns.raw("workout_id")) {
                        filter { eq("user_id", profileUserId) }
                    }
                val allPartIds = decodeList<PIdRow>(pRes.data).map { it.workoutId }.distinct()
                var wPart: List<WorkoutListRow> = emptyList()
                if (allPartIds.isNotEmpty()) {
                    val rP = supabase.from(BackendContracts.Tables.WORKOUTS)
                        .select(
                            columns = Columns.raw("id, user_id, kind, title, state, started_at, calories_kcal")
                        ) {
                            filter {
                                isIn("id", allPartIds.map { it.toString() })
                                gte("started_at", iso(start))
                                lt("started_at", iso(end))
                            }
                        }
                    wPart = decodeList<WorkoutListRow>(rP.data)
                        .filter { it.id !in ownIds }
                }
                val allIds = (wOwn + wPart).map { it.id }
                val scores = fetchScoresByWorkout(allIds)
                fun toUi(rows: List<WorkoutListRow>, participated: Boolean) = rows.map { w ->
                    ProfileDayWorkoutUi(
                        id = w.id,
                        userId = w.userId,
                        kind = w.kind,
                        title = w.title,
                        state = w.state,
                        startedAt = w.startedAt,
                        isParticipated = participated,
                        score = scores[w.id]
                    )
                }.sortedByDescending { it.startedAt.orEmpty() }
                _ui.value = _ui.value.copy(
                    dayLoading = false,
                    dayOwn = toUi(wOwn, false),
                    dayParticipated = toUi(wPart, true)
                )
            }.onFailure { e ->
                _ui.value = _ui.value.copy(
                    dayLoading = false,
                    error = e.message?.take(300) ?: e::class.java.simpleName
                )
            }
        }
    }

    @Serializable
    private data class WorkoutListRow(
        val id: Int,
        @SerialName("user_id") val userId: String,
        val kind: String,
        val title: String? = null,
        val state: String? = null,
        @SerialName("started_at") val startedAt: String? = null
    )

    @Serializable
    private data class ScoreRow(
        @SerialName("workout_id") val workoutId: Int,
        val score: Double? = null
    )

    private suspend fun fetchScoresByWorkout(ids: List<Int>): Map<Int, Double> {
        if (ids.isEmpty()) return emptyMap()
        val res = supabase.from(BackendContracts.Tables.WORKOUT_SCORES)
            .select(columns = Columns.raw("workout_id, score")) {
                filter { isIn("workout_id", ids.map { it.toString() }) }
            }
        val rows = decodeList<ScoreRow>(res.data)
        val out = HashMap<Int, Double>()
        for (r in rows) {
            val d = r.score ?: continue
            out[r.workoutId] = (out[r.workoutId] ?: 0.0) + d
        }
        return out
    }

    private fun parseStartLocalDate(s: String?): LocalDate? {
        if (s.isNullOrBlank()) return null
        return runCatching { Instant.parse(s).atZone(zone).toLocalDate() }.getOrNull()
    }

    private inline fun <reified T> decodeList(raw: String): List<T> =
        SupabaseResponseDecoding.decodeListOrObject(raw)
}

class ProfileMonthCalendarViewModelFactory(
    private val supabase: SupabaseClient,
    private val profileUserId: String
) : ViewModelProvider.Factory {
    @Suppress("UNCHECKED_CAST")
    override fun <T : ViewModel> create(modelClass: Class<T>): T {
        if (modelClass != ProfileMonthCalendarViewModel::class.java) {
            error("Unknown ViewModel: ${modelClass.name}")
        }
        return ProfileMonthCalendarViewModel(supabase, profileUserId) as T
    }
}

/** 7 inicios de fila: Lunes…Domingo (paridad [Liftr/ProfileView.swift] `WEEK_START` + grid). */
fun buildMonthGridCells(ym: YearMonth): List<LocalDate?> {
    val first = ym.atDay(1)
    val monday = DayOfWeek.MONDAY
    val lead = (first.dayOfWeek.value - monday.value + 7) % 7
    val n = ym.lengthOfMonth()
    val cells = ArrayList<LocalDate?>(42)
    repeat(lead) { cells.add(null) }
    for (d in 1..n) {
        cells.add(ym.atDay(d))
    }
    while (cells.size % 7 != 0) {
        cells.add(null)
    }
    return cells
}

fun formatMonthTitle(ym: YearMonth, locale: Locale = Locale.getDefault()): String {
    val f = DateTimeFormatter.ofPattern("LLLL yyyy", locale)
    return f.format(ym.atDay(1)).replaceFirstChar { it.titlecase(locale) }
}

/** Cabecera corta de días (Mon…Sun) según locale, fila a partir del lunes. */
fun weekDayLabels(locale: Locale = Locale.getDefault()): List<String> {
    val monday = java.time.DayOfWeek.MONDAY
    val out = ArrayList<String>(7)
    var d = monday
    repeat(7) {
        out.add(d.getDisplayName(java.time.format.TextStyle.NARROW, locale))
        d = d.plus(1)
    }
    return out
}
