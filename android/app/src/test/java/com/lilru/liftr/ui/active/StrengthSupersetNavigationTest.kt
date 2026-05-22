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

    @Test
    fun workSetIndexUsesMinimumMemberProgress() {
        val exercises = listOf(line(1, "g1", 1, sets = 2), line(2, "g1", 2, sets = 2))
        val progress = mapOf(1 to 1, 2 to 0)
        assertEquals(0, supersetGroupWorkSetIndex(exercises, progress))
    }

    @Test
    fun memberFinishedRoundUsesPerformedSetsWhenIndexNotAdvanced() {
        val exercises = listOf(line(1, "g1", 1, sets = 2), line(2, "g1", 2, sets = 2))
        val ex = exercises[0]
        val progress = mapOf(ex.workoutExerciseId to 0)
        val completed = listOf(
            CompletedSetLine(
                workoutExerciseId = ex.workoutExerciseId,
                configId = 100,
                segmentsInRow = null,
                reps = 10,
                weightKg = 50.0,
                rpe = null,
                restSec = null,
                weightSegments = null
            )
        )
        assertTrue(supersetMemberFinishedRound(ex, roundIndex = 0, progress, completed))
    }

    @Test
    fun supersetPrimaryActionNeverUsesNextExerciseLabel() {
        val exercises = listOf(line(1, "g1", 1), line(2, "g1", 2))
        val set = exercises[0].sets[0]
        val label = primarySetActionLabel(
            ex = exercises[0],
            exercises = exercises,
            setIndex = 0,
            setProgress = mapOf(1 to 0, 2 to 0),
            currentSet = set
        )
        assertEquals("Set done", label)
    }

    @Test
    fun supersetRoundActionUsesRestFromLastMember() {
        val exercises = listOf(
            line(1, "g1", 1, sets = 3),
            line(2, "g1", 2, sets = 3)
        )
        val label = supersetRoundActionLabel(exercises, setIndex = 2)
        assertEquals("Rest 90s", label)
    }

    @Test
    fun supersetMembersContentHeightScalesWithCount() {
        assertTrue(supersetMembersContentHeightDp(2) < supersetMembersContentHeightDp(3))
        assertEquals(336, supersetMembersContentHeightDp(5))
    }
}
