package com.lilru.liftr.workout

import com.lilru.liftr.data.BackendContracts
import com.lilru.liftr.ui.active.CompletedSetLine
import com.lilru.liftr.ui.active.WorkoutNotesStateRow
import com.lilru.liftr.ui.active.mergeWorkoutNotesForFinish
import com.lilru.liftr.ui.active.workoutFinishUpdateJson
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.query.Columns
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.time.Instant

private val json = Json { ignoreUnknownKeys = true }

private inline fun <reified T> decodeFlexibleList(raw: String): List<T> {
    val root = json.parseToJsonElement(raw)
    return when (root) {
        is JsonArray -> root.map { json.decodeFromString<T>(it.toString()) }
        is JsonObject -> listOf(json.decodeFromString<T>(root.toString()))
        else -> emptyList()
    }
}

internal object StrengthFinishPersistence {
    suspend fun persist(
        supabase: SupabaseClient,
        workoutId: Int,
        completedSetLines: List<CompletedSetLine>,
        accumulatedPausedSeconds: Int,
        openPauseSec: Int
    ) {
        val pausedSec = (accumulatedPausedSeconds + openPauseSec).coerceAtLeast(0)
        if (completedSetLines.isNotEmpty()) {
            val byWe = completedSetLines.groupBy { it.workoutExerciseId }
            for ((weId, lines) in byWe) {
                supabase.from(BackendContracts.Tables.EXERCISE_SETS).delete {
                    filter { eq("workout_exercise_id", weId) }
                }
                val persistRows = chunkCompletedLines(lines).flatMap { chunkToPersistRows(it) }
                persistRows.forEach { block ->
                    val payload = buildJsonObject {
                        put("workout_exercise_id", weId)
                        put("set_number", block.count)
                        if (block.reps != null) put("reps", block.reps)
                        if (block.weightKg != null) put("weight_kg", block.weightKg)
                        if (block.rpe != null) put("rpe", block.rpe)
                        if (block.restSec != null) put("rest_sec", block.restSec)
                        block.weightSegments?.let { put("weight_segments", it) }
                    }
                    supabase.from(BackendContracts.Tables.EXERCISE_SETS).insert(payload) { }
                }
            }
        }
        val nRes = supabase
            .from(BackendContracts.Tables.WORKOUTS)
            .select(columns = Columns.raw("notes, state, started_at")) {
                filter { eq("id", workoutId) }
                limit(1)
            }
        val wRow = decodeFlexibleList<WorkoutNotesStateRow>(nRes.data).firstOrNull()
        var effectiveEnded = Instant.now()
        wRow?.started_at?.let { raw ->
            runCatching { Instant.parse(raw) }.getOrNull()?.let { st ->
                if (effectiveEnded.isBefore(st)) effectiveEnded = st
            }
        }
        val ended = effectiveEnded.toString()
        val mergedNotes = mergeWorkoutNotesForFinish(wRow?.notes, null)
        supabase.from(BackendContracts.Tables.WORKOUTS).update(
            workoutFinishUpdateJson(ended, mergedNotes, wRow?.state, pausedSec)
        ) {
            filter { eq("id", workoutId) }
        }
    }

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
