package com.lilru.liftr.ui.active

import android.app.Application
import android.util.Log
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.lilru.liftr.cardio.CardioKmPaceSplits
import com.lilru.liftr.cardio.CardioRouteGeoJson
import com.lilru.liftr.cardio.KmPaceSplitCalculator
import com.lilru.liftr.data.BackendContracts
import com.lilru.liftr.ongoing.CardioLocationBridge
import com.lilru.liftr.prefs.CardioGpsProfile
import com.lilru.liftr.prefs.CardioGpsPreferences
import com.lilru.liftr.territory.TerritoryCaptureClient
import com.lilru.liftr.ui.AppSnackbar
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.query.Columns
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
import java.util.Collections
import java.util.concurrent.atomic.AtomicBoolean
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.put
import kotlin.math.floor
import kotlin.math.roundToInt

/** Cronómetro vs cuenta atrás hacia [targetDurationSec] (como [Liftr.ActiveCardioWorkoutView] TimerMode). */
enum class CardioTimerMode {
    STOPWATCH,
    COUNTDOWN
}

data class ActiveCardioUiState(
    val loading: Boolean = true,
    val loadError: String? = null,
    val actionError: String? = null,
    val workoutId: Int = 0,
    val hasCardioSession: Boolean = true,
    val activityLabel: String = "Cardio",
    val targetDistanceKm: Double? = null,
    val targetDurationSec: Int? = null,
    val distanceText: String = "",
    val gpsProfile: CardioGpsProfile = CardioGpsProfile.BALANCED,
    val timerMode: CardioTimerMode = CardioTimerMode.STOPWATCH,
    /** Tiempos acumulados al cruzar cada km (como [Liftr.ActiveCardioWorkoutView.splitEndElapsedSec]) para la UI. */
    val kmSplitCumulativeSec: List<Int> = emptyList(),
    /** Puntos GPS (lat, lon) para el mapa; vacío al abrir. */
    val routePoints: List<Pair<Double, Double>> = emptyList(),
    val territoryPreviewRings: List<List<Pair<Double, Double>>> = emptyList(),
    /** True while the stopwatch is counting; false at open and when paused. */
    val isSessionRunning: Boolean = false,
    val elapsedSec: Int = 0,
    val finishing: Boolean = false
)

class ActiveCardioWorkoutViewModel(
    private val app: Application,
    private val supabase: SupabaseClient,
    private val workoutId: Int
) : ViewModel() {
    private val json = Json { ignoreUnknownKeys = true }
    private val _ui = MutableStateFlow(ActiveCardioUiState(workoutId = workoutId))
    val uiState: StateFlow<ActiveCardioUiState> = _ui.asStateFlow()

    private val startedAtPatched = AtomicBoolean(false)
    private var initialDistanceText: String = ""
    private var sessionJob: Job? = null
    private val routePoints: MutableList<Pair<Double, Double>> =
        Collections.synchronizedList(mutableListOf())
    private var lastTerritoryPreviewAtMs = 0L
    private var lastTerritoryPreviewPointCount = 0
    private var territoryPreviewJob: Job? = null
    private var routeDistanceM: Double = 0.0
    private val splitCumulativeSec: MutableList<Int> = mutableListOf()
    private var cardioSessionId: Int = 0

    private fun minGpsMetersToAdvance(): Double = when (_ui.value.gpsProfile) {
        CardioGpsProfile.BALANCED -> 5.0
        CardioGpsProfile.BATTERY_SAVING -> 22.0
    }

    init {
        CardioLocationBridge.listener = { lat, lon -> appendRoutePoint(lat, lon) }
        load()
        startSessionTimer()
    }

    override fun onCleared() {
        CardioLocationBridge.listener = null
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

    fun setDistanceText(value: String) {
        _ui.value = _ui.value.copy(distanceText = value)
    }

    fun setGpsProfile(p: CardioGpsProfile) {
        viewModelScope.launch {
            withContext(Dispatchers.IO) { CardioGpsPreferences.setProfile(app, p) }
            _ui.value = _ui.value.copy(gpsProfile = p)
        }
    }

    fun setTimerMode(m: CardioTimerMode) {
        _ui.value = _ui.value.copy(timerMode = m)
    }

    fun appendRoutePoint(lat: Double, lon: Double) {
        synchronized(routePoints) {
            if (routePoints.isEmpty()) {
                routePoints.add(lat to lon)
            } else {
                val last = routePoints.last()
                val d = distMeters(last, lat to lon)
                if (d >= minGpsMetersToAdvance()) {
                    routeDistanceM += d
                    routePoints.add(lat to lon)
                    recordKmSplitsIfNeeded()
                }
            }
        }
        publishRoutePointsToUi()
    }

    private fun publishRoutePointsToUi() {
        val copy = synchronized(routePoints) { routePoints.map { it.first to it.second } }
        _ui.value = _ui.value.copy(routePoints = copy)
        maybeRefreshTerritoryPreview()
    }

    private fun maybeRefreshTerritoryPreview() {
        val st = _ui.value
        if (!st.isSessionRunning || st.routePoints.size < 2) return
        val now = System.currentTimeMillis()
        val pointCount = st.routePoints.size
        if (now - lastTerritoryPreviewAtMs < 15_000 && pointCount - lastTerritoryPreviewPointCount < 8) {
            return
        }
        lastTerritoryPreviewAtMs = now
        lastTerritoryPreviewPointCount = pointCount
        val routeJson = routeGeoJsonLineString() ?: return
        territoryPreviewJob?.cancel()
        territoryPreviewJob = viewModelScope.launch {
            val preview = TerritoryCaptureClient.previewCapture(supabase, routeJson) ?: return@launch
            val rings = preview.cells.mapNotNull { cell ->
                cell.cellGeojson?.ringLatLng()?.takeIf { it.size >= 3 }
            }
            _ui.value = _ui.value.copy(territoryPreviewRings = rings)
        }
    }

    private fun recordKmSplitsIfNeeded() {
        val km = routeDistanceM / 1000.0
        val n = floor(km).toInt().coerceAtLeast(0)
        val elapsed = _ui.value.elapsedSec
        while (splitCumulativeSec.size < n) {
            splitCumulativeSec.add(elapsed)
        }
        _ui.value = _ui.value.copy(kmSplitCumulativeSec = splitCumulativeSec.toList())
    }

    private fun distMeters(a: Pair<Double, Double>, b: Pair<Double, Double>): Double {
        val r = 6371000.0
        val dLat = Math.toRadians(b.first - a.first)
        val dLon = Math.toRadians(b.second - a.second)
        val x = kotlin.math.sin(dLat / 2) * kotlin.math.sin(dLat / 2) +
            kotlin.math.cos(Math.toRadians(a.first)) * kotlin.math.cos(Math.toRadians(b.first)) *
            kotlin.math.sin(dLon / 2) * kotlin.math.sin(dLon / 2)
        return 2 * r * kotlin.math.asin(kotlin.math.min(1.0, kotlin.math.sqrt(x)))
    }

    private fun routeGeoJsonLineString(): String? {
        val copy = synchronized(routePoints) { routePoints.toList() }
        if (copy.size < 2) return null
        val trimmed = CardioRouteGeoJson.decimateLatLngPairs(copy)
        val coords = trimmed.joinToString(",") { "[${it.second},${it.first}]" }
        return """{"type":"LineString","coordinates":[$coords]}"""
    }

    fun toggleSessionRunning() {
        if (_ui.value.finishing) return
        _ui.value = _ui.value.copy(isSessionRunning = !_ui.value.isSessionRunning)
    }

    fun resetSession() {
        if (_ui.value.finishing) return
        val s = _ui.value
        if (s.isSessionRunning || s.elapsedSec == 0) return
        synchronized(routePoints) {
            routePoints.clear()
        }
        routeDistanceM = 0.0
        splitCumulativeSec.clear()
        _ui.value = s.copy(
            isSessionRunning = false,
            elapsedSec = 0,
            distanceText = initialDistanceText,
            routePoints = emptyList(),
            territoryPreviewRings = emptyList(),
            kmSplitCumulativeSec = emptyList()
        )
    }

    fun load() {
        viewModelScope.launch {
            _ui.value = _ui.value.copy(loading = true, loadError = null)
            runCatching {
                supabase.auth.currentUserOrNull()?.id ?: error("No session")

                val cRes = supabase
                    .from(BackendContracts.Tables.CARDIO_SESSIONS)
                    .select(
                        columns = Columns.raw("id, activity_code, modality, distance_km, duration_sec")
                    ) {
                        filter { eq("workout_id", workoutId) }
                        limit(1)
                    }
                val rows = decodeFlexibleList<CardioSessionWire>(cRes.data)
                if (rows.isEmpty()) {
                    _ui.value = _ui.value.copy(loading = false, loadError = null, hasCardioSession = false)
                    return@runCatching
                }
                if (startedAtPatched.compareAndSet(false, true)) {
                    patchWorkoutStartedAtNow(supabase, workoutId)
                }
                val row = rows.first()
                cardioSessionId = row.id
                val rawCode = (row.activityCode ?: row.modality ?: "cardio")
                val label = rawCode.split('_').joinToString(" ") { part ->
                    part.replaceFirstChar { c -> if (c.isLowerCase()) c.titlecase() else c.toString() }
                }
                var dist = ""
                row.distanceKm?.let { km ->
                    dist = if (km == km.roundToInt().toDouble()) {
                        km.roundToInt().toString()
                    } else {
                        String.format("%.2f", km)
                    }
                }
                initialDistanceText = dist
                val prof = withContext(Dispatchers.IO) { CardioGpsPreferences.readProfile(app) }
                val dur = row.durationSec?.takeIf { it > 0 }
                val timerMode =
                    if (dur != null) CardioTimerMode.COUNTDOWN else CardioTimerMode.STOPWATCH
                _ui.value = _ui.value.copy(
                    loading = false,
                    loadError = null,
                    hasCardioSession = true,
                    activityLabel = label,
                    targetDistanceKm = row.distanceKm,
                    targetDurationSec = dur,
                    distanceText = dist,
                    gpsProfile = prof,
                    timerMode = timerMode,
                    kmSplitCumulativeSec = emptyList(),
                    isSessionRunning = false,
                    elapsedSec = 0
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
                val km = parseDistanceKm(_ui.value.distanceText)

                val routeJson = routeGeoJsonLineString()
                supabase.from(BackendContracts.Tables.CARDIO_SESSIONS).update(
                    buildJsonObject {
                        put("duration_sec", elapsed)
                        if (km != null) put("distance_km", km)
                        if (routeJson != null) put("route_geojson", JsonPrimitive(routeJson))
                    }
                ) {
                    filter { eq("workout_id", workoutId) }
                }

                val distTrim = _ui.value.distanceText.trim().replace(',', '.')
                val manualKm = distTrim.toDoubleOrNull() ?: (routeDistanceM / 1000.0)
                val gpsKm = routeDistanceM / 1000.0
                val distEdited = initialDistanceText.trim() != _ui.value.distanceText.trim()
                val usesGps = routePoints.size >= 2
                val splitSeconds = KmPaceSplitCalculator.kmPaceSplitSecondsPerKm(
                    usesGps = usesGps,
                    distanceFieldUserEdited = distEdited,
                    manualKm = manualKm,
                    gpsKm = gpsKm,
                    elapsedSec = elapsed,
                    gpsCumulative = splitCumulativeSec.toList()
                )
                if (cardioSessionId > 0) {
                    val existing = runCatching {
                        val sRes = supabase
                            .from(BackendContracts.Tables.CARDIO_SESSION_STATS)
                            .select(columns = Columns.raw("stats")) {
                                filter { eq("session_id", cardioSessionId) }
                                limit(1)
                            }
                        parseStatsInnerObject(sRes.data)
                    }.getOrElse { buildJsonObject { } }
                    val mergedStats = CardioKmPaceSplits.mergeStatsObject(
                        existing,
                        splitSeconds
                    )
                    supabase.from(BackendContracts.Tables.CARDIO_SESSION_STATS).upsert(
                        buildJsonObject {
                            put("session_id", cardioSessionId)
                            put("stats", mergedStats)
                        }
                    ) {
                        onConflict = "session_id"
                    }
                }

                val nRes = supabase
                    .from(BackendContracts.Tables.WORKOUTS)
                    .select(columns = Columns.raw("notes, state")) {
                        filter { eq("id", workoutId) }
                        limit(1)
                    }
                val wRow = decodeFlexibleList<WorkoutNotesStateRow>(nRes.data).firstOrNull()
                val avgPaceSec = if (manualKm >= 0.01) (elapsed / manualKm).roundToInt() else null
                val gpsNoteBlock = buildGpsWorkoutNotesAppendix(
                    splitPaceSecPerKm = splitSeconds,
                    avgPaceSecPerKm = avgPaceSec
                )
                val mergedNotes = mergeWorkoutNotesForFinish(wRow?.notes, gpsNoteBlock)
                supabase.from(BackendContracts.Tables.WORKOUTS).update(
                    workoutFinishUpdateJson(ended, mergedNotes, wRow?.state)
                ) {
                    filter { eq("id", workoutId) }
                }
            }.onSuccess {
                routeGeoJsonLineString()?.let {
                    val summary = TerritoryCaptureClient.applyCapture(supabase, workoutId)
                    summary?.let { captured ->
                        TerritoryCaptureClient.storeCaptureReferenceCoordinate(app, captured)
                    }
                    TerritoryCaptureClient.captureMessage(summary ?: return@let)?.let { message ->
                        if (summary?.ok == true) {
                            AppSnackbar.showSuccess(message)
                        } else {
                            AppSnackbar.showError(message)
                        }
                    }
                }
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

    private inline fun <reified T> decodeFlexibleList(raw: String): List<T> {
        val root = json.parseToJsonElement(raw)
        return when (root) {
            is JsonArray -> root.map { json.decodeFromString<T>(it.toString()) }
            is JsonObject -> listOf(json.decodeFromString<T>(raw))
            else -> emptyList()
        }
    }

    private fun parseStatsInnerObject(raw: String): JsonObject {
        val r = raw.trim()
        if (r.isEmpty()) return buildJsonObject { }
        return runCatching {
            when (val root = json.parseToJsonElement(r)) {
                is JsonArray -> {
                    val o = root.firstOrNull() as? JsonObject ?: return@runCatching buildJsonObject { }
                    o["stats"]?.jsonObject ?: buildJsonObject { }
                }
                is JsonObject -> root["stats"]?.jsonObject ?: root
                else -> buildJsonObject { }
            }
        }.getOrDefault(buildJsonObject { })
    }
}

@Serializable
private data class CardioSessionWire(
    val id: Int,
    @SerialName("activity_code") val activityCode: String? = null,
    val modality: String? = null,
    @SerialName("distance_km") val distanceKm: Double? = null,
    @SerialName("duration_sec") val durationSec: Int? = null
)

private fun parseDistanceKm(text: String): Double? {
    val trimmed = text.trim().replace(',', '.')
    if (trimmed.isEmpty()) return null
    return trimmed.toDoubleOrNull()
}

private const val TAG = "ActiveCardio"

class ActiveCardioWorkoutViewModelFactory(
    private val app: Application,
    private val supabase: SupabaseClient,
    private val workoutId: Int
) : ViewModelProvider.Factory {
    @Suppress("UNCHECKED_CAST")
    override fun <T : ViewModel> create(modelClass: Class<T>): T {
        if (modelClass != ActiveCardioWorkoutViewModel::class.java) {
            error("Unknown ViewModel: ${modelClass.name}")
        }
        return ActiveCardioWorkoutViewModel(app, supabase, workoutId) as T
    }
}
