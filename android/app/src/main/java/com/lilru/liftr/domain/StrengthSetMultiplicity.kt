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
