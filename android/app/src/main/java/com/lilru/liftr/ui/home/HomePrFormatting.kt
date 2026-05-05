package com.lilru.liftr.ui.home

import android.text.format.DateUtils
import java.time.Instant
import kotlin.math.roundToInt

/** Paridad con [Liftr/HomeView.swift] `HighlightsCard.prettyMetric` / `formatValue` / `relative`. */
object HomePrFormatting {
    fun prettyMetric(metric: String): String = when (metric.lowercase()) {
        "max_hr" -> "Max HR"
        "longest_duration_sec" -> "Longest duration"
        "longest_distance_km" -> "Longest distance"
        "fastest_pace_sec_per_km" -> "Fastest pace"
        "max_elevation_m" -> "Max elevation"
        "est_1rm_kg" -> "Estimated 1RM"
        "max_weight_kg" -> "Max weight"
        "best_set_volume_kg" -> "Best set volume"
        "max_reps" -> "Max reps"
        else -> metric.replace('_', ' ').replaceFirstChar { it.titlecase() }
    }

    fun formatValue(metric: String, value: Double): String {
        val m = metric.lowercase()
        return when {
            m.endsWith("_kg") || m == "est_1rm_kg" || m == "max_weight_kg" || m == "best_set_volume_kg" ->
                "%.1f kg".format(value)
            m.contains("reps") -> "${value.roundToInt()} reps"
            m == "max_hr" -> "${value.roundToInt()} bpm"
            m == "longest_distance_km" -> "%.1f km".format(value)
            m == "max_elevation_m" -> "${value.roundToInt()} m"
            m == "fastest_pace_sec_per_km" -> paceString(value)
            m.endsWith("_sec") || m.contains("duration") -> durationString(value)
            else -> "%.2f".format(value)
        }
    }

    private fun durationString(seconds: Double): String {
        val s = maxOf(0, seconds.roundToInt())
        val h = s / 3600
        val m = (s % 3600) / 60
        val sec = s % 60
        return if (h > 0) String.format("%d:%02d:%02d", h, m, sec) else String.format("%d:%02d", m, sec)
    }

    private fun paceString(seconds: Double): String {
        val s = maxOf(1, seconds.roundToInt())
        val m = s / 60
        val sec = s % 60
        return String.format("%d:%02d /km", m, sec)
    }

    fun relativeShort(iso: String): String {
        if (iso.isBlank()) return "—"
        val t = runCatching { Instant.parse(iso).toEpochMilli() }.getOrNull() ?: return "—"
        return DateUtils.getRelativeTimeSpanString(
            t,
            System.currentTimeMillis(),
            DateUtils.MINUTE_IN_MILLIS,
            DateUtils.FORMAT_ABBREV_RELATIVE
        ).toString()
    }
}

fun homeFeedRelativeStartedAt(iso: String?): String {
    if (iso.isNullOrBlank()) return "—"
    val t = runCatching { Instant.parse(iso).toEpochMilli() }.getOrNull() ?: return "—"
    return DateUtils.getRelativeTimeSpanString(
        t,
        System.currentTimeMillis(),
        DateUtils.MINUTE_IN_MILLIS,
        DateUtils.FORMAT_ABBREV_RELATIVE
    ).toString()
}
