package com.lilru.liftr.ui.active

import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.lilru.liftr.R
import com.lilru.liftr.ongoing.OngoingWorkoutService
import com.lilru.liftr.ongoing.OngoingWorkoutWidgetPrefs
import com.lilru.liftr.hyrox.HyroxExerciseFormatting
import com.lilru.liftr.ui.chat.MessagesFloatingButton
import io.github.jan.supabase.SupabaseClient

@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun ActiveSportWorkoutScreen(
    supabase: SupabaseClient,
    workoutId: Int,
    onClose: () -> Unit,
    modifier: Modifier = Modifier
) {
    val vm: ActiveSportWorkoutViewModel = viewModel(
        factory = ActiveSportWorkoutViewModelFactory(supabase, workoutId)
    )
    val ui by vm.uiState.collectAsStateWithLifecycle()
    val ctx = LocalContext.current
    val ongoingSubtitle = stringResource(R.string.active_sport_title)
    DisposableEffect(ongoingSubtitle, workoutId) {
        OngoingWorkoutService.start(ctx, ongoingSubtitle, trackLocation = false, workoutId = workoutId)
        onDispose { OngoingWorkoutService.stop(ctx) }
    }
    LaunchedEffect(
        workoutId,
        ui.sportLabel,
        ui.elapsedSec,
        ui.scoreForText,
        ui.scoreAgainstText,
        ui.hasSportSession,
        ui.loading
    ) {
        if (ui.hasSportSession && !ui.loading) {
            val t = formatElapsedSport(ui.elapsedSec)
            val sc = buildString {
                if (ui.scoreForText.isNotBlank() || ui.scoreAgainstText.isNotBlank()) {
                    append(ui.scoreForText.trim())
                    append("–")
                    append(ui.scoreAgainstText.trim())
                } else {
                    append("—")
                }
            }
            val sub = if (ui.sportLabel.isNotBlank()) ui.sportLabel
            else ctx.getString(R.string.active_sport_title)
            val stats = "$t · $sc"
            OngoingWorkoutWidgetPrefs.setActive(ctx.applicationContext, workoutId, sub, stats)
        }
    }

    Box(modifier.fillMaxSize()) {
        Scaffold(
            modifier = Modifier.fillMaxSize(),
            topBar = {
                TopAppBar(
                    title = { Text(stringResource(R.string.active_sport_title)) },
                    navigationIcon = {
                        TextButton(onClick = onClose) {
                            Text(stringResource(R.string.active_strength_back))
                        }
                    }
                )
            }
        ) { padding ->
        when {
            ui.loading -> {
                Column(
                    Modifier
                        .fillMaxSize()
                        .padding(padding)
                        .padding(24.dp),
                    verticalArrangement = Arrangement.Center,
                    horizontalAlignment = Alignment.CenterHorizontally
                ) { CircularProgressIndicator() }
            }

            ui.loadError != null -> {
                Column(
                    Modifier
                        .fillMaxSize()
                        .padding(padding)
                        .padding(24.dp)
                ) {
                    Text(
                        text = ui.loadError ?: "",
                        color = MaterialTheme.colorScheme.error
                    )
                    Button(
                        onClick = { vm.load() },
                        modifier = Modifier.padding(top = 8.dp)
                    ) {
                        Text(stringResource(R.string.home_retry))
                    }
                }
            }

            !ui.hasSportSession -> {
                Column(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(padding)
                        .padding(24.dp)
                ) {
                    Text(
                        stringResource(R.string.active_sport_no_session),
                        style = MaterialTheme.typography.bodyLarge
                    )
                    Button(
                        onClick = onClose,
                        modifier = Modifier
                            .padding(top = 16.dp)
                            .fillMaxWidth()
                    ) { Text(stringResource(R.string.active_strength_back)) }
                }
            }

            else -> {
                val elapsed = formatElapsedSport(ui.elapsedSec)
                Column(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(padding)
                        .verticalScroll(rememberScrollState())
                ) {
                    Text(
                        text = ui.sportLabel,
                        style = MaterialTheme.typography.headlineSmall,
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 12.dp, vertical = 8.dp)
                    )
                    ui.targetDurationSec?.let { t ->
                        val mins = maxOf(1, t / 60)
                        Text(
                            text = stringResource(R.string.active_sport_target_min, mins),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.padding(horizontal = 12.dp)
                        )
                    }
                    Text(
                        text = elapsed,
                        style = MaterialTheme.typography.displayLarge,
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(24.dp),
                    )
                    Text(
                        stringResource(R.string.active_cardio_elapsed_label),
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 12.dp)
                    )
                    val status = when {
                        ui.isSessionRunning -> stringResource(R.string.active_cardio_status_running)
                        ui.elapsedSec == 0 -> stringResource(R.string.active_cardio_status_hint)
                        else -> stringResource(R.string.active_cardio_status_paused)
                    }
                    Text(
                        text = status,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(
                            start = 12.dp,
                            end = 12.dp,
                            top = 4.dp,
                            bottom = 4.dp
                        )
                    )
                    val hyroxOrdered = remember(ui.hyroxExercises) {
                        ui.hyroxExercises.sortedBy { it.exerciseOrder }
                    }
                    val hyroxCurrent = hyroxOrdered.getOrNull(ui.hyroxExerciseIndex)
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 12.dp, vertical = 4.dp),
                        horizontalArrangement = Arrangement.spacedBy(10.dp)
                    ) {
                        val startResumePause = if (ui.isSessionRunning) {
                            stringResource(R.string.active_cardio_pause)
                        } else if (ui.elapsedSec == 0) {
                            stringResource(R.string.active_cardio_start)
                        } else {
                            stringResource(R.string.active_cardio_resume)
                        }
                        Button(
                            onClick = { vm.toggleSessionRunning() },
                            enabled = !ui.finishing,
                            modifier = Modifier.weight(1f)
                        ) { Text(startResumePause) }
                        OutlinedButton(
                            onClick = { vm.resetSession() },
                            enabled = !ui.finishing && !ui.isSessionRunning && ui.elapsedSec > 0
                        ) { Text(stringResource(R.string.active_cardio_reset)) }
                    }
                    if (ui.isHyrox) {
                        if (hyroxCurrent != null) {
                            val current = hyroxCurrent
                            Card(
                                Modifier
                                    .fillMaxWidth()
                                    .padding(horizontal = 12.dp, vertical = 4.dp)
                            ) {
                                Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                                    Text(
                                        stringResource(
                                            R.string.active_sport_hyrox_progress,
                                            ui.hyroxExerciseIndex + 1,
                                            hyroxOrdered.size
                                        ),
                                        style = MaterialTheme.typography.labelLarge
                                    )
                                    Text(
                                        HyroxExerciseFormatting.label(
                                            current.exerciseCode,
                                            current.exerciseDisplayName,
                                            current.notes
                                        ),
                                        style = MaterialTheme.typography.titleMedium
                                    )
                                    current.distanceM?.let {
                                        Text(
                                            stringResource(R.string.active_sport_hyrox_distance_m) + ": $it",
                                            style = MaterialTheme.typography.bodyMedium
                                        )
                                    }
                                    current.reps?.let {
                                        Text(
                                            stringResource(R.string.active_sport_hyrox_reps) + ": $it",
                                            style = MaterialTheme.typography.bodyMedium
                                        )
                                    }
                                    current.weightKg?.let {
                                        Text(
                                            stringResource(R.string.active_sport_hyrox_weight) + ": $it",
                                            style = MaterialTheme.typography.bodyMedium
                                        )
                                    }
                                    current.durationSec?.let {
                                        Text(
                                            stringResource(R.string.active_sport_hyrox_duration) + ": $it",
                                            style = MaterialTheme.typography.bodyMedium
                                        )
                                    }
                                    current.heightCm?.let {
                                        Text(
                                            stringResource(R.string.active_sport_hyrox_height) + ": $it",
                                            style = MaterialTheme.typography.bodyMedium
                                        )
                                    }
                                    current.implementCount?.let {
                                        Text(
                                            stringResource(R.string.active_sport_hyrox_implements) + ": $it",
                                            style = MaterialTheme.typography.bodyMedium
                                        )
                                    }
                                    current.notes?.takeIf { it.isNotBlank() }?.let {
                                        Text(
                                            stringResource(R.string.active_sport_hyrox_notes) + ": $it",
                                            style = MaterialTheme.typography.bodySmall
                                        )
                                    }
                                }
                            }
                        } else {
                            Text(
                                stringResource(R.string.active_sport_hyrox_empty),
                                modifier = Modifier.padding(12.dp)
                            )
                        }
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(horizontal = 12.dp, vertical = 4.dp),
                            horizontalArrangement = Arrangement.SpaceBetween
                        ) {
                            OutlinedButton(
                                onClick = { vm.hyroxStep(-1) },
                                enabled = !ui.finishing && ui.hyroxExerciseIndex > 0
                            ) { Text(stringResource(R.string.active_sport_hyrox_prev)) }
                            OutlinedButton(
                                onClick = { vm.hyroxStep(1) },
                                enabled = !ui.finishing &&
                                    hyroxOrdered.isNotEmpty() && ui.hyroxExerciseIndex < hyroxOrdered.lastIndex
                            ) { Text(stringResource(R.string.active_sport_hyrox_next)) }
                        }
                    } else {
                        OutlinedTextField(
                            value = ui.scoreForText,
                            onValueChange = vm::setScoreForText,
                            label = { Text(stringResource(R.string.active_sport_score_for)) },
                            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                            singleLine = true,
                            enabled = !ui.finishing,
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(12.dp)
                        )
                        OutlinedTextField(
                            value = ui.scoreAgainstText,
                            onValueChange = vm::setScoreAgainstText,
                            label = { Text(stringResource(R.string.active_sport_score_against)) },
                            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                            singleLine = true,
                            enabled = !ui.finishing,
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(horizontal = 12.dp, vertical = 0.dp)
                        )
                        Text(
                            text = stringResource(R.string.active_sport_match_result),
                            style = MaterialTheme.typography.labelLarge,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.padding(
                                start = 12.dp,
                                end = 12.dp,
                                top = 4.dp,
                                bottom = 2.dp
                            )
                        )
                        FlowRow(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(
                                    start = 12.dp,
                                    end = 12.dp,
                                    bottom = 4.dp
                                ),
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                            verticalArrangement = Arrangement.spacedBy(8.dp)
                        ) {
                            sportMatchResultEntries.forEach { entry ->
                                FilterChip(
                                    selected = ui.matchResultRaw == entry.raw,
                                    onClick = { vm.setMatchResultRaw(entry.raw) },
                                    enabled = !ui.finishing,
                                    label = { Text(stringResource(entry.labelRes)) }
                                )
                            }
                        }
                        OutlinedTextField(
                            value = ui.matchScoreText,
                            onValueChange = vm::setMatchScoreText,
                            label = { Text(stringResource(R.string.active_sport_match_score_text)) },
                            singleLine = true,
                            enabled = !ui.finishing,
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(horizontal = 12.dp, vertical = 0.dp)
                        )
                        OutlinedTextField(
                            value = ui.locationText,
                            onValueChange = vm::setLocationText,
                            label = { Text(stringResource(R.string.active_sport_location)) },
                            singleLine = true,
                            enabled = !ui.finishing,
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(12.dp)
                        )
                    }
                    OutlinedTextField(
                        value = ui.sessionNotesText,
                        onValueChange = vm::setSessionNotesText,
                        label = { Text(stringResource(R.string.active_sport_session_notes)) },
                        minLines = 2,
                        maxLines = 4,
                        enabled = !ui.finishing,
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 12.dp, vertical = 0.dp)
                    )
                    if (ui.actionError != null) {
                        Text(
                            text = ui.actionError!!,
                            color = MaterialTheme.colorScheme.error,
                            style = MaterialTheme.typography.bodySmall,
                            modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp)
                        )
                    }
                    Button(
                        onClick = { vm.finishWorkout(onClose) },
                        enabled = !ui.finishing && ui.elapsedSec > 0,
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(12.dp)
                    ) {
                        if (ui.finishing) {
                            Text(stringResource(R.string.active_strength_saving))
                        } else {
                            Text(stringResource(R.string.active_strength_finish))
                        }
                    }
                }
            }
        }
    }
        MessagesFloatingButton(supabase = supabase, modifier = Modifier.fillMaxSize())
    }
}

private fun formatElapsedSport(totalSec: Int): String {
    if (totalSec < 0) return "0:00"
    val h = totalSec / 3600
    val m = (totalSec % 3600) / 60
    val s = totalSec % 60
    return if (h > 0) {
        String.format("%d:%02d:%02d", h, m, s)
    } else {
        String.format("%d:%02d", m, s)
    }
}
