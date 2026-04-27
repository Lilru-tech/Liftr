package com.lilru.liftr.ui.profile.progress

import android.app.Application
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.lilru.liftr.data.BackendContracts
import com.lilru.liftr.ui.add.AddCardioActivity
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.query.Columns
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlin.math.max
import kotlin.math.roundToInt

data class ConsistencyDrillDownUiState(
    val loading: Boolean = true,
    val error: String? = null,
    val consistencyMetric: ConsistencyChartMetric = ConsistencyChartMetric.DURATION,
    val slices: List<DrilldownSlice> = emptyList(),
    val totalDurationMin: Int = 0
) {
    fun effectiveMetric(): ConsistencyChartMetric {
        fun tot(m: ConsistencyChartMetric) = slices.sumOf { s ->
            m.measure(s.durationMin, s.count, s.score, s.kcal)
        }
        if (tot(consistencyMetric) > 0) return consistencyMetric
        for (m in ConsistencyChartMetric.entries) {
            if (tot(m) > 0) return m
        }
        return consistencyMetric
    }
}

@Serializable
private data class SportR(
    @SerialName("workout_id") val workoutId: Int,
    val sport: String? = null
)

@Serializable
private data class CardioR(
    @SerialName("workout_id") val workoutId: Int,
    @SerialName("activity_code") val activityCode: String? = null,
    val modality: String? = null
)

@Serializable
private data class MuscleRef(
    @SerialName("muscle_primary") val musclePrimary: String? = null
)

@Serializable
private data class WeR(
    @SerialName("workout_id") val workoutId: Int,
    val exercises: MuscleRef? = null
)

class ConsistencyDrillDownViewModel(
    private val app: Application,
    private val supabase: SupabaseClient,
    private val rootKind: String,
    private val workoutMeta: Map<Int, ConsistencyWorkoutMeta>
) : ViewModel() {
    private val json = Json {
        ignoreUnknownKeys = true
        isLenient = true
        coerceInputValues = true
    }

    private val _uiState = MutableStateFlow(ConsistencyDrillDownUiState())
    val uiState: StateFlow<ConsistencyDrillDownUiState> = _uiState.asStateFlow()

    init {
        viewModelScope.launch {
            val m = withContext(Dispatchers.IO) {
                ProfileProgressMetricPreferences.readDrilldownMetric(app)
            }
            _uiState.update { it.copy(consistencyMetric = m) }
            load()
        }
    }

    fun setMetric(m: ConsistencyChartMetric) {
        _uiState.update { it.copy(consistencyMetric = m) }
        viewModelScope.launch(Dispatchers.IO) {
            ProfileProgressMetricPreferences.setDrilldownMetric(app, m)
        }
    }

    private fun load() {
        viewModelScope.launch {
            _uiState.update { it.copy(loading = true, error = null) }
            runCatching {
                val ids = workoutMeta.filter { it.value.kind.equals(rootKind, ignoreCase = true) }.keys.toList()
                if (ids.isEmpty()) {
                    _uiState.update { it.copy(loading = false, slices = emptyList(), totalDurationMin = 0) }
                    return@runCatching
                }
                val result = when (rootKind.lowercase()) {
                    "sport" -> loadSport(ids)
                    "cardio" -> loadCardio(ids)
                    "strength" -> loadStrength(ids)
                    else -> emptyList()
                }
                val totalM = result.sumOf { it.durationMin }
                _uiState.update {
                    it.copy(loading = false, slices = result, totalDurationMin = totalM, error = null)
                }
            }.onFailure { e ->
                _uiState.update {
                    it.copy(loading = false, error = e.message?.take(300) ?: e::class.java.simpleName)
                }
            }
        }
    }

    private suspend fun loadSport(ids: List<Int>): List<DrilldownSlice> {
        val res = supabase.from(BackendContracts.Tables.SPORT_SESSIONS)
            .select(columns = Columns.raw("workout_id, sport")) {
                filter { isIn("workout_id", ids.map { it.toString() }) }
            }
        val rows = decodeList<SportR>(res.data)
        val firstByW = LinkedHashMap<Int, String>()
        for (r in rows) {
            val name = (r.sport ?: "").trim()
            if (name.isEmpty()) continue
            if (!firstByW.containsKey(r.workoutId)) {
                firstByW[r.workoutId] = name
            }
        }
        return aggregateByLabel(ids) { wid ->
            firstByW[wid]?.let { displaySport(it) }
        }
    }

    private suspend fun loadCardio(ids: List<Int>): List<DrilldownSlice> {
        val res = supabase.from(BackendContracts.Tables.CARDIO_SESSIONS)
            .select(columns = Columns.raw("workout_id, activity_code, modality")) {
                filter { isIn("workout_id", ids.map { it.toString() }) }
            }
        val rows = decodeList<CardioR>(res.data)
        val firstByW = LinkedHashMap<Int, String>()
        for (r in rows) {
            val raw = if (!r.activityCode.isNullOrBlank()) r.activityCode else (r.modality ?: "")
            val t = raw.trim()
            if (t.isEmpty()) continue
            if (!firstByW.containsKey(r.workoutId)) {
                firstByW[r.workoutId] = t.lowercase()
            }
        }
        return aggregateByLabel(ids) { wid ->
            firstByW[wid]?.let { displayCardioCode(it) }
        }
    }

    private suspend fun loadStrength(ids: List<Int>): List<DrilldownSlice> {
        val res = supabase.from(BackendContracts.Tables.WORKOUT_EXERCISES)
            .select(columns = Columns.raw("workout_id, exercises(muscle_primary)")) {
                filter { isIn("workout_id", ids.map { it.toString() }) }
            }
        val rows = decodeList<WeR>(res.data)
        val musclesByW = mutableMapOf<Int, MutableSet<String>>()
        for (r in rows) {
            val m = (r.exercises?.musclePrimary ?: "").trim().lowercase()
            val key = if (m.isEmpty() || m == "cardio") "other" else m
            musclesByW.getOrPut(r.workoutId) { mutableSetOf() }.add(key)
        }
        val countBy = mutableMapOf<String, Int>()
        val minBy = mutableMapOf<String, Int>()
        val scoreBy = mutableMapOf<String, Double>()
        val kcalBy = mutableMapOf<String, Double>()
        for (wid in ids) {
            val meta = workoutMeta[wid] ?: continue
            val dm = meta.durationMin
            val sc = meta.score
            val kc = meta.kcal
            val muscles = musclesByW[wid] ?: setOf("other")
            val n = max(1, muscles.size)
            val shareDur = dm / n
            val shareSc = sc / n
            val shareKc = kc / n
            for (m in muscles) {
                val label = displayMuscle(m)
                countBy[label] = (countBy[label] ?: 0) + 1
                minBy[label] = (minBy[label] ?: 0) + shareDur
                scoreBy[label] = (scoreBy[label] ?: 0.0) + shareSc
                kcalBy[label] = (kcalBy[label] ?: 0.0) + shareKc
            }
        }
        return countBy.keys.sortedWith(compareBy { it.lowercase() }).map { k ->
            DrilldownSlice(
                title = k,
                count = countBy[k] ?: 0,
                durationMin = minBy[k] ?: 0,
                score = scoreBy[k] ?: 0.0,
                kcal = kcalBy[k] ?: 0.0
            )
        }
    }

    private fun aggregateByLabel(
        workoutIds: List<Int>,
        labelForWorkout: (Int) -> String?
    ): List<DrilldownSlice> {
        val countBy = mutableMapOf<String, Int>()
        val minBy = mutableMapOf<String, Int>()
        val scoreBy = mutableMapOf<String, Double>()
        val kcalBy = mutableMapOf<String, Double>()
        for (wid in workoutIds) {
            val meta = workoutMeta[wid] ?: continue
            val label = labelForWorkout(wid) ?: "Other"
            val dm = meta.durationMin
            val sc = meta.score
            val kc = meta.kcal
            countBy[label] = (countBy[label] ?: 0) + 1
            minBy[label] = (minBy[label] ?: 0) + dm
            scoreBy[label] = (scoreBy[label] ?: 0.0) + sc
            kcalBy[label] = (kcalBy[label] ?: 0.0) + kc
        }
        return countBy.keys.sortedWith(compareBy { it.lowercase() }).map { k ->
            DrilldownSlice(
                title = k,
                count = countBy[k] ?: 0,
                durationMin = minBy[k] ?: 0,
                score = scoreBy[k] ?: 0.0,
                kcal = kcalBy[k] ?: 0.0
            )
        }
    }

    private fun displaySport(raw: String) = raw.trim()
        .split(" ")
        .joinToString(" ") { p -> p.replaceFirstChar { c -> c.titlecase() } }

    private fun displayCardioCode(code: String): String {
        val c = code.lowercase()
        val m = AddCardioActivity.entries.firstOrNull { it.wire == c }
        if (m != null) {
            return m.name.replace("_", " ").lowercase()
                .split(" ")
                .joinToString(" ") { p -> p.replaceFirstChar { ch -> ch.titlecase() } }
        }
        return c.replace("_", " ").split(" ")
            .joinToString(" ") { p -> p.replaceFirstChar { ch -> ch.titlecase() } }
    }

    private fun displayMuscle(key: String): String =
        if (key == "other") "Other" else key.replace("_", " ").split(" ")
            .joinToString(" ") { p -> p.replaceFirstChar { c -> c.titlecase() } }

    private inline fun <reified T> decodeList(raw: String): List<T> {
        val root = json.parseToJsonElement(raw)
        return when (root) {
            is JsonArray -> root.map { json.decodeFromString<T>(it.toString()) }
            is JsonObject -> listOf(json.decodeFromString<T>(root.toString()))
            else -> emptyList()
        }
    }
}

class ConsistencyDrillDownViewModelFactory(
    private val app: Application,
    private val supabase: SupabaseClient,
    private val rootKind: String,
    private val workoutMeta: Map<Int, ConsistencyWorkoutMeta>
) : ViewModelProvider.Factory {
    @Suppress("UNCHECKED_CAST")
    override fun <T : ViewModel> create(modelClass: Class<T>): T {
        if (modelClass != ConsistencyDrillDownViewModel::class.java) {
            error("Unknown ViewModel: ${modelClass.name}")
        }
        return ConsistencyDrillDownViewModel(app, supabase, rootKind, workoutMeta) as T
    }
}
