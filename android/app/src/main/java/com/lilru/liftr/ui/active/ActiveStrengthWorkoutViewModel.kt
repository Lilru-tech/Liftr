package com.lilru.liftr.ui.active

import android.util.Log
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
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import java.time.Instant
import java.util.Locale
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.JsonPrimitive

data class ActiveStrengthSetLine(
    val setId: Int,
    val configId: Int,
    val setNumber: Int,
    val reps: Int?,
    val weightKg: Double?,
    val rpe: Double?,
    val restSec: Int?
)

data class ActiveStrengthExerciseLine(
    val workoutExerciseId: Int,
    val displayName: String,
    val sets: List<ActiveStrengthSetLine>
)

private data class CompletedSetLine(
    val workoutExerciseId: Int,
    val reps: Int?,
    val weightKg: Double?,
    val rpe: Double?,
    val restSec: Int?
)

private data class CollapsedPerformedBlock(
    val count: Int,
    val reps: Int?,
    val weightKg: Double?,
    val rpe: Double?,
    val restSec: Int?
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
    val isResting: Boolean = false,
    val restSecondsLeft: Int = 0,
    val sessionElapsedSec: Int = 0,
    val finishing: Boolean = false,
    val completedEntirely: Boolean = false,
    val editRepsText: String = "",
    val editWeightText: String = "",
    val editRpeText: String = "",
    val editRestText: String = "",
    /** Easter egg alineado con [Liftr/ActiveStrengthWorkoutView.swift] (usuario `elborbla`). */
    val showElborblaCelebration: Boolean = false
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
    private val completedSetLines: MutableList<CompletedSetLine> = mutableListOf()

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
            while (true) {
                delay(1000)
                _ui.value = _ui.value.copy(
                    sessionElapsedSec = _ui.value.sessionElapsedSec + 1
                )
            }
        }
    }

    fun load() {
        viewModelScope.launch {
            _ui.value = _ui.value.copy(loading = true, error = null, completedEntirely = false)
            runCatching {
                supabase.auth.currentUserOrNull()?.id ?: error("No session")
                patchWorkoutStartedAtNow(supabase, workoutId)

                val wRes = supabase
                    .from(BackendContracts.Tables.WORKOUT_EXERCISES)
                    .select(
                        columns = Columns.raw("id, exercise_id, order_index, notes, custom_name")
                    ) {
                        filter { eq("workout_id", workoutId) }
                        order("order_index", Order.ASCENDING)
                    }
                val weRows = decodeFlexibleList<WeWire>(wRes.data)
                if (weRows.isEmpty()) {
                    _ui.value = _ui.value.copy(loading = false, error = null, exercises = emptyList())
                    return@runCatching
                }
                val exIds = weRows.map { it.exerciseId }.distinct()
                val namesById = loadExerciseNames(exIds)
                val weIds = weRows.map { it.id }

                val sRes = supabase
                    .from(BackendContracts.Tables.EXERCISE_SETS)
                    .select(columns = Columns.raw("id, workout_exercise_id, set_number, reps, weight_kg, rpe, rest_sec")) {
                        filter { isIn("workout_exercise_id", weIds) }
                        order("set_number", Order.ASCENDING)
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
                        sets = setLines
                    )
                }
                if (lines.isEmpty()) {
                    _ui.value = _ui.value.copy(
                        loading = false,
                        error = null,
                        exercises = emptyList()
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
                        guest2DataError = g2Err
                    )
                )
            }.onFailure { e ->
                Log.e(TAG, "load failed", e)
                _ui.value = _ui.value.copy(
                    loading = false,
                    error = e.message?.take(280) ?: e::class.java.simpleName
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
                    sets = setLines
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
        val sortedRows = rows.sortedBy { it.id }
        val expanded = mutableListOf<ActiveStrengthSetLine>()
        sortedRows.forEach { row ->
            val count = row.setNumber.coerceAtLeast(0)
            repeat(count) {
                val sequentialNumber = expanded.size + 1
                expanded += ActiveStrengthSetLine(
                    setId = row.id * 1000 + sequentialNumber,
                    configId = row.id,
                    setNumber = sequentialNumber,
                    reps = row.reps,
                    weightKg = row.weightKg,
                    rpe = row.rpe,
                    restSec = row.restSec
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

    fun applyCurrentSetEdits() {
        val s = _ui.value
        val ex = s.exercises.getOrNull(s.currentExerciseIndex) ?: return
        val setIndex = s.currentSetIndexByExerciseId[ex.workoutExerciseId] ?: s.currentSetIndex
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
        restJob?.cancel()
        restJob = null
        _ui.value = _ui.value.copy(isResting = false, restSecondsLeft = 0)
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
        completedSetLines.add(
            CompletedSetLine(
                workoutExerciseId = ex.workoutExerciseId,
                reps = reps,
                weightKg = weightKg,
                rpe = rpe,
                restSec = set.restSec
            )
        )
        val nextSetIndex = (setIndex + 1).coerceAtMost(ex.sets.size)
        val nextMap = s.currentSetIndexByExerciseId.toMutableMap().apply {
            put(ex.workoutExerciseId, nextSetIndex)
        }
        val allDone = areAllExercisesCompleted(s.exercises, nextMap)
        val baseState = withSyncedEditFields(
            s.copy(
                currentSetIndex = nextSetIndex,
                currentSetIndexByExerciseId = nextMap,
                completedEntirely = allDone
            )
        )
        val rest = set.restSec?.takeIf { it > 0 } ?: 0
        if (rest > 0) {
            _ui.value = baseState.copy(isResting = true, restSecondsLeft = rest)
            restJob?.cancel()
            restJob = viewModelScope.launch {
                var left = rest
                while (left > 0) {
                    delay(1000)
                    left--
                    _ui.value = _ui.value.copy(restSecondsLeft = left)
                }
                _ui.value = _ui.value.copy(isResting = false, restSecondsLeft = 0)
            }
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
            s.copy(
                currentExerciseIndex = clamped,
                currentSetIndex = setIdx,
                isResting = false,
                restSecondsLeft = 0
            )
        )
    }

    fun goToNextExercise() {
        val s = _ui.value
        if (s.currentExerciseIndex < s.exercises.lastIndex) {
            goToExercise(s.currentExerciseIndex + 1)
        }
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
        completedSetLines.clear()
        val s = _ui.value
        val map = s.exercises.associate { it.workoutExerciseId to 0 }
        _ui.value = withSyncedEditFields(
            s.copy(
                currentExerciseIndex = 0,
                currentSetIndex = 0,
                currentSetIndexByExerciseId = map,
                isResting = false,
                restSecondsLeft = 0,
                completedEntirely = false
            )
        )
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

    fun finishWorkout(onDone: () -> Unit) {
        if (_ui.value.finishing) return
        viewModelScope.launch {
            _ui.value = _ui.value.copy(finishing = true, error = null)
            val res = runCatching {
                supabase.auth.currentUserOrNull()?.id ?: error("No session")
                val ended = Instant.now().toString()
                if (completedSetLines.isNotEmpty()) {
                    val byWe = completedSetLines.groupBy { it.workoutExerciseId }
                    for ((weId, lines) in byWe) {
                        supabase.from(BackendContracts.Tables.EXERCISE_SETS).delete {
                            filter { eq("workout_exercise_id", weId) }
                        }
                        val collapsedBlocks = collapsePerformedLines(lines)
                        collapsedBlocks.forEach { block ->
                            val payload = buildJsonObject {
                                put("workout_exercise_id", weId)
                                put("set_number", block.count)
                                if (block.reps != null) put("reps", block.reps)
                                if (block.weightKg != null) put("weight_kg", block.weightKg)
                                if (block.rpe != null) put("rpe", block.rpe)
                                if (block.restSec != null) put("rest_sec", block.restSec)
                            }
                            supabase.from(BackendContracts.Tables.EXERCISE_SETS).insert(payload) { }
                        }
                    }
                }
                val nRes = supabase
                    .from(BackendContracts.Tables.WORKOUTS)
                    .select(columns = Columns.raw("notes, state")) {
                        filter { eq("id", workoutId) }
                        limit(1)
                    }
                val wRow = decodeFlexibleList<WorkoutNotesStateRow>(nRes.data).firstOrNull()
                val mergedNotes = mergeWorkoutNotesForFinish(wRow?.notes, null)
                supabase.from(BackendContracts.Tables.WORKOUTS).update(
                    buildJsonObject {
                        put("ended_at", ended)
                        if (mergedNotes != null) put("notes", mergedNotes)
                    }
                ) {
                    filter { eq("id", workoutId) }
                }
            }
            if (res.isFailure) {
                val e = res.exceptionOrNull()!!
                Log.e(TAG, "finish failed", e)
                _ui.value = _ui.value.copy(
                    finishing = false,
                    error = e.message?.take(280) ?: e::class.java.simpleName
                )
                return@launch
            }
            val celebrate = checkElborblaCelebration()
            _ui.value = _ui.value.copy(
                finishing = false,
                showElborblaCelebration = celebrate
            )
            if (!celebrate) {
                onDone()
            }
        }
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

    private fun collapsePerformedLines(lines: List<CompletedSetLine>): List<CollapsedPerformedBlock> {
        if (lines.isEmpty()) return emptyList()
        val collapsed = mutableListOf<CollapsedPerformedBlock>()
        var current: CompletedSetLine? = null
        var count = 0
        lines.forEach { line ->
            if (current != null && current == line) {
                count += 1
            } else {
                current?.let { prev ->
                    collapsed += CollapsedPerformedBlock(
                        count = count,
                        reps = prev.reps,
                        weightKg = prev.weightKg,
                        rpe = prev.rpe,
                        restSec = prev.restSec
                    )
                }
                current = line
                count = 1
            }
        }
        current?.let { prev ->
            collapsed += CollapsedPerformedBlock(
                count = count,
                reps = prev.reps,
                weightKg = prev.weightKg,
                rpe = prev.rpe,
                restSec = prev.restSec
            )
        }
        return collapsed
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
    @SerialName("rest_sec") val restSec: Int? = null
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
