package com.lilru.liftr.data

import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.postgrest

object PremiumStatusClient {
    suspend fun fetchIsPremium(supabase: SupabaseClient): Boolean {
        return runCatching {
            val res = supabase.postgrest.rpc(BackendContracts.Rpc.GET_USER_PREMIUM_STATUS_V1) { }
            val trimmed = res.data.trim()
            when (trimmed.lowercase()) {
                "true" -> true
                "false" -> false
                else -> SupabaseResponseDecoding.json.decodeFromString<Boolean>(trimmed)
            }
        }.getOrDefault(false)
    }
}
