package com.lilru.liftr.ui.pets

import android.content.Context
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.workDataOf
import java.util.concurrent.TimeUnit

object PetHatchLocalNotificationScheduler {
    fun schedule(context: Context, hatchAtMs: Long, petType: String) {
        val delayMs = hatchAtMs - System.currentTimeMillis()
        if (delayMs <= 1000L) return
        val request = OneTimeWorkRequestBuilder<PetHatchNotificationWorker>()
            .setInitialDelay(delayMs, TimeUnit.MILLISECONDS)
            .setInputData(workDataOf(PetHatchNotificationWorker.KEY_PET_TYPE to petType))
            .build()
        WorkManager.getInstance(context.applicationContext).enqueueUniqueWork(
            PetHatchNotificationWorker.UNIQUE_WORK,
            ExistingWorkPolicy.REPLACE,
            request
        )
    }

    fun cancel(context: Context) {
        WorkManager.getInstance(context.applicationContext)
            .cancelUniqueWork(PetHatchNotificationWorker.UNIQUE_WORK)
    }
}
