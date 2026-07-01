package com.lilru.liftr.ui.tasks

import kotlin.math.roundToInt

object WeeklyTaskProgressFormat {
    fun formatValue(metric: String, value: Double): String {
        return when (metric) {
            "pace_sec_per_km" -> {
                val mins = (value / 60).toInt()
                val secs = (value % 60).toInt()
                "%d:%02d".format(mins, secs)
            }
            "duration_sec" -> (value / 60.0).roundToInt().toString()
            "distance_km", "volume_kg", "max_weight_kg" -> "%.1f".format(value)
            else -> value.roundToInt().toString()
        }
    }

    fun formatWithUnit(metric: String, value: Double): String {
        val v = formatValue(metric, value)
        return when (metric) {
            "calories_kcal" -> "$v kcal"
            "distance_km" -> "$v km"
            "duration_sec", "sport_weekly_minutes", "hyrox_weekly_minutes" -> "$v min"
            "sport_sessions_weekly" -> {
                val n = value.roundToInt()
                if (n == 1) "1 session" else "$n sessions"
            }
            "volume_kg", "max_weight_kg" -> "$v kg"
            "total_reps" -> "$v reps"
            "total_sets" -> "$v sets"
            "routes_sent" -> {
                val n = value.roundToInt()
                if (n == 1) "1 route" else "$n routes"
            }
            "problems_sent" -> {
                val n = value.roundToInt()
                if (n == 1) "1 problem" else "$n problems"
            }
            "pace_sec_per_km" -> "$v min/km"
            else -> v
        }
    }
}
