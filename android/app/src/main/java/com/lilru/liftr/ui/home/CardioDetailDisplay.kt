package com.lilru.liftr.ui.home

import com.lilru.liftr.ui.add.AddCardioActivity
import java.util.Locale
import kotlin.math.max
import kotlin.math.roundToInt

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

fun isSwimCardioActivityCode(code: String): Boolean {
    val c = code.trim().lowercase(Locale.US)
    return c == AddCardioActivity.SWIM_POOL.wire ||
        c == AddCardioActivity.SWIM_OPEN_WATER.wire ||
        c == "pool_swim" || c == "pool_swimming" ||
        c == "open_water_swim" || c == "open_water"
}

fun formatPaceMinSecPerKm(paceSecPerKm: Int): String {
    val s = max(0, paceSecPerKm)
    return String.format(Locale.US, "%d:%02d /km", s / 60, s % 60)
}

fun secPer100mFromSecPerKm(secPerKm: Int): Int =
    max(0, (secPerKm / 10.0).roundToInt())

fun formatSwimPaceMinSecPer100m(paceSecPerKm: Int): String {
    val s = secPer100mFromSecPerKm(paceSecPerKm)
    return String.format(Locale.US, "%d:%02d /100m", s / 60, s % 60)
}

fun formatSwimDistanceKm(km: Double): String {
    val meters = km * 1000.0
    return if (kotlin.math.abs(meters.roundToInt() - meters) < 0.001) {
        String.format(Locale.US, "%.0f m", meters.roundToInt().toDouble())
    } else {
        String.format(Locale.US, "%.1f m", meters)
    }
}

fun formatCardioDistance(km: Double, activityCode: String): String =
    if (isSwimCardioActivityCode(activityCode)) formatSwimDistanceKm(km)
    else String.format(Locale.US, "%.2f km", km)

fun formatCardioPace(paceSecPerKm: Int, activityCode: String): String =
    if (isSwimCardioActivityCode(activityCode)) formatSwimPaceMinSecPer100m(paceSecPerKm)
    else formatPaceMinSecPerKm(paceSecPerKm)

fun distanceKmFromMetersText(text: String): Double? {
    val t = text.trim().replace(',', '.')
    if (t.isEmpty()) return null
    val meters = t.toDoubleOrNull() ?: return null
    if (meters <= 0.0) return null
    return meters / 1000.0
}

fun metersTextFromKm(km: Double?): String {
    if (km == null || km <= 0.0) return ""
    val meters = km * 1000.0
    return if (kotlin.math.abs(meters.roundToInt() - meters) < 0.001) {
        meters.roundToInt().toString()
    } else {
        String.format(Locale.US, "%.1f", meters)
    }
}

fun autoPaceSecPerKmFromMeters(distanceMetersText: String, durationSec: Int): Int? {
    val km = distanceKmFromMetersText(distanceMetersText) ?: return null
    if (durationSec <= 0) return null
    return (durationSec.toDouble() / km).roundToInt()
}

fun poolDistanceMetersFromLaps(lapsText: String, poolLengthMText: String): Int? {
    val laps = lapsText.trim().toIntOrNull() ?: return null
    val pool = poolLengthMText.trim().toIntOrNull() ?: return null
    if (laps <= 0 || pool <= 0) return null
    return laps * pool
}

fun formatMmSs(totalSec: Int): String {
    val s = max(0, totalSec)
    return String.format(Locale.US, "%d:%02d", s / 60, s % 60)
}
