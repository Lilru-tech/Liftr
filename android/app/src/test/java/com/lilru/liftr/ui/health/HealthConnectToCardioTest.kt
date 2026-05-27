package com.lilru.liftr.ui.health

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class HealthConnectToCardioTest {
    @Test
    fun healthConnectWorkoutExternalId_prefixesNonBlankId() {
        assertEquals("hc:session-abc", healthConnectWorkoutExternalId("session-abc"))
    }

    @Test
    fun healthConnectWorkoutExternalId_trimsWhitespace() {
        assertEquals("hc:abc", healthConnectWorkoutExternalId("  abc  "))
    }

    @Test
    fun healthConnectWorkoutExternalId_returnsNullForBlank() {
        assertNull(healthConnectWorkoutExternalId(""))
        assertNull(healthConnectWorkoutExternalId("   "))
    }
}
