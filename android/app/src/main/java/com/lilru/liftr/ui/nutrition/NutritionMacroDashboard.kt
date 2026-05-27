package com.lilru.liftr.ui.nutrition

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.size
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.lilru.liftr.R
import com.lilru.liftr.data.BackendContracts
import kotlin.math.min
import kotlin.math.roundToInt

@Composable
fun NutritionMacroDashboard(
    recommendation: NutritionRecommendationUi,
    modifier: Modifier = Modifier
) {
    Row(
        modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceEvenly
    ) {
        MacroRing(
            label = stringResource(R.string.nutrition_macro_cal),
            value = recommendation.consumed,
            target = recommendation.baseCaloriesTarget.coerceAtLeast(1.0),
            unit = "kcal",
            color = MaterialTheme.colorScheme.primary
        )
        MacroRing(
            label = stringResource(R.string.nutrition_macro_protein),
            value = recommendation.proteinG,
            target = BackendContracts.NutritionDisplayTargets.PROTEIN_G,
            unit = "g",
            color = MaterialTheme.colorScheme.tertiary
        )
        MacroRing(
            label = stringResource(R.string.nutrition_macro_carbs),
            value = recommendation.carbsG,
            target = BackendContracts.NutritionDisplayTargets.CARBS_G,
            unit = "g",
            color = MaterialTheme.colorScheme.secondary
        )
        MacroRing(
            label = stringResource(R.string.nutrition_macro_fat),
            value = recommendation.fatG,
            target = BackendContracts.NutritionDisplayTargets.FAT_G,
            unit = "g",
            color = MaterialTheme.colorScheme.error.copy(alpha = 0.85f)
        )
    }
}

@Composable
private fun MacroRing(
    label: String,
    value: Double,
    target: Double,
    unit: String,
    color: androidx.compose.ui.graphics.Color
) {
    val progress = if (target > 0) min(value / target, 1.0).toFloat() else 0f
    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
        BoxWithRing(progress, value.roundToInt(), unit, color)
        Text(label, style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun BoxWithRing(
    progress: Float,
    valueInt: Int,
    unit: String,
    color: androidx.compose.ui.graphics.Color
) {
    val trackColor = color.copy(alpha = 0.2f)
    Box(Modifier.size(56.dp), contentAlignment = Alignment.Center) {
        Canvas(Modifier.size(56.dp)) {
            val stroke = 6.dp.toPx()
            val arcSize = Size(size.width - stroke, size.height - stroke)
            val topLeft = Offset(stroke / 2f, stroke / 2f)
            drawArc(color = trackColor, startAngle = 0f, sweepAngle = 360f, useCenter = false, topLeft = topLeft, size = arcSize, style = Stroke(stroke, cap = StrokeCap.Round))
            drawArc(color = color, startAngle = -90f, sweepAngle = 360f * progress, useCenter = false, topLeft = topLeft, size = arcSize, style = Stroke(stroke, cap = StrokeCap.Round))
        }
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text("$valueInt", style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.Bold)
            Text(unit, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
fun NutritionMicroNutrientsSection(
    recommendation: NutritionRecommendationUi,
    expanded: Boolean,
    onToggle: () -> Unit,
    modifier: Modifier = Modifier
) {
    Column(modifier.fillMaxWidth()) {
        androidx.compose.material3.TextButton(onClick = onToggle, modifier = Modifier.fillMaxWidth()) {
            Text(
                if (expanded) stringResource(R.string.nutrition_micro_hide) else stringResource(R.string.nutrition_micro_show),
                style = MaterialTheme.typography.labelLarge,
                fontWeight = FontWeight.SemiBold
            )
        }
        if (expanded) {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                MicroBar(stringResource(R.string.nutrition_facts_saturated_fat), recommendation.saturatedFatG, BackendContracts.NutritionDisplayTargets.SATURATED_FAT_G, "g")
                MicroBar(stringResource(R.string.nutrition_facts_sugars), recommendation.sugarsG, BackendContracts.NutritionDisplayTargets.SUGARS_G, "g")
                MicroBar(stringResource(R.string.nutrition_facts_fiber), recommendation.fiberG, BackendContracts.NutritionDisplayTargets.FIBER_G, "g")
                MicroBar(stringResource(R.string.nutrition_facts_sodium), recommendation.sodiumMg, BackendContracts.NutritionDisplayTargets.SODIUM_MG, "mg")
            }
        }
    }
}

@Composable
private fun MicroBar(label: String, value: Double, target: Double, unit: String) {
    val progress = if (target > 0) (min(value / target, 1.0)).toFloat() else 0f
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text(label, style = MaterialTheme.typography.labelSmall)
            Text(String.format("%.1f / %.0f %s", value, target, unit), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        androidx.compose.material3.LinearProgressIndicator(progress = { progress }, modifier = Modifier.fillMaxWidth())
    }
}
