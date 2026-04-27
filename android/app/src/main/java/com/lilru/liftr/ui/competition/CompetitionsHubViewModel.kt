package com.lilru.liftr.ui.competition

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.lilru.liftr.data.BackendContracts
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
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import java.time.Duration
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlin.comparisons.compareByDescending
import kotlin.comparisons.thenByDescending
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

enum class CompetitionsHubTab {
    Active, Pending, History
}

data class CompetitionProgressUi(
    val workoutsCount: Int = 0,
    val scoreTotal: Double = 0.0,
    val caloriesTotal: Double = 0.0
)

data class ProfileLiteUi(
    val userId: String,
    val username: String,
    val avatarUrl: String?
)

data class CompetitionGoalUi(
    val competitionId: Int,
    val timeLimitAtIso: String? = null,
    val metric: String? = null,
    val targetValue: Double? = null
)

data class CompetitionRowUi(
    val id: Int,
    val createdBy: String,
    val userA: String,
    val userB: String,
    val status: String,
    val inviteExpiresAt: String,
    val acceptedAt: String? = null,
    val finishedAt: String? = null,
    val winnerUserId: String? = null,
    val createdAt: String
)

data class CompetitionHistorySummaryUi(
    val totalHistory: Int,
    val finished: Int,
    val wins: Int,
    val losses: Int,
    val draws: Int,
    val winRate: Double,
    val mostChallengedOpponentId: String?,
    val mostChallengedOpponentName: String,
    val mostChallengedOpponentAvatar: String?,
    val bestRivalId: String?,
    val bestRivalName: String,
    val bestRivalAvatar: String?,
    val bestRivalWinRateText: String,
    val bestRivalRecordText: String,
    val favoriteMetricLabel: String,
    val avgDurationText: String
)

data class CompetitionsHubUiState(
    val tab: CompetitionsHubTab = CompetitionsHubTab.Active,
    val loading: Boolean = true,
    val isRefreshing: Boolean = false,
    val actionBusy: Boolean = false,
    val error: String? = null,
    val myUserId: String? = null,
    val contextOpponentId: String? = null,
    val competitions: List<CompetitionRowUi> = emptyList(),
    val goalsByCompId: Map<Int, CompetitionGoalUi> = emptyMap(),
    val profilesById: Map<String, ProfileLiteUi> = emptyMap(),
    val progressByCompId: Map<Int, Map<String, CompetitionProgressUi>> = emptyMap(),
    val historySummary: CompetitionHistorySummaryUi? = null
) {
    val active: List<CompetitionRowUi> get() = competitions.filter { it.status == "active" }
    val pending: List<CompetitionRowUi> get() = competitions.filter { it.status == "pending" }
    val history: List<CompetitionRowUi> get() = competitions.filter {
        it.status in setOf("finished", "declined", "cancelled", "expired")
    }
}

@Serializable
private data class CompetitionRowWire(
    val id: Int,
    @SerialName("created_by") val createdBy: String,
    @SerialName("user_a") val userA: String,
    @SerialName("user_b") val userB: String,
    val status: String,
    @SerialName("invite_expires_at") val inviteExpiresAt: String,
    @SerialName("accepted_at") val acceptedAt: String? = null,
    @SerialName("finished_at") val finishedAt: String? = null,
    @SerialName("winner_user_id") val winnerUserId: String? = null,
    @SerialName("created_at") val createdAt: String
)

@Serializable
private data class CompetitionGoalWire(
    @SerialName("competition_id") val competitionId: Int,
    @SerialName("time_limit_at") val timeLimitAt: String? = null,
    val metric: String? = null,
    @SerialName("target_value") val targetValue: Double? = null
)

@Serializable
private data class ProfileLiteWire(
    @SerialName("user_id") val userId: String,
    val username: String,
    @SerialName("avatar_url") val avatarUrl: String? = null
)

@Serializable
private data class CompWorkoutProgressWire(
    @SerialName("competition_id") val competitionId: Int,
    @SerialName("workout_owner_id") val workoutOwnerId: String,
    val status: String,
    @SerialName("score_snapshot") val scoreSnapshot: Double? = null,
    @SerialName("calories_snapshot") val caloriesSnapshot: Double? = null
)

@Serializable
private data class CompetitionBlockInsert(
    @SerialName("blocker_id") val blockerId: String,
    @SerialName("blocked_id") val blockedId: String
)

private data class CompetitionLoadResult(
    val competitions: List<CompetitionRowUi>,
    val goals: Map<Int, CompetitionGoalUi>,
    val profiles: Map<String, ProfileLiteUi>,
    val progress: Map<Int, Map<String, CompetitionProgressUi>>,
    val summary: CompetitionHistorySummaryUi
)

class CompetitionsHubViewModel(
    private val supabase: SupabaseClient,
    private val contextOpponentId: String?
) : ViewModel() {

    private val _uiState = MutableStateFlow(CompetitionsHubUiState(contextOpponentId = contextOpponentId))
    val uiState: StateFlow<CompetitionsHubUiState> = _uiState.asStateFlow()

    fun setTab(tab: CompetitionsHubTab) {
        _uiState.update { it.copy(tab = tab) }
    }

    fun refresh(isPull: Boolean = false) {
        val me = supabase.auth.currentUserOrNull()?.id ?: return
        viewModelScope.launch { loadAll(me, isPull) }
    }

    private suspend fun loadAll(me: String, isPull: Boolean = false, silent: Boolean = false) {
        if (!silent) {
            _uiState.update {
                if (isPull) {
                    it.copy(isRefreshing = true, error = null, myUserId = me)
                } else {
                    it.copy(loading = true, isRefreshing = false, error = null, myUserId = me)
                }
            }
        } else {
            _uiState.update { it.copy(error = null) }
        }
        val result = runCatching {
            expirePendingIfNeeded()
            val rows = supabase.from(BackendContracts.Tables.COMPETITIONS)
                .select {
                    filter {
                        or {
                            eq("user_a", me)
                            eq("user_b", me)
                        }
                    }
                    order("created_at", Order.DESCENDING)
                }
                .decodeList<CompetitionRowWire>()
            val uis = rows.map { it.toUi() }
            val ids = uis.map { it.id }
            val goals: Map<Int, CompetitionGoalUi> = if (ids.isEmpty()) {
                emptyMap()
            } else {
                supabase.from(BackendContracts.Tables.COMPETITION_GOALS)
                    .select {
                        filter { isIn("competition_id", ids.map { i -> i.toString() }) }
                    }
                    .decodeList<CompetitionGoalWire>()
                    .associate { g ->
                        g.competitionId to CompetitionGoalUi(
                            competitionId = g.competitionId,
                            timeLimitAtIso = g.timeLimitAt,
                            metric = g.metric,
                            targetValue = g.targetValue
                        )
                    }
            }
            val userIds = uis.flatMap { listOf(it.userA, it.userB) }.distinct()
            val profiles: Map<String, ProfileLiteUi> = if (userIds.isEmpty()) {
                emptyMap()
            } else {
                supabase.from(BackendContracts.Tables.PROFILES)
                    .select {
                        filter { isIn("user_id", userIds) }
                    }
                    .decodeList<ProfileLiteWire>()
                    .associate { w ->
                        w.userId to ProfileLiteUi(
                            userId = w.userId,
                            username = w.username,
                            avatarUrl = w.avatarUrl
                        )
                    }
            }
            val progress = fetchProgressMap(ids)
            val summary = computeHistorySummary(me, uis, goals, profiles)
            CompetitionLoadResult(uis, goals, profiles, progress, summary)
        }
        result.onSuccess { p ->
            _uiState.update {
                it.copy(
                    loading = false,
                    isRefreshing = false,
                    myUserId = it.myUserId ?: me,
                    competitions = p.competitions,
                    goalsByCompId = p.goals,
                    profilesById = p.profiles,
                    progressByCompId = p.progress,
                    historySummary = p.summary
                )
            }
        }
        result.onFailure { e ->
            _uiState.update {
                it.copy(
                    loading = false,
                    isRefreshing = false,
                    error = e.message?.take(400) ?: e::class.java.simpleName
                )
            }
        }
    }

    private suspend fun fetchProgressMap(competitionIds: List<Int>): Map<Int, Map<String, CompetitionProgressUi>> {
        if (competitionIds.isEmpty()) return emptyMap()
        val rows = supabase.from(BackendContracts.Tables.COMPETITION_WORKOUTS)
            .select(
                columns = Columns.raw(
                    "competition_id,workout_owner_id,status,score_snapshot,calories_snapshot"
                )
            ) {
                filter {
                    isIn("competition_id", competitionIds.map { it.toString() })
                    eq("status", "accepted")
                }
            }
            .decodeList<CompWorkoutProgressWire>()
        val out = mutableMapOf<Int, MutableMap<String, CompetitionProgressUi>>()
        for (r in rows) {
            val byUser = out.getOrPut(r.competitionId) { mutableMapOf() }
            var p = byUser[r.workoutOwnerId] ?: CompetitionProgressUi()
            p = p.copy(
                workoutsCount = p.workoutsCount + 1,
                scoreTotal = p.scoreTotal + (r.scoreSnapshot ?: 0.0),
                caloriesTotal = p.caloriesTotal + (r.caloriesSnapshot ?: 0.0)
            )
            byUser[r.workoutOwnerId] = p
        }
        return out
    }

    private fun computeHistorySummary(
        me: String,
        rows: List<CompetitionRowUi>,
        goals: Map<Int, CompetitionGoalUi>,
        profiles: Map<String, ProfileLiteUi>
    ): CompetitionHistorySummaryUi {
        val history = rows.filter { it.status in setOf("finished", "declined", "cancelled", "expired") }
        val finished = history.filter { it.status == "finished" }
        var wins = 0
        var losses = 0
        var draws = 0
        for (c in finished) {
            val w = c.winnerUserId
            if (w == null) {
                draws += 1
            } else if (w == me) {
                wins += 1
            } else {
                losses += 1
            }
        }
        val finishedCount = finished.size
        val winRate = if (finishedCount > 0) wins.toDouble() / finishedCount else 0.0

        val opponentCount = mutableMapOf<String, Int>()
        for (c in history) {
            val opp = if (c.userA == me) c.userB else c.userA
            opponentCount[opp] = (opponentCount[opp] ?: 0) + 1
        }
        val mostOppId = opponentCount.maxByOrNull { it.value }?.key
        val mostOppName = mostOppId?.let { profiles[it]?.username } ?: "—"
        val mostOppAvatar = mostOppId?.let { profiles[it]?.avatarUrl }

        data class RivalAgg(var w: Int = 0, var l: Int = 0, var d: Int = 0) {
            val total: Int get() = w + l + d
            val score: Double
                get() = if (total > 0) (w + 0.5 * d) / total else 0.0
        }

        val rivalAgg = mutableMapOf<String, RivalAgg>()
        for (c in finished) {
            val opp = if (c.userA == me) c.userB else c.userA
            val agg = rivalAgg.getOrPut(opp) { RivalAgg() }
            val w = c.winnerUserId
            when {
                w == null -> agg.d += 1
                w == me -> agg.w += 1
                else -> agg.l += 1
            }
        }
        val bestPair = rivalAgg.entries.maxWithOrNull(
            compareByDescending<Map.Entry<String, RivalAgg>> { it.value.score }
                .thenByDescending { it.value.total }
        )
        val bestRivalId = bestPair?.key
        val bestAgg = bestPair?.value
        val bestRivalName = bestRivalId?.let { profiles[it]?.username } ?: "—"
        val bestRivalAvatar = bestRivalId?.let { profiles[it]?.avatarUrl }
        val bestRivalWinRateText = if (bestAgg == null) {
            "—"
        } else {
            "${(bestAgg.score * 100).roundToInt()}%"
        }
        val bestRivalRecordText = if (bestAgg == null) {
            "—"
        } else {
            "${bestAgg.w}-${bestAgg.l}-${bestAgg.d}"
        }

        val metricCount = mutableMapOf<String, Int>()
        for (c in history) {
            val m = goals[c.id]?.metric ?: continue
            metricCount[m] = (metricCount[m] ?: 0) + 1
        }
        val favoriteRaw = metricCount.maxByOrNull { it.value }?.key
        val favoriteLabel = when (favoriteRaw) {
            "workouts" -> "Workouts"
            "calories" -> "Calories"
            "score" -> "Score"
            null -> "—"
            else -> favoriteRaw
        }
        val durations = finished.mapNotNull { c ->
            val end = c.finishedAt?.let { parseInstant(it) } ?: return@mapNotNull null
            val start = parseInstant(c.createdAt)
            Duration.between(start, end).seconds.toDouble()
        }
        val avgText = if (durations.isEmpty()) {
            "—"
        } else {
            formatDuration(durations.average())
        }
        return CompetitionHistorySummaryUi(
            totalHistory = history.size,
            finished = finishedCount,
            wins = wins,
            losses = losses,
            draws = draws,
            winRate = winRate,
            mostChallengedOpponentId = mostOppId,
            mostChallengedOpponentName = mostOppName,
            mostChallengedOpponentAvatar = mostOppAvatar,
            bestRivalId = bestRivalId,
            bestRivalName = bestRivalName,
            bestRivalAvatar = bestRivalAvatar,
            bestRivalWinRateText = bestRivalWinRateText,
            bestRivalRecordText = bestRivalRecordText,
            favoriteMetricLabel = favoriteLabel,
            avgDurationText = avgText
        )
    }

    private fun formatDuration(seconds: Double): String {
        val s = max(1, seconds.roundToInt())
        val days = s / 86400
        val hours = (s % 86400) / 3600
        val mins = (s % 3600) / 60
        return when {
            days > 0 -> "${days}d ${hours}h"
            hours > 0 -> "${hours}h ${mins}m"
            else -> "${max(mins, 1)}m"
        }
    }

    private suspend fun expirePendingIfNeeded() {
        val nowStr = java.time.Instant.now().toString()
        runCatching {
            supabase.from(BackendContracts.Tables.COMPETITIONS).update(
                buildJsonObject {
                    put("status", JsonPrimitive("expired"))
                    put("finished_at", JsonPrimitive(nowStr))
                }
            ) {
                filter {
                    eq("status", "pending")
                    lt("invite_expires_at", nowStr)
                }
            }
        }
    }

    fun acceptCompetition(id: Int) = runAction {
        val now = Instant.now().toString()
        supabase.from(BackendContracts.Tables.COMPETITIONS).update(
            buildJsonObject {
                put("status", JsonPrimitive("active"))
                put("accepted_at", JsonPrimitive(now))
            }
        ) {
            filter { eq("id", id) }
        }
    }

    fun declineCompetition(id: Int) = runAction {
        val now = Instant.now().toString()
        supabase.from(BackendContracts.Tables.COMPETITIONS).update(
            buildJsonObject {
                put("status", JsonPrimitive("declined"))
                put("declined_at", JsonPrimitive(now))
                put("finished_at", JsonPrimitive(now))
            }
        ) {
            filter { eq("id", id) }
        }
    }

    fun cancelCompetition(id: Int) = runAction {
        val now = Instant.now().toString()
        supabase.from(BackendContracts.Tables.COMPETITIONS).update(
            buildJsonObject {
                put("status", JsonPrimitive("cancelled"))
                put("cancelled_at", JsonPrimitive(now))
                put("finished_at", JsonPrimitive(now))
            }
        ) {
            filter { eq("id", id) }
        }
    }

    fun blockUser(opponentId: String) {
        val me = supabase.auth.currentUserOrNull()?.id ?: return
        if (opponentId == me) return
        viewModelScope.launch {
            runCatching {
                supabase.from(BackendContracts.Tables.COMPETITION_BLOCKS).upsert(
                    CompetitionBlockInsert(blockerId = me, blockedId = opponentId)
                ) {
                    onConflict = "blocker_id,blocked_id"
                }
            }
        }
    }

    private fun runAction(block: suspend () -> Unit) {
        val me = supabase.auth.currentUserOrNull()?.id ?: return
        viewModelScope.launch {
            _uiState.update { it.copy(actionBusy = true, error = null) }
            runCatching { block() }
                .onSuccess {
                    _uiState.update { it.copy(actionBusy = false) }
                    loadAll(me, silent = true)
                }
                .onFailure { e ->
                    _uiState.update {
                        it.copy(
                            actionBusy = false,
                            error = e.message?.take(400) ?: e::class.java.simpleName
                        )
                    }
                }
        }
    }

    private fun CompetitionRowWire.toUi() = CompetitionRowUi(
        id = id,
        createdBy = createdBy,
        userA = userA,
        userB = userB,
        status = status,
        inviteExpiresAt = inviteExpiresAt,
        acceptedAt = acceptedAt,
        finishedAt = finishedAt,
        winnerUserId = winnerUserId,
        createdAt = createdAt
    )

    private fun parseInstant(s: String): Instant {
        val t = s.trim()
        val a = runCatching { Instant.parse(t) }.getOrNull()
        if (a != null) return a
        if (t.length >= 10) {
            return runCatching {
                LocalDate.parse(t.substring(0, 10)).atStartOfDay(ZoneId.systemDefault()).toInstant()
            }.getOrElse { Instant.EPOCH }
        }
        return Instant.EPOCH
    }
}

class CompetitionsHubViewModelFactory(
    private val supabase: SupabaseClient,
    private val contextOpponentId: String?
) : ViewModelProvider.Factory {
    @Suppress("UNCHECKED_CAST")
    override fun <T : ViewModel> create(modelClass: Class<T>): T {
        if (modelClass != CompetitionsHubViewModel::class.java) {
            error("Unknown ViewModel: ${modelClass.name}")
        }
        return CompetitionsHubViewModel(supabase, contextOpponentId) as T
    }
}

fun formatCompetitionDateTime(iso: String): String {
    val i = runCatching { Instant.parse(iso.trim()) }.getOrNull() ?: return iso
    return DateTimeFormatter.ofPattern("MMM d, yyyy, h:mm a", Locale.getDefault())
        .format(i.atZone(ZoneId.systemDefault()))
}

fun statusLabelForDisplay(status: String): String {
    if (status.isEmpty()) return status
    return status.replaceFirstChar { c ->
        if (c.isLowerCase()) c.titlecase(Locale.getDefault()) else c.toString()
    }
}
