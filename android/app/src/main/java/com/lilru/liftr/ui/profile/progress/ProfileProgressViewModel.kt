package com.lilru.liftr.ui.profile.progress

import android.app.Application
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.lilru.liftr.data.BackendContracts
import com.lilru.liftr.data.SupabaseResponseDecoding
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.query.Columns
import io.github.jan.supabase.postgrest.query.Order
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZonedDateTime
import java.time.temporal.TemporalAdjusters
import java.util.Locale
import kotlin.math.max
import kotlin.math.roundToInt

/** Resumen total / media / mejor día / racha (alineado a [Liftr/ProfileView.swift]). */
data class ProgressMetricSummary(
    val total: Double,
    val avgPerWorkout: Double,
    val bestLabel: String,
    val bestValue: Double,
    val streakDays: Int,
    val perMinute: Double
)

data class ProfileProgressUiState(
    val loading: Boolean = true,
    val error: String? = null,
    val range: ProfileProgressRange = ProfileProgressRange.WEEK,
    val subtab: ProfileProgressSubtab = ProfileProgressSubtab.CONSISTENCY,
    val activityMetric: ProfileActivityMetric = ProfileActivityMetric.WORKOUTS,
    val consistencyMetric: ConsistencyChartMetric = ConsistencyChartMetric.DURATION,
    val weekdayMetric: WeekdayProgressMetric = WeekdayProgressMetric.WORKOUTS,
    val kindDistribution: List<KindSlice> = emptyList(),
    val totalDurationMin: Int = 0,
    val consistencyActiveBuckets: Int = 0,
    val consistencyBucketTotal: Int = 0,
    val progressPoints: List<ProgressPoint> = emptyList(),
    val weekdayPoints: List<WeekdayPointUi> = emptyList(),
    val workoutMeta: Map<Int, ConsistencyWorkoutMeta> = emptyMap(),
    val activityCaloriesSummary: ProgressMetricSummary? = null,
    val activityScoreSummary: ProgressMetricSummary? = null
) {
    fun effectiveConsistencyMetric(): ConsistencyChartMetric {
        val slices = kindDistribution
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
private data class WRow(
    val id: Int,
    @SerialName("started_at") val startedAt: String? = null,
    val kind: String = "",
    @SerialName("duration_min") val durationMin: Int? = null,
    @SerialName("calories_kcal") val caloriesKcal: Double? = null,
    val state: String? = null
)

@Serializable
private data class ScoreR(
    @SerialName("workout_id") val workoutId: Int,
    val score: Double
)

@Serializable
private data class DRow(
    @SerialName("workout_id") val workoutId: Int,
    @SerialName("duration_sec") val durationSec: Int? = null
)

private data class TimeWindow(
    val start: ZonedDateTime,
    val endExclusive: ZonedDateTime,
    val bucketCount: Int
)

class ProfileProgressViewModel(
    private val app: Application,
    private val supabase: SupabaseClient,
    private val userId: String
) : ViewModel() {
    private val zone: ZoneId = ZoneId.systemDefault()

    private val _uiState = MutableStateFlow(ProfileProgressUiState())
    val uiState: StateFlow<ProfileProgressUiState> = _uiState.asStateFlow()

    init {
        viewModelScope.launch {
            val m = withContext(Dispatchers.IO) {
                ProfileProgressMetricPreferences.readRootMetric(app)
            }
            _uiState.update { it.copy(consistencyMetric = m) }
            load()
        }
    }

    fun setRange(r: ProfileProgressRange) {
        _uiState.update { it.copy(range = r) }
        load()
    }

    fun setSubtab(s: ProfileProgressSubtab) {
        _uiState.update { it.copy(subtab = s) }
        load()
    }

    fun setActivityMetric(m: ProfileActivityMetric) {
        _uiState.update { it.copy(activityMetric = m) }
        load()
    }

    fun setConsistencyMetric(m: ConsistencyChartMetric) {
        _uiState.update { it.copy(consistencyMetric = m) }
        viewModelScope.launch(Dispatchers.IO) {
            ProfileProgressMetricPreferences.setRootMetric(app, m)
        }
    }

    fun setWeekdayMetric(m: WeekdayProgressMetric) {
        _uiState.update { it.copy(weekdayMetric = m) }
    }

    fun load() {
        viewModelScope.launch {
            _uiState.update { it.copy(loading = true, error = null) }
            runCatching {
                val st = _uiState.value
                val w = timeWindow(st.range, ZonedDateTime.now(zone))
                val buckets = buildBucketLabels(st.range, w)
                val startIso = w.start.toInstant().toString()
                val endIso = w.endExclusive.toInstant().toString()
                val wRes = supabase.from(BackendContracts.Tables.WORKOUTS)
                    .select(
                        columns = Columns.raw("id, started_at, kind, duration_min, calories_kcal, state")
                    ) {
                        filter {
                            eq("user_id", userId)
                            gte("started_at", startIso)
                            lt("started_at", endIso)
                        }
                        order("started_at", Order.ASCENDING)
                    }
                val workouts = SupabaseResponseDecoding.decodeListOrObject<WRow>(wRes.data)
                val ids = workouts.map { it.id }
                val scoreByW = mutableMapOf<Int, Double>()
                if (ids.isNotEmpty()) {
                    val sRes = supabase.from(BackendContracts.Tables.WORKOUT_SCORES)
                        .select(columns = Columns.raw("workout_id, score")) {
                            filter { isIn("workout_id", ids.map { it.toString() }) }
                        }
                    for (r in SupabaseResponseDecoding.decodeListOrObject<ScoreR>(sRes.data)) {
                        scoreByW[r.workoutId] = (scoreByW[r.workoutId] ?: 0.0) + r.score
                    }
                }
                val durByW = mutableMapOf<Int, Int>()
                for (w0 in workouts) {
                    w0.durationMin?.let { durByW[w0.id] = max(0, it) }
                }
                if (ids.isNotEmpty()) {
                    val cRes = supabase.from(BackendContracts.Tables.CARDIO_SESSIONS)
                        .select(columns = Columns.raw("workout_id, duration_sec")) {
                            filter { isIn("workout_id", ids.map { it.toString() }) }
                        }
                    for (r in SupabaseResponseDecoding.decodeListOrObject<DRow>(cRes.data)) {
                        if (r.durationSec != null && !durByW.containsKey(r.workoutId)) {
                            durByW[r.workoutId] = max(0, (r.durationSec!! / 60.0).roundToInt())
                        }
                    }
                    val s2 = supabase.from(BackendContracts.Tables.SPORT_SESSIONS)
                        .select(columns = Columns.raw("workout_id, duration_sec")) {
                            filter { isIn("workout_id", ids.map { it.toString() }) }
                        }
                    for (r in SupabaseResponseDecoding.decodeListOrObject<DRow>(s2.data)) {
                        if (r.durationSec != null && !durByW.containsKey(r.workoutId)) {
                            durByW[r.workoutId] = max(0, (r.durationSec!! / 60.0).roundToInt())
                        }
                    }
                }
                val bKeys = buckets.map { it.first }
                var bucketsCount = bKeys.associateWith { 0 }.toMutableMap()
                var bucketsScore = bKeys.associateWith { 0.0 }.toMutableMap()
                var bucketsKcal = bKeys.associateWith { 0.0 }.toMutableMap()
                val kindCount = mutableMapOf<String, Int>()
                val kindMins = mutableMapOf<String, Int>()
                val kindSc = mutableMapOf<String, Double>()
                val kindKc = mutableMapOf<String, Double>()
                var totalMins = 0
                val metaCollector = mutableMapOf<Int, ConsistencyWorkoutMeta>()
                val weekdayOcc = weekdayOccurrenceCounts(w.start, w.endExclusive)
                val wkLabels = defaultWeekdayLabelsForLocale(Locale.getDefault())
                val weekdayW = IntArray(7)
                val weekdaySc = DoubleArray(7)
                val weekdayKc = DoubleArray(7)
                val weekdayDm = IntArray(7)
                // Paridad con iOS [loadProgress] weekday*Totals: se acumula por filas ya filtradas en la query,
                // no depende de encajar en la clave de bucket del gráfico Activity/Consistency. Si no, un desfase
                // (p. ej. emulador UTC) puede vaciar el bloque "Weekday" aunque haya entrenos.
                for (wk in workouts) {
                    val t = wk.startedAt?.let { parseInstant(it) } ?: continue
                    if ((wk.state ?: "published") == "planned") continue
                    if (t < w.start.toInstant() || t >= w.endExclusive.toInstant()) continue
                    val widx = (t.atZone(zone).toLocalDate().dayOfWeek.value + 6) % 7
                    val scW = scoreByW[wk.id] ?: 0.0
                    val kcW = wk.caloriesKcal ?: 0.0
                    val dmW = durByW[wk.id] ?: 0
                    weekdayW[widx] += 1
                    weekdaySc[widx] += scW
                    weekdayKc[widx] += kcW
                    weekdayDm[widx] += dmW
                }
                for (wk in workouts) {
                    val t = wk.startedAt?.let { parseInstant(it) } ?: continue
                    if ((wk.state ?: "published") == "planned") continue
                    val bk = bucketKeyForInstant(t, st.range) ?: continue
                    if (bk !in bucketsCount) continue
                    bucketsCount[bk] = (bucketsCount[bk] ?: 0) + 1
                    val sc = scoreByW[wk.id] ?: 0.0
                    bucketsScore[bk] = (bucketsScore[bk] ?: 0.0) + sc
                    val kcal = wk.caloriesKcal ?: 0.0
                    bucketsKcal[bk] = (bucketsKcal[bk] ?: 0.0) + kcal
                    val k = wk.kind.lowercase()
                    kindCount[k] = (kindCount[k] ?: 0) + 1
                    val dm = durByW[wk.id] ?: 0
                    kindMins[k] = (kindMins[k] ?: 0) + dm
                    kindSc[k] = (kindSc[k] ?: 0.0) + sc
                    kindKc[k] = (kindKc[k] ?: 0.0) + kcal
                    totalMins += dm
                    metaCollector[wk.id] = ConsistencyWorkoutMeta(k, dm, sc, kcal)
                }
                val weekdayList = (0..6).map { idx ->
                    WeekdayPointUi(
                        weekdayIndex = idx,
                        label = wkLabels.getOrElse(idx) { "?" },
                        occurrences = weekdayOcc[idx],
                        workoutsTotal = weekdayW[idx],
                        scoreTotal = weekdaySc[idx],
                        caloriesTotal = weekdayKc[idx],
                        durationMinutesTotal = weekdayDm[idx]
                    )
                }
                val slices = listOf("strength", "cardio", "sport").mapNotNull { k ->
                    val c = kindCount[k] ?: 0
                    if (c <= 0) null else KindSlice(
                        kind = k,
                        count = c,
                        durationMin = kindMins[k] ?: 0,
                        score = kindSc[k] ?: 0.0,
                        kcal = kindKc[k] ?: 0.0
                    )
                }
                val (activeB, totalB) = when (st.range) {
                    ProfileProgressRange.WEEK, ProfileProgressRange.MONTH -> {
                        val active = bucketsCount.values.count { it > 0 }
                        Pair(active, w.bucketCount)
                    }
                    ProfileProgressRange.YEAR -> {
                        val wStart = w.start.toLocalDate()
                        val wEnd = w.endExclusive.toLocalDate()
                        var days = 0
                        var p = wStart
                        while (p < wEnd) {
                            days++
                            p = p.plusDays(1)
                        }
                        val set = mutableSetOf<LocalDate>()
                        for (wk in workouts) {
                            val t = wk.startedAt?.let { parseInstant(it) } ?: continue
                            if ((wk.state ?: "published") == "planned") continue
                            val day = t.atZone(zone).toLocalDate()
                            if (!day.isBefore(wStart) && day.isBefore(wEnd)) {
                                set.add(day)
                            }
                        }
                        Pair(set.size, max(0, days))
                    }
                }
                var points: List<ProgressPoint> = emptyList()
                when (st.subtab) {
                    ProfileProgressSubtab.ACTIVITY -> {
                        points = buckets.map { (k, label) ->
                            val v = when (st.activityMetric) {
                                ProfileActivityMetric.WORKOUTS -> (bucketsCount[k] ?: 0).toDouble()
                                ProfileActivityMetric.SCORE -> bucketsScore[k] ?: 0.0
                                ProfileActivityMetric.CALORIES -> bucketsKcal[k] ?: 0.0
                            }
                            ProgressPoint(label, v)
                        }
                    }
                    ProfileProgressSubtab.INTENSITY -> {
                        points = buckets.map { (k, label) ->
                            val c = max(1, bucketsCount[k] ?: 0)
                            val avg = (bucketsScore[k] ?: 0.0) / c
                            ProgressPoint(label, avg)
                        }
                    }
                    ProfileProgressSubtab.CONSISTENCY, ProfileProgressSubtab.WEEKDAY -> { }
                }
                val publishedWorkoutCount = workouts.count { (it.state ?: "published") != "planned" }
                var calSum: ProgressMetricSummary? = null
                var scoreSum: ProgressMetricSummary? = null
                if (st.subtab == ProfileProgressSubtab.ACTIVITY) {
                    val totK = bucketsKcal.values.sum()
                    val totS = bucketsScore.values.sum()
                    val avgK = if (publishedWorkoutCount > 0) totK / publishedWorkoutCount else 0.0
                    val avgS = if (publishedWorkoutCount > 0) totS / publishedWorkoutCount else 0.0
                    val (bestKL, bestKV) = bestBucket(
                        buckets, bucketsKcal
                    ) { a, b -> a > b }
                    val (bestSL, bestSV) = bestBucket(
                        buckets, bucketsScore
                    ) { a, b -> a > b }
                    val streak = if (st.range == ProfileProgressRange.YEAR) {
                        0
                    } else {
                        streakFromEnd(
                            w = w,
                            buckets = buckets,
                            hasActivity = { k -> (bucketsCount[k] ?: 0) > 0 }
                        )
                    }
                    val kcalPerMin = if (totalMins > 0) totK / totalMins else 0.0
                    val scPerMin = if (totalMins > 0) totS / totalMins else 0.0
                    if (st.activityMetric == ProfileActivityMetric.CALORIES) {
                        calSum = ProgressMetricSummary(
                            total = totK,
                            avgPerWorkout = avgK,
                            bestLabel = bestKL,
                            bestValue = bestKV,
                            streakDays = streak,
                            perMinute = kcalPerMin
                        )
                    }
                    if (st.activityMetric == ProfileActivityMetric.SCORE) {
                        scoreSum = ProgressMetricSummary(
                            total = totS,
                            avgPerWorkout = avgS,
                            bestLabel = bestSL,
                            bestValue = bestSV,
                            streakDays = streak,
                            perMinute = scPerMin
                        )
                    }
                }
                _uiState.update {
                    it.copy(
                        loading = false,
                        error = null,
                        kindDistribution = slices,
                        totalDurationMin = totalMins,
                        consistencyActiveBuckets = activeB,
                        consistencyBucketTotal = totalB,
                        progressPoints = points,
                        weekdayPoints = weekdayList,
                        workoutMeta = metaCollector,
                        activityCaloriesSummary = calSum,
                        activityScoreSummary = scoreSum
                    )
                }
            }.onFailure { e ->
                _uiState.update {
                    it.copy(loading = false, error = e.message?.take(300) ?: e::class.java.simpleName)
                }
            }
        }
    }

    fun metaForRootKind(rootKind: String): Map<Int, ConsistencyWorkoutMeta> {
        val k = rootKind.lowercase()
        return _uiState.value.workoutMeta.filter { it.value.kind == k }
    }

    private fun weekdayOccurrenceCounts(start: ZonedDateTime, endExclusive: ZonedDateTime): IntArray {
        val counts = IntArray(7)
        var d = start.toLocalDate()
        val end = endExclusive.toLocalDate()
        while (d < end) {
            val idx = (d.dayOfWeek.value + 6) % 7
            counts[idx]++
            d = d.plusDays(1)
        }
        return counts
    }

    private fun timeWindow(
        r: ProfileProgressRange,
        now: ZonedDateTime
    ): TimeWindow = when (r) {
        ProfileProgressRange.WEEK -> {
            val end = now.toLocalDate().plusDays(1).atStartOfDay(zone)
            val start = now.toLocalDate().minusDays(6).atStartOfDay(zone)
            TimeWindow(start, end, 7)
        }
        ProfileProgressRange.MONTH -> {
            val end = now.toLocalDate().plusDays(1).atStartOfDay(zone)
            val start = now.toLocalDate().minusDays(29).atStartOfDay(zone)
            TimeWindow(start, end, 30)
        }
        ProfileProgressRange.YEAR -> {
            val monthStart = now.with(TemporalAdjusters.firstDayOfMonth()).toLocalDate()
            val startDate = monthStart.minusMonths(11)
            val start = startDate.atStartOfDay(zone)
            val end = now.toLocalDate().plusDays(1).atStartOfDay(zone)
            TimeWindow(start, end, 12)
        }
    }

    private fun buildBucketLabels(
        r: ProfileProgressRange,
        w: TimeWindow
    ): List<Pair<Long, String>> = when (r) {
        ProfileProgressRange.WEEK, ProfileProgressRange.MONTH -> {
            val out = ArrayList<Pair<Long, String>>()
            var c = w.start
            val fmtDay = java.time.format.DateTimeFormatter.ofPattern("EEE")
            repeat(w.bucketCount) {
                val key = c.toLocalDate().toEpochDay()
                val label = c.format(fmtDay)
                out.add(key to label)
                c = c.plusDays(1)
            }
            out
        }
        ProfileProgressRange.YEAR -> {
            val out = ArrayList<Pair<Long, String>>()
            var c = w.start
            val fmtM = java.time.format.DateTimeFormatter.ofPattern("MMM")
            repeat(12) {
                val y = c.year
                val m = c.monthValue
                val key = (y * 12L) + m
                val label = c.format(fmtM)
                out.add(key to label)
                c = c.plusMonths(1)
            }
            out
        }
    }

    private fun bucketKeyForInstant(
        t: Instant,
        r: ProfileProgressRange
    ): Long? = when (r) {
        ProfileProgressRange.WEEK, ProfileProgressRange.MONTH -> {
            val d = t.atZone(zone).toLocalDate()
            d.toEpochDay()
        }
        ProfileProgressRange.YEAR -> {
            val z = t.atZone(zone)
            (z.year * 12L) + z.monthValue
        }
    }

    private fun parseInstant(s: String): Instant {
        val t = s.trim()
        val a = runCatching { Instant.parse(t) }.getOrNull()
        if (a != null) return a
        if (t.length >= 10) {
            return runCatching {
                LocalDate.parse(t.substring(0, 10)).atStartOfDay(ZoneId.systemDefault()).toInstant()
            }.getOrElse { Instant.EPOCH }
        }
        return Instant.EPOCH
    }

    private fun bestBucket(
        buckets: List<Pair<Long, String>>,
        map: Map<Long, Double>,
        isBetter: (Double, Double) -> Boolean
    ): Pair<String, Double> {
        if (buckets.isEmpty()) return "—" to 0.0
        var bestL = buckets[0].second
        var bestV = 0.0
        for ((k, label) in buckets) {
            val v = map[k] ?: 0.0
            if (v <= 0.0) continue
            if (bestV == 0.0 || isBetter(v, bestV)) {
                bestV = v
                bestL = label
            }
        }
        return if (bestV > 0.0) bestL to bestV else "—" to 0.0
    }

    private fun streakFromEnd(
        w: TimeWindow,
        buckets: List<Pair<Long, String>>,
        hasActivity: (Long) -> Boolean
    ): Int {
        if (buckets.isEmpty()) return 0
        val endDay = minOf(
            w.endExclusive.toLocalDate().minusDays(1),
            ZonedDateTime.now(zone).toLocalDate()
        )
        var s = 0
        var d = endDay
        val first = w.start.toLocalDate()
        while (!d.isBefore(first)) {
            val key = d.toEpochDay()
            if (hasActivity(key)) {
                s++
                d = d.minusDays(1)
            } else {
                break
            }
        }
        return s
    }
}

class ProfileProgressViewModelFactory(
    private val app: Application,
    private val supabase: SupabaseClient,
    private val userId: String
) : ViewModelProvider.Factory {
    @Suppress("UNCHECKED_CAST")
    override fun <T : ViewModel> create(modelClass: Class<T>): T {
        if (modelClass != ProfileProgressViewModel::class.java) error("Unknown ViewModel: ${modelClass.name}")
        return ProfileProgressViewModel(app, supabase, userId) as T
    }
}
