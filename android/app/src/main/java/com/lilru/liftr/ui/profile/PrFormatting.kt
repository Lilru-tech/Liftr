package com.lilru.liftr.ui.profile

import com.lilru.liftr.ui.add.AddCardioActivity
import com.lilru.liftr.ui.add.AddSportType
import java.util.Locale
import kotlin.math.max
import kotlin.math.roundToInt

object PrFormatting {
    fun activityLabel(kind: String, label: String): String {
        val k = kind.lowercase(Locale.US)
        val wire = label.lowercase(Locale.US)
        if (k == "cardio") {
            AddCardioActivity.entries.find { it.wire == wire }?.let { return cardioTypeLabel(it) }
            if (wire == "cardio") return "Cardio"
            return snakeToTitle(wire)
        }
        if (k == "sport") {
            AddSportType.entries.find { it.wire == wire }?.let {
                return sportTypeLabel(it)
            }
            return snakeToTitle(wire)
        }
        return label
    }

    fun activityIcon(kind: String, label: String): String {
        val k = kind.lowercase(Locale.US)
        val wire = label.lowercase(Locale.US)
        return when (k) {
            "strength" -> "💪"
            "cardio" -> cardioIcon(wire)
            "sport" -> sportIcon(wire)
            else -> ""
        }
    }

    fun prettyMetricName(metric: String, kind: String = "", label: String = ""): String {
        val m = metric.lowercase(Locale.US)
        return when (m) {
            "max_hr", "max_avg_hr" -> "Max HR"
            "longest_duration_sec", "max_moving_time_sec" -> "Longest duration"
            "longest_distance_km", "max_total_distance_km" -> "Longest distance"
            "fastest_pace_sec_per_km" -> "Fastest pace"
            "max_elevation_m", "max_vertical_drop_m", "max_total_vertical_m" -> "Max elevation"
            "est_1rm_kg" -> "Estimated 1RM"
            "max_weight_kg" -> "Max weight"
            "best_set_volume_kg" -> "Best set volume"
            "max_reps" -> "Max reps"
            "max_cadence_rpm" -> "Max cadence"
            "max_watts_avg" -> "Max watts"
            "min_split_sec_per_500m" -> "Best split"
            "max_goals" -> "Max goals"
            "max_assists" -> "Max assists"
            "max_shots_on_target" -> "Max shots on target"
            "max_shots_on_goal" -> "Max shots on goal"
            "max_saves" -> "Max saves"
            "max_tackles", "max_tackles_made" -> "Max tackles"
            "max_yellow" -> "Max yellow cards"
            "max_red" -> "Max red cards"
            "max_points" -> "Max points"
            "max_rebounds" -> "Max rebounds"
            "max_steals" -> "Max steals"
            "max_blocks" -> "Max blocks"
            "min_turnovers" -> "Fewest turnovers"
            "max_fouls" -> "Max fouls"
            "max_sets_won" -> "Max sets won"
            "max_games_won" -> "Max games won"
            "max_aces" -> "Max aces"
            "min_double_faults" -> "Fewest double faults"
            "max_winners" -> "Max winners"
            "min_unforced_errors" -> "Fewest unforced errors"
            "max_break_points_won" -> "Max break points won"
            "max_net_points_won" -> "Max net points won"
            "max_digs" -> "Max digs"
            "min_official_time_sec" -> "Best official time"
            "max_runs_count" -> "Max runs"
            "max_speed_kmh" -> "Max speed"
            "max_routes_sent" -> "Max routes sent"
            "max_flashes" -> "Max flashes"
            "max_hits" -> "Max hits"
            "max_penalty_minutes" -> "Max penalty minutes"
            "max_tries" -> "Max tries"
            "max_meters_gained" -> "Max meters gained"
            "max_offloads" -> "Max offloads"
            "max_turnovers_won" -> "Max turnovers won"
            else -> snakeToTitle(m)
        }
    }

    fun formatValue(metric: String, value: Double?, label: String = ""): String {
        if (value == null) return "—"
        val m = metric.lowercase(Locale.US)
        if (m.endsWith("_kg") || m == "est_1rm_kg" || m == "max_weight_kg" || m == "best_set_volume_kg") {
            return String.format(Locale.US, "%.1f kg", value)
        }
        if (m.contains("reps") && !m.contains("sec")) {
            return "${value.roundToInt()} reps"
        }
        if (m == "max_hr" || m == "max_avg_hr") {
            return "${value.roundToInt()} bpm"
        }
        if (m == "longest_distance_km" || m == "max_total_distance_km") {
            return String.format(Locale.US, "%.1f km", value)
        }
        if (m == "max_speed_kmh") {
            return String.format(Locale.US, "%.1f km/h", value)
        }
        if (m == "max_elevation_m" || m == "max_vertical_drop_m" || m == "max_total_vertical_m") {
            return "${value.roundToInt()} m"
        }
        if (m == "max_cadence_rpm") {
            val unit = if (label.lowercase(Locale.US) == "rowerg") "spm" else "rpm"
            return "${value.roundToInt()} $unit"
        }
        if (m == "max_watts_avg") {
            return "${value.roundToInt()} W"
        }
        if (m == "fastest_pace_sec_per_km") {
            return paceString(value, "/km")
        }
        if (m == "min_split_sec_per_500m") {
            return paceString(value, "/500m")
        }
        if (m.endsWith("_sec") || m.contains("duration") || m.contains("time")) {
            return durationString(value)
        }
        if (m.endsWith("_km")) {
            return String.format(Locale.US, "%.1f km", value)
        }
        if (m.endsWith("_kmh")) {
            return String.format(Locale.US, "%.1f km/h", value)
        }
        if (m.endsWith("_m") && !m.contains("min")) {
            return "${value.roundToInt()} m"
        }
        if (m.startsWith("max_") || m.startsWith("min_")) {
            return "${value.roundToInt()}"
        }
        return String.format(Locale.US, "%.2f", value)
    }

    fun lowerIsBetter(metric: String): Boolean {
        val m = metric.lowercase(Locale.US)
        return m.startsWith("min_")
            || m.contains("pace")
            || m.contains("fastest")
            || m.contains("official_time")
            || m.contains("split")
            || m.contains("turnover")
            || m.contains("double_fault")
            || m.contains("unforced_error")
    }

    fun metricSortOrder(metric: String): Int {
        val order = listOf(
            "longest_distance_km", "max_total_distance_km",
            "longest_duration_sec", "max_moving_time_sec", "min_official_time_sec",
            "fastest_pace_sec_per_km", "min_split_sec_per_500m",
            "max_speed_kmh",
            "max_elevation_m", "max_vertical_drop_m", "max_total_vertical_m",
            "max_hr", "max_avg_hr",
            "max_weight_kg", "est_1rm_kg", "best_set_volume_kg", "max_reps",
            "max_cadence_rpm", "max_watts_avg",
            "max_goals", "max_assists", "max_points", "max_tries",
            "max_routes_sent", "max_flashes", "max_runs_count"
        )
        val m = metric.lowercase(Locale.US)
        val idx = order.indexOf(m)
        if (idx >= 0) return idx
        return 1000 + m.hashCode().mod(1000)
    }

    fun kindSortOrder(kind: String): Int = when (kind.lowercase(Locale.US)) {
        "strength" -> 0
        "cardio" -> 1
        "sport" -> 2
        else -> 3
    }

    private fun cardioTypeLabel(type: AddCardioActivity): String = when (type) {
        AddCardioActivity.RUN -> "Run"
        AddCardioActivity.WALK -> "Walk"
        AddCardioActivity.HIKE -> "Hike"
        AddCardioActivity.TREADMILL -> "Treadmill"
        AddCardioActivity.BIKE -> "Bike"
        AddCardioActivity.E_BIKE -> "E-Bike"
        AddCardioActivity.MTB -> "MTB"
        AddCardioActivity.INDOOR_CYCLING -> "Indoor cycling"
        AddCardioActivity.ROWERG -> "RowErg"
        AddCardioActivity.SWIM_POOL -> "Swim (pool)"
        AddCardioActivity.SWIM_OPEN_WATER -> "Swim (open water)"
    }

    private fun sportTypeLabel(type: AddSportType): String = when (type) {
        AddSportType.PADEL -> "Padel"
        AddSportType.TENNIS -> "Tennis"
        AddSportType.FOOTBALL -> "Football"
        AddSportType.BASKETBALL -> "Basketball"
        AddSportType.BADMINTON -> "Badminton"
        AddSportType.SQUASH -> "Squash"
        AddSportType.TABLE_TENNIS -> "Table Tennis"
        AddSportType.VOLLEYBALL -> "Volleyball"
        AddSportType.HANDBALL -> "Handball"
        AddSportType.HOCKEY -> "Hockey"
        AddSportType.RUGBY -> "Rugby"
        AddSportType.HYROX -> "Hyrox"
        AddSportType.SKI -> "Ski"
        AddSportType.CLIMBING -> "Climbing"
    }

    private fun sportIcon(sport: String): String = when (sport) {
        "padel", "tennis", "squash", "badminton", "table_tennis" -> "🎾"
        "football" -> "⚽️"
        "basketball" -> "🏀"
        "volleyball" -> "🏐"
        "rugby" -> "🏉"
        "hockey", "field_hockey" -> "🏑"
        "handball" -> "🤾‍♂️"
        "hyrox" -> "🔥"
        "ski" -> "⛷️"
        "climbing" -> "🧗"
        else -> "🏅"
    }

    private fun cardioIcon(activity: String): String = when (activity) {
        "run", "outdoor_run", "trail_run" -> "🏃‍♂️"
        "treadmill" -> "🏃‍♀️"
        "walk", "hike" -> "🚶‍♂️"
        "bike", "e_bike", "mtb", "cycling", "road_cycling" -> "🚴‍♂️"
        "indoor_cycling", "spinning" -> "🚲"
        "rowerg", "rowing" -> "🚣‍♂️"
        "swim_pool" -> "🏊‍♂️"
        "swim_open_water" -> "🌊"
        "cardio" -> "❤️‍🔥"
        else -> "❤️‍🔥"
    }

    private fun durationString(value: Double): String {
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

    private fun paceString(value: Double, suffix: String): String {
        val s = max(1, value.roundToInt())
        return String.format(Locale.US, "%d:%02d %s", s / 60, s % 60, suffix)
    }

    private fun snakeToTitle(s: String): String =
        s.replace('_', ' ').replaceFirstChar { c ->
            if (c.isLowerCase()) c.titlecase(Locale.getDefault()) else c.toString()
        }
}
