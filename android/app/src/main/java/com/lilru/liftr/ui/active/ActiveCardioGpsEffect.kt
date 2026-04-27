package com.lilru.liftr.ui.active

import android.Manifest
import android.content.pm.PackageManager
import android.os.Looper
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalContext
import androidx.core.content.ContextCompat
import com.google.android.gms.location.LocationCallback
import com.google.android.gms.location.LocationRequest
import com.google.android.gms.location.LocationResult
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority

@Composable
fun ActiveCardioGpsEffect(vm: ActiveCardioWorkoutViewModel) {
    val context = LocalContext.current
    val client = remember { LocationServices.getFusedLocationProviderClient(context) }
    val hasPerm = ContextCompat.checkSelfPermission(
        context,
        Manifest.permission.ACCESS_FINE_LOCATION
    ) == PackageManager.PERMISSION_GRANTED
    DisposableEffect(hasPerm) {
        if (!hasPerm) {
            return@DisposableEffect onDispose { }
        }
        val req = LocationRequest.Builder(Priority.PRIORITY_HIGH_ACCURACY, 5000L)
            .setMinUpdateIntervalMillis(4000L)
            .setMaxUpdateDelayMillis(10000L)
            .build()
        val cb = object : LocationCallback() {
            override fun onLocationResult(result: LocationResult) {
                val loc = result.lastLocation ?: return
                vm.appendRoutePoint(loc.latitude, loc.longitude)
            }
        }
        client.requestLocationUpdates(req, cb, Looper.getMainLooper())
        onDispose {
            client.removeLocationUpdates(cb)
        }
    }
}
