package com.lilru.liftr.ui.add.recommendation

import com.lilru.liftr.data.BackendContracts
import com.lilru.liftr.ui.goals.LiftrGoalsTime
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.query.Columns
import io.github.jan.supabase.postgrest.query.Order
import io.github.jan.supabase.postgrest.postgrest
import java.time.Instant
import java.time.temporal.ChronoUnit
import kotlin.math.min
import kotlin.math.roundToInt
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

data class GoalRecommendationNudge(
    val workoutsRemaining: Int? = null,
    val caloriesRemaining: Double? = null,
    val summaryLine: String? = null
)

data class MuscleFreshnessEntryResult(
    val muscle: String,
    val status: String
)

data class StrengthRecommendationOutputResult(
    val exercises: List<StrengthRecommendationExerciseResult>,
    val sessionRationale: String? = null,
    val muscleFreshness: List<MuscleFreshnessEntryResult> = emptyList(),
    val routineName: String? = null
)

data class WorkoutRecommendationContext(
    val profileWeightKg: Double? = null,
    val profileSex: String? = null,
    val favoriteExerciseIds: Set<Long> = emptySet(),
    val prMaxWeightByExerciseId: Map<Long, Double> = emptyMap(),
    val goalNudge: GoalRecommendationNudge? = null,
    val publishedStrengthCount: Int = 0,
    val networkExerciseFrequency: Map<Long, Int> = emptyMap(),
    val partialDataNote: String? = null
) {
    val isBeginnerLifter: Boolean
        get() = publishedStrengthCount < WorkoutRecommendationConstants.BEGINNER_STRENGTH_SESSION_THRESHOLD

    fun defaultColdStartWeightKg(): Double =
        WorkoutRecommendationConstants.defaultColdStartWeightKg(profileWeightKg, isBeginnerLifter)

    fun appendGoalLine(rationale: String): String {
        val line = goalNudge?.summaryLine ?: return rationale
        if (rationale.isEmpty()) return line
        return "$rationale $line"
    }

    fun cardioDurationMultiplier(): Double {
        val rem = goalNudge?.caloriesRemaining ?: return 1.0
        if (rem <= 0) return 1.0
        return when {
            rem > 500 -> 1.15
            rem > 200 -> 1.08
            else -> 1.0
        }
    }
}

object WorkoutRecommendationConstants {
    const val LOOKBACK_COUNT = 10
    const val TARGET_EXERCISE_COUNT = 5
    const val DEFAULT_SETS_PER_EXERCISE = 3
    const val DEFAULT_REPS = 12
    const val MAX_RECOMMENDED_SETS = 5
    const val MAX_INFERRED_SETS_FROM_SET_NUMBER = 8
    const val MAX_RECOMMENDED_REPS = 22
    const val MIN_RECOMMENDED_REPS = 6
    const val HIGH_VOLUME_REPS_THRESHOLD = 17
    const val HIGH_VOLUME_SETS_THRESHOLD = 5
    const val DEFAULT_REST_BETWEEN_SETS_SEC = 90
    const val RPE_WEIGHT_DELTA_KG = 2.5
    const val RECOVERY_DEPRIORITIZE_HOURS = 48
    const val FAVORITE_SELECTION_BOOST = 2
    const val PR_CHASE_PROXIMITY_RATIO = 0.05
    const val PR_CAP_INCREMENT_KG = 2.5
    const val BEGINNER_STRENGTH_SESSION_THRESHOLD = 5
    const val NETWORK_LOOKBACK_DAYS = 7

    fun defaultColdStartWeightKg(profileWeightKg: Double?, isBeginner: Boolean): Double {
        if (profileWeightKg != null && profileWeightKg > 0) {
            val factor = if (isBeginner) 0.12 else 0.18
            return roundToHalf(min(60.0, maxOf(5.0, profileWeightKg * factor)))
        }
        return if (isBeginner) 15.0 else 20.0
    }

    fun roundToHalf(x: Double) = (x * 2.0).roundToInt() / 2.0

    fun <T> biasedShuffle(items: List<T>, isBoosted: (T) -> Boolean): List<T> {
        val boosted = mutableListOf<T>()
        val rest = mutableListOf<T>()
        for (item in items) {
            if (isBoosted(item)) {
                repeat(FAVORITE_SELECTION_BOOST) { boosted.add(item) }
            } else {
                rest.add(item)
            }
        }
        return (boosted + rest).shuffled()
    }
}

object WorkoutRecommendationContextLoader {

    @Serializable
    private data class PRRow(
        val kind: String,
        val label: String,
        val metric: String,
        val value: Double
    )

    suspend fun load(
        supabase: SupabaseClient,
        json: Json,
        userId: String,
        catalog: List<ExerciseForRecommendation>,
        includeNetwork: Boolean
    ): WorkoutRecommendationContext {
        var ctx = WorkoutRecommendationContext()

        @Serializable
        data class ProfileRow(
            @SerialName("weight_kg") val weightKg: Double? = null,
            val sex: String? = null,
            @SerialName("date_of_birth") val dateOfBirth: String? = null
        )
        runCatching {
            val pRes = supabase.from(BackendContracts.Tables.PROFILES)
                .select(Columns.raw("weight_kg, sex, date_of_birth")) {
                    filter { eq("user_id", userId) }
                }
            val rows = json.decodeFromString<List<ProfileRow>>(pRes.data)
            rows.firstOrNull()?.let { p ->
                ctx = ctx.copy(profileWeightKg = p.weightKg, profileSex = p.sex)
            }
        }

        @Serializable
        data class FavRow(@SerialName("exercise_id") val exerciseId: Long)
        runCatching {
            val fRes = supabase.from(BackendContracts.Tables.USER_FAVORITE_EXERCISES)
                .select(Columns.raw("exercise_id")) {
                    filter { eq("user_id", userId) }
                }
            val favs = json.decodeFromString<List<FavRow>>(fRes.data).map { it.exerciseId }.toSet()
            ctx = ctx.copy(favoriteExerciseIds = favs)
        }

        runCatching {
            val prParams = buildJsonObject {
                put("p_user_id", userId)
                put("p_kind", "strength")
            }
            val prRes = supabase.postgrest.rpc(BackendContracts.Rpc.GET_USER_PRS, prParams) { }
            val prs = json.decodeFromString<List<PRRow>>(prRes.data)
            ctx = ctx.copy(prMaxWeightByExerciseId = mapStrengthPrs(prs, catalog))
        }

        @Serializable
        data class CountRow(val id: Int)
        runCatching {
            val cRes = supabase.from(BackendContracts.Tables.WORKOUTS)
                .select(Columns.raw("id")) {
                    filter {
                        eq("user_id", userId)
                        eq("kind", "strength")
                        eq("state", "published")
                    }
                }
            ctx = ctx.copy(publishedStrengthCount = json.decodeFromString<List<CountRow>>(cRes.data).size)
        }

        ctx = ctx.copy(goalNudge = loadGoalNudge(supabase, json, userId))

        if (includeNetwork) {
            val (freq, note) = loadNetworkFrequency(supabase, json, userId)
            ctx = ctx.copy(networkExerciseFrequency = freq, partialDataNote = note)
        }

        return ctx
    }

    private fun mapStrengthPrs(
        prs: List<PRRow>,
        catalog: List<ExerciseForRecommendation>
    ): Map<Long, Double> {
        val metrics = setOf("weight_kg", "max_weight_kg", "weight")
        val out = mutableMapOf<Long, Double>()
        for (pr in prs) {
            if (pr.kind.lowercase() != "strength") continue
            if (pr.metric.lowercase() !in metrics) continue
            val norm = pr.label.trim().lowercase()
            if (norm.isEmpty()) continue
            for (ex in catalog) {
                val names = listOfNotNull(ex.name, ex.nameEn, ex.nameEs).map { it.trim().lowercase() }
                if (norm in names) {
                    out[ex.id] = maxOf(out[ex.id] ?: 0.0, pr.value)
                }
            }
        }
        return out
    }

    private suspend fun loadGoalNudge(
        supabase: SupabaseClient,
        json: Json,
        userId: String
    ): GoalRecommendationNudge? {
        val weekStr = LiftrGoalsTime.currentWeekStartDateString()
        @Serializable
        data class GoalRow(
            val id: Long,
            val metric: String,
            @SerialName("target_value") val targetValue: Double
        )
        @Serializable
        data class ResultRow(
            @SerialName("goal_id") val goalId: Long,
            @SerialName("achieved_value") val achievedValue: Double? = null,
            @SerialName("is_completed") val isCompleted: Boolean? = null
        )
        val gRes = runCatching {
            supabase.from(BackendContracts.Tables.WEEKLY_GOALS)
                .select(Columns.raw("id, metric, target_value")) {
                    filter {
                        eq("user_id", userId)
                        eq("week_start", weekStr)
                    }
                }
        }.getOrNull() ?: return null
        val goals = json.decodeFromString<List<GoalRow>>(gRes.data)
        if (goals.isEmpty()) return null
        val resultsByGoal = mutableMapOf<Long, ResultRow>()
        runCatching {
            val rRes = supabase.from(BackendContracts.Tables.WEEKLY_GOAL_RESULTS)
                .select(Columns.raw("goal_id, achieved_value, is_completed")) {
                    filter {
                        isIn("goal_id", goals.map { it.id.toString() })
                        eq("week_start", weekStr)
                    }
                }
            json.decodeFromString<List<ResultRow>>(rRes.data).forEach { resultsByGoal[it.goalId] = it }
        }
        val lines = mutableListOf<String>()
        var workoutsRemaining: Int? = null
        var caloriesRemaining: Double? = null
        for (g in goals) {
            val r = resultsByGoal[g.id]
            if (r?.isCompleted == true) continue
            val achieved = r?.achievedValue ?: 0.0
            when (g.metric.lowercase()) {
                "workouts" -> {
                    val rem = maxOf(0, g.targetValue.roundToInt() - achieved.roundToInt())
                    if (rem in 1..2) {
                        workoutsRemaining = rem
                        lines += if (rem == 1) {
                            "You're 1 workout away from this week's workout goal."
                        } else {
                            "You're $rem workouts away from this week's workout goal."
                        }
                    }
                }
                "calories" -> {
                    val rem = maxOf(0.0, g.targetValue - achieved)
                    if (rem > 150) {
                        caloriesRemaining = rem
                        lines += "Calorie goal still open this week—a slightly longer session can help."
                    }
                }
            }
        }
        if (lines.isEmpty()) return null
        return GoalRecommendationNudge(workoutsRemaining, caloriesRemaining, lines.joinToString(" "))
    }

    private suspend fun loadNetworkFrequency(
        supabase: SupabaseClient,
        json: Json,
        userId: String
    ): Pair<Map<Long, Int>, String?> {
        @Serializable
        data class FollowRow(@SerialName("followee_id") val followeeId: String)
        val fRes = runCatching {
            supabase.from(BackendContracts.Tables.FOLLOWS)
                .select(Columns.raw("followee_id")) {
                    filter { eq("follower_id", userId) }
                    limit(50)
                }
        }.getOrNull() ?: return emptyMap<Long, Int>() to null
        val followees = json.decodeFromString<List<FollowRow>>(fRes.data).map { it.followeeId }
        if (followees.isEmpty()) return emptyMap<Long, Int>() to null
        val since = Instant.now().minus(WorkoutRecommendationConstants.NETWORK_LOOKBACK_DAYS.toLong(), ChronoUnit.DAYS)
        @Serializable
        data class WRow(val id: Int)
        val wRes = runCatching {
            supabase.from(BackendContracts.Tables.WORKOUTS)
                .select(Columns.raw("id")) {
                    filter {
                        isIn("user_id", followees)
                        eq("kind", "strength")
                        eq("state", "published")
                        gte("started_at", since.toString())
                    }
                    limit(100)
                }
        }.getOrNull() ?: return emptyMap<Long, Int>() to "Your network hasn't logged strength workouts recently—we used your own history."
        val workouts = json.decodeFromString<List<WRow>>(wRes.data)
        if (workouts.isEmpty()) {
            return emptyMap<Long, Int>() to "Your network hasn't logged strength workouts recently—we used your own history."
        }
        @Serializable
        data class ExRow(@SerialName("exercise_id") val exerciseId: Long)
        val exRes = runCatching {
            supabase.from(BackendContracts.Tables.WORKOUT_EXERCISES)
                .select(Columns.raw("exercise_id")) {
                    filter { isIn("workout_id", workouts.map { it.id.toString() }) }
                }
        }.getOrNull() ?: return emptyMap<Long, Int>() to "Could not load network exercise trends."
        val freq = json.decodeFromString<List<ExRow>>(exRes.data)
            .groupingBy { it.exerciseId }.eachCount()
        return freq to null
    }
}
