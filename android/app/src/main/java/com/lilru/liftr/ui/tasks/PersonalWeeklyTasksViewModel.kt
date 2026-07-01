package com.lilru.liftr.ui.tasks

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.lilru.liftr.data.BackendContracts
import com.lilru.liftr.ui.home.WorkoutSummary
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.query.Columns
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlin.math.roundToInt
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import org.json.JSONArray
import org.json.JSONObject

data class UserTaskDetailUi(
    val taskId: String,
    val title: String,
    val description: String,
    val category: String,
    val targetMetric: String,
    val targetValue: Double?,
    val rewardXp: Int,
    val rewardCoins: Int,
    val rewardTaskPoints: Int,
    val difficultyBand: String?,
    val status: String,
    val progressPercent: Int?,
    val progressCurrentLabel: String?,
    val progressTargetLabel: String?,
)

data class WeeklyTaskWorkoutUi(
    val workoutId: Int,
    val kind: String,
    val title: String?,
    val startedAt: String?,
    val state: String,
    val caloriesKcal: Double?,
    val contributionValue: Double?,
    val qualifies: Boolean,
    val contributionLabel: String?,
)

data class UserWeeklyTaskUi(
    val taskId: String,
    val title: String,
    val description: String,
    val category: String,
    val targetMetric: String,
    val targetValue: Double?,
    val targetSecondary: Double?,
    val rewardXp: Int,
    val rewardCoins: Int,
    val rewardTaskPoints: Int,
    val difficultyBand: String?,
    val status: String,
    val progressValue: Double?,
    val acceptedCount: Int,
    val acceptSlotsRemaining: Int,
    val refreshCount: Int,
    val freeRefreshAvailable: Boolean,
    val nextRefreshCostCoins: Int?,
    val weekEnd: String?,
) {
    val isGenerated: Boolean get() = status == "generated"
    val isAccepted: Boolean get() = status == "accepted"
    val isCompleted: Boolean get() = status == "completed"
    val isLocked: Boolean get() = isGenerated && acceptSlotsRemaining <= 0
    val canRefreshMenu: Boolean get() = refreshCount < 3

    val progressRatio: Float?
        get() {
            val target = targetValue ?: return null
            val progress = progressValue ?: return null
            if (target <= 0) return null
            return (progress / target).toFloat().coerceIn(0f, 1f)
        }

    val progressPercentInt: Int
        get() = when {
            isCompleted -> 100
            targetValue == null || targetValue <= 0 -> 0
            else -> ((progressValue ?: 0.0) / targetValue * 100.0).roundToInt().coerceIn(0, 100)
        }

    val displayProgressRatio: Float
        get() = progressPercentInt / 100f

    val showsProgressBlock: Boolean
        get() = isAccepted || isCompleted

    val progressCurrentLabel: String
        get() = WeeklyTaskProgressFormat.formatWithUnit(
            targetMetric,
            if (isCompleted) (targetValue ?: 0.0) else (progressValue ?: 0.0)
        )

    val progressTargetLabel: String
        get() = WeeklyTaskProgressFormat.formatWithUnit(targetMetric, targetValue ?: 0.0)
}

data class PersonalWeeklyTasksUiState(
    val loading: Boolean = true,
    val error: String? = null,
    val tasks: List<UserWeeklyTaskUi> = emptyList(),
    val acceptingTaskId: String? = null,
    val unacceptingTaskId: String? = null,
    val refreshingMenu: Boolean = false,
) {
    val acceptedCount: Int get() = tasks.firstOrNull()?.acceptedCount ?: 0
    val acceptSlotsRemaining: Int get() = tasks.firstOrNull()?.acceptSlotsRemaining ?: 3
    val refreshCount: Int get() = tasks.firstOrNull()?.refreshCount ?: 0
    val freeRefreshAvailable: Boolean get() = tasks.firstOrNull()?.freeRefreshAvailable ?: (refreshCount == 0)
    val nextRefreshCostCoins: Int? get() = tasks.firstOrNull()?.nextRefreshCostCoins
    val canRefreshMenu: Boolean get() = refreshCount < 3
    val allMenuTasksCompleted: Boolean get() = tasks.isNotEmpty() && tasks.all { it.isCompleted }
    val showRefreshMenu: Boolean get() = canRefreshMenu && !allMenuTasksCompleted
    val weekEnd: String? get() = tasks.firstOrNull()?.weekEnd
}

class PersonalWeeklyTasksViewModel(
    private val supabase: SupabaseClient,
) : ViewModel() {
    private val _state = MutableStateFlow(PersonalWeeklyTasksUiState())
    val state: StateFlow<PersonalWeeklyTasksUiState> = _state.asStateFlow()

    init {
        refresh()
    }

    fun refresh() {
        viewModelScope.launch {
            _state.value = _state.value.copy(loading = true, error = null)
            runCatching {
                val res = supabase.postgrest.rpc(BackendContracts.Rpc.LIST_MY_WEEKLY_TASKS_V1, buildJsonObject { }) { }
                parseList(res.data)
            }.onSuccess { tasks ->
                _state.value = PersonalWeeklyTasksUiState(loading = false, error = null, tasks = tasks)
            }.onFailure { e ->
                _state.value = PersonalWeeklyTasksUiState(
                    loading = false,
                    error = e.message?.take(300) ?: e::class.java.simpleName,
                    tasks = emptyList()
                )
            }
        }
    }

    fun accept(taskId: String) {
        viewModelScope.launch {
            _state.value = _state.value.copy(acceptingTaskId = taskId, error = null)
            val result = runCatching {
                supabase.postgrest.rpc(
                    BackendContracts.Rpc.ACCEPT_USER_TASK_V1,
                    buildJsonObject { put("p_task_id", taskId) }
                ) { }
            }
            if (result.isSuccess) {
                refresh()
            } else {
                _state.value = _state.value.copy(
                    acceptingTaskId = null,
                    error = result.exceptionOrNull()?.message?.take(300)
                )
            }
        }
    }

    fun unaccept(taskId: String) {
        viewModelScope.launch {
            _state.value = _state.value.copy(unacceptingTaskId = taskId, error = null)
            val result = runCatching {
                supabase.postgrest.rpc(
                    BackendContracts.Rpc.UNACCEPT_USER_TASK_V1,
                    buildJsonObject { put("p_task_id", taskId) }
                ) { }
            }
            if (result.isSuccess) {
                refresh()
            } else {
                _state.value = _state.value.copy(
                    unacceptingTaskId = null,
                    error = result.exceptionOrNull()?.message?.take(300)
                )
            }
        }
    }

    fun refreshMenu() {
        viewModelScope.launch {
            _state.value = _state.value.copy(refreshingMenu = true, error = null)
            val result = runCatching {
                supabase.postgrest.rpc(BackendContracts.Rpc.REFRESH_MY_WEEKLY_TASKS_V1, buildJsonObject { }) { }
            }
            if (result.isSuccess) {
                refresh()
            } else {
                val msg = result.exceptionOrNull()?.message?.lowercase().orEmpty()
                val friendly = when {
                    msg.contains("insufficient_coins") -> "Not enough coins for this refresh."
                    msg.contains("weekly_task_refresh_cap") -> "You've used all menu refreshes this week."
                    else -> result.exceptionOrNull()?.message?.take(300)
                }
                _state.value = _state.value.copy(
                    refreshingMenu = false,
                    error = friendly
                )
            }
        }
    }

    val sessionUserId: String?
        get() = supabase.auth.currentUserOrNull()?.id

    suspend fun loadTaskDetail(taskId: String): UserTaskDetailUi? = withContext(Dispatchers.IO) {
        runCatching {
            val res = supabase.postgrest.rpc(
                BackendContracts.Rpc.GET_USER_TASK_DETAIL_V1,
                buildJsonObject { put("p_task_id", taskId) }
            ) { }
            val arr = JSONArray(res.data)
            val o = arr.optJSONObject(0) ?: return@runCatching null
            UserTaskDetailUi(
                taskId = o.optString("task_id"),
                title = o.optString("title"),
                description = o.optString("description"),
                category = o.optString("category"),
                targetMetric = o.optString("target_metric"),
                targetValue = o.optNullableDouble("target_value"),
                rewardXp = o.optInt("reward_xp", 0),
                rewardCoins = o.optInt("reward_coins", 0),
                rewardTaskPoints = o.optInt("reward_task_points", 0),
                difficultyBand = o.optString("difficulty_band").takeIf { it.isNotBlank() },
                status = o.optString("status"),
                progressPercent = o.optNullableInt("progress_percent"),
                progressCurrentLabel = o.optString("progress_current_label").takeIf { it.isNotBlank() },
                progressTargetLabel = o.optString("progress_target_label").takeIf { it.isNotBlank() },
            )
        }.getOrNull()
    }

    suspend fun loadTaskWorkouts(taskId: String): List<WeeklyTaskWorkoutUi> = withContext(Dispatchers.IO) {
        runCatching {
            val res = supabase.postgrest.rpc(
                BackendContracts.Rpc.LIST_USER_TASK_WORKOUTS_V1,
                buildJsonObject { put("p_task_id", taskId) }
            ) { }
            val arr = JSONArray(res.data)
            (0 until arr.length()).mapNotNull { i ->
                val o = arr.optJSONObject(i) ?: return@mapNotNull null
                WeeklyTaskWorkoutUi(
                    workoutId = o.optInt("workout_id"),
                    kind = o.optString("kind"),
                    title = o.optString("title").takeIf { it.isNotBlank() },
                    startedAt = o.optString("started_at").takeIf { it.isNotBlank() },
                    state = o.optString("state"),
                    caloriesKcal = o.optNullableDouble("calories_kcal"),
                    contributionValue = o.optNullableDouble("contribution_value"),
                    qualifies = o.optBoolean("qualifies", false),
                    contributionLabel = o.optString("contribution_label").takeIf { it.isNotBlank() },
                )
            }
        }.getOrElse { emptyList() }
    }

    suspend fun loadTaskWorkoutSummaries(rows: List<WeeklyTaskWorkoutUi>): List<WorkoutSummary> =
        withContext(Dispatchers.IO) {
            val uid = sessionUserId ?: return@withContext emptyList()
            if (rows.isEmpty()) return@withContext emptyList()
            runCatching {
                val pRes = supabase.from(BackendContracts.Tables.PROFILES)
                    .select(columns = Columns.raw("user_id, username, avatar_url")) {
                        filter { eq("user_id", uid) }
                        limit(1)
                    }
                val prof = JSONArray(pRes.data).optJSONObject(0)
                val ownerUn = prof?.optString("username")
                val ownerAv = prof?.optString("avatar_url")
                val ids = rows.map { it.workoutId }
                val sRes = supabase.from(BackendContracts.Tables.WORKOUT_SCORES)
                    .select(columns = Columns.raw("workout_id, score")) {
                        filter { isIn("workout_id", ids.map { it.toString() }) }
                    }
                val scores = mutableMapOf<Int, Double>()
                val sArr = JSONArray(sRes.data)
                for (i in 0 until sArr.length()) {
                    val s = sArr.optJSONObject(i) ?: continue
                    val wid = s.optInt("workout_id")
                    scores[wid] = (scores[wid] ?: 0.0) + s.optDouble("score", 0.0)
                }
                rows.map { w ->
                    WorkoutSummary(
                        id = w.workoutId,
                        userId = uid,
                        kind = w.kind,
                        title = w.title,
                        startedAt = w.startedAt,
                        endedAt = null,
                        state = w.state,
                        caloriesKcal = w.caloriesKcal,
                        ownerUsername = ownerUn,
                        ownerAvatarUrl = ownerAv,
                        likeCount = 0,
                        isLikedByMe = false,
                        score = scores[w.workoutId],
                    )
                }
            }.getOrElse { emptyList() }
        }

    private fun parseList(raw: String): List<UserWeeklyTaskUi> {
        val arr: JSONArray = when {
            raw.isBlank() -> JSONArray()
            raw.trimStart().startsWith("[") -> JSONArray(raw)
            else -> JSONArray().put(JSONObject(raw))
        }
        return (0 until arr.length()).mapNotNull { i ->
            val o = arr.optJSONObject(i) ?: return@mapNotNull null
            UserWeeklyTaskUi(
                taskId = o.optString("task_id"),
                title = o.optString("title"),
                description = o.optString("description"),
                category = o.optString("category"),
                targetMetric = o.optString("target_metric"),
                targetValue = o.optNullableDouble("target_value"),
                targetSecondary = o.optNullableDouble("target_secondary"),
                rewardXp = o.optInt("reward_xp", 0),
                rewardCoins = o.optInt("reward_coins", 0),
                rewardTaskPoints = o.optInt("reward_task_points", 0),
                difficultyBand = o.optString("difficulty_band").takeIf { it.isNotBlank() },
                status = o.optString("status"),
                progressValue = o.optNullableDouble("progress_value"),
                acceptedCount = o.optInt("accepted_count", 0),
                acceptSlotsRemaining = o.optInt("accept_slots_remaining", 3),
                refreshCount = o.optInt("refresh_count", 0),
                freeRefreshAvailable = if (o.has("free_refresh_available") && !o.isNull("free_refresh_available")) {
                    o.optBoolean("free_refresh_available", false)
                } else {
                    o.optInt("refresh_count", 0) == 0
                },
                nextRefreshCostCoins = if (o.has("next_refresh_cost_coins") && !o.isNull("next_refresh_cost_coins")) {
                    o.optInt("next_refresh_cost_coins", 0)
                } else if (o.optInt("refresh_count", 0) < 3) {
                    0
                } else {
                    null
                },
                weekEnd = o.optString("week_end").takeIf { it.isNotBlank() },
            )
        }
    }

    private fun JSONObject.optNullableDouble(key: String): Double? {
        if (!has(key) || isNull(key)) return null
        return optDouble(key, Double.NaN).takeUnless { it.isNaN() }
    }

    private fun JSONObject.optNullableInt(key: String): Int? {
        if (!has(key) || isNull(key)) return null
        return optInt(key, Int.MIN_VALUE).takeUnless { it == Int.MIN_VALUE }
    }

    class Factory(private val supabase: SupabaseClient) : ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST")
        override fun <T : ViewModel> create(modelClass: Class<T>): T {
            return PersonalWeeklyTasksViewModel(supabase) as T
        }
    }
}
