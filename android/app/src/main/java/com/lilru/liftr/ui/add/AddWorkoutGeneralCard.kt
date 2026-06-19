package com.lilru.liftr.ui.add

import android.app.DatePickerDialog
import android.app.TimePickerDialog
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.MaterialTheme
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
import com.lilru.liftr.ui.components.LiftrFormDateTimeChips
import com.lilru.liftr.ui.components.LiftrFormDivider
import com.lilru.liftr.ui.components.LiftrFormInlineSegmented
import com.lilru.liftr.ui.components.LiftrFormNotesField
import com.lilru.liftr.ui.components.LiftrFormPickerValue
import com.lilru.liftr.ui.components.LiftrFormRow
import com.lilru.liftr.ui.components.LiftrFormTextValue
import com.lilru.liftr.ui.components.LiftrSectionCard
import dev.chrisbanes.haze.HazeState
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

@Composable
internal fun AddWorkoutGeneralCard(
    hazeState: HazeState,
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
    onIntensityChange: (AddWorkoutIntensity) -> Unit,
    showPlanTooltip: Boolean = false,
    onDismissPlanTooltip: () -> Unit = {}
) {
    val ctx = LocalContext.current
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
    val startedZ = remember(startedAtIsoText) { zonedFromIso(startedAtIsoText) }
    val endedZ = remember(endedAtIsoText) { zonedFromIso(endedAtIsoText) }
    val modeLabels = listOf(
        stringResource(R.string.add_mode_add),
        stringResource(R.string.add_mode_plan)
    )
    val modeSelectedIndex = if (selectedState == AddWorkoutState.PUBLISHED) 0 else 1

    LiftrSectionCard(hazeState = hazeState) {
        Column {
            LiftrFormRow(label = stringResource(R.string.add_kind_label)) {
                BoxWithMenus(
                    expanded = typeMenuExpanded,
                    onExpandedChange = { typeMenuExpanded = it },
                    value = kindText,
                    onDismiss = { typeMenuExpanded = false }
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
            LiftrFormDivider()
            LiftrFormRow(label = stringResource(R.string.add_mode_label)) {
                LiftrFormInlineSegmented(
                    labels = modeLabels,
                    selectedIndex = modeSelectedIndex,
                    onSelected = { index ->
                        onStateChange(
                            if (index == 0) AddWorkoutState.PUBLISHED else AddWorkoutState.PLANNED
                        )
                    }
                )
            }
            if (showPlanTooltip) {
                PlanModeFirstHintBubble(onDismiss = onDismissPlanTooltip)
            }
            LiftrFormDivider()
            LiftrFormRow(label = stringResource(R.string.add_workout_title_label)) {
                LiftrFormTextValue(
                    value = title,
                    onValueChange = onTitleChange,
                    placeholder = stringResource(R.string.add_workout_title_label)
                )
            }
            LiftrFormDivider()
            LiftrFormRow(label = stringResource(R.string.add_field_started_at)) {
                LiftrFormDateTimeChips(
                    dateLabel = startedZ.format(dateDisplayFmt),
                    timeLabel = startedZ.format(timeDisplayFmt),
                    onDateClick = {
                        DatePickerDialog(
                            ctx,
                            { _, y, m, d ->
                                val base = zonedFromIso(startedAtIsoText)
                                val next = ZonedDateTime.of(
                                    y, m + 1, d,
                                    base.hour, base.minute, base.second, base.nano,
                                    ZoneId.systemDefault()
                                )
                                val newStart = next.toInstant().toString()
                                onStartedAtChange(newStart)
                                if (scheduleEndedEnabled) {
                                    val st = next.toInstant()
                                    val en = runCatching { Instant.parse(endedAtIsoText.trim()) }.getOrNull()
                                    if (en != null && en.isBefore(st)) {
                                        onEndedAtChange(newStart)
                                    }
                                }
                            },
                            startedZ.year,
                            startedZ.monthValue - 1,
                            startedZ.dayOfMonth
                        ).show()
                    },
                    onTimeClick = {
                        TimePickerDialog(
                            ctx,
                            { _, h, min ->
                                val base = zonedFromIso(startedAtIsoText)
                                val next = ZonedDateTime.of(
                                    base.year, base.monthValue, base.dayOfMonth,
                                    h, min, base.second, base.nano,
                                    ZoneId.systemDefault()
                                )
                                val newStart = next.toInstant().toString()
                                onStartedAtChange(newStart)
                                if (scheduleEndedEnabled) {
                                    val st = next.toInstant()
                                    val en = runCatching { Instant.parse(endedAtIsoText.trim()) }.getOrNull()
                                    if (en != null && en.isBefore(st)) {
                                        onEndedAtChange(newStart)
                                    }
                                }
                            },
                            startedZ.hour,
                            startedZ.minute,
                            true
                        ).show()
                    }
                )
            }
            LiftrFormDivider()
            LiftrFormRow(label = stringResource(R.string.add_field_finished)) {
                Switch(
                    checked = scheduleEndedEnabled,
                    onCheckedChange = onScheduleEndedChange
                )
            }
            if (scheduleEndedEnabled) {
                LiftrFormDivider()
                LiftrFormRow(label = stringResource(R.string.add_field_ended_at)) {
                    LiftrFormDateTimeChips(
                        dateLabel = endedZ.format(dateDisplayFmt),
                        timeLabel = endedZ.format(timeDisplayFmt),
                        onDateClick = {
                            DatePickerDialog(
                                ctx,
                                { _, y, m, d ->
                                    val base = zonedFromIso(endedAtIsoText)
                                    val next = ZonedDateTime.of(
                                        y, m + 1, d,
                                        base.hour, base.minute, base.second, base.nano,
                                        ZoneId.systemDefault()
                                    )
                                    val newEnd = next.toInstant().toString()
                                    val startI = runCatching { Instant.parse(startedAtIsoText.trim()) }.getOrNull()
                                    val e = next.toInstant()
                                    if (startI != null && e.isBefore(startI)) {
                                        onEndedAtChange(startI.toString())
                                    } else {
                                        onEndedAtChange(newEnd)
                                    }
                                },
                                endedZ.year,
                                endedZ.monthValue - 1,
                                endedZ.dayOfMonth
                            ).show()
                        },
                        onTimeClick = {
                            TimePickerDialog(
                                ctx,
                                { _, h, min ->
                                    val base = zonedFromIso(endedAtIsoText)
                                    val next = ZonedDateTime.of(
                                        base.year, base.monthValue, base.dayOfMonth,
                                        h, min, base.second, base.nano,
                                        ZoneId.systemDefault()
                                    )
                                    val newEnd = next.toInstant().toString()
                                    val startI = runCatching { Instant.parse(startedAtIsoText.trim()) }.getOrNull()
                                    val e = next.toInstant()
                                    if (startI != null && e.isBefore(startI)) {
                                        onEndedAtChange(startI.toString())
                                    } else {
                                        onEndedAtChange(newEnd)
                                    }
                                },
                                endedZ.hour,
                                endedZ.minute,
                                true
                            ).show()
                        }
                    )
                }
                scheduleDurationMin?.let { dm ->
                    Text(
                        text = stringResource(R.string.add_duration_from_schedule, dm),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(bottom = 8.dp)
                    )
                }
            }
            LiftrFormDivider()
            LiftrFormNotesField(
                label = stringResource(R.string.add_notes_label),
                value = notes,
                onValueChange = onNotesChange,
                placeholder = stringResource(R.string.add_notes_label)
            )
            LiftrFormDivider()
            LiftrFormRow(label = stringResource(R.string.add_intensity_label)) {
                BoxWithMenus(
                    expanded = intensityMenuExpanded,
                    onExpandedChange = { intensityMenuExpanded = it },
                    value = intensityText,
                    onDismiss = { intensityMenuExpanded = false }
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

@Composable
private fun BoxWithMenus(
    expanded: Boolean,
    onExpandedChange: (Boolean) -> Unit,
    value: String,
    onDismiss: () -> Unit,
    menuContent: @Composable () -> Unit
) {
    Box {
        LiftrFormPickerValue(
            value = value,
            onClick = { onExpandedChange(true) }
        )
        DropdownMenu(
            expanded = expanded,
            onDismissRequest = onDismiss
        ) {
            menuContent()
        }
    }
}

@Composable
private fun PlanModeFirstHintBubble(onDismiss: () -> Unit) {
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 4.dp),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.55f)
        )
    ) {
        Row(
            modifier = Modifier.padding(10.dp),
            verticalAlignment = Alignment.Top,
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(4.dp)
            ) {
                Text(
                    text = stringResource(R.string.add_mode_plan_tooltip_title),
                    style = MaterialTheme.typography.labelLarge
                )
                Text(
                    text = stringResource(R.string.add_mode_plan_tooltip_body),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            TextButton(onClick = onDismiss) {
                Text(stringResource(R.string.add_mode_plan_tooltip_ok))
            }
        }
    }
}
