package com.lilru.liftr.ui.active

import kotlin.math.max

data class StrengthDisplayGroup(
    val id: String,
    val supersetGroupId: String?,
    val exerciseIndices: List<Int>
) {
    val isSuperset: Boolean
        get() = supersetGroupId != null && exerciseIndices.size > 1
}

fun strengthDisplayGroups(exercises: List<ActiveStrengthExerciseLine>): List<StrengthDisplayGroup> {
    val groups = mutableListOf<StrengthDisplayGroup>()
    var idx = 0
    while (idx < exercises.size) {
        val ex = exercises[idx]
        val groupId = ex.supersetGroupId
        if (groupId == null) {
            groups += StrengthDisplayGroup(
                id = "exercise-${ex.workoutExerciseId}",
                supersetGroupId = null,
                exerciseIndices = listOf(idx)
            )
            idx += 1
            continue
        }
        val indices = mutableListOf(idx)
        var nextIdx = idx + 1
        while (nextIdx < exercises.size && exercises[nextIdx].supersetGroupId == groupId) {
            indices += nextIdx
            nextIdx += 1
        }
        if (indices.size > 1) {
            groups += StrengthDisplayGroup(
                id = "superset-$groupId-$idx",
                supersetGroupId = groupId,
                exerciseIndices = indices
            )
        } else {
            groups += StrengthDisplayGroup(
                id = "exercise-${ex.workoutExerciseId}",
                supersetGroupId = null,
                exerciseIndices = listOf(idx)
            )
        }
        idx = nextIdx
    }
    return groups
}

fun displayGroupForExerciseIndex(
    exerciseIndex: Int,
    exercises: List<ActiveStrengthExerciseLine>
): StrengthDisplayGroup? {
    return strengthDisplayGroups(exercises).firstOrNull { exerciseIndex in it.exerciseIndices }
}

fun displayGroupIndexForExerciseIndex(
    exerciseIndex: Int,
    exercises: List<ActiveStrengthExerciseLine>
): Int? {
    return strengthDisplayGroups(exercises).indexOfFirst { exerciseIndex in it.exerciseIndices }.takeIf { it >= 0 }
}

fun pagerAnchorExerciseIndex(exerciseIndex: Int, exercises: List<ActiveStrengthExerciseLine>): Int {
    return displayGroupForExerciseIndex(exerciseIndex, exercises)?.exerciseIndices?.firstOrNull() ?: exerciseIndex
}

fun supersetMembers(
    ex: ActiveStrengthExerciseLine,
    exercises: List<ActiveStrengthExerciseLine>
): List<ActiveStrengthExerciseLine> {
    val groupId = ex.supersetGroupId ?: return emptyList()
    return exercises
        .filter { it.supersetGroupId == groupId }
        .sortedWith(
            compareBy<ActiveStrengthExerciseLine> { it.supersetPosition ?: Int.MAX_VALUE }
                .thenBy { it.orderIndex }
                .thenBy { it.workoutExerciseId }
        )
}

fun shouldStartRestAfterCompletingSet(
    ex: ActiveStrengthExerciseLine,
    exercises: List<ActiveStrengthExerciseLine>,
    setIndex: Int
): Boolean {
    val members = supersetMembers(ex, exercises)
    if (members.size <= 1) return true
    val available = members.filter { it.sets.size > setIndex }
    val currentIdx = available.indexOfFirst { it.workoutExerciseId == ex.workoutExerciseId }
    if (currentIdx < 0) return true
    return currentIdx == available.lastIndex
}

fun nextSupersetMember(
    ex: ActiveStrengthExerciseLine,
    exercises: List<ActiveStrengthExerciseLine>,
    setIndex: Int,
    setProgress: Map<Int, Int>
): ActiveStrengthExerciseLine? {
    val members = supersetMembers(ex, exercises)
    if (members.size <= 1) return null
    val available = members.filter { it.sets.size > setIndex }
    val currentIdx = available.indexOfFirst { it.workoutExerciseId == ex.workoutExerciseId }
    if (currentIdx < 0) return null
    if (currentIdx < available.lastIndex) {
        return available[currentIdx + 1]
    }
    return available.firstOrNull {
        it.workoutExerciseId != ex.workoutExerciseId &&
            (setProgress[it.workoutExerciseId] ?: 0) < it.sets.size
    }
}

fun nextSupersetMemberExerciseIndex(
    ex: ActiveStrengthExerciseLine,
    exercises: List<ActiveStrengthExerciseLine>,
    setIndex: Int,
    setProgress: Map<Int, Int>
): Int? {
    val next = nextSupersetMember(ex, exercises, setIndex, setProgress) ?: return null
    return exercises.indexOfFirst { it.workoutExerciseId == next.workoutExerciseId }.takeIf { it >= 0 }
}

fun supersetGroupWorkSetIndex(
    members: List<ActiveStrengthExerciseLine>,
    setProgress: Map<Int, Int>
): Int {
    if (members.isEmpty()) return 0
    return members.minOf { (setProgress[it.workoutExerciseId] ?: 0).coerceAtMost(it.sets.size) }
}

fun supersetMemberFinishedRound(
    member: ActiveStrengthExerciseLine,
    roundIndex: Int,
    setProgress: Map<Int, Int>,
    completedSets: List<CompletedSetLine>
): Boolean {
    val progress = setProgress[member.workoutExerciseId] ?: 0
    return completedSets.size > roundIndex || progress > roundIndex
}

fun primarySetActionLabel(
    ex: ActiveStrengthExerciseLine,
    exercises: List<ActiveStrengthExerciseLine>,
    setIndex: Int,
    setProgress: Map<Int, Int>,
    currentSet: ActiveStrengthSetLine
): String {
    if (shouldStartRestAfterCompletingSet(ex, exercises, setIndex)) {
        val rest = currentSet.restSec?.takeIf { it > 0 }
        if (rest != null) return "Rest ${rest}s"
    }
    if (supersetMembers(ex, exercises).size > 1) {
        return "Set done"
    }
    val next = nextSupersetMember(ex, exercises, setIndex, setProgress)
    if (next != null) return "Next · ${next.displayName}"
    return "Set done"
}

fun supersetMaxRoundCount(
    members: List<ActiveStrengthExerciseLine>
): Int = members.maxOfOrNull { it.sets.size } ?: 0

fun supersetMembersContentHeightDp(memberCount: Int): Int {
    val rowHeight = 108
    val dividerHeight = 13
    val verticalPadding = 8
    val raw = memberCount * rowHeight + max(0, memberCount - 1) * dividerHeight + verticalPadding
    return minOf(raw, 336)
}

fun supersetRoundRestSec(
    members: List<ActiveStrengthExerciseLine>,
    setIndex: Int
): Int {
    val available = members.filter { it.sets.size > setIndex }
    val last = available.lastOrNull() ?: return 0
    return last.sets.getOrNull(setIndex)?.restSec?.takeIf { it > 0 } ?: 0
}

fun supersetRoundActionLabel(
    members: List<ActiveStrengthExerciseLine>,
    setIndex: Int
): String {
    val rest = supersetRoundRestSec(members, setIndex)
    if (rest > 0) return "Rest ${rest}s"
    return "Set done"
}
