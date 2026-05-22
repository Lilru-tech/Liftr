package com.lilru.liftr.workout

import android.content.Context
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import com.lilru.liftr.data.BackendContracts
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.postgrest
import kotlinx.coroutines.delay
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.io.IOException
import java.time.Instant

@Serializable
private data class PendingStart(
    val workoutId: Int,
    val startedAtIso: String,
    val enqueuedAtEpochMs: Long
)

object WorkoutStartSync {
    private const val PREFS = "liftr_workout_start_sync"
    private const val KEY_PENDING = "pending.v1"
    private val backoffMs = longArrayOf(500L, 2000L, 5000L)

    enum class Status {
        IDLE,
        PENDING,
        SYNCING,
        SYNCED,
        WILL_RETRY
    }

    private val statusByWorkoutId = mutableMapOf<Int, Status>()
    private val listeners = mutableSetOf<(Int, Status) -> Unit>()

    fun addListener(listener: (Int, Status) -> Unit) {
        listeners.add(listener)
    }

    fun removeListener(listener: (Int, Status) -> Unit) {
        listeners.remove(listener)
    }

    fun status(workoutId: Int): Status = statusByWorkoutId[workoutId] ?: Status.IDLE

    fun isPending(workoutId: Int): Boolean {
        val s = status(workoutId)
        return s == Status.PENDING || s == Status.SYNCING || s == Status.WILL_RETRY
    }

    fun enqueueStart(context: Context, workoutId: Int, startedAtIso: String? = null) {
        val iso = startedAtIso ?: Instant.now().toString()
        val pending = loadPending(context).filter { it.workoutId != workoutId } +
            PendingStart(workoutId, iso, System.currentTimeMillis())
        savePending(context, pending)
        setStatus(workoutId, Status.PENDING)
        scheduleWorker(context)
    }

    fun scheduleWorker(context: Context) {
        val request = OneTimeWorkRequestBuilder<WorkoutStartSyncWorker>().build()
        WorkManager.getInstance(context.applicationContext).enqueueUniqueWork(
            WorkoutStartSyncWorker.UNIQUE_NAME,
            ExistingWorkPolicy.REPLACE,
            request
        )
        WorkoutFinishSync.scheduleWorker(context)
    }

    suspend fun syncPending(context: Context, supabase: SupabaseClient): Boolean {
        val finishOk = WorkoutFinishSync.syncPending(context)
        val items = loadPending(context)
        if (items.isEmpty()) return true
        var allOk = true
        for (item in items) {
            setStatus(item.workoutId, Status.SYNCING)
            val ok = performStartWithRetries(context, supabase, item.workoutId, item.startedAtIso)
            if (ok) {
                removePending(context, item.workoutId)
                setStatus(item.workoutId, Status.SYNCED)
            } else {
                allOk = false
                setStatus(item.workoutId, Status.WILL_RETRY)
            }
        }
        return allOk && finishOk
    }

    suspend fun <T> withRetries(
        maxAttempts: Int = 3,
        block: suspend () -> T
    ): T {
        var last: Throwable? = null
        repeat(maxAttempts.coerceAtLeast(1)) { attempt ->
            try {
                return block()
            } catch (t: Throwable) {
                last = t
                if (attempt >= maxAttempts - 1 || !isRetriable(t)) throw t
                delay(backoffMs[attempt.coerceAtMost(backoffMs.size - 1)])
            }
        }
        throw last ?: IllegalStateException("WorkoutStartSync retry failed")
    }

    fun isRetriable(t: Throwable): Boolean {
        if (t is IOException) return true
        val msg = t.message?.lowercase().orEmpty()
        return msg.contains("network") ||
            msg.contains("connection") ||
            msg.contains("timeout") ||
            msg.contains("unable to resolve")
    }

    fun userFacingMessage(t: Throwable): String {
        return if (isRetriable(t)) {
            "Connection issue. You can start offline; we'll sync when you're back online."
        } else {
            t.message?.take(220) ?: t::class.java.simpleName
        }
    }

    private suspend fun performStartWithRetries(
        context: Context,
        supabase: SupabaseClient,
        workoutId: Int,
        startedAtIso: String
    ): Boolean {
        return try {
            withRetries {
                executeStartRpc(supabase, workoutId, startedAtIso)
            }
            true
        } catch (t: Throwable) {
            if (!isRetriable(t)) {
                removePending(context, workoutId)
            }
            false
        }
    }

    private suspend fun executeStartRpc(
        supabase: SupabaseClient,
        workoutId: Int,
        startedAtIso: String
    ) {
        val params = buildJsonObject {
            put("p_workout_id", JsonPrimitive(workoutId))
            put("p_started_at", JsonPrimitive(startedAtIso))
        }
        val res = supabase.postgrest.rpc(BackendContracts.Rpc.START_WORKOUT_V1, params) { }
        val body = res.data.trim()
        if (body.isEmpty() || body == "[]" || body == "null") {
            error("No row was updated (RLS/policy or invalid workout id).")
        }
    }

    private fun loadPending(context: Context): List<PendingStart> {
        val raw = context.applicationContext
            .getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(KEY_PENDING, null)
            ?: return emptyList()
        return runCatching {
            kotlinx.serialization.json.Json.decodeFromString<List<PendingStart>>(raw)
        }.getOrDefault(emptyList())
    }

    private fun savePending(context: Context, items: List<PendingStart>) {
        val encoded = kotlinx.serialization.json.Json.encodeToString(
            kotlinx.serialization.serializer<List<PendingStart>>(),
            items
        )
        context.applicationContext
            .getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_PENDING, encoded)
            .apply()
    }

    fun removePending(context: Context, workoutId: Int) {
        val next = loadPending(context).filter { it.workoutId != workoutId }
        savePending(context, next)
    }

    private fun setStatus(workoutId: Int, status: Status) {
        statusByWorkoutId[workoutId] = status
        listeners.forEach { it(workoutId, status) }
    }
}
