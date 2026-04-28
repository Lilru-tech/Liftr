package com.lilru.liftr.ui.goals

import com.lilru.liftr.ui.home.WorkoutSummary
import java.time.DayOfWeek
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.TemporalAdjusters
import kotlin.math.min
import kotlin.math.roundToInt

/** Same zone and Monday week start as iOS [GoalsManager]. */
object LiftrGoalsTime {
    val ZONE: ZoneId = ZoneId.of("Europe/Madrid")

    fun currentWeekStartDateString(now: Instant = Instant.now()): String {
        val local = now.atZone(ZONE).toLocalDate()
        val monday = local.with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY))
        return monday.toString()
    }
}

enum class GoalMetric(val wire: String) {
    WORKOUTS("workouts"),
    CALORIES("calories"),
    SCORE("score");

    val title: String
        get() = when (this) {
            WORKOUTS -> "Workouts"
            CALORIES -> "Calories"
            SCORE -> "Score"
        }

    val unit: String
        get() = when (this) {
            WORKOUTS -> "workouts/week"
            CALORIES -> "kcal/week"
            SCORE -> "score/week"
        }

    companion object {
        fun fromWire(w: String): GoalMetric =
            entries.firstOrNull { it.wire == w } ?: WORKOUTS
    }
}

enum class GoalsSummaryScope { WEEK, ALL_TIME }

data class GoalRowUi(
    val id: Long,
    val userId: String,
    val weekStartDate: String,
    val title: String,
    val targetValue: Double,
    val achievedValue: Double,
    val isCompleted: Boolean,
    val metric: String
) {
    val progressRatio: Double
        get() {
            val t = targetValue
            if (t <= 0) return 0.0
            return achievedValue / t
        }

    val progress: Double
        get() = minOf(1.0, progressRatio)
}

data class GoalStatsUi(
    val totalGoals: Int,
    val finishedGoals: Int,
    val finishedPercent: Double,
    val avgProgressPercent: Double,
    val bestProgressPercent: Double
)

/** Resumen semanal alineado con [GoalContributionsSummary] en iOS. */
data class GoalContributionsSummaryUi(
    val workoutCount: Int,
    val totalScore: Int,
    val avgScore: Int,
    val maxScore: Int,
    val totalKcal: Int,
    val avgKcal: Int,
    val maxKcal: Int,
    val activeDays: Int,
    val kindCounts: List<Pair<String, Int>>,
    val goalProgressLine: String
)

fun buildGoalContributionsSummary(goal: GoalRowUi, rows: List<WorkoutSummary>): GoalContributionsSummaryUi {
    val workoutCount = rows.size
    val scoreVals = rows.map { it.score ?: 0.0 }
    val totalScore = scoreVals.sum().roundToInt()
    val avgScore = if (workoutCount > 0) (scoreVals.sum() / workoutCount).roundToInt() else 0
    val maxScore = scoreVals.maxOrNull()?.roundToInt() ?: 0
    val kcalVals = rows.map { it.caloriesKcal ?: 0.0 }
    val totalKcal = kcalVals.sum().roundToInt()
    val avgKcal = if (workoutCount > 0) (kcalVals.sum() / workoutCount).roundToInt() else 0
    val maxKcal = kcalVals.maxOrNull()?.roundToInt() ?: 0
    val dayKeys = rows.mapNotNull { r ->
        r.startedAt?.take(10)
    }.toSet()
    val activeDays = dayKeys.size
    val byKind = rows.mapNotNull { it.kind?.lowercase() }.groupingBy { it }.eachCount()
    val kindCounts = byKind.toList().sortedBy { it.first }
    val targetRounded = goal.targetValue.roundToInt()
    val achieved = goal.achievedValue.roundToInt()
    val pct = if (targetRounded > 0) {
        min(999, ((achieved.toDouble() / targetRounded) * 100).roundToInt())
    } else 0
    val pl = when (GoalMetric.fromWire(goal.metric)) {
        GoalMetric.WORKOUTS -> "Target $targetRounded workouts · Logged $achieved · $pct%"
        GoalMetric.CALORIES -> "Target $targetRounded kcal · Logged $achieved · $pct%"
        GoalMetric.SCORE -> "Target $targetRounded pts · Logged $achieved · $pct%"
    }
    return GoalContributionsSummaryUi(
        workoutCount = workoutCount,
        totalScore = totalScore,
        avgScore = avgScore,
        maxScore = maxScore,
        totalKcal = totalKcal,
        avgKcal = avgKcal,
        maxKcal = maxKcal,
        activeDays = activeDays,
        kindCounts = kindCounts,
        goalProgressLine = pl
    )
}

fun goalIsFinished(g: GoalRowUi, now: Instant = Instant.now()): Boolean {
    if (g.isCompleted) return true
    val start = runCatching { LocalDate.parse(g.weekStartDate.take(10)) }.getOrNull() ?: return false
    val weekEnd = start.plusDays(7).atStartOfDay(LiftrGoalsTime.ZONE).toInstant()
    return !now.isBefore(weekEnd)
}
