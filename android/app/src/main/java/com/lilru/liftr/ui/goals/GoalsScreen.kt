package com.lilru.liftr.ui.goals

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.lilru.liftr.R
import io.github.jan.supabase.SupabaseClient
import kotlin.math.min
import kotlin.math.roundToInt

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun GoalsScreen(
    supabase: SupabaseClient,
    targetUserId: String,
    viewedUsername: String,
    onBack: () -> Unit,
    modifier: Modifier = Modifier
) {
    val vm: GoalsViewModel = viewModel(factory = GoalsViewModelFactory(supabase, targetUserId))
    val ui by vm.uiState.collectAsStateWithLifecycle()
    var showNew by remember { mutableStateOf(false) }
    var goalForContrib by remember { mutableStateOf<GoalRowUi?>(null) }
    if (goalForContrib != null) {
        GoalContributionsScreen(
            goal = goalForContrib!!,
            vm = vm,
            onBack = { goalForContrib = null },
            modifier = modifier
        )
        return
    }
    val newSheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)

    Column(
        modifier = modifier
            .fillMaxSize()
            .statusBarsPadding()
            .padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        // Barra iOS: flecha atrás a la izquierda y + a la derecha, misma fila
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            IconButton(onClick = onBack) {
                Icon(
                    imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                    contentDescription = stringResource(R.string.home_back),
                    tint = MaterialTheme.colorScheme.onSurface
                )
            }
            if (vm.isOwnProfile) {
                IconButton(
                    onClick = { showNew = true },
                    enabled = !ui.creating
                ) {
                    Icon(
                        imageVector = Icons.Filled.Add,
                        contentDescription = stringResource(R.string.goals_add),
                        tint = MaterialTheme.colorScheme.onSurface
                    )
                }
            }
        }
        Text(
            text = if (vm.isOwnProfile) {
                stringResource(R.string.goals_title_own)
            } else {
                stringResource(R.string.goals_title_user, viewedUsername)
            },
            style = MaterialTheme.typography.titleLarge
        )
        Text(
            text = stringResource(R.string.goals_header_subtitle),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        val scopeOptions = listOf(GoalsSummaryScope.WEEK, GoalsSummaryScope.ALL_TIME)
        SingleChoiceSegmentedButtonRow(modifier = Modifier.fillMaxWidth()) {
            scopeOptions.forEach { sc ->
                SegmentedButton(
                    selected = ui.scope == sc,
                    onClick = { vm.setScope(sc) },
                    shape = SegmentedButtonDefaults.itemShape(index = scopeOptions.indexOf(sc), count = scopeOptions.size)
                ) {
                    Text(
                        when (sc) {
                            GoalsSummaryScope.WEEK -> stringResource(R.string.goals_scope_week)
                            GoalsSummaryScope.ALL_TIME -> if (ui.allTimeStats == null) {
                                stringResource(R.string.goals_scope_all_time_loading)
                            } else {
                                stringResource(R.string.goals_scope_all_time)
                            }
                        }
                    )
                }
            }
        }
        GoalsSummaryCard(ui = ui)
        if (ui.loading) {
            CircularProgressIndicator(Modifier.padding(24.dp).align(Alignment.CenterHorizontally))
        } else if (ui.error != null) {
            Text(ui.error!!, color = MaterialTheme.colorScheme.error)
        } else if (ui.goals.isEmpty()) {
            Text(
                if (vm.isOwnProfile) stringResource(R.string.goals_empty_own) else stringResource(R.string.goals_empty_other),
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        } else {
            LazyColumn(
                verticalArrangement = Arrangement.spacedBy(8.dp),
                modifier = Modifier.weight(1f, fill = true)
            ) {
                if (ui.activeGoals.isNotEmpty()) {
                    item {
                        Text(
                            stringResource(R.string.goals_section_active, ui.activeGoals.size),
                            style = MaterialTheme.typography.labelLarge,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                    items(ui.activeGoals, key = { it.id }) { g ->
                        GoalRow(
                            g = g,
                            isOwn = vm.isOwnProfile,
                            onOpenContrib = { goalForContrib = it },
                            onRefresh = { vm.refreshOneGoal() },
                            refreshBusy = ui.refreshBusy
                        )
                    }
                }
                if (ui.finishedGoals.isNotEmpty()) {
                    val finishedAvg = if (ui.finishedGoals.isEmpty()) {
                        0
                    } else {
                        val avg = ui.finishedGoals.map { min(1.0, it.progressRatio) }.average()
                        (avg * 100.0).roundToInt()
                    }
                    item {
                        TextButton(
                            onClick = { vm.setShowCompleted(!ui.showCompletedSection) },
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            Text(
                                stringResource(
                                    R.string.goals_section_finished,
                                    finishedAvg,
                                    ui.finishedGoals.size
                                )
                            )
                        }
                    }
                    if (ui.showCompletedSection) {
                        items(ui.finishedGoals, key = { it.id }) { g ->
                            GoalRow(
                                g = g,
                                isOwn = vm.isOwnProfile,
                                onOpenContrib = { goalForContrib = it },
                                onRefresh = { },
                                refreshBusy = false
                            )
                        }
                    }
                }
            }
        }
    }

    if (showNew) {
        ModalBottomSheet(
            onDismissRequest = { showNew = false; vm.clearError() },
            sheetState = newSheetState
        ) {
            NewGoalSheetContent(
                vm = vm,
                onDismiss = { showNew = false; vm.clearError() },
                onCreate = { title, target, metric, onSuccess ->
                    vm.createGoal(title, target, metric, onSuccess = onSuccess)
                }
            )
        }
    }

}

@Composable
private fun GoalsSummaryCard(ui: GoalsUiState) {
    val st = ui.allTimeStats
    val total = when (ui.scope) {
        GoalsSummaryScope.WEEK -> ui.totalGoals
        GoalsSummaryScope.ALL_TIME -> st?.totalGoals ?: 0
    }
    val finished = when (ui.scope) {
        GoalsSummaryScope.WEEK -> ui.finishedCount
        GoalsSummaryScope.ALL_TIME -> st?.finishedGoals ?: 0
    }
    val avg = when (ui.scope) {
        GoalsSummaryScope.WEEK -> ui.weekAvgProgressPercent
        GoalsSummaryScope.ALL_TIME -> st?.avgProgressPercent?.roundToInt() ?: 0
    }
    val best = st?.bestProgressPercent?.roundToInt() ?: 0
    Card(
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.4f)),
        modifier = Modifier.fillMaxWidth()
    ) {
        Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Text(
                    when (ui.scope) {
                        GoalsSummaryScope.WEEK -> stringResource(R.string.goals_summary_week)
                        GoalsSummaryScope.ALL_TIME -> stringResource(R.string.goals_summary_all_time)
                    },
                    style = MaterialTheme.typography.titleSmall
                )
                Text(ui.summaryPercentText, style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(stringResource(R.string.goals_pill_total, total), style = MaterialTheme.typography.labelMedium)
                Text(stringResource(R.string.goals_pill_finished, finished), style = MaterialTheme.typography.labelMedium)
                Text(stringResource(R.string.goals_pill_avg, avg), style = MaterialTheme.typography.labelMedium)
                if (ui.scope == GoalsSummaryScope.ALL_TIME) {
                    Text(stringResource(R.string.goals_pill_best, best), style = MaterialTheme.typography.labelMedium)
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun GoalRow(
    g: GoalRowUi,
    isOwn: Boolean,
    onOpenContrib: (GoalRowUi) -> Unit,
    onRefresh: () -> Unit,
    refreshBusy: Boolean
) {
    val ratio = g.progressRatio.coerceIn(0.0, 2.0)
    val color = when {
        g.isCompleted -> MaterialTheme.colorScheme.outline
        ratio >= 2.0 -> MaterialTheme.colorScheme.tertiary
        ratio >= 1.0 -> MaterialTheme.colorScheme.primary
        ratio >= 0.8 -> MaterialTheme.colorScheme.primaryContainer
        ratio >= 0.6 -> MaterialTheme.colorScheme.secondary
        else -> MaterialTheme.colorScheme.error
    }
    val achieved = g.achievedValue.roundToInt()
    val target = maxOf(1, g.targetValue.roundToInt())
    val pct = (g.progressRatio * 100.0).roundToInt()
    val status = when {
        g.isCompleted -> "Completed"
        goalIsFinished(g) && !g.isCompleted -> "Expired"
        else -> "Active"
    }
    Card(
        onClick = { onOpenContrib(g) },
        modifier = Modifier.fillMaxWidth()
    ) {
        Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Column(Modifier.weight(1f)) {
                    Text(g.title, style = MaterialTheme.typography.titleSmall, maxLines = 2, overflow = TextOverflow.Ellipsis)
                    Text(
                        "${GoalMetric.fromWire(g.metric).title} · ${g.weekStartDate}",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                Column(horizontalAlignment = Alignment.End) {
                    Text("$achieved/$target", style = MaterialTheme.typography.labelLarge)
                    Text("$pct%", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            LinearProgressIndicator(
                progress = { g.progress.toFloat() },
                modifier = Modifier.fillMaxWidth().height(6.dp),
                color = color,
            )
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(status, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                if (isOwn && !g.isCompleted && !goalIsFinished(g)) {
                    IconButton(onClick = onRefresh, enabled = !refreshBusy) {
                        if (refreshBusy) {
                            CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp)
                        } else {
                            Icon(Icons.Filled.Refresh, contentDescription = null)
                        }
                    }
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun NewGoalSheetContent(
    vm: GoalsViewModel,
    onDismiss: () -> Unit,
    onCreate: (String, Int, GoalMetric, onSuccess: () -> Unit) -> Unit
) {
    var metric by remember { mutableStateOf(GoalMetric.WORKOUTS) }
    var title by remember { mutableStateOf("") }
    var target by remember { mutableStateOf("") }
    val ui by vm.uiState.collectAsStateWithLifecycle()

    // Paridad iOS: al cambiar tipo de meta, limpiar target y volver a pedir recomendación; el input se rellena con el RPC.
    LaunchedEffect(metric) {
        target = ""
        vm.fetchRecommendation(metric)
        title = "${metric.title} goal"
    }

    LaunchedEffect(ui.recommendValue) {
        val n = ui.recommendValue
        if (n != null) {
            target = n.toString()
        }
    }

    Column(Modifier.fillMaxWidth().padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text(stringResource(R.string.goals_new_title), style = MaterialTheme.typography.titleMedium)
        val options = listOf(GoalMetric.WORKOUTS, GoalMetric.CALORIES, GoalMetric.SCORE)
        SingleChoiceSegmentedButtonRow(modifier = Modifier.fillMaxWidth()) {
            options.forEach { m ->
                SegmentedButton(
                    selected = metric == m,
                    onClick = {
                        metric = m
                        title = "${m.title} goal"
                    },
                    shape = SegmentedButtonDefaults.itemShape(
                        index = options.indexOf(m),
                        count = options.size
                    )
                ) { Text(m.title) }
            }
        }
        if (vm.existingMetricsThisWeek().contains(metric)) {
            Text(
                stringResource(R.string.goals_metric_exists, metric.title),
                color = MaterialTheme.colorScheme.error,
                style = MaterialTheme.typography.bodySmall
            )
        }
        OutlinedTextField(
            value = title,
            onValueChange = { title = it },
            label = { Text(stringResource(R.string.goals_new_field_title)) },
            modifier = Modifier.fillMaxWidth(),
            singleLine = true
        )
        val hint = if (ui.recommendValue != null) {
            stringResource(R.string.goals_new_target_hint, ui.recommendValue!!, metric.unit)
        } else {
            metric.unit
        }
        OutlinedTextField(
            value = target,
            onValueChange = { target = it.filter { ch -> ch.isDigit() } },
            label = { Text(stringResource(R.string.goals_new_field_target)) },
            supportingText = { Text(hint) },
            modifier = Modifier.fillMaxWidth(),
            singleLine = true
        )
        if (ui.recommendBusy) {
            CircularProgressIndicator(Modifier, strokeWidth = 2.dp)
        }
        Text(stringResource(R.string.goals_new_reco_footer), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        if (ui.error != null) {
            Text(ui.error!!, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedButton(
                onClick = {
                    val t = target.toIntOrNull() ?: return@OutlinedButton
                    if (t <= 0) return@OutlinedButton
                    onCreate(title, t, metric) { onDismiss() }
                },
                enabled = !ui.creating && target.isNotBlank() && !vm.existingMetricsThisWeek().contains(metric)
            ) { Text(stringResource(R.string.goals_new_save)) }
            TextButton(onClick = onDismiss) { Text(stringResource(R.string.goals_new_cancel)) }
        }
    }
}
