package com.lilru.liftr.ui.home

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material3.Button
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.lilru.liftr.R
import com.lilru.liftr.ui.add.AddWorkoutIntensity
import com.lilru.liftr.ui.add.StrengthExerciseDraft
import com.lilru.liftr.ui.add.StrengthSetDraft

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun EditStrengthWorkoutMetaSheetContent(
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
    exercises: List<StrengthExerciseDraft>,
    onExercisesChange: (List<StrengthExerciseDraft>) -> Unit,
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
            stringResource(R.string.edit_strength_workout_meta_title),
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
        Switch(checked = endedAtEnabled, onCheckedChange = onEndedAtEnabledChange)
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
        Text(
            stringResource(R.string.edit_strength_exercises_section),
            style = MaterialTheme.typography.titleSmall,
            modifier = Modifier.padding(top = 8.dp)
        )
        fun replaceAt(index: Int, e: StrengthExerciseDraft) = onExercisesChange(
            exercises.mapIndexed { j, item -> if (j == index) e else item }
        )
        fun moveExercise(from: Int, to: Int) {
            if (from == to || to !in exercises.indices) return
            val m = exercises.toMutableList()
            val t = m.removeAt(from)
            m.add(to, t)
            onExercisesChange(m)
        }
        exercises.forEachIndexed { exIndex, ex ->
            Column(Modifier.fillMaxWidth()) {
                if (exIndex > 0) {
                    HorizontalDivider(Modifier.padding(vertical = 8.dp))
                }
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        ex.exerciseName.ifBlank { "—" },
                        style = MaterialTheme.typography.titleSmall,
                        color = MaterialTheme.colorScheme.primary,
                        modifier = Modifier.weight(1f)
                    )
                    if (exIndex > 0) {
                        IconButton(onClick = { moveExercise(exIndex, exIndex - 1) }) {
                            Icon(
                                imageVector = Icons.Filled.KeyboardArrowUp,
                                contentDescription = stringResource(R.string.edit_strength_move_ex_up_cd)
                            )
                        }
                    }
                    if (exIndex < exercises.lastIndex) {
                        IconButton(onClick = { moveExercise(exIndex, exIndex + 1) }) {
                            Icon(
                                imageVector = Icons.Filled.KeyboardArrowDown,
                                contentDescription = stringResource(R.string.edit_strength_move_ex_down_cd)
                            )
                        }
                    }
                    if (exercises.size > 1) {
                        TextButton(
                            onClick = {
                                onExercisesChange(exercises.filterIndexed { j, _ -> j != exIndex })
                            }
                        ) {
                            Text(
                                stringResource(R.string.edit_strength_remove_exercise),
                                color = MaterialTheme.colorScheme.error
                            )
                        }
                    }
                }
                OutlinedTextField(
                    value = ex.customName,
                    onValueChange = { v -> replaceAt(exIndex, ex.copy(customName = v)) },
                    label = { Text(stringResource(R.string.add_exercise_alias_label)) },
                    modifier = Modifier.fillMaxWidth()
                )
                OutlinedTextField(
                    value = ex.notes,
                    onValueChange = { v -> replaceAt(exIndex, ex.copy(notes = v)) },
                    label = { Text(stringResource(R.string.add_exercise_notes_label)) },
                    modifier = Modifier.fillMaxWidth(),
                    minLines = 2
                )
                ex.sets.forEachIndexed { setIndex, st ->
                    fun patchSet(f: (StrengthSetDraft) -> StrengthSetDraft) {
                        replaceAt(
                            exIndex,
                            ex.copy(sets = ex.sets.mapIndexed { si, s -> if (si == setIndex) f(s) else s })
                        )
                    }
                    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                        Text(
                            stringResource(R.string.add_set_name_format, st.setNumber.coerceIn(1, 99)),
                            style = MaterialTheme.typography.labelLarge,
                            modifier = Modifier.weight(0.4f)
                        )
                        if (ex.sets.size > 1) {
                            IconButton(
                                onClick = {
                                    val next = ex.sets.filterIndexed { i, _ -> i != setIndex }
                                    replaceAt(exIndex, ex.copy(sets = coalesceSets(next)))
                                }
                            ) {
                                Icon(
                                    imageVector = Icons.Filled.Delete,
                                    contentDescription = stringResource(R.string.add_set_remove_content_description),
                                    tint = MaterialTheme.colorScheme.error
                                )
                            }
                        }
                    }
                    Row(
                        horizontalArrangement = Arrangement.spacedBy(4.dp),
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        OutlinedTextField(
                            value = st.repsText,
                            onValueChange = { v -> patchSet { s -> s.copy(repsText = v) } },
                            label = { Text(stringResource(R.string.add_reps_field_label)) },
                            singleLine = true,
                            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                            modifier = Modifier.weight(1f)
                        )
                        OutlinedTextField(
                            value = st.weightText,
                            onValueChange = { patchSet { s -> s.copy(weightText = it) } },
                            label = { Text(stringResource(R.string.add_kg_field_label)) },
                            singleLine = true,
                            keyboardOptions = KeyboardOptions(
                                keyboardType = KeyboardType.Decimal
                            ),
                            modifier = Modifier.weight(1f)
                        )
                    }
                    Row(
                        horizontalArrangement = Arrangement.spacedBy(4.dp),
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        OutlinedTextField(
                            value = st.rpeText,
                            onValueChange = { patchSet { s -> s.copy(rpeText = it) } },
                            label = { Text(stringResource(R.string.add_rpe_field_label)) },
                            singleLine = true,
                            keyboardOptions = KeyboardOptions(
                                keyboardType = KeyboardType.Decimal
                            ),
                            modifier = Modifier.weight(1f)
                        )
                        OutlinedTextField(
                            value = st.restSecText,
                            onValueChange = { patchSet { s -> s.copy(restSecText = it) } },
                            label = { Text(stringResource(R.string.add_rest_sec_field_label)) },
                            singleLine = true,
                            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                            modifier = Modifier.weight(1f)
                        )
                    }
                }
                TextButton(
                    onClick = {
                        if (ex.sets.size < 20) {
                            replaceAt(
                                exIndex,
                                ex.copy(sets = ex.sets + StrengthSetDraft(setNumber = 1))
                            )
                        }
                    },
                    enabled = ex.sets.size < 20
                ) {
                    Icon(Icons.Filled.Add, contentDescription = null, modifier = Modifier.padding(end = 4.dp))
                    Text(stringResource(R.string.add_set_add))
                }
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

/** Tras quitar un set, deja al menos un bloque. */
private fun coalesceSets(sets: List<StrengthSetDraft>): List<StrengthSetDraft> {
    if (sets.isNotEmpty()) return sets
    return listOf(StrengthSetDraft())
}
