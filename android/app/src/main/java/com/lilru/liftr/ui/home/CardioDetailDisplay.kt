package com.lilru.liftr.ui.home

import java.util.Locale
import kotlin.math.max

/**
 * Paridad con helpers en [Liftr.WorkoutDetailView] (cadencia, vatios, etc.) para mostrar [cardio_session_stats].
 */
fun effectiveCardioActivityCode(cardio: CardioSessionDetail): String {
    val a = cardio.activityCode?.trim().orEmpty()
    if (a.isNotEmpty()) return a.lowercase(Locale.US)
    return cardio.modality?.trim().orEmpty().lowercase(Locale.US)
}

fun showsCardioCadenceForActivity(code: String): Boolean {
    if (code.isEmpty()) return false
    return code in setOf("bike", "e_bike", "mtb", "indoor_cycling", "rowerg")
}

fun showsCardioWattsForActivity(code: String): Boolean {
    if (code.isEmpty()) return false
    return code in setOf("bike", "e_bike", "indoor_cycling", "rowerg", "mtb")
}

fun showsCardioInclineForActivity(code: String): Boolean = code == "treadmill"

fun showsCardioSplit500mForActivity(code: String): Boolean = code == "rowerg"

fun showsCardioSwimFieldsForActivity(code: String): Boolean = code == "swim_pool"

/** m:ss /km, alineado con [Liftr.WorkoutDetailView] pace / liftr. */
fun formatPaceMinSecPerKm(paceSecPerKm: Int): String {
    val s = max(0, paceSecPerKm)
    return String.format(Locale.US, "%d:%02d /km", s / 60, s % 60)
}

fun formatMmSs(totalSec: Int): String {
    val s = max(0, totalSec)
    return String.format(Locale.US, "%d:%02d", s / 60, s % 60)
}
