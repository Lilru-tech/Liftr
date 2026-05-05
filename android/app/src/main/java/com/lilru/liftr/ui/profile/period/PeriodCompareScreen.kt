package com.lilru.liftr.ui.profile.period

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Switch
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.MenuAnchorType
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import kotlin.math.round
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.lilru.liftr.R
import com.lilru.liftr.prefs.LiftrPreferences
import com.lilru.liftr.ui.components.LiftrBackTopBar
import com.lilru.liftr.ui.theme.liftrAppBackgroundGradient
import io.github.jan.supabase.SupabaseClient
import com.lilru.liftr.ui.add.ProfileLite
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.ChronoUnit
import java.text.NumberFormat
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlin.math.max
import kotlin.math.roundToInt

private enum class DatePickTarget { A_START, A_END, B_START, B_END }

private fun inclusiveDayCount(start: LocalDate, endInclusive: LocalDate): Long =
    ChronoUnit.DAYS.between(start, endInclusive) + 1

private fun periodCompareLegendBLabel(
    viewerUserId: String,
    userBId: String?,
    followees: List<ProfileLite>,
    periodBStart: LocalDate,
    periodBEndInclusive: LocalDate,
    fmt: DateTimeFormatter,
    resources: android.content.res.Resources
): String {
    val id = userBId?.takeIf { it.isNotBlank() } ?: viewerUserId
    return if (id == viewerUserId) {
        resources.getString(
            R.string.period_compare_legend_b_period_dates,
            periodBStart.format(fmt),
            periodBEndInclusive.format(fmt)
        )
    } else {
        val who = followees.find { it.userId == id }?.username?.takeIf { !it.isNullOrBlank() }
            ?: id.take(8)
        resources.getString(R.string.period_compare_legend_b_user, who)
    }
}

private enum class PeriodCompareOverviewMetric {
    OVERALL,
    WORKOUTS,
    TIME,
    CALORIES,
    SCORE,
    DISTANCE,
    VOLUME
}

private fun overallBalancePcts(a: PeriodSummaryUi, b: PeriodSummaryUi): Pair<Double, Double> {
    val pairs = listOf(
        a.workoutCount.toDouble() to b.workoutCount.toDouble(),
        a.durationMin.toDouble() to b.durationMin.toDouble(),
        a.caloriesKcal to b.caloriesKcal,
        a.score to b.score
    )
    var sumA = 0.0
    for ((x, y) in pairs) {
        val t = x + y
        sumA += if (t <= 0) 50.0 else 100.0 * x / t
    }
    val avgA = sumA / pairs.size
    return avgA to (100.0 - avgA)
}

private fun availableOverviewMetrics(ra: PeriodSideUi, rb: PeriodSideUi): List<PeriodCompareOverviewMetric> {
    return buildList {
        add(PeriodCompareOverviewMetric.OVERALL)
        add(PeriodCompareOverviewMetric.WORKOUTS)
        add(PeriodCompareOverviewMetric.TIME)
        add(PeriodCompareOverviewMetric.CALORIES)
        add(PeriodCompareOverviewMetric.SCORE)
        if (ra.summary.distanceKm > 0 || rb.summary.distanceKm > 0) {
            add(PeriodCompareOverviewMetric.DISTANCE)
        }
        if (ra.summary.volumeKg > 0 || rb.summary.volumeKg > 0) {
            add(PeriodCompareOverviewMetric.VOLUME)
        }
    }
}

private fun overviewMetricValues(
    ra: PeriodSideUi,
    rb: PeriodSideUi,
    m: PeriodCompareOverviewMetric
): Pair<Double, Double> {
    val a = ra.summary
    val b = rb.summary
    return when (m) {
        PeriodCompareOverviewMetric.OVERALL -> overallBalancePcts(a, b)
        PeriodCompareOverviewMetric.WORKOUTS -> a.workoutCount.toDouble() to b.workoutCount.toDouble()
        PeriodCompareOverviewMetric.TIME -> a.durationMin.toDouble() to b.durationMin.toDouble()
        PeriodCompareOverviewMetric.CALORIES -> a.caloriesKcal to b.caloriesKcal
        PeriodCompareOverviewMetric.SCORE -> a.score to b.score
        PeriodCompareOverviewMetric.DISTANCE -> a.distanceKm to b.distanceKm
        PeriodCompareOverviewMetric.VOLUME -> a.volumeKg to b.volumeKg
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PeriodCompareScreen(
    supabase: SupabaseClient,
    viewerUserId: String,
    onBack: () -> Unit,
    modifier: Modifier = Modifier
) {
    val vm: PeriodCompareViewModel = viewModel(
        factory = PeriodCompareViewModelFactory(supabase, viewerUserId)
    )
    val ui by vm.uiState.collectAsStateWithLifecycle()
    val context = LocalContext.current
    val locale = context.resources.configuration.locales[0] ?: Locale.getDefault()
    val backgroundThemeId = remember(context) { LiftrPreferences.backgroundTheme(context) }
    var overviewMetric by remember { mutableStateOf(PeriodCompareOverviewMetric.OVERALL) }
    val zone = ui.localZone
    val fmt = remember(locale) { DateTimeFormatter.ofPattern("MMM d, yyyy", locale) }

    var kindMenuExpanded by remember { mutableStateOf(false) }
    var userMenuExpanded by remember { mutableStateOf(false) }
    var datePickTarget by remember { mutableStateOf<DatePickTarget?>(null) }
    var figuresPerDay by remember { mutableStateOf(false) }

    fun openPicker(t: DatePickTarget) {
        datePickTarget = t
    }

    fun millisToLocalDate(ms: Long): LocalDate =
        Instant.ofEpochMilli(ms).atZone(zone).toLocalDate()

    val kindLabel = when (ui.kind) {
        PeriodCompareKind.ALL -> stringResource(R.string.period_compare_kind_all)
        PeriodCompareKind.STRENGTH -> stringResource(R.string.period_compare_kind_strength)
        PeriodCompareKind.CARDIO -> stringResource(R.string.period_compare_kind_cardio)
        PeriodCompareKind.SPORT -> stringResource(R.string.period_compare_kind_sport)
    }

    val selfLabel = stringResource(R.string.period_compare_user_b_self)
    val userBLabel = remember(ui.userBId, ui.followees, selfLabel, viewerUserId) {
        val id = ui.userBId ?: viewerUserId
        if (id == viewerUserId) selfLabel
        else ui.followees.find { it.userId == id }?.username?.takeIf { !it.isNullOrBlank() }
            ?: id.take(8)
    }
    val comparingWithSelf = remember(ui.userBId, viewerUserId) {
        (ui.userBId?.takeIf { it.isNotBlank() } ?: viewerUserId) == viewerUserId
    }
    val presetSevenLabel = if (comparingWithSelf) stringResource(R.string.period_compare_preset_seven) else stringResource(R.string.period_compare_preset_seven_cross_user)
    val presetWeekLabel = if (comparingWithSelf) stringResource(R.string.period_compare_preset_week) else stringResource(R.string.period_compare_preset_week_cross_user)
    val presetTwentyEightLabel = if (comparingWithSelf) stringResource(R.string.period_compare_preset_twenty_eight) else stringResource(R.string.period_compare_preset_twenty_eight_cross_user)

    val errorText = when (ui.error) {
        "invalid_range" -> stringResource(R.string.period_compare_invalid_range)
        null -> null
        else -> ui.error
    }

    val ra = ui.resultA
    val rb = ui.resultB
    LaunchedEffect(ra, rb) {
        val r1 = ra ?: return@LaunchedEffect
        val r2 = rb ?: return@LaunchedEffect
        val avail = availableOverviewMetrics(r1, r2)
        if (overviewMetric !in avail) {
            overviewMetric = avail.first()
        }
    }

    val resources = LocalContext.current.resources
    val chartLegendBLabel = remember(
        viewerUserId,
        ui.userBId,
        ui.periodBStart,
        ui.periodBEndInclusive,
        ui.followees,
        fmt
    ) {
        periodCompareLegendBLabel(
            viewerUserId = viewerUserId,
            userBId = ui.userBId,
            followees = ui.followees,
            periodBStart = ui.periodBStart,
            periodBEndInclusive = ui.periodBEndInclusive,
            fmt = fmt,
            resources = resources
        )
    }

    Column(
        modifier = modifier
            .fillMaxSize()
            .liftrAppBackgroundGradient(backgroundThemeId)
            .statusBarsPadding()
            .padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        LiftrBackTopBar(onBack = onBack)
        Text(
            stringResource(R.string.period_compare_title),
            style = MaterialTheme.typography.titleLarge
        )

        LazyColumn(
            verticalArrangement = Arrangement.spacedBy(10.dp),
            modifier = Modifier.weight(1f)
        ) {
            item {
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    shape = RoundedCornerShape(16.dp),
                    colors = CardDefaults.cardColors(
                        containerColor = Color.White.copy(alpha = 0.38f)
                    ),
                    border = BorderStroke(0.8.dp, Color.White.copy(alpha = 0.22f)),
                    elevation = CardDefaults.cardElevation(defaultElevation = 2.dp)
                ) {
                    Column(
                        modifier = Modifier.padding(12.dp),
                        verticalArrangement = Arrangement.spacedBy(12.dp)
                    ) {
                        ExposedDropdownMenuBox(
                            expanded = kindMenuExpanded,
                            onExpandedChange = { kindMenuExpanded = it },
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            OutlinedTextField(
                                value = kindLabel,
                                onValueChange = {},
                                readOnly = true,
                                singleLine = true,
                                label = { Text(stringResource(R.string.period_compare_kind)) },
                                trailingIcon = {
                                    ExposedDropdownMenuDefaults.TrailingIcon(expanded = kindMenuExpanded)
                                },
                                modifier = Modifier
                                    .menuAnchor(type = MenuAnchorType.PrimaryNotEditable, enabled = true)
                                    .fillMaxWidth()
                            )
                            ExposedDropdownMenu(
                                expanded = kindMenuExpanded,
                                onDismissRequest = { kindMenuExpanded = false }
                            ) {
                                PeriodCompareKind.entries.forEach { k ->
                                    val label = when (k) {
                                        PeriodCompareKind.ALL -> stringResource(R.string.period_compare_kind_all)
                                        PeriodCompareKind.STRENGTH -> stringResource(R.string.period_compare_kind_strength)
                                        PeriodCompareKind.CARDIO -> stringResource(R.string.period_compare_kind_cardio)
                                        PeriodCompareKind.SPORT -> stringResource(R.string.period_compare_kind_sport)
                                    }
                                    DropdownMenuItem(
                                        text = { Text(label) },
                                        onClick = {
                                            vm.setKind(k)
                                            kindMenuExpanded = false
                                        }
                                    )
                                }
                            }
                        }
                        HorizontalDivider(color = MaterialTheme.colorScheme.outline.copy(alpha = 0.2f))
                        ExposedDropdownMenuBox(
                            expanded = userMenuExpanded,
                            onExpandedChange = { userMenuExpanded = it },
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            OutlinedTextField(
                                value = userBLabel,
                                onValueChange = {},
                                readOnly = true,
                                singleLine = true,
                                label = { Text(stringResource(R.string.period_compare_user_b)) },
                                trailingIcon = {
                                    ExposedDropdownMenuDefaults.TrailingIcon(expanded = userMenuExpanded)
                                },
                                modifier = Modifier
                                    .menuAnchor(type = MenuAnchorType.PrimaryNotEditable, enabled = true)
                                    .fillMaxWidth()
                            )
                            ExposedDropdownMenu(
                                expanded = userMenuExpanded,
                                onDismissRequest = { userMenuExpanded = false }
                            ) {
                                DropdownMenuItem(
                                    text = { Text(selfLabel) },
                                    onClick = {
                                        vm.setUserB(viewerUserId)
                                        userMenuExpanded = false
                                    }
                                )
                                ui.followees.forEach { p ->
                                    val pl = p.username?.takeIf { it.isNotBlank() } ?: p.userId.take(8)
                                    DropdownMenuItem(
                                        text = { Text(pl) },
                                        onClick = {
                                            vm.setUserB(p.userId)
                                            userMenuExpanded = false
                                        }
                                    )
                                }
                            }
                        }
                        Text(
                            stringResource(R.string.period_compare_social_note),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                        if (!comparingWithSelf) {
                            Text(
                                stringResource(R.string.period_compare_cross_user_date_hint),
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.tertiary
                            )
                        }
                        HorizontalDivider(color = MaterialTheme.colorScheme.outline.copy(alpha = 0.2f))
                        Text(
                            stringResource(R.string.period_compare_presets_label),
                            style = MaterialTheme.typography.labelLarge,
                            fontWeight = FontWeight.SemiBold,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                        LazyRow(
                            horizontalArrangement = Arrangement.spacedBy(8.dp)
                        ) {
                            item {
                                FilterChip(
                                    selected = false,
                                    onClick = {
                                        vm.applyDatePreset(
                                            PeriodCompareDatePreset.SEVEN_VS_PRIOR_SEVEN,
                                            locale,
                                            comparingWithSelf
                                        )
                                    },
                                    label = {
                                        Text(
                                            presetSevenLabel,
                                            style = MaterialTheme.typography.labelMedium
                                        )
                                    }
                                )
                            }
                            item {
                                FilterChip(
                                    selected = false,
                                    onClick = {
                                        vm.applyDatePreset(
                                            PeriodCompareDatePreset.WEEK_THIS_VS_ALIGNED_PRIOR,
                                            locale,
                                            comparingWithSelf
                                        )
                                    },
                                    label = {
                                        Text(
                                            presetWeekLabel,
                                            style = MaterialTheme.typography.labelMedium
                                        )
                                    }
                                )
                            }
                            item {
                                FilterChip(
                                    selected = false,
                                    onClick = {
                                        vm.applyDatePreset(
                                            PeriodCompareDatePreset.TWENTY_EIGHT_VS_PRIOR_TWENTY_EIGHT,
                                            locale,
                                            comparingWithSelf
                                        )
                                    },
                                    label = {
                                        Text(
                                            presetTwentyEightLabel,
                                            style = MaterialTheme.typography.labelMedium
                                        )
                                    }
                                )
                            }
                        }
                        HorizontalDivider(color = MaterialTheme.colorScheme.outline.copy(alpha = 0.2f))
                        Text(
                            stringResource(R.string.period_compare_period_a),
                            style = MaterialTheme.typography.labelLarge,
                            fontWeight = FontWeight.SemiBold,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.spacedBy(8.dp)
                        ) {
                            OutlinedTextField(
                                value = ui.periodAStart.format(fmt),
                                onValueChange = {},
                                readOnly = true,
                                label = { Text(stringResource(R.string.period_compare_start)) },
                                modifier = Modifier
                                    .weight(1f),
                                enabled = !ui.loading
                            )
                            OutlinedTextField(
                                value = ui.periodAEndInclusive.format(fmt),
                                onValueChange = {},
                                readOnly = true,
                                label = { Text(stringResource(R.string.period_compare_end)) },
                                modifier = Modifier
                                    .weight(1f),
                                enabled = !ui.loading
                            )
                        }
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            TextButton(onClick = { openPicker(DatePickTarget.A_START) }) {
                                Text(stringResource(R.string.period_compare_start))
                            }
                            TextButton(onClick = { openPicker(DatePickTarget.A_END) }) {
                                Text(stringResource(R.string.period_compare_end))
                            }
                        }
                        HorizontalDivider(color = MaterialTheme.colorScheme.outline.copy(alpha = 0.2f))
                        Text(
                            stringResource(R.string.period_compare_period_b),
                            style = MaterialTheme.typography.labelLarge,
                            fontWeight = FontWeight.SemiBold,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.spacedBy(8.dp)
                        ) {
                            OutlinedTextField(
                                value = ui.periodBStart.format(fmt),
                                onValueChange = {},
                                readOnly = true,
                                label = { Text(stringResource(R.string.period_compare_start)) },
                                modifier = Modifier
                                    .weight(1f),
                                enabled = !ui.loading
                            )
                            OutlinedTextField(
                                value = ui.periodBEndInclusive.format(fmt),
                                onValueChange = {},
                                readOnly = true,
                                label = { Text(stringResource(R.string.period_compare_end)) },
                                modifier = Modifier
                                    .weight(1f),
                                enabled = !ui.loading
                            )
                        }
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            TextButton(onClick = { openPicker(DatePickTarget.B_START) }) {
                                Text(stringResource(R.string.period_compare_start))
                            }
                            TextButton(onClick = { openPicker(DatePickTarget.B_END) }) {
                                Text(stringResource(R.string.period_compare_end))
                            }
                        }
                        FilledTonalButton(
                            onClick = { vm.compare() },
                            enabled = !ui.loading && !ui.loadingFollowees,
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            Text(
                                if (ui.loading) {
                                    stringResource(R.string.period_compare_loading)
                                } else {
                                    stringResource(R.string.period_compare_run)
                                }
                            )
                        }
                    }
                }
            }

            if (errorText != null) {
                item {
                    Text(errorText, color = MaterialTheme.colorScheme.error)
                }
            }

            if (ra != null && rb != null) {
                val resA = ra
                val resB = rb
                val daysA = inclusiveDayCount(ui.periodAStart, ui.periodAEndInclusive).coerceAtLeast(1L)
                val daysB = inclusiveDayCount(ui.periodBStart, ui.periodBEndInclusive).coerceAtLeast(1L)
                val durationMismatch = daysA != daysB
                val wa = resA.summary.workoutCount
                val wb = resB.summary.workoutCount
                if (durationMismatch) {
                    item {
                        Text(
                            stringResource(R.string.period_compare_duration_mismatch),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.tertiary
                        )
                    }
                }
                if (wa == 0 && wb == 0) {
                    item {
                        Text(
                            stringResource(R.string.period_compare_empty_both),
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                } else {
                    if (wa == 0) {
                        item {
                            Text(
                                stringResource(R.string.period_compare_empty_period_a),
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    }
                    if (wb == 0) {
                        item {
                            Text(
                                stringResource(R.string.period_compare_empty_period_b),
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    }
                }
                item {
                    Text(
                        stringResource(R.string.period_compare_chart_overview),
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.SemiBold
                    )
                }
                item {
                    val primary = MaterialTheme.colorScheme.primary
                    val tertiary = MaterialTheme.colorScheme.tertiary
                    val sideALegend = stringResource(R.string.period_compare_side_a)
                    val nfInt = remember(locale) { NumberFormat.getIntegerInstance(locale) }
                    val avail = availableOverviewMetrics(resA, resB)
                    val metricTitle = when (overviewMetric) {
                        PeriodCompareOverviewMetric.OVERALL -> stringResource(R.string.period_compare_overall)
                        PeriodCompareOverviewMetric.WORKOUTS -> stringResource(R.string.profile_progress_metric_workouts)
                        PeriodCompareOverviewMetric.TIME -> stringResource(R.string.period_compare_summary_time)
                        PeriodCompareOverviewMetric.CALORIES -> stringResource(R.string.profile_progress_metric_calories)
                        PeriodCompareOverviewMetric.SCORE -> stringResource(R.string.profile_progress_metric_score)
                        PeriodCompareOverviewMetric.DISTANCE -> "km"
                        PeriodCompareOverviewMetric.VOLUME -> stringResource(R.string.period_compare_figures_volume_abbr)
                    }
                    val (va, vb) = overviewMetricValues(resA, resB, overviewMetric)
                    val formatFn: (Double) -> String = when (overviewMetric) {
                        PeriodCompareOverviewMetric.OVERALL -> {
                            { v: Double -> "${round(v).toInt()}%" }
                        }
                        PeriodCompareOverviewMetric.WORKOUTS,
                        PeriodCompareOverviewMetric.TIME -> {
                            { v: Double -> nfInt.format(v.roundToInt()) }
                        }
                        PeriodCompareOverviewMetric.CALORIES,
                        PeriodCompareOverviewMetric.SCORE,
                        PeriodCompareOverviewMetric.VOLUME -> {
                            { v: Double -> fmtNum(v, locale, 1) }
                        }
                        PeriodCompareOverviewMetric.DISTANCE -> {
                            { v: Double -> fmtNum(v, locale, 2) }
                        }
                    }
                    Card(
                        modifier = Modifier.fillMaxWidth(),
                        colors = CardDefaults.cardColors(
                            containerColor = MaterialTheme.colorScheme.surface.copy(alpha = 0.94f)
                        ),
                        shape = RoundedCornerShape(16.dp)
                    ) {
                        Column(
                            Modifier.padding(12.dp),
                            verticalArrangement = Arrangement.spacedBy(10.dp)
                        ) {
                            Text(
                                stringResource(R.string.period_compare_overview_pick_metric),
                                style = MaterialTheme.typography.labelMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                            LazyRow(
                                horizontalArrangement = Arrangement.spacedBy(8.dp)
                            ) {
                                items(avail, key = { it.name }) { m ->
                                    val label = when (m) {
                                        PeriodCompareOverviewMetric.OVERALL -> stringResource(R.string.period_compare_overall)
                                        PeriodCompareOverviewMetric.WORKOUTS -> stringResource(R.string.profile_progress_metric_workouts)
                                        PeriodCompareOverviewMetric.TIME -> stringResource(R.string.period_compare_summary_time)
                                        PeriodCompareOverviewMetric.CALORIES -> stringResource(R.string.profile_progress_metric_calories)
                                        PeriodCompareOverviewMetric.SCORE -> stringResource(R.string.profile_progress_metric_score)
                                        PeriodCompareOverviewMetric.DISTANCE -> "km"
                                        PeriodCompareOverviewMetric.VOLUME -> stringResource(R.string.period_compare_figures_volume_abbr)
                                    }
                                    FilterChip(
                                        selected = overviewMetric == m,
                                        onClick = { overviewMetric = m },
                                        label = { Text(label, style = MaterialTheme.typography.labelMedium) }
                                    )
                                }
                            }
                            PeriodCompareChartLegend(
                                colorA = primary,
                                colorB = tertiary,
                                labelA = sideALegend,
                                labelB = chartLegendBLabel
                            )
                            PeriodCompareSingleMetricBarChart(
                                title = metricTitle,
                                valueA = va,
                                valueB = vb,
                                formatValue = formatFn,
                                colorA = primary,
                                colorB = tertiary
                            )
                            if (overviewMetric == PeriodCompareOverviewMetric.OVERALL) {
                                Text(
                                    stringResource(R.string.period_compare_overall_hint),
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                            }
                        }
                    }
                }
                item {
                    val merged = mergeBreakdownWorkouts(resA.breakdown, resB.breakdown)
                    if (merged.isNotEmpty()) {
                        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            Text(
                                stringResource(R.string.period_compare_chart_by_type),
                                style = MaterialTheme.typography.titleSmall,
                                fontWeight = FontWeight.SemiBold
                            )
                            Card(
                                modifier = Modifier.fillMaxWidth(),
                                colors = CardDefaults.cardColors(
                                    containerColor = MaterialTheme.colorScheme.surface.copy(alpha = 0.94f)
                                ),
                                shape = RoundedCornerShape(16.dp)
                            ) {
                                Column(Modifier.padding(12.dp)) {
                                    PeriodCompareBreakdownPctSideBySide(
                                        rows = merged,
                                        colorA = MaterialTheme.colorScheme.primary,
                                        colorB = MaterialTheme.colorScheme.tertiary,
                                        legendA = stringResource(R.string.period_compare_side_a),
                                        legendB = chartLegendBLabel,
                                        letterA = stringResource(R.string.period_compare_letter_a),
                                        letterB = stringResource(R.string.period_compare_letter_b),
                                        workoutsLabel = stringResource(R.string.period_compare_summary_workouts)
                                    )
                                }
                            }
                            Text(
                                stringResource(R.string.period_compare_breakdown_mix_hint),
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    }
                }
                item {
                    Text(
                        stringResource(R.string.period_compare_figures),
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.SemiBold
                    )
                }
                item {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        Text(
                            stringResource(R.string.period_compare_per_day),
                            style = MaterialTheme.typography.bodyMedium
                        )
                        Switch(
                            checked = figuresPerDay,
                            onCheckedChange = { figuresPerDay = it }
                        )
                    }
                }
                item {
                    FiguresCompareVisual(
                        a = resA.summary,
                        b = resB.summary,
                        locale = locale,
                        colorA = MaterialTheme.colorScheme.primary,
                        colorB = MaterialTheme.colorScheme.tertiary,
                        perDay = figuresPerDay,
                        daysA = daysA,
                        daysB = daysB
                    )
                }
                item {
                    Text(
                        stringResource(R.string.period_compare_breakdown_detail),
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.SemiBold
                    )
                }
                item {
                    BreakdownMergedDetailCard(
                        rowsA = resA.breakdown,
                        rowsB = resB.breakdown,
                        locale = locale
                    )
                }
                item {
                    Text(
                        stringResource(R.string.period_compare_breakdown_detail_footer),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
        }
    }

    val target = datePickTarget
    if (target != null) {
        val initial = when (target) {
            DatePickTarget.A_START -> ui.periodAStart
            DatePickTarget.A_END -> ui.periodAEndInclusive
            DatePickTarget.B_START -> ui.periodBStart
            DatePickTarget.B_END -> ui.periodBEndInclusive
        }
        val initialMillis = initial.atStartOfDay(zone).toInstant().toEpochMilli()
        val state = rememberDatePickerState(initialSelectedDateMillis = initialMillis)
        DatePickerDialog(
            onDismissRequest = { datePickTarget = null },
            confirmButton = {
                TextButton(
                    onClick = {
                        state.selectedDateMillis?.let { ms ->
                            val d = millisToLocalDate(ms)
                            when (target) {
                                DatePickTarget.A_START -> vm.setPeriodAStart(d)
                                DatePickTarget.A_END -> vm.setPeriodAEndInclusive(d)
                                DatePickTarget.B_START -> vm.setPeriodBStart(d)
                                DatePickTarget.B_END -> vm.setPeriodBEndInclusive(d)
                            }
                        }
                        datePickTarget = null
                    }
                ) { Text(stringResource(R.string.auth_ok)) }
            },
            dismissButton = {
                TextButton(onClick = { datePickTarget = null }) {
                    Text(stringResource(R.string.goals_delete_cancel))
                }
            }
        ) {
            DatePicker(state = state)
        }
    }
}

@Composable
private fun FiguresCompareVisual(
    a: PeriodSummaryUi,
    b: PeriodSummaryUi,
    locale: Locale,
    colorA: Color,
    colorB: Color,
    perDay: Boolean,
    daysA: Long,
    daysB: Long
) {
    val nfInt = remember(locale) { NumberFormat.getIntegerInstance(locale) }
    val sa = if (perDay) 1.0 / daysA.toDouble() else 1.0
    val sb = if (perDay) 1.0 / daysB.toDouble() else 1.0
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surface.copy(alpha = 0.94f)
        ),
        shape = RoundedCornerShape(16.dp)
    ) {
        Column(
            Modifier.padding(14.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            FigureSplitRow(
                label = stringResource(R.string.period_compare_summary_workouts),
                valueA = a.workoutCount.toDouble() * sa,
                valueB = b.workoutCount.toDouble() * sb,
                format = { nfInt.format(it.roundToInt()) },
                colorA = colorA,
                colorB = colorB,
                deltaText = periodCompareDeltaLabel(
                    a.workoutCount.toDouble() * sa,
                    b.workoutCount.toDouble() * sb,
                    locale
                )
            )
            FigureSplitRow(
                label = stringResource(R.string.period_compare_summary_time),
                valueA = a.durationMin.toDouble() * sa,
                valueB = b.durationMin.toDouble() * sb,
                format = { nfInt.format(it.roundToInt()) },
                colorA = colorA,
                colorB = colorB,
                deltaText = periodCompareDeltaLabel(
                    a.durationMin.toDouble() * sa,
                    b.durationMin.toDouble() * sb,
                    locale
                )
            )
            FigureSplitRow(
                label = stringResource(R.string.period_compare_summary_kcal),
                valueA = a.caloriesKcal * sa,
                valueB = b.caloriesKcal * sb,
                format = { fmtNum(it, locale, 1) },
                colorA = colorA,
                colorB = colorB,
                deltaText = periodCompareDeltaLabel(
                    a.caloriesKcal * sa,
                    b.caloriesKcal * sb,
                    locale
                )
            )
            FigureSplitRow(
                label = stringResource(R.string.period_compare_summary_score),
                valueA = a.score * sa,
                valueB = b.score * sb,
                format = { fmtNum(it, locale, 1) },
                colorA = colorA,
                colorB = colorB,
                deltaText = periodCompareDeltaLabel(a.score * sa, b.score * sb, locale)
            )
            if (a.distanceKm > 0 || b.distanceKm > 0) {
                FigureSplitRow(
                    label = "km",
                    valueA = a.distanceKm * sa,
                    valueB = b.distanceKm * sb,
                    format = { fmtNum(it, locale, 2) },
                    colorA = colorA,
                    colorB = colorB,
                    deltaText = periodCompareDeltaLabel(
                        a.distanceKm * sa,
                        b.distanceKm * sb,
                        locale
                    )
                )
            }
            if (a.volumeKg > 0 || b.volumeKg > 0) {
                FigureSplitRow(
                    label = stringResource(R.string.period_compare_figures_volume_abbr),
                    valueA = a.volumeKg * sa,
                    valueB = b.volumeKg * sb,
                    format = { fmtNum(it, locale, 1) },
                    colorA = colorA,
                    colorB = colorB,
                    deltaText = periodCompareDeltaLabel(
                        a.volumeKg * sa,
                        b.volumeKg * sb,
                        locale
                    )
                )
            }
            if (perDay) {
                Text(
                    stringResource(R.string.period_compare_figures_per_day_hint),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            Text(
                stringResource(R.string.period_compare_figures_split_hint),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

@Composable
private fun periodCompareDeltaLabel(va: Double, vb: Double, locale: Locale): String? {
    if (va <= 0.0 && vb <= 0.0) return null
    if (va <= 0.0) {
        return stringResource(R.string.period_compare_delta_new)
    }
    val pct = 100.0 * (vb - va) / va
    val s = String.format(locale, "%+.0f%%", pct)
    return stringResource(R.string.period_compare_delta_b_vs_a, s)
}

@Composable
private fun FigureSplitRow(
    label: String,
    valueA: Double,
    valueB: Double,
    format: (Double) -> String,
    colorA: Color,
    colorB: Color,
    deltaText: String? = null
) {
    val sum = max(valueA + valueB, 1e-9)
    val fracA = (valueA / sum).toFloat().coerceIn(0f, 1f)
    val track = MaterialTheme.colorScheme.outline.copy(alpha = 0.18f)
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(
            label,
            style = MaterialTheme.typography.labelLarge,
            fontWeight = FontWeight.SemiBold
        )
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Text(
                format(valueA),
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold,
                color = colorA,
                maxLines = 1,
                modifier = Modifier.width(72.dp)
            )
            Box(
                modifier = Modifier
                    .weight(1f)
                    .height(12.dp)
                    .clip(RoundedCornerShape(6.dp))
                    .background(track)
            ) {
                Row(Modifier.fillMaxSize()) {
                    val wA = fracA.coerceIn(0.001f, 0.999f)
                    Box(
                        modifier = Modifier
                            .fillMaxHeight()
                            .weight(wA)
                            .background(colorA)
                    )
                    Box(
                        modifier = Modifier
                            .fillMaxHeight()
                            .weight(1f - wA)
                            .background(colorB)
                    )
                }
            }
            Text(
                format(valueB),
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold,
                color = colorB,
                maxLines = 1,
                modifier = Modifier.width(72.dp)
            )
        }
        if (deltaText != null) {
            Text(
                deltaText,
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

@Composable
private fun BreakdownMergedDetailCard(
    rowsA: List<BreakdownRowUi>,
    rowsB: List<BreakdownRowUi>,
    locale: Locale
) {
    val keys = remember(rowsA, rowsB) {
        (rowsA.map { it.label } + rowsB.map { it.label }).distinct().sorted()
    }
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surface.copy(alpha = 0.94f)
        ),
        shape = RoundedCornerShape(16.dp)
    ) {
        Column(Modifier.padding(12.dp)) {
            if (keys.isEmpty()) {
                Text(
                    stringResource(R.string.period_compare_empty),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            } else {
                keys.forEachIndexed { idx, key ->
                    if (idx > 0) {
                        HorizontalDivider(
                            Modifier.padding(vertical = 10.dp),
                            color = MaterialTheme.colorScheme.outline.copy(alpha = 0.22f)
                        )
                    }
                    val ra = rowsA.find { it.label == key }
                    val rb = rowsB.find { it.label == key }
                    val title = key.replaceFirstChar { ch ->
                        if (ch.isLowerCase()) ch.titlecase(locale) else ch.toString()
                    }
                    Text(
                        title,
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.SemiBold
                    )
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(top = 8.dp),
                        horizontalArrangement = Arrangement.spacedBy(12.dp)
                    ) {
                        BreakdownMergedDetailColumn(
                            columnTitle = stringResource(R.string.period_compare_side_a),
                            row = ra,
                            locale = locale,
                            modifier = Modifier.weight(1f)
                        )
                        BreakdownMergedDetailColumn(
                            columnTitle = stringResource(R.string.period_compare_side_b),
                            row = rb,
                            locale = locale,
                            modifier = Modifier.weight(1f)
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun BreakdownMergedDetailColumn(
    columnTitle: String,
    row: BreakdownRowUi?,
    locale: Locale,
    modifier: Modifier = Modifier
) {
    Column(modifier) {
        Text(
            columnTitle,
            style = MaterialTheme.typography.labelMedium,
            fontWeight = FontWeight.SemiBold,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        if (row == null) {
            Text(
                "—",
                style = MaterialTheme.typography.bodySmall,
                modifier = Modifier.padding(top = 4.dp)
            )
        } else {
            Text(
                "${row.workoutCount} · ${row.durationMin} min",
                style = MaterialTheme.typography.bodySmall,
                modifier = Modifier.padding(top = 4.dp)
            )
            Text(
                "${stringResource(R.string.period_compare_summary_kcal)} ${fmtNum(row.caloriesKcal, locale, 1)} · " +
                    "${stringResource(R.string.period_compare_summary_score)} ${fmtNum(row.score, locale, 1)}",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(top = 2.dp)
            )
        }
    }
}

private fun fmtNum(n: Double, locale: Locale, decimals: Int): String {
    val nf = java.text.NumberFormat.getNumberInstance(locale).apply {
        minimumFractionDigits = decimals
        maximumFractionDigits = decimals
    }
    return nf.format(n)
}
