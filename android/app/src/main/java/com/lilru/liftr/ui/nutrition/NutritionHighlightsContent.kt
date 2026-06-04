package com.lilru.liftr.ui.nutrition

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material3.Icon
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.lilru.liftr.R
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import kotlin.math.roundToInt

@Composable
fun NutritionHighlightsContent(
    ui: NutritionUiState,
    onRankingClick: (NutritionRankingKind) -> Unit = {},
    modifier: Modifier = Modifier
) {
    when {
        ui.highlightsLoading -> {
            Column(
                modifier.fillMaxWidth().padding(24.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                CircularProgressIndicator()
            }
        }
        ui.highlightsError != null -> {
            Card(
                modifier = modifier.fillMaxWidth(),
                colors = CardDefaults.cardColors(
                    containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.45f)
                )
            ) {
                Text(
                    ui.highlightsError,
                    modifier = Modifier.padding(14.dp),
                    color = MaterialTheme.colorScheme.error,
                    style = MaterialTheme.typography.bodyMedium
                )
            }
        }
        ui.highlights == null -> Unit
        !ui.highlights.hasAnyLogs -> {
            Card(
                modifier = modifier.fillMaxWidth(),
                colors = CardDefaults.cardColors(
                    containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.45f)
                )
            ) {
                Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(
                        stringResource(R.string.nutrition_highlights_empty_title),
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.SemiBold
                    )
                    Text(
                        stringResource(R.string.nutrition_highlights_empty_body),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
        }
        else -> {
            val h = ui.highlights
            Column(modifier, verticalArrangement = Arrangement.spacedBy(16.dp)) {
                HighlightsSectionCard(
                    title = stringResource(R.string.nutrition_highlights_overview),
                    content = {
                        Row(
                            Modifier.horizontalScroll(rememberScrollState()),
                            horizontalArrangement = Arrangement.spacedBy(10.dp)
                        ) {
                            HighlightsStatPill(
                                label = stringResource(R.string.nutrition_highlights_days_logged),
                                value = h.daysLogged.toString()
                            )
                            HighlightsStatPill(
                                label = stringResource(R.string.nutrition_highlights_entries),
                                value = h.totalLogEntries.toString()
                            )
                            HighlightsStatPill(
                                label = stringResource(R.string.nutrition_highlights_avg_kcal),
                                value = stringResource(
                                    R.string.nutrition_kcal_format,
                                    h.avgKcalPerLoggedDay.roundToInt()
                                )
                            )
                        }
                        val first = h.firstLogDate
                        val last = h.lastLogDate
                        if (first != null && last != null) {
                            Text(
                                stringResource(
                                    R.string.nutrition_highlights_tracking_range,
                                    formatHighlightDate(first),
                                    formatHighlightDate(last)
                                ),
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    }
                )
                HighlightsSectionCard(
                    title = stringResource(R.string.nutrition_highlights_records),
                    content = {
                        h.peakDay?.let { peak ->
                            NavigableHighlightsRecordRow(
                                title = stringResource(R.string.nutrition_highlights_peak_day),
                                detail = formatHighlightDate(peak.date),
                                value = stringResource(R.string.nutrition_kcal_format, peak.kcal.roundToInt()),
                                onClick = { onRankingClick(NutritionRankingKind.HIGHEST_CALORIE_DAYS) }
                            )
                        }
                        h.peakMealSlot?.let { meal ->
                            NavigableHighlightsRecordRow(
                                title = stringResource(R.string.nutrition_highlights_peak_meal),
                                detail = "${meal.mealSlot} · ${formatHighlightDate(meal.date)}",
                                value = stringResource(R.string.nutrition_kcal_format, meal.kcal.roundToInt()),
                                onClick = { onRankingClick(NutritionRankingKind.HIGHEST_CALORIE_MEALS) }
                            )
                        }
                    }
                )
                HighlightsSectionCard(
                    title = stringResource(R.string.nutrition_highlights_most_logged),
                    content = {
                        h.topIngredient?.let { ing ->
                            NavigableHighlightsFoodRow(
                                kind = stringResource(R.string.nutrition_highlights_ingredient),
                                name = ing.name,
                                count = ing.logCount,
                                totalKcal = ing.totalKcal,
                                onClick = { onRankingClick(NutritionRankingKind.MOST_LOGGED_INGREDIENTS) }
                            )
                        }
                        h.topRecipe?.let { rec ->
                            NavigableHighlightsFoodRow(
                                kind = stringResource(R.string.nutrition_highlights_recipe),
                                name = rec.name,
                                count = rec.logCount,
                                totalKcal = rec.totalKcal,
                                onClick = { onRankingClick(NutritionRankingKind.MOST_LOGGED_RECIPES) }
                            )
                        }
                    }
                )
                HighlightsSectionCard(
                    title = stringResource(R.string.nutrition_highlights_habits),
                    content = {
                        h.mostUsedMealSlot?.let { slot ->
                            HighlightsRecordRow(
                                title = stringResource(R.string.nutrition_highlights_most_used_slot),
                                detail = slot,
                                value = null
                            )
                        }
                        val ingredientShare = (100 - h.recipeLogSharePercent).coerceIn(0.0, 100.0)
                        HighlightsRecordRow(
                            title = stringResource(R.string.nutrition_highlights_log_mix),
                            detail = stringResource(
                                R.string.nutrition_highlights_log_mix_detail,
                                ingredientShare.roundToInt(),
                                h.recipeLogSharePercent.roundToInt()
                            ),
                            value = null
                        )
                    }
                )
                h.macroChampions?.let { macro ->
                    if (macro.topProteinSource != null || macro.topCarbSource != null) {
                        HighlightsSectionCard(
                            title = stringResource(R.string.nutrition_highlights_macro_champions),
                            content = {
                                macro.topProteinSource?.let { protein ->
                                    HighlightsRecordRow(
                                        title = stringResource(R.string.nutrition_highlights_top_protein),
                                        detail = protein.name,
                                        value = formatHighlightGrams(protein.totalG)
                                    )
                                }
                                macro.topCarbSource?.let { carbs ->
                                    HighlightsRecordRow(
                                        title = stringResource(R.string.nutrition_highlights_top_carb),
                                        detail = carbs.name,
                                        value = formatHighlightGrams(carbs.totalG)
                                    )
                                }
                            }
                        )
                    }
                }
                h.calorieVolatility?.let { vol ->
                    if (vol.weekdayAvgKcal > 0 || vol.weekendAvgKcal > 0) {
                        HighlightsSectionCard(
                            title = stringResource(R.string.nutrition_highlights_weekly_habits),
                            content = {
                                Row(
                                    Modifier.horizontalScroll(rememberScrollState()),
                                    horizontalArrangement = Arrangement.spacedBy(10.dp)
                                ) {
                                    HighlightsStatPill(
                                        label = stringResource(R.string.nutrition_highlights_weekday_avg),
                                        value = stringResource(
                                            R.string.nutrition_kcal_format,
                                            vol.weekdayAvgKcal.roundToInt()
                                        )
                                    )
                                    HighlightsStatPill(
                                        label = stringResource(R.string.nutrition_highlights_weekend_avg),
                                        value = stringResource(
                                            R.string.nutrition_kcal_format,
                                            vol.weekendAvgKcal.roundToInt()
                                        )
                                    )
                                }
                            }
                        )
                    }
                }
                h.heaviestMeal?.let { meal ->
                    HighlightsSectionCard(
                        title = stringResource(R.string.nutrition_highlights_heaviest_meal),
                        content = {
                            NavigableHighlightsRecordRow(
                                title = meal.mealSlot,
                                detail = formatHighlightDate(meal.date),
                                value = formatHighlightGrams(meal.totalWeightG),
                                onClick = { onRankingClick(NutritionRankingKind.HEAVIEST_MEALS) }
                            )
                        }
                    )
                }
                h.consistencyStreak?.let { streak ->
                    if (streak.currentStreak > 0 || streak.bestStreak > 0) {
                        HighlightsSectionCard(
                            title = stringResource(R.string.nutrition_highlights_consistency_streak),
                            content = {
                                Row(
                                    Modifier.horizontalScroll(rememberScrollState()),
                                    horizontalArrangement = Arrangement.spacedBy(10.dp)
                                ) {
                                    HighlightsStatPill(
                                        label = stringResource(R.string.nutrition_highlights_streak_current),
                                        value = streakDaysLabel(streak.currentStreak)
                                    )
                                    HighlightsStatPill(
                                        label = stringResource(R.string.nutrition_highlights_streak_best),
                                        value = streakDaysLabel(streak.bestStreak)
                                    )
                                }
                            }
                        )
                    }
                }
            }
        }
    }
}

private fun formatHighlightGrams(grams: Double): String {
    return if (grams >= 1000) {
        String.format("%.1f kg", grams / 1000.0)
    } else {
        "${grams.roundToInt()} g"
    }
}

@Composable
private fun streakDaysLabel(count: Int): String {
    return if (count == 1) {
        stringResource(R.string.nutrition_highlights_streak_one_day)
    } else {
        stringResource(R.string.nutrition_highlights_streak_days, count)
    }
}

@Composable
private fun HighlightsSectionCard(
    title: String,
    content: @Composable () -> Unit
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.45f)
        )
    ) {
        Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text(title, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
            content()
        }
    }
}

@Composable
private fun HighlightsStatPill(label: String, value: String) {
    Column(
        Modifier
            .padding(horizontal = 12.dp, vertical = 10.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp)
    ) {
        Text(label, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(value, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold)
    }
}

@Composable
private fun NavigableHighlightsRecordRow(
    title: String,
    detail: String,
    value: String?,
    onClick: () -> Unit
) {
    Row(
        Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(title, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold)
            Text(detail, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Row(
            horizontalArrangement = Arrangement.spacedBy(6.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            value?.let {
                Text(
                    it,
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.Bold,
                    color = MaterialTheme.colorScheme.primary
                )
            }
            Icon(
                Icons.AutoMirrored.Filled.KeyboardArrowRight,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f)
            )
        }
    }
}

@Composable
private fun NavigableHighlightsFoodRow(
    kind: String,
    name: String,
    count: Int,
    totalKcal: Double,
    onClick: () -> Unit
) {
    Row(
        Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(kind, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Text(name, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold)
            Text(
                stringResource(
                    R.string.nutrition_highlights_food_stats,
                    count,
                    totalKcal.roundToInt()
                ),
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
        Icon(
            Icons.AutoMirrored.Filled.KeyboardArrowRight,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f)
        )
    }
}

@Composable
private fun HighlightsRecordRow(
    title: String,
    detail: String,
    value: String?
) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(title, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold)
            Text(detail, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        value?.let {
            Text(
                it,
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.primary
            )
        }
    }
}

@Composable
private fun HighlightsFoodRow(
    kind: String,
    name: String,
    count: Int,
    totalKcal: Double
) {
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(kind, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(name, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold)
        Text(
            stringResource(
                R.string.nutrition_highlights_food_stats,
                count,
                totalKcal.roundToInt()
            ),
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}

private fun formatHighlightDate(iso: String): String {
    return runCatching {
        LocalDate.parse(iso).format(DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM))
    }.getOrElse { iso }
}
