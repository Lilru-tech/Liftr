package com.lilru.liftr.ui.home

import android.app.Application
import android.util.Log
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.lilru.liftr.data.BackendContracts
import com.lilru.liftr.prefs.LiftrPreferences
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.query.Columns
import io.github.jan.supabase.postgrest.query.Order
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import org.json.JSONArray
import org.json.JSONObject
import java.util.LinkedHashMap
import java.time.DayOfWeek
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.YearMonth
import java.time.ZonedDateTime
import java.time.temporal.ChronoUnit
import java.time.temporal.TemporalAdjusters
import java.time.temporal.WeekFields
import kotlin.math.roundToInt
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope

@Serializable
data class WorkoutSummary(
    val id: Int,
    @SerialName("user_id") val userId: String,
    val kind: String? = null,
    val title: String? = null,
    @SerialName("started_at") val startedAt: String? = null,
    @SerialName("ended_at") val endedAt: String? = null,
    val state: String? = null,
    @SerialName("calories_kcal") val caloriesKcal: Double? = null,
    /** Primer `activity_code` de [cardio_sessions] embebido (paridad con iOS). */
    val cardioActivityCode: String? = null,
    val sportName: String? = null,
    /** Rellenado tras un segundo `select` a [profiles] (como en [HomeView.swift] `ensureProfiles`). */
    val ownerUsername: String? = null,
    val ownerAvatarUrl: String? = null,
    val likeCount: Int = 0,
    val isLikedByMe: Boolean = false,
    val score: Double? = null,
    val coAvatarUrls: List<String> = emptyList()
)

data class HomeMonthPoint(
    val dayOfMonth: Int,
    val value: Double
)

data class HomeMonthSummaryUi(
    val label: String,
    val workoutCount: Int,
    val scoreTotal: Int,
    val deltaPercent: Double? = null,
    val series: List<HomeMonthPoint> = emptyList()
)

data class HomePrRow(
    val userId: String,
    val username: String?,
    val kind: String,
    val label: String,
    val metric: String,
    val value: Double,
    val achievedAt: String
)

enum class HomeKindFilter { ALL, STRENGTH, CARDIO, SPORT }

/**
 * Criterio de listado alineado con [Liftr/HomeView.swift]
 * (una query: filas del usuario con cualquier `state`, o followees con `state != planned`).
 */

data class HomeWeeklyTopUser(
    val userId: String,
    val username: String?,
    val avatarUrl: String?,
    val points: Int
)

data class HomeUiState(
    val loading: Boolean = true,
    val error: String? = null,
    val isRefreshing: Boolean = false,
    val kindFilter: HomeKindFilter = HomeKindFilter.ALL,
    val workouts: List<WorkoutSummary> = emptyList(),
    val monthSummary: HomeMonthSummaryUi? = null,
    val isPremium: Boolean = false,
    val recentPrs: List<HomePrRow> = emptyList(),
    val todayCount: Int = 0,
    val todayMinutes: Int = 0,
    val todayPoints: Int = 0,
    val todayKcal: Int = 0,
    val streakDays: Int = 0,
    val weekWorkouts: Int = 0,
    val weekPoints: Int = 0,
    val weekKcal: Int = 0,
    val weeklyTop: List<HomeWeeklyTopUser> = emptyList(),
    val strongestWeekPtsMtd: Int = 0,
    val strongestWeekKcalMtd: Int = 0,
    val bestSportScore: Int = 0,
    val bestSportLabel: String = "",
    val canLoadMore: Boolean = true,
    val isLoadingMore: Boolean = false
)

class HomeViewModel(
    private val supabase: SupabaseClient,
    private val app: Application
) : ViewModel() {
    private companion object {
        const val TAG = "HomeViewModel"
        const val PAGE_SIZE: Int = 30
    }

    private val _uiState = MutableStateFlow(HomeUiState())
    val uiState: StateFlow<HomeUiState> = _uiState.asStateFlow()

    private var cachedFolloweeIds: List<String> = emptyList()
    private var nextFeedPage: Int = 0

    init {
        refresh()
    }

    fun setKindFilter(kind: HomeKindFilter) {
        if (_uiState.value.kindFilter == kind) return
        _uiState.value = _uiState.value.copy(kindFilter = kind)
        refresh()
    }

    /**
     * Paridad con iOS: al cerrar [WorkoutDetail] tras editar, refrescar fila y recalcular
     * resúmenes (p. ej. [recalcHomeSummaries] en [Liftr/HomeView.swift]).
     */
    fun onReturnFromWorkoutDetail(workoutId: Int) {
        viewModelScope.launch {
            runCatching { refreshOneWorkoutAndRecalcHome(workoutId) }
                .onFailure { e -> Log.w(TAG, "onReturnFromWorkoutDetail: ${e.message}") }
        }
    }

    private val likeToggleInFlight = mutableSetOf<Int>()

    /** Paridad con [WorkoutDetailViewModel.toggleLike] para el feed. */
    fun toggleLikeOnWorkout(workoutId: Int) {
        synchronized(likeToggleInFlight) {
            if (!likeToggleInFlight.add(workoutId)) return
        }
        viewModelScope.launch {
            try {
                val me = supabase.auth.currentUserOrNull()?.id ?: return@launch
                val w = _uiState.value.workouts.find { it.id == workoutId } ?: return@launch
                @Serializable
                data class LikeInsert(
                    @SerialName("workout_id") val workoutId: Int,
                    @SerialName("user_id") val userId: String
                )
                runCatching {
                    if (w.isLikedByMe) {
                        supabase.from(BackendContracts.Tables.WORKOUT_LIKES).delete {
                            filter {
                                eq("workout_id", workoutId)
                                eq("user_id", me)
                            }
                        }
                    } else {
                        supabase.from(BackendContracts.Tables.WORKOUT_LIKES).insert(
                            LikeInsert(workoutId = workoutId, userId = me)
                        ) { }
                    }
                }.onSuccess {
                    _uiState.update { st ->
                        st.copy(
                            workouts = st.workouts.map { row ->
                                if (row.id != workoutId) {
                                    row
                                } else {
                                    val nowLiked = !row.isLikedByMe
                                    row.copy(
                                        isLikedByMe = nowLiked,
                                        likeCount = (row.likeCount + if (nowLiked) 1 else -1)
                                            .coerceAtLeast(0)
                                    )
                                }
                            }
                        )
                    }
                }
            } finally {
                synchronized(likeToggleInFlight) {
                    likeToggleInFlight.remove(workoutId)
                }
            }
        }
    }

    fun loadMore() {
        viewModelScope.launch {
            val st = _uiState.value
            if (st.isLoadingMore || !st.canLoadMore || st.loading) return@launch
            if (st.error != null) return@launch
            _uiState.update { it.copy(isLoadingMore = true) }
            val me = supabase.auth.currentUserOrNull()?.id
            if (me == null) {
                _uiState.update { it.copy(isLoadingMore = false) }
                return@launch
            }
            val from = nextFeedPage * PAGE_SIZE
            if (from < 0) {
                _uiState.update { it.copy(isLoadingMore = false) }
                return@launch
            }
            runCatching {
                val visible = (listOf(me) + cachedFolloweeIds).distinct()
                fetchWorkoutPage(me, visible, st.kindFilter, from)
            }.onSuccess { (parsed, canMore) ->
                if (parsed.isNotEmpty()) {
                    val merged = mergeOwnerProfiles(parsed)
                    val enriched = enrichWithSocial(me, merged)
                    _uiState.update { cur ->
                        val combined = (cur.workouts + enriched)
                            .distinctBy { it.id }
                            .sortedByDescending { it.startedAt.orEmpty() }
                        cur.copy(
                            workouts = combined,
                            isLoadingMore = false,
                            canLoadMore = canMore
                        )
                    }
                    if (canMore) nextFeedPage += 1
                } else {
                    _uiState.update { it.copy(isLoadingMore = false, canLoadMore = false) }
                }
            }.onFailure { e ->
                Log.w(TAG, "loadMore: ${e.message}")
                _uiState.update { it.copy(isLoadingMore = false, canLoadMore = false) }
            }
        }
    }

    fun refresh() {
        viewModelScope.launch {
            val st = _uiState.value
            val isPull = st.workouts.isNotEmpty() ||
                (st.error != null) ||
                (st.workouts.isEmpty() && !st.loading)
            if (isPull) {
                _uiState.value = st.copy(isRefreshing = true, error = null)
            } else {
                _uiState.value = st.copy(loading = true, error = null)
            }
            runCatching {
                val me = supabase.auth.currentUserOrNull()?.id
                if (me == null) {
                    nextFeedPage = 0
                    cachedFolloweeIds = emptyList()
                    _uiState.value = HomeUiState(
                        loading = false,
                        isRefreshing = false,
                        error = null,
                        kindFilter = st.kindFilter,
                        workouts = emptyList(),
                        monthSummary = null,
                        recentPrs = emptyList(),
                        canLoadMore = false,
                        isLoadingMore = false
                    )
                    return@launch
                }
                val followees = fetchFolloweeIds(me)
                cachedFolloweeIds = followees
                val visibleUserIds = (listOf(me) + followees).distinct()
                nextFeedPage = 0
                val response = supabase
                    .from(BackendContracts.Tables.WORKOUTS)
                    .select(
                        columns = Columns.raw(
                            "id, user_id, kind, title, started_at, ended_at, state, calories_kcal, " +
                                "cardio_sessions(activity_code), sport_sessions(sport)"
                        )
                    ) {
                        filter {
                            or {
                                eq("user_id", me)
                                and {
                                    isIn("user_id", visibleUserIds)
                                    neq("state", "planned")
                                }
                            }
                        }
                        if (st.kindFilter != HomeKindFilter.ALL) {
                            filter { eq("kind", st.kindFilter.name.lowercase()) }
                        }
                        order("started_at", Order.DESCENDING)
                        range(0L, PAGE_SIZE - 1L)
                    }
                val pageRows = parseWorkoutRows(response.data)
                val canLoadMore = pageRows.size == PAGE_SIZE
                if (canLoadMore) nextFeedPage = 1 else nextFeedPage = 0
                val merged = mergeOwnerProfiles(pageRows)
                val enriched = enrichWithSocial(me, merged)
                val month = runCatching { loadIosMonthDetail(me) }
                    .getOrNull() ?: buildMonthSummaryFallback(me, merged)
                val prs = runCatching { loadRecentPrs(me, followees) }
                    .getOrElse { e ->
                        Log.w(TAG, "PRs: ${e.message}")
                        emptyList()
                    }
                val premium = LiftrPreferences.isPremium(app)
                val r = recalcParallels(me, followees, visibleUserIds)
                HomeRefreshResult(enriched, month, prs, premium, canLoadMore, r)
            }.onSuccess { h ->
                Log.i(TAG, "HOME success. workouts=${h.enriched.size} filter=${_uiState.value.kindFilter}")
                _uiState.value = _uiState.value.copy(
                    loading = false,
                    isRefreshing = false,
                    workouts = h.enriched,
                    monthSummary = h.month,
                    recentPrs = h.prs,
                    isPremium = h.premium,
                    canLoadMore = h.canLoadMore,
                    isLoadingMore = false,
                    error = null,
                    todayCount = h.r.todayCount,
                    todayMinutes = h.r.todayMinutes,
                    todayPoints = h.r.todayPoints,
                    todayKcal = h.r.todayKcal,
                    streakDays = h.r.streakDays,
                    weekWorkouts = h.r.weekWorkouts,
                    weekPoints = h.r.weekPoints,
                    weekKcal = h.r.weekKcal,
                    weeklyTop = h.r.weeklyTop,
                    strongestWeekPtsMtd = h.r.strongestWeekPtsMtd,
                    strongestWeekKcalMtd = h.r.strongestWeekKcalMtd,
                    bestSportScore = h.r.bestSportScore,
                    bestSportLabel = h.r.bestSportLabel
                )
            }.onFailure { e ->
                Log.e(TAG, "HOME failure", e)
                _uiState.value = _uiState.value.copy(
                    loading = false,
                    isRefreshing = false,
                    isLoadingMore = false,
                    error = "HOME: " + (e.message?.take(260) ?: e::class.java.simpleName)
                )
            }
        }
    }

    private data class RecalcResult(
        val todayCount: Int = 0,
        val todayMinutes: Int = 0,
        val todayPoints: Int = 0,
        val todayKcal: Int = 0,
        val streakDays: Int = 0,
        val weekWorkouts: Int = 0,
        val weekPoints: Int = 0,
        val weekKcal: Int = 0,
        val weeklyTop: List<HomeWeeklyTopUser> = emptyList(),
        val strongestWeekPtsMtd: Int = 0,
        val strongestWeekKcalMtd: Int = 0,
        val bestSportScore: Int = 0,
        val bestSportLabel: String = ""
    )

    private data class HomeRefreshResult(
        val enriched: List<WorkoutSummary>,
        val month: HomeMonthSummaryUi?,
        val prs: List<HomePrRow>,
        val premium: Boolean,
        val canLoadMore: Boolean,
        val r: RecalcResult
    )

    private suspend fun recalcParallels(
        me: String,
        followees: List<String>,
        visibleUserIds: List<String>
    ): RecalcResult = coroutineScope {
        val todayA = async { runCatching { loadTodayBlock(me) }.getOrNull() }
        val weekA = async { runCatching { loadWeekAndLeaderboard(me, followees, visibleUserIds) }.getOrNull() }
        val streakA = async { runCatching { loadStreakCount(me) }.getOrNull() }
        val insightA = async { runCatching { loadInsightsBlock(me) }.getOrNull() }
        val todayR = todayA.await() ?: RecalcResult()
        val weekR = weekA.await() ?: RecalcResult()
        val st = streakA.await() ?: 0
        val ins = insightA.await() ?: RecalcResult()
        RecalcResult(
            todayCount = todayR.todayCount,
            todayMinutes = todayR.todayMinutes,
            todayPoints = todayR.todayPoints,
            todayKcal = todayR.todayKcal,
            streakDays = st,
            weekWorkouts = weekR.weekWorkouts,
            weekPoints = weekR.weekPoints,
            weekKcal = weekR.weekKcal,
            weeklyTop = weekR.weeklyTop,
            strongestWeekPtsMtd = ins.strongestWeekPtsMtd,
            strongestWeekKcalMtd = ins.strongestWeekKcalMtd,
            bestSportScore = ins.bestSportScore,
            bestSportLabel = ins.bestSportLabel
        )
    }

    private suspend fun loadTodayBlock(me: String): RecalcResult {
        val zone = ZoneId.systemDefault()
        val start = LocalDate.now(zone).atStartOfDay(zone)
        val end = start.plusDays(1)
        val iso: (Instant) -> String = { it.toString() }
        val res = supabase
            .from(BackendContracts.Tables.WORKOUTS)
            .select(
                columns = Columns.raw("id, started_at, ended_at, calories_kcal")
            ) {
                filter { eq("user_id", me) }
                filter { gte("started_at", iso(start.toInstant())) }
                filter { lt("started_at", iso(end.toInstant())) }
                order("started_at", Order.DESCENDING)
            }
        val rows = parseIdStartedCalRows(res.data)
        if (rows.isEmpty()) {
            return RecalcResult(0, 0, 0, 0)
        }
        val scores = fetchWorkoutScoresSum(rows.map { it.id.toString() })
        var minutes = 0
        var points = 0
        var kcalT = 0
        for (r in rows) {
            r.ended?.let { endS ->
                val s0 = runCatching { Instant.parse(r.started) }.getOrNull()
                val e0 = runCatching { Instant.parse(endS) }.getOrNull()
                if (s0 != null && e0 != null) {
                    val m = ChronoUnit.MINUTES.between(s0, e0).toInt()
                    if (m > 0) minutes += m
                }
            }
            val sc = scores[r.id] ?: 0.0
            points += sc.roundToInt()
            r.kcal?.let { kcalT += it.roundToInt() }
        }
        return RecalcResult(
            todayCount = rows.size,
            todayMinutes = minutes,
            todayPoints = points,
            todayKcal = kcalT
        )
    }

    private data class StartedCal(
        val id: Int,
        val started: String,
        val ended: String?,
        val kcal: Double?
    )

    private fun parseIdStartedCalRows(raw: String): List<StartedCal> {
        val t = raw.trim()
        if (t.isEmpty()) return emptyList()
        return runCatching {
            val arr = when {
                t.startsWith("[") -> JSONArray(t)
                t.startsWith("{") -> (JSONObject(t).opt("data") as? JSONArray) ?: JSONArray()
                else -> return emptyList()
            }
            val out = ArrayList<StartedCal>()
            for (i in 0 until arr.length()) {
                val o = arr.optJSONObject(i) ?: continue
                val id = o.optInt("id", Int.MIN_VALUE).takeIf { it != Int.MIN_VALUE } ?: continue
                val st = o.optString("started_at", "")
                if (st.isBlank()) continue
                val kc = if (o.has("calories_kcal") && !o.isNull("calories_kcal")) {
                    o.optDouble("calories_kcal")
                } else {
                    null
                }
                out.add(StartedCal(id, st, o.optString("ended_at", "").takeIf { it.isNotBlank() }, kc))
            }
            out
        }.getOrDefault(emptyList())
    }

    private suspend fun loadWeekAndLeaderboard(
        me: String,
        followees: List<String>,
        visibleUserIds: List<String>
    ): RecalcResult {
        val zone = ZoneId.systemDefault()
        val nowZ = ZonedDateTime.now(zone)
        val weekStart = nowZ.toLocalDate()
            .with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY))
            .atStartOfDay(zone)
        val iso: (Instant) -> String = { it.toString() }
        val nowInst = nowZ.toInstant()
        val allRes = supabase
            .from(BackendContracts.Tables.WORKOUTS)
            .select(columns = Columns.raw("id, user_id, started_at, ended_at, kind, state, calories_kcal")) {
                filter { isIn("user_id", visibleUserIds) }
                filter { gte("started_at", iso(weekStart.toInstant())) }
                filter { lt("started_at", iso(nowInst)) }
                order("started_at", Order.DESCENDING)
            }
        val allRows = parseIdUserStartedCalRows(allRes.data)
        val meRes = supabase
            .from(BackendContracts.Tables.WORKOUTS)
            .select(columns = Columns.raw("id, user_id, started_at, ended_at, calories_kcal")) {
                filter { eq("user_id", me) }
                filter { gte("started_at", iso(weekStart.toInstant())) }
                filter { lt("started_at", iso(nowInst)) }
                order("started_at", Order.DESCENDING)
            }
        val meRows = parseIdUserStartedCalRows(meRes.data)
        val allIds = (allRows.map { it.wid } + meRows.map { it.wid }).distinct()
        val sc = if (allIds.isNotEmpty()) fetchWorkoutScoresSum(allIds.map { it.toString() }) else emptyMap()
        var myPts = 0
        var myKcal = 0
        for (r in meRows) {
            myPts += (sc[r.wid] ?: 0.0).roundToInt()
            if (r.kcal != null) myKcal += r.kcal.roundToInt()
        }
        val byUser = mutableMapOf<String, Int>()
        for (r in allRows) {
            byUser[r.uid] = (byUser[r.uid] ?: 0) + (sc[r.wid] ?: 0.0).roundToInt()
        }
        val topUids = byUser.entries
            .sortedByDescending { it.value }
            .take(3)
        val nameMap = if (topUids.isNotEmpty()) {
            fetchOwnerProfilesByUserId(topUids.map { it.key })
        } else {
            emptyMap()
        }
        val weeklyTop = topUids.map { (u, p) ->
            val prof = nameMap[u]
            HomeWeeklyTopUser(
                userId = u,
                username = prof?.first,
                avatarUrl = prof?.second,
                points = p
            )
        }
        return RecalcResult(
            weekWorkouts = meRows.size,
            weekPoints = myPts,
            weekKcal = myKcal,
            weeklyTop = weeklyTop
        )
    }

    private data class IdUserRow(
        val wid: Int,
        val uid: String,
        val kcal: Double?
    )

    private fun parseIdUserStartedCalRows(raw: String): List<IdUserRow> {
        val t = raw.trim()
        if (t.isEmpty()) return emptyList()
        return runCatching {
            val arr = when {
                t.startsWith("[") -> JSONArray(t)
                t.startsWith("{") -> (JSONObject(t).opt("data") as? JSONArray) ?: JSONArray()
                else -> return emptyList()
            }
            val out = ArrayList<IdUserRow>()
            for (i in 0 until arr.length()) {
                val o = arr.optJSONObject(i) ?: continue
                val id = o.optInt("id", Int.MIN_VALUE).takeIf { it != Int.MIN_VALUE } ?: continue
                val u = o.optString("user_id", "").takeIf { it.isNotBlank() } ?: continue
                val kc = if (o.has("calories_kcal") && !o.isNull("calories_kcal")) o.optDouble("calories_kcal") else null
                out.add(IdUserRow(id, u, kc))
            }
            out
        }.getOrDefault(emptyList())
    }

    private suspend fun loadStreakCount(me: String): Int {
        val zone = ZoneId.systemDefault()
        val now = ZonedDateTime.now(zone).toInstant()
        val start = now.minus(60, ChronoUnit.DAYS)
        val res = supabase
            .from(BackendContracts.Tables.WORKOUTS)
            .select(columns = Columns.raw("started_at")) {
                filter { eq("user_id", me) }
                filter { gte("started_at", start.toString()) }
                filter { lt("started_at", now.toString()) }
            }
        val dates = parseStartedAtOnly(res.data)
            .mapNotNull { s ->
                runCatching { Instant.parse(s) }.getOrNull()?.atZone(zone)?.toLocalDate()
            }
        return computeStreak(dates, zone)
    }

    private fun parseStartedAtOnly(raw: String): List<String> {
        val t = raw.trim()
        if (t.isEmpty()) return emptyList()
        return runCatching {
            val arr = when {
                t.startsWith("[") -> JSONArray(t)
                t.startsWith("{") -> (JSONObject(t).opt("data") as? JSONArray) ?: JSONArray()
                else -> return emptyList()
            }
            val out = ArrayList<String>()
            for (i in 0 until arr.length()) {
                val o = arr.optJSONObject(i) ?: continue
                o.optString("started_at", "").takeIf { it.isNotBlank() }?.let { out.add(it) }
            }
            out
        }.getOrDefault(emptyList())
    }

    private fun computeStreak(dates: List<LocalDate>, zone: ZoneId): Int {
        val set = dates.map { it }.toSet()
        var c = 0
        var cursor = LocalDate.now(zone)
        while (set.contains(cursor)) {
            c++
            cursor = cursor.minusDays(1)
        }
        return c
    }

    private suspend fun loadInsightsBlock(me: String): RecalcResult {
        val a = runCatching { loadStrongestWeekMtd(me) }.getOrNull() ?: RecalcResult()
        val b = runCatching { loadBestSportMatch(me) }.getOrNull() ?: RecalcResult()
        return RecalcResult(
            strongestWeekPtsMtd = a.strongestWeekPtsMtd,
            strongestWeekKcalMtd = a.strongestWeekKcalMtd,
            bestSportScore = b.bestSportScore,
            bestSportLabel = b.bestSportLabel
        )
    }

    private suspend fun loadStrongestWeekMtd(me: String): RecalcResult {
        val zone = ZoneId.systemDefault()
        val ym = YearMonth.now(zone)
        val now = ZonedDateTime.now(zone)
        val monthStart = ym.atDay(1).atStartOfDay(zone).toInstant()
        val endInst = now.toInstant()
        val iso: (Instant) -> String = { it.toString() }
        val wRes = supabase
            .from(BackendContracts.Tables.WORKOUTS)
            .select(columns = Columns.raw("id,started_at,calories_kcal")) {
                filter { eq("user_id", me) }
                filter { gte("started_at", iso(monthStart)) }
                filter { lt("started_at", iso(endInst)) }
                order("started_at", Order.DESCENDING)
            }
        val rows = parseIdStartedKcal(wRes.data)
        if (rows.isEmpty()) return RecalcResult()
        val sMap = if (rows.isNotEmpty()) {
            fetchWorkoutScoresSum(rows.map { it.id.toString() })
        } else {
            emptyMap()
        }
        val wf = WeekFields.of(DayOfWeek.MONDAY, 4)
        var bestPts = 0.0
        var bestKc = 0.0
        val byWeekPts = mutableMapOf<String, Double>()
        val byWeekKcal = mutableMapOf<String, Double>()
        for (r in rows) {
            val d = r.started ?: continue
            val day = runCatching { Instant.parse(d).atZone(zone).toLocalDate() }.getOrNull() ?: continue
            val yw = day.get(wf.weekBasedYear())
            val wn = day.get(wf.weekOfWeekBasedYear())
            val key = "$yw-W$wn"
            val s = sMap[r.id] ?: 0.0
            byWeekPts[key] = (byWeekPts[key] ?: 0.0) + s
            if (r.kcal != null) {
                byWeekKcal[key] = (byWeekKcal[key] ?: 0.0) + r.kcal
            }
        }
        for (v in byWeekPts.values) if (v > bestPts) bestPts = v
        for (v in byWeekKcal.values) if (v > bestKc) bestKc = v
        return RecalcResult(
            strongestWeekPtsMtd = bestPts.roundToInt(),
            strongestWeekKcalMtd = bestKc.roundToInt()
        )
    }

    private data class IdStartedK(
        val id: Int,
        val started: String,
        val kcal: Double?
    )

    private fun parseIdStartedKcal(raw: String): List<IdStartedK> {
        val t = raw.trim()
        if (t.isEmpty()) return emptyList()
        return runCatching {
            val arr = when {
                t.startsWith("[") -> JSONArray(t)
                t.startsWith("{") -> (JSONObject(t).opt("data") as? JSONArray) ?: JSONArray()
                else -> return emptyList()
            }
            val out = ArrayList<IdStartedK>()
            for (i in 0 until arr.length()) {
                val o = arr.optJSONObject(i) ?: continue
                val id = o.optInt("id", Int.MIN_VALUE).takeIf { it != Int.MIN_VALUE } ?: continue
                val st = o.optString("started_at", "")
                if (st.isBlank()) continue
                val kc = if (o.has("calories_kcal") && !o.isNull("calories_kcal")) o.optDouble("calories_kcal") else null
                out.add(IdStartedK(id, st, kc))
            }
            out
        }.getOrDefault(emptyList())
    }

    private suspend fun loadBestSportMatch(me: String): RecalcResult {
        val wRes = runCatching {
            supabase
                .from(BackendContracts.Tables.WORKOUTS)
                .select(columns = Columns.raw("id")) {
                    filter { eq("user_id", me) }
                    filter { eq("kind", "sport") }
                    order("started_at", Order.DESCENDING)
                    limit(800)
                }
        }.getOrNull() ?: return RecalcResult()
        val wIds = parseIdOnlyList(wRes.data)
        if (wIds.isEmpty()) return RecalcResult()
        val sRes = runCatching {
            supabase
                .from(BackendContracts.Tables.SPORT_SESSIONS)
                .select(columns = Columns.raw("workout_id, sport")) {
                    filter { isIn("workout_id", wIds.map { it.toString() }) }
                }
        }.getOrNull() ?: return RecalcResult()
        val t = sRes.data.trim()
        val sessions = mutableListOf<Pair<Int, String>>()
        if (t.isNotEmpty()) {
            val arr = when {
                t.startsWith("[") -> JSONArray(t)
                t.startsWith("{") -> (JSONObject(t).opt("data") as? JSONArray) ?: JSONArray()
                else -> null
            }
            if (arr != null) {
                for (i in 0 until arr.length()) {
                    val o = arr.optJSONObject(i) ?: continue
                    val w = o.optInt("workout_id", Int.MIN_VALUE).takeIf { it != Int.MIN_VALUE } ?: continue
                    val sp = o.optString("sport", "").takeIf { it.isNotBlank() } ?: continue
                    sessions.add(w to sp)
                }
            }
        }
        if (sessions.isEmpty()) return RecalcResult()
        val sc = fetchWorkoutScoresSum(wIds.map { it.toString() })
        var best = 0
        var bestLabel = ""
        for ((wid, sp) in sessions) {
            val s = (sc[wid] ?: 0.0).roundToInt()
            if (s > best) {
                best = s
                bestLabel = sp.replaceFirstChar { if (it.isLowerCase()) it.titlecase() else it.toString() }
            }
        }
        return RecalcResult(
            bestSportScore = best,
            bestSportLabel = bestLabel
        )
    }

    private suspend fun fetchWorkoutPage(
        me: String,
        visible: List<String>,
        kind: HomeKindFilter,
        from: Int
    ): Pair<List<WorkoutSummary>, Boolean> {
        val to = from + PAGE_SIZE - 1L
        val res = supabase
            .from(BackendContracts.Tables.WORKOUTS)
            .select(
                columns = Columns.raw(
                    "id, user_id, kind, title, started_at, ended_at, state, calories_kcal, " +
                        "cardio_sessions(activity_code), sport_sessions(sport)"
                )
            ) {
                filter {
                    or {
                        eq("user_id", me)
                        and {
                            isIn("user_id", visible)
                            neq("state", "planned")
                        }
                    }
                }
                if (kind != HomeKindFilter.ALL) {
                    filter { eq("kind", kind.name.lowercase()) }
                }
                order("started_at", Order.DESCENDING)
                range(from.toLong(), to)
            }
        val list = parseWorkoutRows(res.data)
        return list to (list.size == PAGE_SIZE)
    }

    private suspend fun refreshOneWorkoutAndRecalcHome(workoutId: Int) {
        val me = supabase.auth.currentUserOrNull()?.id ?: return
        val followees = cachedFolloweeIds
        val visibleUserIds = (listOf(me) + followees).distinct()
        val st = _uiState.value
        val raw = supabase
            .from(BackendContracts.Tables.WORKOUTS)
            .select(
                columns = Columns.raw(
                    "id, user_id, kind, title, started_at, ended_at, state, calories_kcal, " +
                        "cardio_sessions(activity_code), sport_sessions(sport)"
                )
            ) {
                filter { eq("id", workoutId) }
            }
            .data
        val w = parseWorkoutRows(raw).firstOrNull()
        if (w == null) {
            _uiState.update { s ->
                s.copy(workouts = s.workouts.filter { it.id != workoutId })
            }
            applyHomeSummariesAfterWorkoutListChange(me, followees, visibleUserIds)
            return
        }
        val kindFilter = st.kindFilter
        val shouldList = (w.userId == me || (visibleUserIds.contains(w.userId) && w.state?.lowercase() != "planned")) &&
            (kindFilter == HomeKindFilter.ALL || w.kind?.lowercase() == kindFilter.name.lowercase())
        if (!shouldList) {
            _uiState.update { s ->
                s.copy(workouts = s.workouts.filter { it.id != workoutId })
            }
        } else {
            val merged = mergeOwnerProfiles(listOf(w))
            val enriched = enrichWithSocial(me, merged).first()
            _uiState.update { s ->
                val rest = s.workouts.filter { it.id != workoutId }
                s.copy(
                    workouts = (rest + enriched)
                        .distinctBy { it.id }
                        .sortedByDescending { it.startedAt.orEmpty() }
                )
            }
        }
        applyHomeSummariesAfterWorkoutListChange(me, followees, visibleUserIds)
    }

    private suspend fun applyHomeSummariesAfterWorkoutListChange(
        me: String,
        followees: List<String>,
        visibleUserIds: List<String>
    ) {
        val month = runCatching { loadIosMonthDetail(me) }
            .getOrNull() ?: buildMonthSummaryFallback(me, _uiState.value.workouts)
        val prs = runCatching { loadRecentPrs(me, followees) }
            .getOrElse { emptyList() }
        val premium = LiftrPreferences.isPremium(app)
        val r = recalcParallels(me, followees, visibleUserIds)
        _uiState.update { s ->
            s.copy(
                monthSummary = month,
                recentPrs = prs,
                isPremium = premium,
                todayCount = r.todayCount,
                todayMinutes = r.todayMinutes,
                todayPoints = r.todayPoints,
                todayKcal = r.todayKcal,
                streakDays = r.streakDays,
                weekWorkouts = r.weekWorkouts,
                weekPoints = r.weekPoints,
                weekKcal = r.weekKcal,
                weeklyTop = r.weeklyTop,
                strongestWeekPtsMtd = r.strongestWeekPtsMtd,
                strongestWeekKcalMtd = r.strongestWeekKcalMtd,
                bestSportScore = r.bestSportScore,
                bestSportLabel = r.bestSportLabel
            )
        }
    }

    private suspend fun fetchFolloweeIds(me: String): List<String> {
        val response = supabase
            .from(BackendContracts.Tables.FOLLOWS)
            .select(columns = Columns.raw("followee_id")) {
                filter { eq("follower_id", me) }
                limit(500)
            }
        val trimmed = response.data.trim()
        if (trimmed.isEmpty()) return emptyList()

        return when {
            trimmed.startsWith("[") -> {
                val arr = JSONArray(trimmed)
                (0 until arr.length()).mapNotNull { idx ->
                    arr.optJSONObject(idx)?.optString("followee_id", "")?.takeIf { it.isNotBlank() }
                }
            }

            trimmed.startsWith("{") -> {
                val obj = JSONObject(trimmed)
                listOfNotNull(obj.optString("followee_id", "").takeIf { it.isNotBlank() })
            }

            else -> emptyList()
        }
    }

    private suspend fun mergeOwnerProfiles(rows: List<WorkoutSummary>): List<WorkoutSummary> {
        if (rows.isEmpty()) return rows
        val ids = rows.map { it.userId }.distinct()
        val byUser = fetchOwnerProfilesByUserId(ids)
        return rows.map { w ->
            val p = byUser[w.userId]
            w.copy(ownerUsername = p?.first, ownerAvatarUrl = p?.second)
        }
    }

    private suspend fun fetchOwnerProfilesByUserId(
        userIds: List<String>
    ): Map<String, Pair<String?, String?>> {
        if (userIds.isEmpty()) return emptyMap()
        val response = supabase
            .from(BackendContracts.Tables.PROFILES)
            .select(columns = Columns.raw("user_id, username, avatar_url")) {
                filter { isIn("user_id", userIds) }
                limit(500)
            }
        return parseProfileOwnerMap(response.data)
    }

    private fun parseProfileOwnerMap(raw: String): Map<String, Pair<String?, String?>> {
        val t = raw.trim()
        if (t.isEmpty()) return emptyMap()
        val arr = when {
            t.startsWith("[") -> JSONArray(t)
            t.startsWith("{") -> {
                val o = JSONObject(t)
                when (val d = o.opt("data")) {
                    is JSONArray -> d
                    is JSONObject -> JSONArray().put(d)
                    else -> null
                }
            }
            else -> null
        } ?: return emptyMap()
        val out = mutableMapOf<String, Pair<String?, String?>>()
        for (i in 0 until arr.length()) {
            val o = arr.optJSONObject(i) ?: continue
            val uid = o.optString("user_id", "").takeIf { it.isNotBlank() } ?: continue
            out[uid] = Pair(
                o.optProfileString("username"),
                o.optProfileString("avatar_url")
            )
        }
        return out
    }

    private fun JSONObject.optProfileString(key: String): String? =
        if (has(key) && !isNull(key)) {
            optString(key, "").takeIf { it.isNotBlank() }
        } else {
            null
        }

    private fun parseWorkoutRows(raw: String): List<WorkoutSummary> {
        val trimmed = raw.trim()
        if (trimmed.isEmpty()) return emptyList()

        return runCatching {
            when {
                trimmed.startsWith("[") -> {
                    val arr = JSONArray(trimmed)
                    (0 until arr.length()).mapNotNull { idx ->
                        arr.optJSONObject(idx)?.let(::jsonToWorkoutSummary)
                    }
                }

                trimmed.startsWith("{") -> {
                    val obj = JSONObject(trimmed)
                    when {
                        obj.has("data") && obj.opt("data") is JSONArray -> {
                            val arr = obj.optJSONArray("data") ?: JSONArray()
                            (0 until arr.length()).mapNotNull { idx ->
                                arr.optJSONObject(idx)?.let(::jsonToWorkoutSummary)
                            }
                        }

                        obj.has("data") && obj.opt("data") is JSONObject -> {
                            listOfNotNull(obj.optJSONObject("data")?.let(::jsonToWorkoutSummary))
                        }

                        else -> listOfNotNull(jsonToWorkoutSummary(obj))
                    }
                }

                else -> emptyList()
            }
        }.getOrDefault(emptyList())
    }

    private fun jsonToWorkoutSummary(obj: JSONObject): WorkoutSummary? {
        val id = obj.optInt("id", Int.MIN_VALUE).takeIf { it != Int.MIN_VALUE } ?: return null
        val userId = obj.optString("user_id", "").takeIf { it.isNotBlank() } ?: return null

        fun str(key: String): String? = obj.optString(key, "").takeIf { it.isNotBlank() }
        val calories = if (obj.has("calories_kcal") && !obj.isNull("calories_kcal")) {
            obj.optDouble("calories_kcal")
        } else {
            null
        }

        return WorkoutSummary(
            id = id,
            userId = userId,
            kind = str("kind"),
            title = str("title"),
            startedAt = str("started_at"),
            endedAt = str("ended_at"),
            state = str("state"),
            caloriesKcal = calories,
            cardioActivityCode = optCardioActivityCode(obj),
            sportName = optSportName(obj)
        )
    }

    private fun optCardioActivityCode(obj: JSONObject): String? {
        val arr = obj.optJSONArray("cardio_sessions") ?: return null
        if (arr.length() == 0) return null
        return arr.optJSONObject(0)?.optString("activity_code", "")?.takeIf { it.isNotBlank() }
    }

    private fun optSportName(obj: JSONObject): String? {
        val arr = obj.optJSONArray("sport_sessions") ?: return null
        if (arr.length() == 0) return null
        return arr.optJSONObject(0)?.optString("sport", "")?.takeIf { it.isNotBlank() }
    }

    private suspend fun enrichWithSocial(me: String, rows: List<WorkoutSummary>): List<WorkoutSummary> {
        if (rows.isEmpty()) return rows
        val ids = rows.map { it.id }
        val idStrs = ids.map { it.toString() }
        return runCatching {
            val likePairs = fetchWorkoutLikesRaw(idStrs)
            val likesByW = mutableMapOf<Int, Int>()
            val likedByMe = mutableSetOf<Int>()
            for ((wid, uid) in likePairs) {
                likesByW[wid] = (likesByW[wid] ?: 0) + 1
                if (uid == me) likedByMe.add(wid)
            }
            val scoreByW = fetchWorkoutScoresSum(idStrs)
            val coByW = fetchCoParticipantAvatars(idStrs, me)
            rows.map { w ->
                w.copy(
                    likeCount = likesByW[w.id] ?: 0,
                    isLikedByMe = likedByMe.contains(w.id),
                    score = scoreByW[w.id],
                    coAvatarUrls = coByW[w.id].orEmpty()
                )
            }
        }.getOrElse { e ->
            Log.w(TAG, "enrichWithSocial: ${e.message}")
            rows
        }
    }

    /** Aprox. iOS [HomeView.loadMonthlySummary]: series diaria, delta % vs mes anterior. */
    private suspend fun loadIosMonthDetail(me: String): HomeMonthSummaryUi? {
        val zone = ZoneId.systemDefault()
        val ym = YearMonth.now(zone)
        val monthStart = ym.atDay(1).atStartOfDay(zone)
        val monthStartInst = monthStart.toInstant()
        val endInst = ZonedDateTime.now(zone).toInstant()
        val iso = { t: Instant -> t.toString() }

        val wRes = supabase
            .from(BackendContracts.Tables.WORKOUTS)
            .select(columns = Columns.raw("id, started_at")) {
                filter { eq("user_id", me) }
                filter { gte("started_at", iso(monthStartInst)) }
                filter { lt("started_at", iso(endInst)) }
            }
        val wRows = parseIdStartedRows(wRes.data)
        if (wRows.isEmpty()) return null

        val scoreByW = fetchWorkoutScoresSum(wRows.map { it.first.toString() })
        val seriesByDay = LinkedHashMap<Int, Double>()
        var day = 1
        val lastDay = ym.lengthOfMonth()
        while (day <= lastDay) {
            seriesByDay[day] = 0.0
            day++
        }
        for ((wid, started) in wRows) {
            val d = runCatching { Instant.parse(started).atZone(zone).toLocalDate() }
                .getOrNull() ?: continue
            if (YearMonth.from(d) != ym) continue
            val dom = d.dayOfMonth
            val s = scoreByW[wid] ?: 0.0
            seriesByDay[dom] = (seriesByDay[dom] ?: 0.0) + s
        }
        val totalScore = seriesByDay.values.sum().roundToInt()
        val workoutsCount = wRows.size
        val label = "${ym.month.name.lowercase().replaceFirstChar { it.titlecase() }} ${ym.year}"

        val prevYm = ym.minusMonths(1)
        val prevStart = prevYm.atDay(1).atStartOfDay(zone).toInstant()
        val prevEnd = monthStartInst
        val pRes = supabase
            .from(BackendContracts.Tables.WORKOUTS)
            .select(columns = Columns.raw("id")) {
                filter { eq("user_id", me) }
                filter { gte("started_at", iso(prevStart)) }
                filter { lt("started_at", iso(prevEnd)) }
            }
        val prevIds = parseIdOnlyList(pRes.data)
        var prevTotal = 0.0
        if (prevIds.isNotEmpty()) {
            val pScores = fetchWorkoutScoresSum(prevIds.map { it.toString() })
            prevTotal = pScores.values.sum()
        }
        val delta = when {
            prevTotal <= 0.0 && totalScore > 0 -> 100.0
            prevTotal <= 0.0 -> 0.0
            else -> ((totalScore - prevTotal) / prevTotal) * 100.0
        }
        val series = (1..lastDay).map { d ->
            HomeMonthPoint(d, seriesByDay[d] ?: 0.0)
        }
        return HomeMonthSummaryUi(
            label = label,
            workoutCount = workoutsCount,
            scoreTotal = totalScore,
            deltaPercent = delta,
            series = series
        )
    }

    private fun parseIdStartedRows(raw: String): List<Pair<Int, String>> {
        val t = raw.trim()
        if (t.isEmpty()) return emptyList()
        return runCatching {
            val arr = when {
                t.startsWith("[") -> JSONArray(t)
                t.startsWith("{") -> {
                    val o = JSONObject(t)
                    (o.opt("data") as? JSONArray) ?: JSONArray()
                }
                else -> return emptyList()
            }
            val out = ArrayList<Pair<Int, String>>()
            for (i in 0 until arr.length()) {
                val o = arr.optJSONObject(i) ?: continue
                val id = o.optInt("id", Int.MIN_VALUE).takeIf { it != Int.MIN_VALUE } ?: continue
                val st = o.optString("started_at", "")
                if (st.isBlank()) continue
                out.add(id to st)
            }
            out
        }.getOrDefault(emptyList())
    }

    private fun parseIdOnlyList(raw: String): List<Int> {
        val t = raw.trim()
        if (t.isEmpty()) return emptyList()
        return runCatching {
            val arr = when {
                t.startsWith("[") -> JSONArray(t)
                t.startsWith("{") -> (JSONObject(t).opt("data") as? JSONArray) ?: JSONArray()
                else -> return emptyList()
            }
            val out = ArrayList<Int>()
            for (i in 0 until arr.length()) {
                val o = arr.optJSONObject(i) ?: continue
                val id = o.optInt("id", Int.MIN_VALUE).takeIf { it != Int.MIN_VALUE } ?: continue
                out.add(id)
            }
            out
        }.getOrDefault(emptyList())
    }

    private suspend fun loadRecentPrs(me: String, followees: List<String>): List<HomePrRow> {
        val allIds = (listOf(me) + followees).distinct()
        if (allIds.isEmpty()) return emptyList()
        val since = Instant.now().minus(7, ChronoUnit.DAYS).toString()
        val raw = supabase
            .from(BackendContracts.Views.VW_USER_PRS)
            .select(columns = Columns.raw("*")) {
                filter { isIn("user_id", allIds) }
                filter { gte("achieved_at", since) }
                order("achieved_at", Order.DESCENDING)
                limit(10)
            }
            .data
        val prs = parseUserPrs(raw)
        if (prs.isEmpty()) return emptyList()
        val uids = prs.map { it.userId }.distinct()
        val names = fetchOwnerProfilesByUserId(uids)
        return prs.map { p ->
            p.copy(username = names[p.userId]?.first)
        }
    }

    private fun parseUserPrs(raw: String): List<HomePrRow> {
        val t = raw.trim()
        if (t.isEmpty()) return emptyList()
        return runCatching {
            val arr = when {
                t.startsWith("[") -> JSONArray(t)
                t.startsWith("{") -> (JSONObject(t).opt("data") as? JSONArray) ?: JSONArray()
                else -> return emptyList()
            }
            val out = ArrayList<HomePrRow>()
            for (i in 0 until arr.length()) {
                val o = arr.optJSONObject(i) ?: continue
                val uid = o.optString("user_id", "")
                if (uid.isBlank()) continue
                val kind = o.optString("kind", "strength")
                val label = o.optString("label", "")
                val metric = o.optString("metric", "")
                val ach = o.optString("achieved_at", "")
                val value = if (o.has("value") && !o.isNull("value")) o.optDouble("value") else 0.0
                out.add(
                    HomePrRow(
                        userId = uid,
                        username = null,
                        kind = kind,
                        label = label,
                        metric = metric,
                        value = value,
                        achievedAt = ach
                    )
                )
            }
            out
        }.getOrDefault(emptyList())
    }

    private fun buildMonthSummaryFallback(
        me: String,
        rows: List<WorkoutSummary>
    ): HomeMonthSummaryUi? {
        val ym = YearMonth.now(ZoneId.systemDefault())
        var c = 0
        var sc = 0
        for (r in rows) {
            if (r.userId != me) continue
            val t = r.startedAt?.trim() ?: continue
            val d = runCatching {
                Instant.parse(t).atZone(ZoneId.systemDefault()).toLocalDate()
            }.getOrNull() ?: continue
            if (YearMonth.from(d) != ym) continue
            c++
            sc += (r.score ?: 0.0).roundToInt()
        }
        if (c == 0) return null
        return HomeMonthSummaryUi(
            label = "${ym.month.name.lowercase().replaceFirstChar { it.titlecase() }} ${ym.year}",
            workoutCount = c,
            scoreTotal = sc,
            deltaPercent = null,
            series = emptyList()
        )
    }

    private suspend fun fetchWorkoutLikesRaw(workoutIdStrings: List<String>): List<Pair<Int, String>> {
        if (workoutIdStrings.isEmpty()) return emptyList()
        val raw = supabase
            .from(BackendContracts.Tables.WORKOUT_LIKES)
            .select(columns = Columns.raw("workout_id, user_id")) {
                filter { isIn("workout_id", workoutIdStrings) }
                limit(2000)
            }
            .data
        return parseLikesList(raw)
    }

    private fun parseLikesList(raw: String): List<Pair<Int, String>> {
        val t = raw.trim()
        if (t.isEmpty()) return emptyList()
        val arr = when {
            t.startsWith("[") -> JSONArray(t)
            t.startsWith("{") -> {
                val o = JSONObject(t)
                when (val d = o.opt("data")) {
                    is JSONArray -> d
                    is JSONObject -> JSONArray().put(d)
                    else -> return emptyList()
                }
            }
            else -> return emptyList()
        }
        val out = ArrayList<Pair<Int, String>>()
        for (i in 0 until arr.length()) {
            val o = arr.optJSONObject(i) ?: continue
            val w = o.optInt("workout_id", Int.MIN_VALUE).takeIf { it != Int.MIN_VALUE } ?: continue
            val u = o.optString("user_id", "").takeIf { it.isNotBlank() } ?: continue
            out.add(w to u)
        }
        return out
    }

    private suspend fun fetchWorkoutScoresSum(workoutIdStrings: List<String>): Map<Int, Double> {
        if (workoutIdStrings.isEmpty()) return emptyMap()
        val raw = supabase
            .from(BackendContracts.Tables.WORKOUT_SCORES)
            .select(columns = Columns.raw("workout_id, score")) {
                filter { isIn("workout_id", workoutIdStrings) }
                limit(2000)
            }
            .data
        return parseScoresSum(raw)
    }

    private fun parseScoresSum(raw: String): Map<Int, Double> {
        val t = raw.trim()
        if (t.isEmpty()) return emptyMap()
        val arr = when {
            t.startsWith("[") -> JSONArray(t)
            t.startsWith("{") -> {
                val o = JSONObject(t)
                when (val d = o.opt("data")) {
                    is JSONArray -> d
                    is JSONObject -> JSONArray().put(d)
                    else -> return emptyMap()
                }
            }
            else -> return emptyMap()
        }
        val byW = mutableMapOf<Int, Double>()
        for (i in 0 until arr.length()) {
            val o = arr.optJSONObject(i) ?: continue
            val w = o.optInt("workout_id", Int.MIN_VALUE).takeIf { it != Int.MIN_VALUE } ?: continue
            if (!o.has("score") || o.isNull("score")) continue
            val s = o.optDouble("score", 0.0)
            byW[w] = (byW[w] ?: 0.0) + s
        }
        return byW
    }

    private suspend fun fetchCoParticipantAvatars(
        workoutIdStrings: List<String>,
        me: String
    ): Map<Int, List<String>> {
        if (workoutIdStrings.isEmpty()) return emptyMap()
        val rawP = supabase
            .from(BackendContracts.Tables.WORKOUT_PARTICIPANTS)
            .select(columns = Columns.raw("workout_id, user_id")) {
                filter { isIn("workout_id", workoutIdStrings) }
                limit(2000)
            }
            .data
        val byW = mutableMapOf<Int, MutableList<String>>()
        val t = rawP.trim()
        if (t.isEmpty()) return emptyMap()
        val arr = when {
            t.startsWith("[") -> JSONArray(t)
            t.startsWith("{") -> {
                val o = JSONObject(t)
                when (val d = o.opt("data")) {
                    is JSONArray -> d
                    is JSONObject -> JSONArray().put(d)
                    else -> return emptyMap()
                }
            }
            else -> return emptyMap()
        }
        for (i in 0 until arr.length()) {
            val o = arr.optJSONObject(i) ?: continue
            val w = o.optInt("workout_id", Int.MIN_VALUE).takeIf { it != Int.MIN_VALUE } ?: continue
            val u = o.optString("user_id", "").takeIf { it.isNotBlank() } ?: continue
            if (u == me) continue
            byW.getOrPut(w) { mutableListOf() }.add(u)
        }
        val uids = byW.values.flatMap { it }.distinct()
        if (uids.isEmpty()) return emptyMap()
        val avMap = fetchOwnerProfilesByUserId(uids)
        return byW.mapValues { (_, list) ->
            list.take(3).mapNotNull { uid -> avMap[uid]?.second }
        }
    }
}

class HomeViewModelFactory(
    private val application: Application,
    private val supabase: SupabaseClient
) : ViewModelProvider.Factory {
    @Suppress("UNCHECKED_CAST")
    override fun <T : ViewModel> create(modelClass: Class<T>): T {
        if (modelClass != HomeViewModel::class.java) {
            error("Unknown ViewModel: ${modelClass.name}")
        }
        return HomeViewModel(supabase, application) as T
    }
}
