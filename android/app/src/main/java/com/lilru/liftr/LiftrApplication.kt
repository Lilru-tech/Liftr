package com.lilru.liftr

import android.app.Application
import android.util.Log
import com.google.firebase.FirebaseApp
import com.google.firebase.messaging.FirebaseMessaging
import com.lilru.liftr.billing.PlayBillingManager
import com.lilru.liftr.data.LiftrSupabase
import com.lilru.liftr.push.FcmTokenUploader
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

class LiftrApplication : Application() {
    private val appScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    lateinit var playBilling: PlayBillingManager
        private set

    override fun onCreate() {
        super.onCreate()
        LiftrSupabase.init(this)
        playBilling = PlayBillingManager(this)
        playBilling.start()
        // MobileAds se inicializa tras UMP en MainActivity
        runCatching {
            FirebaseApp.initializeApp(this)
            FirebaseMessaging.getInstance().token.addOnCompleteListener { task ->
                if (!task.isSuccessful) {
                    Log.w(TAG, "FCM token: ${task.exception?.message}")
                    return@addOnCompleteListener
                }
                val token = task.result ?: return@addOnCompleteListener
                val client = LiftrSupabase.client ?: return@addOnCompleteListener
                appScope.launch {
                    FcmTokenUploader.updateFcmToken(client, token)
                }
            }
        }.onFailure { e ->
            Log.w(TAG, "Firebase not available: ${e.message}")
        }
    }

    private companion object {
        const val TAG = "LiftrApp"
    }
}
