package com.lilru.liftr.ui.compare

import java.util.Locale

enum class CompareAverageScope {
    MINE,
    GLOBAL
}

sealed class CompareOtherTarget {
    data class Workout(val id: Int) : CompareOtherTarget()
    data class Average(
        val scope: CompareAverageScope,
        val workoutIds: List<Int>,
        val sampleCount: Int
    ) : CompareOtherTarget()
}

data class CompareAverageOption(
    val scope: CompareAverageScope,
    val workoutIds: List<Int>,
    val sampleCount: Int,
    val typeLabel: String
)

sealed class ComparePickerEntry {
    data class AverageRow(val option: CompareAverageOption) : ComparePickerEntry()
    data class SessionRow(val candidate: CompareWorkoutCandidate) : ComparePickerEntry()
}

data class ComparePickerState(
    val sessions: List<CompareWorkoutCandidate> = emptyList(),
    val myAverage: CompareAverageOption? = null,
    val globalAverage: CompareAverageOption? = null
) {
    val hasAnyOption: Boolean =
        sessions.isNotEmpty() || myAverage != null || globalAverage != null

    val entries: List<ComparePickerEntry>
        get() = buildList {
            myAverage?.let { add(ComparePickerEntry.AverageRow(it)) }
            globalAverage?.let { add(ComparePickerEntry.AverageRow(it)) }
            sessions.forEach { add(ComparePickerEntry.SessionRow(it)) }
        }
}

/**
 * Paridad con [Liftr.WorkoutDetailView.CompareCandidate] (RPC [list_comparable_workouts_v1]).
 */
data class CompareWorkoutCandidate(
    val id: Int,
    val title: String?,
    val kind: String,
    val sport: String?,
    val activity: String?,
    val startedAtIso: String,
    val ownerUsername: String?
) {
    val displayTitle: String
        get() {
            val t = title?.trim().orEmpty()
            if (t.isNotEmpty()) return t
            return when (kind.lowercase(Locale.US)) {
                "sport" -> (sport ?: "Sport").replace("_", " ")
                    .replaceFirstChar { if (it.isLowerCase()) it.titlecase(Locale.US) else it.toString() }
                "cardio" -> (activity ?: "Cardio").replace("_", " ")
                    .replaceFirstChar { if (it.isLowerCase()) it.titlecase(Locale.US) else it.toString() }
                else -> "Workout"
            }
        }
}

data class CompareMetricRow(
    val key: String,
    val unit: String,
    val left: Double,
    val right: Double
) {
    val rawDiffPct: Double?
        get() = if (right == 0.0) null else (left - right) / right * 100.0
}

data class CompareSessionLabels(
    val kind: String,
    val bothMine: Boolean,
    val leftLabel: String,
    val rightLabel: String,
    val leftUserName: String?,
    val rightUserName: String?
)
