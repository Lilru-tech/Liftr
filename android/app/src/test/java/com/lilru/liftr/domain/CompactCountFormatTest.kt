package com.lilru.liftr.domain

import org.junit.Assert.assertEquals
import org.junit.Test

class CompactCountFormatTest {
    @Test
    fun formatCompactCount_usesFullNumberBelowOneThousand() {
        assertEquals("42", formatCompactCount(42))
        assertEquals("999", formatCompactCount(999))
    }

    @Test
    fun formatCompactCount_abbreviatesThousandsAndMillions() {
        assertEquals("8.3k", formatCompactCount(8257))
        assertEquals("1.2M", formatCompactCount(1_200_000))
    }
}
