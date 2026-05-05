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
}
