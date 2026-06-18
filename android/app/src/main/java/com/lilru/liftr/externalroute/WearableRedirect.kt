package com.lilru.liftr.externalroute

import android.net.Uri

object WearableRedirect {
    const val HOST = "wearable-callback"

    fun isWearableCallback(uri: Uri): Boolean = uri.host == HOST

    fun status(uri: Uri): String? =
        uri.getQueryParameter("status")

    fun provider(uri: Uri): String? =
        uri.getQueryParameter("provider")
}
