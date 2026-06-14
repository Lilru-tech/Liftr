package com.lilru.liftr.data

import androidx.compose.ui.graphics.Color
import java.time.Instant
import java.time.ZoneId
import java.time.ZonedDateTime
import java.time.temporal.TemporalAdjusters

enum class CoinSourcesPeriod(val label: String) {
    WEEK("Week"),
    MONTH("Month"),
    YEAR("Year"),
    ALL_TIME("All time")
}

data class CoinSourceSlice(
    val sourceKey: String,
    val totalAmount: Int
) {
    val label: String get() = CoinManager.sourceCategoryLabel(sourceKey)
    val color: Color get() = CoinManager.sourceCategoryColor(sourceKey)
}

data class CoinSourcesTimeWindow(
    val start: Instant?,
    val endExclusive: Instant?
)

object CoinSourcesTimeWindows {
    private val zone: ZoneId get() = ZoneId.systemDefault()

    fun forPeriod(period: CoinSourcesPeriod, now: ZonedDateTime = ZonedDateTime.now(zone)): CoinSourcesTimeWindow {
        if (period == CoinSourcesPeriod.ALL_TIME) {
            return CoinSourcesTimeWindow(null, null)
        }
        val dayStart = now.toLocalDate().atStartOfDay(zone)
        return when (period) {
            CoinSourcesPeriod.WEEK -> {
                val start = dayStart.minusDays(6)
                val end = dayStart.plusDays(1)
                CoinSourcesTimeWindow(start.toInstant(), end.toInstant())
            }
            CoinSourcesPeriod.MONTH -> {
                val start = dayStart.minusDays(29)
                val end = dayStart.plusDays(1)
                CoinSourcesTimeWindow(start.toInstant(), end.toInstant())
            }
            CoinSourcesPeriod.YEAR -> {
                val monthStart = now.with(TemporalAdjusters.firstDayOfMonth()).toLocalDate().atStartOfDay(zone)
                val start = monthStart.minusMonths(11)
                val end = dayStart.plusDays(1)
                CoinSourcesTimeWindow(start.toInstant(), end.toInstant())
            }
            CoinSourcesPeriod.ALL_TIME -> CoinSourcesTimeWindow(null, null)
        }
    }
}
