package com.lilru.liftr.auth

import android.net.Uri

object AuthRedirect {
    const val SCHEME = "com.lilru.liftr"
    const val HOST = "auth-callback"

    const val WEB_CALLBACK_HOST = "settleit-auth.vercel.app"
    const val WEB_CALLBACK_PATH = "/auth/callback"
    const val WEB_CALLBACK_URL = "https://$WEB_CALLBACK_HOST$WEB_CALLBACK_PATH"

    const val APP_DEEP_LINK_URL = "$SCHEME://$HOST"

    fun isAuthCallback(uri: Uri?): Boolean =
        uri?.scheme == SCHEME && uri.host == HOST
}

object PasswordResetValidation {
    const val MINIMUM_LENGTH = 8

    fun passwordsMatch(password: String, confirm: String): Boolean = password == confirm

    fun isPasswordValid(password: String): Boolean = password.length >= MINIMUM_LENGTH
}
