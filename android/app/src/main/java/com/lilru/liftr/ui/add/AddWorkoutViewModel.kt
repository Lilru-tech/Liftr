package com.lilru.liftr.ui.add

import android.app.Application
import android.util.Log
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.ViewModel
import com.lilru.liftr.R
import com.lilru.liftr.ui.AppSnackbar
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.lilru.liftr.competition.submitWorkoutToCompetitionIfActive
import com.lilru.liftr.data.BackendContracts
import com.lilru.liftr.hyrox.HyroxExerciseFormatting
import com.lilru.liftr.ui.add.duplicate.DuplicateWorkoutPayload
import com.lilru.liftr.ui.add.recommendation.ExerciseForRecommendation
import com.lilru.liftr.ui.add.recommendation.RecommendationDataSource
import com.lilru.liftr.ui.add.recommendation.StrengthRecommendationExerciseResult
import com.lilru.liftr.ui.add.recommendation.StrengthSuggestionMode
import com.lilru.liftr.ui.add.recommendation.WorkoutRecommendationEngine
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Columns
import io.github.jan.supabase.postgrest.query.Order
import java.time.Instant
import java.util.UUID
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.longOrNull
import kotlinx.serialization.json.put
import org.json.JSONArray
import org.json.JSONObject

@Serializable
data class ExerciseLite(
    val id: Long,
    val name: String,
    @SerialName("name_es") val nameEs: String? = null,
    @SerialName("name_en") val nameEn: String? = null,
    val category: String? = null,
    @SerialName("muscle_primary") val musclePrimary: String? = null,
    val equipment: String? = null
)

enum class ExercisePickerSortMode {
    ALPHABETIC,
    MOST_USED,
    FAVORITES,
    RECENT
}

data class AddWorkoutUiState(
    val loadingExercises: Boolean = true,
    val loadingFollowees: Boolean = true,
    val loadingRoutines: Boolean = true,
    val creating: Boolean = false,
    val savingRoutine: Boolean = false,
    val applyingRoutine: Boolean = false,
    val managingRoutines: Boolean = false,
    val exercises: List<ExerciseLite> = emptyList(),
    val followees: List<ProfileLite> = emptyList(),
    val routineFolders: List<RoutineFolderUi> = emptyList(),
    val routines: List<StrengthRoutineUi> = emptyList(),
    val selectedParticipantIds: Set<String> = emptySet(),
    val perPersonStrength: Boolean = false,
    val currentUserId: String? = null,
    val activeLaneUserId: String? = null,
    val laneExercisesByUser: Map<String, List<StrengthExerciseDraft>> = emptyMap(),
    val selectedExercises: List<StrengthExerciseDraft> = emptyList(),
    val favoriteExerciseIds: Set<Long> = emptySet(),
    val exercisePickerSortMode: ExercisePickerSortMode = ExercisePickerSortMode.ALPHABETIC,
    val message: String? = null,
    val error: String? = null,
    /**
     * Tras crear, el Add puede abrir [MainOverlay.WorkoutDetail] para inicio/ cuenta atrás
     * como en iOS; se consume en [AddWorkoutTabScreen].
     */
    val pendingOpenWorkoutId: Int? = null,
    /**
     * Tras crear un entreno (publicado o planificado): [AddWorkoutTabScreen] pide al shell ir a Home
     * y refrescar el feed.
     */
    val postPublishHomeNonce: Int = 0
)

data class RoutineFolderUi(
    val id: Long,
    val name: String,
    val sortOrder: Int
)

data class StrengthRoutineUi(
    val id: Long,
    val name: String,
    val folderId: Long?,
    val sortOrder: Int,
    val exerciseCount: Int,
    val updatedAtIso: String? = null
)

@Serializable
data class FollowEdge(
    @SerialName("followee_id") val followeeId: String? = null
)

@Serializable
data class ProfileLite(
    @SerialName("user_id") val userId: String,
    val username: String? = null,
    @SerialName("avatar_url") val avatarUrl: String? = null
)

@Serializable
private data class RoutineFolderRow(
    val id: Long,
    val name: String,
    @SerialName("sort_order") val sortOrder: Int = 0
)

@Serializable
private data class RoutineRow(
    val id: Long,
    val name: String,
    @SerialName("folder_id") val folderId: Long? = null,
    @SerialName("sort_order") val sortOrder: Int = 0,
    @SerialName("updated_at") val updatedAt: String? = null
)

@Serializable
private data class RoutineExerciseRow(
    val id: Long,
    @SerialName("routine_id") val routineId: Long,
    @SerialName("exercise_id") val exerciseId: Long,
    @SerialName("order_index") val orderIndex: Int = 1,
    val notes: String? = null,
    @SerialName("custom_name") val customName: String? = null
)

/** Solo `id` + `routine_id` (p. ej. contar ejercicios por rutina) — no mezclar con [RoutineExerciseRow]. */
@Serializable
private data class RoutineExerciseIdRoutinePair(
    val id: Long,
    @SerialName("routine_id") val routineId: Long
)

@Serializable
private data class RoutineSetRow(
    @SerialName("routine_exercise_id") val routineExerciseId: Long,
    @SerialName("set_number") val setNumber: Int = 1,
    val reps: Int? = null,
    @SerialName("weight_kg") val weightKg: Double? = null,
    val rpe: Double? = null,
    @SerialName("rest_sec") val restSec: Int? = null,
    val notes: String? = null
)

data class StrengthSetDraft(
    val id: String = UUID.randomUUID().toString(),
    /** Número de set mostrado y enviado al backend (1…99), como el stepper de iOS. No implica “filas” extra. */
    val setNumber: Int = 1,
    val repsText: String = "8",
    val weightText: String = "",
    val rpeText: String = "",
    val restSecText: String = "",
    val notes: String = ""
)

data class StrengthExerciseDraft(
    val id: String = UUID.randomUUID().toString(),
    /**
     * Fila existente de [workout_exercises] al editar desde [com.lilru.liftr.ui.home.WorkoutDetailScreen];
     * `null` en el flujo Add puro o ejercicio nuevo aún no persistido.
     */
    val workoutExerciseId: Int? = null,
    /** `null` until the user picks an exercise from the catalog (matches iOS empty row). */
    val exerciseId: Long? = null,
    val exerciseName: String = "",
    val customName: String = "",
    val notes: String = "",
    val sets: List<StrengthSetDraft> = listOf(StrengthSetDraft())
)

enum class AddWorkoutKind { STRENGTH, CARDIO, SPORT }

enum class AddWorkoutState { PUBLISHED, PLANNED }
enum class AddWorkoutIntensity(val wire: String) {
    EASY("easy"),
    MODERATE("moderate"),
    HARD("hard"),
    MAX("max")
}

enum class AddCardioActivity(val wire: String) {
    RUN("run"),
    WALK("walk"),
    HIKE("hike"),
    TREADMILL("treadmill"),
    BIKE("bike"),
    E_BIKE("e_bike"),
    MTB("mtb"),
    INDOOR_CYCLING("indoor_cycling"),
    ROWERG("rowerg"),
    SWIM_POOL("swim_pool"),
    SWIM_OPEN_WATER("swim_open_water")

    ;

    val showsElevation: Boolean
        get() = this !in setOf(SWIM_POOL, SWIM_OPEN_WATER, ROWERG, INDOOR_CYCLING, TREADMILL)
    val showsIncline: Boolean
        get() = this == TREADMILL
    val showsCadenceRpm: Boolean
        get() = this in setOf(INDOOR_CYCLING, BIKE, E_BIKE, MTB, ROWERG)
    val showsWatts: Boolean
        get() = this in setOf(INDOOR_CYCLING, ROWERG, BIKE, MTB)
    val showsSplit500m: Boolean
        get() = this == ROWERG
    val showsSwimFields: Boolean
        get() = this == SWIM_POOL
    val showsKmPaceSplits: Boolean
        get() = this !in setOf(SWIM_POOL, SWIM_OPEN_WATER, ROWERG)
}

enum class AddSportType(val wire: String) {
    PADEL("padel"),
    TENNIS("tennis"),
    FOOTBALL("football"),
    BASKETBALL("basketball"),
    BADMINTON("badminton"),
    SQUASH("squash"),
    TABLE_TENNIS("table_tennis"),
    VOLLEYBALL("volleyball"),
    HANDBALL("handball"),
    HOCKEY("hockey"),
    RUGBY("rugby"),
    HYROX("hyrox"),
    SKI("ski")
}

enum class AddMatchResult(val wire: String) {
    WIN("win"),
    LOSS("loss"),
    DRAW("draw"),
    UNFINISHED("unfinished"),
    FORFEIT("forfeit")
}

enum class AddFootballPosition(val wire: String) {
    GOALKEEPER("goalkeeper"),
    DEFENDER("defender"),
    MIDFIELDER("midfielder"),
    FORWARD("forward")
}

enum class AddRacketMode(val wire: String) {
    SINGLES("singles"),
    DOUBLES("doubles"),
    MIXED_DOUBLES("mixed_doubles")
}

enum class AddRacketFormat(val wire: String) {
    BEST_OF_3("best_of_3"),
    BEST_OF_5("best_of_5")
}

class AddWorkoutViewModel(
    private val supabase: SupabaseClient,
    application: Application
) : AndroidViewModel(application) {
    private companion object {
        const val TAG = "AddWorkoutVM"
    }

    private fun strengthSuccessMessage(perPerson: Boolean, addState: AddWorkoutState): String {
        val r = getApplication<Application>().resources
        return when {
            perPerson && addState == AddWorkoutState.PUBLISHED ->
                r.getString(R.string.add_strength_success_squad_published)
            perPerson && addState == AddWorkoutState.PLANNED ->
                r.getString(R.string.add_strength_success_squad_planned)
            addState == AddWorkoutState.PUBLISHED ->
                r.getString(R.string.add_strength_success_published)
            else ->
                r.getString(R.string.add_strength_success_planned)
        }
    }

    /**
     * Banner de éxito + volver a Home (nonce) sin abrir detalle; igual para publicado y planificado.
     */
    private fun onWorkoutCreatedUi(message: String) {
        AppSnackbar.showSuccess(message)
        _uiState.value = _uiState.value.copy(
            creating = false,
            message = null,
            error = null,
            pendingOpenWorkoutId = null,
            postPublishHomeNonce = _uiState.value.postPublishHomeNonce + 1
        )
    }
    private val json = Json { ignoreUnknownKeys = true }

    private val recommendationEngine = WorkoutRecommendationEngine(supabase, json)

    private val _uiState = MutableStateFlow(AddWorkoutUiState())
    val uiState: StateFlow<AddWorkoutUiState> = _uiState.asStateFlow()

    init {
        val me = supabase.auth.currentUserOrNull()?.id
        _uiState.value = _uiState.value.copy(
            currentUserId = me,
            // One empty strength row like iOS [EditableExercise()]
            selectedExercises = listOf(StrengthExerciseDraft())
        )
        loadExercises()
        loadFollowees()
        loadStrengthRoutines()
    }

    /**
     * iOS: aplica [DuplicateWorkoutPayload] tras "Duplicate" en el detalle (fuerza, participantes, etc.).
     */
    fun applyDuplicateFromDetail(payload: DuplicateWorkoutPayload) {
        _uiState.value = _uiState.value.copy(
            selectedExercises = payload.strengthExercises,
            selectedParticipantIds = payload.selectedParticipantIds,
            perPersonStrength = false,
            activeLaneUserId = null,
            laneExercisesByUser = emptyMap(),
            error = null,
            message = "Form filled from workout duplicate. Review and save."
        )
    }

    /**
     * Sets the exercise for a row (from the picker). Same movement may appear more than once.
     */
    fun setExerciseOnDraft(draftId: String, ex: ExerciseLite, languageCode: String = "es") {
        val name = when (languageCode) {
            "en" -> ex.nameEn ?: ex.nameEs ?: ex.name
            else -> ex.nameEs ?: ex.nameEn ?: ex.name
        }
        updateActiveExercises { list ->
            list.map { row ->
                if (row.id == draftId) {
                    row.copy(
                        exerciseId = ex.id,
                        exerciseName = name
                    )
                } else {
                    row
                }
            }
        }
    }

    fun addBlankStrengthExercise() {
        updateActiveExercises { it + StrengthExerciseDraft() }
    }

    @Deprecated("Use setExerciseOnDraft or addBlankStrengthExercise")
    fun addExercise(ex: ExerciseLite) {
        val name = ex.nameEs ?: ex.nameEn ?: ex.name
        updateActiveExercises { list -> list + StrengthExerciseDraft(exerciseId = ex.id, exerciseName = name) }
    }

    fun clearAllStrengthExercises() {
        updateActiveExercises { listOf(StrengthExerciseDraft()) }
    }

    fun removeExercise(exerciseDraftId: String) {
        updateActiveExercises { list ->
            val next = list.filterNot { it.id == exerciseDraftId }
            if (next.isEmpty()) {
                listOf(StrengthExerciseDraft())
            } else {
                next
            }
        }
    }

    fun moveExerciseUp(exerciseDraftId: String) {
        updateActiveExercises { current ->
            val mutable = current.toMutableList()
            val index = mutable.indexOfFirst { it.id == exerciseDraftId }
            if (index <= 0) return@updateActiveExercises current
            val item = mutable.removeAt(index)
            mutable.add(index - 1, item)
            mutable
        }
    }

    fun moveExerciseDown(exerciseDraftId: String) {
        updateActiveExercises { current ->
            val mutable = current.toMutableList()
            val index = mutable.indexOfFirst { it.id == exerciseDraftId }
            if (index == -1 || index >= mutable.lastIndex) return@updateActiveExercises current
            val item = mutable.removeAt(index)
            mutable.add(index + 1, item)
            mutable
        }
    }

    fun addSet(exerciseDraftId: String) {
        updateActiveExercises { list ->
            list.map { ex ->
                if (ex.id == exerciseDraftId) {
                    ex.copy(sets = ex.sets + StrengthSetDraft(setNumber = 1))
                } else {
                    ex
                }
            }
        }
    }

    /**
     * Ajusta el número de set (1…99) de esta fila, sin añadir filas — como el stepper de [StrengthSetRowEditor] en iOS.
     */
    fun bumpSetNumber(exerciseDraftId: String, setDraftId: String, delta: Int) {
        if (delta == 0) return
        updateActiveExercises { list ->
            list.map { ex ->
                if (ex.id != exerciseDraftId) return@map ex
                ex.copy(
                    sets = ex.sets.map { set ->
                        if (set.id != setDraftId) {
                            return@map set
                        }
                        set.copy(
                            setNumber = (set.setNumber + delta).coerceIn(1, 99)
                        )
                    }
                )
            }
        }
    }

    fun removeSet(exerciseDraftId: String, setDraftId: String) {
        updateActiveExercises { list ->
            list.map { ex ->
                if (ex.id != exerciseDraftId) return@map ex
                val nextSets = ex.sets.filterNot { it.id == setDraftId }
                ex.copy(sets = if (nextSets.isEmpty()) listOf(StrengthSetDraft()) else nextSets)
            }
        }
    }

    fun updateSetReps(exerciseDraftId: String, setDraftId: String, repsText: String) {
        updateActiveExercises { list ->
            list.map { ex ->
                if (ex.id != exerciseDraftId) return@map ex
                ex.copy(
                    sets = ex.sets.map { set ->
                        if (set.id == setDraftId) set.copy(repsText = repsText) else set
                    }
                )
            }
        }
    }

    fun updateSetWeight(exerciseDraftId: String, setDraftId: String, weightText: String) {
        updateActiveExercises { list ->
            list.map { ex ->
                if (ex.id != exerciseDraftId) return@map ex
                ex.copy(
                    sets = ex.sets.map { set ->
                        if (set.id == setDraftId) set.copy(weightText = weightText) else set
                    }
                )
            }
        }
    }

    fun updateExerciseCustomName(exerciseDraftId: String, customName: String) {
        updateActiveExercises { list ->
            list.map { ex ->
                if (ex.id == exerciseDraftId) ex.copy(customName = customName) else ex
            }
        }
    }

    fun updateExerciseNotes(exerciseDraftId: String, notes: String) {
        updateActiveExercises { list ->
            list.map { ex ->
                if (ex.id == exerciseDraftId) ex.copy(notes = notes) else ex
            }
        }
    }

    fun updateSetRpe(exerciseDraftId: String, setDraftId: String, rpeText: String) {
        updateActiveExercises { list ->
            list.map { ex ->
                if (ex.id != exerciseDraftId) return@map ex
                ex.copy(
                    sets = ex.sets.map { set ->
                        if (set.id == setDraftId) set.copy(rpeText = rpeText) else set
                    }
                )
            }
        }
    }

    fun updateSetRestSec(exerciseDraftId: String, setDraftId: String, restSecText: String) {
        updateActiveExercises { list ->
            list.map { ex ->
                if (ex.id != exerciseDraftId) return@map ex
                ex.copy(
                    sets = ex.sets.map { set ->
                        if (set.id == setDraftId) set.copy(restSecText = restSecText) else set
                    }
                )
            }
        }
    }

    fun updateSetNotes(exerciseDraftId: String, setDraftId: String, notes: String) {
        updateActiveExercises { list ->
            list.map { ex ->
                if (ex.id != exerciseDraftId) return@map ex
                ex.copy(
                    sets = ex.sets.map { set ->
                        if (set.id == setDraftId) set.copy(notes = notes) else set
                    }
                )
            }
        }
    }

    fun clearStatus() {
        _uiState.value = _uiState.value.copy(error = null, message = null)
    }

    fun consumePendingOpenWorkout() {
        _uiState.value = _uiState.value.copy(pendingOpenWorkoutId = null)
    }

    /** Llamar desde [AddWorkoutTabScreen] tras [onWorkoutPublishedToHome], para no re-disparar al volver a Add. */
    fun clearPostPublishHomeNonce() {
        _uiState.value = _uiState.value.copy(postPublishHomeNonce = 0)
    }

    fun exerciseCatalogForRecommendation(): List<ExerciseForRecommendation> =
        _uiState.value.exercises.map {
            ExerciseForRecommendation(
                id = it.id,
                name = it.name,
                nameEs = it.nameEs,
                nameEn = it.nameEn,
                musclePrimary = it.musclePrimary
            )
        }

    suspend fun recommendStrengthForUi(
        source: RecommendationDataSource,
        mode: StrengthSuggestionMode,
        preferSpanish: Boolean
    ): List<StrengthRecommendationExerciseResult> {
        val userId = supabase.auth.currentUserOrNull()?.id
            ?: throw com.lilru.liftr.ui.add.recommendation.WorkoutRecommendationError.NotSignedIn
        return recommendationEngine.recommendStrength(
            userId = userId,
            source = source,
            mode = mode,
            catalog = exerciseCatalogForRecommendation(),
            preferSpanish = preferSpanish
        )
    }

    suspend fun recommendCardioForUi(
        source: RecommendationDataSource
    ) = recommendationEngine.recommendCardio(
        supabase.auth.currentUserOrNull()?.id
            ?: throw com.lilru.liftr.ui.add.recommendation.WorkoutRecommendationError.NotSignedIn,
        source
    )

    suspend fun recommendSportForUi(
        source: RecommendationDataSource
    ) = recommendationEngine.recommendSport(
        supabase.auth.currentUserOrNull()?.id
            ?: throw com.lilru.liftr.ui.add.recommendation.WorkoutRecommendationError.NotSignedIn,
        source
    )

    fun applyStrengthRecommendation(rows: List<StrengthRecommendationExerciseResult>) {
        fun fmtKg(w: Double) =
            if (kotlin.math.floor(w) == w) w.toInt().toString() else String.format("%.1f", w)
        fun fmtRpe(x: Double) = fmtKg(x)
        val drafts = rows.map { ex ->
            StrengthExerciseDraft(
                exerciseId = ex.exerciseId,
                exerciseName = ex.displayName,
                sets = ex.sets.map { s ->
                    StrengthSetDraft(
                        setNumber = s.setNumber.coerceIn(1, 99),
                        repsText = s.reps.toString(),
                        weightText = fmtKg(s.weightKg),
                        rpeText = s.rpe?.let { fmtRpe(it) }.orEmpty(),
                        restSecText = s.restSec?.toString().orEmpty()
                    )
                }
            )
        }
        updateActiveExercises { drafts }
        _uiState.value = _uiState.value.copy(
            error = null,
            message = "Suggestion applied to the form."
        )
    }

    fun toggleParticipant(userId: String) {
        val state = _uiState.value
        val nextSelected = state.selectedParticipantIds.toMutableSet()
        val added = nextSelected.add(userId)
        if (!added) nextSelected.remove(userId)
        var usePerPerson = state.perPersonStrength
        if (nextSelected.isEmpty() && usePerPerson) {
            setPerPersonStrength(false)
            usePerPerson = false
        }
        if (!usePerPerson) {
            _uiState.value = _uiState.value.copy(
                selectedParticipantIds = nextSelected,
                error = null,
                message = null
            )
            return
        }
        val host = state.currentUserId ?: run {
            _uiState.value = state.copy(error = "Missing session user.")
            return
        }
        val owners = listOf(host) + nextSelected.toList()
        val nextMap = state.laneExercisesByUser.toMutableMap()
        if (added) {
            nextMap[userId] = state.selectedExercises.map { it.deepCopy() }
        } else {
            nextMap.remove(userId)
        }
        nextMap.keys.filterNot { it in owners }.forEach { nextMap.remove(it) }
        _uiState.value = state.copy(
            selectedParticipantIds = nextSelected,
            laneExercisesByUser = nextMap,
            activeLaneUserId = state.activeLaneUserId?.takeIf { it in owners } ?: host,
            error = null,
            message = null
        )
    }

    fun setPerPersonStrength(enabled: Boolean) {
        val current = _uiState.value
        if (!enabled) {
            val hostId = current.currentUserId
            val hostExercises = if (hostId != null) {
                current.laneExercisesByUser[hostId]
            } else {
                null
            } ?: current.selectedExercises
            _uiState.value = current.copy(
                perPersonStrength = false,
                activeLaneUserId = null,
                selectedExercises = hostExercises,
                error = null,
                message = null
            )
            return
        }
        val host = current.currentUserId ?: run {
            _uiState.value = current.copy(error = "Missing session user.")
            return
        }
        val targetOwners = listOf(host) + current.selectedParticipantIds.toList()
        val nextMap = current.laneExercisesByUser.toMutableMap()
        targetOwners.forEach { owner ->
            if (!nextMap.containsKey(owner)) {
                nextMap[owner] = current.selectedExercises.map { it.deepCopy() }
            }
        }
        nextMap.keys.filterNot { it in targetOwners }.forEach { nextMap.remove(it) }
        _uiState.value = current.copy(
            perPersonStrength = true,
            activeLaneUserId = current.activeLaneUserId?.takeIf { it in targetOwners } ?: host,
            laneExercisesByUser = nextMap,
            error = null,
            message = null
        )
    }

    fun setActiveLane(userId: String) {
        val current = _uiState.value
        if (!current.perPersonStrength) return
        if (!current.laneExercisesByUser.containsKey(userId)) return
        _uiState.value = current.copy(activeLaneUserId = userId, error = null, message = null)
    }

    private fun updateActiveExercises(mutator: (List<StrengthExerciseDraft>) -> List<StrengthExerciseDraft>) {
        val current = _uiState.value
        if (!current.perPersonStrength) {
            _uiState.value = current.copy(
                selectedExercises = mutator(current.selectedExercises),
                error = null,
                message = null
            )
            return
        }
        val laneId = current.activeLaneUserId ?: current.currentUserId ?: run {
            _uiState.value = current.copy(error = "Missing active lane user.")
            return
        }
        val currentLane = current.laneExercisesByUser[laneId].orEmpty()
        val nextMap = current.laneExercisesByUser.toMutableMap()
        nextMap[laneId] = mutator(currentLane)
        _uiState.value = current.copy(
            laneExercisesByUser = nextMap,
            activeLaneUserId = laneId,
            error = null,
            message = null
        )
    }

    private fun currentExercisesForEditing(): List<StrengthExerciseDraft> {
        val current = _uiState.value
        if (!current.perPersonStrength) return current.selectedExercises
        val laneId = current.activeLaneUserId ?: current.currentUserId
        return laneId?.let { current.laneExercisesByUser[it] }.orEmpty()
    }

    private suspend fun buildDraftsForRoutine(routineId: Long): List<StrengthExerciseDraft> {
        val st = _uiState.value
        val exRes = supabase.from(BackendContracts.Tables.STRENGTH_ROUTINE_EXERCISES)
            .select(columns = Columns.raw("id, routine_id, exercise_id, order_index, notes, custom_name")) {
                filter { eq("routine_id", routineId) }
                order("order_index", Order.ASCENDING)
            }
        val exerciseRows = decodeFlexibleList<RoutineExerciseRow>(exRes.data)
        val exIds = exerciseRows.map { it.id }
        val setRows = if (exIds.isEmpty()) {
            emptyList()
        } else {
            val setRes = supabase.from(BackendContracts.Tables.STRENGTH_ROUTINE_SETS)
                .select(columns = Columns.raw("routine_exercise_id, set_number, reps, weight_kg, rpe, rest_sec, notes")) {
                    filter { isIn("routine_exercise_id", exIds) }
                    order("set_number", Order.ASCENDING)
                }
            decodeFlexibleList<RoutineSetRow>(setRes.data)
        }
        val byExercise = setRows.groupBy { it.routineExerciseId }
        return exerciseRows.map { ex ->
            val sets = byExercise[ex.id].orEmpty().ifEmpty { listOf(RoutineSetRow(ex.id, 1)) }
            StrengthExerciseDraft(
                exerciseId = ex.exerciseId,
                exerciseName = st.exercises.firstOrNull { it.id == ex.exerciseId }?.let {
                    it.nameEs ?: it.nameEn ?: it.name
                } ?: "Exercise ${ex.exerciseId}",
                customName = ex.customName.orEmpty(),
                notes = ex.notes.orEmpty(),
                sets = sets.map { row ->
                    StrengthSetDraft(
                        setNumber = row.setNumber.coerceIn(1, 99),
                        repsText = row.reps?.toString() ?: "",
                        weightText = row.weightKg?.let { d ->
                            if (d == kotlin.math.floor(d)) d.toInt().toString() else d.toString()
                        } ?: "",
                        rpeText = row.rpe?.toString() ?: "",
                        restSecText = row.restSec?.toString() ?: "",
                        notes = row.notes.orEmpty()
                    )
                }
            )
        }
    }

    private suspend fun insertNewRoutineWithDrafts(
        userId: String,
        routineName: String,
        folderId: Long?,
        selected: List<StrengthExerciseDraft>
    ): Long {
        val routinePayload = buildJsonObject {
            put("user_id", userId)
            put("name", routineName)
            put("sort_order", System.currentTimeMillis().toInt())
            if (folderId != null) put("folder_id", folderId)
        }
        val insertRoutineRes = supabase.from(BackendContracts.Tables.STRENGTH_ROUTINES)
            .insert(routinePayload) { }
        val newRoutineId = parseSingleIdFromRpc(insertRoutineRes.data)
            ?: run {
                val lookupRes = supabase.from(BackendContracts.Tables.STRENGTH_ROUTINES)
                    .select(columns = Columns.raw("id")) {
                        filter {
                            eq("user_id", userId)
                            eq("name", routineName)
                            if (folderId != null) eq("folder_id", folderId)
                        }
                        order("id", Order.DESCENDING)
                        limit(1)
                    }
                Json.parseToJsonElement(lookupRes.data).jsonArray.firstOrNull()
                    ?.jsonObject?.get("id")?.toString()?.trim('"')?.toLongOrNull()
            }
            ?: error("Could not resolve routine id after insert.")

        selected.forEachIndexed { exIndex, exercise ->
            val eid = exercise.exerciseId ?: error("Missing exercise on draft")
            val routineExPayload = buildJsonObject {
                put("routine_id", newRoutineId)
                put("exercise_id", eid)
                put("order_index", exIndex + 1)
                if (exercise.notes.isNotBlank()) put("notes", exercise.notes.trim())
                if (exercise.customName.isNotBlank()) put("custom_name", exercise.customName.trim())
            }
            supabase.from(BackendContracts.Tables.STRENGTH_ROUTINE_EXERCISES)
                .insert(routineExPayload) { }
        }
        val insertedExRes = supabase.from(BackendContracts.Tables.STRENGTH_ROUTINE_EXERCISES)
            .select(columns = Columns.raw("id, routine_id, exercise_id, order_index, notes, custom_name")) {
                filter { eq("routine_id", newRoutineId) }
                order("order_index", Order.ASCENDING)
            }
        val insertedRows = decodeFlexibleList<RoutineExerciseRow>(insertedExRes.data)
        insertedRows.forEachIndexed { index, row ->
            val src = selected.getOrNull(index) ?: return@forEachIndexed
            src.sets.forEachIndexed { setIndex, set ->
                val reps = set.repsText.trim().toIntOrNull()
                val weight = set.weightText.trim().replace(",", ".").toDoubleOrNull()
                val rpe = set.rpeText.trim().replace(",", ".").toDoubleOrNull()
                val rest = set.restSecText.trim().toIntOrNull()
                val n = set.notes.trim()
                if ((reps == null || reps <= 0) && weight == null && rpe == null && rest == null && n.isBlank()) {
                    return@forEachIndexed
                }
                val setPayload = buildJsonObject {
                    put("routine_exercise_id", row.id)
                    put("set_number", set.setNumber.coerceIn(1, 99))
                    if (reps != null && reps > 0) put("reps", reps)
                    if (weight != null) put("weight_kg", weight)
                    if (rpe != null) put("rpe", rpe)
                    if (rest != null) put("rest_sec", rest)
                    if (n.isNotBlank()) put("notes", n)
                }
                supabase.from(BackendContracts.Tables.STRENGTH_ROUTINE_SETS)
                    .insert(setPayload) { }
            }
        }
        return newRoutineId
    }

    fun loadStrengthRoutines() {
        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(loadingRoutines = true)
            runCatching {
                val folderRes = supabase.from(BackendContracts.Tables.STRENGTH_ROUTINE_FOLDERS)
                    .select(columns = Columns.raw("id, name, sort_order")) {
                        order("sort_order", Order.ASCENDING)
                        order("name", Order.ASCENDING)
                    }
                val folders = decodeFlexibleList<RoutineFolderRow>(folderRes.data)
                    .map { RoutineFolderUi(id = it.id, name = it.name, sortOrder = it.sortOrder) }

                val routineRes = supabase.from(BackendContracts.Tables.STRENGTH_ROUTINES)
                    .select(columns = Columns.raw("id, name, folder_id, sort_order, updated_at")) {
                        order("sort_order", Order.ASCENDING)
                        order("name", Order.ASCENDING)
                    }
                val routineRows = decodeFlexibleList<RoutineRow>(routineRes.data)
                val routineIds = routineRows.map { it.id }
                val exerciseRows = if (routineIds.isEmpty()) {
                    emptyList()
                } else {
                    val exRes = supabase.from(BackendContracts.Tables.STRENGTH_ROUTINE_EXERCISES)
                        .select(columns = Columns.raw("id, routine_id")) {
                            filter { isIn("routine_id", routineIds) }
                        }
                    decodeFlexibleList<RoutineExerciseIdRoutinePair>(exRes.data)
                }
                val exerciseCountByRoutine = exerciseRows.groupingBy { it.routineId }.eachCount()
                val routines = routineRows.map { row ->
                    StrengthRoutineUi(
                        id = row.id,
                        name = row.name,
                        folderId = row.folderId,
                        sortOrder = row.sortOrder,
                        exerciseCount = exerciseCountByRoutine[row.id] ?: 0,
                        updatedAtIso = row.updatedAt
                    )
                }
                folders to routines
            }.onSuccess { pair ->
                val (folders, routines) = pair
                _uiState.value = _uiState.value.copy(
                    loadingRoutines = false,
                    routineFolders = folders,
                    routines = routines,
                    error = null
                )
            }.onFailure { e ->
                _uiState.value = _uiState.value.copy(
                    loadingRoutines = false,
                    error = e.message?.take(300) ?: e::class.java.simpleName
                )
            }
        }
    }

    fun applyRoutine(routineId: Long) {
        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(applyingRoutine = true, error = null, message = null)
            runCatching {
                buildDraftsForRoutine(routineId)
            }.onSuccess { mapped ->
                val current = _uiState.value
                val next = if (current.perPersonStrength) {
                    val laneId = current.activeLaneUserId ?: current.currentUserId
                    if (laneId != null) {
                        current.copy(
                            applyingRoutine = false,
                            laneExercisesByUser = current.laneExercisesByUser.toMutableMap().apply {
                                put(laneId, mapped)
                            },
                            message = "Routine applied.",
                            error = null
                        )
                    } else {
                        current.copy(applyingRoutine = false, error = "Missing active lane user.")
                    }
                } else {
                    current.copy(
                        applyingRoutine = false,
                        selectedExercises = mapped,
                        message = "Routine applied.",
                        error = null
                    )
                }
                _uiState.value = next
            }.onFailure { e ->
                _uiState.value = _uiState.value.copy(
                    applyingRoutine = false,
                    error = e.message?.take(300) ?: e::class.java.simpleName
                )
            }
        }
    }

    fun saveCurrentAsRoutine(routineName: String, folderId: Long?) {
        viewModelScope.launch {
            val trimmedName = routineName.trim()
            if (trimmedName.isEmpty()) {
                _uiState.value = _uiState.value.copy(error = "Routine name is required.")
                return@launch
            }
            val selected = currentExercisesForEditing()
            if (selected.isEmpty()) {
                _uiState.value = _uiState.value.copy(error = "Add at least one exercise before saving routine.")
                return@launch
            }
            if (selected.any { it.exerciseId == null }) {
                _uiState.value = _uiState.value.copy(
                    error = "Choose a movement for each exercise before saving the routine."
                )
                return@launch
            }
            _uiState.value = _uiState.value.copy(savingRoutine = true, error = null, message = null)
            runCatching {
                val me = supabase.auth.currentUserOrNull()?.id ?: error("Missing session user.")
                insertNewRoutineWithDrafts(me, trimmedName, folderId, selected)
            }.onSuccess {
                _uiState.value = _uiState.value.copy(
                    savingRoutine = false,
                    message = "Routine saved successfully."
                )
                loadStrengthRoutines()
            }.onFailure { e ->
                _uiState.value = _uiState.value.copy(
                    savingRoutine = false,
                    error = e.message?.take(300) ?: e::class.java.simpleName
                )
            }
        }
    }

    fun createRoutineFolder(name: String) {
        viewModelScope.launch {
            val trimmed = name.trim()
            if (trimmed.isEmpty()) {
                _uiState.value = _uiState.value.copy(error = "Folder name is required.")
                return@launch
            }
            _uiState.value = _uiState.value.copy(managingRoutines = true, error = null, message = null)
            runCatching {
                val me = supabase.auth.currentUserOrNull()?.id ?: error("Missing session user.")
                val payload = buildJsonObject {
                    put("user_id", me)
                    put("name", trimmed)
                    put("sort_order", System.currentTimeMillis().toInt())
                }
                supabase.from(BackendContracts.Tables.STRENGTH_ROUTINE_FOLDERS).insert(payload) { }
            }.onSuccess {
                _uiState.value = _uiState.value.copy(
                    managingRoutines = false,
                    message = "Folder created successfully."
                )
                loadStrengthRoutines()
            }.onFailure { e ->
                _uiState.value = _uiState.value.copy(
                    managingRoutines = false,
                    error = e.message?.take(300) ?: e::class.java.simpleName
                )
            }
        }
    }

    fun renameRoutine(routineId: Long, newName: String) {
        viewModelScope.launch {
            val trimmed = newName.trim()
            if (trimmed.isEmpty()) {
                _uiState.value = _uiState.value.copy(error = "Routine name is required.")
                return@launch
            }
            _uiState.value = _uiState.value.copy(managingRoutines = true, error = null, message = null)
            runCatching {
                val me = supabase.auth.currentUserOrNull()?.id ?: error("Missing session user.")
                val payload = buildJsonObject { put("name", trimmed) }
                supabase.from(BackendContracts.Tables.STRENGTH_ROUTINES).update(payload) {
                    filter {
                        eq("id", routineId)
                        eq("user_id", me)
                    }
                }
            }.onSuccess {
                _uiState.value = _uiState.value.copy(
                    managingRoutines = false,
                    message = "Routine renamed."
                )
                loadStrengthRoutines()
            }.onFailure { e ->
                _uiState.value = _uiState.value.copy(
                    managingRoutines = false,
                    error = e.message?.take(300) ?: e::class.java.simpleName
                )
            }
        }
    }

    fun moveRoutine(routineId: Long, direction: Int) {
        viewModelScope.launch {
            val current = _uiState.value
            val me = current.routines.firstOrNull { it.id == routineId } ?: return@launch
            val sameFolder = current.routines
                .filter { it.folderId == me.folderId }
                .sortedWith(compareBy<StrengthRoutineUi> { it.sortOrder }.thenBy { it.id })
            val index = sameFolder.indexOfFirst { it.id == routineId }
            if (index == -1) return@launch
            val targetIndex = index + direction
            if (targetIndex !in sameFolder.indices) return@launch
            val source = sameFolder[index]
            val target = sameFolder[targetIndex]
            _uiState.value = current.copy(managingRoutines = true, error = null, message = null)
            runCatching {
                val me = supabase.auth.currentUserOrNull()?.id ?: error("Missing session user.")
                supabase.from(BackendContracts.Tables.STRENGTH_ROUTINES).update(
                    buildJsonObject { put("sort_order", target.sortOrder) }
                ) {
                    filter {
                        eq("id", source.id)
                        eq("user_id", me)
                    }
                }
                supabase.from(BackendContracts.Tables.STRENGTH_ROUTINES).update(
                    buildJsonObject { put("sort_order", source.sortOrder) }
                ) {
                    filter {
                        eq("id", target.id)
                        eq("user_id", me)
                    }
                }
            }.onSuccess {
                _uiState.value = _uiState.value.copy(
                    managingRoutines = false,
                    message = "Routine order updated."
                )
                loadStrengthRoutines()
            }.onFailure { e ->
                _uiState.value = _uiState.value.copy(
                    managingRoutines = false,
                    error = e.message?.take(300) ?: e::class.java.simpleName
                )
            }
        }
    }

    fun moveRoutineToFolder(routineId: Long, folderId: Long?) {
        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(managingRoutines = true, error = null, message = null)
            runCatching {
                val me = supabase.auth.currentUserOrNull()?.id ?: error("Missing session user.")
                val payload = buildJsonObject {
                    if (folderId != null) put("folder_id", folderId) else put("folder_id", JsonNull)
                    put("sort_order", System.currentTimeMillis().toInt())
                }
                supabase.from(BackendContracts.Tables.STRENGTH_ROUTINES).update(payload) {
                    filter {
                        eq("id", routineId)
                        eq("user_id", me)
                    }
                }
            }.onSuccess {
                _uiState.value = _uiState.value.copy(
                    managingRoutines = false,
                    message = "Routine folder updated."
                )
                loadStrengthRoutines()
            }.onFailure { e ->
                _uiState.value = _uiState.value.copy(
                    managingRoutines = false,
                    error = e.message?.take(300) ?: e::class.java.simpleName
                )
            }
        }
    }

    fun deleteRoutine(routineId: Long) {
        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(managingRoutines = true, error = null, message = null)
            runCatching {
                val me = supabase.auth.currentUserOrNull()?.id ?: error("Missing session user.")
                supabase.from(BackendContracts.Tables.STRENGTH_ROUTINES).delete {
                    filter {
                        eq("id", routineId)
                        eq("user_id", me)
                    }
                }
            }.onSuccess {
                _uiState.value = _uiState.value.copy(
                    managingRoutines = false,
                    message = "Routine deleted."
                )
                loadStrengthRoutines()
            }.onFailure { e ->
                _uiState.value = _uiState.value.copy(
                    managingRoutines = false,
                    error = e.message?.take(300) ?: e::class.java.simpleName
                )
            }
        }
    }

    fun duplicateStrengthRoutine(sourceRoutineId: Long, newName: String, targetFolderId: Long?) {
        val trimmed = newName.trim()
        if (trimmed.isEmpty()) {
            _uiState.value = _uiState.value.copy(error = "Enter a routine name.")
            return
        }
        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(managingRoutines = true, error = null, message = null)
            runCatching {
                val me = supabase.auth.currentUserOrNull()?.id ?: error("Missing session user.")
                val dup = buildDraftsForRoutine(sourceRoutineId)
                if (dup.isEmpty()) {
                    error("This routine has no exercises to copy.")
                }
                if (dup.any { it.exerciseId == null }) {
                    error("Routine is missing exercise references.")
                }
                val taken = _uiState.value.routines.any {
                    it.name.equals(trimmed, ignoreCase = true) &&
                        (it.folderId == targetFolderId || (it.folderId == null && targetFolderId == null))
                }
                if (taken) {
                    error("A routine with this name already exists in this folder.")
                }
                insertNewRoutineWithDrafts(me, trimmed, targetFolderId, dup)
            }.onSuccess {
                _uiState.value = _uiState.value.copy(
                    managingRoutines = false,
                    message = "Routine duplicated."
                )
                loadStrengthRoutines()
            }.onFailure { e ->
                _uiState.value = _uiState.value.copy(
                    managingRoutines = false,
                    error = e.message?.take(300) ?: e::class.java.simpleName
                )
            }
        }
    }

    fun renameRoutineFolder(folderId: Long, newName: String) {
        viewModelScope.launch {
            val trimmed = newName.trim()
            if (trimmed.isEmpty()) {
                _uiState.value = _uiState.value.copy(error = "Folder name is required.")
                return@launch
            }
            _uiState.value = _uiState.value.copy(managingRoutines = true, error = null, message = null)
            runCatching {
                val me = supabase.auth.currentUserOrNull()?.id ?: error("Missing session user.")
                supabase.from(BackendContracts.Tables.STRENGTH_ROUTINE_FOLDERS).update(
                    buildJsonObject { put("name", trimmed) }
                ) {
                    filter {
                        eq("id", folderId)
                        eq("user_id", me)
                    }
                }
            }.onSuccess {
                _uiState.value = _uiState.value.copy(
                    managingRoutines = false,
                    message = "Folder renamed."
                )
                loadStrengthRoutines()
            }.onFailure { e ->
                _uiState.value = _uiState.value.copy(
                    managingRoutines = false,
                    error = e.message?.take(300) ?: e::class.java.simpleName
                )
            }
        }
    }

    fun moveRoutineFolder(folderId: Long, direction: Int) {
        viewModelScope.launch {
            val ordered = _uiState.value.routineFolders.sortedBy { it.sortOrder }
            val index = ordered.indexOfFirst { it.id == folderId }
            if (index == -1) return@launch
            val targetIndex = index + direction
            if (targetIndex !in ordered.indices) return@launch
            val source = ordered[index]
            val target = ordered[targetIndex]
            _uiState.value = _uiState.value.copy(managingRoutines = true, error = null, message = null)
            runCatching {
                val me = supabase.auth.currentUserOrNull()?.id ?: error("Missing session user.")
                supabase.from(BackendContracts.Tables.STRENGTH_ROUTINE_FOLDERS).update(
                    buildJsonObject { put("sort_order", target.sortOrder) }
                ) {
                    filter {
                        eq("id", source.id)
                        eq("user_id", me)
                    }
                }
                supabase.from(BackendContracts.Tables.STRENGTH_ROUTINE_FOLDERS).update(
                    buildJsonObject { put("sort_order", source.sortOrder) }
                ) {
                    filter {
                        eq("id", target.id)
                        eq("user_id", me)
                    }
                }
            }.onSuccess {
                _uiState.value = _uiState.value.copy(
                    managingRoutines = false,
                    message = "Folder order updated."
                )
                loadStrengthRoutines()
            }.onFailure { e ->
                _uiState.value = _uiState.value.copy(
                    managingRoutines = false,
                    error = e.message?.take(300) ?: e::class.java.simpleName
                )
            }
        }
    }

    fun deleteRoutineFolder(folderId: Long) {
        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(managingRoutines = true, error = null, message = null)
            runCatching {
                val me = supabase.auth.currentUserOrNull()?.id ?: error("Missing session user.")
                supabase.from(BackendContracts.Tables.STRENGTH_ROUTINES).update(
                    buildJsonObject { put("folder_id", JsonNull) }
                ) {
                    filter {
                        eq("user_id", me)
                        eq("folder_id", folderId)
                    }
                }
                supabase.from(BackendContracts.Tables.STRENGTH_ROUTINE_FOLDERS).delete {
                    filter {
                        eq("id", folderId)
                        eq("user_id", me)
                    }
                }
            }.onSuccess {
                _uiState.value = _uiState.value.copy(
                    managingRoutines = false,
                    message = "Folder deleted."
                )
                loadStrengthRoutines()
            }.onFailure { e ->
                _uiState.value = _uiState.value.copy(
                    managingRoutines = false,
                    error = e.message?.take(300) ?: e::class.java.simpleName
                )
            }
        }
    }

    fun copyHostLaneToActiveLane() {
        val current = _uiState.value
        if (!current.perPersonStrength) return
        val host = current.currentUserId ?: return
        val active = current.activeLaneUserId ?: return
        if (host == active) return
        val hostDraft = current.laneExercisesByUser[host].orEmpty().map { it.deepCopy() }
        val next = current.laneExercisesByUser.toMutableMap()
        next[active] = hostDraft
        _uiState.value = current.copy(
            laneExercisesByUser = next,
            message = "Copied host program to active lane.",
            error = null
        )
    }

    fun clearActiveLane() {
        val current = _uiState.value
        if (!current.perPersonStrength) return
        val active = current.activeLaneUserId ?: return
        val next = current.laneExercisesByUser.toMutableMap()
        next[active] = emptyList()
        _uiState.value = current.copy(
            laneExercisesByUser = next,
            message = "Active lane cleared.",
            error = null
        )
    }

    fun loadExercises() {
        refreshExercisesForPicker(ExercisePickerSortMode.ALPHABETIC)
    }

    fun setExercisePickerSortMode(mode: ExercisePickerSortMode) {
        _uiState.value = _uiState.value.copy(exercisePickerSortMode = mode)
        refreshExercisesForPicker(mode)
    }

    /**
     * When the exercise sheet opens: load favorites, then list for current sort (iOS ExercisePickerSheet).
     */
    fun onExercisePickerOpened() {
        viewModelScope.launch {
            runCatching { loadFavoriteIds() }
            refreshExercisesForPickerInternal(_uiState.value.exercisePickerSortMode)
        }
    }

    fun toggleFavoriteExercise(exerciseId: Long) {
        val userId = supabase.auth.currentUserOrNull()?.id ?: return
        val had = _uiState.value.favoriteExerciseIds.contains(exerciseId)
        _uiState.value = _uiState.value.copy(
            favoriteExerciseIds = if (had) {
                _uiState.value.favoriteExerciseIds - exerciseId
            } else {
                _uiState.value.favoriteExerciseIds + exerciseId
            }
        )
        viewModelScope.launch {
            runCatching {
                if (had) {
                    supabase.from(BackendContracts.Tables.USER_FAVORITE_EXERCISES).delete {
                        filter {
                            eq("user_id", userId)
                            eq("exercise_id", exerciseId)
                        }
                    }
                } else {
                    val row = buildJsonObject {
                        put("user_id", userId)
                        put("exercise_id", exerciseId)
                    }
                    supabase.from(BackendContracts.Tables.USER_FAVORITE_EXERCISES).insert(row) { }
                }
            }.onFailure { e ->
                _uiState.value = _uiState.value.copy(
                    favoriteExerciseIds = if (had) {
                        _uiState.value.favoriteExerciseIds + exerciseId
                    } else {
                        _uiState.value.favoriteExerciseIds - exerciseId
                    },
                    error = e.message?.take(300) ?: e::class.java.simpleName
                )
            }
            if (_uiState.value.exercisePickerSortMode == ExercisePickerSortMode.FAVORITES) {
                viewModelScope.launch { refreshExercisesForPickerInternal(ExercisePickerSortMode.FAVORITES) }
            }
        }
    }

    private suspend fun loadFavoriteIds() {
        val res = supabase.from(BackendContracts.Tables.USER_FAVORITE_EXERCISES)
            .select(columns = Columns.raw("exercise_id")) { }
        val arr = runCatching { JSONArray(res.data) }.getOrNull() ?: return
        val ids = (0 until arr.length()).mapNotNull { i ->
            arr.optJSONObject(i)?.optLong("exercise_id")?.takeIf { it > 0 }
        }.toSet()
        _uiState.value = _uiState.value.copy(favoriteExerciseIds = ids)
    }

    private fun exerciseSelectColumns() =
        "id, name, name_es, name_en, category, muscle_primary, equipment"

    private data class ExerciseUsageRow(
        val id: Long,
        val name: String,
        val timesUsed: Int = 0,
        val lastUsedAt: String? = null
    )

    private fun parseExerciseUsageArray(raw: String): List<ExerciseUsageRow> {
        if (raw.isBlank()) return emptyList()
        val arr = runCatching { JSONArray(raw.trim()) }.getOrNull() ?: return emptyList()
        return (0 until arr.length()).mapNotNull { i ->
            val o = arr.optJSONObject(i) ?: return@mapNotNull null
            ExerciseUsageRow(
                id = o.optLong("id", 0L).takeIf { it > 0L } ?: return@mapNotNull null,
                name = o.optString("name", ""),
                timesUsed = o.optInt("times_used", 0),
                lastUsedAt = o.optString("last_used_at", "").takeIf { it.isNotEmpty() }
            )
        }
    }

    private suspend fun fetchExercisesByIdsPreservingOrder(ids: List<Long>): List<ExerciseLite> {
        if (ids.isEmpty()) return emptyList()
        val res = supabase.from(BackendContracts.Tables.EXERCISES)
            .select(columns = Columns.raw(exerciseSelectColumns())) {
                filter {
                    eq("is_public", true)
                    eq("modality", "strength")
                    isIn("id", ids)
                }
                limit(2000)
            }
        val rows = runCatching { res.decodeList<ExerciseLite>() }.getOrDefault(emptyList())
        val byId = rows.associateBy { it.id }
        return ids.mapNotNull { id ->
            byId[id] ?: ExerciseLite(
                id = id,
                name = "Exercise $id",
                nameEs = null,
                nameEn = null,
                category = null,
                musclePrimary = null,
                equipment = null
            )
        }
    }

    private fun refreshExercisesForPicker(mode: ExercisePickerSortMode) {
        viewModelScope.launch { refreshExercisesForPickerInternal(mode) }
    }

    private suspend fun refreshExercisesForPickerInternal(mode: ExercisePickerSortMode) {
        _uiState.value = _uiState.value.copy(loadingExercises = true, error = null)
        try {
            val list: List<ExerciseLite> = when (mode) {
                ExercisePickerSortMode.ALPHABETIC -> {
                    supabase.from(BackendContracts.Tables.EXERCISES)
                        .select(columns = Columns.raw(exerciseSelectColumns())) {
                            filter {
                                eq("is_public", true)
                                eq("modality", "strength")
                            }
                            order("name", Order.ASCENDING)
                            limit(2000)
                        }
                        .decodeList<ExerciseLite>()
                }
                ExercisePickerSortMode.MOST_USED -> {
                    val params = buildJsonObject {
                        put("p_modality", "strength")
                        put("p_search", JsonNull)
                        put("p_limit", 200)
                    }
                    val res = supabase.postgrest.rpc(BackendContracts.Rpc.GET_EXERCISES_USAGE, params) { }
                    val used = parseExerciseUsageArray(res.data)
                    if (used.isEmpty()) {
                        emptyList()
                    } else {
                        val ids = used.map { it.id }
                        fetchExercisesByIdsPreservingOrder(ids)
                    }
                }
                ExercisePickerSortMode.RECENT -> {
                    val params = buildJsonObject {
                        put("p_modality", "strength")
                        put("p_search", JsonNull)
                        put("p_limit", 200)
                    }
                    val res = supabase.postgrest.rpc(BackendContracts.Rpc.GET_EXERCISES_USAGE, params) { }
                    val used = parseExerciseUsageArray(res.data)
                    val sorted = used
                        .filter { (it.lastUsedAt != null && it.lastUsedAt.isNotBlank() && it.timesUsed > 0) }
                        .sortedWith(compareByDescending<ExerciseUsageRow> { u ->
                            runCatching { Instant.parse(u.lastUsedAt!!) }.getOrNull() ?: Instant.EPOCH
                        })
                    if (sorted.isEmpty()) {
                        emptyList()
                    } else {
                        val ids = sorted.map { it.id }
                        fetchExercisesByIdsPreservingOrder(ids)
                    }
                }
                ExercisePickerSortMode.FAVORITES -> {
                    loadFavoriteIds()
                    val favs = _uiState.value.favoriteExerciseIds
                    if (favs.isEmpty()) {
                        emptyList()
                    } else {
                        supabase.from(BackendContracts.Tables.EXERCISES)
                            .select(columns = Columns.raw(exerciseSelectColumns())) {
                                filter {
                                    eq("is_public", true)
                                    eq("modality", "strength")
                                    isIn("id", favs.toList())
                                }
                                order("name", Order.ASCENDING)
                                limit(2000)
                            }
                            .decodeList<ExerciseLite>()
                    }
                }
            }
            _uiState.value = _uiState.value.copy(
                loadingExercises = false,
                exercisePickerSortMode = mode,
                exercises = list
            )
        } catch (e: Exception) {
            _uiState.value = _uiState.value.copy(
                loadingExercises = false,
                error = e.message?.take(300) ?: e::class.java.simpleName
            )
        }
    }

    fun loadFollowees() {
        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(loadingFollowees = true)
            runCatching {
                val me = supabase.auth.currentUserOrNull()?.id ?: error("Missing session user.")
                val edgeRes = supabase.from(BackendContracts.Tables.FOLLOWS)
                    .select(columns = Columns.raw("followee_id")) {
                        filter { eq("follower_id", me) }
                        limit(500)
                    }
                val ids = runCatching {
                    json.decodeFromString<List<FollowEdge>>(edgeRes.data)
                        .mapNotNull { it.followeeId }
                }.getOrDefault(emptyList())
                if (ids.isEmpty()) return@runCatching emptyList()
                val profileRes = supabase.from(BackendContracts.Tables.PROFILES)
                    .select(columns = Columns.raw("user_id, username, avatar_url")) {
                        filter { isIn("user_id", ids) }
                        order("username", Order.ASCENDING)
                    }
                json.decodeFromString<List<ProfileLite>>(profileRes.data)
            }.onSuccess { followees ->
                _uiState.value = _uiState.value.copy(
                    loadingFollowees = false,
                    followees = followees
                )
            }.onFailure { e ->
                _uiState.value = _uiState.value.copy(
                    loadingFollowees = false,
                    error = e.message?.take(300) ?: e::class.java.simpleName
                )
            }
        }
    }

    /**
     * Fuerza: *per person* → `plan_strength_squad_programs`; misma sesión → `create_strength_workout` + participantes.
     * Copias vinculadas al **iniciar** desde el detalle del entreno, no al guardar en Add (paridad con iOS).
     */
    fun createStrengthWorkout(
        title: String,
        notes: String,
        durationMin: Int?,
        intensity: AddWorkoutIntensity,
        state: AddWorkoutState,
        startedAtIso: String? = null,
        endedAtIso: String? = null,
        useCustomSchedule: Boolean = false,
        scheduleEndedEnabled: Boolean = false
    ) {
        viewModelScope.launch {
            val snap = _uiState.value
            val participantIds = snap.selectedParticipantIds.toList()
            val perPersonStrength = snap.perPersonStrength
            if (perPersonStrength && participantIds.size > 2) {
                _uiState.value = snap.copy(
                    error = "Per-person planning supports at most two partners (three people total)."
                )
                return@launch
            }
            _uiState.value = _uiState.value.copy(creating = true, error = null, message = null)
            runCatching {
                val userId = supabase.auth.currentUserOrNull()?.id
                    ?: error("Missing session user.")
                val startedAt = parseInstantOrNow(startedAtIso)
                val endedAt = when {
                    useCustomSchedule && scheduleEndedEnabled && !endedAtIso.isNullOrBlank() ->
                        runCatching { Instant.parse(endedAtIso.trim()) }.getOrNull()?.toString()
                    durationMin != null && durationMin > 0 ->
                        startedAt.plusSeconds(durationMin.toLong() * 60L).toString()
                    else -> null
                }
                fun paramsForState(stateWire: String, payloadItems: List<Pair<StrengthExerciseDraft, List<StrengthSetPayload>>>) = buildJsonObject {
                    put("p_user_id", userId)
                    put("p_started_at", startedAt.toString())
                    put("p_perceived_intensity", intensity.wire)
                    put("p_state", stateWire)
                    if (title.isNotBlank()) {
                        put("p_title", title.trim())
                    }
                    if (notes.isNotBlank()) {
                        put("p_notes", notes.trim())
                    }
                    if (endedAt != null) {
                        put("p_ended_at", endedAt)
                    }
                    put("p_items", buildJsonArray {
                        payloadItems.forEachIndexed { exerciseIndex, pair ->
                            val (exercise, validSets) = pair
                            add(
                                buildJsonObject {
                                    put("exercise_id", checkNotNull(exercise.exerciseId))
                                    put("order_index", exerciseIndex + 1)
                                    if (exercise.notes.isNotBlank()) {
                                        put("notes", exercise.notes.trim())
                                    }
                                    if (exercise.customName.isNotBlank()) {
                                        put("custom_name", exercise.customName.trim())
                                    }
                                    put("sets", buildJsonArray {
                                        validSets.forEachIndexed { _, p ->
                                            val reps = p.reps
                                            val weightKg = p.weightKg
                                            add(
                                                buildJsonObject {
                                                    put("set_number", p.setNumber.coerceIn(1, 99))
                                                    if (reps != null) {
                                                        put("reps", reps)
                                                    }
                                                    if (weightKg != null) {
                                                        put("weight_kg", weightKg)
                                                    }
                                                    p.rpe?.let { put("rpe", it) }
                                                    p.restSec?.let { put("rest_sec", it) }
                                                    p.notes?.let { put("notes", it) }
                                                }
                                            )
                                        }
                                    })
                                }
                            )
                        }
                    })
                }

                val targetState = state.name.lowercase()
                if (perPersonStrength) {
                    val owners = listOf(userId) + participantIds
                    val programsPayload = owners.map { ownerId ->
                        val lane = snap.laneExercisesByUser[ownerId].orEmpty()
                        if (lane.isEmpty()) {
                            error("Each person needs at least one valid exercise.")
                        }
                        val payloadItems = buildStrengthPayloadItems(lane)
                        if (payloadItems.isEmpty()) {
                            error("Each person needs at least one valid exercise.")
                        }
                        ownerId to payloadItems
                    }
                    val programs = buildJsonArray {
                        programsPayload.forEach { pair ->
                            val (ownerId, payloadItems) = pair
                            add(
                                buildJsonObject {
                                    put("owner_user_id", ownerId)
                                    put("items", paramsForState(targetState, payloadItems)["p_items"]!!)
                                }
                            )
                        }
                    }
                    val squadParams = buildJsonObject {
                        put("p_programs", programs)
                        put("p_title", title)
                        put("p_notes", notes)
                        put("p_started_at", startedAt.toString())
                        put("p_perceived_intensity", intensity.wire)
                        put("p_state", targetState)
                        put("p_ended_at", endedAt ?: "")
                    }
                    val squadRes = supabase.postgrest.rpc(
                        BackendContracts.Rpc.PLAN_STRENGTH_SQUAD_PROGRAMS,
                        squadParams
                    ) { }
                    val squadIds = parseLongArrayFromRpc(squadRes.data)
                    val firstWid = squadIds.firstOrNull()
                    supabase.submitWorkoutToCompetitionIfActive(firstWid)
                } else {
                    val selected = snap.selectedExercises
                    if (selected.isEmpty()) error("Add at least one exercise first.")
                    val params = paramsForState(targetState, buildStrengthPayloadItems(selected))
                    val res = supabase.postgrest.rpc(BackendContracts.Rpc.CREATE_STRENGTH_WORKOUT, params) { }
                    val workoutId = parseSingleIdFromRpc(res.data)
                        ?: fetchLastWorkoutId(userId, "strength")
                    if (workoutId != null && participantIds.isNotEmpty()) {
                        addParticipantsToWorkout(workoutId, participantIds)
                    }
                    supabase.submitWorkoutToCompetitionIfActive(workoutId)
                }
            }.onSuccess {
                onWorkoutCreatedUi(strengthSuccessMessage(perPersonStrength, state))
            }.onFailure { e ->
                Log.e(TAG, "createStrengthWorkout failed", e)
                val raw = e.message.orEmpty()
                val low = raw.lowercase()
                val friendly = if (
                    state == AddWorkoutState.PLANNED &&
                    "invalid input value for enum workout_state" in low &&
                    "\"planned\"" in low
                ) {
                    "Tu backend actual no soporta el estado 'planned' en workout_state. Usa 'Published' o aplica la migracion del enum/funcion en Supabase."
                } else {
                    raw.take(300).ifBlank { e::class.java.simpleName }
                }
                _uiState.value = _uiState.value.copy(
                    creating = false,
                    error = friendly
                )
            }
        }
    }

    fun createCardioWorkout(
        title: String,
        notes: String,
        activity: AddCardioActivity,
        distanceKmText: String,
        durationSecText: String,
        avgHrText: String,
        maxHrText: String,
        avgPaceSecPerKmText: String,
        elevationGainMText: String,
        cadenceRpmText: String,
        wattsAvgText: String,
        inclinePercentText: String,
        swimLapsText: String,
        poolLengthMText: String,
        swimStyleText: String,
        splitSecPer500mText: String,
        kmSplitsPaceText: String,
        intensity: AddWorkoutIntensity,
        state: AddWorkoutState,
        startedAtIso: String? = null,
        endedAtIso: String? = null,
        useCustomSchedule: Boolean = false,
        scheduleEndedEnabled: Boolean = false
    ) {
        viewModelScope.launch {
            val participantIds = _uiState.value.selectedParticipantIds.toList()
            _uiState.value = _uiState.value.copy(creating = true, error = null, message = null)
            runCatching {
                val userId = supabase.auth.currentUserOrNull()?.id
                    ?: error("Missing session user.")
                val startedAt = parseInstantOrNow(startedAtIso).toString()
                val durationSec = parseInt(durationSecText)
                val endedAt = when {
                    useCustomSchedule && scheduleEndedEnabled && !endedAtIso.isNullOrBlank() ->
                        runCatching { Instant.parse(endedAtIso.trim()).toString() }.getOrNull()
                    durationSec != null && durationSec > 0 ->
                        Instant.parse(startedAt).plusSeconds(durationSec.toLong()).toString()
                    else -> null
                }
                val stats = buildJsonObject {
                    parseInt(avgHrText)?.let { put("avg_hr", it) }
                    parseInt(maxHrText)?.let { put("max_hr", it) }
                    parseInt(cadenceRpmText)?.let { put("cadence_rpm", it) }
                    parseInt(wattsAvgText)?.let { put("watts_avg", it) }
                    parseDouble(inclinePercentText)?.let { put("incline_pct", it) }
                    parseInt(swimLapsText)?.let { put("swim_laps", it) }
                    parseInt(poolLengthMText)?.let { put("pool_length_m", it) }
                    if (swimStyleText.isNotBlank()) put("swim_style", swimStyleText.trim())
                    parseInt(splitSecPer500mText)?.let { put("split_sec_per_500m", it) }
                    val splitSecs = com.lilru.liftr.cardio.CardioKmPaceSplits.parseFieldText(kmSplitsPaceText)
                    if (activity.showsKmPaceSplits && splitSecs.isNotEmpty()) {
                        put("km_split_pace_sec", buildJsonArray {
                            splitSecs.forEach { add(JsonPrimitive(it)) }
                        })
                    }
                }
                val p = buildJsonObject {
                    put("p_user_id", userId)
                    put("p_activity_code", activity.wire)
                    put("p_started_at", startedAt)
                    put("p_perceived_intensity", intensity.wire)
                    put("p_state", state.name.lowercase())
                    if (title.isNotBlank()) put("p_title", title.trim())
                    if (notes.isNotBlank()) put("p_notes", notes.trim())
                    if (endedAt != null) put("p_ended_at", endedAt)
                    parseDouble(distanceKmText)?.let { put("p_distance_km", it) }
                    durationSec?.let { put("p_duration_sec", it) }
                    parseInt(avgHrText)?.let { put("p_avg_hr", it) }
                    parseInt(maxHrText)?.let { put("p_max_hr", it) }
                    parseInt(avgPaceSecPerKmText)?.let { put("p_avg_pace_sec_per_km", it) }
                    parseInt(elevationGainMText)?.let { put("p_elevation_gain_m", it) }
                    put("p_stats", stats)
                }
                val wrapper = buildJsonObject { put("p", p) }
                val res = supabase.postgrest.rpc(BackendContracts.Rpc.CREATE_CARDIO_WORKOUT_V2, wrapper) { }
                val workoutId = parseSingleIdFromRpc(res.data) ?: fetchLastWorkoutId(userId, "cardio")
                if (workoutId != null && participantIds.isNotEmpty()) {
                    addParticipantsToWorkout(workoutId, participantIds)
                }
                supabase.submitWorkoutToCompetitionIfActive(workoutId)
            }.onSuccess {
                val r = getApplication<Application>().resources
                val msg = if (state == AddWorkoutState.PUBLISHED) {
                    r.getString(R.string.add_strength_success_published)
                } else {
                    r.getString(R.string.add_strength_success_planned)
                }
                onWorkoutCreatedUi(msg)
            }.onFailure { e ->
                _uiState.value = _uiState.value.copy(
                    creating = false,
                    error = formatCreateError(e, state)
                )
            }
        }
    }

    fun createSportWorkout(
        title: String,
        notes: String,
        sport: AddSportType,
        durationMinText: String,
        scoreForText: String,
        scoreAgainstText: String,
        matchScoreText: String,
        location: String,
        sessionNotes: String,
        matchResult: AddMatchResult,
        footballPosition: AddFootballPosition,
        racketMode: AddRacketMode,
        racketFormat: AddRacketFormat,
        sportStats: Map<String, String>,
        hyroxExercisesText: String,
        intensity: AddWorkoutIntensity,
        state: AddWorkoutState,
        startedAtIso: String? = null,
        endedAtIso: String? = null,
        useCustomSchedule: Boolean = false,
        scheduleEndedEnabled: Boolean = false
    ) {
        viewModelScope.launch {
            val participantIds = _uiState.value.selectedParticipantIds.toList()
            _uiState.value = _uiState.value.copy(creating = true, error = null, message = null)
            runCatching {
                val userId = supabase.auth.currentUserOrNull()?.id
                    ?: error("Missing session user.")
                val startedInstant = parseInstantOrNow(startedAtIso)
                val startedAt = startedInstant.toString()
                val endedInstant = if (useCustomSchedule && scheduleEndedEnabled && !endedAtIso.isNullOrBlank()) {
                    runCatching { Instant.parse(endedAtIso.trim()) }.getOrNull()
                } else {
                    null
                }
                val durationMinTyped = parseInt(durationMinText)
                val durationMin = durationMinTyped ?: run {
                    if (endedInstant != null) {
                        val secs = (endedInstant.epochSecond - startedInstant.epochSecond).coerceAtLeast(1L)
                        (secs / 60L).toInt().coerceAtLeast(1)
                    } else {
                        null
                    }
                }
                val p = buildJsonObject {
                    put("p_user_id", userId.toString())
                    put("p_sport", sport.wire)
                    put("p_started_at", startedAt)
                    put("p_perceived_intensity", intensity.wire)
                    put("p_state", state.name.lowercase())
                    if (title.isNotBlank()) put("p_title", title.trim())
                    if (notes.isNotBlank()) put("p_notes", notes.trim())
                    if (endedInstant != null) {
                        put("p_ended_at", endedInstant.toString())
                    }
                    durationMin?.let { put("p_duration_min", it) }
                    parseInt(scoreForText)?.let { put("p_score_for", it) }
                    parseInt(scoreAgainstText)?.let { put("p_score_against", it) }
                    if (sport != AddSportType.SKI) {
                        put("p_match_result", matchResult.wire)
                    }
                    if (matchScoreText.isNotBlank()) put("p_match_score_text", matchScoreText.trim())
                    if (location.isNotBlank()) put("p_location", location.trim())
                    if (sessionNotes.isNotBlank()) put("p_session_notes", sessionNotes.trim())
                }
                val stats = SportStatsPayloadBuilder.build(
                    sport = sport,
                    durationMinText = durationMinText,
                    footballPosition = footballPosition,
                    racketMode = racketMode,
                    racketFormat = racketFormat,
                    sportStats = sportStats,
                    hyroxExercisesText = hyroxExercisesText
                )
                val wrapper = buildJsonObject {
                    put("p", p)
                    put("p_stats", stats)
                }
                val res = supabase.postgrest.rpc(BackendContracts.Rpc.CREATE_SPORT_WORKOUT_V2, wrapper) { }
                val workoutId = parseSingleIdFromRpc(res.data) ?: fetchLastWorkoutId(userId, "sport")
                if (workoutId != null && participantIds.isNotEmpty()) {
                    addParticipantsToWorkout(workoutId, participantIds)
                }
                if (workoutId != null && sport == AddSportType.HYROX) {
                    patchHyroxExerciseDisplayNamesIfNeeded(workoutId, hyroxExercisesText)
                }
                supabase.submitWorkoutToCompetitionIfActive(workoutId)
            }.onSuccess {
                val r = getApplication<Application>().resources
                val msg = if (state == AddWorkoutState.PUBLISHED) {
                    r.getString(R.string.add_strength_success_published)
                } else {
                    r.getString(R.string.add_strength_success_planned)
                }
                onWorkoutCreatedUi(msg)
            }.onFailure { e ->
                _uiState.value = _uiState.value.copy(
                    creating = false,
                    error = formatCreateError(e, state)
                )
            }
        }
    }

    private fun parseInstantOrNow(iso: String?): Instant =
        iso?.trim()?.takeIf { it.isNotEmpty() }?.let { raw ->
            runCatching { Instant.parse(raw) }.getOrNull()
        } ?: Instant.now()

    private fun parseLongArrayFromRpc(raw: String): List<Long> {
        val t = raw.trim()
        if (t.isEmpty()) return emptyList()
        return runCatching {
            val arr = JSONArray(t)
            List(arr.length()) { i -> arr.getLong(i) }
        }.getOrElse {
            runCatching {
                Json.parseToJsonElement(t).jsonArray.mapNotNull { el ->
                    when (el) {
                        is JsonPrimitive -> el.longOrNull ?: el.content.toLongOrNull()
                        else -> null
                    }
                }
            }.getOrDefault(emptyList())
        }
    }

    private suspend fun fetchSportSessionIdForWorkout(workoutId: Long): Int? {
        val res = supabase.from(BackendContracts.Tables.SPORT_SESSIONS)
            .select(columns = Columns.raw("id")) {
                filter { eq("workout_id", workoutId) }
                limit(1)
            }
        return runCatching {
            Json.parseToJsonElement(res.data).jsonArray.firstOrNull()
                ?.jsonObject?.get("id")?.jsonPrimitive?.content?.toIntOrNull()
        }.getOrNull()
    }

    private suspend fun patchHyroxExerciseDisplayNamesIfNeeded(
        workoutId: Long,
        hyroxExercisesText: String
    ) {
        if (hyroxExercisesText.isBlank()) return
        val arr = runCatching { Json.parseToJsonElement(hyroxExercisesText.trim()).jsonArray }
            .getOrNull() ?: return
        if (arr.isEmpty()) return
        val sessionId = fetchSportSessionIdForWorkout(workoutId) ?: return
        @Serializable
        data class HyroxDisplayNamePatch(
            @SerialName("exercise_display_name") val exerciseDisplayName: String
        )
        for ((idx, el) in arr.withIndex()) {
            val o = el as? JsonObject ?: continue
            val code = o["exercise_code"]?.jsonPrimitive?.contentOrNull
                ?: o["exerciseCode"]?.jsonPrimitive?.contentOrNull
                ?: continue
            val custom = o["exercise_display_name"]?.jsonPrimitive?.contentOrNull
                ?: o["custom_display_name"]?.jsonPrimitive?.contentOrNull
                ?: ""
            val notes = o["notes"]?.jsonPrimitive?.contentOrNull ?: ""
            val order = idx + 1
            val display = HyroxExerciseFormatting.persistedPayload(code, custom, notes).displayName
                ?: continue
            runCatching {
                supabase.from(BackendContracts.Tables.HYROX_SESSION_EXERCISES).update(
                    HyroxDisplayNamePatch(exerciseDisplayName = display)
                ) {
                    filter {
                        eq("session_id", sessionId)
                        eq("exercise_order", order)
                    }
                }
            }.onFailure { e ->
                Log.w(TAG, "hyrox display name patch failed order=$order", e)
            }
        }
    }

    private fun parseInt(value: String): Int? = value.trim().toIntOrNull()

    private fun parseDouble(value: String): Double? =
        value.trim().replace(",", ".").toDoubleOrNull()

    private inline fun <reified T> decodeFlexibleList(raw: String): List<T> {
        return runCatching {
            json.decodeFromString<List<T>>(raw)
        }.getOrElse {
            val root = Json.parseToJsonElement(raw)
            when {
                root is kotlinx.serialization.json.JsonArray ->
                    json.decodeFromString(root.toString())
                root is kotlinx.serialization.json.JsonObject && "data" in root ->
                    json.decodeFromString(root["data"].toString())
                root is kotlinx.serialization.json.JsonObject ->
                    listOf(json.decodeFromString(root.toString()))
                else -> emptyList()
            }
        }
    }

    private fun buildStrengthPayloadItems(
        exercises: List<StrengthExerciseDraft>
    ): List<Pair<StrengthExerciseDraft, List<StrengthSetPayload>>> {
        if (exercises.any { it.exerciseId == null }) {
            error("Choose a movement for each exercise (Exercise field).")
        }
        if (exercises.any { it.sets.isEmpty() }) {
            error("Each exercise needs at least one set.")
        }
        val mapped = exercises.map { exercise ->
            val exId = exercise.exerciseId ?: error("Missing exercise_id")
            if (exId <= 0L) error("Invalid exercise.")
            val validSets = exercise.sets.mapNotNull { set ->
                val reps = set.repsText.trim().toIntOrNull()
                val weight = set.weightText.trim().replace(",", ".").toDoubleOrNull()
                val rpe = set.rpeText.trim().replace(",", ".").toDoubleOrNull()
                val restSec = set.restSecText.trim().toIntOrNull()
                val notes = set.notes.trim()
                if ((reps == null || reps <= 0) && weight == null && rpe == null && restSec == null && notes.isBlank()) {
                    return@mapNotNull null
                }
                val safeReps = reps?.takeIf { it > 0 }
                StrengthSetPayload(
                    setNumber = set.setNumber.coerceIn(1, 99),
                    reps = safeReps,
                    weightKg = weight,
                    rpe = rpe,
                    restSec = restSec,
                    notes = notes.ifBlank { null }
                )
            }
            exercise to validSets
        }
        if (mapped.any { it.second.isEmpty() }) {
            error("Each exercise must contain at least one set with reps > 0 or additional valid fields.")
        }
        return mapped
    }

    private fun formatCreateError(error: Throwable, state: AddWorkoutState): String {
        Log.e(TAG, "create workout failed", error)
        val raw = error.message.orEmpty()
        val low = raw.lowercase()
        return if (
            state == AddWorkoutState.PLANNED &&
            "invalid input value for enum workout_state" in low &&
            "\"planned\"" in low
        ) {
            "Tu backend actual no soporta el estado 'planned' en workout_state. Usa 'Published' o aplica la migracion del enum/funcion en Supabase."
        } else {
            raw.take(300).ifBlank { error::class.java.simpleName }
        }
    }

    private suspend fun addParticipantsToWorkout(workoutId: Long, participantIds: List<String>) {
        participantIds.forEach { uid ->
            val params = buildJsonObject {
                put("p_workout_id", workoutId)
                put("p_user_id", uid)
            }
            runCatching {
                supabase.postgrest.rpc(BackendContracts.Rpc.ADD_WORKOUT_PARTICIPANT, params) { }
            }.onFailure { e ->
                Log.w(TAG, "add_workout_participant failed for $uid (workout $workoutId)", e)
            }
        }
    }

    private suspend fun fetchLastWorkoutId(userId: String, kind: String): Long? {
        val res = supabase.from(BackendContracts.Tables.WORKOUTS)
            .select(columns = Columns.raw("id")) {
                filter {
                    eq("user_id", userId)
                    eq("kind", kind)
                }
                order("started_at", Order.DESCENDING)
                limit(1)
            }
        return runCatching {
            kotlinx.serialization.json.Json.parseToJsonElement(res.data)
                .jsonArray.firstOrNull()
                ?.jsonObject?.get("id")
                ?.toString()
                ?.trim('"')
                ?.toLongOrNull()
        }.getOrNull()
    }

    private fun parseSingleIdFromRpc(raw: String): Long? {
        val trimmed = raw.trim()
        trimmed.toLongOrNull()?.let { return it }
        runCatching {
            JSONArray(trimmed).optLong(0).takeIf { it > 0L }
        }.getOrNull()?.let { return it }
        runCatching {
            JSONObject(trimmed).optLong("id").takeIf { it > 0L }
        }.getOrNull()?.let { return it }
        return null
    }
}

private data class StrengthSetPayload(
    val setNumber: Int,
    val reps: Int?,
    val weightKg: Double?,
    val rpe: Double?,
    val restSec: Int?,
    val notes: String?
)

private fun StrengthExerciseDraft.deepCopy(): StrengthExerciseDraft = copy(
    sets = sets.map { it.copy() }
)

class AddWorkoutViewModelFactory(
    private val supabase: SupabaseClient,
    private val application: Application
) : ViewModelProvider.Factory {
    @Suppress("UNCHECKED_CAST")
    override fun <T : ViewModel> create(modelClass: Class<T>): T {
        if (modelClass != AddWorkoutViewModel::class.java) {
            error("Unknown ViewModel: ${modelClass.name}")
        }
        return AddWorkoutViewModel(supabase, application) as T
    }
}
