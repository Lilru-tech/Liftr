package com.lilru.liftr.ui.nutrition

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.lilru.liftr.R
import com.lilru.liftr.ui.components.LiftrFormDivider
import com.lilru.liftr.ui.components.LiftrFormRow
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle

private enum class InsightsDatePickTarget { FROM, TO }

private val InsightsAccentBlue = Color(0xFF007AFF)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun NutritionInsightsRangeCard(
    ui: NutritionUiState,
    vm: NutritionViewModel,
    onAnalyze: () -> Unit,
    modifier: Modifier = Modifier
) {
    var datePickTarget by remember { mutableStateOf<InsightsDatePickTarget?>(null) }
    val rangeFormatter = remember { DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM) }
    val zone = remember { ZoneId.systemDefault() }

    Column(modifier = modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(
            stringResource(R.string.nutrition_insights_range_title),
            style = MaterialTheme.typography.titleSmall,
            fontWeight = FontWeight.SemiBold
        )
        Row(
            modifier = Modifier.horizontalScroll(rememberScrollState()),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            InsightsQuickPill(
                label = stringResource(R.string.nutrition_insights_pill_one_day),
                selected = ui.insightsQuickPreset == NutritionInsightsQuickPreset.ONE_DAY,
                onClick = { vm.applyInsightsQuickPreset(NutritionInsightsQuickPreset.ONE_DAY) }
            )
            InsightsQuickPill(
                label = stringResource(R.string.nutrition_insights_pill_one_week),
                selected = ui.insightsQuickPreset == NutritionInsightsQuickPreset.ONE_WEEK,
                onClick = { vm.applyInsightsQuickPreset(NutritionInsightsQuickPreset.ONE_WEEK) }
            )
            InsightsQuickPill(
                label = stringResource(R.string.nutrition_insights_pill_one_month),
                selected = ui.insightsQuickPreset == NutritionInsightsQuickPreset.ONE_MONTH,
                onClick = { vm.applyInsightsQuickPreset(NutritionInsightsQuickPreset.ONE_MONTH) }
            )
        }
        Text(
            stringResource(
                R.string.nutrition_insights_selected_range,
                rangeFormatter.format(ui.insightsFromDate),
                rangeFormatter.format(ui.insightsToDate)
            ),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        LiftrFormRow(label = stringResource(R.string.nutrition_insights_from_label)) {
            InsightsDateChip(
                label = rangeFormatter.format(ui.insightsFromDate),
                onClick = { datePickTarget = InsightsDatePickTarget.FROM }
            )
        }
        LiftrFormDivider()
        LiftrFormRow(label = stringResource(R.string.nutrition_insights_to_label)) {
            InsightsDateChip(
                label = rangeFormatter.format(ui.insightsToDate),
                onClick = { datePickTarget = InsightsDatePickTarget.TO }
            )
        }
        Button(
            onClick = onAnalyze,
            modifier = Modifier.fillMaxWidth(),
            enabled = !ui.insightsFromDate.isAfter(ui.insightsToDate),
            colors = ButtonDefaults.buttonColors(containerColor = InsightsAccentBlue),
            shape = RoundedCornerShape(50)
        ) {
            Text(stringResource(R.string.nutrition_insights_analyze))
        }
    }

    val target = datePickTarget
    if (target != null) {
        val initial = when (target) {
            InsightsDatePickTarget.FROM -> ui.insightsFromDate
            InsightsDatePickTarget.TO -> ui.insightsToDate
        }
        val initialMillis = initial.atStartOfDay(zone).toInstant().toEpochMilli()
        val state = rememberDatePickerState(initialSelectedDateMillis = initialMillis)
        DatePickerDialog(
            onDismissRequest = { datePickTarget = null },
            confirmButton = {
                TextButton(
                    onClick = {
                        state.selectedDateMillis?.let { ms ->
                            val d = Instant.ofEpochMilli(ms).atZone(zone).toLocalDate()
                            when (target) {
                                InsightsDatePickTarget.FROM -> vm.setInsightsFromDate(d)
                                InsightsDatePickTarget.TO -> vm.setInsightsToDate(d)
                            }
                        }
                        datePickTarget = null
                    }
                ) { Text(stringResource(R.string.auth_ok)) }
            },
            dismissButton = {
                TextButton(onClick = { datePickTarget = null }) {
                    Text(stringResource(R.string.goals_delete_cancel))
                }
            }
        ) {
            DatePicker(state = state)
        }
    }
}

@Composable
private fun InsightsQuickPill(
    label: String,
    selected: Boolean,
    onClick: () -> Unit
) {
    val shape = RoundedCornerShape(50)
    val bg = if (selected) InsightsAccentBlue.copy(alpha = 0.14f) else Color.White.copy(alpha = 0.35f)
    val borderColor = if (selected) InsightsAccentBlue.copy(alpha = 0.55f) else Color.White.copy(alpha = 0.35f)
    Text(
        text = label,
        style = MaterialTheme.typography.labelLarge,
        fontWeight = FontWeight.SemiBold,
        color = if (selected) InsightsAccentBlue else MaterialTheme.colorScheme.onSurface,
        modifier = Modifier
            .clip(shape)
            .background(bg)
            .border(1.dp, borderColor, shape)
            .clickable(onClick = onClick)
            .padding(horizontal = 12.dp, vertical = 8.dp)
    )
}

@Composable
private fun InsightsDateChip(
    label: String,
    onClick: () -> Unit
) {
    Text(
        text = label,
        style = MaterialTheme.typography.bodyMedium,
        color = MaterialTheme.colorScheme.onSurface,
        modifier = Modifier
            .clip(RoundedCornerShape(10.dp))
            .background(Color.White.copy(alpha = 0.45f))
            .clickable(onClick = onClick)
            .padding(horizontal = 12.dp, vertical = 8.dp)
    )
}
