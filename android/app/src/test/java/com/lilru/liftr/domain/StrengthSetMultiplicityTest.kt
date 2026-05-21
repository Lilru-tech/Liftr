package com.lilru.liftr.domain

import org.junit.Assert.assertEquals
import org.junit.Test

class StrengthSetMultiplicityTest {
    @Test
    fun legacySequentialSetNumbersCountAsOneEach() {
        val mults = strengthSetMultiplicities(listOf(1, 2, 3))
        assertEquals(listOf(1, 1, 1), mults)
        assertEquals(3, mults.sum())
    }

    @Test
    fun explicitTimesUseSetNumberAsMultiplier() {
        val mults = strengthSetMultiplicities(listOf(4, 2))
        assertEquals(listOf(4, 2), mults)
        assertEquals(6, mults.sum())
    }

    @Test
    fun summaryPrefixOnlyWhenMultiplierAboveOne() {
        assertEquals("12 reps", strengthSetSummaryWithMultiplier("12 reps", 1))
        assertEquals("2× · 12 reps", strengthSetSummaryWithMultiplier("12 reps", 2))
    }
}
