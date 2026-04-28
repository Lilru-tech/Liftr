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
enum class RankingMetric { SCORE, CALORIES, LEVEL, BEST_WORKOUT }

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
        _uiState.value = _uiState.value.copy(metric = v)
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
        _uiState.value = _uiState.value.copy(kind = v)
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
