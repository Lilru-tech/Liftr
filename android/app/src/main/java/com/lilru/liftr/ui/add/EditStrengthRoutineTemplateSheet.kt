package com.lilru.liftr.ui.add

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.lilru.liftr.R

@Composable
fun EditStrengthRoutineTemplateSheetContent(
    edit: StrengthRoutineTemplateEdit,
    loadingExercises: Boolean,
    vm: AddWorkoutViewModel,
    onRequestExercisePick: (draftId: String) -> Unit,
    onDismiss: () -> Unit
) {
    var showClearDialog by remember { mutableStateOf(false) }
    val canSave = remember(edit.drafts) {
        runCatching { buildStrengthPayloadItemsForRoutineUpdate(edit.drafts) }.isSuccess
    }
    val canClearAll = edit.drafts.size > 1 ||
        edit.drafts.any { it.exerciseId != null || it.exerciseName.isNotBlank() }

    Column(
        modifier = Modifier
            .navigationBarsPadding()
            .padding(horizontal = 16.dp, vertical = 8.dp)
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Text(
                text = edit.routineName,
                style = MaterialTheme.typography.titleLarge,
                modifier = Modifier.weight(1f)
            )
            TextButton(
                onClick = onDismiss,
                enabled = !edit.saving
            ) {
                Text(stringResource(R.string.add_routine_dialog_cancel))
            }
            Button(
                onClick = { vm.saveEditedRoutine() },
                enabled = !edit.loading && !edit.saving && canSave
            ) {
                Text(stringResource(R.string.add_routine_save_action))
            }
        }
        when {
            edit.loading -> {
                Row(
                    Modifier
                        .fillMaxWidth()
                        .padding(24.dp),
                    horizontalArrangement = Arrangement.Center
                ) {
                    CircularProgressIndicator()
                }
            }
            edit.drafts.isEmpty() -> {
                edit.error?.let { err ->
                    Text(
                        err,
                        color = MaterialTheme.colorScheme.error,
                        style = MaterialTheme.typography.bodyMedium,
                        modifier = Modifier.padding(vertical = 8.dp)
                    )
                }
                TextButton(onClick = onDismiss) {
                    Text(stringResource(R.string.add_routine_sheet_close))
                }
            }
            else -> {
                Column(
                    modifier = Modifier
                        .verticalScroll(rememberScrollState())
                ) {
                    edit.error?.let { err ->
                        Text(
                            err,
                            color = MaterialTheme.colorScheme.error,
                            style = MaterialTheme.typography.bodySmall,
                            modifier = Modifier.padding(bottom = 8.dp)
                        )
                    }
                    StrengthExerciseDraftsEditorBlock(
                        exercises = edit.drafts,
                        loadingExercises = loadingExercises,
                        showQuickActions = false,
                        onRecommendClick = { },
                        onPickExerciseClick = onRequestExercisePick,
                        onUpdateCustomName = { id, v -> vm.templateEditUpdateExerciseCustomName(id, v) },
                        onUpdateNotes = { id, v -> vm.templateEditUpdateExerciseNotes(id, v) },
                        onBumpSetNumber = { e, s, d -> vm.templateEditBumpSetNumber(e, s, d) },
                        onRemoveSet = { e, s -> vm.templateEditRemoveSet(e, s) },
                        onUpdateSetReps = { e, s, v -> vm.templateEditUpdateSetReps(e, s, v) },
                        onUpdateSetWeight = { e, s, v -> vm.templateEditUpdateSetWeight(e, s, v) },
                        onUpdateSetRpe = { e, s, v -> vm.templateEditUpdateSetRpe(e, s, v) },
                        onUpdateSetRestSec = { e, s, v -> vm.templateEditUpdateSetRestSec(e, s, v) },
                        onEnableDropSet = { e, s -> vm.templateEditEnableDropSet(e, s) },
                        onClearDropSet = { e, s -> vm.templateEditClearDropSet(e, s) },
                        onAddDropSegment = { e, s -> vm.templateEditAddDropSegment(e, s) },
                        onRemoveLastDropSegment = { e, s -> vm.templateEditRemoveLastDropSegment(e, s) },
                        onUpdateDropSegmentReps = { e, s, seg, v -> vm.templateEditUpdateDropSegmentReps(e, s, seg, v) },
                        onUpdateDropSegmentWeight = { e, s, seg, v -> vm.templateEditUpdateDropSegmentWeight(e, s, seg, v) },
                        onAddSet = { vm.templateEditAddSet(it) },
                        onMoveExerciseUp = { vm.templateEditMoveExerciseUp(it) },
                        onMoveExerciseDown = { vm.templateEditMoveExerciseDown(it) },
                        onRemoveExercise = { vm.templateEditRemoveExercise(it) },
                        onAddBlankExercise = { vm.templateEditAddBlankStrengthExercise() },
                        onClearAllExercises = { showClearDialog = true },
                        showClearAllButton = canClearAll
                    )
                }
            }
        }
    }
    if (showClearDialog) {
        AlertDialog(
            onDismissRequest = { showClearDialog = false },
            title = { Text(stringResource(R.string.add_clear_all_exercises)) },
            text = { Text(stringResource(R.string.add_clear_all_exercises_message)) },
            confirmButton = {
                TextButton(
                    onClick = {
                        showClearDialog = false
                        vm.templateEditClearAllStrengthExercises()
                    }
                ) {
                    Text(stringResource(R.string.add_clear_all_exercises_confirm))
                }
            },
            dismissButton = {
                TextButton(onClick = { showClearDialog = false }) {
                    Text(stringResource(R.string.add_routine_dialog_cancel))
                }
            }
        )
    }
}
