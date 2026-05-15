package com.lilru.liftr.ui.active

import android.app.Application
import android.Manifest
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilterChip
import androidx.compose.material3.ExperimentalMaterial3Api
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
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
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
import com.lilru.liftr.prefs.CardioGpsProfile
import com.lilru.liftr.ui.chat.MessagesFloatingButton
import com.lilru.liftr.ui.map.CardioRouteFullscreenMapDialog
import com.lilru.liftr.ui.map.CardioRouteMapBox
import io.github.jan.supabase.SupabaseClient
import kotlin.math.roundToInt

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ActiveCardioWorkoutScreen(
    supabase: SupabaseClient,
    workoutId: Int,
    onClose: () -> Unit,
    modifier: Modifier = Modifier
) {
    val ctx = LocalContext.current
    val app = ctx.applicationContext as Application
    val vm: ActiveCardioWorkoutViewModel = viewModel(
        factory = ActiveCardioWorkoutViewModelFactory(app, supabase, workoutId)
    )
    val ui by vm.uiState.collectAsStateWithLifecycle()
    val ongoingSubtitle = stringResource(R.string.active_cardio_title)
    var hasLoc by remember {
        mutableStateOf(
            ContextCompat.checkSelfPermission(
                ctx,
                Manifest.permission.ACCESS_FINE_LOCATION
            ) == android.content.pm.PackageManager.PERMISSION_GRANTED
        )
    }
    val locPerm = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted ->
        hasLoc = granted
    }
    LaunchedEffect(Unit) {
        if (!hasLoc) {
            locPerm.launch(Manifest.permission.ACCESS_FINE_LOCATION)
        }
    }
    val gpsProfileRaw = when (ui.gpsProfile) {
        CardioGpsProfile.BALANCED -> "balanced"
        CardioGpsProfile.BATTERY_SAVING -> "batterySaving"
    }
    DisposableEffect(ongoingSubtitle, hasLoc, workoutId, gpsProfileRaw) {
        OngoingWorkoutService.start(
            context = ctx,
            subtitle = ongoingSubtitle,
            trackLocation = hasLoc,
            workoutId = workoutId,
            gpsProfile = gpsProfileRaw
        )
        onDispose { OngoingWorkoutService.stop(ctx) }
    }
    LaunchedEffect(
        workoutId,
        ui.elapsedSec,
        ui.timerMode,
        ui.targetDurationSec,
        ui.distanceText,
        ui.activityLabel,
        ui.hasCardioSession,
        ui.loading
    ) {
        if (ui.hasCardioSession && !ui.loading) {
            val sub = if (ui.activityLabel.isNotBlank()) ui.activityLabel
            else ctx.getString(R.string.active_cardio_title)
            val km = parseDisplayKm(ui.distanceText)
            val timerSec = primaryCardioDisplaySec(
                mode = ui.timerMode,
                target = ui.targetDurationSec,
                elapsed = ui.elapsedSec
            )
            val elapsed = formatElapsedCardio(timerSec)
            val pace = if (km != null && km >= 0.01 && ui.elapsedSec > 0) {
                val secPerKm = (ui.elapsedSec / km).roundToInt()
                formatElapsedCardio(secPerKm) + " /km"
            } else {
                "—"
            }
            val kmd = when {
                km != null -> String.format(java.util.Locale.US, "%.2f km", km)
                ui.distanceText.isNotBlank() -> ui.distanceText.trim() + " km"
                else -> "—"
            }
            val stats = "$kmd · $elapsed · $pace"
            OngoingWorkoutWidgetPrefs.setActive(ctx.applicationContext, workoutId, sub, stats)
        }
    }

    Box(modifier.fillMaxSize()) {
        Scaffold(
            modifier = Modifier.fillMaxSize(),
            topBar = {
                TopAppBar(
                    title = { Text(stringResource(R.string.active_cardio_title)) },
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

            !ui.hasCardioSession -> {
                Column(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(padding)
                        .padding(24.dp)
                ) {
                    Text(
                        stringResource(R.string.active_cardio_no_session),
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
                var showFullRouteMap by remember(workoutId) { mutableStateOf(false) }
                LaunchedEffect(ui.routePoints.size) {
                    if (ui.routePoints.size < 2) showFullRouteMap = false
                }
                val mainSec = primaryCardioDisplaySec(
                    mode = ui.timerMode,
                    target = ui.targetDurationSec,
                    elapsed = ui.elapsedSec
                )
                val mainFormatted = formatElapsedCardio(mainSec)
                val km = parseDisplayKm(ui.distanceText)
                val paceText = if (km != null && km >= 0.01 && ui.elapsedSec > 0) {
                    val secPerKm = (ui.elapsedSec / km).roundToInt()
                    formatElapsedCardio(secPerKm) + " /km"
                } else {
                    "—"
                }
                val timerLabel = if (ui.timerMode == CardioTimerMode.COUNTDOWN && ui.targetDurationSec != null) {
                    stringResource(R.string.active_cardio_time_left)
                } else {
                    stringResource(R.string.active_cardio_elapsed_label)
                }
                Column(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(padding)
                        .verticalScroll(rememberScrollState())
                ) {
                    Text(
                        text = ui.activityLabel,
                        style = MaterialTheme.typography.headlineSmall,
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 12.dp, vertical = 8.dp)
                    )
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 12.dp),
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        ui.targetDistanceKm?.let { d ->
                            Text(
                                stringResource(
                                    R.string.active_cardio_target_km,
                                    d.toFloat()
                                ),
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                        ui.targetDurationSec?.let { t ->
                            Text(
                                stringResource(
                                    R.string.active_cardio_target_time,
                                    formatElapsedCardio(t)
                                ),
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    }
                    if (hasLoc) {
                        Text(
                            stringResource(R.string.active_cardio_gps_mode_label),
                            style = MaterialTheme.typography.labelLarge,
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(horizontal = 12.dp, vertical = 4.dp)
                        )
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(horizontal = 12.dp),
                            horizontalArrangement = Arrangement.spacedBy(8.dp)
                        ) {
                            FilterChip(
                                selected = ui.gpsProfile == CardioGpsProfile.BALANCED,
                                onClick = { vm.setGpsProfile(CardioGpsProfile.BALANCED) },
                                label = { Text(stringResource(R.string.active_cardio_gps_balanced)) }
                            )
                            FilterChip(
                                selected = ui.gpsProfile == CardioGpsProfile.BATTERY_SAVING,
                                onClick = { vm.setGpsProfile(CardioGpsProfile.BATTERY_SAVING) },
                                label = { Text(stringResource(R.string.active_cardio_gps_battery)) }
                            )
                        }
                    }
                    ui.targetDurationSec?.let {
                        Text(
                            stringResource(R.string.active_cardio_timer_mode_label),
                            style = MaterialTheme.typography.labelLarge,
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(horizontal = 12.dp, vertical = 4.dp)
                        )
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(horizontal = 12.dp),
                            horizontalArrangement = Arrangement.spacedBy(8.dp)
                        ) {
                            FilterChip(
                                selected = ui.timerMode == CardioTimerMode.STOPWATCH,
                                onClick = { vm.setTimerMode(CardioTimerMode.STOPWATCH) },
                                label = { Text(stringResource(R.string.active_cardio_timer_stopwatch)) }
                            )
                            FilterChip(
                                selected = ui.timerMode == CardioTimerMode.COUNTDOWN,
                                onClick = { vm.setTimerMode(CardioTimerMode.COUNTDOWN) },
                                label = { Text(stringResource(R.string.active_cardio_timer_countdown)) }
                            )
                        }
                    }
                    if (hasLoc && ui.routePoints.size >= 2) {
                        Text(
                            stringResource(R.string.active_cardio_route_label),
                            style = MaterialTheme.typography.labelLarge,
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(horizontal = 12.dp)
                                .padding(top = 8.dp)
                        )
                        Box(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(horizontal = 12.dp, vertical = 4.dp)
                        ) {
                            CardioRouteMapBox(
                                routePoints = ui.routePoints,
                                territoryPreviewRings = ui.territoryPreviewRings,
                                modifier = Modifier.fillMaxWidth()
                            )
                            TextButton(
                                onClick = { showFullRouteMap = true },
                                modifier = Modifier
                                    .align(Alignment.TopEnd)
                                    .padding(4.dp)
                            ) {
                                Text(stringResource(R.string.cardio_map_expand))
                            }
                        }
                    }
                    CardioRouteFullscreenMapDialog(
                        visible = showFullRouteMap && ui.routePoints.size >= 2,
                        onDismiss = { showFullRouteMap = false },
                        routePoints = ui.routePoints,
                        showOpenInGoogleMaps = false
                    )
                    Text(
                        text = mainFormatted,
                        style = MaterialTheme.typography.displayLarge,
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(24.dp),
                    )
                    Text(
                        text = timerLabel,
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
                            modifier = Modifier
                                .weight(1f)
                        ) { Text(startResumePause) }
                        OutlinedButton(
                            onClick = { vm.resetSession() },
                            enabled = !ui.finishing && !ui.isSessionRunning && ui.elapsedSec > 0
                        ) { Text(stringResource(R.string.active_cardio_reset)) }
                    }
                    if (paceText != "—") {
                        Text(
                            stringResource(R.string.active_cardio_avg_pace, paceText),
                            style = MaterialTheme.typography.titleMedium,
                            modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp)
                        )
                    }
                    if (ui.kmSplitCumulativeSec.isNotEmpty()) {
                        Text(
                            stringResource(R.string.active_cardio_km_splits_title),
                            style = MaterialTheme.typography.titleSmall,
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(horizontal = 12.dp, vertical = 4.dp)
                        )
                        val laps = lapDeltasFromCumulative(ui.kmSplitCumulativeSec)
                        laps.forEachIndexed { i, secPerKm ->
                            Text(
                                stringResource(
                                    R.string.active_cardio_km_split_line,
                                    i + 1,
                                    formatElapsedCardio(secPerKm) + " /km"
                                ),
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                modifier = Modifier.padding(horizontal = 12.dp, vertical = 2.dp)
                            )
                        }
                    }
                    OutlinedTextField(
                        value = ui.distanceText,
                        onValueChange = vm::setDistanceText,
                        label = { Text(stringResource(R.string.active_cardio_distance_km)) },
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(12.dp)
                    )
                    if (ui.actionError != null) {
                        Text(
                            text = ui.actionError!!,
                            color = MaterialTheme.colorScheme.error,
                            style = MaterialTheme.typography.bodySmall,
                            modifier = Modifier.padding(horizontal = 12.dp)
                        )
                    }
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(12.dp),
                    ) {
                        Button(
                            onClick = { vm.finishWorkout(onClose) },
                            enabled = !ui.finishing && ui.elapsedSec > 0,
                            modifier = Modifier.fillMaxWidth()
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
    }
        if (!ui.finishing) {
            MessagesFloatingButton(supabase = supabase, modifier = Modifier.fillMaxSize())
        }
    }
}

private fun primaryCardioDisplaySec(
    mode: CardioTimerMode,
    target: Int?,
    elapsed: Int
): Int = if (mode == CardioTimerMode.COUNTDOWN && target != null) {
    (target - elapsed).coerceAtLeast(0)
} else {
    elapsed
}

private fun lapDeltasFromCumulative(cumulative: List<Int>): List<Int> {
    if (cumulative.isEmpty()) return emptyList()
    var prev = 0
    return cumulative.map { c ->
        val d = (c - prev).coerceAtLeast(0)
        prev = c
        d
    }
}

private fun formatElapsedCardio(totalSec: Int): String {
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

private fun parseDisplayKm(text: String): Double? {
    val trimmed = text.trim().replace(',', '.')
    if (trimmed.isEmpty()) return null
    return trimmed.toDoubleOrNull()
}
