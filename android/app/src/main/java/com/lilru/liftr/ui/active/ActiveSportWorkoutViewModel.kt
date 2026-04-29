package com.lilru.liftr.ui.active

import android.util.Log
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.lilru.liftr.data.BackendContracts
import com.lilru.liftr.ui.home.formatActivityCodeForDisplay
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.postgrest.from
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
import java.util.concurrent.atomic.AtomicBoolean
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

data class ActiveHyroxExerciseUi(
    val id: Int,
    val exerciseCode: String,
    val exerciseOrder: Int,
    val distanceM: Int? = null,
    val reps: Int? = null,
    val weightKg: Double? = null,
    val durationSec: Int? = null,
    val heightCm: Int? = null,
    val implementCount: Int? = null,
    val notes: String? = null,
    val exerciseDisplayName: String? = null
)

data class ActiveSportUiState(
    val loading: Boolean = true,
    val loadError: String? = null,
    val actionError: String? = null,
    val workoutId: Int = 0,
    val hasSportSession: Boolean = true,
    val sportLabel: String = "Sport",
    val isHyrox: Boolean = false,
    val sportSessionId: Int = 0,
    val hyroxExercises: List<ActiveHyroxExerciseUi> = emptyList(),
    val hyroxExerciseIndex: Int = 0,
    val targetDurationSec: Int? = null,
    val isSessionRunning: Boolean = false,
    val elapsedSec: Int = 0,
    val finishing: Boolean = false,
    val scoreForText: String = "",
    val scoreAgainstText: String = "",
    val matchResultRaw: String = "unfinished",
    val matchScoreText: String = "",
    val locationText: String = "",
    val sessionNotesText: String = ""
)

class ActiveSportWorkoutViewModel(
    private val supabase: SupabaseClient,
    private val workoutId: Int
) : ViewModel() {
    private val json = Json { ignoreUnknownKeys = true }
    private val _ui = MutableStateFlow(ActiveSportUiState(workoutId = workoutId))
    val uiState: StateFlow<ActiveSportUiState> = _ui.asStateFlow()

    private val startedAtPatched = AtomicBoolean(false)
    private var sessionJob: Job? = null

    init {
        load()
        startSessionTimer()
    }

    override fun onCleared() {
        sessionJob?.cancel()
        super.onCleared()
    }

    private fun startSessionTimer() {
        sessionJob?.cancel()
        sessionJob = viewModelScope.launch {
            while (true) {
                delay(1000)
                val s = _ui.value
                if (s.isSessionRunning) {
                    _ui.value = s.copy(elapsedSec = s.elapsedSec + 1)
                }
            }
        }
    }

    fun toggleSessionRunning() {
        if (_ui.value.finishing) return
        _ui.value = _ui.value.copy(isSessionRunning = !_ui.value.isSessionRunning)
    }

    fun resetSession() {
        if (_ui.value.finishing) return
        val s = _ui.value
        if (s.isSessionRunning || s.elapsedSec == 0) return
        _ui.value = s.copy(isSessionRunning = false, elapsedSec = 0)
    }

    fun setScoreForText(value: String) {
        _ui.value = _ui.value.copy(scoreForText = value)
    }

    fun setScoreAgainstText(value: String) {
        _ui.value = _ui.value.copy(scoreAgainstText = value)
    }

    fun setMatchResultRaw(value: String) {
        _ui.value = _ui.value.copy(matchResultRaw = value)
    }

    fun setMatchScoreText(value: String) {
        _ui.value = _ui.value.copy(matchScoreText = value)
    }

    fun setLocationText(value: String) {
        _ui.value = _ui.value.copy(locationText = value)
    }

    fun setSessionNotesText(value: String) {
        _ui.value = _ui.value.copy(sessionNotesText = value)
    }

    fun hyroxStep(delta: Int) {
        val s = _ui.value
        if (!s.isHyrox) return
        val n = s.hyroxExercises.size
        if (n == 0) return
        val next = (s.hyroxExerciseIndex + delta).coerceIn(0, n - 1)
        if (next != s.hyroxExerciseIndex) {
            _ui.value = s.copy(hyroxExerciseIndex = next)
        }
    }

    fun load() {
        viewModelScope.launch {
            _ui.value = _ui.value.copy(loading = true, loadError = null)
            runCatching {
                supabase.auth.currentUserOrNull()?.id ?: error("No session")

                val sRes = supabase
                    .from(BackendContracts.Tables.SPORT_SESSIONS)
                    .select(
                        columns = Columns.raw(
                            "id, sport, duration_sec, score_for, score_against, " +
                                "match_result, match_score_text, location, notes"
                        )
                    ) {
                        filter { eq("workout_id", workoutId) }
                        limit(1)
                    }
                val rows = decodeFlexibleList<SportSessionWire>(sRes.data)
                if (rows.isEmpty()) {
                    _ui.value = _ui.value.copy(loading = false, loadError = null, hasSportSession = false)
                    return@runCatching
                }
                if (startedAtPatched.compareAndSet(false, true)) {
                    patchWorkoutStartedAtNow(supabase, workoutId)
                }
                val row = rows.first()
                val label = formatActivityCodeForDisplay(row.sport.trim().ifEmpty { "sport" })
                val isHyrox = row.sport.trim().equals("hyrox", ignoreCase = true)
                val hyroxList: List<ActiveHyroxExerciseUi> = if (isHyrox) {
                    val hRes = supabase
                        .from(BackendContracts.Tables.HYROX_SESSION_EXERCISES)
                        .select(
                            columns = Columns.raw(
                                "id, exercise_code, exercise_order, distance_m, reps, weight_kg, " +
                                    "duration_sec, height_cm, implement_count, notes, exercise_display_name"
                            )
                        ) {
                            filter { eq("session_id", row.id) }
                            order("exercise_order", Order.ASCENDING)
                        }
                    decodeFlexibleList<HyroxExerciseWire>(hRes.data).map { w ->
                        ActiveHyroxExerciseUi(
                            id = w.id,
                            exerciseCode = w.exerciseCode,
                            exerciseOrder = w.exerciseOrder,
                            distanceM = w.distanceM,
                            reps = w.reps,
                            weightKg = w.weightKg,
                            durationSec = w.durationSec,
                            heightCm = w.heightCm,
                            implementCount = w.implementCount,
                            notes = w.notes,
                            exerciseDisplayName = w.exerciseDisplayName
                        )
                    }
                } else {
                    emptyList()
                }
                _ui.value = _ui.value.copy(
                    loading = false,
                    loadError = null,
                    hasSportSession = true,
                    sportLabel = label,
                    isHyrox = isHyrox,
                    sportSessionId = row.id,
                    hyroxExercises = hyroxList,
                    hyroxExerciseIndex = 0,
                    targetDurationSec = row.durationSec?.takeIf { it > 0 },
                    isSessionRunning = false,
                    elapsedSec = 0,
                    scoreForText = row.scoreFor?.let { v -> v.toString() } ?: "",
                    scoreAgainstText = row.scoreAgainst?.let { v -> v.toString() } ?: "",
                    matchResultRaw = normalizeSportMatchResult(row.matchResult),
                    matchScoreText = row.matchScoreText ?: "",
                    locationText = row.location ?: "",
                    sessionNotesText = row.notes ?: ""
                )
            }.onFailure { e ->
                Log.e(TAG, "load failed", e)
                _ui.value = _ui.value.copy(
                    loading = false,
                    loadError = e.message?.take(280) ?: e::class.java.simpleName
                )
            }
        }
    }

    fun finishWorkout(onDone: () -> Unit) {
        if (_ui.value.finishing) return
        val elapsed = _ui.value.elapsedSec
        if (elapsed <= 0) return
        viewModelScope.launch {
            _ui.value = _ui.value.copy(
                finishing = true,
                isSessionRunning = false,
                actionError = null
            )
            runCatching {
                supabase.auth.currentUserOrNull()?.id ?: error("No session")
                val ended = Instant.now().toString()

                val snap = _ui.value
                supabase.from(BackendContracts.Tables.SPORT_SESSIONS).update(
                    sportSessionFinishJson(elapsed, snap)
                ) {
                    filter { eq("workout_id", workoutId) }
                }

                if (snap.isHyrox && snap.sportSessionId > 0) {
                    persistHyroxExercises(snap.sportSessionId, snap.hyroxExercises)
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
                    workoutFinishUpdateJson(ended, mergedNotes, wRow?.state)
                ) {
                    filter { eq("id", workoutId) }
                }
            }.onSuccess {
                _ui.value = _ui.value.copy(finishing = false)
                onDone()
            }.onFailure { e ->
                Log.e(TAG, "finish failed", e)
                _ui.value = _ui.value.copy(
                    finishing = false,
                    actionError = e.message?.take(280) ?: e::class.java.simpleName
                )
            }
        }
    }

    private suspend fun persistHyroxExercises(sessionId: Int, exercises: List<ActiveHyroxExerciseUi>) {
        supabase.from(BackendContracts.Tables.HYROX_SESSION_EXERCISES).delete {
            filter { eq("session_id", sessionId) }
        }
        for (ex in exercises) {
            supabase.from(BackendContracts.Tables.HYROX_SESSION_EXERCISES).insert(
                hyroxInsertJson(sessionId, ex)
            ) { }
        }
    }

    private inline fun <reified T> decodeFlexibleList(raw: String): List<T> {
        val root = json.parseToJsonElement(raw)
        return when (root) {
            is JsonArray -> root.map { json.decodeFromString<T>(it.toString()) }
            is JsonObject -> listOf(json.decodeFromString<T>(raw))
            else -> emptyList()
        }
    }
}

@Serializable
private data class HyroxExerciseWire(
    val id: Int,
    @SerialName("exercise_code") val exerciseCode: String,
    @SerialName("exercise_order") val exerciseOrder: Int,
    @SerialName("distance_m") val distanceM: Int? = null,
    val reps: Int? = null,
    @SerialName("weight_kg") val weightKg: Double? = null,
    @SerialName("duration_sec") val durationSec: Int? = null,
    @SerialName("height_cm") val heightCm: Int? = null,
    @SerialName("implement_count") val implementCount: Int? = null,
    val notes: String? = null,
    @SerialName("exercise_display_name") val exerciseDisplayName: String? = null
)

private fun hyroxInsertJson(sessionId: Int, ex: ActiveHyroxExerciseUi) = buildJsonObject {
    put("session_id", sessionId)
    put("exercise_code", ex.exerciseCode)
    put("exercise_order", ex.exerciseOrder)
    ex.distanceM?.let { put("distance_m", it) } ?: put("distance_m", JsonNull)
    ex.reps?.let { put("reps", it) } ?: put("reps", JsonNull)
    ex.weightKg?.let { put("weight_kg", JsonPrimitive(it)) } ?: put("weight_kg", JsonNull)
    ex.durationSec?.let { put("duration_sec", it) } ?: put("duration_sec", JsonNull)
    ex.heightCm?.let { put("height_cm", it) } ?: put("height_cm", JsonNull)
    ex.implementCount?.let { put("implement_count", it) } ?: put("implement_count", JsonNull)
    ex.notes?.takeIf { it.isNotBlank() }?.let { put("notes", it) } ?: put("notes", JsonNull)
    ex.exerciseDisplayName?.takeIf { it.isNotBlank() }?.let { put("exercise_display_name", it) }
        ?: put("exercise_display_name", JsonNull)
}

private fun sportSessionFinishJson(elapsed: Int, s: ActiveSportUiState) = buildJsonObject {
    put("duration_sec", elapsed)
    val sf = s.scoreForText.trim()
    if (sf.isEmpty()) {
        put("score_for", JsonNull)
    } else {
        sf.toIntOrNull()?.let { put("score_for", it) } ?: put("score_for", JsonNull)
    }
    val sa = s.scoreAgainstText.trim()
    if (sa.isEmpty()) {
        put("score_against", JsonNull)
    } else {
        sa.toIntOrNull()?.let { put("score_against", it) } ?: put("score_against", JsonNull)
    }
    val mr = normalizeSportMatchResult(s.matchResultRaw)
    put("match_result", mr)
    val mst = s.matchScoreText.trim()
    if (mst.isEmpty()) put("match_score_text", JsonNull) else put("match_score_text", mst)
    val loc = s.locationText.trim()
    if (loc.isEmpty()) put("location", JsonNull) else put("location", loc)
    val n = s.sessionNotesText.trim()
    if (n.isEmpty()) put("notes", JsonNull) else put("notes", n)
}

@Serializable
private data class SportSessionWire(
    val id: Int,
    val sport: String,
    @SerialName("duration_sec") val durationSec: Int? = null,
    @SerialName("score_for") val scoreFor: Int? = null,
    @SerialName("score_against") val scoreAgainst: Int? = null,
    @SerialName("match_result") val matchResult: String? = null,
    @SerialName("match_score_text") val matchScoreText: String? = null,
    val location: String? = null,
    val notes: String? = null
)

private const val TAG = "ActiveSport"

class ActiveSportWorkoutViewModelFactory(
    private val supabase: SupabaseClient,
    private val workoutId: Int
) : ViewModelProvider.Factory {
    @Suppress("UNCHECKED_CAST")
    override fun <T : ViewModel> create(modelClass: Class<T>): T {
        if (modelClass != ActiveSportWorkoutViewModel::class.java) {
            error("Unknown ViewModel: ${modelClass.name}")
        }
        return ActiveSportWorkoutViewModel(supabase, workoutId) as T
    }
}
