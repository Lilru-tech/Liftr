package com.lilru.liftr.ui.home

fun WorkoutDetailRow.cardioActivityCodeOrNull(): String? =
    cardioSessions?.firstOrNull()?.activityCode?.takeIf { it.isNotBlank() }

fun WorkoutDetailRow.sportNameOrNull(): String? =
    sportSessions?.firstOrNull()?.sport?.takeIf { it.isNotBlank() }

/**
 * Alinea con [ActiveCardioWorkoutView.activityLabel] / iOS: códigos tipo [road_cycling] → texto legible.
 */
fun formatActivityCodeForDisplay(code: String): String {
    if (code.isBlank()) return code
    return code.trim().split('_').joinToString(" ") { part ->
        part.replaceFirstChar { c -> if (c.isLowerCase()) c.titlecase() else c.toString() }
    }
}

/** Formato corto m:ss o h:mm:ss, alineado con otras pantallas de cardio/sport. */
fun formatDurationFromSec(totalSec: Int): String {
    if (totalSec < 0) return "0:00"
    val h = totalSec / 3600
    val m = (totalSec % 3600) / 60
    val s = totalSec % 60
    return if (h > 0) {
        String.format("%d:%02d:%02d", h, m, s)
    } else {
        String.format("%d:%02d", m, s)
    }
}
