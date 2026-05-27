package com.lilru.liftr.workout

import android.content.Context
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters

class WorkoutFinishSyncWorker(
    appContext: Context,
    params: WorkerParameters
) : CoroutineWorker(appContext, params) {
    override suspend fun doWork(): Result {
        val ok = WorkoutFinishSync.syncPending(applicationContext)
        return if (ok) Result.success() else Result.retry()
    }

    companion object {
        const val UNIQUE_NAME = "liftr_workout_finish_sync"
    }
}
