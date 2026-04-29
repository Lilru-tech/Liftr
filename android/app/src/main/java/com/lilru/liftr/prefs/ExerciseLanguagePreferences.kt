package com.lilru.liftr.prefs

import android.content.Context
import android.content.Context.MODE_PRIVATE
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.withContext

private val Context.exerciseLanguageDataStore by preferencesDataStore("liftr_exercise_language")

/**
 * Paridad con iOS: idioma de nombres de ejercicios en Add / picker.
 * Migra el valor de `com.lilru.liftr.add_workout` → `exercise_language` (SharedPreferences) si aún no hay DataStore.
 */
object ExerciseLanguagePreferences {
    private const val LEGACY_PREFS = "com.lilru.liftr.add_workout"
    private const val LEGACY_KEY = "exercise_language"
    private val keyLang = stringPreferencesKey(LEGACY_KEY)

    suspend fun read(context: Context): String = withContext(Dispatchers.IO) {
        val fromStore = context.exerciseLanguageDataStore.data.map { it[keyLang] }.first()
        if (fromStore != null) return@withContext fromStore
        val legacy = context.applicationContext
            .getSharedPreferences(LEGACY_PREFS, MODE_PRIVATE)
            .getString(LEGACY_KEY, null)
        val v = (legacy ?: "en").ifEmpty { "en" }
        set(context, v)
        v
    }

    suspend fun set(context: Context, lang: String) {
        val v = if (lang.isNotEmpty()) lang else "en"
        context.exerciseLanguageDataStore.edit { p ->
            p[keyLang] = v
        }
    }
}
