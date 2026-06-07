package com.lilru.liftr.ui.add

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class StrengthRoutineOverwriteDiffTest {
    private fun item(exerciseId: Long, orderIndex: Int, sets: List<StrengthProgramSet>) =
        StrengthProgramItem(
            exerciseId = exerciseId,
            orderIndex = orderIndex,
            notes = null,
            customName = null,
            sets = sets
        )

    private fun set(
        num: Int,
        rowOrder: Int = num,
        reps: Int? = null,
        weight: Double? = null,
        rpe: Double? = null,
        rest: Int? = null
    ) = StrengthProgramSet(
        setNumber = num,
        rowOrder = rowOrder,
        reps = reps,
        weightKg = weight,
        rpe = rpe,
        restSec = rest,
        notes = null,
        weightSegments = null
    )

    private fun diff(proposed: List<StrengthProgramItem>, routine: List<StrengthProgramItem>) =
        buildStrengthRoutineOverwriteDiffLines(proposed, routine) { "Exercise" }

    @Test
    fun repsChangeDetected() {
        val proposed = listOf(item(1, 1, listOf(set(1, reps = 12))))
        val routine = listOf(item(1, 1, listOf(set(1, reps = 10))))
        val lines = diff(proposed, routine)
        assertTrue(lines.any { it.fieldTitle == "Reps" && it.oldValue == "10" && it.newValue == "12" })
    }

    @Test
    fun weightChangeDetected() {
        val proposed = listOf(item(1, 1, listOf(set(1, weight = 60.5))))
        val routine = listOf(item(1, 1, listOf(set(1, weight = 60.0))))
        val lines = diff(proposed, routine)
        assertTrue(lines.any { it.fieldTitle == "Weight" })
    }

    @Test
    fun rpeNilToValueDetected() {
        val proposed = listOf(item(1, 1, listOf(set(1, rpe = 8.0))))
        val routine = listOf(item(1, 1, listOf(set(1, rpe = null))))
        val lines = diff(proposed, routine)
        assertTrue(lines.any { it.fieldTitle == "RPE" && it.oldValue == "—" && it.newValue == "8.0" })
    }

    @Test
    fun rpeWithinEpsilonNotDetected() {
        val proposed = listOf(item(1, 1, listOf(set(1, rpe = 8.0005))))
        val routine = listOf(item(1, 1, listOf(set(1, rpe = 8.0))))
        val lines = diff(proposed, routine)
        assertFalse(lines.any { it.fieldTitle == "RPE" })
    }

    @Test
    fun restChangeDetected() {
        val proposed = listOf(item(1, 1, listOf(set(1, rest = 120))))
        val routine = listOf(item(1, 1, listOf(set(1, rest = 90))))
        val lines = diff(proposed, routine)
        assertTrue(lines.any { it.fieldTitle == "Rest" && it.oldValue == "90 s" && it.newValue == "120 s" })
    }

    @Test
    fun addedSetDetected() {
        val proposed = listOf(
            item(
                1,
                1,
                listOf(set(1, reps = 10), set(2, reps = 10), set(3, reps = 10), set(4, reps = 10))
            )
        )
        val routine = listOf(
            item(
                1,
                1,
                listOf(set(1, reps = 10), set(2, reps = 10), set(3, reps = 10))
            )
        )
        val lines = diff(proposed, routine)
        assertTrue(lines.any { it.fieldTitle == "Sets" || it.fieldTitle == "Added set" })
    }

    @Test
    fun exerciseStructureMatchIgnoresSetCount() {
        val threeSets = listOf(item(1, 1, listOf(set(1), set(2), set(3))))
        val fourSets = listOf(item(1, 1, listOf(set(1), set(2), set(3), set(4))))
        assertTrue(exerciseStructureMatch(threeSets, fourSets))
    }

    @Test
    fun exerciseStructureMatchRequiresSameExerciseIds() {
        val a = listOf(item(1, 1, listOf(set(1))))
        val b = listOf(item(2, 1, listOf(set(1))))
        assertFalse(exerciseStructureMatch(a, b))
    }

    @Test
    fun timesMultiplierShowsAddedSetNotRemoved() {
        val routine = listOf(item(1, 1, listOf(set(1, reps = 10))))
        val proposed = listOf(item(1, 1, listOf(set(2, reps = 10))))
        val lines = diff(proposed, routine)
        assertTrue(lines.any { it.fieldTitle == "Added set" && it.setNumber == 2 })
        assertFalse(lines.any { it.fieldTitle == "Removed set" })
        assertTrue(lines.any { it.fieldTitle == "Sets" && it.oldValue == "1" && it.newValue == "2" })
    }

    @Test
    fun unchangedMultiplierContentFingerprintMatches() {
        val routine = listOf(item(1, 1, listOf(set(1, reps = 10, weight = 50.0))))
        val unchanged = listOf(item(1, 1, listOf(set(1, reps = 10, weight = 50.0))))
        assertTrue(
            strengthRoutineContentFingerprintFromItems(routine) ==
                strengthRoutineContentFingerprintFromItems(unchanged)
        )
    }

    @Test
    fun timesMultiplierChangesContentFingerprint() {
        val routine = listOf(item(1, 1, listOf(set(1, reps = 10, weight = 50.0))))
        val doubled = listOf(item(1, 1, listOf(set(2, reps = 10, weight = 50.0))))
        assertTrue(
            strengthRoutineContentFingerprintFromItems(routine) !=
                strengthRoutineContentFingerprintFromItems(doubled)
        )
    }

    @Test
    fun collapseMultiplierExpandsToTwoSetsForDiff() {
        val routine = listOf(item(1, 1, listOf(set(1, reps = 10))))
        val collapsedPerformed = listOf(item(1, 1, listOf(set(2, reps = 10))))
        val lines = diff(collapsedPerformed, routine)
        assertTrue(lines.isNotEmpty())
        assertTrue(lines.any { it.fieldTitle == "Added set" || it.fieldTitle == "Sets" })
        assertFalse(lines.any { it.fieldTitle == "Removed set" })
    }

    @Test
    fun expandedSetsForCompareEmitsSequentialNumbers() {
        val expanded = expandedStrengthProgramSetsForCompare(listOf(set(2, reps = 8)))
        assertTrue(expanded.size == 2)
        assertTrue(expanded.map { it.setNumber } == listOf(1, 2))
        assertTrue(expanded.all { it.reps == 8 })
    }

    @Test
    fun structureMatchIgnoresOrderIndexValues() {
        val routine = listOf(item(10, 50, listOf(set(1, reps = 10))))
        val proposed = listOf(item(10, 1, listOf(set(1, reps = 12))))
        assertTrue(exerciseStructureMatch(proposed, routine))
        val lines = diff(proposed, routine)
        assertTrue(lines.any { it.fieldTitle == "Reps" })
    }

    @Test
    fun addSetRowWithNewPrescriptionShowsBlankOldValues() {
        val routine = listOf(item(1, 1, listOf(set(1, rowOrder = 1, reps = 1, weight = 1.0, rpe = 1.0, rest = 1))))
        val proposed = listOf(
            item(
                1,
                1,
                listOf(
                    set(2, rowOrder = 1, reps = 1, weight = 1.0, rpe = 1.0, rest = 1),
                    set(1, rowOrder = 2, reps = 2, weight = 2.0, rpe = 2.0, rest = 2)
                )
            )
        )
        val lines = diff(proposed, routine)
        assertFalse(lines.any { it.fieldTitle == "Reps" && it.setNumber == 1 && it.oldValue == "1" && it.newValue == "2" })
        assertTrue(lines.any { it.fieldTitle == "Reps" && it.oldValue == "—" && it.newValue == "2" })
        assertTrue(lines.any { it.fieldTitle == "Added set" })
    }
}
