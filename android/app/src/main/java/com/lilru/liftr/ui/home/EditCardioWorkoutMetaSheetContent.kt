package com.lilru.liftr.ui.home

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
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

/**
 * Edición de entreno **cardio** en detalle: metadatos comunes + [cardio_sessions] + stats extra
 * (paridad con [EditWorkoutMetaSheet] caso cardio en iOS).
 */
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
        OutlinedTextField(
            value = distanceKm,
            onValueChange = onDistanceKmChange,
            label = { Text(stringResource(R.string.add_cardio_distance_km_label)) },
            modifier = Modifier.fillMaxWidth()
        )
        Text(stringResource(R.string.add_cardio_duration_hms_caption), style = MaterialTheme.typography.labelSmall)
        OutlinedTextField(
            value = durH, onValueChange = onDurHChange, label = { Text(stringResource(R.string.add_cardio_duration_h_label)) },
            modifier = Modifier.fillMaxWidth()
        )
        OutlinedTextField(
            value = durM, onValueChange = onDurMChange, label = { Text(stringResource(R.string.add_cardio_duration_m_label)) },
            modifier = Modifier.fillMaxWidth()
        )
        OutlinedTextField(
            value = durS, onValueChange = onDurSChange, label = { Text(stringResource(R.string.add_cardio_duration_s_label)) },
            modifier = Modifier.fillMaxWidth()
        )
        OutlinedTextField(avgHr, onAvgHrChange, label = { Text(stringResource(R.string.add_cardio_avg_hr_label)) }, modifier = Modifier.fillMaxWidth())
        OutlinedTextField(maxHr, onMaxHrChange, label = { Text(stringResource(R.string.add_cardio_max_hr_label)) }, modifier = Modifier.fillMaxWidth())
        OutlinedTextField(
            value = avgPaceSecPerKm,
            onValueChange = onAvgPaceSecPerKmChange,
            label = { Text(stringResource(R.string.add_cardio_avg_pace_sec_label)) },
            modifier = Modifier.fillMaxWidth()
        )
        OutlinedTextField(
            value = elevationM,
            onValueChange = onElevationMChange,
            label = { Text(stringResource(R.string.add_cardio_elevation_m_label)) },
            modifier = Modifier.fillMaxWidth()
        )
        OutlinedTextField(
            cadenceRpm, onCadenceRpmChange,
            label = { Text(stringResource(R.string.add_cardio_cadence_rpm_label)) },
            modifier = Modifier.fillMaxWidth()
        )
        OutlinedTextField(
            wattsAvg, onWattsAvgChange,
            label = { Text(stringResource(R.string.add_cardio_watts_avg_label)) },
            modifier = Modifier.fillMaxWidth()
        )
        OutlinedTextField(
            inclinePct, onInclinePctChange,
            label = { Text(stringResource(R.string.add_cardio_incline_pct_label)) },
            modifier = Modifier.fillMaxWidth()
        )
        OutlinedTextField(
            splitSecPer500m, onSplitSecPer500mChange,
            label = { Text(stringResource(R.string.add_cardio_split_500m_label)) },
            modifier = Modifier.fillMaxWidth()
        )
        OutlinedTextField(
            kmSplitsPaceText, onKmSplitsPaceTextChange,
            label = { Text(stringResource(R.string.add_cardio_km_split_label)) },
            modifier = Modifier.fillMaxWidth()
        )
        OutlinedTextField(
            swimLaps, onSwimLapsChange,
            label = { Text(stringResource(R.string.add_cardio_swim_laps_label)) },
            modifier = Modifier.fillMaxWidth()
        )
        OutlinedTextField(
            poolLengthM, onPoolLengthMChange,
            label = { Text(stringResource(R.string.add_cardio_pool_length_m_label)) },
            modifier = Modifier.fillMaxWidth()
        )
        OutlinedTextField(
            swimStyle, onSwimStyleChange,
            label = { Text(stringResource(R.string.add_cardio_swim_style_label)) },
            modifier = Modifier.fillMaxWidth()
        )
        Button(
            onClick = onSave,
            enabled = !saving,
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = 8.dp)
        ) { Text(if (saving) stringResource(R.string.edit_workout_meta_saving) else saveLabel) }
    }
}
