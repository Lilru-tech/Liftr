package com.lilru.liftr.navigation

import android.content.Intent
import java.util.concurrent.atomic.AtomicInteger

/**
 * [MainActivity] / widget: extra `open_workout_id` → [LiftrAppContent] (paridad con deep links).
 */
object OpenWorkoutIntentStore {
    private val pending = AtomicInteger(-1)

    fun setFromIntent(intent: Intent?) {
        if (intent == null) return
        val w = intent.getIntExtra(EXTRA_OPEN_WORKOUT_ID, -1)
        if (w > 0) {
            pending.set(w)
        }
    }

    fun takeWorkoutId(): Int? {
        val v = pending.getAndSet(-1)
        return v.takeIf { it > 0 }
    }

    const val EXTRA_OPEN_WORKOUT_ID = "open_workout_id"
}
