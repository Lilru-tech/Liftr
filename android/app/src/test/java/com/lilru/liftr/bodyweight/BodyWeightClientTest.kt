package com.lilru.liftr.bodyweight

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.time.Instant

class BodyWeightClientTest {
    @Test
    fun deltaTextWhenNoChange() {
        assertEquals("No change vs previous entry", BodyWeightPresentation.deltaText(80.0, 80.0))
    }

    @Test
    fun deltaTextWhenIncreased() {
        assertEquals("+1.2 kg vs previous entry", BodyWeightPresentation.deltaText(81.2, 80.0))
    }

    @Test
    fun periodDeltaUsesLatestAndBaseline() {
        val now = Instant.parse("2026-05-14T10:00:00Z")
        val old = Instant.parse("2026-04-01T10:00:00Z")
        val entries = listOf(
            BodyWeightEntryWire(
                id = "a",
                userId = "u",
                measuredAt = old.toString(),
                weightKg = 80.0,
                source = "manual"
            ),
            BodyWeightEntryWire(
                id = "b",
                userId = "u",
                measuredAt = now.toString(),
                weightKg = 81.0,
                source = "manual"
            )
        )
        assertEquals("+1.0 kg in the last 30 days", BodyWeightPresentation.periodDeltaText(entries, 30, now))
    }

    @Test
    fun chartPointsRespectRange() {
        val now = Instant.parse("2026-05-14T10:00:00Z")
        val old = now.minusSeconds(120L * 86_400L)
        val recent = now.minusSeconds(10L * 86_400L)
        val entries = listOf(
            BodyWeightEntryWire("a", "u", old.toString(), 70.0, "manual"),
            BodyWeightEntryWire("b", "u", recent.toString(), 72.0, "manual")
        )
        val points = BodyWeightPresentation.chartPoints(entries, BodyWeightRangePreset.Days30, now)
        assertEquals(1, points.size)
        assertEquals(72.0, points[0].value, 0.001)
    }

    @Test
    fun sourceLabelManual() {
        assertEquals("Manual", BodyWeightPresentation.sourceLabel(BodyWeightSource.Manual))
    }

    @Test
    fun deltaTextWithoutPreviousIsNull() {
        assertNull(BodyWeightPresentation.deltaText(80.0, null))
    }
}
