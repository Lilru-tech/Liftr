package com.lilru.liftr.ui.add

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class StrengthSupersetDraftTest {
    @Test
    fun compactSupersetMetadata_clearsSingletonAndRenumbersPositions() {
        val groupA = "group-a"
        val groupB = "group-b"
        val drafts = listOf(
            StrengthExerciseDraft(
                exerciseId = 1L,
                supersetGroupId = groupA,
                supersetPosition = 4
            ),
            StrengthExerciseDraft(
                exerciseId = 2L,
                supersetGroupId = groupA,
                supersetPosition = 9
            ),
            StrengthExerciseDraft(
                exerciseId = 3L,
                supersetGroupId = groupB,
                supersetPosition = 1
            )
        )
        val compacted = compactSupersetMetadata(drafts)
        assertEquals(groupA, compacted[0].supersetGroupId)
        assertEquals(1, compacted[0].supersetPosition)
        assertEquals(groupA, compacted[1].supersetGroupId)
        assertEquals(2, compacted[1].supersetPosition)
        assertNull(compacted[2].supersetGroupId)
        assertNull(compacted[2].supersetPosition)
    }

    @Test
    fun strengthRoutineFingerprint_includesSupersetMetadata() {
        val group = "g1"
        val a = StrengthExerciseDraft(
            exerciseId = 10L,
            customName = "A",
            supersetGroupId = group,
            supersetPosition = 1,
            sets = listOf(StrengthSetDraft(repsText = "8"))
        )
        val b = StrengthExerciseDraft(
            exerciseId = 10L,
            customName = "A",
            sets = listOf(StrengthSetDraft(repsText = "8"))
        )
        val withSuperset = strengthRoutineContentFingerprintFromDrafts(listOf(a))
        val withoutSuperset = strengthRoutineContentFingerprintFromDrafts(listOf(b))
        assert(withSuperset != withoutSuperset)
    }
}
