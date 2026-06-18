package com.lilru.liftr.ui.profile

import kotlin.math.abs

object ComparePrsFormat {
    fun prettyMetricName(metric: String): String = PrFormatting.prettyMetricName(metric)

    fun formatValue(metric: String, value: Double?, label: String = ""): String =
        PrFormatting.formatValue(metric, value, label)

    fun winner(
        metric: String,
        myValue: Double?,
        otherValue: Double?
    ): PrWinner {
        if (myValue == null || otherValue == null) return PrWinner.Unknown
        if (abs(myValue - otherValue) < 1e-9) return PrWinner.Tie
        val lowerIsBetter = PrFormatting.lowerIsBetter(metric)
        return if (lowerIsBetter) {
            if (myValue < otherValue) PrWinner.Me else PrWinner.Other
        } else {
            if (myValue > otherValue) PrWinner.Me else PrWinner.Other
        }
    }
}

enum class PrWinner { Me, Other, Tie, Unknown }
