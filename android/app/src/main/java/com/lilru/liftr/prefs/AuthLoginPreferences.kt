package com.lilru.liftr.prefs

import android.content.Context
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map

private val Context.authLoginDataStore by preferencesDataStore("liftr_auth_login")

/**
 * Paridad con [Liftr.LoginView] (remember me + email en keychain en iOS).
 * En Android solo se persiste el **email** (no la contraseña en claro).
 */
object AuthLoginPreferences {
    private val keyRemember = booleanPreferencesKey("login_remember_email")
    private val keyEmail = stringPreferencesKey("login_saved_email")

    data class State(
        val rememberEmail: Boolean = false,
        val savedEmail: String = ""
    )

    suspend fun readState(context: Context): State =
        context.authLoginDataStore.data.map { p: Preferences ->
            val rem = p[keyRemember] ?: false
            val em = (p[keyEmail] ?: "").trim()
            State(rememberEmail = rem, savedEmail = if (rem) em else "")
        }.first()

    suspend fun setRememberWithEmail(context: Context, remember: Boolean, email: String) {
        val safe = email.trim()
        context.authLoginDataStore.edit { p ->
            p[keyRemember] = remember
            if (remember && safe.isNotEmpty()) {
                p[keyEmail] = safe
            } else {
                p.remove(keyEmail)
            }
        }
    }
}
