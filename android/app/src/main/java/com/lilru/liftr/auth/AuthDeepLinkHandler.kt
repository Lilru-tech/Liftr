package com.lilru.liftr.auth

import android.content.Intent
import com.lilru.liftr.data.LiftrSupabase
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.handleDeeplinks

fun handleAuthDeepLinkIfPresent(intent: Intent?, client: SupabaseClient?): Boolean {
    val uri = intent?.data ?: return false
    if (!AuthRedirect.isAuthCallback(uri)) return false
    val supabase = client ?: return false
    supabase.handleDeeplinks(intent)
    PasswordRecoveryGate.markPending()
    return true
}
