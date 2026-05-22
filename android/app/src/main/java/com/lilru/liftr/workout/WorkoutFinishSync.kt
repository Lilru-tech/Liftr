package com.lilru.liftr.workout

import android.content.Context
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import com.lilru.liftr.data.LiftrSupabase
import com.lilru.liftr.ui.active.CompletedSetLine
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import java.io.IOException

@Serializable
data class PendingCompletedSetLine(
    val workoutExerciseId: Int,
    val configId: Int,
    val segmentsInRow: Int,
    val reps: Int? = null,
    val weightKg: Double? = null,
    val rpe: Double? = null,
    val restSec: Int? = null,
    val weightSegmentsJson: String? = null
)

@Serializable
data class PendingStrengthFinish(
    val workoutId: Int,
    val pausedSec: Int,
    val openPauseSec: Int,
    val completedSets: List<PendingCompletedSetLine>,
    val enqueuedAtEpochMs: Long
)

object WorkoutFinishSync {
    private const val PREFS = "liftr_workout_finish_sync"
    private const val KEY_PENDING = "pending.v1"
    private val json = Json { ignoreUnknownKeys = true }
    private val pendingListSerializer = ListSerializer(PendingStrengthFinish.serializer())

    fun enqueue(
        context: Context,
        workoutId: Int,
        pausedSec: Int,
        openPauseSec: Int,
        completedSetLines: List<CompletedSetLine>
    ) {
        val item = PendingStrengthFinish(
            workoutId = workoutId,
            pausedSec = pausedSec,
            openPauseSec = openPauseSec,
            completedSets = completedSetLines.map { it.toPending() },
            enqueuedAtEpochMs = System.currentTimeMillis()
        )
        val pending = loadPending(context).filter { it.workoutId != workoutId } + item
        savePending(context, pending)
        scheduleWorker(context)
    }

    fun scheduleWorker(context: Context) {
        val request = OneTimeWorkRequestBuilder<WorkoutFinishSyncWorker>().build()
        WorkManager.getInstance(context.applicationContext).enqueueUniqueWork(
            WorkoutFinishSyncWorker.UNIQUE_NAME,
            ExistingWorkPolicy.REPLACE,
            request
        )
    }

    suspend fun syncPending(context: Context): Boolean {
        val supabase = LiftrSupabase.client ?: return true
        val items = loadPending(context)
        if (items.isEmpty()) return true
        var allOk = true
        for (item in items) {
            val ok = runCatching {
                WorkoutStartSync.withRetries {
                    StrengthFinishPersistence.persist(
                        supabase = supabase,
                        workoutId = item.workoutId,
                        completedSetLines = item.completedSets.map { it.toCompleted() },
                        accumulatedPausedSeconds = item.pausedSec,
                        openPauseSec = item.openPauseSec
                    )
                }
            }.isSuccess
            if (ok) {
                removePending(context, item.workoutId)
            } else {
                allOk = false
            }
        }
        return allOk
    }

    fun isRetriable(t: Throwable): Boolean = WorkoutStartSync.isRetriable(t)

    fun userFacingMessage(t: Throwable): String = WorkoutStartSync.userFacingMessage(t)

    private fun CompletedSetLine.toPending() = PendingCompletedSetLine(
        workoutExerciseId = workoutExerciseId,
        configId = configId,
        segmentsInRow = segmentsInRow,
        reps = reps,
        weightKg = weightKg,
        rpe = rpe,
        restSec = restSec,
        weightSegmentsJson = weightSegments?.toString()
    )

    private fun PendingCompletedSetLine.toCompleted(): CompletedSetLine {
        val segments: JsonArray? = weightSegmentsJson?.let { raw ->
            runCatching { json.parseToJsonElement(raw) as? JsonArray }.getOrNull()
        }
        return CompletedSetLine(
            workoutExerciseId = workoutExerciseId,
            configId = configId,
            segmentsInRow = segmentsInRow,
            reps = reps,
            weightKg = weightKg,
            rpe = rpe,
            restSec = restSec,
            weightSegments = segments
        )
    }

    private fun loadPending(context: Context): List<PendingStrengthFinish> {
        val raw = context.applicationContext
            .getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(KEY_PENDING, null)
            ?: return emptyList()
        return runCatching {
            json.decodeFromString(pendingListSerializer, raw)
        }.getOrDefault(emptyList())
    }

    private fun savePending(context: Context, items: List<PendingStrengthFinish>) {
        context.applicationContext
            .getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_PENDING, json.encodeToString(pendingListSerializer, items))
            .apply()
    }

    fun removePending(context: Context, workoutId: Int) {
        val next = loadPending(context).filter { it.workoutId != workoutId }
        savePending(context, next)
    }
}
