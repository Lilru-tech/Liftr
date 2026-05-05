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
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

internal fun friendlyWeeklyChallengeLoadError(e: Throwable): String {
    val msg = e.message ?: return e::class.java.simpleName
    return if (msg.contains("read-only transaction", ignoreCase = true)) {
        "Couldn’t load challenges. Redeploy the latest weekly-challenges SQL (RPCs must be VOLATILE), then try again."
    } else {
        msg.take(300)
    }
}

private fun JSONObject.optNullableString(key: String): String? {
    if (!has(key) || isNull(key)) return null
    return optString(key).takeIf { it.isNotEmpty() }
}

private fun JSONObject.optNullableDouble(key: String): Double? {
    if (!has(key) || isNull(key)) return null
    return optDouble(key, Double.NaN).takeUnless { it.isNaN() }
}

data class WeeklyChallengeListRowUi(
    val instanceId: String,
    val templateCode: String,
    val title: String,
    val description: String,
    val cadence: String,
    val maxWinners: Int,
    val claimsCount: Long,
    /** ISO-8601 end instant from API; format in UI for "does not expire" vs date. */
    val periodEndIso: String,
    val challengeCategory: String?,
    val metricKind: String?,
    val viewerClaimed: Boolean,
    val viewerRank: Int?,
) {
    fun resolvedCategory(): String {
        val c = challengeCategory?.trim()?.lowercase()
        if (!c.isNullOrEmpty()) return c
        return when (metricKind?.lowercase()) {
            "cumulative_cardio_km", "cardio_session_pace_gate" -> "cardio"
            "cumulative_sport_sessions" -> "sport"
            else -> "strength"
        }
    }
}

data class WeeklyChallengesUiState(
    val loading: Boolean = true,
    val error: String? = null,
    val items: List<WeeklyChallengeListRowUi> = emptyList(),
)

class WeeklyChallengesViewModel(
    private val supabase: SupabaseClient,
) : ViewModel() {
    private val _state = MutableStateFlow(WeeklyChallengesUiState())
    val state: StateFlow<WeeklyChallengesUiState> = _state.asStateFlow()

    init {
        refresh()
    }

    fun refresh() {
        viewModelScope.launch {
            _state.value = _state.value.copy(loading = true, error = null)
            runCatching {
                val res = supabase.postgrest.rpc(
                    BackendContracts.Rpc.LIST_ACTIVE_CHALLENGES_V1,
                    buildJsonObject { }
                ) { }
                parseList(res.data)
            }.onSuccess { items ->
                _state.value = WeeklyChallengesUiState(loading = false, error = null, items = items)
            }.onFailure { e ->
                _state.value = WeeklyChallengesUiState(
                    loading = false,
                    error = friendlyWeeklyChallengeLoadError(e),
                    items = emptyList()
                )
            }
        }
    }

    private fun parseList(raw: String): List<WeeklyChallengeListRowUi> {
        val arr: JSONArray = when {
            raw.isBlank() -> JSONArray()
            raw.trimStart().startsWith("[") -> JSONArray(raw)
            else -> JSONArray().put(JSONObject(raw))
        }
        return (0 until arr.length()).mapNotNull { i ->
            val o = arr.optJSONObject(i) ?: return@mapNotNull null
            WeeklyChallengeListRowUi(
                instanceId = o.optString("instance_id"),
                templateCode = o.optString("template_code"),
                title = o.optString("title"),
                description = o.optString("description"),
                cadence = o.optString("cadence"),
                maxWinners = o.optInt("max_winners", 1),
                claimsCount = o.optLong("claims_count", 0L),
                periodEndIso = o.optString("period_end"),
                challengeCategory = o.optNullableString("challenge_category"),
                metricKind = o.optNullableString("metric_kind"),
                viewerClaimed = o.has("viewer_claimed") && !o.isNull("viewer_claimed") && o.optBoolean("viewer_claimed", false),
                viewerRank = if (o.has("viewer_rank") && !o.isNull("viewer_rank")) {
                    o.optInt("viewer_rank").takeIf { it > 0 }
                } else {
                    null
                },
            ).takeIf { it.instanceId.isNotEmpty() }
        }
    }

}

class WeeklyChallengesViewModelFactory(
    private val supabase: SupabaseClient,
) : ViewModelProvider.Factory {
    @Suppress("UNCHECKED_CAST")
    override fun <T : ViewModel> create(modelClass: Class<T>): T {
        if (modelClass != WeeklyChallengesViewModel::class.java) {
            error("Unknown ViewModel: ${modelClass.name}")
        }
        return WeeklyChallengesViewModel(supabase) as T
    }
}

data class ChallengeDetailUi(
    val instanceId: String,
    val title: String,
    val description: String,
    val cadence: String,
    val maxWinners: Int,
    val claimsCount: Long,
    val viewerRank: Int?,
    val viewerClaimed: Boolean,
    val metricKind: String?,
)

data class ChallengeLeaderRowUi(
    val rank: Int,
    val userId: String,
    val username: String?,
    val avatarUrl: String?,
    val workoutId: Long?,
)

data class ChallengeDetailScreenState(
    val loading: Boolean = true,
    val error: String? = null,
    val detail: ChallengeDetailUi? = null,
    val leaderboard: List<ChallengeLeaderRowUi> = emptyList(),
    val progressLine: String? = null,
)

class ChallengeWeeklyDetailViewModel(
    private val supabase: SupabaseClient,
    private val instanceId: UUID,
) : ViewModel() {
    private val _state = MutableStateFlow(ChallengeDetailScreenState())
    val state: StateFlow<ChallengeDetailScreenState> = _state.asStateFlow()

    init {
        load()
    }

    fun load() {
        viewModelScope.launch {
            _state.value = ChallengeDetailScreenState(loading = true, error = null)
            runCatching {
                val idStr = instanceId.toString()
                val dParams = buildJsonObject { put("p_instance_id", idStr) }
                val dRes = supabase.postgrest.rpc(
                    BackendContracts.Rpc.GET_CHALLENGE_INSTANCE_DETAIL_V1,
                    dParams
                ) { }
                val detail = parseDetail(dRes.data) ?: error("empty detail")

                val lParams = buildJsonObject {
                    put("p_instance_id", idStr)
                    put("p_limit", 20)
                }
                val lRes = supabase.postgrest.rpc(
                    BackendContracts.Rpc.GET_CHALLENGE_INSTANCE_LEADERBOARD_V1,
                    lParams
                ) { }
                val lb = parseLeaderboard(lRes.data)

                val pRes = supabase.postgrest.rpc(
                    BackendContracts.Rpc.GET_CHALLENGE_MY_PROGRESS_V1,
                    dParams
                ) { }
                val progressLine = parseProgressLine(pRes.data, detail.metricKind)

                ChallengeDetailScreenState(
                    loading = false,
                    detail = detail,
                    leaderboard = lb,
                    progressLine = progressLine,
                )
            }.onSuccess { st ->
                _state.value = st
            }.onFailure { e ->
                _state.value = ChallengeDetailScreenState(
                    loading = false,
                    error = friendlyWeeklyChallengeLoadError(e),
                )
            }
        }
    }

    private fun parseDetail(raw: String): ChallengeDetailUi? {
        val arr: JSONArray = when {
            raw.isBlank() -> return null
            raw.trimStart().startsWith("[") -> JSONArray(raw)
            else -> JSONArray().put(JSONObject(raw))
        }
        if (arr.length() == 0) return null
        val o = arr.getJSONObject(0)
        return ChallengeDetailUi(
            instanceId = o.optString("instance_id"),
            title = o.optString("title"),
            description = o.optString("description"),
            cadence = o.optString("cadence"),
            maxWinners = o.optInt("max_winners", 1),
            claimsCount = o.optLong("claims_count", 0L),
            viewerRank = if (o.isNull("viewer_rank")) null else o.optInt("viewer_rank"),
            viewerClaimed = o.optBoolean("viewer_claimed", false),
            metricKind = o.optNullableString("metric_kind"),
        )
    }

    private fun parseLeaderboard(raw: String): List<ChallengeLeaderRowUi> {
        val arr: JSONArray = when {
            raw.isBlank() -> JSONArray()
            raw.trimStart().startsWith("[") -> JSONArray(raw)
            else -> JSONArray().put(JSONObject(raw))
        }
        return (0 until arr.length()).mapNotNull { i ->
            val o = arr.optJSONObject(i) ?: return@mapNotNull null
            ChallengeLeaderRowUi(
                rank = o.optInt("rank", i + 1),
                userId = o.optString("user_id"),
                username = o.optNullableString("username"),
                avatarUrl = o.optNullableString("avatar_url"),
                workoutId = if (o.isNull("workout_id")) null else o.optLong("workout_id"),
            )
        }
    }

    private fun parseProgressLine(raw: String, metricKind: String?): String? {
        val arr: JSONArray = when {
            raw.isBlank() -> return null
            raw.trimStart().startsWith("[") -> JSONArray(raw)
            else -> JSONArray().put(JSONObject(raw))
        }
        if (arr.length() == 0) return null
        val o = arr.getJSONObject(0)
        val mk = metricKind ?: o.optNullableString("metric_kind") ?: return null
        val pv = o.optDouble("progress_value", 0.0)
        val tv = o.optDouble("target_value", 0.0)
        val sec = o.optNullableDouble("secondary_cap")
        return when (mk) {
            "cumulative_cardio_km" -> String.format("%.1f / %.0f km", pv, tv)
            "single_set_max_kg" -> String.format("%.0f / %.0f kg (best set)", pv, tv)
            "cardio_session_pace_gate" -> {
                val capMin = ((sec ?: 3600.0).toInt()) / 60
                String.format("%.1f km (goal ≥ %.0f km in ≤ %d min)", pv, tv, capMin)
            }
            "cumulative_sport_sessions" -> String.format("%.0f / %.0f sport workouts", pv, tv)
            "cumulative_strength_workouts" -> String.format("%.0f / %.0f strength workouts", pv, tv)
            "cumulative_strength_reps" -> String.format("%.0f / %.0f reps", pv, tv)
            "cumulative_strength_sets" -> String.format("%.0f / %.0f sets", pv, tv)
            "cumulative_strength_volume_kg" -> String.format("%.0f / %.0f kg volume", pv, tv)
            "single_set_max_reps" -> String.format("%.0f / %.0f reps (best set)", pv, tv)
            "strength_workouts_touching_muscle" -> String.format("%.0f / %.0f focused workouts", pv, tv)
            else -> null
        }
    }
}

class ChallengeWeeklyDetailViewModelFactory(
    private val supabase: SupabaseClient,
    private val instanceId: UUID,
) : ViewModelProvider.Factory {
    @Suppress("UNCHECKED_CAST")
    override fun <T : ViewModel> create(modelClass: Class<T>): T {
        if (modelClass != ChallengeWeeklyDetailViewModel::class.java) {
            error("Unknown ViewModel: ${modelClass.name}")
        }
        return ChallengeWeeklyDetailViewModel(supabase, instanceId) as T
    }
}
