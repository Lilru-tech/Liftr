package com.lilru.liftr.ui.profile.progress

import android.app.Application
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.lilru.liftr.R
import com.lilru.liftr.ui.components.LiftrBackTopBar
import io.github.jan.supabase.SupabaseClient
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.round
import kotlin.math.roundToInt

@Composable
fun ConsistencyDrillDownScreen(
    supabase: SupabaseClient,
    rootKind: String,
    workoutMeta: Map<Int, ConsistencyWorkoutMeta>,
    onBack: () -> Unit,
    modifier: Modifier = Modifier
) {
    val app = LocalContext.current.applicationContext as Application
    val vm: ConsistencyDrillDownViewModel = viewModel(
        key = "drill-$rootKind-${workoutMeta.size}-${workoutMeta.keys.hashCode()}",
        factory = ConsistencyDrillDownViewModelFactory(app, supabase, rootKind, workoutMeta)
    )
    val ui by vm.uiState.collectAsStateWithLifecycle()
    val m = ui.effectiveMetric()
    Column(
        modifier = modifier
            .fillMaxSize()
            .statusBarsPadding()
            .padding(12.dp)
            .verticalScroll(rememberScrollState()),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        LiftrBackTopBar(onBack = onBack)
        Text(
            when (rootKind.lowercase()) {
                "sport" -> stringResource(R.string.profile_progress_drill_sport)
                "cardio" -> stringResource(R.string.profile_progress_drill_cardio)
                "strength" -> stringResource(R.string.profile_progress_drill_strength)
                else -> stringResource(R.string.profile_progress_drill_generic)
            },
            style = MaterialTheme.typography.titleLarge
        )
        val cms = ConsistencyChartMetric.entries
        SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
            cms.forEachIndexed { i, met ->
                SegmentedButton(
                    selected = ui.consistencyMetric == met,
                    onClick = { vm.setMetric(met) },
                    shape = SegmentedButtonDefaults.itemShape(i, cms.size)
                ) {
                    Text(
                        when (met) {
                            ConsistencyChartMetric.DURATION -> stringResource(R.string.profile_progress_consistency_time)
                            ConsistencyChartMetric.WORKOUTS -> stringResource(R.string.profile_progress_consistency_workouts)
                            ConsistencyChartMetric.SCORE -> stringResource(R.string.profile_progress_consistency_score)
                            ConsistencyChartMetric.CALORIES -> stringResource(R.string.profile_progress_consistency_kcal)
                        }
                    )
                }
            }
        }
        if (rootKind.equals("strength", ignoreCase = true)) {
            Text(
                stringResource(R.string.profile_progress_strength_footnote),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
        if (ui.loading) {
            Text(stringResource(R.string.profile_progress_loading))
        } else if (ui.error != null) {
            Text(ui.error!!, color = MaterialTheme.colorScheme.error)
        } else if (ui.slices.isEmpty()) {
            Text(
                stringResource(R.string.profile_progress_drill_empty),
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        } else {
            val total = ui.slices.sumOf { s ->
                m.measure(s.durationMin, s.count, s.score, s.kcal)
            }
            ui.slices.forEach { slice ->
                val v = m.measure(slice.durationMin, slice.count, slice.score, slice.kcal)
                val pct = if (total > 0) (v / total) else 0.0
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    Text(slice.title, style = MaterialTheme.typography.bodyLarge)
                    Column(horizontalAlignment = androidx.compose.ui.Alignment.End) {
                        Text(primaryDrill(m, slice, pct), style = MaterialTheme.typography.labelLarge)
                        Text(secondaryDrill(m, slice), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
            val totalSc = ui.slices.sumOf { it.score }
            val totalKc = ui.slices.sumOf { it.kcal }
            val footerW = if (rootKind.equals("strength", ignoreCase = true)) {
                workoutMeta.size
            } else {
                ui.slices.sumOf { it.count }
            }
            val footer = buildString {
                append(footerW)
                append(" workouts · ")
                append(formatMinutesDrill(ui.totalDurationMin))
                append(" total")
                if (totalSc > 0) {
                    append(" · ")
                    append(formatDrillPoints(totalSc))
                    append(" pts")
                }
                if (totalKc > 0) {
                    append(" · ")
                    append(formatDrillKcal(totalKc))
                    append(" kcal")
                }
            }
            Text(footer, style = MaterialTheme.typography.labelMedium, modifier = Modifier.padding(top = 8.dp))
        }
    }
}

private fun primaryDrill(m: ConsistencyChartMetric, s: DrilldownSlice, pct: Double): String {
    val p = (max(0.0, min(1.0, pct)) * 100.0).roundToInt()
    val pctStr = "$p%"
    val wc = if (s.count == 1) "1 workout" else "${s.count} workouts"
    return when (m) {
        ConsistencyChartMetric.DURATION -> "${formatMinutesDrill(s.durationMin)} · $pctStr"
        ConsistencyChartMetric.WORKOUTS -> "$wc · $pctStr"
        ConsistencyChartMetric.SCORE -> "${formatDrillPoints(s.score)} pts · $pctStr"
        ConsistencyChartMetric.CALORIES -> "${formatDrillKcal(s.kcal)} kcal · $pctStr"
    }
}

private fun secondaryDrill(m: ConsistencyChartMetric, s: DrilldownSlice): String {
    val parts = mutableListOf<String>()
    if (m != ConsistencyChartMetric.WORKOUTS) {
        parts.add(if (s.count == 1) "1 workout" else "${s.count} workouts")
    }
    if (m != ConsistencyChartMetric.DURATION && s.durationMin > 0) {
        parts.add(formatMinutesDrill(s.durationMin))
    }
    if (m != ConsistencyChartMetric.SCORE && s.score > 0) {
        parts.add("${formatDrillPoints(s.score)} pts")
    }
    if (m != ConsistencyChartMetric.CALORIES && s.kcal > 0) {
        parts.add("${formatDrillKcal(s.kcal)} kcal")
    }
    return if (parts.isEmpty()) " " else parts.joinToString(" · ")
}

private fun formatMinutesDrill(m: Int): String {
    if (m <= 0) return "0m"
    val h = m / 60
    val r = m % 60
    return if (h > 0) (if (r > 0) "${h}h ${r}m" else "${h}h") else "${r}m"
}

private fun formatDrillPoints(x: Double): String {
    val r = round(x)
    if (abs(x - r) < 0.05) return String.format(java.util.Locale.US, "%.0f", r)
    return String.format(java.util.Locale.US, "%.1f", x)
}

private fun formatDrillKcal(x: Double): String = when {
    x >= 100 -> String.format(java.util.Locale.US, "%.0f", x)
    x >= 10 -> String.format(java.util.Locale.US, "%.1f", x)
    else -> String.format(java.util.Locale.US, "%.2f", x)
}
