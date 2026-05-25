package com.lilru.liftr.data

import io.github.jan.supabase.SupabaseClient
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

object PremiumStatusStore {
    private val _isPremium = MutableStateFlow(false)
    val isPremium: StateFlow<Boolean> = _isPremium.asStateFlow()

    suspend fun refresh(supabase: SupabaseClient) {
        _isPremium.value = PremiumStatusClient.fetchIsPremium(supabase)
    }

    fun clear() {
        _isPremium.value = false
    }
}
