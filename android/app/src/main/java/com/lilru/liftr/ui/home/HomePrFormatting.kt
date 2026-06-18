package com.lilru.liftr.ui.home

import android.text.format.DateUtils
import com.lilru.liftr.ui.profile.PrFormatting
import java.time.Instant

object HomePrFormatting {
    fun prettyMetric(metric: String, kind: String = "", label: String = ""): String =
        PrFormatting.prettyMetricName(metric, kind, label)

    fun formatValue(metric: String, value: Double, label: String = ""): String =
        PrFormatting.formatValue(metric, value, label)

    fun activityLabel(kind: String, label: String): String =
        PrFormatting.activityLabel(kind, label)

    fun relativeShort(iso: String): String {
        if (iso.isBlank()) return "—"
        val t = runCatching { Instant.parse(iso).toEpochMilli() }.getOrNull() ?: return "—"
        return DateUtils.getRelativeTimeSpanString(
            t,
            System.currentTimeMillis(),
            DateUtils.MINUTE_IN_MILLIS,
            DateUtils.FORMAT_ABBREV_RELATIVE
        ).toString()
    }
}

fun homeFeedRelativeStartedAt(iso: String?): String {
    if (iso.isNullOrBlank()) return "—"
    val t = runCatching { Instant.parse(iso).toEpochMilli() }.getOrNull() ?: return "—"
    return DateUtils.getRelativeTimeSpanString(
        t,
        System.currentTimeMillis(),
        DateUtils.MINUTE_IN_MILLIS,
        DateUtils.FORMAT_ABBREV_RELATIVE
    ).toString()
}
