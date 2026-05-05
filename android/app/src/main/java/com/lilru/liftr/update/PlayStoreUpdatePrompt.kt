package com.lilru.liftr.update

import android.content.Context
import android.content.SharedPreferences

/**
 * Estrategia y cadencia alineada con [Liftr.AppUpdateChecker] (iOS): comprobar con Play In-App Update
 * y no spamear avisos.
 */
object PlayStoreUpdatePrompt {
    private const val PREFS = "liftr_app_update"
    private const val K_LAST_CHECK_MS = "app_update_last_check_ms"
    private const val K_LAST_PROMPT_MS = "app_update_last_prompt_ms"
    private const val K_LAST_PROMPT_VCODE = "app_update_last_prompt_vcode"
    private const val MIN_CHECK_MS = 24L * 60 * 60 * 1000
    private const val MIN_PROMPT_MS = 24L * 60 * 60 * 1000

    fun prefs(c: Context): SharedPreferences = c.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun canCheck(p: SharedPreferences): Boolean {
        val now = System.currentTimeMillis()
        return now - p.getLong(K_LAST_CHECK_MS, 0L) >= MIN_CHECK_MS
    }

    fun markCheckStart(p: SharedPreferences) {
        p.edit().putLong(K_LAST_CHECK_MS, System.currentTimeMillis()).apply()
    }

    /**
     * Si se debe enseñar el banner: nueva [availableVersionCode] o pasó el intervalo respecto a la
     * última versión con la que se enseñó.
     */
    fun shouldShowPrompt(p: SharedPreferences, availableVersionCode: Int): Boolean {
        val now = System.currentTimeMillis()
        val lastV = p.getInt(K_LAST_PROMPT_VCODE, -1)
        val lastAt = p.getLong(K_LAST_PROMPT_MS, 0L)
        if (lastV == availableVersionCode && now - lastAt < MIN_PROMPT_MS) {
            return false
        }
        return true
    }

    fun recordPromptShown(p: SharedPreferences, availableVersionCode: Int) {
        p.edit()
            .putLong(K_LAST_PROMPT_MS, System.currentTimeMillis())
            .putInt(K_LAST_PROMPT_VCODE, availableVersionCode)
            .apply()
    }
}
