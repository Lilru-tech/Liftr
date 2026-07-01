package com.lilru.liftr.ui.nutrition

import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Lightbulb
import androidx.compose.material.icons.filled.ThumbUp
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Divider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.lilru.liftr.R
import kotlin.math.roundToInt

@Composable
fun NutritionSmartInsightsInlineContent(
    ui: NutritionUiState,
    modifier: Modifier = Modifier
) {
    Column(modifier = modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        when {
            ui.smartInsightsLoading -> LoadingInsightsContent()
            ui.smartInsightsError != null -> {
                Text(
                    ui.smartInsightsError!!,
                    color = MaterialTheme.colorScheme.error,
                    style = MaterialTheme.typography.bodyMedium,
                    modifier = Modifier.insightsCard()
                )
            }
            ui.smartInsights != null -> InsightsLoadedContent(ui.smartInsights!!)
        }
    }
}

@Composable
private fun Modifier.insightsCard(): Modifier = this
    .clip(RoundedCornerShape(16.dp))
    .background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.45f))
    .padding(14.dp)

@Composable
internal fun LoadingInsightsContent() {
    val transition = rememberInfiniteTransition(label = "shimmer")
    val alpha by transition.animateFloat(
        initialValue = 0.07f,
        targetValue = 0.16f,
        animationSpec = infiniteRepeatable(tween(900), RepeatMode.Reverse),
        label = "alpha"
    )
    val shimmerColor = MaterialTheme.colorScheme.onSurface.copy(alpha = alpha)
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        ShimmerBlock(shimmerColor, 120.dp)
        ShimmerBlock(shimmerColor, 72.dp)
        ShimmerBlock(shimmerColor, 56.dp)
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.Center) {
            CircularProgressIndicator()
        }
    }
}

@Composable
private fun ShimmerBlock(color: Color, height: androidx.compose.ui.unit.Dp) {
    Box(
        Modifier
            .fillMaxWidth()
            .height(height)
            .clip(RoundedCornerShape(12.dp))
            .background(color)
    )
}

@Composable
internal fun InsightsLoadedContent(insights: SmartNutritionRecommendationUi) {
    val remaining = insights.avgDailyRemainingBudget

    Column(
        Modifier
            .fillMaxWidth()
            .insightsCard(),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Text(
            stringResource(R.string.nutrition_insights_daily_averages),
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.SemiBold
        )
        Text(
            stringResource(R.string.nutrition_insights_metabolic_hint),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            MetricColumn(
                title = stringResource(R.string.nutrition_target_base),
                value = insights.baseCaloriesTarget.roundToInt(),
                tint = Color(0xFF42A5F5),
                modifier = Modifier.weight(1f)
            )
            MetricColumn(
                title = stringResource(R.string.nutrition_activity_burned),
                value = insights.avgDailyBurnedKcal.roundToInt(),
                tint = Color(0xFF4DB6AC),
                modifier = Modifier.weight(1f)
            )
            MetricColumn(
                title = stringResource(R.string.nutrition_consumed),
                value = insights.avgDailyConsumedKcal.roundToInt(),
                tint = Color(0xFFFF9800),
                modifier = Modifier.weight(1f)
            )
        }
        Divider(color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.12f))
        NutritionCalorieBudgetStatusRow(
            remainingKcal = remaining,
            titleWhenUnderRes = R.string.nutrition_insights_energy_budget_left,
            titleWhenOverRes = R.string.nutrition_insights_budget_over_title,
            hintWhenUnderRes = R.string.nutrition_insights_budget_remaining_hint,
            hintWhenOverRes = R.string.nutrition_insights_budget_over_hint
        )
        Text(
            stringResource(
                R.string.nutrition_insights_total_energy_out,
                insights.avgDailyEnergyOut.roundToInt()
            ),
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }

    val training = insights.trainingDayAvg
    val rest = insights.restDayAvg
    if ((training?.days ?: 0) > 0 || (rest?.days ?: 0) > 0) {
        TrainingRestCard(training = training, rest = rest)
    }

    if (insights.insights.isNotEmpty()) {
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(
                stringResource(R.string.nutrition_insights_personalized),
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold
            )
            insights.insights.forEach { card ->
                InsightCard(card)
            }
        }
    }

    if (insights.recommendationText.isNotBlank()) {
        Column(
            Modifier
                .fillMaxWidth()
                .insightsCard(),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Text(
                stringResource(R.string.nutrition_insights_summary),
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold
            )
            Text(insights.recommendationText, style = MaterialTheme.typography.bodyMedium)
        }
    }

    if (insights.alerts.isNotEmpty()) {
        Text(
            stringResource(R.string.nutrition_insights_watch),
            style = MaterialTheme.typography.titleSmall,
            fontWeight = FontWeight.SemiBold,
            color = Color(0xFFFF9800)
        )
        insights.alerts.forEach { alert ->
            Text(
                alert,
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(12.dp))
                    .background(Color(0xFFFF9800).copy(alpha = 0.12f))
                    .padding(12.dp),
                style = MaterialTheme.typography.bodyMedium
            )
        }
    }
}

@Composable
private fun TrainingRestCard(
    training: NutritionDayMacroAvgUi?,
    rest: NutritionDayMacroAvgUi?
) {
    Column(
        Modifier
            .fillMaxWidth()
            .insightsCard(),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        Text(
            stringResource(R.string.nutrition_insights_training_vs_rest),
            style = MaterialTheme.typography.titleSmall,
            fontWeight = FontWeight.SemiBold
        )
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            DayTypeColumn(
                title = stringResource(R.string.nutrition_insights_training_days),
                avg = training,
                modifier = Modifier.weight(1f)
            )
            DayTypeColumn(
                title = stringResource(R.string.nutrition_insights_rest_days),
                avg = rest,
                modifier = Modifier.weight(1f)
            )
        }
    }
}

@Composable
private fun DayTypeColumn(
    title: String,
    avg: NutritionDayMacroAvgUi?,
    modifier: Modifier = Modifier
) {
    Column(
        modifier
            .clip(RoundedCornerShape(10.dp))
            .background(MaterialTheme.colorScheme.onSurface.copy(alpha = 0.06f))
            .padding(8.dp)
    ) {
        Text(title, style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.SemiBold)
        Text(
            stringResource(R.string.nutrition_kcal_format, (avg?.kcal ?: 0.0).roundToInt()),
            style = MaterialTheme.typography.labelMedium,
            fontWeight = FontWeight.Bold
        )
        Text(
            stringResource(
                R.string.nutrition_insights_macro_short,
                (avg?.proteinG ?: 0.0).roundToInt(),
                (avg?.carbsG ?: 0.0).roundToInt()
            ),
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}

@Composable
private fun InsightCard(card: SmartNutritionInsightUi) {
    val tint = insightColor(card.sentiment)
    Column(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .background(tint.copy(alpha = 0.10f))
            .padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(insightIcon(card.sentiment), contentDescription = null, tint = tint)
            Text(card.title, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold, color = tint)
        }
        Text(card.body, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

private fun insightIcon(sentiment: String): ImageVector = when (sentiment) {
    "positive" -> Icons.Filled.ThumbUp
    "warning" -> Icons.Filled.Warning
    else -> Icons.Filled.Lightbulb
}

private fun insightColor(sentiment: String): Color = when (sentiment) {
    "positive" -> Color(0xFF34C759)
    "warning" -> Color(0xFFFF9800)
    else -> Color(0xFF007AFF)
}

@Composable
private fun MetricColumn(
    title: String,
    value: Int,
    tint: Color,
    modifier: Modifier = Modifier
) {
    Column(
        modifier
            .clip(RoundedCornerShape(10.dp))
            .background(tint.copy(alpha = 0.15f))
            .padding(8.dp)
    ) {
        Text(title, style = MaterialTheme.typography.labelSmall, maxLines = 1)
        Text(
            stringResource(R.string.nutrition_kcal_format, value),
            style = MaterialTheme.typography.labelLarge,
            fontWeight = FontWeight.Bold
        )
    }
}

@Composable
fun NutritionDailyInsightCard(
    insight: DailyNutritionInsightsUi,
    modifier: Modifier = Modifier
) {
    val top = insight.insights.firstOrNull()
    if (top != null) {
        val tint = insightColor(top.sentiment)
        Column(
            modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(12.dp))
                .background(MaterialTheme.colorScheme.onSurface.copy(alpha = 0.06f))
                .padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(insightIcon(top.sentiment), contentDescription = null, tint = tint)
                Text(top.title, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold, color = tint)
            }
            Text(top.body, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    } else if (insight.recommendationText.isNotBlank()) {
        Text(
            insight.recommendationText,
            modifier = modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(12.dp))
                .background(MaterialTheme.colorScheme.onSurface.copy(alpha = 0.06f))
                .padding(12.dp),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}
