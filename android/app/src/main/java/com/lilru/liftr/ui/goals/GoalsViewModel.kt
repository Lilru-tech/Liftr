package com.lilru.liftr.ui.goals

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.lilru.liftr.data.BackendContracts
import com.lilru.liftr.ui.home.WorkoutSummary
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Columns
import io.github.jan.supabase.postgrest.query.Order
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset
import kotlin.math.roundToInt

data class GoalsUiState(
    val loading: Boolean = true,
    val error: String? = null,
    val scope: GoalsSummaryScope = GoalsSummaryScope.WEEK,
    val goals: List<GoalRowUi> = emptyList(),
    val allTimeStats: GoalStatsUi? = null,
    val showCompletedSection: Boolean = false,
    val creating: Boolean = false,
    val recommendBusy: Boolean = false,
    val recommendValue: Int? = null,
    val refreshBusy: Boolean = false
) {
    val activeGoals: List<GoalRowUi>
        get() = goals.filter { !goalIsFinished(it) }

    val finishedGoals: List<GoalRowUi>
        get() = goals.filter { goalIsFinished(it) }

    val totalGoals: Int get() = goals.size
    val completedGoalsCount: Int get() = goals.count { it.isCompleted }
    val missedGoalsCount: Int get() = goals.count { goalIsFinished(it) && !it.isCompleted }

    val weekCompletionPercent: Int
        get() {
            if (goals.isEmpty()) return 0
            return ((completedGoalsCount.toDouble() / goals.size) * 100.0).roundToInt()
        }

    val weekAvgProgressPercent: Int
        get() {
            if (goals.isEmpty()) return 0
            val sum = goals.sumOf { it.progressRatio }
            return ((sum / goals.size) * 100.0).roundToInt()
        }

    val weekBestProgressPercent: Int
        get() {
            if (goals.isEmpty()) return 0
            return ((goals.maxOfOrNull { it.progressRatio } ?: 0.0) * 100.0).roundToInt()
        }

    val summaryPercentText: String
        get() {
            val v = when (scope) {
                GoalsSummaryScope.WEEK -> weekCompletionPercent.toDouble()
                GoalsSummaryScope.ALL_TIME -> allTimeStats?.finishedPercent ?: 0.0
            }
            return "${v.roundToInt()}%"
        }
}

@Serializable
private data class WeeklyGoalWire(
    val id: Long,
    @SerialName("user_id") val userId: String,
    @SerialName("week_start") val weekStart: String,
    val metric: String,
    @SerialName("target_value") val targetValue: Double,
    val title: String? = null
)

@Serializable
private data class WeeklyGoalResultWire(
    @SerialName("goal_id") val goalId: Long,
    @SerialName("user_id") val userId: String? = null,
    @SerialName("week_start") val weekStart: String? = null,
    @SerialName("achieved_value") val achievedValue: Double = 0.0,
    @SerialName("is_completed") val isCompleted: Boolean = false
)

@Serializable
private data class GoalStatsWire(
    @SerialName("total_goals") val totalGoals: Int = 0,
    @SerialName("finished_goals") val finishedGoals: Int = 0,
    @SerialName("missed_goals") val missedGoals: Int = 0,
    @SerialName("finished_percent") val finishedPercent: Double = 0.0,
    @SerialName("avg_progress_percent") val avgProgressPercent: Double = 0.0,
    @SerialName("best_progress_percent") val bestProgressPercent: Double = 0.0
)

@Serializable
private data class WeeklyGoalInsert(
    @SerialName("user_id") val userId: String,
    @SerialName("week_start") val weekStart: String,
    val metric: String,
    @SerialName("target_value") val targetValue: Double,
    val title: String?
)

@Serializable
private data class WorkoutContribWire(
    val id: Int,
    @SerialName("user_id") val userId: String,
    val kind: String,
    val title: String? = null,
    @SerialName("started_at") val startedAt: String? = null,
    @SerialName("ended_at") val endedAt: String? = null,
    val state: String,
    @SerialName("calories_kcal") val caloriesKcal: Double? = null
)

@Serializable
private data class ScoreWire(
    @SerialName("workout_id") val workoutId: Int,
    val score: Double
)

@Serializable
private data class ProfileContribWire(
    @SerialName("user_id") val userId: String,
    val username: String? = null,
    @SerialName("avatar_url") val avatarUrl: String? = null
)

class GoalsViewModel(
    private val supabase: SupabaseClient,
    private val targetUserId: String
) : ViewModel() {
    private val json = Json {
        ignoreUnknownKeys = true
        isLenient = true
        coerceInputValues = true
    }

    private val _uiState = MutableStateFlow(GoalsUiState())
    val uiState: StateFlow<GoalsUiState> = _uiState.asStateFlow()

    val isOwnProfile: Boolean
        get() = supabase.auth.currentUserOrNull()?.id == targetUserId

    /** Para [HomeWorkoutFeedCard] (“You” vs username del dueño). */
    val sessionUserId: String?
        get() = supabase.auth.currentUserOrNull()?.id

    fun existingMetricsThisWeek(): Set<GoalMetric> {
        val w = LiftrGoalsTime.currentWeekStartDateString()
        return _uiState.value.goals
            .filter { it.weekStartDate == w }
            .map { GoalMetric.fromWire(it.metric) }
            .toSet()
    }

    init {
        refresh()
    }

    fun setScope(scope: GoalsSummaryScope) {
        _uiState.update { it.copy(scope = scope) }
        refresh()
    }

    fun setShowCompleted(show: Boolean) {
        _uiState.update { it.copy(showCompletedSection = show) }
    }

    fun refresh() {
        viewModelScope.launch {
            _uiState.update { it.copy(loading = true, error = null) }
            runCatching {
                loadAllTimeStats()
                val rows = when (_uiState.value.scope) {
                    GoalsSummaryScope.WEEK -> fetchWeekGoals()
                    GoalsSummaryScope.ALL_TIME -> fetchAllTimeGoals()
                }
                _uiState.update {
                    it.copy(loading = false, goals = rows, error = null)
                }
            }.onFailure { e ->
                _uiState.update {
                    it.copy(loading = false, error = e.message?.take(300) ?: e::class.java.simpleName)
                }
            }
        }
    }

    private suspend fun loadAllTimeStats() {
        val params = buildJsonObject { put("p_user_id", targetUserId) }
        val res = supabase.postgrest.rpc(BackendContracts.Rpc.GET_GOAL_STATS, params) { }
        val stats = decodeGoalStats(res.data)
        _uiState.update { it.copy(allTimeStats = stats) }
    }

    private fun decodeGoalStats(raw: String): GoalStatsUi {
        val root = json.parseToJsonElement(raw)
        val w = when (root) {
            is JsonArray -> root.firstOrNull()?.let { json.decodeFromString<GoalStatsWire>(it.toString()) }
            is JsonObject -> runCatching { json.decodeFromString<GoalStatsWire>(root.toString()) }.getOrNull()
            else -> null
        } ?: return GoalStatsUi(0, 0, 0, 0.0, 0.0, 0.0)
        return GoalStatsUi(
            totalGoals = w.totalGoals,
            finishedGoals = w.finishedGoals,
            missedGoals = w.missedGoals,
            finishedPercent = w.finishedPercent,
            avgProgressPercent = w.avgProgressPercent,
            bestProgressPercent = w.bestProgressPercent
        )
    }

    private suspend fun fetchWeekGoals(): List<GoalRowUi> {
        recomputeForCurrentWeek()
        val weekStr = LiftrGoalsTime.currentWeekStartDateString()
        val gRes = supabase.from(BackendContracts.Tables.WEEKLY_GOALS)
            .select(
                columns = Columns.raw("id,user_id,week_start,metric,target_value,title")
            ) {
                filter {
                    eq("user_id", targetUserId)
                    eq("week_start", weekStr)
                }
                order("updated_at", Order.DESCENDING)
            }
        val goals = decodeList<WeeklyGoalWire>(gRes.data)
        if (goals.isEmpty()) return emptyList()
        val goalIds = goals.map { it.id }
        val rRes = supabase.from(BackendContracts.Tables.WEEKLY_GOAL_RESULTS)
            .select(
                columns = Columns.raw("goal_id,user_id,week_start,achieved_value,is_completed")
            ) {
                filter {
                    isIn("goal_id", goalIds.map { it.toString() })
                    eq("week_start", weekStr)
                }
            }
        val results = decodeList<WeeklyGoalResultWire>(rRes.data)
        val byGoal = results.associateBy { it.goalId }
        return goals.map { g ->
            val r = byGoal[g.id]
            toUi(g, r)
        }
    }

    private suspend fun recomputeForCurrentWeek() {
        val weekStr = LiftrGoalsTime.currentWeekStartDateString()
        val params = buildJsonObject {
            put("p_user_id", targetUserId)
            put("p_week_start", weekStr)
        }
        supabase.postgrest.rpc(BackendContracts.Rpc.RECOMPUTE_WEEKLY_GOAL_RESULTS, params) { }
    }

    private suspend fun fetchAllTimeGoals(): List<GoalRowUi> {
        val gRes = supabase.from(BackendContracts.Tables.WEEKLY_GOALS)
            .select(
                columns = Columns.raw("id,user_id,week_start,metric,target_value,title")
            ) {
                filter { eq("user_id", targetUserId) }
                order("week_start", Order.DESCENDING)
                limit(100)
            }
        val goals = decodeList<WeeklyGoalWire>(gRes.data)
        if (goals.isEmpty()) return emptyList()
        val goalIds = goals.map { it.id }.toSet().toList()
        val rRes = supabase.from(BackendContracts.Tables.WEEKLY_GOAL_RESULTS)
            .select(
                columns = Columns.raw("goal_id,user_id,week_start,achieved_value,is_completed")
            ) {
                filter { isIn("goal_id", goalIds.map { it.toString() }) }
            }
        val results = decodeList<WeeklyGoalResultWire>(rRes.data)
        val keyMap = results.associateBy { "${it.goalId}|${it.weekStart ?: ""}" }
        return goals.map { g ->
            val ws = normalizeWeekDate(g.weekStart)
            val r = keyMap["${g.id}|$ws"]
                ?: results.find { it.goalId == g.id && normalizeWeekDate(it.weekStart) == ws }
            toUi(g, r)
        }
    }

    private fun normalizeWeekDate(s: String?): String {
        if (s == null) return ""
        return s.take(10)
    }

    private fun toUi(g: WeeklyGoalWire, r: WeeklyGoalResultWire?): GoalRowUi {
        val t = (g.title?.trim()?.takeIf { it.isNotEmpty() } ?: "Goal")
        return GoalRowUi(
            id = g.id,
            userId = g.userId,
            weekStartDate = g.weekStart.take(10),
            title = t,
            targetValue = g.targetValue,
            achievedValue = r?.achievedValue ?: 0.0,
            isCompleted = r?.isCompleted ?: false,
            metric = g.metric
        )
    }

    fun createGoal(
        title: String,
        target: Int,
        metric: GoalMetric,
        onSuccess: () -> Unit = {}
    ) {
        if (!isOwnProfile) return
        val me = supabase.auth.currentUserOrNull()?.id ?: return
        viewModelScope.launch {
            _uiState.update { it.copy(creating = true, error = null) }
            runCatching {
                val weekStr = LiftrGoalsTime.currentWeekStartDateString()
                val ins = WeeklyGoalInsert(
                    userId = me,
                    weekStart = weekStr,
                    metric = metric.wire,
                    targetValue = target.toDouble(),
                    title = title.trim().ifEmpty { null }
                )
                supabase.from(BackendContracts.Tables.WEEKLY_GOALS).insert(ins) { }
                recomputeForCurrentWeek()
                loadAllTimeStats()
                val rows = when (_uiState.value.scope) {
                    GoalsSummaryScope.WEEK -> fetchWeekGoals()
                    GoalsSummaryScope.ALL_TIME -> fetchAllTimeGoals()
                }
                _uiState.update { it.copy(creating = false, goals = rows) }
                onSuccess()
            }.onFailure { e ->
                val msg = e.message.orEmpty()
                val dup = msg.contains("weekly_goals", ignoreCase = true) ||
                    msg.contains("unique", ignoreCase = true) ||
                    msg.contains("duplicate", ignoreCase = true)
                _uiState.update {
                    it.copy(
                        creating = false,
                        error = if (dup) {
                            "You already have a goal for this metric this week."
                        } else {
                            e.message?.take(300) ?: e::class.java.simpleName
                        }
                    )
                }
            }
        }
    }

    fun refreshOneGoal() {
        if (!isOwnProfile) return
        viewModelScope.launch {
            _uiState.update { it.copy(refreshBusy = true) }
            runCatching {
                recomputeForCurrentWeek()
                val rows = when (_uiState.value.scope) {
                    GoalsSummaryScope.WEEK -> fetchWeekGoals()
                    GoalsSummaryScope.ALL_TIME -> fetchAllTimeGoals()
                }
                _uiState.update { it.copy(goals = rows, refreshBusy = false) }
            }.onFailure { e ->
                _uiState.update { it.copy(refreshBusy = false, error = e.message?.take(300)) }
            }
        }
    }

    fun fetchRecommendation(metric: GoalMetric) {
        if (!isOwnProfile) return
        val me = supabase.auth.currentUserOrNull()?.id ?: return
        viewModelScope.launch {
            _uiState.update { it.copy(recommendBusy = true, recommendValue = null) }
            runCatching {
                val params = buildJsonObject {
                    put("p_user_id", me)
                    put("p_metric", metric.wire)
                }
                val res = supabase.postgrest.rpc(BackendContracts.Rpc.GET_WEEKLY_GOAL_RECOMMENDATION, params) { }
                val n = runCatching {
                    val s = res.data
                    s.trim().removePrefix("[").removeSuffix("]")
                    json.parseToJsonElement(s).toString().toDoubleOrNull()?.roundToInt()
                        ?: json.parseToJsonElement(s).toString().trim().toIntOrNull()
                }.getOrNull() ?: parseRecommendationNumber(res.data) ?: 1
                _uiState.update { it.copy(recommendBusy = false, recommendValue = n) }
            }.onFailure {
                _uiState.update { it.copy(recommendBusy = false, recommendValue = 1) }
            }
        }
    }

    private fun parseRecommendationNumber(raw: String): Int? {
        val t = raw.trim()
        if (t.isEmpty() || t == "null") return null
        return t.removePrefix("\"").removeSuffix("\"").toDoubleOrNull()?.roundToInt()
    }

    suspend fun loadContributions(g: GoalRowUi): List<WorkoutSummary> = runCatching {
        val start = LocalDate.parse(g.weekStartDate.take(10))
        val startIso = start.atStartOfDay(LiftrGoalsTime.ZONE).toInstant().toString()
        val endIso = start.plusDays(7).atStartOfDay(LiftrGoalsTime.ZONE).toInstant().toString()
        val wRes = supabase.from(BackendContracts.Tables.WORKOUTS)
            .select(
                columns = Columns.raw("id, user_id, kind, title, started_at, ended_at, state, calories_kcal")
            ) {
                filter {
                    eq("user_id", g.userId)
                    gte("started_at", startIso)
                    lt("started_at", endIso)
                }
                order("started_at", Order.DESCENDING)
            }
        val ws = decodeList<WorkoutContribWire>(wRes.data)
        if (ws.isEmpty()) return@runCatching emptyList()
        val pRes = supabase.from(BackendContracts.Tables.PROFILES)
            .select(columns = Columns.raw("user_id, username, avatar_url")) {
                filter { eq("user_id", g.userId) }
                limit(1)
            }
        val prof = decodeList<ProfileContribWire>(pRes.data).firstOrNull()
        val ownerUn = prof?.username
        val ownerAv = prof?.avatarUrl
        val ids = ws.map { it.id }
        val sRes = supabase.from(BackendContracts.Tables.WORKOUT_SCORES)
            .select(columns = Columns.raw("workout_id, score")) {
                filter { isIn("workout_id", ids.map { it.toString() }) }
            }
        val scoreRows = decodeList<ScoreWire>(sRes.data)
        val byW = scoreRows.groupBy { it.workoutId }
            .mapValues { e -> e.value.sumOf { it.score } }
        ws.map { w ->
            WorkoutSummary(
                id = w.id,
                userId = w.userId,
                kind = w.kind,
                title = w.title,
                startedAt = w.startedAt,
                endedAt = w.endedAt,
                state = w.state,
                caloriesKcal = w.caloriesKcal,
                ownerUsername = ownerUn,
                ownerAvatarUrl = ownerAv,
                likeCount = 0,
                isLikedByMe = false,
                score = byW[w.id]
            )
        }
    }.getOrElse { emptyList() }

    private inline fun <reified T> decodeList(raw: String): List<T> {
        val root = json.parseToJsonElement(raw)
        return when (root) {
            is JsonArray -> root.map { json.decodeFromString<T>(it.toString()) }
            is JsonObject -> listOf(json.decodeFromString<T>(root.toString()))
            else -> emptyList()
        }
    }

    fun clearError() {
        _uiState.update { it.copy(error = null) }
    }
}

class GoalsViewModelFactory(
    private val supabase: SupabaseClient,
    private val targetUserId: String
) : ViewModelProvider.Factory {
    @Suppress("UNCHECKED_CAST")
    override fun <T : ViewModel> create(modelClass: Class<T>): T {
        if (modelClass != GoalsViewModel::class.java) error("Unknown ViewModel: ${modelClass.name}")
        return GoalsViewModel(supabase, targetUserId) as T
    }
}
