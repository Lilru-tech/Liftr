package com.lilru.liftr.externalroute

import android.content.Intent
import android.net.Uri

object WearableCallbackStore {
  private var pendingUri: Uri? = null

  fun setFromIntent(intent: Intent?) {
    val uri = intent?.data ?: return
    if (WearableRedirect.isWearableCallback(uri)) {
      pendingUri = uri
    }
  }

  fun consume(): Uri? {
    val uri = pendingUri
    pendingUri = null
    return uri
  }
}
