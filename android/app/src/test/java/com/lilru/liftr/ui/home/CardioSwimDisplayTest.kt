package com.lilru.liftr.ui.home

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

class CardioSwimDisplayTest {

    @Test
    fun screenshotExample_pacePer100m() {
        val durationSec = 49 * 60 + 12
        val pace = autoPaceSecPerKmFromMeters("2225", durationSec)
        assertNotNull(pace)
        assertTrue(pace!! in 1320..1335)
        assertEquals("2:13 /100m", formatSwimPaceMinSecPer100m(pace))
    }

    @Test
    fun metersKmRoundTrip() {
        val km = distanceKmFromMetersText("2225")
        assertNotNull(km)
        assertEquals(2.225, km!!, 0.0001)
        assertEquals("2225", metersTextFromKm(km))
    }

    @Test
    fun poolLapsTimesLength() {
        assertEquals(625, poolDistanceMetersFromLaps("25", "25"))
    }

    @Test
    fun isSwimActivity() {
        assertTrue(isSwimCardioActivityCode("swim_pool"))
        assertTrue(isSwimCardioActivityCode("swim_open_water"))
    }
}
