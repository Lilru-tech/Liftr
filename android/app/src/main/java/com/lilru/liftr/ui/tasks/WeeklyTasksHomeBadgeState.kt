package com.lilru.liftr.ui.tasks

import android.content.Context
import androidx.compose.ui.graphics.Color
import com.lilru.liftr.data.BackendContracts
import com.lilru.liftr.prefs.LiftrPreferences
import io.github.jan.supabase.postgrest.postgrest
import org.json.JSONObject
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class WeeklyTasksHomeSummary(
    @SerialName("week_start") val weekStart: String,
    @SerialName("accepted_count") val acceptedCount: Int = 0,
    @SerialName("accept_slots_remaining") val acceptSlotsRemaining: Int = 0,
    @SerialName("available_count") val availableCount: Int = 0,
    @SerialName("completed_count_this_week") val completedCountThisWeek: Int = 0,
) {
    val hasPickableTasks: Boolean
        get() = acceptSlotsRemaining > 0 && availableCount > 0
}

object WeeklyTasksHomeBadgeState {
    fun hasUnseenCompletion(context: Context, summary: WeeklyTasksHomeSummary): Boolean {
        val lastSeen = effectiveLastSeenCount(context, summary)
        return summary.completedCountThisWeek > lastSeen
    }

    private fun effectiveLastSeenCount(context: Context, summary: WeeklyTasksHomeSummary): Int {
        val storedWeek = LiftrPreferences.weeklyTasksLastSeenWeekStart(context)
        if (storedWeek != summary.weekStart) return 0
        return LiftrPreferences.weeklyTasksLastSeenCompletedCount(context)
    }

    fun markSeen(context: Context, summary: WeeklyTasksHomeSummary) {
        LiftrPreferences.setWeeklyTasksLastSeenCompletedCount(context, summary.completedCountThisWeek)
        LiftrPreferences.setWeeklyTasksLastSeenWeekStart(context, summary.weekStart)
    }

    fun accentDotColor(context: Context, summary: WeeklyTasksHomeSummary): Color? {
        if (hasUnseenCompletion(context, summary)) {
            return Color(0xFF34C759)
        }
        if (summary.hasPickableTasks) {
            return Color(0xFFFF9500)
        }
        return null
    }

    fun pillShowsPickSubtitle(summary: WeeklyTasksHomeSummary): Boolean = summary.hasPickableTasks
}

suspend fun fetchWeeklyTasksHomeSummary(supabase: io.github.jan.supabase.SupabaseClient): WeeklyTasksHomeSummary? =
    runCatching {
        val res = supabase.postgrest.rpc(BackendContracts.Rpc.GET_MY_WEEKLY_TASKS_HOME_SUMMARY_V1) { }
        val o = JSONObject(res.data)
        WeeklyTasksHomeSummary(
            weekStart = o.optString("week_start"),
            acceptedCount = o.optInt("accepted_count", 0),
            acceptSlotsRemaining = o.optInt("accept_slots_remaining", 0),
            availableCount = o.optInt("available_count", 0),
            completedCountThisWeek = o.optInt("completed_count_this_week", 0),
        )
    }.getOrNull()

suspend fun markWeeklyTasksHomeSeen(supabase: io.github.jan.supabase.SupabaseClient, context: Context) {
    val summary = fetchWeeklyTasksHomeSummary(supabase) ?: return
    WeeklyTasksHomeBadgeState.markSeen(context, summary)
}
