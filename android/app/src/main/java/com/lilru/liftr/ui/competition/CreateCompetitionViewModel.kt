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
import java.time.Instant
import java.time.temporal.ChronoUnit

data class CreateCompetitionUiState(
    val checkingExisting: Boolean = true,
    val existing: CompetitionRowUi? = null,
    val creating: Boolean = false,
    val error: String? = null
)

@Serializable
private data class CompetitionInsertPayload(
    @SerialName("created_by") val createdBy: String,
    @SerialName("user_a") val userA: String,
    @SerialName("user_b") val userB: String,
    val status: String,
    @SerialName("invite_expires_at") val inviteExpiresAt: String
)

@Serializable
private data class CompetitionGoalInsertPayload(
    @SerialName("competition_id") val competitionId: Int,
    @SerialName("time_limit_at") val timeLimitAt: String? = null,
    val metric: String? = null,
    @SerialName("target_value") val targetValue: Double? = null
)

@Serializable
private data class IdRow(val id: Int)

@Serializable
private data class CompetitionCheckWire(
    val id: Int,
    @SerialName("created_by") val createdBy: String,
    @SerialName("user_a") val userA: String,
    @SerialName("user_b") val userB: String,
    val status: String,
    @SerialName("invite_expires_at") val inviteExpiresAt: String,
    @SerialName("accepted_at") val acceptedAt: String? = null,
    @SerialName("declined_at") val declinedAt: String? = null,
    @SerialName("cancelled_at") val cancelledAt: String? = null,
    @SerialName("finished_at") val finishedAt: String? = null,
    @SerialName("winner_user_id") val winnerUserId: String? = null,
    @SerialName("created_at") val createdAt: String,
    @SerialName("updated_at") val updatedAt: String? = null
)

class CreateCompetitionViewModel(
    private val supabase: SupabaseClient,
    private val opponentUserId: String
) : ViewModel() {

    private val _ui = MutableStateFlow(CreateCompetitionUiState())
    val uiState: StateFlow<CreateCompetitionUiState> = _ui.asStateFlow()

    init {
        checkExisting()
    }

    fun checkExisting() {
        val me = supabase.auth.currentUserOrNull()?.id ?: return
        viewModelScope.launch {
            _ui.update { it.copy(checkingExisting = true, error = null) }
            val r = runCatching {
                val rows = supabase.from(BackendContracts.Tables.COMPETITIONS)
                    .select {
                        filter {
                            isIn("status", listOf("active", "pending"))
                            or {
                                and {
                                    eq("user_a", me)
                                    eq("user_b", opponentUserId)
                                }
                                and {
                                    eq("user_a", opponentUserId)
                                    eq("user_b", me)
                                }
                            }
                        }
                        order("created_at", Order.DESCENDING)
                        limit(1)
                    }
                    .decodeList<CompetitionCheckWire>()
                rows.firstOrNull()?.toUi()
            }
            r.onSuccess { ex ->
                _ui.update { it.copy(checkingExisting = false, existing = ex) }
            }
            r.onFailure {
                _ui.update { it.copy(checkingExisting = false, existing = null) }
            }
        }
    }

    fun create(
        includeTimeLimit: Boolean,
        timeLimitDays: Int,
        includePerformanceGoal: Boolean,
        metric: String,
        targetText: String
    ) {
        val me = supabase.auth.currentUserOrNull()?.id ?: return
        if (!includeTimeLimit && !includePerformanceGoal) return
        viewModelScope.launch {
            _ui.update { it.copy(creating = true, error = null) }
            val result = runCatching {
                val now = Instant.now()
                val inviteExpires = now.plus(48, ChronoUnit.HOURS).toString()
                val compIns = CompetitionInsertPayload(
                    createdBy = me,
                    userA = me,
                    userB = opponentUserId,
                    status = "pending",
                    inviteExpiresAt = inviteExpires
                )
                val res = supabase.from(BackendContracts.Tables.COMPETITIONS).insert(compIns) {
                    select(Columns.raw("id"))
                }
                val compId = res.decodeList<IdRow>().firstOrNull()?.id
                    ?: error("No id returned from competitions insert")
                val timeLimitAt: String? = if (includeTimeLimit) {
                    now.plus(timeLimitDays.toLong(), ChronoUnit.DAYS).toString()
                } else {
                    null
                }
                val targetValue: Double? = if (includePerformanceGoal) {
                    val t = targetText.replace(",", ".").trim()
                    t.toDoubleOrNull() ?: error("Invalid target")
                } else {
                    null
                }
                val metricVal: String? = if (includePerformanceGoal) metric else null
                if (includePerformanceGoal) {
                    require((targetValue ?: 0.0) > 0) { "Target must be positive" }
                }
                val goalIns = CompetitionGoalInsertPayload(
                    competitionId = compId,
                    timeLimitAt = timeLimitAt,
                    metric = metricVal,
                    targetValue = targetValue
                )
                supabase.from(BackendContracts.Tables.COMPETITION_GOALS).insert(goalIns) { }
            }
            result.onSuccess {
                _ui.update { it.copy(creating = false) }
            }
            result.onFailure { e ->
                val msg = e.message.orEmpty()
                _ui.update {
                    it.copy(
                        creating = false,
                        error = when {
                            msg.contains("ux_competitions_active_pair", ignoreCase = true) ||
                                msg.contains("duplicate key", ignoreCase = true) -> {
                                "You already have an active competition with this user. Challenge someone else to start a new one."
                            }
                            else -> e.message?.take(400) ?: e::class.java.simpleName
                        }
                    )
                }
                if (msg.contains("ux_competitions_active_pair", ignoreCase = true) ||
                    msg.contains("duplicate key", ignoreCase = true)
                ) {
                    checkExisting()
                }
            }
        }
    }

    private fun CompetitionCheckWire.toUi() = CompetitionRowUi(
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
}

class CreateCompetitionViewModelFactory(
    private val supabase: SupabaseClient,
    private val opponentUserId: String
) : ViewModelProvider.Factory {
    @Suppress("UNCHECKED_CAST")
    override fun <T : ViewModel> create(modelClass: Class<T>): T {
        if (modelClass != CreateCompetitionViewModel::class.java) {
            error("Unknown ViewModel: ${modelClass.name}")
        }
        return CreateCompetitionViewModel(supabase, opponentUserId) as T
    }
}
