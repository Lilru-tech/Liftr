package com.lilru.liftr.ui.home

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Remove
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material3.Button
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.VerticalDivider
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.lilru.liftr.R
import com.lilru.liftr.ui.add.AddWorkoutIntensity
import com.lilru.liftr.ui.add.StrengthExerciseDraft
import com.lilru.liftr.ui.add.StrengthSegmentDraft
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
                    val sn = st.setNumber.coerceIn(1, 99)
                    Row(
                        Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        Column(Modifier.weight(1f, fill = false)) {
                            Text(
                                stringResource(R.string.add_strength_set_slot_format, setIndex + 1),
                                style = MaterialTheme.typography.titleSmall,
                                fontWeight = FontWeight.SemiBold
                            )
                            Text(
                                stringResource(R.string.add_strength_repeat_times_label),
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Surface(
                                shape = RoundedCornerShape(20.dp),
                                color = MaterialTheme.colorScheme.surfaceVariant
                            ) {
                                Row(verticalAlignment = Alignment.CenterVertically) {
                                    IconButton(
                                        onClick = {
                                            patchSet { s ->
                                                s.copy(setNumber = (s.setNumber - 1).coerceIn(1, 99))
                                            }
                                        },
                                        enabled = sn > 1,
                                        modifier = Modifier.heightIn(max = 40.dp)
                                    ) {
                                        Icon(
                                            imageVector = Icons.Filled.Remove,
                                            contentDescription = stringResource(R.string.add_set_stepper_minus)
                                        )
                                    }
                                    VerticalDivider(Modifier.height(24.dp))
                                    Text(
                                        stringResource(R.string.add_strength_repeat_times_format, sn),
                                        style = MaterialTheme.typography.titleSmall,
                                        modifier = Modifier.padding(horizontal = 6.dp)
                                    )
                                    VerticalDivider(Modifier.height(24.dp))
                                    IconButton(
                                        onClick = {
                                            patchSet { s ->
                                                s.copy(setNumber = (s.setNumber + 1).coerceIn(1, 99))
                                            }
                                        },
                                        enabled = sn < 99,
                                        modifier = Modifier.heightIn(max = 40.dp)
                                    ) {
                                        Icon(
                                            imageVector = Icons.Filled.Add,
                                            contentDescription = stringResource(R.string.add_set_stepper_plus)
                                        )
                                    }
                                }
                            }
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
                    }
                    if (st.segments.size >= 2) {
                        st.segments.forEachIndexed { segIdx, seg ->
                            Row(
                                horizontalArrangement = Arrangement.spacedBy(6.dp),
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(top = 4.dp),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Text(
                                    stringResource(R.string.add_strength_drop_step_format, segIdx + 1),
                                    style = MaterialTheme.typography.labelMedium,
                                    modifier = Modifier.padding(end = 4.dp)
                                )
                                OutlinedTextField(
                                    value = seg.repsText,
                                    onValueChange = { v ->
                                        patchSet { s ->
                                            s.copy(
                                                segments = s.segments.mapIndexed { j, e ->
                                                    if (j == segIdx) e.copy(repsText = v) else e
                                                }
                                            )
                                        }
                                    },
                                    label = { Text(stringResource(R.string.add_reps_field_label)) },
                                    singleLine = true,
                                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                                    modifier = Modifier.weight(1f)
                                )
                                OutlinedTextField(
                                    value = seg.weightText,
                                    onValueChange = { v ->
                                        patchSet { s ->
                                            s.copy(
                                                segments = s.segments.mapIndexed { j, e ->
                                                    if (j == segIdx) e.copy(weightText = v) else e
                                                }
                                            )
                                        }
                                    },
                                    label = { Text(stringResource(R.string.add_kg_field_label)) },
                                    singleLine = true,
                                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                                    modifier = Modifier.weight(1f)
                                )
                            }
                        }
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.spacedBy(8.dp)
                        ) {
                            TextButton(
                                onClick = {
                                    patchSet { s ->
                                        s.copy(segments = s.segments + StrengthSegmentDraft())
                                    }
                                }
                            ) {
                                Text(stringResource(R.string.add_strength_drop_add_step))
                            }
                            TextButton(
                                onClick = {
                                    patchSet { s ->
                                        if (s.segments.size > 2) {
                                            s.copy(segments = s.segments.dropLast(1))
                                        } else {
                                            s
                                        }
                                    }
                                },
                                enabled = st.segments.size > 2
                            ) {
                                Text(stringResource(R.string.add_strength_drop_remove_step))
                            }
                            TextButton(
                                onClick = { patchSet { s -> s.copy(segments = emptyList()) } }
                            ) {
                                Text(stringResource(R.string.add_strength_drop_clear))
                            }
                        }
                        Row(
                            horizontalArrangement = Arrangement.spacedBy(4.dp),
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(top = 4.dp)
                        ) {
                            OutlinedTextField(
                                value = st.rpeText,
                                onValueChange = { patchSet { s -> s.copy(rpeText = it) } },
                                label = { Text(stringResource(R.string.add_rpe_field_label)) },
                                singleLine = true,
                                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
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
                    } else {
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
                        TextButton(
                            onClick = {
                                patchSet { s ->
                                    s.copy(
                                        segments = listOf(
                                            StrengthSegmentDraft(repsText = s.repsText, weightText = s.weightText),
                                            StrengthSegmentDraft()
                                        )
                                    )
                                }
                            },
                            modifier = Modifier.padding(top = 4.dp)
                        ) {
                            Text(stringResource(R.string.add_strength_drop_set))
                        }
                    }
                }
                Column(Modifier.fillMaxWidth()) {
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
                    Text(
                        stringResource(R.string.add_strength_next_row_hint, ex.sets.size + 1),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(start = 4.dp, bottom = 4.dp)
                    )
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
