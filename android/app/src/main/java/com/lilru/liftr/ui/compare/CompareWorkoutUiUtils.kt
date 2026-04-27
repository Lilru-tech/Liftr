package com.lilru.liftr.ui.compare

import java.util.Locale
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.roundToInt

object CompareWorkoutFormat {
    private const val HyroxCustomPairingSep = "\u001E"

    fun metricDirection(metric: String): Double {
        if (metric.startsWith("hyrox.station.") && metric.endsWith(".duration_sec")) return -1.0
        return when (metric) {
            "avg_pace_sec_per_km", "fastest_km_pace_sec", "split_sec_per_500m",
            "sec_per_km", "sec_per_500m", "avg_hr", "max_hr", "score_against",
            "hx_penalty_time_sec", "hx_official_time_sec", "hx_rank_overall", "hx_rank_category", "hx_no_reps" -> -1.0
            else -> 1.0
        }
    }

    fun barPairFractions(left: Double, right: Double, metric: String): Pair<Float, Float> {
        val maxV0 = max(max(left, right), 0.0001)
        if (metricDirection(metric) >= 0) {
            return (left / maxV0).toFloat() to (right / maxV0).toFloat()
        }
        val e = 1e-6
        val sL = 1.0 / max(left, e)
        val sR = 1.0 / max(right, e)
        val m = max(sL, sR)
        if (m < 1e-20) return 0.5f to 0.5f
        return (sL / m).toFloat() to (sR / m).toFloat()
    }

    fun rawDiffPct(left: Double, right: Double): Double? =
        if (right == 0.0) null else (left - right) / right * 100.0

    fun overallSignedPcts(rows: List<CompareMetricRow>): List<Double> =
        rows.mapNotNull { m ->
            val p = rawDiffPct(m.left, m.right) ?: return@mapNotNull null
            (p * metricDirection(m.key)).coerceIn(-150.0, 150.0)
        }

    fun overallPct(signed: List<Double>): Double? {
        if (signed.isEmpty()) return null
        return signed.sum() / signed.size.toDouble()
    }

    fun overallPctFormat(v: Double): String {
        val a = abs(v)
        return if (a < 10) String.format(Locale.US, "%+.2f%%", v) else String.format(Locale.US, "%+.1f%%", v)
    }

    fun pctRowFormat(v: Double): String = String.format(Locale.US, "%+.1f%%", v)

    fun hasNonZero(m: CompareMetricRow): Boolean =
        abs(m.left) > 1e-9 || abs(m.right) > 1e-9

    fun prettyMetric(m: String): String = when (m) {
        "distance_km" -> "Distance"
        "duration_sec" -> "Duration"
        "avg_pace_sec_per_km" -> "Avg pace"
        "fastest_km_pace_sec" -> "Fastest km"
        "avg_hr" -> "Avg HR"
        "max_hr" -> "Max HR"
        "elevation_gain_m" -> "Elevation gain"
        "cadence" -> "Cadence"
        "watts_avg" -> "Avg watts"
        "incline_pct" -> "Incline"
        "swim_laps" -> "Laps"
        "pool_length_m" -> "Pool length"
        "split_sec_per_500m" -> "Split /500m"
        "score_for" -> "Score for"
        "score_against" -> "Score against"
        "rk_sets_won" -> "Sets won"
        "rk_sets_lost" -> "Sets lost"
        "rk_games_won" -> "Games won"
        "rk_games_lost" -> "Games lost"
        "rk_aces" -> "Aces"
        "rk_double_faults" -> "Double faults"
        "rk_winners" -> "Winners"
        "rk_unforced_errors" -> "Unforced errors"
        "rk_break_points_won" -> "Break points won"
        "rk_break_points_total" -> "Break points total"
        "rk_net_points_won" -> "Net points won"
        "rk_net_points_total" -> "Net points total"
        "bb_points" -> "Points"
        "bb_rebounds" -> "Rebounds"
        "bb_assists" -> "Assists"
        "bb_steals" -> "Steals"
        "bb_blocks" -> "Blocks"
        "bb_fg_made" -> "FG made"
        "bb_fg_attempted" -> "FG attempted"
        "bb_three_made" -> "3PT made"
        "bb_three_attempted" -> "3PT attempted"
        "bb_ft_made" -> "FT made"
        "bb_ft_attempted" -> "FT attempted"
        "bb_turnovers" -> "Turnovers"
        "bb_fouls" -> "Fouls"
        "fb_minutes_played" -> "Minutes played"
        "fb_goals" -> "Goals"
        "fb_assists" -> "Assists"
        "fb_shots_on_target" -> "Shots on target"
        "fb_passes_completed" -> "Passes completed"
        "fb_passes_attempted" -> "Passes attempted"
        "fb_tackles" -> "Tackles"
        "fb_interceptions" -> "Interceptions"
        "fb_saves" -> "Saves"
        "fb_yellow_cards" -> "Yellow cards"
        "fb_red_cards" -> "Red cards"
        "exercises_count" -> "Exercises"
        "sets_count" -> "Sets"
        "total_volume_kg" -> "Total volume"
        "total_reps" -> "Total reps"
        "avg_weight_per_rep_kg" -> "Avg weight / rep"
        "avg_weight_per_set_kg" -> "Avg weight / set"
        "volume_per_min_kg" -> "Volume / min"
        "sets_per_min" -> "Sets / min"
        "reps_per_min" -> "Reps / min"
        "max_weight_kg" -> "Heaviest set"
        "max_set_volume_kg" -> "Top set volume"
        "avg_rpe" -> "Average RPE"
        "hard_sets_count" -> "Hard sets (RPE ≥ 8)"
        "avg_reps_per_exercise" -> "Reps / exercise"
        "avg_sets_per_exercise" -> "Sets / exercise"
        "vb_points" -> "Points"
        "vb_aces" -> "Aces"
        "vb_blocks" -> "Blocks"
        "vb_digs" -> "Digs"
        "hb_minutes_played" -> "Minutes played"
        "hb_goals" -> "Goals"
        "hb_shots" -> "Shots"
        "hb_shots_on_target" -> "Shots on target"
        "hb_assists" -> "Assists"
        "hb_steals" -> "Steals"
        "hb_blocks" -> "Blocks"
        "hb_turnovers_lost" -> "Turnovers lost"
        "hb_seven_m_goals" -> "7 m goals"
        "hb_seven_m_attempts" -> "7 m attempts"
        "hb_saves" -> "Saves"
        "hb_yellow_cards" -> "Yellow cards"
        "hb_two_min_suspensions" -> "2-min suspensions"
        "hb_red_cards" -> "Red cards"
        "hk_minutes_played" -> "Minutes played"
        "hk_goals" -> "Goals"
        "hk_assists" -> "Assists"
        "hk_shots_on_goal" -> "Shots on goal"
        "hk_plus_minus" -> "+/-"
        "hk_hits" -> "Hits"
        "hk_blocks" -> "Blocks"
        "hk_faceoffs_won" -> "Faceoffs won"
        "hk_faceoffs_total" -> "Faceoffs total"
        "hk_saves" -> "Saves"
        "hk_penalty_minutes" -> "Penalty minutes"
        "rg_minutes_played" -> "Minutes played"
        "rg_tries" -> "Tries"
        "rg_conversions_made" -> "Conversions made"
        "rg_conversions_attempted" -> "Conversions attempted"
        "rg_penalty_goals_made" -> "Penalty goals made"
        "rg_penalty_goals_attempted" -> "Penalty goals attempted"
        "rg_runs" -> "Runs"
        "rg_meters_gained" -> "Meters gained"
        "rg_offloads" -> "Offloads"
        "rg_tackles_made" -> "Tackles made"
        "rg_tackles_missed" -> "Tackles missed"
        "rg_turnovers_won" -> "Turnovers won"
        "rg_yellow_cards" -> "Yellow cards"
        "rg_red_cards" -> "Red cards"
        "hx_official_time_sec" -> "Official time"
        "hx_rank_overall" -> "Overall rank"
        "hx_rank_category" -> "Category rank"
        "hx_no_reps" -> "No-reps"
        "hx_penalty_time_sec" -> "Penalty time"
        "hx_avg_hr" -> "Avg HR"
        "hx_max_hr" -> "Max HR"
        else -> if (m.startsWith("hyrox.station.")) prettyHyroxStationMetric(m) else titleCaseUnderscores(m)
    }

    private fun titleCaseUnderscores(m: String): String =
        m.replace('_', ' ').replaceFirstChar { c ->
            if (c.isLowerCase()) c.titlecase(Locale.getDefault()) else c.toString()
        }

    private fun prettyHyroxStationMetric(m: String): String {
        val comps = m.split('.')
        if (comps.size < 4 || comps[0] != "hyrox" || comps[1] != "station") {
            return titleCaseUnderscores(m)
        }
        val field = comps.last()
        val occKey = comps.drop(2).dropLast(1).joinToString(".")
        val station = hyroxOccurrenceLabel(occKey)
        val fieldLabel: String = when (field) {
            "distance_m" -> "Distance"
            "reps" -> "Reps"
            "duration_sec" -> "Duration"
            "weight_kg" -> "Weight"
            "implement_count" -> "Implements"
            else -> titleCaseUnderscores(field)
        }
        return "$station · $fieldLabel"
    }

    private fun hyroxCodeDisplayName(code: String): String = when (code) {
        "run" -> "Run"
        "row" -> "Row"
        "ski_erg" -> "Ski erg"
        "sled_push" -> "Sled push"
        "sled_pull" -> "Sled pull"
        "burpee_broad_jump" -> "Burpee broad jump"
        "farmer_carry" -> "Farmer's carry"
        "sandbag_lunges" -> "Sandbag lunges"
        "wall_balls" -> "Wall balls"
        else -> titleCaseUnderscores(code)
    }

    private fun hyroxOccurrenceLabel(key: String): String {
        if (key.startsWith("custom" + HyroxCustomPairingSep)) {
            val sep = HyroxCustomPairingSep
            val parts = key.split(sep, ignoreCase = false, limit = 0)
            if (parts.size == 3 && parts[0] == "custom" && parts[1].isNotEmpty()) {
                val ord = parts[2].toIntOrNull() ?: 0
                val title = parts[1].replaceFirstChar { c ->
                    if (c.isLowerCase()) c.titlecase(Locale.getDefault()) else c.toString()
                }
                return if (ord >= 2) "$title ($ord)" else title
            }
            return titleCaseUnderscores(key)
        }
        val u = key.lastIndexOf('_')
        if (u < 0) return titleCaseUnderscores(key)
        val suffix = key.substring(u + 1)
        val ord = suffix.toIntOrNull() ?: return titleCaseUnderscores(key)
        if (ord < 1) return titleCaseUnderscores(key)
        val code = key.substring(0, u)
        val name = hyroxCodeDisplayName(code)
        return if (ord == 1) name else "$name ($ord)"
    }

    fun formatValue(v: Double, unit: String): String = when (unit) {
        "km" -> String.format(Locale.US, "%.2f km", v)
        "kg" -> String.format(Locale.US, "%.1f kg", v)
        "sec" -> formatSecs(v)
        "sec_per_km" -> formatSecsPerKm(v)
        "sec_per_500m" -> formatSecsPer500(v)
        "bpm" -> String.format(Locale.US, "%.0f bpm", v)
        "m" -> String.format(Locale.US, "%.0f m", v)
        "W" -> String.format(Locale.US, "%.0f W", v)
        "pct" -> String.format(Locale.US, "%.1f %%", v)
        "count" -> String.format(Locale.US, "%.0f", v)
        "sets", "games", "pts", "laps", "min" -> String.format(Locale.US, "%.0f $unit", v)
        "kg_per_min" -> String.format(Locale.US, "%.1f kg/min", v)
        "sets_per_min" -> String.format(Locale.US, "%.2f sets/min", v)
        "reps_per_min" -> String.format(Locale.US, "%.2f reps/min", v)
        "kg_per_rep" -> String.format(Locale.US, "%.2f kg/rep", v)
        "kg_per_set" -> String.format(Locale.US, "%.2f kg/set", v)
        "rpe" -> String.format(Locale.US, "%.1f", v)
        "reps_per_exercise" -> String.format(Locale.US, "%.1f reps/ex", v)
        "sets_per_exercise" -> String.format(Locale.US, "%.1f sets/ex", v)
        else -> String.format(Locale.US, "%.2f $unit", v)
    }

    private fun formatSecs(v: Double): String {
        val s = max(0, v.roundToInt())
        val h = s / 3600
        val m = (s % 3600) / 60
        val sec = s % 60
        return if (h > 0) String.format(Locale.US, "%d:%02d:%02d", h, m, sec) else String.format(Locale.US, "%d:%02d", m, sec)
    }

    private fun formatSecsPerKm(v: Double): String {
        val s = max(0, v.roundToInt())
        return String.format(Locale.US, "%d:%02d /km", s / 60, s % 60)
    }

    private fun formatSecsPer500(v: Double): String {
        val s = max(0, v.roundToInt())
        return String.format(Locale.US, "%d:%02d /500m", s / 60, s % 60)
    }

}
