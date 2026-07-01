package com.lilru.liftr.ui.tasks

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.lilru.liftr.data.BackendContracts
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.postgrest
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import org.json.JSONArray
import org.json.JSONObject

data class WeeklyTasksHistoryStatsUi(
    val totalAccepted: Int,
    val totalCompleted: Int,
    val totalExpired: Int,
    val completionRatePercent: Int,
    val totalXpEarned: Int,
    val totalCoinsEarned: Int,
    val totalTaskPointsEarned: Int,
    val currentWeekAccepted: Int,
    val currentWeekCompleted: Int,
)

data class WeeklyTasksHistoryTaskUi(
    val taskId: String,
    val title: String,
    val category: String,
    val difficultyBand: String?,
    val completedAt: String?,
    val rewardXp: Int,
    val rewardCoins: Int,
    val rewardTaskPoints: Int,
)

data class WeeklyTasksHistoryUiState(
    val loading: Boolean = true,
    val loadingMore: Boolean = false,
    val error: String? = null,
    val stats: WeeklyTasksHistoryStatsUi? = null,
    val completedTasks: List<WeeklyTasksHistoryTaskUi> = emptyList(),
    val totalCompletedTasks: Int = 0,
    val hasMore: Boolean = false,
)

class WeeklyTasksHistoryViewModel(
    private val supabase: SupabaseClient,
) : ViewModel() {
    private val _state = MutableStateFlow(WeeklyTasksHistoryUiState())
    val state: StateFlow<WeeklyTasksHistoryUiState> = _state.asStateFlow()

    private val pageSize = 10
    private var nextOffset = 0

    init {
        refresh()
    }

    fun refresh() {
        viewModelScope.launch {
            nextOffset = 0
            _state.value = _state.value.copy(loading = true, error = null)
            runCatching {
                withContext(Dispatchers.IO) {
                    fetchPage(offset = 0)
                }
            }.onSuccess { page ->
                _state.value = WeeklyTasksHistoryUiState(
                    loading = false,
                    error = null,
                    stats = page.stats,
                    completedTasks = page.tasks,
                    totalCompletedTasks = page.total,
                    hasMore = page.hasMore,
                )
                nextOffset = page.tasks.size
            }.onFailure { e ->
                _state.value = WeeklyTasksHistoryUiState(
                    loading = false,
                    error = e.message?.take(300) ?: e::class.java.simpleName,
                )
            }
        }
    }

    fun loadMore() {
        viewModelScope.launch {
            val current = _state.value
            if (!current.hasMore || current.loadingMore) return@launch
            _state.value = current.copy(loadingMore = true, error = null)
            runCatching {
                withContext(Dispatchers.IO) {
                    fetchPage(offset = nextOffset)
                }
            }.onSuccess { page ->
                _state.value = _state.value.copy(
                    loadingMore = false,
                    stats = page.stats ?: current.stats,
                    completedTasks = current.completedTasks + page.tasks,
                    totalCompletedTasks = page.total,
                    hasMore = page.hasMore,
                )
                nextOffset += page.tasks.size
            }.onFailure { e ->
                _state.value = _state.value.copy(
                    loadingMore = false,
                    error = e.message?.take(300) ?: e::class.java.simpleName,
                )
            }
        }
    }

    private data class HistoryPage(
        val stats: WeeklyTasksHistoryStatsUi?,
        val tasks: List<WeeklyTasksHistoryTaskUi>,
        val total: Int,
        val hasMore: Boolean,
    )

    private suspend fun fetchPage(offset: Int): HistoryPage {
        val res = supabase.postgrest.rpc(
            BackendContracts.Rpc.GET_MY_WEEKLY_TASKS_HISTORY_V1,
            buildJsonObject {
                put("p_tasks_limit", pageSize)
                put("p_tasks_offset", offset)
            }
        ) { }
        return parsePayload(res.data)
    }

    private fun parsePayload(raw: String): HistoryPage {
        val root = JSONObject(raw)
        val statsObj = root.optJSONObject("stats")
        val stats = statsObj?.let {
            WeeklyTasksHistoryStatsUi(
                totalAccepted = it.optInt("total_accepted", 0),
                totalCompleted = it.optInt("total_completed", 0),
                totalExpired = it.optInt("total_expired", 0),
                completionRatePercent = it.optInt("completion_rate_percent", 0),
                totalXpEarned = it.optInt("total_xp_earned", 0),
                totalCoinsEarned = it.optInt("total_coins_earned", 0),
                totalTaskPointsEarned = it.optInt("total_task_points_earned", 0),
                currentWeekAccepted = it.optInt("current_week_accepted", 0),
                currentWeekCompleted = it.optInt("current_week_completed", 0),
            )
        }
        val tasksArr = root.optJSONArray("completed_tasks") ?: JSONArray()
        val tasks = (0 until tasksArr.length()).mapNotNull { i ->
            val t = tasksArr.optJSONObject(i) ?: return@mapNotNull null
            WeeklyTasksHistoryTaskUi(
                taskId = t.optString("task_id"),
                title = t.optString("title"),
                category = t.optString("category"),
                difficultyBand = t.optString("difficulty_band").takeIf { it.isNotBlank() },
                completedAt = t.optString("completed_at").takeIf { it.isNotBlank() },
                rewardXp = t.optInt("reward_xp", 0),
                rewardCoins = t.optInt("reward_coins", 0),
                rewardTaskPoints = t.optInt("reward_task_points", 0),
            )
        }
        return HistoryPage(
            stats = stats,
            tasks = tasks,
            total = root.optInt("total_completed_tasks", 0),
            hasMore = root.optBoolean("has_more", false),
        )
    }

    class Factory(private val supabase: SupabaseClient) : ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST")
        override fun <T : ViewModel> create(modelClass: Class<T>): T {
            return WeeklyTasksHistoryViewModel(supabase) as T
        }
    }
}
