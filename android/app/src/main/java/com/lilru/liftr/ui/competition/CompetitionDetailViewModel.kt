package com.lilru.liftr.ui.competition

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.lilru.liftr.data.BackendContracts
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Columns
import io.github.jan.supabase.postgrest.query.Order
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.util.Locale
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
private data class CompWorkoutEntryWire(
    val id: Int,
    @SerialName("competition_id") val competitionId: Int,
    @SerialName("workout_id") val workoutId: Int,
    @SerialName("workout_owner_id") val workoutOwnerId: String,
    val status: String
)

@Serializable
private data class WorkoutLiteWire(
    val id: Int,
    @SerialName("user_id") val userId: String,
    val title: String? = null,
    val kind: String? = null,
    @SerialName("started_at") val startedAt: String,
    @SerialName("calories_kcal") val caloriesKch: Double? = null
)

@Serializable
private data class ProfileNameWire(
    @SerialName("user_id") val userId: String,
    val username: String
)

data class CompWorkoutDisplayRow(
    val entryId: Int,
    val workoutId: Int,
    val workoutOwnerId: String,
    val status: String,
    val ownerName: String,
    val titleOrKind: String,
    val startedAtIso: String
)

data class CompetitionDetailUiState(
    val loading: Boolean = true,
    val isRefreshing: Boolean = false,
    val error: String? = null,
    val rows: List<CompWorkoutDisplayRow> = emptyList()
)

class CompetitionDetailViewModel(
    private val supabase: SupabaseClient,
    private val competitionId: Int,
    private val seedProfiles: Map<String, ProfileLiteUi>
) : ViewModel() {

    private val _uiState = MutableStateFlow(CompetitionDetailUiState())
    val uiState: StateFlow<CompetitionDetailUiState> = _uiState.asStateFlow()

    fun load(isPull: Boolean = false) {
        viewModelScope.launch {
            _uiState.update {
                if (isPull) {
                    it.copy(isRefreshing = true, error = null)
                } else {
                    it.copy(loading = true, isRefreshing = false, error = null)
                }
            }
            val result = runCatching {
                val entries = supabase.from(BackendContracts.Tables.COMPETITION_WORKOUTS)
                    .select {
                        filter { eq("competition_id", competitionId) }
                        order("created_at", Order.DESCENDING)
                    }
                    .decodeList<CompWorkoutEntryWire>()

                val wids = entries.map { it.workoutId }.toSet().toList()
                val workoutsById: Map<Int, WorkoutLiteWire> = if (wids.isEmpty()) {
                    emptyMap()
                } else {
                    supabase.from(BackendContracts.Tables.WORKOUTS)
                        .select(
                            columns = Columns.raw("id,user_id,title,kind,started_at,calories_kcal")
                        ) {
                            filter { isIn("id", wids.map { it.toString() }) }
                        }
                        .decodeList<WorkoutLiteWire>()
                        .associateBy { it.id }
                }

                val ownerIds = entries.map { it.workoutOwnerId }.toSet() - seedProfiles.keys
                val fromDb: Map<String, String> = if (ownerIds.isEmpty()) {
                    emptyMap()
                } else {
                    supabase.from(BackendContracts.Tables.PROFILES)
                        .select(columns = Columns.raw("user_id,username")) {
                            filter { isIn("user_id", ownerIds.toList()) }
                        }
                        .decodeList<ProfileNameWire>()
                        .associate { it.userId to it.username }
                }
                val nameById = buildMap {
                    seedProfiles.forEach { (k, p) -> put(k, p.username) }
                    fromDb.forEach { (k, v) -> putIfAbsent(k, v) }
                }

                entries.map { e ->
                    val w = workoutsById[e.workoutId]
                    val name = w?.title?.trim().orEmpty()
                    val kind = w?.kind
                    val titleOrKind = when {
                        name.isNotEmpty() -> name
                        !kind.isNullOrBlank() -> kind.replaceFirstChar { ch ->
                            if (ch.isLowerCase()) ch.titlecase(Locale.getDefault()) else ch.toString()
                        }
                        else -> "Workout"
                    }
                    CompWorkoutDisplayRow(
                        entryId = e.id,
                        workoutId = e.workoutId,
                        workoutOwnerId = e.workoutOwnerId,
                        status = e.status,
                        ownerName = nameById[e.workoutOwnerId] ?: "User",
                        titleOrKind = titleOrKind,
                        startedAtIso = w?.startedAt.orEmpty()
                    )
                }
            }
            result.onSuccess { rowList ->
                _uiState.update {
                    it.copy(loading = false, isRefreshing = false, rows = rowList)
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
    }
}

class CompetitionDetailViewModelFactory(
    private val supabase: SupabaseClient,
    private val competitionId: Int,
    private val seedProfiles: Map<String, ProfileLiteUi>
) : ViewModelProvider.Factory {
    @Suppress("UNCHECKED_CAST")
    override fun <T : ViewModel> create(modelClass: Class<T>): T {
        if (modelClass != CompetitionDetailViewModel::class.java) {
            error("Unknown ViewModel: ${modelClass.name}")
        }
        return CompetitionDetailViewModel(supabase, competitionId, seedProfiles) as T
    }
}
