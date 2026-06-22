package com.lilru.liftr.ui.active

import android.util.Log
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.lilru.liftr.data.BackendContracts
import com.lilru.liftr.data.LiftrSupabase
import com.lilru.liftr.climbing.ClimbingRouteFormatting
import com.lilru.liftr.ui.add.AddFootballPosition
import com.lilru.liftr.ui.add.AddRacketFormat
import com.lilru.liftr.ui.add.AddRacketMode
import com.lilru.liftr.ui.add.AddSportType
import com.lilru.liftr.ui.add.SportStatsPayloadBuilder
import com.lilru.liftr.workout.ActiveWorkoutCheckpointEntry
import com.lilru.liftr.workout.ActiveWorkoutCheckpointKind
import com.lilru.liftr.workout.ActiveWorkoutSessionCheckpoint
import com.lilru.liftr.workout.SportCheckpointPayload
import com.lilru.liftr.workout.SportHyroxExerciseSnapshot
import com.lilru.liftr.ui.home.formatActivityCodeForDisplay
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
    val caloriesKcal: Double? = null,
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
    val isClimbing: Boolean = false,
    val isSki: Boolean = false,
    val sportSessionId: Int = 0,
    val hyroxExercises: List<ActiveHyroxExerciseUi> = emptyList(),
    val hyroxExerciseIndex: Int = 0,
    val climbingSportStats: Map<String, String> = emptyMap(),
    val climbingRoutesJson: String = "[]",
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
        saveSessionCheckpoint()
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

    fun setClimbingStat(key: String, value: String) {
        val next = _ui.value.climbingSportStats.toMutableMap().apply { put(key, value) }
        _ui.value = _ui.value.copy(climbingSportStats = next)
        saveSessionCheckpoint()
    }

    fun setClimbingRoutesJson(value: String) {
        _ui.value = _ui.value.copy(climbingRoutesJson = value)
        saveSessionCheckpoint()
    }

    fun hyroxStep(delta: Int) {
        val s = _ui.value
        if (!s.isHyrox) return
        val n = s.hyroxExercises.size
        if (n == 0) return
        val next = (s.hyroxExerciseIndex + delta).coerceIn(0, n - 1)
        if (next != s.hyroxExerciseIndex) {
            _ui.value = s.copy(hyroxExerciseIndex = next)
            saveSessionCheckpoint()
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
                val isClimbing = row.sport.trim().equals("climbing", ignoreCase = true)
                val isSki = row.sport.trim().equals("ski", ignoreCase = true)
                val hyroxList: List<ActiveHyroxExerciseUi> = if (isHyrox) {
                    val hRes = supabase
                        .from(BackendContracts.Tables.HYROX_SESSION_EXERCISES)
                        .select(
                            columns = Columns.raw(
                                "id, exercise_code, exercise_order, distance_m, reps, weight_kg, " +
                                    "duration_sec, height_cm, implement_count, calories_kcal, notes, exercise_display_name"
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
                            caloriesKcal = w.caloriesKcal,
                            notes = w.notes,
                            exerciseDisplayName = w.exerciseDisplayName
                        )
                    }
                } else {
                    emptyList()
                }
                val climbingLoad = if (isClimbing) {
                    loadClimbingSessionData(row.id)
                } else {
                    emptyMap<String, String>() to "[]"
                }
                _ui.value = _ui.value.copy(
                    loading = false,
                    loadError = null,
                    hasSportSession = true,
                    sportLabel = label,
                    isHyrox = isHyrox,
                    isClimbing = isClimbing,
                    isSki = isSki,
                    sportSessionId = row.id,
                    hyroxExercises = hyroxList,
                    hyroxExerciseIndex = 0,
                    climbingSportStats = climbingLoad.first,
                    climbingRoutesJson = climbingLoad.second,
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
                restoreSportCheckpointIfNeeded()
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
                if (snap.isClimbing) {
                    persistClimbingStats(workoutId, snap)
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
                clearSportCheckpoint()
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

    private var didRestoreSportCheckpoint = false

    fun saveSessionCheckpoint() {
        val ctx = LiftrSupabase.appContext ?: return
        val s = _ui.value
        val hyroxSnaps = s.hyroxExercises.map { ex ->
            SportHyroxExerciseSnapshot(
                id = ex.id,
                exerciseCode = ex.exerciseCode,
                exerciseOrder = ex.exerciseOrder,
                distanceM = ex.distanceM,
                reps = ex.reps,
                weightKg = ex.weightKg,
                durationSec = ex.durationSec,
                heightCm = ex.heightCm,
                implementCount = ex.implementCount,
                caloriesKcal = ex.caloriesKcal,
                notes = ex.notes,
                customDisplayName = ex.exerciseDisplayName
            )
        }
        val completedIds = (0 until s.hyroxExerciseIndex.coerceAtLeast(0))
            .mapNotNull { idx -> s.hyroxExercises.getOrNull(idx)?.id }
        val payload = SportCheckpointPayload(
            elapsedSec = s.elapsedSec,
            isSessionRunning = s.isSessionRunning,
            remainingSec = 0,
            initialTargetSec = s.targetDurationSec ?: 0,
            hyroxExerciseIndex = s.hyroxExerciseIndex,
            completedHyroxExerciseIds = completedIds,
            hyroxExercises = hyroxSnaps,
            scoreForText = s.scoreForText,
            scoreAgainstText = s.scoreAgainstText,
            matchResultRaw = s.matchResultRaw,
            matchScoreText = s.matchScoreText,
            locationText = s.locationText,
            sessionNotesText = s.sessionNotesText,
            climbingSportStats = s.climbingSportStats,
            climbingRoutesJson = s.climbingRoutesJson
        )
        ActiveWorkoutSessionCheckpoint.store(
            ctx,
            ActiveWorkoutCheckpointEntry(
                workoutId = workoutId,
                kind = ActiveWorkoutCheckpointKind.SPORT,
                savedAtEpochMs = System.currentTimeMillis(),
                sport = payload
            )
        )
    }

    fun clearSportCheckpoint() {
        LiftrSupabase.appContext?.let { ActiveWorkoutSessionCheckpoint.clearIfWorkout(it, workoutId) }
    }

    private fun restoreSportCheckpointIfNeeded() {
        if (didRestoreSportCheckpoint) return
        val ctx = LiftrSupabase.appContext ?: return
        val entry = ActiveWorkoutSessionCheckpoint.load(ctx) ?: return
        if (entry.workoutId != workoutId || entry.kind != ActiveWorkoutCheckpointKind.SPORT) return
        val sport = entry.sport ?: return
        didRestoreSportCheckpoint = true
        val hyroxList = if (sport.hyroxExercises.isNotEmpty()) {
            sport.hyroxExercises.map { ex ->
                ActiveHyroxExerciseUi(
                    id = ex.id,
                    exerciseCode = ex.exerciseCode,
                    exerciseOrder = ex.exerciseOrder,
                    distanceM = ex.distanceM,
                    reps = ex.reps,
                    weightKg = ex.weightKg,
                    durationSec = ex.durationSec,
                    heightCm = ex.heightCm,
                    implementCount = ex.implementCount,
                    caloriesKcal = ex.caloriesKcal,
                    notes = ex.notes,
                    exerciseDisplayName = ex.customDisplayName
                )
            }
        } else {
            _ui.value.hyroxExercises
        }
        _ui.value = _ui.value.copy(
            elapsedSec = sport.elapsedSec,
            isSessionRunning = sport.isSessionRunning,
            hyroxExercises = hyroxList,
            hyroxExerciseIndex = sport.hyroxExerciseIndex,
            scoreForText = sport.scoreForText,
            scoreAgainstText = sport.scoreAgainstText,
            matchResultRaw = sport.matchResultRaw,
            matchScoreText = sport.matchScoreText,
            locationText = sport.locationText,
            sessionNotesText = sport.sessionNotesText,
            climbingSportStats = sport.climbingSportStats.ifEmpty { _ui.value.climbingSportStats },
            climbingRoutesJson = sport.climbingRoutesJson.ifEmpty { _ui.value.climbingRoutesJson }
        )
    }

    private suspend fun loadClimbingSessionData(sessionId: Int): Pair<Map<String, String>, String> {
        val sRes = supabase.from(BackendContracts.Tables.CLIMBING_SESSION_STATS)
            .select(columns = Columns.raw("*")) {
                filter { eq("session_id", sessionId) }
                limit(1)
            }
        val row = decodeFlexibleList<ClimbingStatsWire>(sRes.data).firstOrNull()
        val stats = mutableMapOf<String, String>(
            "environment" to (row?.environment ?: "indoor"),
            "primary_style" to (row?.primaryStyle ?: "boulder")
        )
        row?.routesSent?.let { stats["routes_sent"] = it.toString() }
        row?.routesAttempted?.let { stats["routes_attempted"] = it.toString() }
        row?.totalVerticalM?.let { stats["total_vertical_m"] = it.toString() }
        row?.movingTimeSec?.let { stats["moving_time_sec"] = it.toString() }
        row?.pausedTimeSec?.let { stats["paused_time_sec"] = it.toString() }
        row?.venueName?.takeIf { it.isNotBlank() }?.let { stats["venue_name"] = it }
        row?.weather?.takeIf { it.isNotBlank() }?.let { stats["weather"] = it }
        row?.avgHr?.let { stats["avg_hr"] = it.toString() }
        row?.maxHr?.let { stats["max_hr"] = it.toString() }
        row?.falls?.let { stats["falls"] = it.toString() }
        row?.flashes?.let { stats["flashes"] = it.toString() }
        row?.highestGradeSystem?.takeIf { it.isNotBlank() }?.let { stats["highest_grade_system"] = it }
        row?.highestGradeValue?.takeIf { it.isNotBlank() }?.let { stats["highest_grade_value"] = it }
        ClimbingRouteFormatting.sanitizeClimbingSportStats(stats)

        val rRes = supabase.from(BackendContracts.Tables.CLIMBING_SESSION_ROUTES)
            .select(columns = Columns.raw("route_order, route_name, style, grade_system, grade_value, attempts, sent, flash, notes")) {
                filter { eq("session_id", sessionId) }
                order("route_order", Order.ASCENDING)
            }
        val routes = ClimbingRouteFormatting.sanitizeRoutes(decodeFlexibleList<ClimbingRouteWire>(rRes.data).map { r ->
            com.lilru.liftr.climbing.ClimbingRouteForm(
                routeName = r.routeName.orEmpty(),
                style = com.lilru.liftr.climbing.ClimbingStyle.fromWire(r.style),
                gradeSystem = com.lilru.liftr.climbing.ClimbingGradeSystem.fromWire(r.gradeSystem),
                gradeValue = r.gradeValue.orEmpty(),
                attempts = r.attempts?.toString().orEmpty(),
                sent = r.sent == true,
                flash = r.flash == true,
                notes = r.notes.orEmpty()
            )
        })
        return stats to ClimbingRouteFormatting.encodeRoutesJson(routes)
    }

    private suspend fun persistClimbingStats(workoutId: Int, snap: ActiveSportUiState) {
        val stats = SportStatsPayloadBuilder.build(
            sport = AddSportType.CLIMBING,
            durationMinText = "",
            footballPosition = AddFootballPosition.FORWARD,
            racketMode = AddRacketMode.SINGLES,
            racketFormat = AddRacketFormat.BEST_OF_3,
            sportStats = snap.climbingSportStats,
            hyroxExercisesText = "[]",
            climbingRoutesJson = snap.climbingRoutesJson
        )
        val p = buildJsonObject {
            put("p_sport", "climbing")
            val loc = snap.locationText.trim()
            if (loc.isNotEmpty()) put("p_location", loc)
            val notes = snap.sessionNotesText.trim()
            if (notes.isNotEmpty()) put("p_session_notes", notes)
        }
        val wrapper = buildJsonObject {
            put("p_workout_id", workoutId)
            put("p", p)
            put("p_stats", stats)
        }
        supabase.postgrest.rpc(BackendContracts.Rpc.UPDATE_SPORT_WORKOUT_V2, wrapper) { }
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
    @SerialName("calories_kcal") val caloriesKcal: Double? = null,
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
    ex.caloriesKcal?.let { put("calories_kcal", JsonPrimitive(it)) } ?: put("calories_kcal", JsonNull)
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
    if (!s.isClimbing && !s.isSki) {
        val mr = normalizeSportMatchResult(s.matchResultRaw)
        put("match_result", mr)
    }
    val mst = s.matchScoreText.trim()
    if (mst.isEmpty()) put("match_score_text", JsonNull) else put("match_score_text", mst)
    val loc = s.locationText.trim()
    if (loc.isEmpty()) put("location", JsonNull) else put("location", loc)
    val n = s.sessionNotesText.trim()
    if (n.isEmpty()) put("notes", JsonNull) else put("notes", n)
}

@Serializable
private data class ClimbingStatsWire(
    val environment: String? = null,
    @SerialName("primary_style") val primaryStyle: String? = null,
    @SerialName("routes_sent") val routesSent: Int? = null,
    @SerialName("routes_attempted") val routesAttempted: Int? = null,
    @SerialName("total_vertical_m") val totalVerticalM: Int? = null,
    @SerialName("moving_time_sec") val movingTimeSec: Int? = null,
    @SerialName("paused_time_sec") val pausedTimeSec: Int? = null,
    @SerialName("venue_name") val venueName: String? = null,
    val weather: String? = null,
    @SerialName("avg_hr") val avgHr: Int? = null,
    @SerialName("max_hr") val maxHr: Int? = null,
    val falls: Int? = null,
    val flashes: Int? = null,
    @SerialName("highest_grade_system") val highestGradeSystem: String? = null,
    @SerialName("highest_grade_value") val highestGradeValue: String? = null
)

@Serializable
private data class ClimbingRouteWire(
    @SerialName("route_name") val routeName: String? = null,
    val style: String? = null,
    @SerialName("grade_system") val gradeSystem: String? = null,
    @SerialName("grade_value") val gradeValue: String? = null,
    val attempts: Int? = null,
    val sent: Boolean? = null,
    val flash: Boolean? = null,
    val notes: String? = null
)

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
