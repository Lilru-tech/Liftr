package com.lilru.liftr.ui.active

import androidx.annotation.StringRes
import com.lilru.liftr.R

data class SportMatchResultEntry(
    val raw: String,
    @StringRes val labelRes: Int
)

/**
 * Alinea con [MatchResult] en [AddWorkoutSheet.swift] (iOS).
 */
val sportMatchResultEntries: List<SportMatchResultEntry> = listOf(
    SportMatchResultEntry("win", R.string.match_result_win),
    SportMatchResultEntry("loss", R.string.match_result_loss),
    SportMatchResultEntry("draw", R.string.match_result_draw),
    SportMatchResultEntry("unfinished", R.string.match_result_unfinished),
    SportMatchResultEntry("forfeit", R.string.match_result_forfeit)
)

private val validMatchResultRaws: Set<String> = sportMatchResultEntries.map { it.raw }.toSet()

fun normalizeSportMatchResult(raw: String?): String {
    val t = raw?.trim()?.lowercase() ?: return "unfinished"
    return if (t in validMatchResultRaws) t else "unfinished"
}
