package com.lilru.liftr.ui.notifications

import com.lilru.liftr.data.BackendContracts
import com.lilru.liftr.data.SupabaseResponseDecoding
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.query.Columns
import kotlinx.serialization.json.JsonObject

object UnreadNotificationCounter {
    suspend fun count(supabase: SupabaseClient): Int {
        val me = supabase.auth.currentUserOrNull()?.id ?: return 0
        return runCatching {
            supabase
                .from(BackendContracts.Tables.NOTIFICATIONS)
                .select(columns = Columns.raw("id")) {
                    filter {
                        eq("user_id", me)
                        eq("is_read", false)
                    }
                    limit(500)
                }
                .let { SupabaseResponseDecoding.decodeListOrObject<JsonObject>(it.data).size }
        }.getOrDefault(0)
    }
}
