package com.lilru.liftr.prefs

import android.content.Context
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

private val Context.homeUiDataStore by preferencesDataStore("liftr_home_ui")

/** Plegado de secciones en Home (paridad con @AppStorage en iOS HomeView: today, streak, insights, monthly). */
object HomeUiPreferences {
    private val homeCollapseData = booleanPreferencesKey("home_collapse_data")
    private val homeCollapseModules = booleanPreferencesKey("home_collapse_modules")
    private val homeCollapseToday = booleanPreferencesKey("home_collapse_today")
    private val homeCollapseStreak = booleanPreferencesKey("home_collapse_streak")
    private val homeCollapseInsights = booleanPreferencesKey("home_collapse_insights")
    private val homeCollapseMonthly = booleanPreferencesKey("home_collapse_monthly")

    data class HomeCollapseState(
        val collapseData: Boolean = false,
        val collapseModules: Boolean = false,
        val collapseToday: Boolean = false,
        val collapseStreak: Boolean = false,
        val collapseInsights: Boolean = false,
        val collapseMonthly: Boolean = false
    ) {
        fun withAllCollapsed(v: Boolean) = copy(
            collapseData = v,
            collapseModules = v,
            collapseToday = v,
            collapseStreak = v,
            collapseInsights = v,
            collapseMonthly = v
        )
    }

    fun collapseFlow(context: Context): Flow<HomeCollapseState> =
        context.homeUiDataStore.data.map { p: Preferences ->
            HomeCollapseState(
                collapseData = p[homeCollapseData] ?: false,
                collapseModules = p[homeCollapseModules] ?: false,
                collapseToday = p[homeCollapseToday] ?: false,
                collapseStreak = p[homeCollapseStreak] ?: false,
                collapseInsights = p[homeCollapseInsights] ?: false,
                collapseMonthly = p[homeCollapseMonthly] ?: false
            )
        }

    suspend fun setCollapseModules(context: Context, v: Boolean) {
        context.homeUiDataStore.edit { it[homeCollapseModules] = v }
    }

    suspend fun setAllCollapsed(context: Context, collapsed: Boolean) {
        context.homeUiDataStore.edit { p ->
            p[homeCollapseData] = collapsed
            p[homeCollapseModules] = collapsed
            p[homeCollapseToday] = collapsed
            p[homeCollapseStreak] = collapsed
            p[homeCollapseInsights] = collapsed
            p[homeCollapseMonthly] = collapsed
        }
    }

    suspend fun setCollapseMonthly(context: Context, v: Boolean) {
        context.homeUiDataStore.edit { it[homeCollapseMonthly] = v }
    }

    suspend fun setCollapseToday(context: Context, v: Boolean) {
        context.homeUiDataStore.edit { it[homeCollapseToday] = v }
    }

    suspend fun setCollapseStreak(context: Context, v: Boolean) {
        context.homeUiDataStore.edit { it[homeCollapseStreak] = v }
    }

    suspend fun setCollapseInsights(context: Context, v: Boolean) {
        context.homeUiDataStore.edit { it[homeCollapseInsights] = v }
    }
}
