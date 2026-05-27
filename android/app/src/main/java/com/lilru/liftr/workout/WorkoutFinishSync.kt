package com.lilru.liftr.workout

import android.content.Context
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import com.lilru.liftr.data.LiftrSupabase
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json
import java.io.IOException

@Serializable
data class PendingFinishSet(
    val setNumber: Int,
    val reps: Int? = null,
    val weightKg: Double? = null,
    val rpe: Double? = null,
    val restSec: Int? = null,
    val weightSegmentsJson: String? = null
)

@Serializable
data class PendingFinishExercise(
    val workoutExerciseId: Int,
    val sets: List<PendingFinishSet> = emptyList()
)

@Serializable
data class PendingFinishLinked(
    val workoutId: Int,
    val exercises: List<PendingFinishExercise> = emptyList()
)

@Serializable
data class PendingStrengthFinish(
    val workoutId: Int,
    val endedAtIso: String,
    val pausedSec: Int,
    val hostExercises: List<PendingFinishExercise>,
    val linked: List<PendingFinishLinked> = emptyList(),
    val enqueuedAtEpochMs: Long
)

object WorkoutFinishSync {
    private const val PREFS = "liftr_workout_finish_sync"
    private const val KEY_PENDING = "pending.v2"
    private val json = Json { ignoreUnknownKeys = true }
    private val pendingListSerializer = ListSerializer(PendingStrengthFinish.serializer())

    internal fun enqueue(
        context: Context,
        workoutId: Int,
        endedAtIso: String,
        pausedSec: Int,
        hostExercises: List<StrengthFinishExercisePayload>,
        linked: List<StrengthFinishLinkedPayload> = emptyList()
    ) {
        val item = PendingStrengthFinish(
            workoutId = workoutId,
            endedAtIso = endedAtIso,
            pausedSec = pausedSec,
            hostExercises = hostExercises.map { it.toPending() },
            linked = linked.map { link ->
                PendingFinishLinked(
                    workoutId = link.workoutId,
                    exercises = link.exercises.map { it.toPending() }
                )
            },
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
                    StrengthWorkoutSaveRpc.finishStrengthWorkoutV1(
                        supabase = supabase,
                        workoutId = item.workoutId,
                        endedAtIso = item.endedAtIso,
                        pausedSec = item.pausedSec,
                        hostExercises = item.hostExercises.map { it.toPayload() },
                        linked = item.linked.map { link ->
                            StrengthFinishLinkedPayload(
                                workoutId = link.workoutId,
                                exercises = link.exercises.map { it.toPayload() }
                            )
                        }
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

    private fun StrengthFinishExercisePayload.toPending() = PendingFinishExercise(
        workoutExerciseId = workoutExerciseId,
        sets = sets.map { set ->
            PendingFinishSet(
                setNumber = set.setNumber,
                reps = set.reps,
                weightKg = set.weightKg,
                rpe = set.rpe,
                restSec = set.restSec,
                weightSegmentsJson = set.weightSegments?.toString()
            )
        }
    )

    private fun PendingFinishExercise.toPayload(): StrengthFinishExercisePayload {
        val segmentsDecoder = json
        return StrengthFinishExercisePayload(
            workoutExerciseId = workoutExerciseId,
            sets = sets.map { set ->
                val segments = set.weightSegmentsJson?.let { raw ->
                    runCatching {
                        segmentsDecoder.parseToJsonElement(raw) as? kotlinx.serialization.json.JsonArray
                    }.getOrNull()
                }
                StrengthFinishSetPayload(
                    setNumber = set.setNumber,
                    reps = set.reps,
                    weightKg = set.weightKg,
                    rpe = set.rpe,
                    restSec = set.restSec,
                    weightSegments = segments
                )
            }
        )
    }

    private fun loadPending(context: Context): List<PendingStrengthFinish> {
        val raw = context.applicationContext
            .getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(KEY_PENDING, null)
            ?: return emptyList()
        return runCatching { json.decodeFromString(pendingListSerializer, raw) }.getOrDefault(emptyList())
    }

    private fun savePending(context: Context, items: List<PendingStrengthFinish>) {
        context.applicationContext
            .getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_PENDING, json.encodeToString(pendingListSerializer, items))
            .apply()
    }

    private fun removePending(context: Context, workoutId: Int) {
        savePending(context, loadPending(context).filter { it.workoutId != workoutId })
    }
}
