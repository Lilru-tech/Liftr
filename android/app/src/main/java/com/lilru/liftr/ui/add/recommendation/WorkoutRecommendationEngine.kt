package com.lilru.liftr.ui.add.recommendation

import com.lilru.liftr.data.BackendContracts
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.query.Columns
import io.github.jan.supabase.postgrest.query.Order
import java.time.Instant
import kotlin.math.abs
import kotlin.math.min
import kotlin.math.roundToInt
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonPrimitive

@Serializable
private data class RecWRow(
    val id: Int,
    @SerialName("started_at") val startedAt: String? = null
)

@Serializable
private data class RecMuscleRef(@SerialName("muscle_primary") val musclePrimary: String? = null)

@Serializable
private data class RecExWire(
    val id: Int,
    @SerialName("workout_id") val workoutId: Int,
    @SerialName("exercise_id") val exerciseId: Long,
    @SerialName("order_index") val orderIndex: Int,
    val exercises: RecMuscleRef? = null
)

@Serializable
private data class RecSetWire(
    @SerialName("workout_exercise_id") val workoutExerciseId: Int,
    @SerialName("set_number") val setNumber: Int,
    val reps: Int? = null,
    @SerialName("weight_kg") val weightKg: Double? = null,
    val rpe: Double? = null,
    @SerialName("rest_sec") val restSec: Int? = null
)

/**
 * iOS [WorkoutRecommendationService] (logic ported for Android / same Supabase queries).
 */
class WorkoutRecommendationEngine(
    private val supabase: SupabaseClient,
    private val json: Json = Json { ignoreUnknownKeys = true }
) {
    private val lookbackCount = 10
    private val targetExerciseCount = 5
    private val defaultSetsPerExercise = 3
    private val defaultReps = 12
    private val maxRecommendedSets = 5
    private val maxInferredSetsFromSetNumber = 8
    private val maxRecommendedReps = 22
    private val minRecommendedReps = 6
    private val highVolumeRepsThreshold = 17
    private val highVolumeSetsThreshold = 5
    private val defaultRestBetweenSetsSec = 90

    private data class FlatSet(
        val workoutId: Int,
        val startedAt: Instant?,
        val workoutExerciseId: Int,
        val exerciseId: Long,
        val orderIndex: Int,
        val musclePrimary: String?,
        val setNumber: Int,
        val reps: Int?,
        val weightKg: Double?,
        val rpe: Double?,
        val restSec: Int?
    )

    suspend fun recommendStrength(
        userId: String,
        source: RecommendationDataSource,
        mode: StrengthSuggestionMode,
        catalog: List<ExerciseForRecommendation>,
        preferSpanish: Boolean
    ): List<StrengthRecommendationExerciseResult> {
        val wRes = supabase.from(BackendContracts.Tables.WORKOUTS)
            .select(Columns.raw("id, started_at")) {
                filter {
                    eq("user_id", userId)
                    eq("kind", "strength")
                    eq("state", "published")
                }
                order("started_at", Order.DESCENDING)
                limit(lookbackCount.toLong())
            }
        val workouts = json.decodeFromString<List<RecWRow>>(wRes.data)
        if (workouts.isEmpty()) {
            if (source == RecommendationDataSource.FULL_CATALOG && catalog.isNotEmpty()) {
                return coldStartStrength(catalog, preferSpanish)
            }
            throw WorkoutRecommendationError.NoWorkoutsInWindow
        }
        val workoutIds = workouts.map { it.id.toString() }
        val startedByWid = workouts.associate { w ->
            w.id to w.startedAt?.let { runCatching { Instant.parse(it) }.getOrNull() }
        }
        val exRes = supabase.from(BackendContracts.Tables.WORKOUT_EXERCISES)
            .select(Columns.raw("id, workout_id, exercise_id, order_index, exercises(muscle_primary)")) {
                filter { isIn("workout_id", workoutIds) }
                order("order_index", Order.ASCENDING)
            }
        val exRows = json.decodeFromString<List<RecExWire>>(exRes.data)
        val weIds = exRows.map { it.id }
        var setRows: List<RecSetWire> = emptyList()
        if (weIds.isNotEmpty()) {
            val setRes = supabase.from(BackendContracts.Tables.EXERCISE_SETS)
                .select(
                    Columns.raw("workout_exercise_id, set_number, reps, weight_kg, rpe, rest_sec")
                ) {
                    filter { isIn("workout_exercise_id", weIds.map { it.toString() }) }
                    order("set_number", Order.ASCENDING)
                }
            setRows = json.decodeFromString(setRes.data)
        }
        val setsByWE = setRows.groupBy { it.workoutExerciseId }
        val flat = mutableListOf<FlatSet>()
        for (ex in exRows) {
            val st = startedByWid[ex.workoutId]
            val muscle = ex.exercises?.musclePrimary
            val list = setsByWE[ex.id]
            if (!list.isNullOrEmpty()) {
                for (s in list) {
                    flat.add(
                        FlatSet(
                            workoutId = ex.workoutId,
                            startedAt = st,
                            workoutExerciseId = ex.id,
                            exerciseId = ex.exerciseId,
                            orderIndex = ex.orderIndex,
                            musclePrimary = muscle,
                            setNumber = s.setNumber,
                            reps = s.reps,
                            weightKg = s.weightKg,
                            rpe = s.rpe,
                            restSec = s.restSec
                        )
                    )
                }
            } else {
                flat.add(
                    FlatSet(
                        workoutId = ex.workoutId,
                        startedAt = st,
                        workoutExerciseId = ex.id,
                        exerciseId = ex.exerciseId,
                        orderIndex = ex.orderIndex,
                        musclePrimary = muscle,
                        setNumber = 1,
                        reps = null,
                        weightKg = null,
                        rpe = null,
                        restSec = null
                    )
                )
            }
        }
        return when (mode) {
            StrengthSuggestionMode.PRIORITIZE_UNDERTRAINED_MUSCLES ->
                suggestBalancedStrength(flat, catalog, source, preferSpanish)
            StrengthSuggestionMode.PRIORITIZE_FREQUENT_LIFTS ->
                suggestFrequentStrength(flat, catalog, source, preferSpanish)
        }
    }

    suspend fun recommendCardio(
        userId: String,
        source: RecommendationDataSource
    ): CardioRecommendationResult =
        WorkoutRecommendationCardioSport.recommendCardio(supabase, json, userId, source)

    suspend fun recommendSport(
        userId: String,
        source: RecommendationDataSource
    ): SportRecommendationResult =
        WorkoutRecommendationCardioSport.recommendSport(supabase, json, userId, source)

    // --- Strength helpers (iOS) ---

    private fun normMuscle(s: String?) =
        s?.trim()?.lowercase().orEmpty()

    private fun coldStartStrength(
        catalog: List<ExerciseForRecommendation>,
        preferSpanish: Boolean
    ): List<StrengthRecommendationExerciseResult> {
        val pool = catalog.shuffled()
        val w = 20.0
        val rpe: Double? = 8.0
        return pool.take(targetExerciseCount).map { ex ->
            val sets = (1..defaultSetsPerExercise).map { sn ->
                StrengthRecommendationSetResult(
                    setNumber = sn,
                    reps = defaultReps,
                    weightKg = w,
                    rpe = rpe,
                    restSec = defaultRestBetweenSetsSec
                )
            }
            StrengthRecommendationExerciseResult(
                exerciseId = ex.id,
                displayName = ex.localizedName(preferSpanish),
                musclePrimary = ex.musclePrimary,
                sets = sets
            )
        }
    }

    private fun suggestFrequentStrength(
        flat: List<FlatSet>,
        catalog: List<ExerciseForRecommendation>,
        source: RecommendationDataSource,
        preferSpanish: Boolean
    ): List<StrengthRecommendationExerciseResult> {
        val historyIds = flat.map { it.exerciseId }.toSet()
        val pool: List<ExerciseForRecommendation> = when (source) {
            RecommendationDataSource.RECENT_HISTORY,
            RecommendationDataSource.HYROX,
            RecommendationDataSource.HYROX_RACE -> catalog.filter { it.id in historyIds }
            RecommendationDataSource.FULL_CATALOG -> catalog
        }
        if (pool.isEmpty()) {
            throw WorkoutRecommendationError.LoadFailed("No exercises in pool.")
        }
        val workoutsByExercise = flat.groupBy { it.exerciseId }
            .mapValues { e -> e.value.map { it.workoutId }.toSet() }
        val ranked = pool.map { ex -> ex to (workoutsByExercise[ex.id]?.size ?: 0) }
            .sortedWith(compareByDescending<Pair<ExerciseForRecommendation, Int>> { it.second }
                .thenBy { it.first.id })
        val chosen = mutableListOf<ExerciseForRecommendation>()
        val used = mutableSetOf<Long>()
        for ((ex, _) in ranked) {
            if (used.add(ex.id)) {
                chosen.add(ex)
                if (chosen.size >= targetExerciseCount) break
            }
        }
        if (chosen.size < targetExerciseCount) {
            for (ex in pool.shuffled()) {
                if (chosen.size >= targetExerciseCount) break
                if (used.add(ex.id)) chosen.add(ex)
            }
        }
        return buildResultList(chosen.take(targetExerciseCount), flat, preferSpanish, "Frequent")
    }

    private fun suggestBalancedStrength(
        flat: List<FlatSet>,
        catalog: List<ExerciseForRecommendation>,
        source: RecommendationDataSource,
        preferSpanish: Boolean
    ): List<StrengthRecommendationExerciseResult> {
        val muscleSetCounts = mutableMapOf<String, Int>()
        for (s in flat) {
            val m = normMuscle(s.musclePrimary)
            if (m.isNotEmpty() && m != "cardio") {
                muscleSetCounts[m] = (muscleSetCounts[m] ?: 0) + 1
            }
        }
        val sortedMuscles = muscleSetCounts.keys.sortedBy { muscleSetCounts[it]!! }
        val targetMuscles: Set<String> = if (sortedMuscles.isEmpty()) {
            catalog.map { normMuscle(it.musclePrimary) }.filter { it.isNotEmpty() && it != "cardio" }
                .toSet()
        } else {
            sortedMuscles.take(min(3, sortedMuscles.size)).toSet()
        }
        val historyIds = flat.map { it.exerciseId }.toSet()
        val pool: List<ExerciseForRecommendation> = when (source) {
            RecommendationDataSource.RECENT_HISTORY,
            RecommendationDataSource.HYROX,
            RecommendationDataSource.HYROX_RACE -> catalog.filter { it.id in historyIds }
            RecommendationDataSource.FULL_CATALOG -> catalog
        }
        var filtered = pool.filter { targetMuscles.contains(normMuscle(it.musclePrimary)) }
        if (filtered.isEmpty()) filtered = pool
        val shuffled = filtered.shuffled()
        val chosen = mutableListOf<ExerciseForRecommendation>()
        val used = mutableSetOf<Long>()
        for (ex in shuffled) {
            if (used.add(ex.id)) {
                chosen.add(ex)
                if (chosen.size >= targetExerciseCount) break
            }
        }
        for (ex in pool) {
            if (chosen.size >= targetExerciseCount) break
            if (used.add(ex.id)) chosen.add(ex)
        }
        return buildResultList(chosen.take(targetExerciseCount), flat, preferSpanish, "Balance")
    }

    private fun buildResultList(
        chosen: List<ExerciseForRecommendation>,
        flat: List<FlatSet>,
        preferSpanish: Boolean,
        @Suppress("unused") reason: String
    ): List<StrengthRecommendationExerciseResult> {
        val out = mutableListOf<StrengthRecommendationExerciseResult>()
        for (ex in chosen) {
            var setsOut = buildSetsForExercise(ex.id, flat, ex.musclePrimary)
            if (setsOut.isEmpty()) {
                val w = suggestWeight(ex.id, flat)
                val rpe: Double? = 8.0
                setsOut = (1..defaultSetsPerExercise).map { sn ->
                    StrengthRecommendationSetResult(
                        setNumber = sn,
                        reps = defaultReps,
                        weightKg = w,
                        rpe = rpe,
                        restSec = defaultRestBetweenSetsSec
                    )
                }
            }
            out.add(
                StrengthRecommendationExerciseResult(
                    exerciseId = ex.id,
                    displayName = ex.localizedName(preferSpanish),
                    musclePrimary = ex.musclePrimary,
                    sets = setsOut
                )
            )
        }
        if (out.isEmpty()) throw WorkoutRecommendationError.LoadFailed("Could not build a session.")
        return out
    }

    private fun buildSetsForExercise(
        exerciseId: Long,
        flat: List<FlatSet>,
        @Suppress("unused") muscle: String?
    ): List<StrengthRecommendationSetResult> {
        val latestWid = latestWorkoutIdForExercise(exerciseId, flat) ?: return emptyList()
        val rawLast = flat.filter { it.exerciseId == exerciseId && it.workoutId == latestWid }
        val slice = pickBestWorkoutExerciseSlice(rawLast).sortedBy { it.setNumber }
        val mergedLogged = mergeDuplicateSetNumbers(slice)
        if (mergedLogged.isEmpty()) return emptyList()
        val inLast = expandToInferredFullSession(mergedLogged)
        val rpes = inLast.mapNotNull { it.rpe }
        val avgRpe = if (rpes.isEmpty()) 8.0 else rpes.average()
        var carryTemplate = 0.0
        val withWeight = inLast.map { s ->
            var template = s.weightKg ?: 0.0
            if (template <= 0) {
                template = if (carryTemplate > 0) carryTemplate else suggestWeight(exerciseId, flat)
            } else {
                carryTemplate = template
            }
            val adj = adjustWeight(template, avgRpe)
            val reps = s.reps?.coerceIn(minRecommendedReps, maxRecommendedReps) ?: defaultReps
            StrengthRecommendationSetResult(
                setNumber = s.setNumber,
                reps = reps,
                weightKg = roundToHalf(adj),
                rpe = s.rpe,
                restSec = s.restSec ?: defaultRestBetweenSetsSec
            )
        }
        return adjustVolumeForRpe(withWeight, avgRpe)
    }

    private fun latestWorkoutIdForExercise(exerciseId: Long, flat: List<FlatSet>): Int? {
        val rows = flat.filter { it.exerciseId == exerciseId }
        if (rows.isEmpty()) return null
        return rows.groupBy { it.workoutId }
            .maxByOrNull { (_, rs) -> rs.maxOf { it.startedAt ?: Instant.EPOCH } }
            ?.key
    }

    private fun pickBestWorkoutExerciseSlice(rows: List<FlatSet>): List<FlatSet> {
        val g = rows.groupBy { it.workoutExerciseId }
        val best = g.maxByOrNull { it.value.size }?.value
        return best ?: rows
    }

    private fun mergeDuplicateSetNumbers(rows: List<FlatSet>): List<FlatSet> {
        val g = rows.groupBy { it.setNumber }
        return g.keys.sorted().mapNotNull { k ->
            (g[k] ?: emptyList()).maxByOrNull { it.weightKg ?: 0.0 }
        }
    }

    private fun expandToInferredFullSession(logged: List<FlatSet>): List<FlatSet> {
        if (logged.isEmpty()) return emptyList()
        val maxSn = logged.maxOf { it.setNumber }
        var target = listOf(logged.size, maxSn, defaultSetsPerExercise).maxOrNull()!!
        target = min(target, maxInferredSetsFromSetNumber)
        return (1..target).map { ord ->
            val src = logged.minByOrNull { abs(it.setNumber - ord) } ?: logged.last()
            src.copy(setNumber = ord)
        }
    }

    private fun renumberStrengthSets(sets: List<StrengthRecommendationSetResult>) =
        sets.mapIndexed { i, s -> s.copy(setNumber = i + 1) }

    private fun adjustVolumeForRpe(
        sets: List<StrengthRecommendationSetResult>,
        avgRpe: Double
    ): List<StrengthRecommendationSetResult> {
        if (sets.isEmpty()) return sets
        var out = sets.toMutableList()
        val n = out.size
        val maxReps = out.maxOf { it.reps }
        if (avgRpe < 8.0) {
            val highVolume = maxReps >= highVolumeRepsThreshold || n >= highVolumeSetsThreshold
            if (highVolume) return renumberStrengthSets(out)
            if (n < maxRecommendedSets && maxReps <= highVolumeRepsThreshold - 1) {
                val last = out.last()
                out.add(
                    last.copy(
                        setNumber = n + 1,
                    )
                )
            } else if (maxReps <= maxRecommendedReps - 2) {
                out = out.map { s -> s.copy(reps = min(maxRecommendedReps, s.reps + 2)) }.toMutableList()
            }
        }
        return renumberStrengthSets(out)
    }

    private fun suggestWeight(exerciseId: Long, flat: List<FlatSet>): Double {
        val latestWid = latestWorkoutIdForExercise(exerciseId, flat) ?: return 20.0
        val slice = flat.filter { it.exerciseId == exerciseId && it.workoutId == latestWid && it.weightKg != null }
        val weights = slice.mapNotNull { it.weightKg }
        if (weights.isEmpty()) {
            val any = flat.filter { it.exerciseId == exerciseId && it.weightKg != null }
            val fs = any.mapNotNull { it.weightKg }
            return roundToHalf((fs.maxOrNull() ?: 20.0))
        }
        val base = weights.maxOrNull() ?: 20.0
        val rps = slice.mapNotNull { it.rpe }
        val avgRpe = if (rps.isEmpty()) 8.0 else rps.average()
        return roundToHalf(adjustWeight(base, avgRpe))
    }

    private fun adjustWeight(base: Double, avgRpe: Double): Double = when {
        avgRpe < 8.0 -> base + 2.5
        avgRpe >= 9.0 -> (base - 2.5).coerceAtLeast(0.0)
        else -> base
    }

    private fun roundToHalf(x: Double) = (x * 2.0).roundToInt() / 2.0
}

@Serializable
data class ExerciseForRecommendation(
    val id: Long,
    val name: String,
    @SerialName("name_es") val nameEs: String? = null,
    @SerialName("name_en") val nameEn: String? = null,
    @SerialName("muscle_primary") val musclePrimary: String? = null
) {
    fun localizedName(preferSpanish: Boolean) = when {
        preferSpanish && !nameEs.isNullOrBlank() -> nameEs
        !preferSpanish && !nameEn.isNullOrBlank() -> nameEn
        else -> name
    }
}
