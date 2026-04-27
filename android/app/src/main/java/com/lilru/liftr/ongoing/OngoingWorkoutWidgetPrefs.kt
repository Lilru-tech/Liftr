package com.lilru.liftr.ongoing

import android.content.Context

/**
 * Estado mínimo para [LiftrWidget] mientras [OngoingWorkoutService] está en primer plano.
 */
object OngoingWorkoutWidgetPrefs {
    private const val PREFS = "liftr_ongoing_widget"
    private const val KEY_WID = "workout_id"
    private const val KEY_SUB = "subtitle"
    private const val KEY_STATS = "stats_line"
    private const val KEY_START_MS = "started_at_ms"

    data class Snapshot(
        val workoutId: Int,
        val subtitle: String,
        val startedAtMs: Long,
        /** Distancia / tiempo / ritmo (cardio), set actual (fuerza), etc. */
        val statsLine: String = ""
    )

    fun setActive(
        context: Context,
        workoutId: Int,
        subtitle: String,
        statsLine: String = ""
    ) {
        val p = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val oldWid = p.getInt(KEY_WID, -1)
        val startMs = if (oldWid == workoutId) {
            p.getLong(KEY_START_MS, 0L).takeIf { it > 0L } ?: System.currentTimeMillis()
        } else {
            System.currentTimeMillis()
        }
        p.edit()
            .putInt(KEY_WID, workoutId)
            .putString(KEY_SUB, subtitle)
            .putString(KEY_STATS, statsLine)
            .putLong(KEY_START_MS, startMs)
            .apply()
        OngoingWorkoutWidgetRefresh.requestUpdate(context)
    }

    fun clear(context: Context) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().clear().apply()
        OngoingWorkoutWidgetRefresh.requestUpdate(context)
    }

    fun read(context: Context): Snapshot? {
        val p = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val id = p.getInt(KEY_WID, -1)
        if (id <= 0) return null
        val sub = p.getString(KEY_SUB, null)?.trim().orEmpty()
        val stats = p.getString(KEY_STATS, null)?.trim().orEmpty()
        val start = p.getLong(KEY_START_MS, 0L).takeIf { it > 0L } ?: return null
        return Snapshot(workoutId = id, subtitle = sub, startedAtMs = start, statsLine = stats)
    }
}
