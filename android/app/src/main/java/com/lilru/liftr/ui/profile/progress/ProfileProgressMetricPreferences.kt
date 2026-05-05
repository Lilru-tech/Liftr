package com.lilru.liftr.ui.profile.progress

import android.content.Context
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map

private val Context.profileProgressDataStore by preferencesDataStore("liftr_profile_progress")

/**
 * Paridad con iOS @AppStorage: `consistencyRootChartMetric` y `consistencyDrilldownChartMetric`.
 */
object ProfileProgressMetricPreferences {
    private val keyRoot = stringPreferencesKey("consistency_root_chart_metric")
    private val keyDrilldown = stringPreferencesKey("consistency_drilldown_chart_metric")

    suspend fun readRootMetric(context: Context): ConsistencyChartMetric {
        val w = context.profileProgressDataStore.data.map { p -> p[keyRoot] }.first()
        return ConsistencyChartMetric.fromWire(w)
    }

    suspend fun setRootMetric(context: Context, m: ConsistencyChartMetric) {
        context.profileProgressDataStore.edit { it[keyRoot] = m.wire }
    }

    suspend fun readDrilldownMetric(context: Context): ConsistencyChartMetric {
        val w = context.profileProgressDataStore.data.map { p -> p[keyDrilldown] }.first()
        return ConsistencyChartMetric.fromWire(w)
    }

    suspend fun setDrilldownMetric(context: Context, m: ConsistencyChartMetric) {
        context.profileProgressDataStore.edit { it[keyDrilldown] = m.wire }
    }
}
