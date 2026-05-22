package com.lilru.liftr.ui.add

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Remove
import androidx.compose.material3.Card
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.VerticalDivider
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.lilru.liftr.R

/**
 * Editor de filas de fuerza (ejercicio + series) compartido entre Add workout y edición de plantillas.
 */
@Composable
fun StrengthExerciseDraftsEditorBlock(
    exercises: List<StrengthExerciseDraft>,
    loadingExercises: Boolean,
    showQuickActions: Boolean,
    onRecommendClick: () -> Unit,
    onPickExerciseClick: (draftId: String) -> Unit,
    onUpdateCustomName: (exerciseDraftId: String, customName: String) -> Unit,
    onUpdateNotes: (exerciseDraftId: String, notes: String) -> Unit,
    onBumpSetNumber: (exerciseDraftId: String, setDraftId: String, delta: Int) -> Unit,
    onRemoveSet: (exerciseDraftId: String, setDraftId: String) -> Unit,
    onUpdateSetReps: (exerciseDraftId: String, setDraftId: String, repsText: String) -> Unit,
    onUpdateSetWeight: (exerciseDraftId: String, setDraftId: String, weightText: String) -> Unit,
    onUpdateSetRpe: (exerciseDraftId: String, setDraftId: String, rpeText: String) -> Unit,
    onUpdateSetRestSec: (exerciseDraftId: String, setDraftId: String, restSecText: String) -> Unit,
    onEnableDropSet: (exerciseDraftId: String, setDraftId: String) -> Unit,
    onClearDropSet: (exerciseDraftId: String, setDraftId: String) -> Unit,
    onAddDropSegment: (exerciseDraftId: String, setDraftId: String) -> Unit,
    onRemoveLastDropSegment: (exerciseDraftId: String, setDraftId: String) -> Unit,
    onUpdateDropSegmentReps: (exerciseDraftId: String, setDraftId: String, segmentDraftId: String, repsText: String) -> Unit,
    onUpdateDropSegmentWeight: (exerciseDraftId: String, setDraftId: String, segmentDraftId: String, weightText: String) -> Unit,
    onAddSet: (exerciseDraftId: String) -> Unit,
    onMoveExerciseUp: (exerciseDraftId: String) -> Unit,
    onMoveExerciseDown: (exerciseDraftId: String) -> Unit,
    onRemoveExercise: (exerciseDraftId: String) -> Unit,
    onAddBlankExercise: () -> Unit,
    onClearAllExercises: () -> Unit,
    showClearAllButton: Boolean,
    onStartSuperset: ((exerciseDraftId: String) -> Unit)? = null,
    onAddNextToSuperset: ((exerciseDraftId: String) -> Unit)? = null,
    onRemoveFromSuperset: ((exerciseDraftId: String) -> Unit)? = null,
    modifier: Modifier = Modifier
) {
    Card(modifier = modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            if (showQuickActions) {
                Text(
                    stringResource(R.string.add_section_quick_actions),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                TextButton(
                    onClick = onRecommendClick,
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text("✦ ${stringResource(R.string.add_recommend_button)}")
                }
                HorizontalDivider()
            }
            Text(
                stringResource(R.string.add_section_lifts),
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Text(
                stringResource(R.string.add_lifts_reorder_hint),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            val lifts = exercises
            lifts.forEachIndexed { index, ex ->
                val canMoveUp = index > 0
                val canMoveDown = index < lifts.lastIndex
                val moreThanOne = lifts.size > 1
                Text(
                    stringResource(R.string.add_exercise_pick),
                    style = MaterialTheme.typography.titleSmall
                )
                OutlinedButton(
                    onClick = { onPickExerciseClick(ex.id) },
                    modifier = Modifier.fillMaxWidth(),
                    enabled = !loadingExercises
                ) {
                    Text(
                        ex.exerciseId?.let { ex.exerciseName.trim() }
                            ?.takeIf { it.isNotEmpty() }
                            ?: stringResource(R.string.add_exercise_tap_to_pick)
                    )
                }
                if (loadingExercises) {
                    Text(
                        stringResource(R.string.add_loading_exercises),
                        style = MaterialTheme.typography.bodySmall
                    )
                }
                OutlinedTextField(
                    value = ex.customName,
                    onValueChange = { onUpdateCustomName(ex.id, it) },
                    label = { Text(stringResource(R.string.add_exercise_alias_label)) },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )
                OutlinedTextField(
                    value = ex.notes,
                    onValueChange = { onUpdateNotes(ex.id, it) },
                    label = { Text(stringResource(R.string.add_exercise_notes_label)) },
                    modifier = Modifier.fillMaxWidth(),
                    minLines = 2,
                    maxLines = 4
                )
                if (
                    lifts.size >= 2 &&
                    onStartSuperset != null &&
                    onAddNextToSuperset != null &&
                    onRemoveFromSuperset != null
                ) {
                    val groupId = ex.supersetGroupId
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            stringResource(R.string.active_strength_superset_label),
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                        if (groupId != null) {
                            Text(
                                stringResource(
                                    R.string.add_strength_superset_group_format,
                                    supersetGroupDisplayNumber(groupId, lifts),
                                    ex.supersetPosition ?: 1
                                ),
                                style = MaterialTheme.typography.labelSmall
                            )
                            if (canAddNextToSuperset(lifts, groupId)) {
                                TextButton(onClick = { onAddNextToSuperset(ex.id) }) {
                                    Text(stringResource(R.string.add_strength_superset_add_next))
                                }
                            }
                            TextButton(onClick = { onRemoveFromSuperset(ex.id) }) {
                                Text(
                                    stringResource(R.string.add_strength_superset_remove),
                                    color = MaterialTheme.colorScheme.error
                                )
                            }
                        } else {
                            TextButton(
                                onClick = { onStartSuperset(ex.id) },
                                enabled = canStartSupersetAt(lifts, index)
                            ) {
                                Text(stringResource(R.string.add_strength_superset_with_next))
                            }
                        }
                    }
                }
                ex.sets.forEachIndexed { setIndex, set ->
                    val errColor = MaterialTheme.colorScheme.error
                    val sn = set.setNumber.coerceIn(1, 99)
                    Row(
                        modifier = Modifier.fillMaxWidth(),
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
                                        onClick = { onBumpSetNumber(ex.id, set.id, -1) },
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
                                        onClick = { onBumpSetNumber(ex.id, set.id, 1) },
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
                                    onClick = { onRemoveSet(ex.id, set.id) }
                                ) {
                                    Icon(
                                        imageVector = Icons.Filled.Delete,
                                        contentDescription = stringResource(R.string.add_set_remove_content_description),
                                        tint = errColor
                                    )
                                }
                            }
                        }
                    }
                    if (set.segments.size >= 2) {
                        set.segments.forEachIndexed { segIdx, seg ->
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(top = 4.dp),
                                horizontalArrangement = Arrangement.spacedBy(6.dp),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Text(
                                    stringResource(R.string.add_strength_drop_step_format, segIdx + 1),
                                    style = MaterialTheme.typography.labelMedium,
                                    modifier = Modifier.padding(end = 4.dp)
                                )
                                OutlinedTextField(
                                    value = seg.repsText,
                                    onValueChange = { onUpdateDropSegmentReps(ex.id, set.id, seg.id, it) },
                                    label = { Text(stringResource(R.string.add_reps_field_label)) },
                                    singleLine = true,
                                    modifier = Modifier.weight(1f)
                                )
                                OutlinedTextField(
                                    value = seg.weightText,
                                    onValueChange = { onUpdateDropSegmentWeight(ex.id, set.id, seg.id, it) },
                                    label = { Text(stringResource(R.string.add_kg_field_label)) },
                                    singleLine = true,
                                    modifier = Modifier.weight(1f)
                                )
                            }
                        }
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.spacedBy(8.dp)
                        ) {
                            TextButton(onClick = { onAddDropSegment(ex.id, set.id) }) {
                                Text(stringResource(R.string.add_strength_drop_add_step))
                            }
                            TextButton(
                                onClick = { onRemoveLastDropSegment(ex.id, set.id) },
                                enabled = set.segments.size > 2
                            ) {
                                Text(stringResource(R.string.add_strength_drop_remove_step))
                            }
                            TextButton(onClick = { onClearDropSet(ex.id, set.id) }) {
                                Text(stringResource(R.string.add_strength_drop_clear))
                            }
                        }
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(top = 4.dp),
                            horizontalArrangement = Arrangement.spacedBy(6.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            OutlinedTextField(
                                value = set.rpeText,
                                onValueChange = { onUpdateSetRpe(ex.id, set.id, it) },
                                label = { Text(stringResource(R.string.add_rpe_field_label)) },
                                singleLine = true,
                                modifier = Modifier.weight(1f)
                            )
                            OutlinedTextField(
                                value = set.restSecText,
                                onValueChange = { onUpdateSetRestSec(ex.id, set.id, it) },
                                label = { Text(stringResource(R.string.add_rest_sec_field_label)) },
                                singleLine = true,
                                modifier = Modifier.weight(1f)
                            )
                        }
                    } else {
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(top = 4.dp),
                            horizontalArrangement = Arrangement.spacedBy(6.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            OutlinedTextField(
                                value = set.repsText,
                                onValueChange = { onUpdateSetReps(ex.id, set.id, it) },
                                label = { Text(stringResource(R.string.add_reps_field_label)) },
                                singleLine = true,
                                modifier = Modifier.weight(1f)
                            )
                            OutlinedTextField(
                                value = set.weightText,
                                onValueChange = { onUpdateSetWeight(ex.id, set.id, it) },
                                label = { Text(stringResource(R.string.add_kg_field_label)) },
                                singleLine = true,
                                modifier = Modifier.weight(1f)
                            )
                            OutlinedTextField(
                                value = set.rpeText,
                                onValueChange = { onUpdateSetRpe(ex.id, set.id, it) },
                                label = { Text(stringResource(R.string.add_rpe_field_label)) },
                                singleLine = true,
                                modifier = Modifier.weight(1f)
                            )
                            OutlinedTextField(
                                value = set.restSecText,
                                onValueChange = { onUpdateSetRestSec(ex.id, set.id, it) },
                                label = { Text(stringResource(R.string.add_rest_sec_field_label)) },
                                singleLine = true,
                                modifier = Modifier.weight(1f)
                            )
                        }
                        TextButton(onClick = { onEnableDropSet(ex.id, set.id) }) {
                            Text(stringResource(R.string.add_strength_drop_set))
                        }
                    }
                }
                Column(Modifier.fillMaxWidth()) {
                    TextButton(
                        onClick = { onAddSet(ex.id) },
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text(stringResource(R.string.add_set_add))
                    }
                    Text(
                        stringResource(R.string.add_strength_next_row_hint, ex.sets.size + 1),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(start = 4.dp, bottom = 4.dp)
                    )
                }
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    if (canMoveUp) {
                        TextButton(onClick = { onMoveExerciseUp(ex.id) }) {
                            Text(stringResource(R.string.add_move_exercise_up))
                        }
                    }
                    if (canMoveDown) {
                        TextButton(onClick = { onMoveExerciseDown(ex.id) }) {
                            Text(stringResource(R.string.add_move_exercise_down))
                        }
                    }
                    if (moreThanOne) {
                        TextButton(
                            onClick = { onRemoveExercise(ex.id) }
                        ) {
                            Row(
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(6.dp)
                            ) {
                                Icon(
                                    imageVector = Icons.Filled.Delete,
                                    contentDescription = null,
                                    tint = MaterialTheme.colorScheme.error
                                )
                                Text(stringResource(R.string.add_remove_exercise))
                            }
                        }
                    }
                }
                if (index < lifts.lastIndex) {
                    HorizontalDivider(Modifier.padding(vertical = 6.dp))
                }
            }
            TextButton(
                onClick = onAddBlankExercise,
                modifier = Modifier.fillMaxWidth()
            ) {
                Text(stringResource(R.string.add_add_exercise))
            }
            if (showClearAllButton) {
                OutlinedButton(
                    onClick = onClearAllExercises,
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(stringResource(R.string.add_clear_all_exercises))
                }
            }
        }
    }
}
