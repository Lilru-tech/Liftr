package com.lilru.liftr.ui.nutrition

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.Button
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
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
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.lilru.liftr.R
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle

private enum class InsightsDatePickTarget { FROM, TO }

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
            stringResource(R.string.nutrition_insights_title),
            style = MaterialTheme.typography.titleSmall,
            fontWeight = FontWeight.SemiBold
        )
        Row(
            modifier = Modifier.horizontalScroll(rememberScrollState()),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            FilterChip(
                selected = ui.insightsQuickPreset == NutritionInsightsQuickPreset.ONE_DAY,
                onClick = { vm.applyInsightsQuickPreset(NutritionInsightsQuickPreset.ONE_DAY) },
                label = { Text(stringResource(R.string.nutrition_insights_pill_one_day)) }
            )
            FilterChip(
                selected = ui.insightsQuickPreset == NutritionInsightsQuickPreset.ONE_WEEK,
                onClick = { vm.applyInsightsQuickPreset(NutritionInsightsQuickPreset.ONE_WEEK) },
                label = { Text(stringResource(R.string.nutrition_insights_pill_one_week)) }
            )
            FilterChip(
                selected = ui.insightsQuickPreset == NutritionInsightsQuickPreset.ONE_MONTH,
                onClick = { vm.applyInsightsQuickPreset(NutritionInsightsQuickPreset.ONE_MONTH) },
                label = { Text(stringResource(R.string.nutrition_insights_pill_one_month)) }
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
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            TextButton(
                onClick = { datePickTarget = InsightsDatePickTarget.FROM },
                modifier = Modifier.weight(1f)
            ) {
                Text(
                    stringResource(R.string.nutrition_insights_from_date, rangeFormatter.format(ui.insightsFromDate)),
                    style = MaterialTheme.typography.bodyMedium
                )
            }
            TextButton(
                onClick = { datePickTarget = InsightsDatePickTarget.TO },
                modifier = Modifier.weight(1f)
            ) {
                Text(
                    stringResource(R.string.nutrition_insights_to_date, rangeFormatter.format(ui.insightsToDate)),
                    style = MaterialTheme.typography.bodyMedium
                )
            }
        }
        Button(
            onClick = onAnalyze,
            modifier = Modifier.fillMaxWidth(),
            enabled = !ui.insightsFromDate.isAfter(ui.insightsToDate)
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
