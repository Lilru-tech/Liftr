package com.lilru.liftr.ui.ranking

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.lilru.liftr.data.BackendContracts
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.postgrest
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import org.json.JSONArray
import org.json.JSONObject

enum class RankingScope { GLOBAL, FRIENDS }
enum class RankingPeriod { DAY, WEEK, MONTH, ALL }
enum class RankingKind { ALL, STRENGTH, CARDIO, SPORT }
enum class RankingMetric {
    SCORE,
    CALORIES,
    LEVEL,
    BEST_WORKOUT,
    GOALS_COMPLETED,
    DUELS_WON,
    STRENGTH_VOLUME,
    STRENGTH_REPS,
    STRENGTH_SETS,
    STRENGTH_MAX_SET_WEIGHT,
    CARDIO_DISTANCE,
    CARDIO_ELEVATION,
    CARDIO_DURATION,
    CARDIO_BEST_PACE,
    SPORT_MATCH_WINS,
    SPORT_WIN_RATE,
    SPORT_DURATION,
    LIKES_RECEIVED,
    COMMENTS_RECEIVED,
    GROUP_SESSIONS,
    ACHIEVEMENTS,
    HYROX_BEST_TIME,
    FOOTBALL_GOALS,
    SKI_DISTANCE_KPI
}

private fun RankingMetric.isVisibleFor(kind: RankingKind): Boolean = when (this) {
    RankingMetric.STRENGTH_VOLUME,
    RankingMetric.STRENGTH_REPS,
    RankingMetric.STRENGTH_SETS,
    RankingMetric.STRENGTH_MAX_SET_WEIGHT -> kind == RankingKind.ALL || kind == RankingKind.STRENGTH
    RankingMetric.CARDIO_DISTANCE,
    RankingMetric.CARDIO_ELEVATION,
    RankingMetric.CARDIO_DURATION,
    RankingMetric.CARDIO_BEST_PACE -> kind == RankingKind.ALL || kind == RankingKind.CARDIO
    RankingMetric.SPORT_MATCH_WINS,
    RankingMetric.SPORT_WIN_RATE,
    RankingMetric.SPORT_DURATION,
    RankingMetric.HYROX_BEST_TIME,
    RankingMetric.FOOTBALL_GOALS,
    RankingMetric.SKI_DISTANCE_KPI -> kind == RankingKind.ALL || kind == RankingKind.SPORT
    RankingMetric.LIKES_RECEIVED,
    RankingMetric.COMMENTS_RECEIVED,
    RankingMetric.GROUP_SESSIONS,
    RankingMetric.ACHIEVEMENTS -> kind == RankingKind.ALL
    else -> true
}

internal fun rankingMetricsChipsForKind(kind: RankingKind): List<RankingMetric> =
    RankingMetric.entries.filter { it.isVisibleFor(kind) }

internal data class RankingMetricSheetSection(val title: String, val metrics: List<RankingMetric>)

internal fun rankingMetricSheetSections(kind: RankingKind): List<RankingMetricSheetSection> {
    val general = listOf(
        RankingMetric.SCORE,
        RankingMetric.CALORIES,
        RankingMetric.LEVEL,
        RankingMetric.BEST_WORKOUT,
        RankingMetric.GOALS_COMPLETED,
        RankingMetric.DUELS_WON
    )
    val strength = listOf(
        RankingMetric.STRENGTH_VOLUME,
        RankingMetric.STRENGTH_REPS,
        RankingMetric.STRENGTH_SETS,
        RankingMetric.STRENGTH_MAX_SET_WEIGHT
    ).filter { it.isVisibleFor(kind) }
    val cardio = listOf(
        RankingMetric.CARDIO_DISTANCE,
        RankingMetric.CARDIO_ELEVATION,
        RankingMetric.CARDIO_DURATION,
        RankingMetric.CARDIO_BEST_PACE
    ).filter { it.isVisibleFor(kind) }
    val social = listOf(
        RankingMetric.LIKES_RECEIVED,
        RankingMetric.COMMENTS_RECEIVED,
        RankingMetric.GROUP_SESSIONS,
        RankingMetric.ACHIEVEMENTS
    ).filter { it.isVisibleFor(kind) }
    val sport = listOf(
        RankingMetric.SPORT_MATCH_WINS,
        RankingMetric.SPORT_WIN_RATE,
        RankingMetric.SPORT_DURATION,
        RankingMetric.HYROX_BEST_TIME,
        RankingMetric.FOOTBALL_GOALS,
        RankingMetric.SKI_DISTANCE_KPI
    ).filter { it.isVisibleFor(kind) }
    return listOf(
        RankingMetricSheetSection("General", general),
        RankingMetricSheetSection("Social", social),
        RankingMetricSheetSection("Strength", strength),
        RankingMetricSheetSection("Cardio", cardio),
        RankingMetricSheetSection("Sport", sport)
    ).filter { it.metrics.isNotEmpty() }
}

/** Al abrir el ranking embebido (p. ej. desde Level y XP) con misma lógica que [RankingViewModel]. */
data class RankingInitial(
    val metric: RankingMetric? = null,
    val scope: RankingScope? = null
)

data class RankingUserRow(
    val rank: Int,
    val userId: String,
    val username: String?,
    val avatarUrl: String? = null,
    val primary: String,
    val secondary: String
)

data class RankingWorkoutRow(
    val rank: Int,
    val workoutId: Long,
    val userId: String,
    val username: String?,
    val avatarUrl: String? = null,
    val kind: String?,
    val title: String?,
    val startedAt: String?,
    val score: String
)

data class RankingUiState(
    val loading: Boolean = true,
    val isRefreshing: Boolean = false,
    val error: String? = null,
    val metric: RankingMetric = RankingMetric.SCORE,
    val scope: RankingScope = RankingScope.GLOBAL,
    val period: RankingPeriod = RankingPeriod.WEEK,
    val kind: RankingKind = RankingKind.ALL,
    val userRows: List<RankingUserRow> = emptyList(),
    val workoutRows: List<RankingWorkoutRow> = emptyList()
)

class RankingViewModel(
    private val supabase: SupabaseClient,
    private val initial: RankingInitial? = null
) : ViewModel() {
    private val _uiState = MutableStateFlow(
        RankingUiState(
            metric = initial?.metric ?: RankingMetric.SCORE,
            scope = initial?.scope ?: RankingScope.GLOBAL
        )
    )
    val uiState: StateFlow<RankingUiState> = _uiState.asStateFlow()

    init {
        refresh()
    }

    fun setMetric(v: RankingMetric) {
        val st = _uiState.value
        val period = if (v == RankingMetric.GROUP_SESSIONS && st.period != RankingPeriod.ALL) {
            RankingPeriod.ALL
        } else {
            st.period
        }
        _uiState.value = st.copy(metric = v, period = period)
        refresh()
    }

    fun setScope(v: RankingScope) {
        _uiState.value = _uiState.value.copy(scope = v)
        refresh()
    }

    fun setPeriod(v: RankingPeriod) {
        _uiState.value = _uiState.value.copy(period = v)
        refresh()
    }

    fun setKind(v: RankingKind) {
        val st = _uiState.value
        val metric = if (!st.metric.isVisibleFor(v)) {
            RankingMetric.SCORE
        } else {
            st.metric
        }
        _uiState.value = st.copy(kind = v, metric = metric)
        refresh()
    }

    /**
     * @param showBlockingLoader false en pull-to-refresh: mantiene la lista visible y usa [isRefreshing].
     */
    fun refresh(showBlockingLoader: Boolean = true) {
        viewModelScope.launch {
            val st = _uiState.value
            _uiState.value = if (showBlockingLoader) {
                st.copy(loading = true, isRefreshing = false, error = null)
            } else {
                st.copy(isRefreshing = true, error = null)
            }
            runCatching {
                when (st.metric) {
                    RankingMetric.SCORE -> fetchScore(st)
                    RankingMetric.CALORIES -> fetchCalories(st)
                    RankingMetric.LEVEL -> fetchLevel(st)
                    RankingMetric.BEST_WORKOUT -> fetchBestWorkouts(st)
                    RankingMetric.GOALS_COMPLETED -> fetchGoalsCompleted(st)
                    RankingMetric.DUELS_WON -> fetchDuelsWon(st)
                    RankingMetric.STRENGTH_VOLUME -> fetchStrengthVolume(st)
                    RankingMetric.STRENGTH_REPS -> fetchStrengthReps(st)
                    RankingMetric.STRENGTH_SETS -> fetchStrengthSets(st)
                    RankingMetric.STRENGTH_MAX_SET_WEIGHT -> fetchStrengthMaxWeight(st)
                    RankingMetric.CARDIO_DISTANCE -> fetchCardioDistance(st)
                    RankingMetric.CARDIO_ELEVATION -> fetchCardioElevation(st)
                    RankingMetric.CARDIO_DURATION -> fetchCardioDuration(st)
                    RankingMetric.CARDIO_BEST_PACE -> fetchCardioBestPace(st)
                    RankingMetric.SPORT_MATCH_WINS -> fetchSportMatchWins(st)
                    RankingMetric.SPORT_WIN_RATE -> fetchSportWinRate(st)
                    RankingMetric.SPORT_DURATION -> fetchSportDuration(st)
                    RankingMetric.LIKES_RECEIVED -> fetchLikesReceived(st)
                    RankingMetric.COMMENTS_RECEIVED -> fetchCommentsReceived(st)
                    RankingMetric.GROUP_SESSIONS -> fetchGroupSessions(st)
                    RankingMetric.ACHIEVEMENTS -> fetchAchievements(st)
                    RankingMetric.HYROX_BEST_TIME -> fetchHyroxBestTime(st)
                    RankingMetric.FOOTBALL_GOALS -> fetchFootballGoals(st)
                    RankingMetric.SKI_DISTANCE_KPI -> fetchSkiDistanceKpi(st)
                }
            }.onSuccess { (users, workouts) ->
                _uiState.value = _uiState.value.copy(
                    loading = false,
                    isRefreshing = false,
                    userRows = users,
                    workoutRows = workouts
                )
            }.onFailure { e ->
                _uiState.value = _uiState.value.copy(
                    loading = false,
                    isRefreshing = false,
                    error = e.message?.take(300) ?: e::class.java.simpleName
                )
            }
        }
    }

    private suspend fun fetchScore(st: RankingUiState): Pair<List<RankingUserRow>, List<RankingWorkoutRow>> {
        val params = buildJsonObject {
            put("p_scope", mapScope(st.scope))
            put("p_period", mapPeriod(st.period))
            put("p_kind", mapKind(st.kind))
            put("p_algorithm", JsonNull)
            put("p_limit", 100)
            put("p_sex", JsonNull)
            put("p_age_band", JsonNull)
        }
        val res = supabase.postgrest.rpc(BackendContracts.Rpc.GET_LEADERBOARD_V1, params) { }
        val arr = parseArrayFlexible(res.data)
        val rows = (0 until arr.length()).mapNotNull { idx ->
            arr.optJSONObject(idx)?.let { o ->
                RankingUserRow(
                    rank = o.optInt("rank", idx + 1),
                    userId = o.optString("user_id"),
                    username = o.optNullableString("username"),
                    avatarUrl = o.optNullableString("avatar_url"),
                    primary = "Score: ${o.optDouble("total_score", 0.0).format1()}",
                    secondary = "Workouts: ${o.optInt("workouts_cnt", 0)}"
                )
            }
        }
        return rows to emptyList()
    }

    private suspend fun fetchCalories(st: RankingUiState): Pair<List<RankingUserRow>, List<RankingWorkoutRow>> {
        val params = buildJsonObject {
            put("p_scope", mapScope(st.scope))
            put("p_period", mapPeriod(st.period))
            put("p_kind", mapKind(st.kind))
            put("p_limit", 100)
            put("p_sex", JsonNull)
            put("p_age_band", JsonNull)
        }
        val res = supabase.postgrest.rpc(BackendContracts.Rpc.GET_CALORIES_LEADERBOARD_V1, params) { }
        val arr = parseArrayFlexible(res.data)
        val rows = (0 until arr.length()).mapNotNull { idx ->
            arr.optJSONObject(idx)?.let { o ->
                RankingUserRow(
                    rank = o.optInt("rank", idx + 1),
                    userId = o.optString("user_id"),
                    username = o.optNullableString("username"),
                    avatarUrl = o.optNullableString("avatar_url"),
                    primary = "Kcal: ${o.optDouble("total_kcal", 0.0).toInt()}",
                    secondary = "Workouts: ${o.optInt("workouts_cnt", 0)}"
                )
            }
        }
        return rows to emptyList()
    }

    private suspend fun fetchLevel(st: RankingUiState): Pair<List<RankingUserRow>, List<RankingWorkoutRow>> {
        val params = buildJsonObject {
            put("p_scope", mapScope(st.scope))
            put("p_limit", 100)
            put("p_sex", JsonNull)
            put("p_age_band", JsonNull)
        }
        val res = supabase.postgrest.rpc(BackendContracts.Rpc.GET_LEVEL_LEADERBOARD_V1, params) { }
        val arr = parseArrayFlexible(res.data)
        val rows = (0 until arr.length()).mapNotNull { idx ->
            arr.optJSONObject(idx)?.let { o ->
                RankingUserRow(
                    rank = o.optInt("rank", idx + 1),
                    userId = o.optString("user_id"),
                    username = o.optNullableString("username"),
                    avatarUrl = o.optNullableString("avatar_url"),
                    primary = "Level: ${o.optInt("level", 0)}",
                    secondary = "XP: ${o.optLong("xp", 0)}"
                )
            }
        }
        return rows to emptyList()
    }

    private suspend fun fetchBestWorkouts(st: RankingUiState): Pair<List<RankingUserRow>, List<RankingWorkoutRow>> {
        val params = buildJsonObject {
            put("p_scope", mapScope(st.scope))
            put("p_period", mapPeriod(st.period))
            put("p_kind", mapKind(st.kind))
            put("p_limit", 100)
            put("p_sex", JsonNull)
            put("p_age_band", JsonNull)
        }
        val res = supabase.postgrest.rpc(BackendContracts.Rpc.GET_BEST_WORKOUTS_LEADERBOARD_V1, params) { }
        val arr = parseArrayFlexible(res.data)
        val rows = (0 until arr.length()).mapNotNull { idx ->
            arr.optJSONObject(idx)?.let { o ->
                RankingWorkoutRow(
                    rank = o.optInt("rank", idx + 1),
                    workoutId = o.optLong("workout_id", -1L),
                    userId = o.optString("user_id"),
                    username = o.optNullableString("username"),
                    avatarUrl = o.optNullableString("avatar_url"),
                    kind = o.optNullableString("kind"),
                    title = o.optNullableString("title"),
                    startedAt = o.optNullableString("started_at"),
                    score = o.optDouble("score", 0.0).format1()
                )
            }
        }
        return emptyList<RankingUserRow>() to rows
    }

    private suspend fun fetchGoalsCompleted(st: RankingUiState): Pair<List<RankingUserRow>, List<RankingWorkoutRow>> {
        val params = buildJsonObject {
            put("p_scope", mapScope(st.scope))
            put("p_limit", 100)
            put("p_sex", JsonNull)
            put("p_age_band", JsonNull)
        }
        val res = supabase.postgrest.rpc(BackendContracts.Rpc.GET_GOALS_COMPLETED_LEADERBOARD_V1, params) { }
        val arr = parseArrayFlexible(res.data)
        val rows = (0 until arr.length()).mapNotNull { idx ->
            arr.optJSONObject(idx)?.let { o ->
                RankingUserRow(
                    rank = o.optInt("rank", idx + 1),
                    userId = o.optString("user_id"),
                    username = o.optNullableString("username"),
                    avatarUrl = o.optNullableString("avatar_url"),
                    primary = "Completed: ${o.optLong("completed_goals", 0)}",
                    secondary = "Weeks: ${o.optLong("goal_weeks", 0)}"
                )
            }
        }
        return rows to emptyList()
    }

    private suspend fun fetchStrengthVolume(st: RankingUiState): Pair<List<RankingUserRow>, List<RankingWorkoutRow>> {
        val params = buildJsonObject {
            put("p_scope", mapScope(st.scope))
            put("p_period", mapPeriod(st.period))
            put("p_limit", 100)
            put("p_sex", JsonNull)
            put("p_age_band", JsonNull)
            put("p_muscle_primary", JsonNull)
        }
        val res = supabase.postgrest.rpc(BackendContracts.Rpc.GET_STRENGTH_VOLUME_LEADERBOARD_V1, params) { }
        val arr = parseArrayFlexible(res.data)
        val rows = (0 until arr.length()).mapNotNull { idx ->
            arr.optJSONObject(idx)?.let { o ->
                val vol = o.optDouble("total_volume_kg", 0.0)
                val primary = if (vol >= 1000) {
                    "Volume: ${String.format("%.1fk kg", vol / 1000.0)}"
                } else {
                    "Volume: ${String.format("%.0f kg", vol)}"
                }
                RankingUserRow(
                    rank = o.optInt("rank", idx + 1),
                    userId = o.optString("user_id"),
                    username = o.optNullableString("username"),
                    avatarUrl = o.optNullableString("avatar_url"),
                    primary = primary,
                    secondary = "Workouts: ${o.optInt("workouts_cnt", 0)}"
                )
            }
        }
        return rows to emptyList()
    }

    private suspend fun fetchCardioDistance(st: RankingUiState): Pair<List<RankingUserRow>, List<RankingWorkoutRow>> {
        val params = buildJsonObject {
            put("p_scope", mapScope(st.scope))
            put("p_period", mapPeriod(st.period))
            put("p_limit", 100)
            put("p_sex", JsonNull)
            put("p_age_band", JsonNull)
            put("p_activity_code", JsonNull)
        }
        val res = supabase.postgrest.rpc(BackendContracts.Rpc.GET_CARDIO_DISTANCE_LEADERBOARD_V1, params) { }
        val arr = parseArrayFlexible(res.data)
        val rows = (0 until arr.length()).mapNotNull { idx ->
            arr.optJSONObject(idx)?.let { o ->
                val km = o.optDouble("total_distance_km", 0.0)
                val primary = if (km >= 100) {
                    "Distance: ${String.format("%.0f km", km)}"
                } else {
                    "Distance: ${String.format("%.1f km", km)}"
                }
                RankingUserRow(
                    rank = o.optInt("rank", idx + 1),
                    userId = o.optString("user_id"),
                    username = o.optNullableString("username"),
                    avatarUrl = o.optNullableString("avatar_url"),
                    primary = primary,
                    secondary = "Workouts: ${o.optInt("workouts_cnt", 0)}"
                )
            }
        }
        return rows to emptyList()
    }

    private suspend fun fetchSportMatchWins(st: RankingUiState): Pair<List<RankingUserRow>, List<RankingWorkoutRow>> {
        val params = buildJsonObject {
            put("p_scope", mapScope(st.scope))
            put("p_period", mapPeriod(st.period))
            put("p_limit", 100)
            put("p_sex", JsonNull)
            put("p_age_band", JsonNull)
            put("p_sport", JsonNull)
        }
        val res = supabase.postgrest.rpc(BackendContracts.Rpc.GET_SPORT_MATCH_WINS_LEADERBOARD_V1, params) { }
        val arr = parseArrayFlexible(res.data)
        val rows = (0 until arr.length()).mapNotNull { idx ->
            arr.optJSONObject(idx)?.let { o ->
                RankingUserRow(
                    rank = o.optInt("rank", idx + 1),
                    userId = o.optString("user_id"),
                    username = o.optNullableString("username"),
                    avatarUrl = o.optNullableString("avatar_url"),
                    primary = "Wins: ${o.optLong("wins", 0)}",
                    secondary = "Matches: ${o.optLong("matches_played", 0)}"
                )
            }
        }
        return rows to emptyList()
    }

    private suspend fun fetchCardioElevation(st: RankingUiState): Pair<List<RankingUserRow>, List<RankingWorkoutRow>> {
        val params = buildJsonObject {
            put("p_scope", mapScope(st.scope))
            put("p_period", mapPeriod(st.period))
            put("p_limit", 100)
            put("p_sex", JsonNull)
            put("p_age_band", JsonNull)
            put("p_activity_code", JsonNull)
        }
        val res = supabase.postgrest.rpc(BackendContracts.Rpc.GET_CARDIO_ELEVATION_LEADERBOARD_V1, params) { }
        val arr = parseArrayFlexible(res.data)
        val rows = (0 until arr.length()).mapNotNull { idx ->
            arr.optJSONObject(idx)?.let { o ->
                val m = o.optLong("total_elevation_m", 0L)
                val primary = if (m >= 1000) {
                    "Ascent: ${String.format("%.1fk m", m / 1000.0)}"
                } else {
                    "Ascent: ${m} m"
                }
                RankingUserRow(
                    rank = o.optInt("rank", idx + 1),
                    userId = o.optString("user_id"),
                    username = o.optNullableString("username"),
                    avatarUrl = o.optNullableString("avatar_url"),
                    primary = primary,
                    secondary = "Workouts: ${o.optInt("workouts_cnt", 0)}"
                )
            }
        }
        return rows to emptyList()
    }

    private suspend fun fetchCardioDuration(st: RankingUiState): Pair<List<RankingUserRow>, List<RankingWorkoutRow>> {
        val params = buildJsonObject {
            put("p_scope", mapScope(st.scope))
            put("p_period", mapPeriod(st.period))
            put("p_limit", 100)
            put("p_sex", JsonNull)
            put("p_age_band", JsonNull)
            put("p_activity_code", JsonNull)
        }
        val res = supabase.postgrest.rpc(BackendContracts.Rpc.GET_CARDIO_DURATION_LEADERBOARD_V1, params) { }
        val arr = parseArrayFlexible(res.data)
        val rows = (0 until arr.length()).mapNotNull { idx ->
            arr.optJSONObject(idx)?.let { o ->
                val sec = o.optLong("total_duration_sec", 0L)
                val primary = formatDurationSec(sec)
                RankingUserRow(
                    rank = o.optInt("rank", idx + 1),
                    userId = o.optString("user_id"),
                    username = o.optNullableString("username"),
                    avatarUrl = o.optNullableString("avatar_url"),
                    primary = "Time: $primary",
                    secondary = "Workouts: ${o.optInt("workouts_cnt", 0)}"
                )
            }
        }
        return rows to emptyList()
    }

    private suspend fun fetchCardioBestPace(st: RankingUiState): Pair<List<RankingUserRow>, List<RankingWorkoutRow>> {
        val params = buildJsonObject {
            put("p_scope", mapScope(st.scope))
            put("p_period", mapPeriod(st.period))
            put("p_limit", 100)
            put("p_sex", JsonNull)
            put("p_age_band", JsonNull)
            put("p_activity_code", JsonNull)
            put("p_min_distance_km", 1.0)
        }
        val res = supabase.postgrest.rpc(BackendContracts.Rpc.GET_CARDIO_BEST_PACE_LEADERBOARD_V1, params) { }
        val arr = parseArrayFlexible(res.data)
        val rows = (0 until arr.length()).mapNotNull { idx ->
            arr.optJSONObject(idx)?.let { o ->
                val pace = o.optInt("best_pace_sec_per_km", 0)
                val m = pace / 60
                val s = pace % 60
                val primary = String.format("Best pace: %d:%02d /km", m, s)
                RankingUserRow(
                    rank = o.optInt("rank", idx + 1),
                    userId = o.optString("user_id"),
                    username = o.optNullableString("username"),
                    avatarUrl = o.optNullableString("avatar_url"),
                    primary = primary,
                    secondary = "Sessions ≥1 km: ${o.optInt("qualifying_workouts_cnt", 0)}"
                )
            }
        }
        return rows to emptyList()
    }

    private suspend fun fetchStrengthReps(st: RankingUiState): Pair<List<RankingUserRow>, List<RankingWorkoutRow>> {
        val params = buildJsonObject {
            put("p_scope", mapScope(st.scope))
            put("p_period", mapPeriod(st.period))
            put("p_limit", 100)
            put("p_sex", JsonNull)
            put("p_age_band", JsonNull)
            put("p_muscle_primary", JsonNull)
        }
        val res = supabase.postgrest.rpc(BackendContracts.Rpc.GET_STRENGTH_TOTAL_REPS_LEADERBOARD_V1, params) { }
        val arr = parseArrayFlexible(res.data)
        val rows = (0 until arr.length()).mapNotNull { idx ->
            arr.optJSONObject(idx)?.let { o ->
                RankingUserRow(
                    rank = o.optInt("rank", idx + 1),
                    userId = o.optString("user_id"),
                    username = o.optNullableString("username"),
                    avatarUrl = o.optNullableString("avatar_url"),
                    primary = "Reps: ${o.optLong("total_reps", 0)}",
                    secondary = "Workouts: ${o.optInt("workouts_cnt", 0)}"
                )
            }
        }
        return rows to emptyList()
    }

    private suspend fun fetchStrengthSets(st: RankingUiState): Pair<List<RankingUserRow>, List<RankingWorkoutRow>> {
        val params = buildJsonObject {
            put("p_scope", mapScope(st.scope))
            put("p_period", mapPeriod(st.period))
            put("p_limit", 100)
            put("p_sex", JsonNull)
            put("p_age_band", JsonNull)
            put("p_muscle_primary", JsonNull)
        }
        val res = supabase.postgrest.rpc(BackendContracts.Rpc.GET_STRENGTH_TOTAL_SETS_LEADERBOARD_V1, params) { }
        val arr = parseArrayFlexible(res.data)
        val rows = (0 until arr.length()).mapNotNull { idx ->
            arr.optJSONObject(idx)?.let { o ->
                RankingUserRow(
                    rank = o.optInt("rank", idx + 1),
                    userId = o.optString("user_id"),
                    username = o.optNullableString("username"),
                    avatarUrl = o.optNullableString("avatar_url"),
                    primary = "Sets: ${o.optLong("total_sets", 0)}",
                    secondary = "Workouts: ${o.optInt("workouts_cnt", 0)}"
                )
            }
        }
        return rows to emptyList()
    }

    private suspend fun fetchStrengthMaxWeight(st: RankingUiState): Pair<List<RankingUserRow>, List<RankingWorkoutRow>> {
        val params = buildJsonObject {
            put("p_scope", mapScope(st.scope))
            put("p_period", mapPeriod(st.period))
            put("p_limit", 100)
            put("p_sex", JsonNull)
            put("p_age_band", JsonNull)
            put("p_muscle_primary", JsonNull)
        }
        val res = supabase.postgrest.rpc(BackendContracts.Rpc.GET_STRENGTH_MAX_SET_WEIGHT_LEADERBOARD_V1, params) { }
        val arr = parseArrayFlexible(res.data)
        val rows = (0 until arr.length()).mapNotNull { idx ->
            arr.optJSONObject(idx)?.let { o ->
                val kg = o.optDouble("max_weight_kg", 0.0)
                val primary = "Max set: ${String.format("%.1f kg", kg)}"
                RankingUserRow(
                    rank = o.optInt("rank", idx + 1),
                    userId = o.optString("user_id"),
                    username = o.optNullableString("username"),
                    avatarUrl = o.optNullableString("avatar_url"),
                    primary = primary,
                    secondary = "Workouts: ${o.optInt("workouts_cnt", 0)}"
                )
            }
        }
        return rows to emptyList()
    }

    private suspend fun fetchSportDuration(st: RankingUiState): Pair<List<RankingUserRow>, List<RankingWorkoutRow>> {
        val params = buildJsonObject {
            put("p_scope", mapScope(st.scope))
            put("p_period", mapPeriod(st.period))
            put("p_limit", 100)
            put("p_sex", JsonNull)
            put("p_age_band", JsonNull)
            put("p_sport", JsonNull)
        }
        val res = supabase.postgrest.rpc(BackendContracts.Rpc.GET_SPORT_DURATION_LEADERBOARD_V1, params) { }
        val arr = parseArrayFlexible(res.data)
        val rows = (0 until arr.length()).mapNotNull { idx ->
            arr.optJSONObject(idx)?.let { o ->
                val sec = o.optLong("total_duration_sec", 0L)
                val primary = formatDurationSec(sec)
                RankingUserRow(
                    rank = o.optInt("rank", idx + 1),
                    userId = o.optString("user_id"),
                    username = o.optNullableString("username"),
                    avatarUrl = o.optNullableString("avatar_url"),
                    primary = "Play time: $primary",
                    secondary = "Workouts: ${o.optInt("workouts_cnt", 0)}"
                )
            }
        }
        return rows to emptyList()
    }

    private suspend fun fetchSportWinRate(st: RankingUiState): Pair<List<RankingUserRow>, List<RankingWorkoutRow>> {
        val params = buildJsonObject {
            put("p_scope", mapScope(st.scope))
            put("p_period", mapPeriod(st.period))
            put("p_limit", 100)
            put("p_sex", JsonNull)
            put("p_age_band", JsonNull)
            put("p_sport", JsonNull)
            put("p_min_matches", 3)
        }
        val res = supabase.postgrest.rpc(BackendContracts.Rpc.GET_SPORT_WIN_RATE_LEADERBOARD_V1, params) { }
        val arr = parseArrayFlexible(res.data)
        val rows = (0 until arr.length()).mapNotNull { idx ->
            arr.optJSONObject(idx)?.let { o ->
                val rate = o.optDouble("win_rate", 0.0) * 100.0
                RankingUserRow(
                    rank = o.optInt("rank", idx + 1),
                    userId = o.optString("user_id"),
                    username = o.optNullableString("username"),
                    avatarUrl = o.optNullableString("avatar_url"),
                    primary = "Win rate: ${String.format("%.0f%%", rate)}",
                    secondary = "Wins: ${o.optLong("wins", 0)} / ${o.optLong("matches_played", 0)} (min 3 matches)"
                )
            }
        }
        return rows to emptyList()
    }

    private suspend fun fetchLikesReceived(st: RankingUiState): Pair<List<RankingUserRow>, List<RankingWorkoutRow>> {
        val params = buildJsonObject {
            put("p_scope", mapScope(st.scope))
            put("p_period", mapPeriod(st.period))
            put("p_limit", 100)
            put("p_sex", JsonNull)
            put("p_age_band", JsonNull)
        }
        val res = supabase.postgrest.rpc(BackendContracts.Rpc.GET_WORKOUT_LIKES_RECEIVED_LEADERBOARD_V1, params) { }
        val arr = parseArrayFlexible(res.data)
        val rows = (0 until arr.length()).mapNotNull { idx ->
            arr.optJSONObject(idx)?.let { o ->
                RankingUserRow(
                    rank = o.optInt("rank", idx + 1),
                    userId = o.optString("user_id"),
                    username = o.optNullableString("username"),
                    avatarUrl = o.optNullableString("avatar_url"),
                    primary = "Likes: ${o.optLong("likes_received", 0)}",
                    secondary = "Published workouts: ${o.optInt("published_workouts_cnt", 0)}"
                )
            }
        }
        return rows to emptyList()
    }

    private suspend fun fetchCommentsReceived(st: RankingUiState): Pair<List<RankingUserRow>, List<RankingWorkoutRow>> {
        val params = buildJsonObject {
            put("p_scope", mapScope(st.scope))
            put("p_period", mapPeriod(st.period))
            put("p_limit", 100)
            put("p_sex", JsonNull)
            put("p_age_band", JsonNull)
        }
        val res = supabase.postgrest.rpc(BackendContracts.Rpc.GET_WORKOUT_COMMENTS_RECEIVED_LEADERBOARD_V1, params) { }
        val arr = parseArrayFlexible(res.data)
        val rows = (0 until arr.length()).mapNotNull { idx ->
            arr.optJSONObject(idx)?.let { o ->
                RankingUserRow(
                    rank = o.optInt("rank", idx + 1),
                    userId = o.optString("user_id"),
                    username = o.optNullableString("username"),
                    avatarUrl = o.optNullableString("avatar_url"),
                    primary = "Comments: ${o.optLong("comments_received", 0)}",
                    secondary = "Published workouts: ${o.optInt("published_workouts_cnt", 0)}"
                )
            }
        }
        return rows to emptyList()
    }

    private suspend fun fetchGroupSessions(st: RankingUiState): Pair<List<RankingUserRow>, List<RankingWorkoutRow>> {
        val params = buildJsonObject {
            put("p_scope", mapScope(st.scope))
            put("p_period", mapPeriod(st.period))
            put("p_limit", 100)
            put("p_sex", JsonNull)
            put("p_age_band", JsonNull)
        }
        val res = supabase.postgrest.rpc(BackendContracts.Rpc.GET_GROUP_WORKOUT_SESSIONS_LEADERBOARD_V1, params) { }
        val arr = parseArrayFlexible(res.data)
        val rows = (0 until arr.length()).mapNotNull { idx ->
            arr.optJSONObject(idx)?.let { o ->
                RankingUserRow(
                    rank = o.optInt("rank", idx + 1),
                    userId = o.optString("user_id"),
                    username = o.optNullableString("username"),
                    avatarUrl = o.optNullableString("avatar_url"),
                    primary = "Group sessions (2+): ${o.optInt("group_sessions_cnt", 0)}",
                    secondary = "of ${o.optInt("published_workouts_cnt", 0)} published in period"
                )
            }
        }
        return rows to emptyList()
    }

    private suspend fun fetchAchievements(st: RankingUiState): Pair<List<RankingUserRow>, List<RankingWorkoutRow>> {
        val params = buildJsonObject {
            put("p_scope", mapScope(st.scope))
            put("p_period", mapPeriod(st.period))
            put("p_limit", 100)
            put("p_sex", JsonNull)
            put("p_age_band", JsonNull)
        }
        val res = supabase.postgrest.rpc(BackendContracts.Rpc.GET_ACHIEVEMENTS_UNLOCKED_PERIOD_LEADERBOARD_V1, params) { }
        val arr = parseArrayFlexible(res.data)
        val rows = (0 until arr.length()).mapNotNull { idx ->
            arr.optJSONObject(idx)?.let { o ->
                RankingUserRow(
                    rank = o.optInt("rank", idx + 1),
                    userId = o.optString("user_id"),
                    username = o.optNullableString("username"),
                    avatarUrl = o.optNullableString("avatar_url"),
                    primary = "Unlocked: ${o.optLong("unlocked_cnt", 0)}",
                    secondary = "Uses period selector above"
                )
            }
        }
        return rows to emptyList()
    }

    private suspend fun fetchHyroxBestTime(st: RankingUiState): Pair<List<RankingUserRow>, List<RankingWorkoutRow>> {
        val params = buildJsonObject {
            put("p_scope", mapScope(st.scope))
            put("p_period", mapPeriod(st.period))
            put("p_limit", 100)
            put("p_sex", JsonNull)
            put("p_age_band", JsonNull)
        }
        val res = supabase.postgrest.rpc(BackendContracts.Rpc.GET_HYROX_BEST_OFFICIAL_TIME_LEADERBOARD_V1, params) { }
        val arr = parseArrayFlexible(res.data)
        val rows = (0 until arr.length()).mapNotNull { idx ->
            arr.optJSONObject(idx)?.let { o ->
                val sec = o.optLong("best_official_time_sec", 0L)
                val primary = "Best time: ${formatDurationSec(sec)}"
                RankingUserRow(
                    rank = o.optInt("rank", idx + 1),
                    userId = o.optString("user_id"),
                    username = o.optNullableString("username"),
                    avatarUrl = o.optNullableString("avatar_url"),
                    primary = primary,
                    secondary = "Hyrox sessions: ${o.optInt("hyrox_sessions_cnt", 0)}"
                )
            }
        }
        return rows to emptyList()
    }

    private suspend fun fetchFootballGoals(st: RankingUiState): Pair<List<RankingUserRow>, List<RankingWorkoutRow>> {
        val params = buildJsonObject {
            put("p_scope", mapScope(st.scope))
            put("p_period", mapPeriod(st.period))
            put("p_limit", 100)
            put("p_sex", JsonNull)
            put("p_age_band", JsonNull)
        }
        val res = supabase.postgrest.rpc(BackendContracts.Rpc.GET_FOOTBALL_GOALS_LEADERBOARD_V1, params) { }
        val arr = parseArrayFlexible(res.data)
        val rows = (0 until arr.length()).mapNotNull { idx ->
            arr.optJSONObject(idx)?.let { o ->
                RankingUserRow(
                    rank = o.optInt("rank", idx + 1),
                    userId = o.optString("user_id"),
                    username = o.optNullableString("username"),
                    avatarUrl = o.optNullableString("avatar_url"),
                    primary = "Goals: ${o.optLong("total_goals", 0)}",
                    secondary = "Sessions: ${o.optInt("sessions_cnt", 0)}"
                )
            }
        }
        return rows to emptyList()
    }

    private suspend fun fetchSkiDistanceKpi(st: RankingUiState): Pair<List<RankingUserRow>, List<RankingWorkoutRow>> {
        val params = buildJsonObject {
            put("p_scope", mapScope(st.scope))
            put("p_period", mapPeriod(st.period))
            put("p_limit", 100)
            put("p_sex", JsonNull)
            put("p_age_band", JsonNull)
        }
        val res = supabase.postgrest.rpc(BackendContracts.Rpc.GET_SKI_DISTANCE_LEADERBOARD_V1, params) { }
        val arr = parseArrayFlexible(res.data)
        val rows = (0 until arr.length()).mapNotNull { idx ->
            arr.optJSONObject(idx)?.let { o ->
                val km = o.optDouble("total_distance_km", 0.0)
                val primary = if (km >= 100) {
                    "Ski: ${String.format("%.0f km", km)}"
                } else {
                    "Ski: ${String.format("%.1f km", km)}"
                }
                RankingUserRow(
                    rank = o.optInt("rank", idx + 1),
                    userId = o.optString("user_id"),
                    username = o.optNullableString("username"),
                    avatarUrl = o.optNullableString("avatar_url"),
                    primary = primary,
                    secondary = "Sessions: ${o.optInt("sessions_cnt", 0)}"
                )
            }
        }
        return rows to emptyList()
    }

    private fun formatDurationSec(sec: Long): String {
        val s = sec.toInt().coerceAtLeast(0)
        if (s < 3600) return "${s / 60}m"
        val h = s / 3600
        val m = (s % 3600) / 60
        return "${h}h ${m}m"
    }

    private suspend fun fetchDuelsWon(st: RankingUiState): Pair<List<RankingUserRow>, List<RankingWorkoutRow>> {
        val params = buildJsonObject {
            put("p_scope", mapScope(st.scope))
            put("p_limit", 100)
            put("p_sex", JsonNull)
            put("p_age_band", JsonNull)
        }
        val res = supabase.postgrest.rpc(BackendContracts.Rpc.GET_DUELS_WON_LEADERBOARD_V1, params) { }
        val arr = parseArrayFlexible(res.data)
        val rows = (0 until arr.length()).mapNotNull { idx ->
            arr.optJSONObject(idx)?.let { o ->
                RankingUserRow(
                    rank = o.optInt("rank", idx + 1),
                    userId = o.optString("user_id"),
                    username = o.optNullableString("username"),
                    avatarUrl = o.optNullableString("avatar_url"),
                    primary = "Wins: ${o.optLong("wins", 0)}",
                    secondary = "Duels: ${o.optLong("duels_finished", 0)}"
                )
            }
        }
        return rows to emptyList()
    }

    private fun parseArrayFlexible(raw: String): JSONArray {
        val t = raw.trim()
        if (t.startsWith("[")) return JSONArray(t)
        if (t.startsWith("{")) {
            val o = JSONObject(t)
            val data = o.opt("data")
            return when (data) {
                is JSONArray -> data
                is JSONObject -> JSONArray().put(data)
                else -> JSONArray().put(o)
            }
        }
        return JSONArray()
    }

    private fun mapScope(v: RankingScope): String = if (v == RankingScope.GLOBAL) "global" else "friends"
    private fun mapKind(v: RankingKind): String = v.name.lowercase()
    private fun mapPeriod(v: RankingPeriod): String = when (v) {
        RankingPeriod.DAY -> "day"
        RankingPeriod.WEEK -> "week"
        RankingPeriod.MONTH -> "month"
        RankingPeriod.ALL -> "all"
    }
}

private fun JSONObject.optNullableString(key: String): String? =
    if (has(key) && !isNull(key)) optString(key).takeIf { it.isNotBlank() } else null

private fun Double.format1(): String = String.format("%.1f", this)

class RankingViewModelFactory(
    private val supabase: SupabaseClient,
    private val initial: RankingInitial? = null
) : ViewModelProvider.Factory {
    @Suppress("UNCHECKED_CAST")
    override fun <T : ViewModel> create(modelClass: Class<T>): T {
        if (modelClass != RankingViewModel::class.java) {
            error("Unknown ViewModel: ${modelClass.name}")
        }
        return RankingViewModel(supabase, initial) as T
    }
}
