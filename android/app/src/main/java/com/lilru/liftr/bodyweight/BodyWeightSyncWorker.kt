package com.lilru.liftr.bodyweight

import android.content.Context
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import com.lilru.liftr.data.LiftrSupabase
import com.lilru.liftr.prefs.LiftrPreferences
import io.github.jan.supabase.auth.auth
import java.util.concurrent.TimeUnit

class BodyWeightSyncWorker(
    appContext: Context,
    params: WorkerParameters
) : CoroutineWorker(appContext, params) {
    override suspend fun doWork(): Result {
        if (!LiftrPreferences.bodyWeightHealthSyncEnabled(applicationContext)) {
            return Result.success()
        }
        val supabase = LiftrSupabase.client ?: return Result.success()
        if (supabase.auth.currentUserOrNull() == null) {
            return Result.success()
        }
        return runCatching {
            HealthConnectBodyWeightSync(applicationContext, supabase).syncRecentSamples()
        }.fold(
            onSuccess = { Result.success() },
            onFailure = { Result.retry() }
        )
    }

    companion object {
        private const val UNIQUE_NAME = "liftr_body_weight_sync"

        fun schedule(context: Context) {
            val request = PeriodicWorkRequestBuilder<BodyWeightSyncWorker>(1, TimeUnit.DAYS).build()
            WorkManager.getInstance(context).enqueueUniquePeriodicWork(
                UNIQUE_NAME,
                ExistingPeriodicWorkPolicy.UPDATE,
                request
            )
        }

        fun cancel(context: Context) {
            WorkManager.getInstance(context).cancelUniqueWork(UNIQUE_NAME)
        }
    }
}
