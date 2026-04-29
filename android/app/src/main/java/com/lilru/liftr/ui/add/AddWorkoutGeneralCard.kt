package com.lilru.liftr.ui.add

import android.app.DatePickerDialog
import android.app.TimePickerDialog
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Card
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.MenuAnchorType
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.lilru.liftr.R
import java.time.Instant
import java.time.ZoneId
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter
import java.util.Locale

private val dateDisplayFmt: DateTimeFormatter =
    DateTimeFormatter.ofPattern("d MMM yyyy", Locale.getDefault())
private val timeDisplayFmt: DateTimeFormatter = DateTimeFormatter.ofPattern("HH:mm", Locale.getDefault())

private fun zonedFromIso(iso: String): ZonedDateTime {
    val i = runCatching { Instant.parse(iso.trim()) }.getOrNull() ?: Instant.now()
    return i.atZone(ZoneId.systemDefault())
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ScheduleDateTimeRow(
    label: String,
    valueIso: String,
    onValueIso: (String) -> Unit
) {
    val ctx = LocalContext.current
    val z = remember(valueIso) { zonedFromIso(valueIso) }
    Column(Modifier.fillMaxWidth()) {
        Text(
            text = label,
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(bottom = 4.dp)
        )
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            OutlinedButton(
                onClick = {
                    DatePickerDialog(
                        ctx,
                        { _, y, m, d ->
                            val base = zonedFromIso(valueIso)
                            val next = ZonedDateTime.of(
                                y,
                                m + 1,
                                d,
                                base.hour,
                                base.minute,
                                base.second,
                                base.nano,
                                ZoneId.systemDefault()
                            )
                            onValueIso(next.toInstant().toString())
                        },
                        z.year,
                        z.monthValue - 1,
                        z.dayOfMonth
                    ).show()
                },
                modifier = Modifier.weight(1f)
            ) { Text(z.format(dateDisplayFmt)) }
            OutlinedButton(
                onClick = {
                    TimePickerDialog(
                        ctx,
                        { _, h, min ->
                            val base = zonedFromIso(valueIso)
                            val next = ZonedDateTime.of(
                                base.year,
                                base.monthValue,
                                base.dayOfMonth,
                                h,
                                min,
                                base.second,
                                base.nano,
                                ZoneId.systemDefault()
                            )
                            onValueIso(next.toInstant().toString())
                        },
                        z.hour,
                        z.minute,
                        true
                    ).show()
                },
                modifier = Modifier.weight(1f)
            ) { Text(z.format(timeDisplayFmt)) }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun AddWorkoutGeneralCard(
    selectedKind: AddWorkoutKind,
    onKindChange: (AddWorkoutKind) -> Unit,
    selectedState: AddWorkoutState,
    onStateChange: (AddWorkoutState) -> Unit,
    title: String,
    onTitleChange: (String) -> Unit,
    startedAtIsoText: String,
    onStartedAtChange: (String) -> Unit,
    scheduleEndedEnabled: Boolean,
    onScheduleEndedChange: (Boolean) -> Unit,
    endedAtIsoText: String,
    onEndedAtChange: (String) -> Unit,
    scheduleDurationMin: Int?,
    notes: String,
    onNotesChange: (String) -> Unit,
    selectedIntensity: AddWorkoutIntensity,
    onIntensityChange: (AddWorkoutIntensity) -> Unit
) {
    var typeMenuExpanded by remember { mutableStateOf(false) }
    var intensityMenuExpanded by remember { mutableStateOf(false) }
    val kindText = when (selectedKind) {
        AddWorkoutKind.STRENGTH -> stringResource(R.string.add_kind_strength)
        AddWorkoutKind.CARDIO -> stringResource(R.string.add_kind_cardio)
        AddWorkoutKind.SPORT -> stringResource(R.string.add_kind_sport)
    }
    val intensityText = when (selectedIntensity) {
        AddWorkoutIntensity.EASY -> stringResource(R.string.add_intensity_easy)
        AddWorkoutIntensity.MODERATE -> stringResource(R.string.add_intensity_moderate)
        AddWorkoutIntensity.HARD -> stringResource(R.string.add_intensity_hard)
        AddWorkoutIntensity.MAX -> stringResource(R.string.add_intensity_max)
    }
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(0.dp)
        ) {
            ExposedDropdownMenuBox(
                expanded = typeMenuExpanded,
                onExpandedChange = { typeMenuExpanded = it },
                modifier = Modifier.fillMaxWidth()
            ) {
                OutlinedTextField(
                    value = kindText,
                    onValueChange = {},
                    readOnly = true,
                    singleLine = true,
                    label = { Text(stringResource(R.string.add_kind_label)) },
                    trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = typeMenuExpanded) },
                    modifier = Modifier
                        .menuAnchor(type = MenuAnchorType.PrimaryNotEditable, enabled = true)
                        .fillMaxWidth()
                )
                ExposedDropdownMenu(
                    expanded = typeMenuExpanded,
                    onDismissRequest = { typeMenuExpanded = false }
                ) {
                    AddWorkoutKind.entries.forEach { k ->
                        val label = when (k) {
                            AddWorkoutKind.STRENGTH -> stringResource(R.string.add_kind_strength)
                            AddWorkoutKind.CARDIO -> stringResource(R.string.add_kind_cardio)
                            AddWorkoutKind.SPORT -> stringResource(R.string.add_kind_sport)
                        }
                        DropdownMenuItem(
                            text = { Text(label) },
                            onClick = {
                                onKindChange(k)
                                typeMenuExpanded = false
                            }
                        )
                    }
                }
            }
            HorizontalDivider(Modifier.padding(vertical = 6.dp))
            Text(
                text = stringResource(R.string.add_mode_label),
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(bottom = 4.dp)
            )
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(vertical = 4.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                SingleChoiceSegmentedButtonRow(modifier = Modifier.fillMaxWidth()) {
                    SegmentedButton(
                        selected = selectedState == AddWorkoutState.PUBLISHED,
                        onClick = { onStateChange(AddWorkoutState.PUBLISHED) },
                        shape = SegmentedButtonDefaults.itemShape(index = 0, count = 2)
                    ) {
                        Text(stringResource(R.string.add_mode_add))
                    }
                    SegmentedButton(
                        selected = selectedState == AddWorkoutState.PLANNED,
                        onClick = { onStateChange(AddWorkoutState.PLANNED) },
                        shape = SegmentedButtonDefaults.itemShape(index = 1, count = 2)
                    ) {
                        Text(stringResource(R.string.add_mode_plan))
                    }
                }
                Text(
                    text = if (selectedState == AddWorkoutState.PUBLISHED) {
                        stringResource(R.string.add_mode_add_sub)
                    } else {
                        stringResource(R.string.add_mode_plan_sub)
                    },
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.fillMaxWidth()
                )
            }
            HorizontalDivider(Modifier.padding(vertical = 6.dp))
            OutlinedTextField(
                value = title,
                onValueChange = onTitleChange,
                label = { Text(stringResource(R.string.add_workout_title_label)) },
                singleLine = true,
                modifier = Modifier.fillMaxWidth()
            )
            ScheduleDateTimeRow(
                label = stringResource(R.string.add_field_started_at),
                valueIso = startedAtIsoText,
                onValueIso = { newStart ->
                    onStartedAtChange(newStart)
                    if (scheduleEndedEnabled) {
                        val st = runCatching { Instant.parse(newStart) }.getOrNull()
                        val en = runCatching { Instant.parse(endedAtIsoText.trim()) }.getOrNull()
                        if (st != null && en != null && en.isBefore(st)) {
                            onEndedAtChange(newStart)
                        }
                    }
                }
            )
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(vertical = 4.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Text(
                    stringResource(R.string.add_field_finished),
                    style = MaterialTheme.typography.bodyLarge
                )
                Switch(
                    checked = scheduleEndedEnabled,
                    onCheckedChange = onScheduleEndedChange
                )
            }
            if (scheduleEndedEnabled) {
                val startI = remember(startedAtIsoText) {
                    runCatching { Instant.parse(startedAtIsoText.trim()) }.getOrNull()
                }
                ScheduleDateTimeRow(
                    label = stringResource(R.string.add_field_ended_at),
                    valueIso = endedAtIsoText,
                    onValueIso = { newEnd ->
                        val e = runCatching { Instant.parse(newEnd) }.getOrNull()
                        if (startI != null && e != null && e.isBefore(startI)) {
                            onEndedAtChange(startI.toString())
                        } else {
                            onEndedAtChange(newEnd)
                        }
                    }
                )
                scheduleDurationMin?.let { dm ->
                    Text(
                        text = stringResource(R.string.add_duration_from_schedule, dm),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(vertical = 4.dp)
                    )
                }
            }
            HorizontalDivider(Modifier.padding(vertical = 6.dp))
            OutlinedTextField(
                value = notes,
                onValueChange = onNotesChange,
                label = { Text(stringResource(R.string.add_notes_label)) },
                minLines = 2,
                maxLines = 4,
                modifier = Modifier.fillMaxWidth()
            )
            ExposedDropdownMenuBox(
                expanded = intensityMenuExpanded,
                onExpandedChange = { intensityMenuExpanded = it },
                modifier = Modifier.fillMaxWidth()
            ) {
                OutlinedTextField(
                    value = intensityText,
                    onValueChange = {},
                    readOnly = true,
                    singleLine = true,
                    label = { Text(stringResource(R.string.add_intensity_label)) },
                    trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = intensityMenuExpanded) },
                    modifier = Modifier
                        .menuAnchor(type = MenuAnchorType.PrimaryNotEditable, enabled = true)
                        .fillMaxWidth()
                )
                ExposedDropdownMenu(
                    expanded = intensityMenuExpanded,
                    onDismissRequest = { intensityMenuExpanded = false }
                ) {
                    AddWorkoutIntensity.entries.forEach { v ->
                        val label = when (v) {
                            AddWorkoutIntensity.EASY -> stringResource(R.string.add_intensity_easy)
                            AddWorkoutIntensity.MODERATE -> stringResource(R.string.add_intensity_moderate)
                            AddWorkoutIntensity.HARD -> stringResource(R.string.add_intensity_hard)
                            AddWorkoutIntensity.MAX -> stringResource(R.string.add_intensity_max)
                        }
                        DropdownMenuItem(
                            text = { Text(label) },
                            onClick = {
                                onIntensityChange(v)
                                intensityMenuExpanded = false
                            }
                        )
                    }
                }
            }
        }
    }
}
