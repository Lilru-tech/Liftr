package com.lilru.liftr.ui.compare

import com.lilru.liftr.data.BackendContracts
import com.lilru.liftr.ui.home.isSwimCardioActivityCode
import com.lilru.liftr.ui.home.secPer100mFromSecPerKm
import com.lilru.liftr.domain.strengthSetMultiplicities
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.query.Columns
import io.github.jan.supabase.postgrest.query.Order
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import kotlin.math.max
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

private val compJson = Json { ignoreUnknownKeys = true }

@Serializable
private data class CompareWRow(
    val id: Int,
    val kind: String,
    val title: String? = null,
    @SerialName("user_id") val userId: String,
    @SerialName("started_at") val startedAt: String? = null
)

@Serializable
private data class ProfileNameRow(
    @SerialName("user_id") val userId: String,
    val username: String? = null
)

@Serializable
private data class WMetaRow(
    @SerialName("duration_min") val durationMin: Int? = null,
    @SerialName("started_at") val startedAt: String? = null,
    @SerialName("ended_at") val endedAt: String? = null
)

@Serializable
private data class WeId(
    val id: Int
)

@Serializable
private data class SetRow(
    val id: Int,
    @SerialName("workout_exercise_id") val workoutExerciseId: Int,
    @SerialName("set_number") val setNumber: Int,
    val reps: Int? = null,
    @SerialName("weight_kg") val weightKg: Double? = null,
    val rpe: Double? = null,
    @SerialName("rest_sec") val restSec: Int? = null
)

private data class StrengthStats(
    val exercisesCount: Int,
    val setsCount: Int,
    val totalReps: Int,
    val totalVolumeKg: Double,
    val maxWeightKg: Double?,
    val maxSetVolumeKg: Double?,
    val avgRpe: Double?,
    val hardSetsCount: Int,
    val totalRestSec: Double,
    val avgRestSec: Double?
)

private fun bestDurationSecMeta(meta: WMetaRow): Double? {
    val dm = meta.durationMin
    if (dm != null && dm > 0) return (dm * 60).toDouble()
    val s = meta.startedAt?.let { runCatching { Instant.parse(it) }.getOrNull() } ?: return null
    val e = meta.endedAt?.let { runCatching { Instant.parse(it) }.getOrNull() } ?: return null
    val sec = (e.epochSecond - s.epochSecond).toDouble()
    return if (sec > 0) sec else null
}

private fun perMin(value: Double, durationSec: Double?): Double? {
    val d = durationSec ?: return null
    if (d <= 0) return null
    val minutes = d / 60.0
    if (minutes <= 0) return null
    return value / minutes
}

private val dateFmtDateTime: DateTimeFormatter =
    DateTimeFormatter.ofPattern("dd/MM/yyyy HH:mm").withZone(ZoneId.systemDefault())
private val dateFmtDate: DateTimeFormatter =
    DateTimeFormatter.ofPattern("dd/MM/yyyy").withZone(ZoneId.systemDefault())

private fun compareDateSuffix(iso: String?, otherIso: String?): String {
    if (iso.isNullOrBlank()) return ""
    val t = runCatching { Instant.parse(iso) }.getOrNull() ?: return ""
    val o = otherIso?.let { runCatching { Instant.parse(it) }.getOrNull() }
    val z = ZoneId.systemDefault()
    val f = if (o != null) {
        val d1 = t.atZone(z).toLocalDate()
        val d2 = o.atZone(z).toLocalDate()
        if (d1 == d2) dateFmtDateTime else dateFmtDate
    } else {
        dateFmtDate
    }
    return " (${f.format(t.atZone(z))})"
}

suspend fun loadCompareWorkoutData(
    supabase: SupabaseClient,
    currentWorkoutId: Int,
    otherWorkoutId: Int
): Result<CompareWorkoutLoadData> =
    loadCompareWorkoutData(
        supabase = supabase,
        currentWorkoutId = currentWorkoutId,
        other = CompareOtherTarget.Workout(otherWorkoutId),
        averageRightLabel = null
    )

/**
 * Carga etiquetas y métricas alineada a [Liftr.CompareWorkoutsView.load].
 */
suspend fun loadCompareWorkoutData(
    supabase: SupabaseClient,
    currentWorkoutId: Int,
    other: CompareOtherTarget,
    averageRightLabel: String?
): Result<CompareWorkoutLoadData> = runCatching {
    when (other) {
        is CompareOtherTarget.Workout -> loadCompareWorkoutPair(
            supabase, currentWorkoutId, other.id
        )
        is CompareOtherTarget.Average -> loadCompareWorkoutAverage(
            supabase,
            currentWorkoutId,
            other,
            averageRightLabel ?: "Average"
        )
    }
}

private suspend fun loadCompareWorkoutPair(
    supabase: SupabaseClient,
    currentWorkoutId: Int,
    otherWorkoutId: Int
): CompareWorkoutLoadData {
    val lRes = supabase.from(BackendContracts.Tables.WORKOUTS)
        .select(columns = Columns.raw("id, kind, title, user_id, started_at")) {
            filter { eq("id", currentWorkoutId) }
        }
    val rRes = supabase.from(BackendContracts.Tables.WORKOUTS)
        .select(columns = Columns.raw("id, kind, title, user_id, started_at")) {
            filter { eq("id", otherWorkoutId) }
        }
    val lList = compJson.decodeFromString<List<CompareWRow>>(lRes.data)
    val rList = compJson.decodeFromString<List<CompareWRow>>(rRes.data)
    val L = lList.firstOrNull() ?: error("Workout not found: $currentWorkoutId")
    val R = rList.firstOrNull() ?: error("Workout not found: $otherWorkoutId")
    if (L.kind.lowercase() != R.kind.lowercase()) {
        error("Workouts are different types (${L.kind} vs ${R.kind}).")
    }
    var aName: String? = null
    var bName: String? = null
    if (L.userId != R.userId) {
        aName = fetchUserName(supabase, L.userId)
        bName = fetchUserName(supabase, R.userId)
    }
    val showNames = L.userId != R.userId
    val bothMine = L.userId == R.userId
    val leftBase = makeWorkoutLabel(
        L,
        if (showNames) "User" else "Workout A",
        aName,
        showNames
    )
    val rightBase = makeWorkoutLabel(
        R,
        if (showNames) "User" else "Workout B",
        bName,
        showNames
    )
    val leftLabel = leftBase + compareDateSuffix(L.startedAt, R.startedAt)
    val rightLabel = rightBase + compareDateSuffix(R.startedAt, L.startedAt)
    val labels = CompareSessionLabels(
        kind = L.kind,
        bothMine = bothMine,
        leftLabel = leftLabel,
        rightLabel = rightLabel,
        leftUserName = aName,
        rightUserName = bName
    )
    val metrics = metricsForKind(
        supabase,
        L.kind.lowercase(),
        currentWorkoutId,
        otherWorkoutId
    )
    return CompareWorkoutLoadData(labels = labels, metrics = metrics)
}

private suspend fun loadCompareWorkoutAverage(
    supabase: SupabaseClient,
    currentWorkoutId: Int,
    average: CompareOtherTarget.Average,
    averageRightLabel: String
): CompareWorkoutLoadData {
    val poolIds = average.workoutIds
    if (poolIds.size < CompareAveragePoolLoader.MIN_SAMPLES) {
        error("Not enough workouts for average.")
    }
    val lRes = supabase.from(BackendContracts.Tables.WORKOUTS)
        .select(columns = Columns.raw("id, kind, title, user_id, started_at")) {
            filter { eq("id", currentWorkoutId) }
        }
    val L = compJson.decodeFromString<List<CompareWRow>>(lRes.data).firstOrNull()
        ?: error("Workout not found: $currentWorkoutId")
    val leftBase = makeWorkoutLabel(L, fallback = "Workout A", nameOverride = null, forceUserName = false)
    val leftLabel = leftBase + compareDateSuffix(L.startedAt, null)
    val kind = L.kind.lowercase()
    val perSession = poolIds.map { pid ->
        metricsForKind(supabase, kind, currentWorkoutId, pid)
    }
    val metrics = averageCompareMetricRows(perSession)
    val labels = CompareSessionLabels(
        kind = L.kind,
        bothMine = true,
        leftLabel = leftLabel,
        rightLabel = averageRightLabel,
        leftUserName = null,
        rightUserName = null
    )
    return CompareWorkoutLoadData(labels = labels, metrics = metrics)
}

private fun makeWorkoutLabel(
    w: CompareWRow,
    fallback: String,
    nameOverride: String?,
    forceUserName: Boolean
): String {
    if (forceUserName) {
        val n = nameOverride?.trim().orEmpty()
        return if (n.isEmpty()) fallback else n
    }
    val n2 = nameOverride?.trim().orEmpty()
    if (n2.isNotEmpty()) return n2
    val t = w.title?.trim().orEmpty()
    if (t.isNotEmpty()) return t
    return fallback
}

private suspend fun metricsForKind(
    supabase: SupabaseClient,
    kind: String,
    leftWid: Int,
    rightWid: Int
): List<CompareMetricRow> = when (kind) {
    "cardio" -> buildCardioMetrics(supabase, leftWid, rightWid)
    "sport" -> CompareSportMetrics.build(compJson, supabase, leftWid, rightWid)
    "strength" -> buildStrengthMetrics(supabase, leftWid, rightWid)
    else -> error("Unsupported workout kind.")
}

private suspend fun fetchUserName(supabase: SupabaseClient, userId: String): String? {
    return runCatching {
        val res = supabase.from(BackendContracts.Tables.PROFILES)
            .select(columns = Columns.raw("user_id, username")) {
                filter { eq("user_id", userId) }
            }
        val list = compJson.decodeFromString<List<ProfileNameRow>>(res.data)
        list.firstOrNull()?.username?.trim()?.takeIf { it.isNotEmpty() }
    }.getOrNull()
}

private suspend fun buildStrengthStats(supabase: SupabaseClient, wid: Int): StrengthStats {
    val exRes = supabase.from(BackendContracts.Tables.WORKOUT_EXERCISES)
        .select(columns = Columns.raw("id")) {
            filter { eq("workout_id", wid) }
        }
    val exIds = compJson.decodeFromString<List<WeId>>(exRes.data).map { it.id }
    if (exIds.isEmpty()) {
        return StrengthStats(0, 0, 0, 0.0, null, null, null, 0, 0.0, null)
    }
    val setsRes = supabase.from(BackendContracts.Tables.EXERCISE_SETS)
        .select(
            columns = Columns.raw("id, workout_exercise_id, set_number, reps, weight_kg, rpe, rest_sec")
        ) {
            filter { isIn("workout_exercise_id", exIds) }
            order("set_number", Order.ASCENDING)
        }
    val sets = compJson.decodeFromString<List<SetRow>>(setsRes.data)
    val byWe = sets.groupBy { it.workoutExerciseId }
    var totalReps = 0
    var totalVolumeKg = 0.0
    var maxWeightKg: Double? = null
    var maxSetVolumeKg: Double? = null
    var rpeWeightedSum = 0.0
    var rpeWeightTotal = 0.0
    var hardSets = 0
    var setsCount = 0
    var totalRestSec = 0.0
    var restMultWeight = 0.0
    for ((_, mutRows) in byWe) {
        val rows = mutRows.sortedBy { it.id }
        val nums = rows.map { it.setNumber }
        val mults = strengthSetMultiplicities(nums)
        for ((s, mult) in rows.zip(mults)) {
            setsCount += mult
            val reps = max(s.reps ?: 0, 0)
            val w = s.weightKg ?: 0.0
            totalReps += reps * mult
            val setVol = reps.toDouble() * w
            totalVolumeKg += setVol * mult
            if (w > 0) {
                maxWeightKg = (maxWeightKg?.let { maxOf(it, w) } ?: w)
            }
            if (setVol > 0) {
                maxSetVolumeKg = (maxSetVolumeKg?.let { maxOf(it, setVol) } ?: setVol)
            }
            val r = s.rpe
            if (r != null) {
                val m = mult.toDouble()
                rpeWeightedSum += r * m
                rpeWeightTotal += m
                if (r >= 8.0) hardSets += mult
            }
            val restVal = max(s.restSec ?: 0, 0)
            val mRest = mult.toDouble()
            totalRestSec += restVal * mRest
            if (restVal > 0) {
                restMultWeight += mRest
            }
        }
    }
    val avgRpe = if (rpeWeightTotal > 0) rpeWeightedSum / rpeWeightTotal else null
    val avgRestSec = if (restMultWeight > 0) totalRestSec / restMultWeight else null
    return StrengthStats(
        exercisesCount = exIds.size,
        setsCount = setsCount,
        totalReps = totalReps,
        totalVolumeKg = totalVolumeKg,
        maxWeightKg = maxWeightKg,
        maxSetVolumeKg = maxSetVolumeKg,
        avgRpe = avgRpe,
        hardSetsCount = hardSets,
        totalRestSec = totalRestSec,
        avgRestSec = avgRestSec
    )
}

private fun MutableList<CompareMetricRow>.addM(metric: String, unit: String, l: Double?, r: Double?) {
    if (l == null || r == null) return
    add(CompareMetricRow(key = metric, unit = unit, left = l, right = r))
}

private suspend fun buildStrengthMetrics(
    supabase: SupabaseClient,
    leftWid: Int,
    rightWid: Int
): List<CompareMetricRow> {
    val lMetaR = supabase.from(BackendContracts.Tables.WORKOUTS)
        .select(columns = Columns.raw("duration_min, started_at, ended_at")) {
            filter { eq("id", leftWid) }
        }
    val rMetaR = supabase.from(BackendContracts.Tables.WORKOUTS)
        .select(columns = Columns.raw("duration_min, started_at, ended_at")) {
            filter { eq("id", rightWid) }
        }
    val lMeta = compJson.decodeFromString<List<WMetaRow>>(lMetaR.data).firstOrNull()
        ?: WMetaRow()
    val rMeta = compJson.decodeFromString<List<WMetaRow>>(rMetaR.data).firstOrNull()
        ?: WMetaRow()
    val lStats = buildStrengthStats(supabase, leftWid)
    val rStats = buildStrengthStats(supabase, rightWid)
    val lDur = bestDurationSecMeta(lMeta)
    val rDur = bestDurationSecMeta(rMeta)
    val out = mutableListOf<CompareMetricRow>()
    out.addM("duration_sec", "sec", lDur, rDur)
    out.addM("total_volume_kg", "kg", lStats.totalVolumeKg, rStats.totalVolumeKg)
    out.addM("exercises_count", "count", lStats.exercisesCount.toDouble(), rStats.exercisesCount.toDouble())
    out.addM("sets_count", "count", lStats.setsCount.toDouble(), rStats.setsCount.toDouble())
    out.addM("total_reps", "count", lStats.totalReps.toDouble(), rStats.totalReps.toDouble())
    val lAwr = if (lStats.totalReps > 0) lStats.totalVolumeKg / lStats.totalReps else null
    val rAwr = if (rStats.totalReps > 0) rStats.totalVolumeKg / rStats.totalReps else null
    out.addM("avg_weight_per_rep_kg", "kg_per_rep", lAwr, rAwr)
    val lAws = if (lStats.setsCount > 0) lStats.totalVolumeKg / lStats.setsCount else null
    val rAws = if (rStats.setsCount > 0) rStats.totalVolumeKg / rStats.setsCount else null
    out.addM("avg_weight_per_set_kg", "kg_per_set", lAws, rAws)
    val lAre = if (lStats.exercisesCount > 0) lStats.totalReps.toDouble() / lStats.exercisesCount else null
    val rAre = if (rStats.exercisesCount > 0) rStats.totalReps.toDouble() / rStats.exercisesCount else null
    out.addM("avg_reps_per_exercise", "reps_per_exercise", lAre, rAre)
    val lAse = if (lStats.exercisesCount > 0) lStats.setsCount.toDouble() / lStats.exercisesCount else null
    val rAse = if (rStats.exercisesCount > 0) rStats.setsCount.toDouble() / rStats.exercisesCount else null
    out.addM("avg_sets_per_exercise", "sets_per_exercise", lAse, rAse)
    out.addM("volume_per_min_kg", "kg_per_min", perMin(lStats.totalVolumeKg, lDur), perMin(rStats.totalVolumeKg, rDur))
    out.addM("sets_per_min", "sets_per_min", perMin(lStats.setsCount.toDouble(), lDur), perMin(rStats.setsCount.toDouble(), rDur))
    out.addM("reps_per_min", "reps_per_min", perMin(lStats.totalReps.toDouble(), lDur), perMin(rStats.totalReps.toDouble(), rDur))
    out.addM("max_weight_kg", "kg", lStats.maxWeightKg, rStats.maxWeightKg)
    out.addM("max_set_volume_kg", "kg", lStats.maxSetVolumeKg, rStats.maxSetVolumeKg)
    out.addM("avg_rpe", "rpe", lStats.avgRpe, rStats.avgRpe)
    out.addM("hard_sets_count", "count", lStats.hardSetsCount.toDouble(), rStats.hardSetsCount.toDouble())
    out.addM("total_rest_sec", "sec", lStats.totalRestSec, rStats.totalRestSec)
    out.addM("avg_rest_sec", "sec", lStats.avgRestSec, rStats.avgRestSec)
    fun restPct(totalRest: Double, durationSec: Double?): Double? {
        val d = durationSec ?: return null
        if (d <= 0) return null
        return 100.0 * totalRest / d
    }
    out.addM(
        "rest_pct_of_session",
        "pct",
        restPct(lStats.totalRestSec, lDur),
        restPct(rStats.totalRestSec, rDur)
    )
    return out
}

@Serializable
private data class CardioRowM(
    val id: Int,
    @SerialName("activity_code") val activityCode: String? = null,
    val modality: String? = null,
    @SerialName("distance_km") val distanceKm: Double? = null,
    @SerialName("duration_sec") val durationSec: Int? = null,
    @SerialName("avg_hr") val avgHr: Int? = null,
    @SerialName("max_hr") val maxHr: Int? = null,
    @SerialName("avg_pace_sec_per_km") val avgPaceSecPerKm: Int? = null,
    @SerialName("elevation_gain_m") val elevationGainM: Int? = null
)

@Serializable
private data class CardioStatsWireM(
    val stats: ExtrasM? = null
) {
    @Serializable
    data class ExtrasM(
        @SerialName("cadence_rpm") val cadenceRpm: Int? = null,
        @SerialName("watts_avg") val wattsAvg: Int? = null,
        @SerialName("incline_pct") val inclinePct: Double? = null,
        @SerialName("swim_laps") val swimLaps: Int? = null,
        @SerialName("pool_length_m") val poolLengthM: Int? = null,
        @SerialName("split_sec_per_500m") val splitSecPer500m: Int? = null,
        @SerialName("km_split_pace_sec") val kmSplitPaceSec: List<Int>? = null
    )
}

private fun fastestKmPaceSecFromSplits(splits: List<Int>?): Double? {
    val s = splits?.filter { it > 0 } ?: return null
    if (s.isEmpty()) return null
    return s.min().toDouble()
}

private suspend fun buildCardioMetrics(
    supabase: SupabaseClient,
    leftWid: Int,
    rightWid: Int
): List<CompareMetricRow> {
    val lQ = supabase.from(BackendContracts.Tables.CARDIO_SESSIONS)
        .select { filter { eq("workout_id", leftWid) } }
    val rQ = supabase.from(BackendContracts.Tables.CARDIO_SESSIONS)
        .select { filter { eq("workout_id", rightWid) } }
    val L = compJson.decodeFromString<List<CardioRowM>>(lQ.data).firstOrNull()
        ?: error("No cardio session for workout $leftWid")
    val R = compJson.decodeFromString<List<CardioRowM>>(rQ.data).firstOrNull()
        ?: error("No cardio session for workout $rightWid")
    val la = (L.activityCode?.trim() ?: L.modality?.trim() ?: "").lowercase()
    val ra = (R.activityCode?.trim() ?: R.modality?.trim() ?: "").lowercase()
    if (la.isEmpty() || la != ra) {
        error("Cardio activities differ ($la vs $ra).")
    }
    suspend fun extras(sessionId: Int): CardioStatsWireM.ExtrasM? = runCatching {
        val q = supabase.from(BackendContracts.Tables.CARDIO_SESSION_STATS)
            .select(columns = Columns.raw("stats")) { filter { eq("session_id", sessionId) } }
        compJson.decodeFromString<List<CardioStatsWireM>>(q.data).firstOrNull()?.stats
    }.getOrNull()
    val le = extras(L.id)
    val re = extras(R.id)
    val out = mutableListOf<CompareMetricRow>()
    val swimCompare = isSwimCardioActivityCode(la)
    if (swimCompare) {
        out.addM("distance_km", "m", L.distanceKm?.let { it * 1000.0 }, R.distanceKm?.let { it * 1000.0 })
        out.addM(
            "avg_pace_sec_per_km",
            "sec_per_100m",
            L.avgPaceSecPerKm?.let { secPer100mFromSecPerKm(it).toDouble() },
            R.avgPaceSecPerKm?.let { secPer100mFromSecPerKm(it).toDouble() }
        )
    } else {
        out.addM("distance_km", "km", L.distanceKm, R.distanceKm)
        out.addM("avg_pace_sec_per_km", "sec_per_km", L.avgPaceSecPerKm?.toDouble(), R.avgPaceSecPerKm?.toDouble())
    }
    out.addM("duration_sec", "sec", L.durationSec?.toDouble(), R.durationSec?.toDouble())
    val lF = if (le != null && re != null) {
        val a = fastestKmPaceSecFromSplits(le.kmSplitPaceSec)
        val b = fastestKmPaceSecFromSplits(re.kmSplitPaceSec)
        if (a != null && b != null) Pair(a, b) else null
    } else null
    if (lF != null) {
        out.addM("fastest_km_pace_sec", "sec_per_km", lF.first, lF.second)
    }
    out.addM("avg_hr", "bpm", L.avgHr?.toDouble(), R.avgHr?.toDouble())
    out.addM("max_hr", "bpm", L.maxHr?.toDouble(), R.maxHr?.toDouble())
    out.addM("elevation_gain_m", "m", L.elevationGainM?.toDouble(), R.elevationGainM?.toDouble())
    if (le != null && re != null) {
        out.addM("cadence", "rpm_spm", le.cadenceRpm?.toDouble(), re.cadenceRpm?.toDouble())
        out.addM("watts_avg", "W", le.wattsAvg?.toDouble(), re.wattsAvg?.toDouble())
        out.addM("incline_pct", "pct", le.inclinePct, re.inclinePct)
        out.addM("swim_laps", "laps", le.swimLaps?.toDouble(), re.swimLaps?.toDouble())
        out.addM("pool_length_m", "m", le.poolLengthM?.toDouble(), re.poolLengthM?.toDouble())
        out.addM("split_sec_per_500m", "sec_per_500m", le.splitSecPer500m?.toDouble(), re.splitSecPer500m?.toDouble())
    }
    return out
}
