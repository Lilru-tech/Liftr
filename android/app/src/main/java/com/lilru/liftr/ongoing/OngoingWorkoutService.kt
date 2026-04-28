package com.lilru.liftr.ongoing

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import com.google.android.gms.location.LocationCallback
import com.google.android.gms.location.LocationRequest
import com.google.android.gms.location.LocationResult
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import com.lilru.liftr.MainActivity
import com.lilru.liftr.R
import com.lilru.liftr.navigation.OpenWorkoutIntentStore

/**
 * FGS dinámico: usa tipos solo cuando hay permisos runtime disponibles, para evitar crashes en
 * Android 14/15 al iniciar entrenos sin ACTIVITY_RECOGNITION/BODY_SENSORS concedidos.
 */
class OngoingWorkoutService : Service() {

    private var locationCallback: LocationCallback? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private var notifRefreshRunnable: Runnable? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val sub = intent?.getStringExtra(EXTRA_SUBTITLE)
            ?: getString(R.string.ongoing_workout_subtitle_default)
        val track = intent?.getBooleanExtra(EXTRA_TRACK_LOCATION, false) == true
        val wid = intent?.getIntExtra(EXTRA_WORKOUT_ID, -1) ?: -1
        val gpsProfile = intent?.getStringExtra(EXTRA_GPS_PROFILE) ?: "balanced"
        val fgType = resolveForegroundType(track)
        if (fgType == null) {
            Log.w(TAG, "FGS skipped: no allowed foreground type with current permissions.")
            stopSelf(startId)
            return START_NOT_STICKY
        }
        if (wid > 0) {
            OngoingWorkoutWidgetPrefs.setActive(this, wid, sub, statsLine = "")
        }
        stopLocationUpdatesInternal()
        createChannelIfNeeded()
        val notif = buildNotificationFromPrefs(wid, sub)
        startForegroundWithTypes(fgType, notif)
        startNotificationRefreshLoop()
        if (track && hasFineLocation()) {
            startFusedLocation(gpsProfile)
        } else {
            if (track) {
                Log.w(TAG, "Track location requested but no ACCESS_FINE_LOCATION; notification only")
            }
        }
        return START_STICKY
    }

    private fun hasFineLocation(): Boolean {
        return ActivityCompat.checkSelfPermission(
            this,
            android.Manifest.permission.ACCESS_FINE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED
    }

    private fun hasAnyHealthRuntimePermission(): Boolean {
        val healthPerms = listOfNotNull(
            android.Manifest.permission.ACTIVITY_RECOGNITION,
            android.Manifest.permission.BODY_SENSORS,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                android.Manifest.permission.HIGH_SAMPLING_RATE_SENSORS
            } else {
                null
            }
        )
        return healthPerms.any { perm ->
            ActivityCompat.checkSelfPermission(this, perm) == PackageManager.PERMISSION_GRANTED
        }
    }

    private fun startForegroundWithTypes(type: Int, notif: Notification) {
        if (Build.VERSION.SDK_INT < 34) {
            @Suppress("DEPRECATION")
            startForeground(NOTIFICATION_ID, notif)
            return
        }
        ServiceCompat.startForeground(
            this,
            NOTIFICATION_ID,
            notif,
            type
        )
    }

    private fun resolveForegroundType(needsLocation: Boolean): Int? {
        if (Build.VERSION.SDK_INT < 34) return ServiceInfo.FOREGROUND_SERVICE_TYPE_MANIFEST
        val hasLocationPermission = hasFineLocation()
        val hasHealthPermission = hasAnyHealthRuntimePermission()
        return when {
            needsLocation && hasLocationPermission && hasHealthPermission ->
                ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION or
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_HEALTH
            needsLocation && hasLocationPermission ->
                ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION
            hasHealthPermission ->
                ServiceInfo.FOREGROUND_SERVICE_TYPE_HEALTH
            else -> null
        }
    }

    private fun startFusedLocation(gpsProfile: String) {
        val client = LocationServices.getFusedLocationProviderClient(this)
        val req = if (gpsProfile == "batterySaving") {
            LocationRequest.Builder(Priority.PRIORITY_BALANCED_POWER_ACCURACY, 12_000L)
                .setMinUpdateIntervalMillis(10_000L)
                .setMaxUpdateDelayMillis(20_000L)
                .build()
        } else {
            LocationRequest.Builder(Priority.PRIORITY_HIGH_ACCURACY, 5000L)
                .setMinUpdateIntervalMillis(4000L)
                .setMaxUpdateDelayMillis(10_000L)
                .build()
        }
        val cb = object : LocationCallback() {
            override fun onLocationResult(result: LocationResult) {
                val loc = result.lastLocation ?: return
                mainHandler.post {
                    CardioLocationBridge.push(loc.latitude, loc.longitude)
                }
            }
        }
        locationCallback = cb
        try {
            if (hasFineLocation()) {
                client.requestLocationUpdates(req, cb, Looper.getMainLooper())
            }
        } catch (e: SecurityException) {
            Log.w(TAG, "Fused: ${e.message}")
        }
    }

    private fun stopLocationUpdatesInternal() {
        locationCallback?.let { cb ->
            if (hasFineLocation()) {
                runCatching {
                    LocationServices.getFusedLocationProviderClient(this)
                        .removeLocationUpdates(cb)
                }
            }
        }
        locationCallback = null
    }

    override fun onDestroy() {
        notifRefreshRunnable?.let { mainHandler.removeCallbacks(it) }
        notifRefreshRunnable = null
        stopLocationUpdatesInternal()
        OngoingWorkoutWidgetPrefs.clear(this)
        super.onDestroy()
    }

    private fun startNotificationRefreshLoop() {
        notifRefreshRunnable?.let { mainHandler.removeCallbacks(it) }
        val r = object : Runnable {
            override fun run() {
                val snap = OngoingWorkoutWidgetPrefs.read(this@OngoingWorkoutService)
                val w = snap?.workoutId?.takeIf { it > 0 } ?: -1
                if (w > 0) {
                    val n = buildNotificationFromPrefs(
                        w,
                        snap?.subtitle.orEmpty()
                    )
                    NotificationManagerCompat.from(this@OngoingWorkoutService)
                        .notify(NOTIFICATION_ID, n)
                }
                notifRefreshRunnable = this
                mainHandler.postDelayed(this, 2500L)
            }
        }
        notifRefreshRunnable = r
        mainHandler.postDelayed(r, 2500L)
    }

    private fun buildNotificationFromPrefs(
        workoutId: Int,
        intentSubtitleFallback: String
    ): Notification {
        val open = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            if (workoutId > 0) {
                putExtra(OpenWorkoutIntentStore.EXTRA_OPEN_WORKOUT_ID, workoutId)
            }
        }
        val pflags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        val pi = PendingIntent.getActivity(this, 0, open, pflags)
        val snap = OngoingWorkoutWidgetPrefs.read(this)
        val kind = (snap?.subtitle?.takeIf { it.isNotBlank() } ?: intentSubtitleFallback).trim()
        val stats = snap?.statsLine?.trim().orEmpty()
        val line = when {
            stats.isNotEmpty() && kind.isNotEmpty() -> "$kind — $stats"
            stats.isNotEmpty() -> stats
            kind.isNotEmpty() -> kind
            else -> getString(R.string.ongoing_workout_subtitle_default)
        }
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(getString(R.string.ongoing_workout_notif_title))
            .setContentText(line)
            .setStyle(NotificationCompat.BigTextStyle().bigText(line))
            .setSmallIcon(R.drawable.ic_launcher)
            .setOngoing(true)
            .setContentIntent(pi)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOnlyAlertOnce(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .build()
    }

    private fun createChannelIfNeeded() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = getSystemService(NotificationManager::class.java) ?: return
        val ch = NotificationChannel(
            CHANNEL_ID,
            getString(R.string.ongoing_workout_notif_channel),
            NotificationManager.IMPORTANCE_LOW
        )
        nm.createNotificationChannel(ch)
    }

    companion object {
        const val NOTIFICATION_ID = 94001
        private const val CHANNEL_ID = "ongoing_workout"
        const val EXTRA_SUBTITLE = "subtitle"
        const val EXTRA_TRACK_LOCATION = "track_location"
        const val EXTRA_WORKOUT_ID = "workout_id"
        /** "balanced" o "batterySaving" (paridad con [Liftr.CardioGPSProfile]). */
        const val EXTRA_GPS_PROFILE = "gps_profile"
        private const val TAG = "OngoingWorkoutSvc"
        private val HEALTH_RUNTIME_PERMISSIONS = listOfNotNull(
            android.Manifest.permission.ACTIVITY_RECOGNITION,
            android.Manifest.permission.BODY_SENSORS,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                android.Manifest.permission.HIGH_SAMPLING_RATE_SENSORS
            } else {
                null
            }
        )

        fun start(
            context: Context,
            subtitle: String,
            trackLocation: Boolean = false,
            workoutId: Int,
            gpsProfile: String = "balanced"
        ) {
            if (Build.VERSION.SDK_INT >= 34) {
                val hasLocationPermission = ActivityCompat.checkSelfPermission(
                    context,
                    android.Manifest.permission.ACCESS_FINE_LOCATION
                ) == PackageManager.PERMISSION_GRANTED
                val hasHealthPermission = HEALTH_RUNTIME_PERMISSIONS.any { perm ->
                    ActivityCompat.checkSelfPermission(context, perm) == PackageManager.PERMISSION_GRANTED
                }
                val canStart = when {
                    trackLocation -> hasLocationPermission || hasHealthPermission
                    else -> hasHealthPermission
                }
                if (!canStart) {
                    Log.w(TAG, "Skip starting OngoingWorkoutService: missing runtime permissions for FGS types.")
                    return
                }
            }
            val i = Intent(context, OngoingWorkoutService::class.java)
                .putExtra(EXTRA_SUBTITLE, subtitle)
                .putExtra(EXTRA_TRACK_LOCATION, trackLocation)
                .putExtra(EXTRA_WORKOUT_ID, workoutId)
                .putExtra(EXTRA_GPS_PROFILE, gpsProfile)
            ContextCompat.startForegroundService(context, i)
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, OngoingWorkoutService::class.java))
        }
    }
}
