package com.lilru.liftr.ui.territory

import android.content.Context
import android.util.Log
import com.google.android.gms.common.ConnectionResult
import com.google.android.gms.common.GoogleApiAvailability
import com.google.android.gms.maps.MapsInitializer
import com.lilru.liftr.BuildConfig

const val TERRITORY_MAP_LOG_TAG = "LiftrTerritoryMap"

object TerritoryMapDiagnostics {
    fun logStartup(context: Context) {
        val key = BuildConfig.MAPS_API_KEY
        val keyTail = if (key.length >= 4) key.takeLast(4) else "none"
        val playServices = GoogleApiAvailability.getInstance().isGooglePlayServicesAvailable(context)
        Log.i(
            TERRITORY_MAP_LOG_TAG,
            "package=${context.packageName} mapsKeyConfigured=${key.isNotBlank()} mapsKeyTail=$keyTail playServices=$playServices"
        )
        if (playServices != ConnectionResult.SUCCESS) {
            Log.w(TERRITORY_MAP_LOG_TAG, "Google Play services unavailable code=$playServices")
        }
        runCatching {
            MapsInitializer.initialize(
                context,
                MapsInitializer.Renderer.LATEST
            ) { renderer ->
                Log.i(TERRITORY_MAP_LOG_TAG, "Maps SDK initialized renderer=$renderer")
            }
        }.onFailure { error ->
            Log.e(TERRITORY_MAP_LOG_TAG, "Maps SDK initialize failed", error)
        }
    }

    fun logCellsFetched(cellCount: Int, drawableCells: Int) {
        Log.i(
            TERRITORY_MAP_LOG_TAG,
            "Territory cells fetched=$cellCount drawableRings=$drawableCells"
        )
    }

    fun logMapLoaded() {
        Log.i(
            TERRITORY_MAP_LOG_TAG,
            "GoogleMap onMapLoaded. If tiles stay blank, filter Logcat for Authorization failure."
        )
    }
}
