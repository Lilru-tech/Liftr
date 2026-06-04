package com.lilru.liftr.domain

import org.junit.Assert.assertEquals
import org.junit.Test

class LevelProgressTest {
    @Test
    fun levelOneBandUsesFloorZero() {
        assertEquals(0.5, levelProgressRatio(60, 0, 120), 0.0001)
    }

    @Test
    fun higherLevelUsesWithinBandNotLifetimeOverNextCap() {
        assertEquals(0.5666666666666666, levelProgressRatio(11_700, 10_000, 13_000), 0.0001)
    }

    @Test
    fun atCurrentFloorIsZeroPercent() {
        assertEquals(0.0, levelProgressRatio(10_000, 10_000, 13_000), 0.0001)
    }

    @Test
    fun atNextCapIsOneHundredPercent() {
        assertEquals(1.0, levelProgressRatio(13_000, 10_000, 13_000), 0.0001)
    }

    @Test
    fun invalidSpanReturnsZero() {
        assertEquals(0.0, levelProgressRatio(500, 600, 600), 0.0001)
    }

    @Test
    fun clampsBelowFloorAndAboveCap() {
        assertEquals(0.0, levelProgressRatio(9_000, 10_000, 13_000), 0.0001)
        assertEquals(1.0, levelProgressRatio(15_000, 10_000, 13_000), 0.0001)
    }
}
