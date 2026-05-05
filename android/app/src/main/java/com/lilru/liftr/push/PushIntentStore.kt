package com.lilru.liftr.push

import android.content.Intent
import java.util.concurrent.atomic.AtomicReference

/**
 * Se rellena desde [com.lilru.liftr.MainActivity] al abrir la app por notificación;
 * se consume al estar autenticado (misma idea que [Liftr/AppState.swift] `pendingNotification`).
 */
object PushIntentStore {
    private val ref = AtomicReference<Map<String, String>?>(null)

    fun setFromIntent(intent: Intent?) {
        if (intent == null) return
        val m = extractPushData(intent)
        if (m != null) {
            ref.set(m)
        }
    }

    fun take(): Map<String, String>? = ref.getAndSet(null)

    private fun extractPushData(i: Intent): Map<String, String>? {
        val out = HashMap<String, String>()
        i.extras?.keySet()?.forEach { k ->
            if (k.startsWith("push_")) {
                val v = i.extras!![k] as? String ?: return@forEach
                out[k.removePrefix("push_")] = v
            }
        }
        i.getStringExtra("push_type")?.let { out["type"] = it }
        if (out.isEmpty() && i.getStringExtra("type") == null) {
            return null
        }
        if (!out.containsKey("type")) {
            i.getStringExtra("type")?.let { out["type"] = it }
        }
        return if (out["type"].isNullOrBlank() && out.isEmpty()) null else out
    }
}
