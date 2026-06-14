package com.lilru.liftr.ui.add.recommendation

import com.lilru.liftr.data.BackendContracts
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.query.Columns
import io.github.jan.supabase.postgrest.query.Order
import java.time.Instant
import java.time.temporal.ChronoUnit
import kotlin.math.abs
import kotlin.math.exp
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
        preferSpanish: Boolean,
        networkInspired: Boolean = false,
        excludeRoutineId: Long? = null
    ): StrengthRecommendationOutputResult {
        val ctx = WorkoutRecommendationContextLoader.load(
            supabase, json, userId, catalog, networkInspired || source == RecommendationDataSource.NETWORK_INSPIRED
        )
        if (source == RecommendationDataSource.MY_ROUTINES) {
            return recommendFromSavedStrengthRoutine(userId, catalog, preferSpanish, ctx, excludeRoutineId)
        }
        val effectiveSource = if (networkInspired && source == RecommendationDataSource.RECENT_HISTORY) {
            RecommendationDataSource.NETWORK_INSPIRED
        } else source

        val wRes = supabase.from(BackendContracts.Tables.WORKOUTS)
            .select(Columns.raw("id, started_at")) {
                filter {
                    eq("user_id", userId)
                    eq("kind", "strength")
                    eq("state", "published")
                }
                order("started_at", Order.DESCENDING)
                limit(WorkoutRecommendationConstants.LOOKBACK_COUNT.toLong())
            }
        val workouts = json.decodeFromString<List<RecWRow>>(wRes.data)
        if (workouts.isEmpty()) {
            if ((effectiveSource == RecommendationDataSource.FULL_CATALOG ||
                    effectiveSource == RecommendationDataSource.NETWORK_INSPIRED) && catalog.isNotEmpty()
            ) {
                val exercises = coldStartStrength(catalog, preferSpanish, ctx)
                return wrapStrengthOutput(exercises, ctx, emptyList(), ctx.partialDataNote, null)
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
        val exercises = when (mode) {
            StrengthSuggestionMode.PRIORITIZE_UNDERTRAINED_MUSCLES ->
                suggestBalancedStrength(flat, catalog, effectiveSource, preferSpanish, ctx)
            StrengthSuggestionMode.PRIORITIZE_FREQUENT_LIFTS ->
                suggestFrequentStrength(flat, catalog, effectiveSource, preferSpanish, ctx)
            StrengthSuggestionMode.CHASE_PRS ->
                suggestChasePRStrength(flat, catalog, effectiveSource, preferSpanish, ctx)
        }
        return wrapStrengthOutput(exercises, ctx, flat, ctx.partialDataNote, null)
    }

    suspend fun recommendCardio(
        userId: String,
        source: RecommendationDataSource,
        networkInspired: Boolean = false
    ): CardioRecommendationResult =
        WorkoutRecommendationCardioSport.recommendCardio(supabase, json, userId, source, networkInspired)

    suspend fun recommendSport(
        userId: String,
        source: RecommendationDataSource,
        networkInspired: Boolean = false
    ): SportRecommendationResult =
        WorkoutRecommendationCardioSport.recommendSport(supabase, json, userId, source, networkInspired)

    private fun wrapStrengthOutput(
        exercises: List<StrengthRecommendationExerciseResult>,
        ctx: WorkoutRecommendationContext,
        flat: List<FlatSet>,
        extra: String?,
        routineName: String?
    ): StrengthRecommendationOutputResult {
        val favCount = exercises.count { ctx.favoriteExerciseIds.contains(it.exerciseId) }
        val parts = mutableListOf<String>()
        if (favCount > 0) {
            parts += if (favCount == 1) "Includes 1 of your favorites." else "Includes $favCount of your favorites."
        }
        extra?.takeIf { it.isNotBlank() }?.let { parts += it }
        ctx.goalNudge?.summaryLine?.let { parts += it }
        return StrengthRecommendationOutputResult(
            exercises = exercises,
            sessionRationale = parts.takeIf { it.isNotEmpty() }?.joinToString(" "),
            muscleFreshness = muscleFreshnessEntries(flat),
            routineName = routineName
        )
    }

    private fun muscleFreshnessEntries(flat: List<FlatSet>): List<MuscleFreshnessEntryResult> {
        val now = Instant.now()
        val lastByMuscle = mutableMapOf<String, Instant>()
        for (s in flat) {
            val m = normMuscle(s.musclePrimary)
            if (m.isEmpty() || m == "cardio") continue
            val st = s.startedAt ?: continue
            val prev = lastByMuscle[m]
            if (prev == null || st.isAfter(prev)) lastByMuscle[m] = st
        }
        return lastByMuscle.keys.sorted().map { muscle ->
            val hours = ChronoUnit.HOURS.between(lastByMuscle[muscle], now).toDouble()
            val status = when {
                hours >= 72 -> "fresh"
                hours >= WorkoutRecommendationConstants.RECOVERY_DEPRIORITIZE_HOURS -> "recent"
                else -> "trainedRecently"
            }
            MuscleFreshnessEntryResult(muscle.replaceFirstChar { it.uppercase() }, status)
        }
    }

    private suspend fun recommendFromSavedStrengthRoutine(
        userId: String,
        catalog: List<ExerciseForRecommendation>,
        preferSpanish: Boolean,
        ctx: WorkoutRecommendationContext,
        excludeRoutineId: Long?
    ): StrengthRecommendationOutputResult {
        @Serializable
        data class RoutineRow(val id: Long, val name: String)
        val rRes = supabase.from(BackendContracts.Tables.STRENGTH_ROUTINES)
            .select(Columns.raw("id, name")) {
                filter { eq("user_id", userId) }
                order("updated_at", Order.ASCENDING)
            }
        var rows = json.decodeFromString<List<RoutineRow>>(rRes.data)
        if (excludeRoutineId != null) rows = rows.filter { it.id != excludeRoutineId }
        val picked = rows.randomOrNull() ?: throw WorkoutRecommendationError.LoadFailed(
            "Save a strength routine first, or pick another data source."
        )
        @Serializable
        data class SetWire(
            @SerialName("set_number") val setNumber: Int,
            val reps: Int? = null,
            @SerialName("weight_kg") val weightKg: Double? = null,
            val rpe: Double? = null,
            @SerialName("rest_sec") val restSec: Int? = null
        )
        @Serializable
        data class ExWire(
            @SerialName("exercise_id") val exerciseId: Long,
            @SerialName("order_index") val orderIndex: Int,
            @SerialName("custom_name") val customName: String? = null,
            @SerialName("strength_routine_sets") val sets: List<SetWire>? = null
        )
        @Serializable
        data class Detail(val name: String, @SerialName("strength_routine_exercises") val exercises: List<ExWire>? = null)
        val dRes = supabase.from(BackendContracts.Tables.STRENGTH_ROUTINES)
            .select(
                Columns.raw(
                    "name, strength_routine_exercises(exercise_id, order_index, custom_name, strength_routine_sets(set_number, reps, weight_kg, rpe, rest_sec))"
                )
            ) {
                filter { eq("id", picked.id) }
            }
        val detail = json.decodeFromString<List<Detail>>(dRes.data).firstOrNull()
            ?: throw WorkoutRecommendationError.LoadFailed("Could not load routine.")
        val catalogById = catalog.associateBy { it.id }
        val exercises = (detail.exercises ?: emptyList()).sortedBy { it.orderIndex }.map { ex ->
            val sets = (ex.sets ?: emptyList()).sortedBy { it.setNumber }.mapIndexed { idx, s ->
                StrengthRecommendationSetResult(
                    setNumber = idx + 1,
                    reps = (s.reps ?: WorkoutRecommendationConstants.DEFAULT_REPS)
                        .coerceIn(WorkoutRecommendationConstants.MIN_RECOMMENDED_REPS, WorkoutRecommendationConstants.MAX_RECOMMENDED_REPS),
                    weightKg = WorkoutRecommendationConstants.roundToHalf(s.weightKg ?: ctx.defaultColdStartWeightKg()),
                    rpe = s.rpe,
                    restSec = s.restSec ?: WorkoutRecommendationConstants.DEFAULT_REST_BETWEEN_SETS_SEC
                )
            }.ifEmpty {
                (1..WorkoutRecommendationConstants.DEFAULT_SETS_PER_EXERCISE).map { sn ->
                    StrengthRecommendationSetResult(
                        sn, WorkoutRecommendationConstants.DEFAULT_REPS, ctx.defaultColdStartWeightKg(), 8.0,
                        WorkoutRecommendationConstants.DEFAULT_REST_BETWEEN_SETS_SEC
                    )
                }
            }
            val display = ex.customName?.trim()?.takeIf { it.isNotEmpty() }
                ?: catalogById[ex.exerciseId]?.localizedName(preferSpanish)
                ?: "Exercise ${ex.exerciseId}"
            StrengthRecommendationExerciseResult(
                exerciseId = ex.exerciseId,
                displayName = display,
                musclePrimary = catalogById[ex.exerciseId]?.musclePrimary,
                sets = sets
            )
        }
        if (exercises.isEmpty()) throw WorkoutRecommendationError.LoadFailed("That routine has no exercises.")
        return wrapStrengthOutput(
            exercises, ctx, emptyList(),
            "Loaded from your routine \"${detail.name}\".", detail.name
        )
    }

    // --- Strength helpers (iOS) ---

    private fun normMuscle(s: String?) =
        s?.trim()?.lowercase().orEmpty()

    private fun coldStartStrength(
        catalog: List<ExerciseForRecommendation>,
        preferSpanish: Boolean,
        ctx: WorkoutRecommendationContext
    ): List<StrengthRecommendationExerciseResult> {
        val pool = WorkoutRecommendationConstants.biasedShuffle(catalog) { ctx.favoriteExerciseIds.contains(it.id) }
        val w = ctx.defaultColdStartWeightKg()
        val rpe: Double? = 8.0
        return pool.take(WorkoutRecommendationConstants.TARGET_EXERCISE_COUNT).map { ex ->
            val sets = (1..WorkoutRecommendationConstants.DEFAULT_SETS_PER_EXERCISE).map { sn ->
                StrengthRecommendationSetResult(
                    setNumber = sn,
                    reps = WorkoutRecommendationConstants.DEFAULT_REPS,
                    weightKg = w,
                    rpe = rpe,
                    restSec = WorkoutRecommendationConstants.DEFAULT_REST_BETWEEN_SETS_SEC
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

    private fun exercisePool(
        catalog: List<ExerciseForRecommendation>,
        source: RecommendationDataSource,
        historyIds: Set<Long>,
        ctx: WorkoutRecommendationContext
    ): List<ExerciseForRecommendation> = when (source) {
        RecommendationDataSource.RECENT_HISTORY,
        RecommendationDataSource.HYROX,
        RecommendationDataSource.HYROX_RACE -> catalog.filter { it.id in historyIds }
        RecommendationDataSource.FULL_CATALOG,
        RecommendationDataSource.MY_ROUTINES -> catalog
        RecommendationDataSource.NETWORK_INSPIRED -> {
            val networkIds = ctx.networkExerciseFrequency.keys
            if (networkIds.isEmpty()) catalog.filter { it.id in historyIds }
            else catalog.filter { it.id in networkIds || it.id in historyIds }
        }
    }

    private fun suggestFrequentStrength(
        flat: List<FlatSet>,
        catalog: List<ExerciseForRecommendation>,
        source: RecommendationDataSource,
        preferSpanish: Boolean,
        ctx: WorkoutRecommendationContext
    ): List<StrengthRecommendationExerciseResult> {
        val historyIds = flat.map { it.exerciseId }.toSet()
        val pool = exercisePool(catalog, source, historyIds, ctx)
        if (pool.isEmpty()) throw WorkoutRecommendationError.LoadFailed("No exercises in pool.")
        val workoutsByExercise = flat.groupBy { it.exerciseId }.mapValues { e -> e.value.map { it.workoutId }.toSet() }
        var ranked = pool.map { ex -> ex to (workoutsByExercise[ex.id]?.size ?: 0) }
            .sortedWith(compareByDescending<Pair<ExerciseForRecommendation, Int>> { it.second }.thenBy { it.first.id })
        if (source == RecommendationDataSource.NETWORK_INSPIRED && ctx.networkExerciseFrequency.isNotEmpty()) {
            ranked = pool.sortedWith(
                compareByDescending<ExerciseForRecommendation> { ctx.networkExerciseFrequency[it.id] ?: 0 }
                    .thenBy { workoutsByExercise[it.id]?.size ?: 0 }
            ).map { it to (workoutsByExercise[it.id]?.size ?: 0) }
        }
        val chosen = mutableListOf<ExerciseForRecommendation>()
        val used = mutableSetOf<Long>()
        for ((ex, _) in ranked) {
            if (used.add(ex.id)) {
                chosen.add(ex)
                if (chosen.size >= WorkoutRecommendationConstants.TARGET_EXERCISE_COUNT) break
            }
        }
        if (chosen.size < WorkoutRecommendationConstants.TARGET_EXERCISE_COUNT) {
            for (ex in WorkoutRecommendationConstants.biasedShuffle(pool) { ctx.favoriteExerciseIds.contains(it.id) }) {
                if (chosen.size >= WorkoutRecommendationConstants.TARGET_EXERCISE_COUNT) break
                if (used.add(ex.id)) chosen.add(ex)
            }
        }
        return buildResultList(chosen.take(WorkoutRecommendationConstants.TARGET_EXERCISE_COUNT), flat, preferSpanish, ctx)
    }

    private fun suggestChasePRStrength(
        flat: List<FlatSet>,
        catalog: List<ExerciseForRecommendation>,
        source: RecommendationDataSource,
        preferSpanish: Boolean,
        ctx: WorkoutRecommendationContext
    ): List<StrengthRecommendationExerciseResult> {
        val historyIds = flat.map { it.exerciseId }.toSet()
        val pool = exercisePool(catalog, source, historyIds, ctx)
        if (pool.isEmpty()) throw WorkoutRecommendationError.LoadFailed("No exercises in pool.")
        val chase = pool.mapNotNull { ex ->
            val pr = ctx.prMaxWeightByExerciseId[ex.id] ?: return@mapNotNull null
            if (pr <= 0) return@mapNotNull null
            val latest = latestMaxWeight(ex.id, flat)
            if (latest <= 0) return@mapNotNull null
            if (latest >= pr * (1 - WorkoutRecommendationConstants.PR_CHASE_PROXIMITY_RATIO)) {
                ex to kotlin.math.abs(pr - latest)
            } else null
        }.sortedBy { it.second }.map { it.first }
        var chosen = chase.take(WorkoutRecommendationConstants.TARGET_EXERCISE_COUNT).toMutableList()
        if (chosen.size < WorkoutRecommendationConstants.TARGET_EXERCISE_COUNT) {
            val fb = suggestFrequentStrength(
                flat, catalog,
                if (source == RecommendationDataSource.NETWORK_INSPIRED) RecommendationDataSource.RECENT_HISTORY else source,
                preferSpanish, ctx
            )
            val used = chosen.map { it.id }.toMutableSet()
            for (r in fb) {
                if (chosen.size >= WorkoutRecommendationConstants.TARGET_EXERCISE_COUNT) break
                catalog.firstOrNull { it.id == r.exerciseId && it.id !in used }?.let {
                    chosen.add(it)
                    used.add(it.id)
                }
            }
        }
        if (chosen.isEmpty()) {
            return suggestFrequentStrength(flat, catalog, source, preferSpanish, ctx)
        }
        return buildResultList(chosen, flat, preferSpanish, ctx)
    }

    private fun latestMaxWeight(exerciseId: Long, flat: List<FlatSet>): Double {
        val wid = latestWorkoutIdForExercise(exerciseId, flat) ?: return 0.0
        return flat.filter { it.exerciseId == exerciseId && it.workoutId == wid && it.weightKg != null }
            .mapNotNull { it.weightKg }.maxOrNull() ?: 0.0
    }

    private fun suggestBalancedStrength(
        flat: List<FlatSet>,
        catalog: List<ExerciseForRecommendation>,
        source: RecommendationDataSource,
        preferSpanish: Boolean,
        ctx: WorkoutRecommendationContext
    ): List<StrengthRecommendationExerciseResult> {
        val now = Instant.now()
        val muscleSetCounts = mutableMapOf<String, Double>()
        for (s in flat) {
            val m = normMuscle(s.musclePrimary)
            if (m.isEmpty() || m == "cardio") continue
            val days = maxOf(0.0, ChronoUnit.SECONDS.between(s.startedAt ?: now, now) / 86400.0)
            muscleSetCounts[m] = (muscleSetCounts[m] ?: 0.0) + exp(-days / 7.0)
        }
        val recentMuscles = flat.filter { s ->
            val st = s.startedAt ?: return@filter false
            ChronoUnit.HOURS.between(st, now) < WorkoutRecommendationConstants.RECOVERY_DEPRIORITIZE_HOURS
        }.map { normMuscle(it.musclePrimary) }.filter { it.isNotEmpty() && it != "cardio" }.toSet()
        val sortedMuscles = muscleSetCounts.keys.sortedBy { muscleSetCounts[it] ?: 0.0 }
        val targetMuscles = if (sortedMuscles.isEmpty()) {
            catalog.map { normMuscle(it.musclePrimary) }.filter { it.isNotEmpty() && it != "cardio" }.toSet()
        } else {
            val preferred = sortedMuscles.filter { it !in recentMuscles }
            val base = if (preferred.isEmpty()) sortedMuscles else preferred
            base.take(min(3, base.size)).toSet()
        }
        val historyIds = flat.map { it.exerciseId }.toSet()
        val pool = exercisePool(catalog, source, historyIds, ctx)
        var filtered = pool.filter { targetMuscles.contains(normMuscle(it.musclePrimary)) }
        if (filtered.isEmpty()) filtered = pool
        val shuffled = WorkoutRecommendationConstants.biasedShuffle(filtered) { ctx.favoriteExerciseIds.contains(it.id) }
        val chosen = mutableListOf<ExerciseForRecommendation>()
        val used = mutableSetOf<Long>()
        for (ex in shuffled) {
            if (used.add(ex.id)) {
                chosen.add(ex)
                if (chosen.size >= WorkoutRecommendationConstants.TARGET_EXERCISE_COUNT) break
            }
        }
        for (ex in pool) {
            if (chosen.size >= WorkoutRecommendationConstants.TARGET_EXERCISE_COUNT) break
            if (used.add(ex.id)) chosen.add(ex)
        }
        return buildResultList(chosen.take(WorkoutRecommendationConstants.TARGET_EXERCISE_COUNT), flat, preferSpanish, ctx)
    }

    private fun buildResultList(
        chosen: List<ExerciseForRecommendation>,
        flat: List<FlatSet>,
        preferSpanish: Boolean,
        ctx: WorkoutRecommendationContext
    ): List<StrengthRecommendationExerciseResult> {
        val out = mutableListOf<StrengthRecommendationExerciseResult>()
        for (ex in chosen) {
            var setsOut = buildSetsForExercise(ex.id, flat, ctx)
            if (setsOut.isEmpty()) {
                val w = suggestWeight(ex.id, flat, ctx)
                setsOut = (1..WorkoutRecommendationConstants.DEFAULT_SETS_PER_EXERCISE).map { sn ->
                    StrengthRecommendationSetResult(
                        setNumber = sn,
                        reps = WorkoutRecommendationConstants.DEFAULT_REPS,
                        weightKg = w,
                        rpe = 8.0,
                        restSec = WorkoutRecommendationConstants.DEFAULT_REST_BETWEEN_SETS_SEC
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
        ctx: WorkoutRecommendationContext
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
        val prCap = ctx.prMaxWeightByExerciseId[exerciseId]?.plus(WorkoutRecommendationConstants.PR_CAP_INCREMENT_KG)
        val withWeight = inLast.map { s ->
            var template = s.weightKg ?: 0.0
            if (template <= 0) {
                template = if (carryTemplate > 0) carryTemplate else suggestWeight(exerciseId, flat, ctx)
            } else {
                carryTemplate = template
            }
            var adj = adjustWeight(template, avgRpe)
            prCap?.let { adj = min(adj, it) }
            val reps = s.reps?.coerceIn(
                WorkoutRecommendationConstants.MIN_RECOMMENDED_REPS,
                WorkoutRecommendationConstants.MAX_RECOMMENDED_REPS
            ) ?: WorkoutRecommendationConstants.DEFAULT_REPS
            StrengthRecommendationSetResult(
                setNumber = s.setNumber,
                reps = reps,
                weightKg = WorkoutRecommendationConstants.roundToHalf(adj),
                rpe = s.rpe,
                restSec = s.restSec ?: WorkoutRecommendationConstants.DEFAULT_REST_BETWEEN_SETS_SEC
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

    private fun suggestWeight(exerciseId: Long, flat: List<FlatSet>, ctx: WorkoutRecommendationContext): Double {
        val latestWid = latestWorkoutIdForExercise(exerciseId, flat) ?: return ctx.defaultColdStartWeightKg()
        val slice = flat.filter { it.exerciseId == exerciseId && it.workoutId == latestWid && it.weightKg != null }
        val weights = slice.mapNotNull { it.weightKg }
        if (weights.isEmpty()) {
            val any = flat.filter { it.exerciseId == exerciseId && it.weightKg != null }
            return WorkoutRecommendationConstants.roundToHalf(any.mapNotNull { it.weightKg }.maxOrNull() ?: ctx.defaultColdStartWeightKg())
        }
        val base = weights.maxOrNull() ?: ctx.defaultColdStartWeightKg()
        val rps = slice.mapNotNull { it.rpe }
        val avgRpe = if (rps.isEmpty()) 8.0 else rps.average()
        var adj = adjustWeight(base, avgRpe)
        ctx.prMaxWeightByExerciseId[exerciseId]?.let { adj = min(adj, it + WorkoutRecommendationConstants.PR_CAP_INCREMENT_KG) }
        return WorkoutRecommendationConstants.roundToHalf(adj)
    }

    private fun adjustWeight(base: Double, avgRpe: Double): Double = when {
        avgRpe < 8.0 -> base + WorkoutRecommendationConstants.RPE_WEIGHT_DELTA_KG
        avgRpe >= 9.0 -> (base - WorkoutRecommendationConstants.RPE_WEIGHT_DELTA_KG).coerceAtLeast(0.0)
        else -> base
    }
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
