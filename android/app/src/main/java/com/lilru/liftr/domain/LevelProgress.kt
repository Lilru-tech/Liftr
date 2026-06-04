package com.lilru.liftr.domain

import kotlin.math.max
import kotlin.math.min

fun levelProgressRatio(
    totalXp: Long,
    currentFloor: Long,
    nextCap: Long
): Double {
    val span = nextCap - currentFloor
    if (span <= 0) return 0.0
    val earned = totalXp - currentFloor
    return min(1.0, max(0.0, earned.toDouble() / span.toDouble()))
}
