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
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

@Serializable
private data class PendingReviewWire(
    val id: Int,
    @SerialName("competition_id") val competitionId: Int = 0,
    @SerialName("workout_id") val workoutId: Int,
    @SerialName("workout_owner_id") val workoutOwnerId: String,
    val status: String = "pending",
    @SerialName("score_snapshot") val scoreSnapshot: Double? = null,
    @SerialName("calories_snapshot") val caloriesSnapshot: Double? = null,
    @SerialName("created_at") val createdAt: String? = null,
    @SerialName("updated_at") val updatedAt: String? = null,
    @SerialName("competitions") val competitionEmbed: CompetitionEmbedWire? = null
)

@Serializable
private data class CompetitionEmbedWire(
    @SerialName("user_a") val userA: String? = null,
    @SerialName("user_b") val userB: String? = null
)

data class PendingReviewRowUi(
    val id: Int,
    val workoutId: Int,
    val workoutOwnerId: String
)

data class CompetitionReviewsUiState(
    val loading: Boolean = true,
    val isRefreshing: Boolean = false,
    val actionBusy: Boolean = false,
    val error: String? = null,
    val rows: List<PendingReviewRowUi> = emptyList()
)

class CompetitionReviewsViewModel(
    private val supabase: SupabaseClient
) : ViewModel() {

    private val _ui = MutableStateFlow(CompetitionReviewsUiState())
    val uiState: StateFlow<CompetitionReviewsUiState> = _ui.asStateFlow()

    fun load(isPull: Boolean = false, silent: Boolean = false) {
        val me = supabase.auth.currentUserOrNull()?.id
        if (me == null) {
            _ui.update {
                it.copy(loading = false, isRefreshing = false, error = null, rows = emptyList())
            }
            return
        }
        viewModelScope.launch {
            if (!silent) {
                _ui.update {
                    if (isPull) {
                        it.copy(isRefreshing = true, error = null)
                    } else {
                        it.copy(loading = true, isRefreshing = false, error = null)
                    }
                }
            } else {
                _ui.update { it.copy(error = null) }
            }
            val r = runCatching {
                val selectCols =
                    "id,competition_id,workout_id,workout_owner_id,status,score_snapshot,calories_snapshot,created_at,updated_at,competitions!inner(user_a,user_b)"
                supabase.from(BackendContracts.Tables.COMPETITION_WORKOUTS)
                    .select(columns = Columns.raw(selectCols)) {
                        filter {
                            eq("status", "pending")
                            neq("workout_owner_id", me)
                        }
                    }
                    .decodeList<PendingReviewWire>()
                    .map { w ->
                        PendingReviewRowUi(
                            id = w.id,
                            workoutId = w.workoutId,
                            workoutOwnerId = w.workoutOwnerId
                        )
                    }
            }
            r.onSuccess { rows ->
                _ui.update { it.copy(loading = false, isRefreshing = false, rows = rows) }
            }
            r.onFailure { e ->
                _ui.update {
                    it.copy(
                        loading = false,
                        isRefreshing = false,
                        error = e.message?.take(400) ?: e::class.java.simpleName
                    )
                }
            }
        }
    }

    fun review(competitionWorkoutId: Int, accept: Boolean) {
        viewModelScope.launch {
            _ui.update { it.copy(actionBusy = true, error = null) }
            val r = runCatching {
                val params = buildJsonObject {
                    put("p_competition_workout_id", competitionWorkoutId)
                    put("p_accept", accept)
                }
                supabase.postgrest.rpc(BackendContracts.Rpc.REVIEW_COMPETITION_WORKOUT, params) { }
            }
            r.onSuccess {
                _ui.update { it.copy(actionBusy = false) }
                load(silent = true)
            }
            r.onFailure { e ->
                _ui.update {
                    it.copy(
                        actionBusy = false,
                        error = e.message?.take(400) ?: e::class.java.simpleName
                    )
                }
            }
        }
    }
}

class CompetitionReviewsViewModelFactory(
    private val supabase: SupabaseClient
) : ViewModelProvider.Factory {
    @Suppress("UNCHECKED_CAST")
    override fun <T : ViewModel> create(modelClass: Class<T>): T {
        if (modelClass != CompetitionReviewsViewModel::class.java) {
            error("Unknown ViewModel: ${modelClass.name}")
        }
        return CompetitionReviewsViewModel(supabase) as T
    }
}
