package com.lilru.liftr.workout

import android.content.Context
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import com.lilru.liftr.data.LiftrSupabase

class WorkoutStartSyncWorker(
    appContext: Context,
    params: WorkerParameters
) : CoroutineWorker(appContext, params) {
    override suspend fun doWork(): Result {
        val supabase = LiftrSupabase.client ?: return Result.success()
        val ok = WorkoutStartSync.syncPending(applicationContext, supabase)
        return if (ok) Result.success() else Result.retry()
    }

    companion object {
        const val UNIQUE_NAME = "liftr_workout_start_sync"
    }
}
