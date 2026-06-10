package com.lilru.liftr.ui.pets

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationChannelCompat
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import com.lilru.liftr.MainActivity
import com.lilru.liftr.R

class PetHatchNotificationWorker(
    context: Context,
    params: WorkerParameters
) : CoroutineWorker(context, params) {

    override suspend fun doWork(): Result {
        val petType = inputData.getString(KEY_PET_TYPE) ?: "pet"
        val displayType = petType.replace('_', ' ')
        val chId = CHANNEL_ID
        val manager = NotificationManagerCompat.from(applicationContext)
        manager.createNotificationChannel(
            NotificationChannelCompat.Builder(chId, NotificationManagerCompat.IMPORTANCE_DEFAULT)
                .setName("Liftr")
                .build()
        )
        val intent = Intent(applicationContext, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("push_type", "pet_hatched")
            putExtra("push_pet_type", petType)
        }
        val pi = PendingIntent.getActivity(
            applicationContext,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val notification = NotificationCompat.Builder(applicationContext, chId)
            .setSmallIcon(R.drawable.ic_stat_liftr)
            .setContentTitle("Your egg is ready to hatch!")
            .setContentText("Your $displayType egg is ready to hatch!")
            .setAutoCancel(true)
            .setContentIntent(pi)
            .build()
        try {
            manager.notify(NOTIFICATION_ID, notification)
        } catch (_: SecurityException) {
        }
        return Result.success()
    }

    companion object {
        const val UNIQUE_WORK = "liftr_pet_hatch_alarm"
        const val KEY_PET_TYPE = "pet_type"
        private const val CHANNEL_ID = "liftr_push"
        private const val NOTIFICATION_ID = 9101
    }
}
