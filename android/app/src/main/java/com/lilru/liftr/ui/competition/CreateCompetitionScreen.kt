package com.lilru.liftr.ui.competition

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.lilru.liftr.R
import com.lilru.liftr.ui.components.LiftrBackTopBar
import io.github.jan.supabase.SupabaseClient
import kotlin.math.max

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CreateCompetitionScreen(
    supabase: SupabaseClient,
    opponentUserId: String,
    onDismiss: () -> Unit,
    onViewCompetitions: (opponentId: String) -> Unit,
    modifier: Modifier = Modifier
) {
    val vm: CreateCompetitionViewModel = viewModel(
        key = "create-comp-$opponentUserId",
        factory = CreateCompetitionViewModelFactory(supabase, opponentUserId)
    )
    val ui by vm.uiState.collectAsStateWithLifecycle()
    var includeTimeLimit by rememberSaveable { mutableStateOf(true) }
    var timeLimitDays by rememberSaveable { mutableIntStateOf(7) }
    var includePerformanceGoal by rememberSaveable { mutableStateOf(true) }
    var metric by rememberSaveable { mutableStateOf("workouts") }
    var targetText by rememberSaveable { mutableStateOf("10") }
    val metrics = listOf("workouts", "calories", "score")
    var wasCreating by remember { mutableStateOf(false) }

    LaunchedEffect(ui.creating, ui.error) {
        if (wasCreating && !ui.creating && ui.error == null) {
            onDismiss()
        }
        wasCreating = ui.creating
    }

    val isValid: Boolean = (includeTimeLimit || includePerformanceGoal) && (
        !includePerformanceGoal || run {
            val t = targetText.replace(",", ".").trim()
            val d = t.toDoubleOrNull()
            d != null && d > 0
        }
        )

    if (ui.checkingExisting) {
        Column(
            modifier = modifier
                .fillMaxSize()
                .statusBarsPadding()
                .padding(16.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            LiftrBackTopBar(onBack = onDismiss)
            CircularProgressIndicator(Modifier.padding(top = 32.dp))
        }
        return
    }

    val existing = ui.existing
    if (existing != null) {
        Column(
            modifier = modifier
                .fillMaxSize()
                .statusBarsPadding()
                .padding(16.dp)
                .verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            LiftrBackTopBar(onBack = onDismiss)
            Text(
                stringResource(R.string.create_competition_existing_title),
                style = MaterialTheme.typography.titleMedium
            )
            Text(
                stringResource(
                    if (existing.status == "active") {
                        R.string.create_competition_existing_active_body
                    } else {
                        R.string.create_competition_existing_pending_body
                    }
                ),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Text(
                stringResource(R.string.create_competition_existing_hint),
                style = MaterialTheme.typography.bodySmall
            )
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                FilledTonalButton(
                    onClick = { onViewCompetitions(opponentUserId) },
                    modifier = Modifier
                ) { Text(stringResource(R.string.create_competition_view_competitions)) }
                OutlinedButton(
                    onClick = onDismiss,
                    modifier = Modifier
                ) { Text(stringResource(R.string.create_competition_pick_other)) }
            }
        }
        return
    }

    Column(
        modifier = modifier
            .fillMaxSize()
            .statusBarsPadding()
            .padding(16.dp)
            .verticalScroll(rememberScrollState()),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        LiftrBackTopBar(onBack = onDismiss)
        Text(
            stringResource(R.string.create_competition_header),
            style = MaterialTheme.typography.titleLarge
        )
        if (ui.error != null) {
            Text(ui.error!!, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
        }
        Text(
            stringResource(R.string.create_competition_time_limit_section),
            style = MaterialTheme.typography.labelLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.SpaceBetween, modifier = Modifier.fillMaxWidth()) {
            Text(stringResource(R.string.create_competition_enable_time_limit))
            Switch(checked = includeTimeLimit, onCheckedChange = { includeTimeLimit = it })
        }
        if (includeTimeLimit) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                OutlinedButton(
                    onClick = { timeLimitDays = max(1, timeLimitDays - 1) },
                    enabled = timeLimitDays > 1
                ) { Text("−") }
                Text(
                    stringResource(R.string.create_competition_days, timeLimitDays),
                    modifier = Modifier.padding(horizontal = 8.dp)
                )
                OutlinedButton(
                    onClick = { timeLimitDays = (timeLimitDays + 1).coerceAtMost(60) },
                    enabled = timeLimitDays < 60
                ) { Text("+") }
            }
        }
        Text(
            stringResource(R.string.create_competition_perf_section),
            style = MaterialTheme.typography.labelLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.SpaceBetween, modifier = Modifier.fillMaxWidth()) {
            Text(stringResource(R.string.create_competition_enable_performance))
            Switch(checked = includePerformanceGoal, onCheckedChange = { includePerformanceGoal = it })
        }
        if (includePerformanceGoal) {
            SingleChoiceSegmentedButtonRow(modifier = Modifier.fillMaxWidth()) {
                metrics.forEachIndexed { index, m ->
                    SegmentedButton(
                        selected = metric == m,
                        onClick = { metric = m },
                        shape = SegmentedButtonDefaults.itemShape(index, metrics.size)
                    ) {
                        Text(
                            when (m) {
                                "workouts" -> stringResource(R.string.profile_progress_metric_workouts)
                                "calories" -> stringResource(R.string.profile_progress_metric_calories)
                                else -> stringResource(R.string.profile_progress_metric_score)
                            }
                        )
                    }
                }
            }
            val keyboard = if (metric == "workouts") KeyboardType.Number else KeyboardType.Decimal
            val placeholder = when (metric) {
                "workouts" -> stringResource(R.string.create_competition_target_hint_workouts)
                "calories" -> stringResource(R.string.create_competition_target_hint_calories)
                else -> stringResource(R.string.create_competition_target_hint_score)
            }
            OutlinedTextField(
                value = targetText,
                onValueChange = { targetText = it },
                label = { Text(placeholder) },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = keyboard)
            )
        }
        Text(
            stringResource(R.string.create_competition_rules_footnote),
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        FilledTonalButton(
            onClick = {
                if (isValid && !ui.creating) {
                    vm.create(
                        includeTimeLimit = includeTimeLimit,
                        timeLimitDays = timeLimitDays,
                        includePerformanceGoal = includePerformanceGoal,
                        metric = metric,
                        targetText = targetText
                    )
                }
            },
            enabled = isValid && !ui.creating,
            modifier = Modifier.fillMaxWidth()
        ) {
            Row(horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) {
                if (ui.creating) {
                    CircularProgressIndicator(
                        strokeWidth = 2.dp,
                        modifier = Modifier
                            .size(20.dp)
                            .padding(end = 8.dp)
                    )
                }
                Text(stringResource(R.string.create_competition_send))
            }
        }
    }
}
