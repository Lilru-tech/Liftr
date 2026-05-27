package com.lilru.liftr.ui.add

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.lilru.liftr.R
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonArray

@Composable
fun EditHyroxRoutineTemplateSheetContent(
    edit: HyroxRoutineTemplateEdit,
    vm: AddWorkoutViewModel,
    onDismiss: () -> Unit
) {
    val canSave = remember(edit.exercisesJson) {
        runCatching {
            val arr = Json.parseToJsonElement(edit.exercisesJson.trim()).jsonArray
            arr.isNotEmpty()
        }.getOrDefault(false)
    }

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
                onClick = { vm.saveEditedHyroxRoutine() },
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
            edit.exercisesJson.isBlank() && edit.error != null -> {
                Text(
                    edit.error ?: "",
                    color = MaterialTheme.colorScheme.error,
                    style = MaterialTheme.typography.bodyMedium,
                    modifier = Modifier.padding(vertical = 8.dp)
                )
                TextButton(onClick = onDismiss) {
                    Text(stringResource(R.string.add_routine_sheet_close))
                }
            }
            else -> {
                Column(
                    modifier = Modifier.verticalScroll(rememberScrollState())
                ) {
                    edit.error?.let { err ->
                        Text(
                            err,
                            color = MaterialTheme.colorScheme.error,
                            style = MaterialTheme.typography.bodyMedium,
                            modifier = Modifier.padding(bottom = 8.dp)
                        )
                    }
                    Text(
                        stringResource(R.string.workout_detail_hyrox_stats_title),
                        style = MaterialTheme.typography.titleSmall,
                        modifier = Modifier.padding(bottom = 4.dp)
                    )
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
                        OutlinedTextField(
                            value = edit.sportStats["division"] ?: "",
                            onValueChange = {
                                vm.patchHyroxRoutineTemplateEdit { e ->
                                    e.copy(sportStats = e.sportStats + ("division" to it), error = null)
                                }
                            },
                            label = { Text(stringResource(R.string.workout_detail_hyrox_division)) },
                            singleLine = true,
                            modifier = Modifier.weight(1f),
                            enabled = !edit.saving
                        )
                        OutlinedTextField(
                            value = edit.sportStats["category"] ?: "",
                            onValueChange = {
                                vm.patchHyroxRoutineTemplateEdit { e ->
                                    e.copy(sportStats = e.sportStats + ("category" to it), error = null)
                                }
                            },
                            label = { Text(stringResource(R.string.workout_detail_hyrox_category)) },
                            singleLine = true,
                            modifier = Modifier.weight(1f),
                            enabled = !edit.saving
                        )
                    }
                    OutlinedTextField(
                        value = edit.sportStats["age_group"] ?: "",
                        onValueChange = {
                            vm.patchHyroxRoutineTemplateEdit { e ->
                                e.copy(sportStats = e.sportStats + ("age_group" to it), error = null)
                            }
                        },
                        label = { Text(stringResource(R.string.workout_detail_hyrox_age_group)) },
                        singleLine = true,
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(top = 8.dp),
                        enabled = !edit.saving
                    )
                    Row(
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(top = 8.dp)
                    ) {
                        OutlinedTextField(
                            value = edit.sportStats["official_time_sec"] ?: "",
                            onValueChange = {
                                vm.patchHyroxRoutineTemplateEdit { e ->
                                    e.copy(sportStats = e.sportStats + ("official_time_sec" to it), error = null)
                                }
                            },
                            label = { Text(stringResource(R.string.workout_detail_hyrox_official_time)) },
                            singleLine = true,
                            modifier = Modifier.weight(1f),
                            enabled = !edit.saving
                        )
                        OutlinedTextField(
                            value = edit.sportStats["penalty_time_sec"] ?: "",
                            onValueChange = {
                                vm.patchHyroxRoutineTemplateEdit { e ->
                                    e.copy(sportStats = e.sportStats + ("penalty_time_sec" to it), error = null)
                                }
                            },
                            label = { Text(stringResource(R.string.workout_detail_hyrox_penalty_time)) },
                            singleLine = true,
                            modifier = Modifier.weight(1f),
                            enabled = !edit.saving
                        )
                    }
                    Row(
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(top = 8.dp)
                    ) {
                        OutlinedTextField(
                            value = edit.sportStats["no_reps"] ?: "",
                            onValueChange = {
                                vm.patchHyroxRoutineTemplateEdit { e ->
                                    e.copy(sportStats = e.sportStats + ("no_reps" to it), error = null)
                                }
                            },
                            label = { Text(stringResource(R.string.workout_detail_hyrox_no_reps)) },
                            singleLine = true,
                            modifier = Modifier.weight(1f),
                            enabled = !edit.saving
                        )
                        OutlinedTextField(
                            value = edit.sportStats["rank_overall"] ?: "",
                            onValueChange = {
                                vm.patchHyroxRoutineTemplateEdit { e ->
                                    e.copy(sportStats = e.sportStats + ("rank_overall" to it), error = null)
                                }
                            },
                            label = { Text(stringResource(R.string.workout_detail_hyrox_rank_overall)) },
                            singleLine = true,
                            modifier = Modifier.weight(1f),
                            enabled = !edit.saving
                        )
                        OutlinedTextField(
                            value = edit.sportStats["rank_category"] ?: "",
                            onValueChange = {
                                vm.patchHyroxRoutineTemplateEdit { e ->
                                    e.copy(sportStats = e.sportStats + ("rank_category" to it), error = null)
                                }
                            },
                            label = { Text(stringResource(R.string.workout_detail_hyrox_rank_category)) },
                            singleLine = true,
                            modifier = Modifier.weight(1f),
                            enabled = !edit.saving
                        )
                    }
                    Row(
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(top = 8.dp)
                    ) {
                        OutlinedTextField(
                            value = edit.sportStats["avg_hr"] ?: "",
                            onValueChange = {
                                vm.patchHyroxRoutineTemplateEdit { e ->
                                    e.copy(sportStats = e.sportStats + ("avg_hr" to it), error = null)
                                }
                            },
                            label = { Text(stringResource(R.string.workout_detail_hyrox_avg_hr)) },
                            singleLine = true,
                            modifier = Modifier.weight(1f),
                            enabled = !edit.saving
                        )
                        OutlinedTextField(
                            value = edit.sportStats["max_hr"] ?: "",
                            onValueChange = {
                                vm.patchHyroxRoutineTemplateEdit { e ->
                                    e.copy(sportStats = e.sportStats + ("max_hr" to it), error = null)
                                }
                            },
                            label = { Text(stringResource(R.string.workout_detail_hyrox_max_hr)) },
                            singleLine = true,
                            modifier = Modifier.weight(1f),
                            enabled = !edit.saving
                        )
                    }
                    OutlinedTextField(
                        value = edit.exercisesJson,
                        onValueChange = {
                            vm.patchHyroxRoutineTemplateEdit { e -> e.copy(exercisesJson = it, error = null) }
                        },
                        label = { Text(stringResource(R.string.add_sport_hyrox_exercises_json_label)) },
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(top = 12.dp),
                        minLines = 6,
                        maxLines = 14,
                        enabled = !edit.saving
                    )
                }
            }
        }
    }
}
