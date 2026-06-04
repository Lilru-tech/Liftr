package com.lilru.liftr.domain

import kotlin.math.max

/**
 * Paridad con [strengthSetMultiplicities] en Liftr/StrengthSetMultiplicity.swift.
 */
fun strengthSetMultiplicities(sortedSetNumbers: List<Int>): List<Int> {
    val r = sortedSetNumbers.size
    if (r <= 0) return emptyList()
    if (sortedSetNumbers == (1..r).toList()) {
        return List(r) { 1 }
    }
    return sortedSetNumbers.map { max(it, 1) }
}

data class StrengthSetRowWithMultiplier<T>(
    val row: T,
    val multiplier: Int,
    val lineOrdinal: Int
)

fun <T> strengthSetRowsWithMultiplicities(
    rows: List<T>,
    orderIndex: (T) -> Int?,
    id: (T) -> Int,
    setNumber: (T) -> Int
): List<StrengthSetRowWithMultiplier<T>> {
    val sorted = rows.sortedWith(
        compareBy<T> { orderIndex(it) ?: Int.MAX_VALUE }.thenBy { id(it) }
    )
    val mults = strengthSetMultiplicities(sorted.map(setNumber))
    return sorted.mapIndexed { index, row ->
        StrengthSetRowWithMultiplier(
            row = row,
            multiplier = mults.getOrElse(index) { 1 },
            lineOrdinal = orderIndex(row) ?: (index + 1)
        )
    }
}

fun strengthSetSummaryWithMultiplier(body: String, multiplier: Int): String =
    if (multiplier > 1) "$multiplier× · $body" else body

data class StrengthWeightSegmentWire(
    val reps: Int,
    val weightKg: Double
)

fun exerciseSetSegmentVolumeKg(
    reps: Int?,
    weightKg: Double?,
    weightSegments: List<StrengthWeightSegmentWire>?
): Double {
    if (!weightSegments.isNullOrEmpty() && weightSegments.size >= 2) {
        return weightSegments.sumOf { max(it.reps, 0).toDouble() * max(it.weightKg, 0.0) }
    }
    val repVal = max(reps ?: 0, 0)
    val weightVal = weightKg ?: 0.0
    return repVal.toDouble() * max(weightVal, 0.0)
}

fun <T> strengthDetailVolumeKg(
    setsByExercise: Map<Int, List<T>>,
    orderIndex: (T) -> Int?,
    id: (T) -> Int,
    setNumber: (T) -> Int,
    reps: (T) -> Int?,
    weightKg: (T) -> Double?,
    weightSegments: (T) -> List<StrengthWeightSegmentWire>?
): Double {
    var total = 0.0
    for (rows in setsByExercise.values) {
        val paired = strengthSetRowsWithMultiplicities(rows, orderIndex, id, setNumber)
        for (item in paired) {
            val segmentVolume = exerciseSetSegmentVolumeKg(
                reps = reps(item.row),
                weightKg = weightKg(item.row),
                weightSegments = weightSegments(item.row)
            )
            total += segmentVolume * item.multiplier
        }
    }
    return total
}
