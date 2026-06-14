package com.lilru.liftr.ui.achievements

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.lilru.liftr.data.BackendContracts
import com.lilru.liftr.data.CoinManager
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.postgrest
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
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import kotlin.math.min
import kotlin.math.roundToInt

data class AchievementRowUi(
    val achievementId: Int,
    val code: String,
    val title: String,
    val description: String?,
    val category: String,
    val iconUrl: String?,
    val unlockedAt: String?,
    val isUnlocked: Boolean,
    val requirementType: String? = null,
    val requirementValue: Double? = null,
    val progressCurrent: Double? = null,
    /** % of users with ≥1 published workout who unlocked this; null if backend hides small samples. */
    val communityPctUnlocked: Double? = null,
    val communitySampleSize: Int? = null,
    val isTracked: Boolean = false
) {
    val idKey: String get() = "$achievementId|$code"

    val progressFraction: Float
        get() {
            if (isUnlocked) return 1f
            val target = requirementValue ?: return 0f
            if (target <= 0) return 0f
            val cur = progressCurrent ?: return 0f
            if (cur < 0) return 0f
            return min(1.0, cur / target).toFloat()
        }

    val progressPercentInt: Int
        get() = (progressFraction * 100f).roundToInt().coerceIn(0, 100)
}

enum class AchievementLockFilter { ALL, UNLOCKED, LOCKED, TRACKED }

enum class AchievementCategoryFilter {
    ALL, GENERAL, STRENGTH, CARDIO, SPORT, SOCIAL, STREAK, RANKING, PET, COINS;

    val label: String
        get() = when (this) {
            ALL -> "All"
            GENERAL -> "General"
            STRENGTH -> "Strength"
            CARDIO -> "Cardio"
            SPORT -> "Sport"
            SOCIAL -> "Social"
            STREAK -> "Streak"
            RANKING -> "Ranking"
            PET -> "Pet"
            COINS -> "Coins"
        }
}

data class AchievementsUiState(
    val loading: Boolean = true,
    val error: String? = null,
    val items: List<AchievementRowUi> = emptyList(),
    val lockFilter: AchievementLockFilter = AchievementLockFilter.ALL,
    val category: AchievementCategoryFilter = AchievementCategoryFilter.ALL,
    val search: String = "",
    val recomputeBusy: Boolean = false,
    val trackBusy: Boolean = false,
    val trackError: String? = null
) {
    val trackedCount: Int get() = items.count { it.isTracked }

    val filtered: List<AchievementRowUi>
        get() {
            var s = items.asSequence()
            s = when (lockFilter) {
                AchievementLockFilter.ALL -> s
                AchievementLockFilter.UNLOCKED -> s.filter { it.isUnlocked }
                AchievementLockFilter.LOCKED -> s.filter { !it.isUnlocked }
                AchievementLockFilter.TRACKED -> s.filter { it.isTracked }
            }
            s = if (category == AchievementCategoryFilter.ALL) {
                s
            } else {
                s.filter { it.category.equals(category.label, ignoreCase = true) }
            }
            val q = search.trim()
            if (q.isNotEmpty()) {
                val ql = q.lowercase()
                s = s.filter {
                    it.title.lowercase().contains(ql) ||
                        (it.description?.lowercase()?.contains(ql) == true) ||
                        it.code.lowercase().contains(ql)
                }
            }
            return s.sortedWith(
                compareBy<AchievementRowUi> { !it.isUnlocked }
                    .thenBy { it.category }
                    .thenBy { it.title }
            ).toList()
        }
}

@Serializable
private data class AchievementWire(
    @SerialName("achievement_id") val achievementId: Int = 0,
    val code: String = "",
    val title: String = "",
    val description: String? = null,
    val category: String = "",
    @SerialName("icon_url") val iconUrl: String? = null,
    @SerialName("user_id") val userId: String? = null,
    @SerialName("unlocked_at") val unlockedAt: String? = null,
    @SerialName("is_unlocked") val isUnlocked: Boolean = false,
    @SerialName("requirement_type") val requirementType: String? = null,
    @SerialName("requirement_value") val requirementValue: Double? = null,
    @SerialName("progress_current") val progressCurrent: Double? = null,
    @SerialName("community_pct_unlocked") val communityPctUnlocked: Double? = null,
    @SerialName("community_sample_size") val communitySampleSize: Int? = null,
    @SerialName("is_tracked") val isTracked: Boolean = false
)

@Serializable
private data class ToggleTrackWire(
    val tracked: Boolean = false,
    @SerialName("tracked_count") val trackedCount: Int = 0
)

class AchievementsViewModel(
    private val supabase: SupabaseClient,
    private val targetUserId: String
) : ViewModel() {
    private val json = Json {
        ignoreUnknownKeys = true
        isLenient = true
        coerceInputValues = true
    }

    private val _uiState = MutableStateFlow(AchievementsUiState())
    val uiState: StateFlow<AchievementsUiState> = _uiState.asStateFlow()

    init {
        load()
    }

    fun setLockFilter(f: AchievementLockFilter) {
        _uiState.update { it.copy(lockFilter = f) }
    }

    fun setCategory(c: AchievementCategoryFilter) {
        _uiState.update { it.copy(category = c) }
    }

    fun setSearch(s: String) {
        _uiState.update { it.copy(search = s) }
    }

    fun load() {
        viewModelScope.launch {
            _uiState.update { it.copy(loading = true, error = null) }
            runCatching {
                val params = buildJsonObject { put("p_user_id", targetUserId) }
                val res = supabase.postgrest.rpc(BackendContracts.Rpc.GET_USER_ACHIEVEMENTS, params) { }
                val rows = decodeList<AchievementWire>(res.data).map { w ->
                    AchievementRowUi(
                        achievementId = w.achievementId,
                        code = w.code,
                        title = w.title,
                        description = w.description,
                        category = w.category,
                        iconUrl = w.iconUrl,
                        unlockedAt = w.unlockedAt,
                        isUnlocked = w.isUnlocked,
                        requirementType = w.requirementType,
                        requirementValue = w.requirementValue,
                        progressCurrent = w.progressCurrent,
                        communityPctUnlocked = w.communityPctUnlocked,
                        communitySampleSize = w.communitySampleSize,
                        isTracked = w.isTracked
                    )
                }
                _uiState.update { it.copy(loading = false, items = rows) }
            }.onFailure { e ->
                _uiState.update {
                    it.copy(loading = false, error = e.message?.take(300) ?: e::class.java.simpleName)
                }
            }
        }
    }

    fun recomputeAndReload() {
        viewModelScope.launch {
            _uiState.update { it.copy(recomputeBusy = true) }
            runCatching {
                val params = buildJsonObject { put("p_user_id", targetUserId) }
                supabase.postgrest.rpc(BackendContracts.Rpc.CHECK_AND_UNLOCK_ACHIEVEMENTS_FOR, params) { }
            }
            CoinManager.refreshBalanceAfterMutation(supabase, notifyIfEarned = true)
            _uiState.update { it.copy(recomputeBusy = false) }
            load()
        }
    }

    fun toggleTrack(achievementId: Int) {
        viewModelScope.launch {
            _uiState.update { it.copy(trackBusy = true, trackError = null) }
            runCatching {
                val params = buildJsonObject { put("p_achievement_id", achievementId) }
                val res = supabase.postgrest.rpc(BackendContracts.Rpc.TOGGLE_TRACKED_ACHIEVEMENT_V1, params) { }
                val payload = json.decodeFromString<ToggleTrackWire>(res.data)
                _uiState.update { st ->
                    st.copy(
                        items = st.items.map { row ->
                            if (row.achievementId != achievementId) row
                            else row.copy(isTracked = payload.tracked)
                        },
                        trackBusy = false
                    )
                }
            }.onFailure { e ->
                val msg = e.message?.lowercase().orEmpty()
                val friendly = when {
                    msg.contains("tracked_limit_reached") -> "You can track up to 5 achievements."
                    msg.contains("already_unlocked") -> "Unlocked achievements cannot be tracked."
                    else -> e.message?.take(300) ?: e::class.java.simpleName
                }
                _uiState.update { it.copy(trackBusy = false, trackError = friendly) }
            }
        }
    }

    private inline fun <reified T> decodeList(raw: String): List<T> {
        val root = json.parseToJsonElement(raw)
        return when (root) {
            is JsonArray -> root.map { json.decodeFromString<T>(it.toString()) }
            is JsonObject -> listOf(json.decodeFromString<T>(root.toString()))
            else -> emptyList()
        }
    }
}

class AchievementsViewModelFactory(
    private val supabase: SupabaseClient,
    private val targetUserId: String
) : ViewModelProvider.Factory {
    @Suppress("UNCHECKED_CAST")
    override fun <T : ViewModel> create(modelClass: Class<T>): T {
        if (modelClass != AchievementsViewModel::class.java) error("Unknown ViewModel: ${modelClass.name}")
        return AchievementsViewModel(supabase, targetUserId) as T
    }
}
