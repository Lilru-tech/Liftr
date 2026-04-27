package com.lilru.liftr.ui.home

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
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
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.lilru.liftr.R
import com.lilru.liftr.ui.add.AddWorkoutIntensity
import com.lilru.liftr.ui.active.sportMatchResultEntries

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun EditSportWorkoutMetaSheetContent(
    sportTypeLabel: String,
    showMatchResult: Boolean,
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
    durationMin: String,
    onDurationMinChange: (String) -> Unit,
    scoreFor: String,
    onScoreForChange: (String) -> Unit,
    scoreAgainst: String,
    onScoreAgainstChange: (String) -> Unit,
    matchResultRaw: String,
    onMatchResultRawChange: (String) -> Unit,
    matchScoreText: String,
    onMatchScoreTextChange: (String) -> Unit,
    location: String,
    onLocationChange: (String) -> Unit,
    sessionNotes: String,
    onSessionNotesChange: (String) -> Unit,
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
            stringResource(R.string.edit_sport_workout_meta_title),
            style = MaterialTheme.typography.titleLarge
        )
        Text(
            stringResource(R.string.edit_sport_workout_meta_sport, sportTypeLabel),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
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
        OutlinedTextField(
            value = durationMin,
            onValueChange = onDurationMinChange,
            label = { Text(stringResource(R.string.add_duration_min_label)) },
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
            singleLine = true,
            modifier = Modifier.fillMaxWidth()
        )
        OutlinedTextField(
            value = scoreFor,
            onValueChange = onScoreForChange,
            label = { Text(stringResource(R.string.active_sport_score_for)) },
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
            singleLine = true,
            modifier = Modifier.fillMaxWidth()
        )
        OutlinedTextField(
            value = scoreAgainst,
            onValueChange = onScoreAgainstChange,
            label = { Text(stringResource(R.string.active_sport_score_against)) },
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
            singleLine = true,
            modifier = Modifier.fillMaxWidth()
        )
        if (showMatchResult) {
            Text(
                stringResource(R.string.active_sport_match_result),
                style = MaterialTheme.typography.labelLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                for (e in sportMatchResultEntries) {
                    FilterChip(
                        selected = matchResultRaw == e.raw,
                        onClick = { onMatchResultRawChange(e.raw) },
                        label = { Text(stringResource(e.labelRes)) }
                    )
                }
            }
        }
        OutlinedTextField(
            value = matchScoreText,
            onValueChange = onMatchScoreTextChange,
            label = { Text(stringResource(R.string.active_sport_match_score_text)) },
            singleLine = true,
            modifier = Modifier.fillMaxWidth()
        )
        OutlinedTextField(
            value = location,
            onValueChange = onLocationChange,
            label = { Text(stringResource(R.string.active_sport_location)) },
            singleLine = true,
            modifier = Modifier.fillMaxWidth()
        )
        OutlinedTextField(
            value = sessionNotes,
            onValueChange = onSessionNotesChange,
            label = { Text(stringResource(R.string.active_sport_session_notes)) },
            minLines = 2,
            maxLines = 4,
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
