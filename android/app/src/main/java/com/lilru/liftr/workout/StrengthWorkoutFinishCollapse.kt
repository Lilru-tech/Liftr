package com.lilru.liftr.workout

import com.lilru.liftr.ui.active.CompletedSetLine
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

internal data class StrengthFinishSetPayload(
    val setNumber: Int,
    val reps: Int?,
    val weightKg: Double?,
    val rpe: Double?,
    val restSec: Int?,
    val weightSegments: JsonArray?
)

internal data class StrengthFinishExercisePayload(
    val workoutExerciseId: Int,
    val sets: List<StrengthFinishSetPayload>
)

internal object StrengthWorkoutFinishCollapse {
    private data class CollapsedPersistRow(
        val count: Int,
        val reps: Int?,
        val weightKg: Double?,
        val rpe: Double?,
        val restSec: Int?,
        val weightSegments: JsonArray? = null
    )

    private data class LegacyLineKey(val reps: Int?, val weightKg: Double?, val rpe: Double?, val restSec: Int?)
    private data class SegmentLineKey(
        val reps: Int?,
        val weightKg: Double?,
        val rpe: Double?,
        val restSec: Int?,
        val weightSegmentsRaw: String?
    )

    fun buildExercisePayloads(
        workoutExerciseIds: List<Int>,
        completedByExerciseId: Map<Int, List<CompletedSetLine>>
    ): List<StrengthFinishExercisePayload> {
        return workoutExerciseIds.map { weId ->
            val lines = completedByExerciseId[weId].orEmpty()
            val sets = chunkCompletedLines(lines)
                .flatMap { chunkToPersistRows(it) }
                .map { row ->
                    StrengthFinishSetPayload(
                        setNumber = row.count,
                        reps = row.reps,
                        weightKg = row.weightKg,
                        rpe = row.rpe,
                        restSec = row.restSec,
                        weightSegments = row.weightSegments
                    )
                }
            StrengthFinishExercisePayload(workoutExerciseId = weId, sets = sets)
        }
    }

    fun exerciseToJsonObject(exercise: StrengthFinishExercisePayload) = buildJsonObject {
        put("workout_exercise_id", exercise.workoutExerciseId)
        put(
            "sets",
            buildJsonArray {
                exercise.sets.forEach { set ->
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

    fun exercisesToJsonArray(exercises: List<StrengthFinishExercisePayload>) = buildJsonArray {
        exercises.forEach { add(exerciseToJsonObject(it)) }
    }

    private fun chunkCompletedLines(lines: List<CompletedSetLine>): List<List<CompletedSetLine>> {
        if (lines.isEmpty()) return emptyList()
        val out = mutableListOf<MutableList<CompletedSetLine>>()
        var cur = mutableListOf(lines.first())
        for (i in 1 until lines.size) {
            val line = lines[i]
            if (line.configId == cur.first().configId) {
                cur += line
            } else {
                out += cur
                cur = mutableListOf(line)
            }
        }
        out += cur
        return out
    }

    private fun collapseLegacyChunk(chunk: List<CompletedSetLine>): List<CollapsedPersistRow> {
        if (chunk.isEmpty()) return emptyList()
        val collapsed = mutableListOf<CollapsedPersistRow>()
        var currentKey: LegacyLineKey? = null
        var count = 0
        chunk.forEach { line ->
            val key = LegacyLineKey(line.reps, line.weightKg, line.rpe, line.restSec)
            if (currentKey != null && currentKey == key) {
                count += 1
            } else {
                if (currentKey != null) {
                    collapsed += CollapsedPersistRow(count, currentKey!!.reps, currentKey!!.weightKg, currentKey!!.rpe, currentKey!!.restSec, null)
                }
                currentKey = key
                count = 1
            }
        }
        if (currentKey != null) {
            collapsed += CollapsedPersistRow(count, currentKey!!.reps, currentKey!!.weightKg, currentKey!!.rpe, currentKey!!.restSec, null)
        }
        return collapsed
    }

    private fun collapseSegmentChunk(chunk: List<CompletedSetLine>): List<CollapsedPersistRow> {
        if (chunk.isEmpty()) return emptyList()
        val collapsed = mutableListOf<CollapsedPersistRow>()
        var currentKey: SegmentLineKey? = null
        var currentSegs: JsonArray? = null
        var count = 0
        fun flush() {
            val k = currentKey ?: return
            collapsed += CollapsedPersistRow(
                count = count,
                reps = k.reps,
                weightKg = k.weightKg,
                rpe = k.rpe,
                restSec = k.restSec,
                weightSegments = currentSegs
            )
        }
        chunk.forEach { line ->
            val key = SegmentLineKey(
                line.reps,
                line.weightKg,
                line.rpe,
                line.restSec,
                line.weightSegments?.toString()
            )
            if (currentKey != null && currentKey == key) {
                count += 1
            } else {
                if (currentKey != null) flush()
                currentKey = key
                currentSegs = line.weightSegments
                count = 1
            }
        }
        if (currentKey != null) flush()
        return collapsed
    }

    private fun chunkToPersistRows(chunk: List<CompletedSetLine>): List<CollapsedPersistRow> {
        if (chunk.isEmpty()) return emptyList()
        return if (chunk.first().segmentsInRow <= 1) {
            collapseLegacyChunk(chunk)
        } else {
            collapseSegmentChunk(chunk)
        }
    }
}
