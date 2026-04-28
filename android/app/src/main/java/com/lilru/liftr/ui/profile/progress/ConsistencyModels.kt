package com.lilru.liftr.ui.profile.progress

enum class ProfileProgressRange {
    WEEK,
    MONTH,
    YEAR
}

enum class ProfileProgressSubtab {
    ACTIVITY,
    INTENSITY,
    CONSISTENCY
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
