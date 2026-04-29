package com.lilru.liftr.ui.profile.progress

import android.app.Application
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.LocalMinimumInteractiveComponentEnforcement
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.lilru.liftr.R
import com.lilru.liftr.ui.components.LiftrBackTopBar
import io.github.jan.supabase.SupabaseClient
import java.util.Locale
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/** Altura de cada segmento; acercar a iOS (píldoras bajas). */
private val ProgressSegmentButtonHeight = 30.dp
private val ProgressSegmentRowSpacing = 6.dp

@Composable
private fun ProgressSegmentLabel(text: String) {
    Text(
        text = text,
        style = MaterialTheme.typography.labelSmall,
        fontSize = 11.sp,
        lineHeight = 13.sp,
        maxLines = 1,
        overflow = TextOverflow.Ellipsis
    )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ProfileProgressScreen(
    supabase: SupabaseClient,
    userId: String,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
    /** Pestaña *Progress* del perfil: sin barra Atrás ni título duplicado. */
    embedded: Boolean = false
) {
    val app = LocalContext.current.applicationContext as Application
    val vm: ProfileProgressViewModel = viewModel(
        key = userId,
        factory = ProfileProgressViewModelFactory(app, supabase, userId)
    )
    val ui by vm.uiState.collectAsStateWithLifecycle()
    var drillKind by remember { mutableStateOf<String?>(null) }
    if (drillKind != null) {
        val meta = vm.metaForRootKind(drillKind!!)
        val k = drillKind!!
        ConsistencyDrillDownScreen(
            supabase = supabase,
            rootKind = k,
            workoutMeta = meta,
            onBack = { drillKind = null }
        )
        return
    }
    Column(
        modifier = modifier
            .fillMaxSize()
            .then(if (embedded) Modifier else Modifier.statusBarsPadding())
            .padding(if (embedded) 4.dp else 12.dp),
        verticalArrangement = Arrangement.spacedBy(if (embedded) 8.dp else 10.dp)
    ) {
        if (!embedded) {
            LiftrBackTopBar(onBack = onBack)
            Text(
                stringResource(R.string.profile_progress_title),
                style = MaterialTheme.typography.titleLarge
            )
        }
        // Selectores compactos (paridad visual con iOS: menos altura y tipografía label).
        CompositionLocalProvider(LocalMinimumInteractiveComponentEnforcement provides false) {
            Column(verticalArrangement = Arrangement.spacedBy(ProgressSegmentRowSpacing)) {
                val ranges = listOf(
                    ProfileProgressRange.WEEK,
                    ProfileProgressRange.MONTH,
                    ProfileProgressRange.YEAR
                )
                SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                    ranges.forEachIndexed { i, r ->
                        SegmentedButton(
                            selected = ui.range == r,
                            onClick = { vm.setRange(r) },
                            shape = SegmentedButtonDefaults.itemShape(i, ranges.size),
                            modifier = Modifier
                                .defaultMinSize(minWidth = 0.dp, minHeight = 0.dp)
                                .height(ProgressSegmentButtonHeight)
                        ) {
                            ProgressSegmentLabel(
                                when (r) {
                                    ProfileProgressRange.WEEK -> stringResource(R.string.profile_progress_range_week)
                                    ProfileProgressRange.MONTH -> stringResource(R.string.profile_progress_range_month)
                                    ProfileProgressRange.YEAR -> stringResource(R.string.profile_progress_range_year)
                                }
                            )
                        }
                    }
                }
                val subTabs = listOf(
                    ProfileProgressSubtab.ACTIVITY,
                    ProfileProgressSubtab.INTENSITY,
                    ProfileProgressSubtab.CONSISTENCY,
                    ProfileProgressSubtab.WEEKDAY
                )
                SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                    subTabs.forEachIndexed { i, t ->
                        SegmentedButton(
                            selected = ui.subtab == t,
                            onClick = { vm.setSubtab(t) },
                            shape = SegmentedButtonDefaults.itemShape(i, subTabs.size),
                            modifier = Modifier
                                .defaultMinSize(minWidth = 0.dp, minHeight = 0.dp)
                                .height(ProgressSegmentButtonHeight)
                        ) {
                            ProgressSegmentLabel(
                                when (t) {
                                    ProfileProgressSubtab.ACTIVITY -> stringResource(R.string.profile_progress_sub_activity)
                                    ProfileProgressSubtab.INTENSITY -> stringResource(R.string.profile_progress_sub_intensity)
                                    ProfileProgressSubtab.CONSISTENCY -> stringResource(R.string.profile_progress_sub_consistency)
                                    ProfileProgressSubtab.WEEKDAY -> stringResource(R.string.profile_progress_sub_weekday)
                                }
                            )
                        }
                    }
                }
                when (ui.subtab) {
                    ProfileProgressSubtab.ACTIVITY -> {
                        val ams = listOf(
                            ProfileActivityMetric.WORKOUTS,
                            ProfileActivityMetric.SCORE,
                            ProfileActivityMetric.CALORIES
                        )
                        SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                            ams.forEachIndexed { i, m ->
                                SegmentedButton(
                                    selected = ui.activityMetric == m,
                                    onClick = { vm.setActivityMetric(m) },
                                    shape = SegmentedButtonDefaults.itemShape(i, ams.size),
                                    modifier = Modifier
                                        .defaultMinSize(minWidth = 0.dp, minHeight = 0.dp)
                                        .height(ProgressSegmentButtonHeight)
                                ) {
                                    ProgressSegmentLabel(
                                        when (m) {
                                            ProfileActivityMetric.WORKOUTS -> stringResource(R.string.profile_progress_metric_workouts)
                                            ProfileActivityMetric.SCORE -> stringResource(R.string.profile_progress_metric_score)
                                            ProfileActivityMetric.CALORIES -> stringResource(R.string.profile_progress_metric_calories)
                                        }
                                    )
                                }
                            }
                        }
                    }
                    ProfileProgressSubtab.CONSISTENCY -> {
                        val cms = ConsistencyChartMetric.entries
                        SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                            cms.forEachIndexed { i, m ->
                                SegmentedButton(
                                    selected = ui.consistencyMetric == m,
                                    onClick = { vm.setConsistencyMetric(m) },
                                    shape = SegmentedButtonDefaults.itemShape(i, cms.size),
                                    modifier = Modifier
                                        .defaultMinSize(minWidth = 0.dp, minHeight = 0.dp)
                                        .height(ProgressSegmentButtonHeight)
                                ) {
                                    ProgressSegmentLabel(
                                        when (m) {
                                            ConsistencyChartMetric.DURATION -> stringResource(R.string.profile_progress_consistency_time)
                                            ConsistencyChartMetric.WORKOUTS -> stringResource(R.string.profile_progress_consistency_workouts)
                                            ConsistencyChartMetric.SCORE -> stringResource(R.string.profile_progress_consistency_score)
                                            ConsistencyChartMetric.CALORIES -> stringResource(R.string.profile_progress_consistency_kcal)
                                        }
                                    )
                                }
                            }
                        }
                    }
                    ProfileProgressSubtab.WEEKDAY -> {
                        val wms = WeekdayProgressMetric.entries
                        SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                            wms.forEachIndexed { i, m ->
                                SegmentedButton(
                                    selected = ui.weekdayMetric == m,
                                    onClick = { vm.setWeekdayMetric(m) },
                                    shape = SegmentedButtonDefaults.itemShape(i, wms.size),
                                    modifier = Modifier
                                        .defaultMinSize(minWidth = 0.dp, minHeight = 0.dp)
                                        .height(ProgressSegmentButtonHeight)
                                ) {
                                    ProgressSegmentLabel(
                                        when (m) {
                                            WeekdayProgressMetric.WORKOUTS -> stringResource(R.string.profile_progress_metric_workouts)
                                            WeekdayProgressMetric.SCORE -> stringResource(R.string.profile_progress_metric_score)
                                            WeekdayProgressMetric.CALORIES -> stringResource(R.string.profile_progress_metric_calories)
                                            WeekdayProgressMetric.HOURS -> stringResource(R.string.profile_progress_metric_hours)
                                        }
                                    )
                                }
                            }
                        }
                    }
                    else -> { }
                }
            }
        }
        if (ui.loading) {
            Text(stringResource(R.string.profile_progress_loading))
        } else if (ui.error != null) {
            Text(ui.error!!, color = MaterialTheme.colorScheme.error)
        } else {
            when (ui.subtab) {
                ProfileProgressSubtab.ACTIVITY, ProfileProgressSubtab.INTENSITY -> {
                    val yAxis = when (ui.subtab) {
                        ProfileProgressSubtab.INTENSITY -> stringResource(R.string.profile_progress_chart_y_intensity)
                        ProfileProgressSubtab.ACTIVITY -> when (ui.activityMetric) {
                            ProfileActivityMetric.WORKOUTS -> stringResource(R.string.profile_progress_chart_y_workouts)
                            ProfileActivityMetric.SCORE -> stringResource(R.string.profile_progress_chart_y_score)
                            ProfileActivityMetric.CALORIES -> stringResource(R.string.profile_progress_chart_y_kcal)
                        }
                        else -> ""
                    }
                    val rangeLabel = when (ui.range) {
                        ProfileProgressRange.WEEK -> stringResource(R.string.profile_progress_range_week)
                        ProfileProgressRange.MONTH -> stringResource(R.string.profile_progress_range_month)
                        ProfileProgressRange.YEAR -> stringResource(R.string.profile_progress_range_year)
                    }
                    LazyColumn(
                        verticalArrangement = Arrangement.spacedBy(12.dp),
                        modifier = Modifier
                            .weight(1f)
                            .fillMaxWidth()
                    ) {
                        if (ui.subtab == ProfileProgressSubtab.ACTIVITY &&
                            ui.activityMetric == ProfileActivityMetric.CALORIES &&
                            ui.activityCaloriesSummary != null
                        ) {
                            item {
                                ActivityMetricSummaryCard(
                                    title = stringResource(R.string.profile_progress_calories_card_title),
                                    range = rangeLabel,
                                    s = ui.activityCaloriesSummary!!,
                                    isKcal = true,
                                    isYear = ui.range == ProfileProgressRange.YEAR
                                )
                            }
                        }
                        if (ui.subtab == ProfileProgressSubtab.ACTIVITY &&
                            ui.activityMetric == ProfileActivityMetric.SCORE &&
                            ui.activityScoreSummary != null
                        ) {
                            item {
                                ActivityMetricSummaryCard(
                                    title = stringResource(R.string.profile_progress_score_card_title),
                                    range = rangeLabel,
                                    s = ui.activityScoreSummary!!,
                                    isKcal = false,
                                    isYear = ui.range == ProfileProgressRange.YEAR
                                )
                            }
                        }
                        if (ui.progressPoints.isEmpty()) {
                            item {
                                Text(
                                    stringResource(R.string.profile_progress_no_data),
                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                            }
                        } else {
                            item {
                                ProfileActivityLineChart(
                                    points = ui.progressPoints,
                                    lineColor = MaterialTheme.colorScheme.primary,
                                    yAxisLabel = yAxis
                                )
                            }
                        }
                    }
                }
                ProfileProgressSubtab.CONSISTENCY -> {
                    val m = ui.effectiveConsistencyMetric()
                    val slices = ui.kindDistribution.sortedBy { kindSortIndex(it.kind) }
                    val total = slices.sumOf { s -> m.measure(s.durationMin, s.count, s.score, s.kcal) }
                    if (slices.isEmpty() && ui.totalDurationMin == 0) {
                        Text(
                            stringResource(R.string.profile_progress_no_data),
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    } else {
                        val donut = slices.map { s ->
                            val meas = m.measure(s.durationMin, s.count, s.score, s.kcal)
                            DonutSegment(
                                label = kindTitle(s.kind),
                                value = meas,
                                color = consistencyKindColor(s.kind)
                            )
                        }
                        LazyColumn(
                            verticalArrangement = Arrangement.spacedBy(8.dp),
                            modifier = Modifier
                                .weight(1f)
                                .fillMaxWidth()
                        ) {
                            item {
                                Text(
                                    stringResource(
                                        R.string.profile_progress_consistency_streak,
                                        ui.consistencyActiveBuckets,
                                        ui.consistencyBucketTotal
                                    ),
                                    style = MaterialTheme.typography.labelMedium
                                )
                            }
                            item {
                                val metricTitle = when (m) {
                                    ConsistencyChartMetric.DURATION -> stringResource(R.string.profile_progress_consistency_time)
                                    ConsistencyChartMetric.WORKOUTS -> stringResource(R.string.profile_progress_consistency_workouts)
                                    ConsistencyChartMetric.SCORE -> stringResource(R.string.profile_progress_consistency_score)
                                    ConsistencyChartMetric.CALORIES -> stringResource(R.string.profile_progress_consistency_kcal)
                                }
                                KindDonutChart(
                                    segments = donut,
                                    centerTitle = metricTitle
                                )
                            }
                            items(slices, key = { it.kind }) { s ->
                                val v = m.measure(s.durationMin, s.count, s.score, s.kcal)
                                val rtot = if (total > 0) (v / total).toFloat() else 0f
                                KindRow(
                                    title = kindTitle(s.kind),
                                    ratio = rtot,
                                    line1 = primaryLine(m, s, total),
                                    onClick = { drillKind = s.kind }
                                )
                            }
                        }
                    }
                }
                ProfileProgressSubtab.WEEKDAY -> {
                    val wm = ui.weekdayMetric
                    val yAxis = when (wm) {
                        WeekdayProgressMetric.WORKOUTS -> stringResource(R.string.profile_progress_weekday_y_axis_workouts)
                        WeekdayProgressMetric.SCORE -> stringResource(R.string.profile_progress_weekday_y_axis_score)
                        WeekdayProgressMetric.CALORIES -> stringResource(R.string.profile_progress_weekday_y_axis_kcal)
                        WeekdayProgressMetric.HOURS -> stringResource(R.string.profile_progress_weekday_y_axis_hours)
                    }
                    val pts = ui.weekdayPoints
                    val hasAny = pts.any { p -> p.totalValue(wm) > 0 }
                    if (!hasAny) {
                        Text(
                            stringResource(R.string.profile_progress_no_data),
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    } else {
                        val nonZero = pts.filter { it.averageValue(wm) > 0 }
                        val strongest = nonZero.maxByOrNull { it.averageValue(wm) }
                        val lowest = nonZero.minByOrNull { it.averageValue(wm) }
                        val avgActive = if (nonZero.isNotEmpty()) {
                            nonZero.sumOf { it.averageValue(wm) } / nonZero.size.toDouble()
                        } else {
                            0.0
                        }
                        LazyColumn(
                            verticalArrangement = Arrangement.spacedBy(12.dp),
                            modifier = Modifier
                                .weight(1f)
                                .fillMaxWidth()
                        ) {
                            item {
                                Text(
                                    stringResource(R.string.profile_progress_weekday_summary),
                                    style = MaterialTheme.typography.titleSmall,
                                    fontWeight = FontWeight.SemiBold
                                )
                            }
                            item {
                                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                                    if (strongest != null) {
                                        Text(
                                            stringResource(
                                                R.string.profile_progress_weekday_strongest,
                                                strongest.label,
                                                formatWeekdayMetric(strongest.averageValue(wm), wm)
                                            ),
                                            style = MaterialTheme.typography.labelSmall,
                                            color = MaterialTheme.colorScheme.onSurfaceVariant
                                        )
                                    }
                                    if (lowest != null && (strongest == null || lowest.label != strongest.label)) {
                                        Text(
                                            stringResource(
                                                R.string.profile_progress_weekday_lowest,
                                                lowest.label,
                                                formatWeekdayMetric(lowest.averageValue(wm), wm)
                                            ),
                                            style = MaterialTheme.typography.labelSmall,
                                            color = MaterialTheme.colorScheme.onSurfaceVariant
                                        )
                                    }
                                    if (nonZero.isNotEmpty()) {
                                        Text(
                                            stringResource(
                                                R.string.profile_progress_weekday_avg_active,
                                                formatWeekdayMetric(avgActive, wm)
                                            ),
                                            style = MaterialTheme.typography.labelSmall,
                                            color = MaterialTheme.colorScheme.onSurfaceVariant
                                        )
                                    }
                                }
                            }
                            item {
                                ProfileWeekdayBarChart(
                                    points = pts,
                                    metric = wm,
                                    barColor = MaterialTheme.colorScheme.primary,
                                    yAxisLabel = yAxis
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

private fun formatWeekdayMetric(value: Double, m: WeekdayProgressMetric): String = when (m) {
    WeekdayProgressMetric.WORKOUTS, WeekdayProgressMetric.SCORE -> {
        if (abs(value - value.roundToInt()) < 0.05) {
            "${value.roundToInt()}"
        } else {
            String.format(Locale.US, "%.1f", value)
        }
    }
    WeekdayProgressMetric.CALORIES -> "${value.roundToInt()} kcal"
    WeekdayProgressMetric.HOURS -> String.format(Locale.US, "%.2f h", value)
}

@Composable
private fun ActivityMetricSummaryCard(
    title: String,
    range: String,
    s: ProgressMetricSummary,
    isKcal: Boolean,
    isYear: Boolean
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.4f)
        )
    ) {
        Column(
            Modifier.padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Text(title, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
                Text(range, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Column {
                    Text(stringResource(R.string.profile_progress_total), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Text(
                        if (isKcal) "${s.total.toInt()} kcal" else "${s.total.toInt()}",
                        style = MaterialTheme.typography.titleMedium
                    )
                }
                Column(horizontalAlignment = Alignment.End) {
                    Text(
                        stringResource(R.string.profile_progress_avg_per_workout),
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    Text(
                        if (isKcal) "${s.avgPerWorkout.toInt()} kcal" else "${s.avgPerWorkout.toInt()}",
                        style = MaterialTheme.typography.titleMedium
                    )
                }
            }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Column(Modifier.weight(1f)) {
                    Text(
                        stringResource(R.string.profile_progress_best_day),
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    Text(
                        if (s.bestValue > 0) {
                            if (isKcal) "${s.bestLabel} · ${s.bestValue.toInt()} kcal" else "${s.bestLabel} · ${s.bestValue.toInt()}"
                        } else {
                            stringResource(R.string.profile_progress_dash)
                        },
                        style = MaterialTheme.typography.bodySmall
                    )
                }
                Column(horizontalAlignment = Alignment.End) {
                    Text(
                        stringResource(R.string.profile_progress_streak_label),
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    Text(
                        if (isYear) {
                            stringResource(R.string.profile_progress_dash)
                        } else {
                            stringResource(R.string.profile_progress_streak_d, s.streakDays)
                        },
                        style = MaterialTheme.typography.bodySmall
                    )
                }
            }
            if (s.perMinute > 0) {
                Text(
                    if (isKcal) {
                        stringResource(R.string.profile_progress_efficiency_kcal, s.perMinute)
                    } else {
                        stringResource(R.string.profile_progress_efficiency_score, s.perMinute)
                    },
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }
}

private fun kindSortIndex(kind: String) = when (kind.lowercase()) {
    "strength" -> 0
    "cardio" -> 1
    "sport" -> 2
    else -> 99
}

private fun consistencyKindColor(kind: String) = when (kind.lowercase()) {
    "strength" -> Color(0xFF1E88E5)
    "cardio" -> Color(0xFF43A047)
    "sport" -> Color(0xFFFF9800)
    else -> Color.Gray
}

private fun kindTitle(kind: String) = when (kind.lowercase()) {
    "strength" -> "Strength"
    "cardio" -> "Cardio"
    "sport" -> "Sport"
    else -> kind.replaceFirstChar { c -> c.titlecase() }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun KindRow(
    title: String,
    ratio: Float,
    line1: String,
    onClick: () -> Unit
) {
    Card(
        onClick = onClick,
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.35f)
        ),
        modifier = Modifier.fillMaxWidth()
    ) {
        Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Text(title, style = MaterialTheme.typography.titleSmall)
                Text(line1, style = MaterialTheme.typography.labelMedium)
            }
            LinearProgressIndicator(
                progress = { min(1f, max(0f, ratio)) },
                modifier = Modifier
                    .fillMaxWidth()
                    .height(8.dp)
            )
        }
    }
}

private fun primaryLine(m: ConsistencyChartMetric, s: KindSlice, total: Double): String {
    val v = m.measure(s.durationMin, s.count, s.score, s.kcal)
    val pct = if (total > 0) ((v / total) * 100.0).roundToInt() else 0
    return "${formatMeasure(m, s)} · $pct%"
}

private fun formatMeasure(m: ConsistencyChartMetric, s: KindSlice): String = when (m) {
    ConsistencyChartMetric.DURATION -> formatMinutes(s.durationMin)
    ConsistencyChartMetric.WORKOUTS -> if (s.count == 1) "1" else "${s.count}"
    ConsistencyChartMetric.SCORE -> "${formatNum(s.score)} pts"
    ConsistencyChartMetric.CALORIES -> "${formatNum(s.kcal)} kcal"
}

private fun formatMinutes(mins: Int): String {
    if (mins <= 0) return "0m"
    val h = mins / 60
    val r = mins % 60
    return if (h > 0) (if (r > 0) "${h}h ${r}m" else "${h}h") else "${r}m"
}

private fun formatNum(x: Double): String {
    val r = kotlin.math.round(x)
    if (kotlin.math.abs(x - r) < 0.05) return r.toInt().toString()
    return String.format(java.util.Locale.US, "%.1f", x)
}

