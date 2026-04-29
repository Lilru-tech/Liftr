package com.lilru.liftr.prefs

import android.content.Context
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map

private val Context.cardioGpsDataStore by preferencesDataStore("liftr_cardio_gps")

/** Alineado con [Liftr.CardioGPSProfile] (balanced / batterySaving). */
enum class CardioGpsProfile {
    BALANCED,
    BATTERY_SAVING
}

object CardioGpsPreferences {
    private val keyProfile = stringPreferencesKey("cardio_gps_profile")

    private fun toRaw(p: CardioGpsProfile): String = when (p) {
        CardioGpsProfile.BALANCED -> "balanced"
        CardioGpsProfile.BATTERY_SAVING -> "batterySaving"
    }

    private fun fromRaw(s: String?): CardioGpsProfile = when (s) {
        "batterySaving" -> CardioGpsProfile.BATTERY_SAVING
        else -> CardioGpsProfile.BALANCED
    }

    suspend fun readProfile(context: Context): CardioGpsProfile {
        val raw = context.cardioGpsDataStore.data
            .map { it[keyProfile] }
            .first()
        return fromRaw(raw)
    }

    suspend fun setProfile(context: Context, profile: CardioGpsProfile) {
        context.cardioGpsDataStore.edit { p ->
            p[keyProfile] = toRaw(profile)
        }
    }
}
