package com.lilru.liftr.ui.active

import android.util.Log
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.lilru.liftr.data.BackendContracts
import com.lilru.liftr.data.LiftrSupabase
import com.lilru.liftr.workout.StrengthFinishPersistence
import com.lilru.liftr.workout.WorkoutFinishSync
import com.lilru.liftr.workout.WorkoutProgramCache
import com.lilru.liftr.workout.WorkoutProgramCacheEntry
import com.lilru.liftr.workout.WorkoutStartSync
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Columns
import io.github.jan.supabase.postgrest.query.Order
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.serialization.SerialName
import kotlin.math.ceil
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import java.time.Instant
import java.util.Locale
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.JsonPrimitive
import com.lilru.liftr.ui.add.StrengthExerciseDraft
import com.lilru.liftr.ui.add.StrengthProgramItem
import com.lilru.liftr.ui.add.StrengthProgramSet
import com.lilru.liftr.ui.add.StrengthRoutineOverwriteCandidate
import com.lilru.liftr.ui.add.StrengthRoutineOverwritePrompt
import com.lilru.liftr.ui.add.StrengthSegmentPayload
import com.lilru.liftr.ui.add.StrengthSetDraft
import com.lilru.liftr.ui.add.StrengthSegmentDraft
import com.lilru.liftr.ui.add.applyStrengthRoutinePrescriptionUpdate
import com.lilru.liftr.ui.add.fetchStrengthRoutineOverwriteCandidate
import com.lilru.liftr.ui.add.weightSegmentsToJsonArray
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

data class ActiveStrengthSetLine(
    val setId: Int,
    val configId: Int,
    val setNumber: Int,
    val reps: Int?,
    val weightKg: Double?,
    val rpe: Double?,
    val restSec: Int?,
    val segmentsInRow: Int = 1,
    val weightSegments: JsonArray? = null
)

data class ActiveStrengthExerciseLine(
    val workoutExerciseId: Int,
    val displayName: String,
    val sets: List<ActiveStrengthSetLine>,
    val orderIndex: Int = 0,
    val supersetGroupId: String? = null,
    val supersetPosition: Int? = null
)

data class CompletedSetLine(
    val workoutExerciseId: Int,
    val configId: Int,
    val segmentsInRow: Int,
    val reps: Int?,
    val weightKg: Double?,
    val rpe: Double?,
    val restSec: Int?,
    val weightSegments: JsonArray? = null
)

private data class CollapsedPersistRow(
    val count: Int,
    val reps: Int?,
    val weightKg: Double?,
    val rpe: Double?,
    val restSec: Int?,
    val weightSegments: JsonArray? = null
)

data class ActiveStrengthUiState(
    val loading: Boolean = true,
    val error: String? = null,
    val workoutId: Int = 0,
    val exercises: List<ActiveStrengthExerciseLine> = emptyList(),
    /** Programa del compañero (vía RPC [FETCH_DUAL_LINKED_STRENGTH_WORKOUT_DATA]), solo lectura. */
    val guestExercises: List<ActiveStrengthExerciseLine> = emptyList(),
    val guestDataError: String? = null,
    val guest2Exercises: List<ActiveStrengthExerciseLine> = emptyList(),
    val guest2DataError: String? = null,
    val currentExerciseIndex: Int = 0,
    val currentSetIndex: Int = 0,
    val currentSetIndexByExerciseId: Map<Int, Int> = emptyMap(),
    /** Histórico de series completadas por workout_exercise_id en orden cronológico de finalización. */
    val completedSetsByExerciseId: Map<Int, List<CompletedSetLine>> = emptyMap(),
    val isResting: Boolean = false,
    val restSecondsLeft: Int = 0,
    /** Descanso activo por ejercicio (burbuja) aunque el índice actual sea otro. */
    val restSecondsLeftByExerciseId: Map<Int, Int> = emptyMap(),
    /** Segundos totales planificados al iniciar cada descanso (sector “quesito” en burbujas). */
    val restPlannedTotalSecByExerciseId: Map<Int, Int> = emptyMap(),
    val sessionElapsedSec: Int = 0,
    val isSessionPaused: Boolean = false,
    val finishing: Boolean = false,
    val completedEntirely: Boolean = false,
    val editRepsText: String = "",
    val editWeightText: String = "",
    val editRpeText: String = "",
    val editRestText: String = "",
    /** Easter egg alineado con [Liftr/ActiveStrengthWorkoutView.swift] (usuario `elborbla`). */
    val showElborblaCelebration: Boolean = false,
    /** Burbuja de énfasis fijada al primer descanso / primera serie sin descanso hasta cambiar de ejercicio (host). */
    val navEmphasisLockWorkoutExerciseId: Int? = null,
    val strengthRoutineOverwritePrompt: StrengthRoutineOverwritePrompt? = null,
    val startSyncStatus: WorkoutStartSync.Status = WorkoutStartSync.Status.IDLE
) {
    val atEnd: Boolean
        get() {
            if (exercises.isEmpty()) return true
            val li = currentExerciseIndex
            val si = currentSetIndex
            val ex = exercises.getOrNull(li) ?: return true
            return li == exercises.lastIndex && si == ex.sets.lastIndex
        }
}

class ActiveStrengthWorkoutViewModel(
    private val supabase: SupabaseClient,
    private val workoutId: Int,
    private val dualGuestWorkoutId: Int? = null,
    private val dualGuest2WorkoutId: Int? = null
) : ViewModel() {
    private val json = Json { ignoreUnknownKeys = true }
    private val _ui = MutableStateFlow(ActiveStrengthUiState(workoutId = workoutId))
    val uiState: StateFlow<ActiveStrengthUiState> = _ui.asStateFlow()

    private var restJob: Job? = null
    private var sessionJob: Job? = null
    /** epoch ms fin de descanso por workout_exercise_id */
    private val restDeadlineMsByExerciseId: MutableMap<Int, Long> = mutableMapOf()
    private val restPlannedTotalSecByExerciseIdMutable: MutableMap<Int, Int> = mutableMapOf()
    private val completedSetLines: MutableList<CompletedSetLine> = mutableListOf()
    private var hostWeRows: List<WeWire> = emptyList()
    private var pendingFinishOnDone: ((offlineQueued: Boolean) -> Unit)? = null
    private var accumulatedPausedSeconds: Int = 0
    private var pauseBeganEpochMs: Long? = null

    init {
        load()
        startSessionTimer()
    }

    override fun onCleared() {
        restJob?.cancel()
        sessionJob?.cancel()
        super.onCleared()
    }

    private fun startSessionTimer() {
        sessionJob?.cancel()
        sessionJob = viewModelScope.launch {
            while (isActive) {
                delay(1000)
                val cur = _ui.value
                if (cur.isSessionPaused) continue
                _ui.value = cur.copy(sessionElapsedSec = cur.sessionElapsedSec + 1)
            }
        }
    }

    fun toggleSessionPause() {
        val s = _ui.value
        if (s.finishing || s.loading) return
        if (s.isSessionPaused) {
            val began = pauseBeganEpochMs ?: run {
                _ui.value = s.copy(isSessionPaused = false)
                return
            }
            val now = System.currentTimeMillis()
            val dtMs = (now - began).coerceAtLeast(0L)
            pauseBeganEpochMs = null
            if (dtMs > 0L) {
                for (id in restDeadlineMsByExerciseId.keys.toList()) {
                    val end = restDeadlineMsByExerciseId[id] ?: continue
                    restDeadlineMsByExerciseId[id] = end + dtMs
                }
                accumulatedPausedSeconds =
                    (accumulatedPausedSeconds + (dtMs / 1000L).toInt()).coerceAtMost(Int.MAX_VALUE / 4)
            }
            _ui.value = withSyncedEditFields(syncRestDeadlinesToUi(s.copy(isSessionPaused = false)))
        } else {
            pauseBeganEpochMs = System.currentTimeMillis()
            _ui.value = s.copy(isSessionPaused = true)
        }
    }

    fun updateStartSyncStatus(status: WorkoutStartSync.Status) {
        _ui.value = _ui.value.copy(startSyncStatus = status)
    }

    private fun hydrateFromProgramCache(entry: WorkoutProgramCacheEntry): List<ActiveStrengthExerciseLine> {
        return entry.exercises.mapNotNull { ex ->
            val sets = ex.sets.map { s ->
                val sid = -(ex.workoutExerciseId * 1000 + s.setNumber)
                ActiveStrengthSetLine(
                    setId = sid,
                    configId = sid,
                    setNumber = s.setNumber,
                    reps = s.reps,
                    weightKg = s.weightKg,
                    rpe = s.rpe,
                    restSec = s.restSec
                )
            }
            if (sets.isEmpty()) return@mapNotNull null
            ActiveStrengthExerciseLine(
                workoutExerciseId = ex.workoutExerciseId,
                displayName = ex.displayName,
                sets = sets
            )
        }
    }

    fun load() {
        viewModelScope.launch {
            val ctx = LiftrSupabase.appContext
            val cachedLines = ctx?.let { c ->
                WorkoutProgramCache.entry(c, workoutId)?.let { hydrateFromProgramCache(it) }
            }.orEmpty()
            val hydratedFromCache = cachedLines.isNotEmpty()
            _ui.value = _ui.value.copy(
                loading = !hydratedFromCache,
                error = null,
                completedEntirely = false,
                exercises = if (hydratedFromCache) cachedLines else _ui.value.exercises,
                startSyncStatus = WorkoutStartSync.status(workoutId)
            )
            runCatching {
                supabase.auth.currentUserOrNull()?.id ?: error("No session")
                if (!WorkoutStartSync.isPending(workoutId)) {
                    patchWorkoutStartedAtNow(supabase, workoutId)
                }

                val wRes = supabase
                    .from(BackendContracts.Tables.WORKOUT_EXERCISES)
                    .select(
                        columns = Columns.raw(
                            "id, exercise_id, order_index, superset_group_id, superset_position, notes, custom_name"
                        )
                    ) {
                        filter { eq("workout_id", workoutId) }
                        order("order_index", Order.ASCENDING)
                    }
                val weRows = decodeFlexibleList<WeWire>(wRes.data)
                hostWeRows = weRows
                if (weRows.isEmpty()) {
                    accumulatedPausedSeconds = 0
                    pauseBeganEpochMs = null
                    _ui.value = _ui.value.copy(
                        loading = false,
                        error = null,
                        exercises = emptyList(),
                        isSessionPaused = false
                    )
                    return@runCatching
                }
                val exIds = weRows.map { it.exerciseId }.distinct()
                val namesById = loadExerciseNames(exIds)
                val weIds = weRows.map { it.id }

                val sRes = supabase
                    .from(BackendContracts.Tables.EXERCISE_SETS)
                    .select(columns = Columns.raw("id, workout_exercise_id, set_number, reps, weight_kg, rpe, rest_sec, weight_segments")) {
                        filter { isIn("workout_exercise_id", weIds) }
                        order("set_number", Order.ASCENDING)
                        order("id", Order.ASCENDING)
                    }
                val setRows = decodeFlexibleList<SetWire>(sRes.data)
                val byWe = setRows.groupBy { it.workoutExerciseId }
                    .mapValues { (_, v) -> v.sortedBy { it.id } }

                val lines = weRows.mapNotNull { we ->
                    val name = we.customName?.trim()?.takeIf { it.isNotEmpty() }
                        ?: namesById[we.exerciseId]
                        ?: "Exercise ${we.exerciseId}"
                    val setLines = expandSetsForActiveUi(byWe[we.id] ?: emptyList())
                    if (setLines.isEmpty()) return@mapNotNull null
                    ActiveStrengthExerciseLine(
                        workoutExerciseId = we.id,
                        displayName = name,
                        sets = setLines,
                        orderIndex = we.orderIndex,
                        supersetGroupId = we.supersetGroupId,
                        supersetPosition = we.supersetPosition
                    )
                }
                if (lines.isEmpty()) {
                    accumulatedPausedSeconds = 0
                    pauseBeganEpochMs = null
                    _ui.value = _ui.value.copy(
                        loading = false,
                        error = null,
                        exercises = emptyList(),
                        isSessionPaused = false
                    )
                    return@runCatching
                }
                var guestLines: List<ActiveStrengthExerciseLine> = emptyList()
                var guestErr: String? = null
                var g2Lines: List<ActiveStrengthExerciseLine> = emptyList()
                var g2Err: String? = null
                dualGuestWorkoutId?.takeIf { it > 0 }?.let { gw ->
                    val r = runCatching { buildGuestProgramFromDualRpc(gw) }
                    r.onSuccess { guestLines = it }
                    r.onFailure { e -> guestErr = e.message?.take(220) ?: e::class.java.simpleName }
                }
                dualGuest2WorkoutId?.takeIf { it > 0 }?.let { g2w ->
                    val r = runCatching { buildGuestProgramFromDualRpc(g2w) }
                    r.onSuccess { g2Lines = it }
                    r.onFailure { e -> g2Err = e.message?.take(220) ?: e::class.java.simpleName }
                }
                val setIndexMap = lines.associate { it.workoutExerciseId to 0 }
                restJob?.cancel()
                restJob = null
                restDeadlineMsByExerciseId.clear()
                restPlannedTotalSecByExerciseIdMutable.clear()
                accumulatedPausedSeconds = 0
                pauseBeganEpochMs = null
                _ui.value = withSyncedEditFields(
                    _ui.value.copy(
                        loading = false,
                        error = null,
                        exercises = lines,
                        currentExerciseIndex = 0,
                        currentSetIndex = 0,
                        currentSetIndexByExerciseId = setIndexMap,
                        guestExercises = guestLines,
                        guestDataError = guestErr,
                        guest2Exercises = g2Lines,
                        guest2DataError = g2Err,
                        isResting = false,
                        restSecondsLeft = 0,
                        restSecondsLeftByExerciseId = emptyMap(),
                        restPlannedTotalSecByExerciseId = emptyMap(),
                        navEmphasisLockWorkoutExerciseId = null,
                        isSessionPaused = false
                    )
                )
            }.onFailure { e ->
                hostWeRows = emptyList()
                Log.e(TAG, "load failed", e)
                accumulatedPausedSeconds = 0
                pauseBeganEpochMs = null
                val keepCached = _ui.value.exercises.isNotEmpty()
                _ui.value = _ui.value.copy(
                    loading = false,
                    error = if (keepCached) null else e.message?.take(280) ?: e::class.java.simpleName,
                    isSessionPaused = false
                )
            }
        }
    }

    private suspend fun buildGuestProgramFromDualRpc(guestWorkoutId: Int): List<ActiveStrengthExerciseLine> {
        val params = buildJsonObject {
            put("p_workout_id", JsonPrimitive(guestWorkoutId.toLong()))
        }
        val res = supabase.postgrest.rpc(
            BackendContracts.Rpc.FETCH_DUAL_LINKED_STRENGTH_WORKOUT_DATA,
            params
        ) { }
        val raw = res.data.trim()
        val el = json.parseToJsonElement(raw)
        val obj: JsonObject = when (el) {
            is JsonObject -> el
            is JsonArray -> el.firstOrNull()?.let { it as? JsonObject }
                ?: error("Invalid dual response")
            else -> error("Invalid dual response")
        }
        val bundle = json.decodeFromString<DualLinkedBundle>(obj.toString())
        val byWe = bundle.sets.groupBy { it.workoutExerciseId }
            .mapValues { (_, v) -> v.sortedBy { it.id } }
        return bundle.exercises
            .sortedBy { it.orderIndex }
            .mapNotNull { ex ->
                val name = ex.customName?.trim()?.takeIf { it.isNotEmpty() }
                    ?: ex.exercises?.name?.trim()?.takeIf { it.isNotEmpty() }
                    ?: "Exercise ${ex.exerciseId}"
                val setLines = expandSetsForActiveUi(byWe[ex.id] ?: emptyList())
                if (setLines.isEmpty()) return@mapNotNull null
                ActiveStrengthExerciseLine(
                    workoutExerciseId = ex.id,
                    displayName = name,
                    sets = setLines,
                    orderIndex = ex.orderIndex,
                    supersetGroupId = ex.supersetGroupId,
                    supersetPosition = ex.supersetPosition
                )
            }
    }

    private suspend fun loadExerciseNames(ids: List<Long>): Map<Long, String> {
        if (ids.isEmpty()) return emptyMap()
        val res = supabase
            .from(BackendContracts.Tables.EXERCISES)
            .select(columns = Columns.raw("id, name, name_en, name_es")) {
                filter { isIn("id", ids) }
            }
        val rows = decodeFlexibleList<ExerciseNameWire>(res.data)
        return rows.associate { row ->
            val label = row.nameEs?.trim()?.takeIf { it.isNotEmpty() }
                ?: row.nameEn?.trim()?.takeIf { it.isNotEmpty() }
                ?: row.name
            row.id to (label ?: "Exercise")
        }
    }

    private fun expandSetsForActiveUi(rows: List<SetWire>): List<ActiveStrengthSetLine> {
        if (rows.isEmpty()) return emptyList()
        val sortedRows = rows.sortedWith(compareBy<SetWire> { it.setNumber }.thenBy { it.id })
        val expanded = mutableListOf<ActiveStrengthSetLine>()
        sortedRows.forEach { row ->
            val k = row.weightSegments?.takeIf { it.size >= 2 }?.size ?: 1
            val macro = row.setNumber.coerceAtLeast(0)
            repeat(macro) { repIdx ->
                val firstSeg = row.weightSegments?.firstOrNull()?.jsonObject
                val r0 = firstSeg?.get("reps")?.jsonPrimitive?.content?.toIntOrNull()
                val w0 = firstSeg?.get("weight_kg")?.jsonPrimitive?.content?.toDoubleOrNull()
                val sequentialNumber = expanded.size + 1
                expanded += ActiveStrengthSetLine(
                    setId = row.id * 100000 + repIdx + 1,
                    configId = row.id,
                    setNumber = sequentialNumber,
                    reps = r0 ?: row.reps,
                    weightKg = w0 ?: row.weightKg,
                    rpe = row.rpe,
                    restSec = row.restSec,
                    segmentsInRow = k,
                    weightSegments = row.weightSegments
                )
            }
        }
        return expanded
    }

    fun setEditRepsText(value: String) {
        _ui.value = _ui.value.copy(editRepsText = value)
    }

    fun setEditWeightText(value: String) {
        _ui.value = _ui.value.copy(editWeightText = value)
    }

    fun setEditRpeText(value: String) {
        _ui.value = _ui.value.copy(editRpeText = value)
    }

    fun setEditRestText(value: String) {
        _ui.value = _ui.value.copy(editRestText = value)
    }

    fun applyCurrentSetEdits(expandedIndexOverride: Int? = null) {
        val s = _ui.value
        val ex = s.exercises.getOrNull(s.currentExerciseIndex) ?: return
        val setIndex = expandedIndexOverride
            ?: s.currentSetIndexByExerciseId[ex.workoutExerciseId]
            ?: s.currentSetIndex
        val reps = s.editRepsText.trim().toIntOrNull()
        val weight = s.editWeightText.trim().replace(',', '.').toDoubleOrNull()
        val rpe = s.editRpeText.trim().replace(',', '.').toDoubleOrNull()
        val rest = s.editRestText.trim().toIntOrNull()?.coerceAtLeast(0)
        val nextSets = updateBlockForExpandedIndex(
            sets = ex.sets,
            expandedIndex = setIndex,
            reps = reps,
            weightKg = weight,
            rpe = rpe,
            restSec = rest
        )
        val nextEx = ex.copy(sets = nextSets)
        val nextExercises = s.exercises.mapIndexed { idx, line ->
            if (idx == s.currentExerciseIndex) nextEx else line
        }
        _ui.value = withSyncedEditFields(
            s.copy(
                exercises = nextExercises,
                completedEntirely = false
            )
        )
    }

    fun convertCurrentSetToDropSet(expandedIndexOverride: Int? = null) {
        val s = _ui.value
        if (s.loading || s.finishing || s.isResting) return
        val ex = s.exercises.getOrNull(s.currentExerciseIndex) ?: return
        val setIndex = expandedIndexOverride
            ?: s.currentSetIndexByExerciseId[ex.workoutExerciseId]
            ?: s.currentSetIndex
        val cur = ex.sets.getOrNull(setIndex) ?: return
        if (cur.weightSegments != null && cur.weightSegments.size >= 2) return
        val r0 = cur.reps ?: 10
        val w0 = cur.weightKg ?: 0.0
        val ws = weightSegmentsToJsonArray(
            listOf(
                StrengthSegmentPayload(r0, w0),
                StrengthSegmentPayload(r0, 0.0)
            )
        )
        val newConfigId = nextSyntheticConfigId(ex.sets)
        val nextSets = ex.sets.mapIndexed { idx, line ->
            if (idx != setIndex) line
            else line.copy(
                configId = newConfigId,
                reps = r0,
                weightKg = w0,
                segmentsInRow = 2,
                weightSegments = ws
            )
        }
        val nextEx = ex.copy(sets = renumberExpandedSets(nextSets))
        val nextExercises = s.exercises.mapIndexed { idx, line ->
            if (idx == s.currentExerciseIndex) nextEx else line
        }
        _ui.value = withSyncedEditFields(s.copy(exercises = nextExercises, completedEntirely = false))
    }

    fun applyCurrentDropSetEdits(
        segments: List<StrengthSegmentPayload>,
        expandedIndexOverride: Int? = null
    ) {
        val s = _ui.value
        if (s.loading || s.finishing) return
        val ex = s.exercises.getOrNull(s.currentExerciseIndex) ?: return
        val setIndex = expandedIndexOverride
            ?: s.currentSetIndexByExerciseId[ex.workoutExerciseId]
            ?: s.currentSetIndex
        if (ex.sets.getOrNull(setIndex) == null) return
        if (segments.size < 2) return

        val ws = weightSegmentsToJsonArray(segments)
        val r0 = segments.first().reps
        val w0 = segments.first().weightKg

        val newConfigId = nextSyntheticConfigId(ex.sets)
        val nextSets = ex.sets.mapIndexed { idx, line ->
            if (idx != setIndex) line
            else line.copy(
                configId = newConfigId,
                reps = r0,
                weightKg = w0,
                segmentsInRow = segments.size,
                weightSegments = ws
            )
        }
        val nextEx = ex.copy(sets = renumberExpandedSets(nextSets))
        val nextExercises = s.exercises.mapIndexed { idx, line ->
            if (idx == s.currentExerciseIndex) nextEx else line
        }
        _ui.value = withSyncedEditFields(s.copy(exercises = nextExercises, completedEntirely = false))
    }

    fun convertCurrentSetToNormalSet(
        reps: Int,
        weightKg: Double,
        expandedIndexOverride: Int? = null
    ) {
        val s = _ui.value
        if (s.loading || s.finishing) return
        val ex = s.exercises.getOrNull(s.currentExerciseIndex) ?: return
        val setIndex = expandedIndexOverride
            ?: s.currentSetIndexByExerciseId[ex.workoutExerciseId]
            ?: s.currentSetIndex
        if (ex.sets.getOrNull(setIndex) == null) return

        val newConfigId = nextSyntheticConfigId(ex.sets)
        val nextSets = ex.sets.mapIndexed { idx, line ->
            if (idx != setIndex) line
            else line.copy(
                configId = newConfigId,
                reps = reps,
                weightKg = weightKg,
                segmentsInRow = 1,
                weightSegments = null
            )
        }
        val nextEx = ex.copy(sets = renumberExpandedSets(nextSets))
        val nextExercises = s.exercises.mapIndexed { idx, line ->
            if (idx == s.currentExerciseIndex) nextEx else line
        }
        _ui.value = withSyncedEditFields(s.copy(exercises = nextExercises, completedEntirely = false))
    }

    fun addSetToCurrentExercise() {
        val s = _ui.value
        if (s.loading || s.finishing || s.isResting) return
        val ex = s.exercises.getOrNull(s.currentExerciseIndex) ?: return
        val nextSets = appendOneSetToExpandedSets(ex.sets)
        val nextEx = ex.copy(sets = nextSets)
        val nextExercises = s.exercises.mapIndexed { idx, line ->
            if (idx == s.currentExerciseIndex) nextEx else line
        }
        _ui.value = withSyncedEditFields(s.copy(exercises = nextExercises, completedEntirely = false))
    }

    fun removeSetFromCurrentExercise() {
        val s = _ui.value
        if (s.loading || s.finishing || s.isResting) return
        val ex = s.exercises.getOrNull(s.currentExerciseIndex) ?: return
        if (ex.sets.size <= 1) return
        val nextSets = removeOneSetFromExpandedSets(ex.sets)
        val oldIdx = s.currentSetIndexByExerciseId[ex.workoutExerciseId] ?: s.currentSetIndex
        val nextSetIndex = oldIdx.coerceAtMost(nextSets.lastIndex)
        val nextEx = ex.copy(sets = nextSets)
        val nextExercises = s.exercises.mapIndexed { idx, line ->
            if (idx == s.currentExerciseIndex) nextEx else line
        }
        val nextMap = s.currentSetIndexByExerciseId.toMutableMap().apply {
            put(ex.workoutExerciseId, nextSetIndex)
        }
        _ui.value = withSyncedEditFields(
            s.copy(
                exercises = nextExercises,
                currentSetIndex = nextSetIndex,
                currentSetIndexByExerciseId = nextMap,
                completedEntirely = areAllExercisesCompleted(nextExercises, nextMap)
            )
        )
    }

    fun skipRest() {
        val s = _ui.value
        val cur = s.exercises.getOrNull(s.currentExerciseIndex) ?: return
        restDeadlineMsByExerciseId.remove(cur.workoutExerciseId)
        restPlannedTotalSecByExerciseIdMutable.remove(cur.workoutExerciseId)
        restJob?.cancel()
        restJob = null
        _ui.value = withSyncedEditFields(syncRestDeadlinesToUi(s))
        if (restDeadlineMsByExerciseId.isNotEmpty()) startRestTicker()
    }

    /**
     * Marca la serie actual como hecha; si hay descanso, entra en cuenta atrás; si no, avanza.
     */
    fun onSetDone() {
        val s = _ui.value
        if (s.isResting || s.loading || s.finishing) return
        if (s.exercises.isEmpty()) return
        val ex = s.exercises.getOrNull(s.currentExerciseIndex) ?: return
        val setIndex = s.currentSetIndexByExerciseId[ex.workoutExerciseId] ?: s.currentSetIndex
        val set = ex.sets.getOrNull(setIndex) ?: return
        val reps = s.editRepsText.trim().toIntOrNull() ?: set.reps
        val wRaw = s.editWeightText.trim().replace(',', '.')
        val weightKg = wRaw.toDoubleOrNull() ?: set.weightKg
        val rRaw = s.editRpeText.trim().replace(',', '.')
        val rpe = rRaw.toDoubleOrNull() ?: set.rpe
        val completedLine = CompletedSetLine(
            workoutExerciseId = ex.workoutExerciseId,
            configId = set.configId,
            segmentsInRow = set.segmentsInRow,
            reps = reps,
            weightKg = weightKg,
            rpe = rpe,
            restSec = set.restSec,
            weightSegments = set.weightSegments
        )
        completedSetLines.add(completedLine)
        val nextSetIndex = (setIndex + 1).coerceAtMost(ex.sets.size)
        val nextMap = s.currentSetIndexByExerciseId.toMutableMap().apply {
            put(ex.workoutExerciseId, nextSetIndex)
        }
        val nextCompletedMap = s.completedSetsByExerciseId.toMutableMap().apply {
            val prior = this[ex.workoutExerciseId].orEmpty()
            this[ex.workoutExerciseId] = prior + completedLine
        }
        val allDone = areAllExercisesCompleted(s.exercises, nextMap)
        val newEmphasisLock = s.navEmphasisLockWorkoutExerciseId ?: ex.workoutExerciseId
        val shouldRest = shouldStartRestAfterCompletingSet(ex, s.exercises, setIndex)
        val nextMemberIdx = if (!shouldRest) {
            nextSupersetMemberExerciseIndex(ex, s.exercises, setIndex, nextMap)
        } else {
            null
        }
        val nextExerciseIndex = nextMemberIdx ?: s.currentExerciseIndex
        val nextMember = s.exercises.getOrNull(nextExerciseIndex)
        val syncedSetIndex = nextMember?.let { nextMap[it.workoutExerciseId] ?: it.sets.size.coerceAtLeast(0) }
            ?: nextSetIndex
        val baseState = withSyncedEditFields(
            s.copy(
                currentExerciseIndex = nextExerciseIndex,
                currentSetIndex = syncedSetIndex,
                currentSetIndexByExerciseId = nextMap,
                completedSetsByExerciseId = nextCompletedMap,
                completedEntirely = allDone,
                navEmphasisLockWorkoutExerciseId = newEmphasisLock
            )
        )
        val rest = if (shouldRest) set.restSec?.takeIf { it > 0 } ?: 0 else 0
        if (rest > 0) {
            val end = System.currentTimeMillis() + rest * 1000L
            restDeadlineMsByExerciseId[ex.workoutExerciseId] = end
            restPlannedTotalSecByExerciseIdMutable[ex.workoutExerciseId] = rest
            _ui.value = withSyncedEditFields(syncRestDeadlinesToUi(baseState))
            startRestTicker()
        } else {
            _ui.value = baseState
        }
    }

    fun goToExercise(index: Int) {
        val s = _ui.value
        if (s.loading || s.finishing) return
        val clamped = index.coerceIn(0, s.exercises.lastIndex)
        val ex = s.exercises.getOrNull(clamped) ?: return
        val setIdx = (s.currentSetIndexByExerciseId[ex.workoutExerciseId] ?: 0)
            .coerceIn(0, ex.sets.size)
        _ui.value = withSyncedEditFields(
            syncRestDeadlinesToUi(
                s.copy(
                    currentExerciseIndex = clamped,
                    currentSetIndex = setIdx
                )
            )
        )
    }

    fun goToNextExercise() {
        val s = _ui.value
        val groups = strengthDisplayGroups(s.exercises)
        val gi = displayGroupIndexForExerciseIndex(s.currentExerciseIndex, s.exercises) ?: return
        if (gi + 1 >= groups.size) return
        val nextIdx = groups[gi + 1].exerciseIndices.firstOrNull() ?: return
        _ui.value = _ui.value.copy(navEmphasisLockWorkoutExerciseId = null)
        goToExercise(nextIdx)
    }

    fun goToPreviousExercise() {
        val s = _ui.value
        if (s.currentExerciseIndex > 0) {
            goToExercise(s.currentExerciseIndex - 1)
        }
    }

    /**
     * Paridad con iOS: al reabrir Active, la sesión visual empieza desde 0 aunque los datos ya
     * editados (reps/peso/rpe/rest) permanezcan guardados en memoria/BD.
     */
    fun resetSessionProgress() {
        restJob?.cancel()
        restJob = null
        restDeadlineMsByExerciseId.clear()
        restPlannedTotalSecByExerciseIdMutable.clear()
        completedSetLines.clear()
        accumulatedPausedSeconds = 0
        pauseBeganEpochMs = null
        val s = _ui.value
        val map = s.exercises.associate { it.workoutExerciseId to 0 }
        _ui.value = withSyncedEditFields(
            s.copy(
                currentExerciseIndex = 0,
                currentSetIndex = 0,
                currentSetIndexByExerciseId = map,
                completedSetsByExerciseId = emptyMap(),
                isResting = false,
                restSecondsLeft = 0,
                restSecondsLeftByExerciseId = emptyMap(),
                restPlannedTotalSecByExerciseId = emptyMap(),
                completedEntirely = false,
                navEmphasisLockWorkoutExerciseId = null,
                isSessionPaused = false
            )
        )
    }

    private fun syncRestDeadlinesToUi(s: ActiveStrengthUiState): ActiveStrengthUiState {
        val now = System.currentTimeMillis()
        restDeadlineMsByExerciseId.keys.toList().forEach { id ->
            val end = restDeadlineMsByExerciseId[id] ?: return@forEach
            if (end <= now) {
                restDeadlineMsByExerciseId.remove(id)
                restPlannedTotalSecByExerciseIdMutable.remove(id)
            }
        }
        val secMap = restDeadlineMsByExerciseId.mapValues { (_, endMs) ->
            kotlin.math.max(0, ceil((endMs - now) / 1000.0).toInt())
        }.filterValues { it > 0 }
        secMap.keys.forEach { id ->
            if (restPlannedTotalSecByExerciseIdMutable[id] == null) {
                restPlannedTotalSecByExerciseIdMutable[id] = kotlin.math.max(1, secMap[id] ?: 1)
            }
        }
        restPlannedTotalSecByExerciseIdMutable.keys.toList().forEach { id ->
            if (id !in secMap) restPlannedTotalSecByExerciseIdMutable.remove(id)
        }
        val cur = s.exercises.getOrNull(s.currentExerciseIndex)
        val curId = cur?.workoutExerciseId
        val left = curId?.let { secMap[it] } ?: 0
        return s.copy(
            restSecondsLeftByExerciseId = secMap,
            restPlannedTotalSecByExerciseId = restPlannedTotalSecByExerciseIdMutable.toMap(),
            isResting = left > 0,
            restSecondsLeft = left
        )
    }

    private fun startRestTicker() {
        restJob?.cancel()
        restJob = viewModelScope.launch {
            while (isActive && restDeadlineMsByExerciseId.isNotEmpty()) {
                delay(1000)
                if (_ui.value.isSessionPaused) continue
                _ui.value = withSyncedEditFields(syncRestDeadlinesToUi(_ui.value))
            }
        }
    }

    private fun withSyncedEditFields(s: ActiveStrengthUiState): ActiveStrengthUiState {
        val ex = s.exercises.getOrNull(s.currentExerciseIndex)
        val setIndex = ex?.let {
            (s.currentSetIndexByExerciseId[it.workoutExerciseId] ?: s.currentSetIndex).coerceIn(0, it.sets.size)
        } ?: 0
        val set = ex?.sets?.getOrNull(setIndex)
        if (set == null) {
            return s.copy(currentSetIndex = setIndex, editRepsText = "", editWeightText = "", editRpeText = "", editRestText = "")
        }
        return s.copy(
            currentSetIndex = setIndex,
            editRepsText = set.reps?.toString() ?: "",
            editWeightText = formatDoubleField(set.weightKg),
            editRpeText = set.rpe?.let { r -> if (r == r.toInt().toDouble()) r.toInt().toString() else String.format("%.1f", r) } ?: "",
            editRestText = set.restSec?.toString() ?: ""
        )
    }

    private fun areAllExercisesCompleted(
        exercises: List<ActiveStrengthExerciseLine>,
        setMap: Map<Int, Int>
    ): Boolean {
        if (exercises.isEmpty()) return false
        return exercises.all { ex ->
            (setMap[ex.workoutExerciseId] ?: 0) >= ex.sets.size
        }
    }

    private fun formatDoubleField(d: Double?): String {
        if (d == null) return ""
        return if (d == d.toInt().toDouble()) d.toInt().toString() else String.format(Locale.US, "%.1f", d)
    }

    fun dismissStrengthRoutineOverwrite() {
        pendingFinishOnDone = null
        _ui.value = _ui.value.copy(strengthRoutineOverwritePrompt = null)
    }

    fun confirmStrengthRoutineOverwrite(updateRoutine: Boolean) {
        val cb = pendingFinishOnDone ?: return
        val prompt = _ui.value.strengthRoutineOverwritePrompt ?: return
        pendingFinishOnDone = null
        _ui.value = _ui.value.copy(strengthRoutineOverwritePrompt = null)
        val routineUpdate: Pair<Long, List<StrengthExerciseDraft>>? =
            if (updateRoutine) prompt.routineId to draftsForRoutineUpdateFromPerformed() else null
        viewModelScope.launch {
            runFinishPersistence(onDone = cb, routineUpdate = routineUpdate)
        }
    }

    fun finishWorkout(onDone: (offlineQueued: Boolean) -> Unit) {
        if (_ui.value.finishing) return
        viewModelScope.launch {
            val uid = supabase.auth.currentUserOrNull()?.id
            if (uid != null && hostWeRows.isNotEmpty()) {
                val proposed = programItemsForRoutineOverwrite()
                if (proposed != null) {
                    val candidate = runCatching {
                        fetchStrengthRoutineOverwriteCandidate(
                            supabase,
                            uid,
                            proposed
                        ) { eid ->
                            val we = hostWeRows.firstOrNull { it.exerciseId == eid }
                            we?.customName?.trim()?.takeIf { it.isNotEmpty() }
                                ?: "Exercise ${we?.exerciseId ?: eid}"
                        }
                    }.getOrNull() ?: StrengthRoutineOverwriteCandidate.None
                    if (candidate is StrengthRoutineOverwriteCandidate.Prompt) {
                        pendingFinishOnDone = onDone
                        _ui.value = _ui.value.copy(strengthRoutineOverwritePrompt = candidate.value)
                        return@launch
                    }
                }
            }
            runFinishPersistence(onDone = onDone, routineUpdate = null)
        }
    }

    private suspend fun runFinishPersistence(
        onDone: (offlineQueued: Boolean) -> Unit,
        routineUpdate: Pair<Long, List<StrengthExerciseDraft>>?
    ) {
        _ui.value = _ui.value.copy(finishing = true, error = null)
        val openPauseSec = pauseBeganEpochMs?.let {
            ((System.currentTimeMillis() - it).coerceAtLeast(0L) / 1000L).toInt()
        } ?: 0
        val pausedSecSnapshot = accumulatedPausedSeconds
        val res = runCatching {
            val userId = supabase.auth.currentUserOrNull()?.id ?: error("No session")
            StrengthFinishPersistence.persist(
                supabase = supabase,
                workoutId = workoutId,
                completedSetLines = completedSetLines.toList(),
                accumulatedPausedSeconds = pausedSecSnapshot,
                openPauseSec = openPauseSec
            )
            if (routineUpdate != null) {
                applyStrengthRoutinePrescriptionUpdate(
                    supabase,
                    userId,
                    routineUpdate.first,
                    routineUpdate.second
                )
            }
        }
        if (res.isFailure) {
            val e = res.exceptionOrNull()!!
            Log.e(TAG, "finish failed", e)
            if (WorkoutFinishSync.isRetriable(e)) {
                LiftrSupabase.appContext?.let { ctx ->
                    WorkoutFinishSync.enqueue(
                        ctx,
                        workoutId,
                        pausedSecSnapshot,
                        openPauseSec,
                        completedSetLines.toList()
                    )
                }
                _ui.value = _ui.value.copy(finishing = false, error = null)
                onDone(true)
                return
            }
            _ui.value = _ui.value.copy(
                finishing = false,
                error = e.message?.take(280) ?: e::class.java.simpleName
            )
            return
        }
        val celebrate = checkElborblaCelebration()
        _ui.value = _ui.value.copy(
            finishing = false,
            showElborblaCelebration = celebrate
        )
        if (!celebrate) {
            onDone(false)
        }
    }

    private fun programItemsForRoutineOverwrite(): List<StrengthProgramItem>? {
        if (hostWeRows.isEmpty()) return null
        val items = mutableListOf<StrengthProgramItem>()
        for (we in hostWeRows.sortedBy { it.orderIndex }) {
            val lines = completedSetLines.filter { it.workoutExerciseId == we.id }
            if (lines.isEmpty()) return null
            val rows = chunkCompletedLines(lines).flatMap { chunkToPersistRows(it) }
            val sets = rows.mapIndexed { idx, row ->
                val segList = row.weightSegments?.takeIf { it.size >= 2 }?.mapNotNull { el ->
                    val o = el.jsonObject
                    val r = o["reps"]?.jsonPrimitive?.content?.toIntOrNull() ?: return@mapNotNull null
                    val w = o["weight_kg"]?.jsonPrimitive?.content?.toDoubleOrNull() ?: return@mapNotNull null
                    StrengthSegmentPayload(r, w)
                }?.takeIf { it.size >= 2 }
                StrengthProgramSet(
                    setNumber = idx + 1,
                    reps = row.reps,
                    weightKg = row.weightKg,
                    rpe = row.rpe,
                    restSec = row.restSec,
                    notes = null,
                    weightSegments = segList
                )
            }
            items.add(
                StrengthProgramItem(
                    exerciseId = we.exerciseId,
                    orderIndex = we.orderIndex,
                    notes = we.notes,
                    customName = we.customName,
                    sets = sets
                )
            )
        }
        return items
    }

    private fun draftsForRoutineUpdateFromPerformed(): List<StrengthExerciseDraft> {
        return hostWeRows.sortedBy { it.orderIndex }.map { we ->
            val lines = completedSetLines.filter { it.workoutExerciseId == we.id }
            val custom = we.customName?.trim().orEmpty()
            val rows = chunkCompletedLines(lines).flatMap { chunkToPersistRows(it) }
            StrengthExerciseDraft(
                exerciseId = we.exerciseId,
                customName = custom,
                exerciseName = "",
                notes = we.notes.orEmpty(),
                sets = rows.map { row -> strengthSetDraftFromPersistRow(row) }
            )
        }
    }

    private fun strengthSetDraftFromPersistRow(row: CollapsedPersistRow): StrengthSetDraft {
        val arr = row.weightSegments
        val segs = if (arr == null || arr.size < 2) {
            emptyList()
        } else {
            arr.mapNotNull { el ->
                val o = el.jsonObject
                val r = o["reps"]?.jsonPrimitive?.content?.toIntOrNull() ?: return@mapNotNull null
                val w = o["weight_kg"]?.jsonPrimitive?.content?.toDoubleOrNull() ?: return@mapNotNull null
                StrengthSegmentDraft(
                    repsText = r.toString(),
                    weightText = formatDoubleField(w)
                )
            }.takeIf { it.size == arr.size && it.size >= 2 } ?: emptyList()
        }
        val r0 = segs.firstOrNull()?.repsText ?: row.reps?.toString() ?: ""
        val w0 = segs.firstOrNull()?.weightText ?: formatDoubleField(row.weightKg)
        return StrengthSetDraft(
            setNumber = row.count.coerceIn(1, 99),
            repsText = r0,
            weightText = w0,
            rpeText = row.rpe?.let { r ->
                if (r == r.toInt().toDouble()) r.toInt().toString() else String.format(Locale.US, "%.1f", r)
            } ?: "",
            restSecText = row.restSec?.toString() ?: "",
            segments = segs
        )
    }

    private suspend fun checkElborblaCelebration(): Boolean {
        val uid = supabase.auth.currentUserOrNull()?.id ?: return false
        return runCatching {
            val r = supabase.from(BackendContracts.Tables.PROFILES)
                .select(columns = Columns.raw("username")) {
                    filter { eq("user_id", uid) }
                    limit(1)
                }
            val rows = decodeFlexibleList<UsernameRow>(r.data)
            val u = rows.firstOrNull()?.username?.trim()?.lowercase(Locale.ROOT) ?: return@runCatching false
            u == ELBORBLA_USER
        }.getOrDefault(false)
    }

    private data class LegacyLineKey(val reps: Int?, val weightKg: Double?, val rpe: Double?, val restSec: Int?)
    private data class SegmentLineKey(
        val reps: Int?,
        val weightKg: Double?,
        val rpe: Double?,
        val restSec: Int?,
        val weightSegmentsRaw: String?
    )

    private fun chunkCompletedLines(lines: List<CompletedSetLine>): List<List<CompletedSetLine>> {
        if (lines.isEmpty()) return emptyList()
        val out = mutableListOf<MutableList<CompletedSetLine>>()
        var cur = mutableListOf(lines.first())
        for (i in 1 until lines.size) {
            val line = lines[i]
            if (line.configId == cur.first().configId) {
                cur += line
            } else {
                out += cur
                cur = mutableListOf(line)
            }
        }
        out += cur
        return out
    }

    private fun collapseLegacyChunk(chunk: List<CompletedSetLine>): List<CollapsedPersistRow> {
        if (chunk.isEmpty()) return emptyList()
        val collapsed = mutableListOf<CollapsedPersistRow>()
        var currentKey: LegacyLineKey? = null
        var count = 0
        chunk.forEach { line ->
            val key = LegacyLineKey(line.reps, line.weightKg, line.rpe, line.restSec)
            if (currentKey != null && currentKey == key) {
                count += 1
            } else {
                if (currentKey != null) {
                    collapsed += CollapsedPersistRow(count, currentKey!!.reps, currentKey!!.weightKg, currentKey!!.rpe, currentKey!!.restSec, null)
                }
                currentKey = key
                count = 1
            }
        }
        if (currentKey != null) {
            collapsed += CollapsedPersistRow(count, currentKey!!.reps, currentKey!!.weightKg, currentKey!!.rpe, currentKey!!.restSec, null)
        }
        return collapsed
    }

    private fun collapseSegmentChunk(chunk: List<CompletedSetLine>): List<CollapsedPersistRow> {
        if (chunk.isEmpty()) return emptyList()
        val collapsed = mutableListOf<CollapsedPersistRow>()
        var currentKey: SegmentLineKey? = null
        var currentSegs: JsonArray? = null
        var count = 0

        fun flush() {
            val k = currentKey ?: return
            collapsed += CollapsedPersistRow(
                count = count,
                reps = k.reps,
                weightKg = k.weightKg,
                rpe = k.rpe,
                restSec = k.restSec,
                weightSegments = currentSegs
            )
        }

        chunk.forEach { line ->
            val key = SegmentLineKey(
                line.reps,
                line.weightKg,
                line.rpe,
                line.restSec,
                line.weightSegments?.toString()
            )
            if (currentKey != null && currentKey == key) {
                count += 1
            } else {
                if (currentKey != null) flush()
                currentKey = key
                currentSegs = line.weightSegments
                count = 1
            }
        }
        if (currentKey != null) flush()
        return collapsed
    }

    private fun chunkToPersistRows(chunk: List<CompletedSetLine>): List<CollapsedPersistRow> {
        if (chunk.isEmpty()) return emptyList()
        return if (chunk.first().segmentsInRow <= 1) {
            collapseLegacyChunk(chunk)
        } else {
            collapseSegmentChunk(chunk)
        }
    }

    fun dismissElborblaCelebration(onDone: () -> Unit) {
        _ui.value = _ui.value.copy(showElborblaCelebration = false)
        onDone()
    }

    private inline fun <reified T> decodeFlexibleList(raw: String): List<T> {
        val root = json.parseToJsonElement(raw)
        return when (root) {
            is JsonArray -> root.map { json.decodeFromString<T>(it.toString()) }
            is JsonObject -> listOf(json.decodeFromString<T>(root.toString()))
            else -> emptyList()
        }
    }

    private companion object {
        const val TAG = "ActiveStrengthVM"
        const val ELBORBLA_USER = "elborbla"
    }
}

@Serializable
private data class UsernameRow(val username: String? = null)

@Serializable
private data class DualLinkedBundle(
    val exercises: List<DualExWire> = emptyList(),
    val sets: List<SetWire> = emptyList()
)

@Serializable
private data class DualExWire(
    val id: Int,
    @SerialName("exercise_id") val exerciseId: Long,
    @SerialName("order_index") val orderIndex: Int,
    @SerialName("superset_group_id") val supersetGroupId: String? = null,
    @SerialName("superset_position") val supersetPosition: Int? = null,
    val notes: String? = null,
    @SerialName("custom_name") val customName: String? = null,
    @SerialName("target_sets") val targetSets: Int? = null,
    val exercises: NestedExName? = null
)

@Serializable
private data class NestedExName(
    val name: String? = null
)

@Serializable
private data class WeWire(
    val id: Int,
    @SerialName("exercise_id") val exerciseId: Long,
    @SerialName("order_index") val orderIndex: Int,
    @SerialName("superset_group_id") val supersetGroupId: String? = null,
    @SerialName("superset_position") val supersetPosition: Int? = null,
    val notes: String? = null,
    @SerialName("custom_name") val customName: String? = null
)

@Serializable
private data class SetWire(
    val id: Int,
    @SerialName("workout_exercise_id") val workoutExerciseId: Int,
    @SerialName("set_number") val setNumber: Int,
    val reps: Int? = null,
    @SerialName("weight_kg") val weightKg: Double? = null,
    val rpe: Double? = null,
    @SerialName("rest_sec") val restSec: Int? = null,
    @SerialName("weight_segments") val weightSegments: JsonArray? = null
)

@Serializable
private data class ExerciseNameWire(
    val id: Long,
    val name: String? = null,
    @SerialName("name_en") val nameEn: String? = null,
    @SerialName("name_es") val nameEs: String? = null
)

class ActiveStrengthWorkoutViewModelFactory(
    private val supabase: SupabaseClient,
    private val workoutId: Int,
    private val dualGuestWorkoutId: Int? = null,
    private val dualGuest2WorkoutId: Int? = null
) : ViewModelProvider.Factory {
    @Suppress("UNCHECKED_CAST")
    override fun <T : ViewModel> create(modelClass: Class<T>): T {
        if (modelClass != ActiveStrengthWorkoutViewModel::class.java) {
            error("Unknown ViewModel: ${modelClass.name}")
        }
        return ActiveStrengthWorkoutViewModel(
            supabase,
            workoutId,
            dualGuestWorkoutId,
            dualGuest2WorkoutId
        ) as T
    }
}
