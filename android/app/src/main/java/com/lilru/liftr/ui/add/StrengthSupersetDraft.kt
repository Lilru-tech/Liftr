package com.lilru.liftr.ui.add

import com.lilru.liftr.data.BackendContracts
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.query.Columns
import io.github.jan.supabase.postgrest.query.Order
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObjectBuilder
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.longOrNull
import kotlinx.serialization.json.put
import java.util.UUID

fun compactSupersetMetadata(drafts: List<StrengthExerciseDraft>): List<StrengthExerciseDraft> {
    val groupCounts = drafts.mapNotNull { it.supersetGroupId }
        .groupingBy { it }
        .eachCount()
    val groupPositions = mutableMapOf<String, Int>()
    return drafts.map { draft ->
        val groupId = draft.supersetGroupId
        if (groupId == null || (groupCounts[groupId] ?: 0) <= 1) {
            draft.copy(supersetGroupId = null, supersetPosition = null)
        } else {
            val position = (groupPositions[groupId] ?: 0) + 1
            groupPositions[groupId] = position
            draft.copy(supersetPosition = position)
        }
    }
}

fun normalizedSupersetDrafts(drafts: List<StrengthExerciseDraft>): List<StrengthExerciseDraft> {
    val valid = drafts.filter { draft ->
        draft.exerciseId != null && draft.sets.any { draftSetToStrengthPayload(it) != null }
    }
    return compactSupersetMetadata(valid)
}

fun supersetGroupDisplayNumber(groupId: String, exercises: List<StrengthExerciseDraft>): Int {
    val groups = exercises.mapNotNull { it.supersetGroupId }.distinct()
    return groups.indexOf(groupId).let { if (it < 0) 1 else it + 1 }
}

fun JsonObjectBuilder.applyRoutineExerciseSupersetFields(draft: StrengthExerciseDraft) {
    val groupId = draft.supersetGroupId
    if (groupId != null) {
        put("superset_group_id", JsonPrimitive(groupId))
        draft.supersetPosition?.let { put("superset_position", it) }
    } else {
        put("superset_group_id", JsonNull)
        put("superset_position", JsonNull)
    }
}

suspend fun patchWorkoutSupersetsForCreatedWorkouts(
    supabase: SupabaseClient,
    workoutIds: List<Long>,
    programs: List<List<StrengthExerciseDraft>>
) {
    for ((idx, workoutId) in workoutIds.withIndex()) {
        if (idx >= programs.size) continue
        val program = normalizedSupersetDrafts(programs[idx])
        if (program.none { it.supersetGroupId != null }) continue
        val res = supabase.from(BackendContracts.Tables.WORKOUT_EXERCISES).select(
            columns = Columns.raw("id, order_index")
        ) {
            filter { eq("workout_id", workoutId) }
            order("order_index", Order.ASCENDING)
        }
        val rows = Json.parseToJsonElement(res.data).jsonArray.mapNotNull { el ->
            val o = el.jsonObject
            val id = o["id"]?.jsonPrimitive?.longOrNull ?: return@mapNotNull null
            val orderIndex = o["order_index"]?.jsonPrimitive?.content?.toIntOrNull() ?: return@mapNotNull null
            id to orderIndex
        }
        for ((rowId, orderIndex) in rows) {
            val draft = program.getOrNull(orderIndex - 1) ?: StrengthExerciseDraft()
            val patch = buildJsonObject {
                applyRoutineExerciseSupersetFields(draft)
            }
            supabase.from(BackendContracts.Tables.WORKOUT_EXERCISES).update(patch) {
                filter { eq("id", rowId) }
            }
        }
    }
}

fun newSupersetGroupId(): String = UUID.randomUUID().toString()

fun strengthRoutineSupersetColumnsUnavailable(error: Throwable): Boolean {
    val text = error.message?.lowercase().orEmpty()
    return text.contains("superset_group_id") || text.contains("superset_position")
}

const val STRENGTH_ROUTINE_DETAIL_SELECT =
    "id,name,strength_routine_exercises(exercise_id,order_index,superset_group_id,superset_position,notes,custom_name,strength_routine_sets(set_number,reps,weight_kg,rpe,rest_sec,notes,weight_segments))"

const val STRENGTH_ROUTINE_DETAIL_SELECT_LEGACY =
    "id,name,strength_routine_exercises(exercise_id,order_index,notes,custom_name,strength_routine_sets(set_number,reps,weight_kg,rpe,rest_sec,notes,weight_segments))"

const val STRENGTH_ROUTINE_FULL_SELECT =
    "id,name,updated_at,strength_routine_exercises(exercise_id,order_index,superset_group_id,superset_position,notes,custom_name,strength_routine_sets(set_number,reps,weight_kg,rpe,rest_sec,notes,weight_segments))"

const val STRENGTH_ROUTINE_FULL_SELECT_LEGACY =
    "id,name,updated_at,strength_routine_exercises(exercise_id,order_index,notes,custom_name,strength_routine_sets(set_number,reps,weight_kg,rpe,rest_sec,notes,weight_segments))"

fun canStartSupersetAt(list: List<StrengthExerciseDraft>, index: Int): Boolean {
    if (list.size < 2) return false
    if (index < 0 || index >= list.lastIndex) return false
    val current = list[index]
    val next = list[index + 1]
    if (current.supersetGroupId != null && current.supersetGroupId == next.supersetGroupId) return false
    return true
}

fun startSupersetAt(list: List<StrengthExerciseDraft>, index: Int): List<StrengthExerciseDraft> {
    if (!canStartSupersetAt(list, index)) return list
    val mutable = list.toMutableList()
    val groupId = mutable[index].supersetGroupId
        ?: mutable[index + 1].supersetGroupId
        ?: newSupersetGroupId()
    mutable[index] = mutable[index].copy(supersetGroupId = groupId)
    mutable[index + 1] = mutable[index + 1].copy(supersetGroupId = groupId)
    return compactSupersetMetadata(mutable)
}

fun canAddNextToSuperset(list: List<StrengthExerciseDraft>, groupId: String): Boolean {
    val indices = list.indices.filter { list[it].supersetGroupId == groupId }
    val lastInGroup = indices.maxOrNull() ?: return false
    val nextIndex = lastInGroup + 1
    if (nextIndex >= list.size) return false
    return list[nextIndex].supersetGroupId != groupId
}

fun addNextExerciseToSuperset(list: List<StrengthExerciseDraft>, groupId: String): List<StrengthExerciseDraft> {
    val indices = list.indices.filter { list[it].supersetGroupId == groupId }
    val lastInGroup = indices.maxOrNull() ?: return list
    val nextIndex = lastInGroup + 1
    if (nextIndex >= list.size || list[nextIndex].supersetGroupId == groupId) return list
    val mutable = list.toMutableList()
    mutable[nextIndex] = mutable[nextIndex].copy(supersetGroupId = groupId)
    return compactSupersetMetadata(mutable)
}

fun removeExerciseFromSuperset(list: List<StrengthExerciseDraft>, index: Int): List<StrengthExerciseDraft> {
    if (index !in list.indices) return list
    val mutable = list.toMutableList()
    mutable[index] = mutable[index].copy(supersetGroupId = null, supersetPosition = null)
    return compactSupersetMetadata(mutable)
}

fun swapExercisesWithSupersetCompact(list: List<StrengthExerciseDraft>, from: Int, to: Int): List<StrengthExerciseDraft> {
    if (from !in list.indices || to !in list.indices) return list
    val mutable = list.toMutableList()
    val item = mutable.removeAt(from)
    mutable.add(to, item)
    return compactSupersetMetadata(mutable)
}
