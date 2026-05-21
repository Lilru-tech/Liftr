package com.lilru.liftr.ui.active

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class StrengthSupersetNavigationTest {

    private fun line(
        id: Int,
        group: String?,
        position: Int?,
        sets: Int = 3
    ) = ActiveStrengthExerciseLine(
        workoutExerciseId = id,
        displayName = "Ex$id",
        sets = (1..sets).map { i ->
            ActiveStrengthSetLine(
                setId = id * 100 + i,
                configId = id * 100 + i,
                setNumber = i,
                reps = 10,
                weightKg = 50.0,
                restSec = if (i == sets) 90 else 0
            )
        },
        orderIndex = id,
        supersetGroupId = group,
        supersetPosition = position
    )

    @Test
    fun groupsPairSupersetMembers() {
        val exercises = listOf(
            line(1, "g1", 1),
            line(2, "g1", 2),
            line(3, null, null)
        )
        val groups = strengthDisplayGroups(exercises)
        assertEquals(2, groups.size)
        assertTrue(groups[0].isSuperset)
        assertEquals(listOf(0, 1), groups[0].exerciseIndices)
        assertFalse(groups[1].isSuperset)
    }

    @Test
    fun shouldDeferRestUntilLastMemberInRound() {
        val exercises = listOf(line(1, "g1", 1), line(2, "g1", 2))
        assertFalse(shouldStartRestAfterCompletingSet(exercises[0], exercises, setIndex = 0))
        assertTrue(shouldStartRestAfterCompletingSet(exercises[1], exercises, setIndex = 0))
    }

    @Test
    fun pagerAnchorUsesFirstMemberIndex() {
        val exercises = listOf(line(1, "g1", 1), line(2, "g1", 2))
        assertEquals(0, pagerAnchorExerciseIndex(1, exercises))
    }
}
