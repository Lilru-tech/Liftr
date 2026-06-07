package com.lilru.liftr.ui.active

import com.lilru.liftr.ui.add.StrengthProgramSet
import com.lilru.liftr.ui.add.StrengthSegmentPayload
import com.lilru.liftr.workout.StrengthWorkoutFinishCollapse
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlin.math.max

internal fun appendOneSetToExpandedSets(sets: List<ActiveStrengthSetLine>): List<ActiveStrengthSetLine> {
    if (sets.isEmpty()) {
        return listOf(
            ActiveStrengthSetLine(
                setId = -1,
                configId = -1,
                setNumber = 1,
                reps = 10,
                weightKg = 0.0,
                rpe = null,
                restSec = 60,
                segmentsInRow = 1
            )
        )
    }
    val template = sets.last()
    val nextSet = template.copy(
        setId = nextSyntheticSetId(sets),
        setNumber = sets.size + 1
    )
    return sets + nextSet
}

internal fun removeOneSetFromExpandedSets(sets: List<ActiveStrengthSetLine>): List<ActiveStrengthSetLine> {
    if (sets.size <= 1) return sets
    return renumberExpandedSets(sets.dropLast(1))
}

internal fun updateBlockForExpandedIndex(
    sets: List<ActiveStrengthSetLine>,
    expandedIndex: Int,
    reps: Int?,
    weightKg: Double?,
    rpe: Double?,
    restSec: Int?
): List<ActiveStrengthSetLine> {
    if (sets.getOrNull(expandedIndex) == null) return sets
    val newConfigId = nextSyntheticConfigId(sets)
    val updated = sets.mapIndexed { idx, line ->
        if (idx != expandedIndex) line
        else line.copy(
            configId = newConfigId,
            reps = reps,
            weightKg = weightKg,
            rpe = rpe,
            restSec = restSec
        )
    }
    return renumberExpandedSets(updated)
}

internal fun nextSyntheticConfigId(sets: List<ActiveStrengthSetLine>): Int {
    val minExisting = sets.minOfOrNull { it.configId } ?: 0
    return if (minExisting < 0) minExisting - 1 else -1
}

internal fun renumberExpandedSets(sets: List<ActiveStrengthSetLine>): List<ActiveStrengthSetLine> {
    return sets.mapIndexed { idx, line ->
        line.copy(setNumber = idx + 1)
    }
}

private fun nextSyntheticSetId(sets: List<ActiveStrengthSetLine>): Int {
    val minExisting = sets.minOfOrNull { it.setId } ?: 0
    return if (minExisting < 0) minExisting - 1 else -1
}

internal fun programSetsFromExpandedPlanned(
    planned: List<ActiveStrengthSetLine>,
    completedForExercise: List<CompletedSetLine>
): List<StrengthProgramSet> {
    if (planned.isEmpty()) return emptyList()
    val completedByConfig = completedForExercise.groupBy { it.configId }
    val configIdsInOrder = planned.map { it.configId }.distinct()
    return configIdsInOrder.mapIndexed { idx, configId ->
        val plannedForConfig = planned.filter { it.configId == configId }
        val multiplier = plannedForConfig.size.coerceIn(1, 99)
        val template = plannedForConfig.first()
        val collapsed = StrengthWorkoutFinishCollapse.collapseCompletedLinesForCompare(
            completedByConfig[configId].orEmpty()
        )
        if (collapsed.isNotEmpty()) {
            val first = collapsed.first()
            val performedCount = collapsed.sumOf { it.setNumber }.coerceAtLeast(1)
            StrengthProgramSet(
                setNumber = max(multiplier, performedCount),
                rowOrder = idx + 1,
                reps = first.reps ?: template.reps,
                weightKg = first.weightKg ?: template.weightKg,
                rpe = first.rpe ?: template.rpe,
                restSec = first.restSec ?: template.restSec,
                notes = null,
                weightSegments = strengthSegmentsFromJson(first.weightSegments ?: template.weightSegments)
            )
        } else {
            StrengthProgramSet(
                setNumber = multiplier,
                rowOrder = idx + 1,
                reps = template.reps,
                weightKg = template.weightKg,
                rpe = template.rpe,
                restSec = template.restSec,
                notes = null,
                weightSegments = strengthSegmentsFromJson(template.weightSegments)
            )
        }
    }
}

private fun strengthSegmentsFromJson(arr: JsonArray?): List<StrengthSegmentPayload>? {
    if (arr == null || arr.size < 2) return null
    val segs = arr.mapNotNull { el ->
        val o = el.jsonObject
        val r = o["reps"]?.jsonPrimitive?.content?.toIntOrNull() ?: return@mapNotNull null
        val w = o["weight_kg"]?.jsonPrimitive?.content?.toDoubleOrNull() ?: return@mapNotNull null
        StrengthSegmentPayload(r, w)
    }
    return segs.takeIf { it.size >= 2 }
}
