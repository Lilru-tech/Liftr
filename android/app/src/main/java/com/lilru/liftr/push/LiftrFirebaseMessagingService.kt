package com.lilru.liftr.push

import android.app.PendingIntent
import android.content.Intent
import android.util.Log
import androidx.core.app.NotificationChannelCompat
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import com.lilru.liftr.MainActivity
import com.lilru.liftr.R
import com.lilru.liftr.data.LiftrSupabase
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

class LiftrFirebaseMessagingService : FirebaseMessagingService() {
    private val job = SupervisorJob()
    private val scope = CoroutineScope(Dispatchers.IO + job)

    override fun onNewToken(token: String) {
        val client = LiftrSupabase.client ?: return
        scope.launch {
            FcmTokenUploader.updateFcmToken(client, token)
        }
    }

    override fun onMessageReceived(message: RemoteMessage) {
        val data = message.data
        if (data.isNotEmpty()) {
            showDataNotification(
                title = message.notification?.title ?: data["title"] ?: getString(R.string.app_name),
                body = message.notification?.body ?: data["body"] ?: "",
                data = data
            )
        }
    }

    private fun showDataNotification(title: String, body: String, data: Map<String, String>) {
        val chId = "liftr_push"
        val manager = NotificationManagerCompat.from(this)
        manager.createNotificationChannel(
            NotificationChannelCompat.Builder(
                chId,
                NotificationManagerCompat.IMPORTANCE_DEFAULT
            ).setName("Liftr")
                .build()
        )
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            for ((k, v) in data) {
                putExtra("push_$k", v)
            }
            data["notification_id"]?.let { putExtra("push_notification_id", it) }
            data["type"]?.let { putExtra("push_type", it) }
        }
        val pi = PendingIntent.getActivity(
            this,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val n = NotificationCompat.Builder(this, chId)
            .setSmallIcon(R.drawable.ic_launcher)
            .setContentTitle(title)
            .setContentText(body)
            .setAutoCancel(true)
            .setContentIntent(pi)
            .build()
        try {
            manager.notify(System.currentTimeMillis().toInt() and 0xFFFF, n)
        } catch (e: SecurityException) {
            Log.w(TAG, "Notification not shown (permission?): ${e.message}")
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        job.cancel()
    }

    private companion object {
        const val TAG = "LiftrFCM"
    }
}
