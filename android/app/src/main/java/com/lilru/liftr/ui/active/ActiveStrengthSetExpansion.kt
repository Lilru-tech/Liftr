package com.lilru.liftr.ui.active

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
    val current = sets.getOrNull(expandedIndex) ?: return sets
    val configId = current.configId
    val configCount = sets.count { it.configId == configId }
    val updated = if (current.segmentsInRow <= 1 || configCount <= 1) {
        sets.map { line ->
            if (line.configId != configId) line
            else line.copy(reps = reps, weightKg = weightKg, rpe = rpe, restSec = restSec)
        }
    } else {
        val lastIdxForConfig = sets.indexOfLast { it.configId == configId }
        sets.mapIndexed { idx, line ->
            if (idx != expandedIndex && idx != lastIdxForConfig) {
                line
            } else if (idx == expandedIndex) {
                line.copy(reps = reps, weightKg = weightKg, rpe = rpe)
            } else {
                line.copy(rpe = rpe, restSec = restSec)
            }
        }
    }
    return renumberExpandedSets(updated)
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
