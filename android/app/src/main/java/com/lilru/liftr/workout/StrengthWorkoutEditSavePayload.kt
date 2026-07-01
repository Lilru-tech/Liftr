package com.lilru.liftr.workout

import com.lilru.liftr.ui.add.StrengthExerciseDraft
import com.lilru.liftr.ui.add.draftSetToStrengthPayload
import com.lilru.liftr.ui.add.weightSegmentsToJsonArray
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

internal data class StrengthEditExercisePayload(
    val workoutExerciseId: Int,
    val exerciseId: Long,
    val orderIndex: Int,
    val notes: String?,
    val customName: String?,
    val sets: List<StrengthFinishSetPayload>
)

internal object StrengthWorkoutEditSavePayload {
    fun buildFromDrafts(exercises: List<StrengthExerciseDraft>): List<StrengthEditExercisePayload> {
        return exercises.mapIndexed { index, ex ->
            val sets = ex.sets.mapNotNull { draftSetToStrengthPayload(it) }
                .map { p ->
                    StrengthFinishSetPayload(
                        setNumber = p.setNumber.coerceIn(1, 99),
                        reps = p.reps,
                        weightKg = p.weightKg,
                        rpe = p.rpe,
                        restSec = p.restSec,
                        weightSegments = p.weightSegments
                            ?.takeIf { it.size >= 2 }
                            ?.let { weightSegmentsToJsonArray(it) }
                    )
                }
            StrengthEditExercisePayload(
                workoutExerciseId = ex.workoutExerciseId!!,
                exerciseId = ex.exerciseId!!,
                orderIndex = index + 1,
                notes = ex.notes.trim().takeIf { it.isNotEmpty() },
                customName = ex.customName.trim().takeIf { it.isNotEmpty() },
                sets = sets
            )
        }
    }

    fun exercisesToJsonArray(exercises: List<StrengthEditExercisePayload>) = buildJsonArray {
        exercises.forEach { ex ->
            add(
                buildJsonObject {
                    put("workout_exercise_id", ex.workoutExerciseId)
                    put("exercise_id", ex.exerciseId)
                    put("order_index", ex.orderIndex)
                    if (ex.notes != null) put("notes", ex.notes) else put("notes", JsonNull)
                    if (ex.customName != null) put("custom_name", ex.customName) else put("custom_name", JsonNull)
                    put(
                        "sets",
                        buildJsonArray {
                            ex.sets.forEach { set ->
                                add(
                                    buildJsonObject {
                                        put("set_number", set.setNumber)
                                        set.reps?.let { put("reps", it) }
                                        set.weightKg?.let { put("weight_kg", it) }
                                        set.rpe?.let { put("rpe", it) }
                                        set.restSec?.let { put("rest_sec", it) }
                                        set.weightSegments?.let { put("weight_segments", it) }
                                    }
                                )
                            }
                        }
                    )
                }
            )
        }
    }
}
