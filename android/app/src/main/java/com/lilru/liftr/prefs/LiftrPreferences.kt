package com.lilru.liftr.prefs

import android.content.Context
import android.content.Context.MODE_PRIVATE

/**
 * Paridad con iOS [@AppStorage("isPremium")]: almacenamiento local del estado premium
 * (complementa la detección vía Play Billing al arrancar).
 */
object LiftrPreferences {
    private const val PREF = "liftr_app_prefs"
    private const val KEY_IS_PREMIUM = "isPremium"
    private const val KEY_SKIP_START_COUNTDOWN = "skipStartCountdown"
    private const val KEY_ACTIVE_STRENGTH_NAV_HINT_SEEN = "activeStrengthNavHintSeen"
    private const val KEY_ADD_WORKOUT_PLAN_TOOLTIP_SEEN = "addWorkoutPlanTooltipSeen"
    /**
     * Paridad con iOS [ProfileView] / [Liftr/GradientBackground] @AppStorage("backgroundTheme");
     * valores: mintBlue, sunset, forest, midnight, lavender, ocean, rose, desert, berry, mono.
     */
    private const val KEY_BACKGROUND_THEME = "backgroundTheme"

    fun isPremium(context: Context): Boolean =
        context.applicationContext
            .getSharedPreferences(PREF, MODE_PRIVATE)
            .getBoolean(KEY_IS_PREMIUM, false)

    fun setPremium(context: Context, value: Boolean) {
        context.applicationContext
            .getSharedPreferences(PREF, MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_IS_PREMIUM, value)
            .apply()
    }

    /**
     * Si es true, se abre el entreno activo sin [com.lilru.liftr.ui.home.StartWorkoutCountdownScreen]
     * (lectura usada en [com.lilru.liftr.ui.home.WorkoutDetailScreen]; ajuste de producto o pruebas; ver `ADD_WORKOUT_PARITY.md`).
     */
    fun skipStartCountdown(context: Context): Boolean =
        context.applicationContext
            .getSharedPreferences(PREF, MODE_PRIVATE)
            .getBoolean(KEY_SKIP_START_COUNTDOWN, false)

    fun setSkipStartCountdown(context: Context, value: Boolean) {
        context.applicationContext
            .getSharedPreferences(PREF, MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_SKIP_START_COUNTDOWN, value)
            .apply()
    }

    /** Paridad con [Liftr.ActiveStrengthWorkoutView] @AppStorage activeStrengthNavHintSeen. */
    fun activeStrengthNavHintSeen(context: Context): Boolean =
        context.applicationContext
            .getSharedPreferences(PREF, MODE_PRIVATE)
            .getBoolean(KEY_ACTIVE_STRENGTH_NAV_HINT_SEEN, false)

    fun setActiveStrengthNavHintSeen(context: Context, value: Boolean) {
        context.applicationContext
            .getSharedPreferences(PREF, MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_ACTIVE_STRENGTH_NAV_HINT_SEEN, value)
            .apply()
    }

    /** Paridad con [Liftr.AddWorkoutSheet] @AppStorage addWorkoutPlanTooltipSeen. */
    fun addWorkoutPlanTooltipSeen(context: Context): Boolean =
        context.applicationContext
            .getSharedPreferences(PREF, MODE_PRIVATE)
            .getBoolean(KEY_ADD_WORKOUT_PLAN_TOOLTIP_SEEN, false)

    fun setAddWorkoutPlanTooltipSeen(context: Context, value: Boolean) {
        context.applicationContext
            .getSharedPreferences(PREF, MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_ADD_WORKOUT_PLAN_TOOLTIP_SEEN, value)
            .apply()
    }

    fun backgroundTheme(context: Context): String {
        return context.applicationContext
            .getSharedPreferences(PREF, MODE_PRIVATE)
            .getString(KEY_BACKGROUND_THEME, "mintBlue")
            ?: "mintBlue"
    }

    fun setBackgroundTheme(context: Context, value: String) {
        val v = value.trim().ifEmpty { "mintBlue" }
        context.applicationContext
            .getSharedPreferences(PREF, MODE_PRIVATE)
            .edit()
            .putString(KEY_BACKGROUND_THEME, v)
            .apply()
    }

    private const val KEY_TERRITORY_REFERENCE_LAT = "territoryReferenceLat"
    private const val KEY_TERRITORY_REFERENCE_LON = "territoryReferenceLon"
    private const val KEY_TERRITORY_HISTORICAL_BACKFILL_DONE = "territoryHistoricalBackfillCompletedV2"

    fun territoryReferenceCoordinate(context: Context): Pair<Double, Double>? {
        val prefs = context.applicationContext.getSharedPreferences(PREF, MODE_PRIVATE)
        if (!prefs.contains(KEY_TERRITORY_REFERENCE_LAT) || !prefs.contains(KEY_TERRITORY_REFERENCE_LON)) {
            return null
        }
        return prefs.getFloat(KEY_TERRITORY_REFERENCE_LAT, 0f).toDouble() to
            prefs.getFloat(KEY_TERRITORY_REFERENCE_LON, 0f).toDouble()
    }

    fun setTerritoryReferenceCoordinate(context: Context, latitude: Double, longitude: Double) {
        context.applicationContext
            .getSharedPreferences(PREF, MODE_PRIVATE)
            .edit()
            .putFloat(KEY_TERRITORY_REFERENCE_LAT, latitude.toFloat())
            .putFloat(KEY_TERRITORY_REFERENCE_LON, longitude.toFloat())
            .apply()
    }

    fun territoryHistoricalBackfillDone(context: Context): Boolean =
        context.applicationContext
            .getSharedPreferences(PREF, MODE_PRIVATE)
            .getBoolean(KEY_TERRITORY_HISTORICAL_BACKFILL_DONE, false)

    fun setTerritoryHistoricalBackfillDone(context: Context, value: Boolean) {
        context.applicationContext
            .getSharedPreferences(PREF, MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_TERRITORY_HISTORICAL_BACKFILL_DONE, value)
            .apply()
    }

    fun getStringList(context: Context, key: String): List<String> {
        val raw = context.applicationContext
            .getSharedPreferences(PREF, MODE_PRIVATE)
            .getString(key, null)
            ?: return emptyList()
        if (raw.isEmpty()) return emptyList()
        return raw.split('\u001F').filter { it.isNotEmpty() }
    }

    fun setStringList(context: Context, key: String, values: List<String>) {
        val raw = values.joinToString("\u001F")
        context.applicationContext
            .getSharedPreferences(PREF, MODE_PRIVATE)
            .edit()
            .putString(key, raw)
            .apply()
    }

    private const val KEY_BODY_WEIGHT_HEALTH_SYNC_ENABLED = "bodyWeightHealthSyncEnabled"
    private const val KEY_BODY_WEIGHT_HEALTH_LAST_SYNC_AT = "bodyWeightHealthLastSyncAt"

    fun bodyWeightHealthSyncEnabled(context: Context): Boolean =
        context.applicationContext
            .getSharedPreferences(PREF, MODE_PRIVATE)
            .getBoolean(KEY_BODY_WEIGHT_HEALTH_SYNC_ENABLED, false)

    fun setBodyWeightHealthSyncEnabled(context: Context, value: Boolean) {
        context.applicationContext
            .getSharedPreferences(PREF, MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_BODY_WEIGHT_HEALTH_SYNC_ENABLED, value)
            .apply()
    }

    fun bodyWeightHealthLastSyncAt(context: Context): java.time.Instant? {
        val raw = context.applicationContext
            .getSharedPreferences(PREF, MODE_PRIVATE)
            .getString(KEY_BODY_WEIGHT_HEALTH_LAST_SYNC_AT, null)
            ?: return null
        return runCatching { java.time.Instant.parse(raw) }.getOrNull()
    }

    fun setBodyWeightHealthLastSyncAt(context: Context, value: java.time.Instant) {
        context.applicationContext
            .getSharedPreferences(PREF, MODE_PRIVATE)
            .edit()
            .putString(KEY_BODY_WEIGHT_HEALTH_LAST_SYNC_AT, value.toString())
            .apply()
    }
}
