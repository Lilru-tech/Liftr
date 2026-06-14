package com.lilru.liftr.domain

import java.util.Locale

fun formatCompactCount(value: Int): String = formatCompactCount(value.toLong())

fun formatCompactCount(value: Long): String = when {
    value >= 1_000_000L -> String.format(Locale.US, "%.1fM", value / 1_000_000.0)
    value >= 1_000L -> String.format(Locale.US, "%.1fk", value / 1_000.0)
    else -> value.toString()
}
