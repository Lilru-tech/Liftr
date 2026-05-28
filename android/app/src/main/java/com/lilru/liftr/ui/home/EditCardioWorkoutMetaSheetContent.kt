package com.lilru.liftr.ui.home

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.ui.text.input.KeyboardType
import com.lilru.liftr.ui.components.WorkoutMetricField
import com.lilru.liftr.ui.components.WorkoutMetricReadoutField
import com.lilru.liftr.ui.home.formatSwimPaceMinSecPer100m
import com.lilru.liftr.ui.home.autoPaceSecPerKmFromMeters
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.lilru.liftr.R
import com.lilru.liftr.ui.add.AddCardioActivity
import com.lilru.liftr.ui.add.AddWorkoutIntensity
import kotlin.math.roundToInt

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun EditCardioWorkoutMetaSheetContent(
    title: String,
    onTitleChange: (String) -> Unit,
    notes: String,
    onNotesChange: (String) -> Unit,
    startedAtIso: String,
    onStartedAtChange: (String) -> Unit,
    endedAtEnabled: Boolean,
    onEndedAtEnabledChange: (Boolean) -> Unit,
    endedAtIso: String,
    onEndedAtChange: (String) -> Unit,
    intensity: AddWorkoutIntensity,
    onIntensityChange: (AddWorkoutIntensity) -> Unit,
    activity: AddCardioActivity,
    onActivityChange: (AddCardioActivity) -> Unit,
    distanceKm: String,
    onDistanceKmChange: (String) -> Unit,
    durH: String,
    durM: String,
    durS: String,
    onDurHChange: (String) -> Unit,
    onDurMChange: (String) -> Unit,
    onDurSChange: (String) -> Unit,
    avgHr: String,
    onAvgHrChange: (String) -> Unit,
    maxHr: String,
    onMaxHrChange: (String) -> Unit,
    avgPaceSecPerKm: String,
    onAvgPaceSecPerKmChange: (String) -> Unit,
    elevationM: String,
    onElevationMChange: (String) -> Unit,
    cadenceRpm: String,
    onCadenceRpmChange: (String) -> Unit,
    wattsAvg: String,
    onWattsAvgChange: (String) -> Unit,
    inclinePct: String,
    onInclinePctChange: (String) -> Unit,
    splitSecPer500m: String,
    onSplitSecPer500mChange: (String) -> Unit,
    kmSplitsPaceText: String,
    onKmSplitsPaceTextChange: (String) -> Unit,
    swimLaps: String,
    onSwimLapsChange: (String) -> Unit,
    poolLengthM: String,
    onPoolLengthMChange: (String) -> Unit,
    swimStyle: String,
    onSwimStyleChange: (String) -> Unit,
    saveLabel: String,
    saving: Boolean,
    onSave: () -> Unit
) {
    val swimUnits = activity.usesSwimDistanceAndPace
    val durSec = parseHmsToSecForPace(durH, durM, durS)
    val computedPace = when {
        swimUnits && durSec != null ->
            autoPaceSecPerKmFromMeters(distanceKm, durSec)?.let { formatSwimPaceMinSecPer100m(it) }
        !swimUnits && durSec != null -> {
            val km = distanceKm.trim().replace(',', '.').toDoubleOrNull()
            if (km != null && km > 0.0) {
                formatPaceMinSecPerKm((durSec.toDouble() / km).roundToInt())
            } else null
        }
        else -> null
    }

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(16.dp)
            .verticalScroll(rememberScrollState()),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        Text(
            stringResource(R.string.edit_workout_meta_title),
            style = MaterialTheme.typography.titleLarge
        )
        OutlinedTextField(
            value = title,
            onValueChange = onTitleChange,
            label = { Text(stringResource(R.string.add_workout_title_label)) },
            modifier = Modifier.fillMaxWidth()
        )
        OutlinedTextField(
            value = notes,
            onValueChange = onNotesChange,
            label = { Text(stringResource(R.string.add_notes_label)) },
            modifier = Modifier.fillMaxWidth(),
            minLines = 2
        )
        OutlinedTextField(
            value = startedAtIso,
            onValueChange = onStartedAtChange,
            label = { Text(stringResource(R.string.add_schedule_started_iso_label)) },
            supportingText = { Text(stringResource(R.string.edit_workout_meta_iso_hint)) },
            modifier = Modifier.fillMaxWidth()
        )
        Text(stringResource(R.string.add_schedule_ended_enabled_label), style = MaterialTheme.typography.labelLarge)
        Switch(
            checked = endedAtEnabled,
            onCheckedChange = onEndedAtEnabledChange
        )
        if (endedAtEnabled) {
            OutlinedTextField(
                value = endedAtIso,
                onValueChange = onEndedAtChange,
                label = { Text(stringResource(R.string.add_schedule_ended_iso_label)) },
                modifier = Modifier.fillMaxWidth()
            )
        }
        Text(stringResource(R.string.add_intensity_label), style = MaterialTheme.typography.labelLarge)
        FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            for (v in AddWorkoutIntensity.entries) {
                val chipText = when (v) {
                    AddWorkoutIntensity.EASY -> stringResource(R.string.add_intensity_easy)
                    AddWorkoutIntensity.MODERATE -> stringResource(R.string.add_intensity_moderate)
                    AddWorkoutIntensity.HARD -> stringResource(R.string.add_intensity_hard)
                    AddWorkoutIntensity.MAX -> stringResource(R.string.add_intensity_max)
                }
                FilterChip(
                    onClick = { onIntensityChange(v) },
                    label = { Text(chipText) },
                    selected = intensity == v
                )
            }
        }
        Text(stringResource(R.string.add_cardio_activity_label), style = MaterialTheme.typography.labelLarge)
        FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            for (a in AddCardioActivity.entries) {
                FilterChip(
                    onClick = { onActivityChange(a) },
                    label = { Text(a.wire) },
                    selected = activity == a
                )
            }
        }
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            WorkoutMetricField(
                title = if (swimUnits) "Dist m" else "Dist km",
                value = distanceKm,
                onValueChange = onDistanceKmChange,
                modifier = Modifier.weight(1.2f),
                keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(keyboardType = KeyboardType.Decimal)
            )
            WorkoutMetricField(
                title = "h",
                value = durH,
                onValueChange = onDurHChange,
                modifier = Modifier.weight(0.6f),
                keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(keyboardType = KeyboardType.Number)
            )
            WorkoutMetricField(
                title = "m",
                value = durM,
                onValueChange = onDurMChange,
                modifier = Modifier.weight(0.6f),
                keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(keyboardType = KeyboardType.Number)
            )
            WorkoutMetricField(
                title = "s",
                value = durS,
                onValueChange = onDurSChange,
                modifier = Modifier.weight(0.6f),
                keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(keyboardType = KeyboardType.Number)
            )
        }
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            WorkoutMetricField(
                title = "Avg HR",
                value = avgHr,
                onValueChange = onAvgHrChange,
                modifier = Modifier.weight(1f),
                keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(keyboardType = KeyboardType.Number)
            )
            WorkoutMetricField(
                title = "Max HR",
                value = maxHr,
                onValueChange = onMaxHrChange,
                modifier = Modifier.weight(1f),
                keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(keyboardType = KeyboardType.Number)
            )
        }
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            WorkoutMetricReadoutField(
                title = if (swimUnits) "Pace /100m" else "Pace /km",
                value = computedPace ?: "—",
                modifier = Modifier.weight(1f)
            )
            if (activity.showsElevation) {
                WorkoutMetricField(
                    title = "Elev m",
                    value = elevationM,
                    onValueChange = onElevationMChange,
                    modifier = Modifier.weight(1f),
                    keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(keyboardType = KeyboardType.Number)
                )
            }
        }
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            WorkoutMetricField(
                title = if (swimUnits) "Pace s/100m" else "Pace s/km",
                value = avgPaceSecPerKm,
                onValueChange = onAvgPaceSecPerKmChange,
                modifier = Modifier.weight(1f),
                keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(keyboardType = KeyboardType.Number)
            )
        }
        if (activity.showsCadenceRpm || activity.showsWatts) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                if (activity.showsCadenceRpm) {
                    WorkoutMetricField(
                        title = "Cadence",
                        value = cadenceRpm,
                        onValueChange = onCadenceRpmChange,
                        modifier = Modifier.weight(1f),
                        keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(keyboardType = KeyboardType.Number)
                    )
                }
                if (activity.showsWatts) {
                    WorkoutMetricField(
                        title = "Watts",
                        value = wattsAvg,
                        onValueChange = onWattsAvgChange,
                        modifier = Modifier.weight(1f),
                        keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(keyboardType = KeyboardType.Number)
                    )
                }
            }
        }
        if (activity.showsIncline) {
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                WorkoutMetricField(
                    title = "Incline %",
                    value = inclinePct,
                    onValueChange = onInclinePctChange,
                    modifier = Modifier.weight(1f),
                    keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(keyboardType = KeyboardType.Decimal)
                )
            }
        }
        if (activity.showsSplit500m) {
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                WorkoutMetricField(
                    title = "Split /500m",
                    value = splitSecPer500m,
                    onValueChange = onSplitSecPer500mChange,
                    modifier = Modifier.weight(1f),
                    keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(keyboardType = KeyboardType.Number)
                )
            }
        }
        if (activity.showsKmPaceSplits) {
            OutlinedTextField(
                kmSplitsPaceText, onKmSplitsPaceTextChange,
                label = { Text(stringResource(R.string.add_cardio_km_split_label)) },
                modifier = Modifier.fillMaxWidth()
            )
        }
        if (activity.showsSwimFields) {
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                WorkoutMetricField(
                    title = "Laps",
                    value = swimLaps,
                    onValueChange = onSwimLapsChange,
                    modifier = Modifier.weight(1f),
                    keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(keyboardType = KeyboardType.Number)
                )
                WorkoutMetricField(
                    title = "Pool m",
                    value = poolLengthM,
                    onValueChange = onPoolLengthMChange,
                    modifier = Modifier.weight(1f),
                    keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(keyboardType = KeyboardType.Number)
                )
            }
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                WorkoutMetricField(
                    title = "Style",
                    value = swimStyle,
                    onValueChange = onSwimStyleChange,
                    modifier = Modifier.fillMaxWidth()
                )
            }
        }
        Button(
            onClick = onSave,
            enabled = !saving,
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = 8.dp)
        ) { Text(if (saving) stringResource(R.string.edit_workout_meta_saving) else saveLabel) }
    }
}

private fun parseHmsToSecForPace(h: String, m: String, s: String): Int? {
    val hi = h.trim().toIntOrNull() ?: 0
    val mi = m.trim().toIntOrNull() ?: 0
    val si = s.trim().toIntOrNull() ?: 0
    if (mi !in 0..59 || si !in 0..59 || hi < 0) return null
    val total = hi * 3600 + mi * 60 + si
    return if (total > 0) total else null
}
