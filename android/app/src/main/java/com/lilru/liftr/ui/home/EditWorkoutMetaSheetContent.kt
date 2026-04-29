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
import com.lilru.liftr.ui.add.AddWorkoutIntensity

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun EditWorkoutMetaSheetContent(
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
        FlowRow(
            horizontalArrangement = Arrangement.spacedBy(6.dp)
        ) {
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
        Button(
            onClick = onSave,
            enabled = !saving,
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = 8.dp)
        ) { Text(if (saving) stringResource(R.string.edit_workout_meta_saving) else saveLabel) }
    }
}

fun intensityFromServerOrDefault(raw: String?): AddWorkoutIntensity {
    val w = raw?.lowercase() ?: return AddWorkoutIntensity.MODERATE
    return AddWorkoutIntensity.entries.find { it.wire == w } ?: AddWorkoutIntensity.MODERATE
}
