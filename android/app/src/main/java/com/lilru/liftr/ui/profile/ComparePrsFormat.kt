package com.lilru.liftr.ui.profile

import java.util.Locale
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.roundToInt

/**
 * Alinea con [Liftr.ComparePRsView] — nombres de métricas y formateo de valores.
 */
object ComparePrsFormat {
    fun prettyMetricName(metric: String): String {
        val m = metric.lowercase(Locale.US)
        if (m == "max_hr") return "Max HR"
        if (m == "longest_duration_sec") return "Longest duration"
        if (m == "longest_distance_km") return "Longest distance"
        if (m == "fastest_pace_sec_per_km") return "Fastest pace"
        if (m == "max_elevation_m") return "Max elevation"
        if (m == "est_1rm_kg") return "Estimated 1RM"
        if (m == "max_weight_kg") return "Max weight"
        if (m == "best_set_volume_kg") return "Best set volume"
        if (m == "max_reps") return "Max reps"
        return m.replace('_', ' ').replaceFirstChar { c ->
            if (c.isLowerCase()) c.titlecase(Locale.getDefault()) else c.toString()
        }
    }

    fun formatValue(metric: String, value: Double?): String {
        if (value == null) return "—"
        val m = metric.lowercase(Locale.US)
        if (m.endsWith("_kg") || m == "est_1rm_kg" || m == "max_weight_kg" || m == "best_set_volume_kg") {
            return String.format(Locale.US, "%.1f kg", value)
        }
        if (m.contains("reps")) return "${value.roundToInt()} reps"
        if (m == "max_hr") return "${value.roundToInt()} bpm"
        if (m == "longest_distance_km") return String.format(Locale.US, "%.1f km", value)
        if (m == "max_elevation_m") return "${value.roundToInt()} m"
        if (m == "fastest_pace_sec_per_km") {
            val s = max(1, value.roundToInt())
            return String.format(Locale.US, "%d:%02d /km", s / 60, s % 60)
        }
        if (m.endsWith("_sec") || m.contains("duration")) {
            val s = max(0, value.roundToInt())
            val h = s / 3600
            val mm = (s % 3600) / 60
            val ss = s % 60
            return if (h > 0) {
                String.format(Locale.US, "%d:%02d:%02d", h, mm, ss)
            } else {
                String.format(Locale.US, "%d:%02d", mm, ss)
            }
        }
        return String.format(Locale.US, "%.2f", value)
    }

    fun winner(
        metric: String,
        myValue: Double?,
        otherValue: Double?
    ): PrWinner {
        if (myValue == null || otherValue == null) return PrWinner.Unknown
        if (abs(myValue - otherValue) < 1e-9) return PrWinner.Tie
        val m = metric.lowercase(Locale.US)
        val lowerIsBetter = m.contains("pace") || m.contains("fastest")
        return if (lowerIsBetter) {
            if (myValue < otherValue) PrWinner.Me else PrWinner.Other
        } else {
            if (myValue > otherValue) PrWinner.Me else PrWinner.Other
        }
    }
}

enum class PrWinner { Me, Other, Tie, Unknown }
