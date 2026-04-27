package com.lilru.liftr.push

import android.util.Log
import com.lilru.liftr.data.BackendContracts
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.postgrest.from
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/**
 * Paridad con [Liftr/NotificationTokenUploader.swift]: `profiles.fcm_token`.
 */
object FcmTokenUploader {
    private const val TAG = "FcmTokenUploader"

    suspend fun updateFcmToken(supabase: SupabaseClient, token: String) {
        val user = supabase.auth.currentUserOrNull() ?: run {
            Log.w(TAG, "No authenticated user; skipping fcm_token update")
            return
        }
        runCatching {
            supabase.from(BackendContracts.Tables.PROFILES).update(
                buildJsonObject { put("fcm_token", JsonPrimitive(token)) }
            ) {
                filter { eq("user_id", user.id) }
            }
        }.onSuccess {
            Log.i(TAG, "fcm_token updated in Supabase for user_id ${user.id}")
        }.onFailure { e ->
            Log.e(TAG, "Error updating fcm_token: ${e.message}", e)
        }
    }

    suspend fun clearFcmToken(supabase: SupabaseClient) {
        val user = supabase.auth.currentUserOrNull() ?: return
        runCatching {
            supabase.from(BackendContracts.Tables.PROFILES).update(
                buildJsonObject { put("fcm_token", JsonNull) }
            ) {
                filter { eq("user_id", user.id) }
            }
        }.onFailure { e -> Log.w(TAG, "clear fcm_token: ${e.message}") }
    }
}
