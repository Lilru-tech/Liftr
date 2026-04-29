package com.lilru.liftr.cardio

import kotlin.math.floor

/**
 * Paridad con [Liftr/ActiveCardioWorkoutView.swift] (kmPaceSplitSecondsPerKm, lapDeltas, lapsForManualDistance).
 */
object KmPaceSplitCalculator {

    private fun lapDeltas(cumulative: List<Int>): List<Int> {
        var prev = 0
        return cumulative.map { c ->
            val d = maxOf(0, c - prev)
            prev = c
            d
        }
    }

    private fun lapsForManualDistance(fullKmCount: Int, elapsedSec: Int, gpsCumulative: List<Int>): List<Int> {
        val n = fullKmCount
        val t = elapsedSec
        val g = gpsCumulative.size
        val laps = mutableListOf<Int>()
        var prev = 0
        val take = minOf(n, g)
        for (i in 0 until take) {
            val cum = gpsCumulative[i]
            laps.add(maxOf(0, cum - prev))
            prev = cum
        }
        if (laps.size < n) {
            val rem = n - laps.size
            val tail = maxOf(0, t - prev)
            if (rem > 0) {
                val base = tail / rem
                var rest = tail % rem
                repeat(rem) {
                    var v = base
                    if (rest > 0) {
                        v += 1
                        rest -= 1
                    }
                    laps.add(maxOf(1, v))
                }
            }
        }
        return laps
    }

    fun kmPaceSplitSecondsPerKm(
        usesGps: Boolean,
        distanceFieldUserEdited: Boolean,
        manualKm: Double,
        gpsKm: Double,
        elapsedSec: Int,
        gpsCumulative: List<Int>
    ): List<Int> {
        if (!usesGps) return emptyList()
        val tolerance = 0.04
        val treatAsGpsDistance = !distanceFieldUserEdited || kotlin.math.abs(manualKm - gpsKm) <= tolerance
        return if (treatAsGpsDistance) {
            if (gpsCumulative.isEmpty()) return emptyList()
            val laps = lapDeltas(gpsCumulative)
            if (laps.isEmpty()) emptyList() else laps
        } else {
            val n = floor(manualKm).toInt()
            if (n < 1) return emptyList()
            val laps = lapsForManualDistance(n, elapsedSec, gpsCumulative)
            if (laps.isEmpty()) emptyList() else laps
        }
    }
}
