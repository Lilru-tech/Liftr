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

    @Test
    fun collapsedSetMultipliesVolume() {
        data class Row(
            val id: Int,
            val orderIndex: Int?,
            val setNumber: Int,
            val reps: Int?,
            val weightKg: Double?,
            val weightSegments: List<StrengthWeightSegmentWire>?
        )
        val rows = listOf(
            Row(id = 1, orderIndex = 1, setNumber = 5, reps = 12, weightKg = 60.0, weightSegments = null)
        )
        val volume = strengthDetailVolumeKg(
            setsByExercise = mapOf(1 to rows),
            orderIndex = { it.orderIndex },
            id = { it.id },
            setNumber = { it.setNumber },
            reps = { it.reps },
            weightKg = { it.weightKg },
            weightSegments = { it.weightSegments }
        )
        assertEquals(3600.0, volume, 0.001)
    }

    @Test
    fun sequentialSetsDoNotMultiplyVolume() {
        data class Row(
            val id: Int,
            val orderIndex: Int?,
            val setNumber: Int,
            val reps: Int?,
            val weightKg: Double?,
            val weightSegments: List<StrengthWeightSegmentWire>?
        )
        val rows = listOf(
            Row(id = 1, orderIndex = 1, setNumber = 1, reps = 10, weightKg = 50.0, weightSegments = null),
            Row(id = 2, orderIndex = 2, setNumber = 2, reps = 10, weightKg = 50.0, weightSegments = null),
            Row(id = 3, orderIndex = 3, setNumber = 3, reps = 10, weightKg = 50.0, weightSegments = null)
        )
        val volume = strengthDetailVolumeKg(
            setsByExercise = mapOf(1 to rows),
            orderIndex = { it.orderIndex },
            id = { it.id },
            setNumber = { it.setNumber },
            reps = { it.reps },
            weightKg = { it.weightKg },
            weightSegments = { it.weightSegments }
        )
        assertEquals(1500.0, volume, 0.001)
    }

    @Test
    fun dropSetSegmentsSumBeforeMultiplier() {
        data class Row(
            val id: Int,
            val orderIndex: Int?,
            val setNumber: Int,
            val reps: Int?,
            val weightKg: Double?,
            val weightSegments: List<StrengthWeightSegmentWire>?
        )
        val rows = listOf(
            Row(
                id = 1,
                orderIndex = 1,
                setNumber = 2,
                reps = 8,
                weightKg = 80.0,
                weightSegments = listOf(
                    StrengthWeightSegmentWire(reps = 8, weightKg = 80.0),
                    StrengthWeightSegmentWire(reps = 4, weightKg = 60.0)
                )
            )
        )
        val volume = strengthDetailVolumeKg(
            setsByExercise = mapOf(1 to rows),
            orderIndex = { it.orderIndex },
            id = { it.id },
            setNumber = { it.setNumber },
            reps = { it.reps },
            weightKg = { it.weightKg },
            weightSegments = { it.weightSegments }
        )
        assertEquals(1760.0, volume, 0.001)
    }
}
