package com.lilru.liftr.ui.profile.progress

import java.time.DayOfWeek
import java.time.format.TextStyle
import java.util.Locale
import kotlin.math.max

enum class ProfileProgressRange {
    WEEK,
    MONTH,
    YEAR
}

enum class ProfileProgressSubtab {
    ACTIVITY,
    INTENSITY,
    CONSISTENCY,
    /** Paridad con iOS [ProfileView.ProgressSubtab.weekdaySummary]. */
    WEEKDAY
}

enum class ProfileActivityMetric {
    WORKOUTS,
    SCORE,
    CALORIES
}

/** Alineado con iOS [ConsistencyChartMetric]. */
enum class ConsistencyChartMetric(val wire: String) {
    DURATION("duration"),
    WORKOUTS("workouts"),
    SCORE("score"),
    CALORIES("calories");

    companion object {
        fun fromWire(s: String?): ConsistencyChartMetric =
            entries.find { it.wire == s } ?: DURATION
    }

    val pickerLabel: String
        get() = when (this) {
            DURATION -> "Time"
            WORKOUTS -> "Workouts"
            SCORE -> "Score"
            CALORIES -> "Calories"
        }

    val chartAxisLabel: String
        get() = when (this) {
            DURATION -> "Minutes"
            WORKOUTS -> "Workouts"
            SCORE -> "Score"
            CALORIES -> "kcal"
        }

    fun measure(durationMin: Int, count: Int, score: Double, kcal: Double): Double =
        when (this) {
            DURATION -> durationMin.toDouble()
            WORKOUTS -> count.toDouble()
            SCORE -> maxOf(0.0, score)
            CALORIES -> maxOf(0.0, kcal)
        }
}

data class ConsistencyWorkoutMeta(
    val kind: String,
    val durationMin: Int,
    val score: Double,
    val kcal: Double
)

data class KindSlice(
    val kind: String,
    val count: Int,
    val durationMin: Int,
    val score: Double,
    val kcal: Double
)

data class ProgressPoint(
    val label: String,
    val value: Double
)

data class DrilldownSlice(
    val title: String,
    val count: Int,
    val durationMin: Int,
    val score: Double,
    val kcal: Double
)

/** Paridad con [Liftr.ProfileView.WeekdayMetric] / [Liftr.ProfileView.WeekdayPoint]. */
enum class WeekdayProgressMetric {
    WORKOUTS,
    SCORE,
    CALORIES,
    HOURS
}

data class WeekdayPointUi(
    val weekdayIndex: Int,
    val label: String,
    val occurrences: Int,
    val workoutsTotal: Int,
    val scoreTotal: Double,
    val caloriesTotal: Double,
    val durationMinutesTotal: Int
) {
    fun totalValue(m: WeekdayProgressMetric): Double = when (m) {
        WeekdayProgressMetric.WORKOUTS -> workoutsTotal.toDouble()
        WeekdayProgressMetric.SCORE -> scoreTotal
        WeekdayProgressMetric.CALORIES -> max(0.0, caloriesTotal)
        WeekdayProgressMetric.HOURS -> durationMinutesTotal / 60.0
    }

    fun averageValue(m: WeekdayProgressMetric): Double {
        if (occurrences <= 0) return 0.0
        return totalValue(m) / occurrences.toDouble()
    }
}

fun defaultWeekdayLabelsForLocale(locale: Locale = Locale.getDefault()): List<String> {
    return (0..6).map { i ->
        DayOfWeek.MONDAY.plus(i.toLong()).getDisplayName(TextStyle.SHORT, locale)
    }
}
