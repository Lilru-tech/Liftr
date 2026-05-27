package com.lilru.liftr.ui.nutrition

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.lilru.liftr.R
import kotlin.math.abs
import kotlin.math.roundToInt

private val BudgetUnderColor = Color(0xFFFF9800)
private val BudgetOverColor = Color(0xFFE53935)

@Composable
fun NutritionCalorieBudgetStatusRow(
    remainingKcal: Double,
    modifier: Modifier = Modifier,
    titleWhenUnderRes: Int = R.string.nutrition_budget_remaining_title,
    titleWhenOverRes: Int = R.string.nutrition_budget_over_title,
    hintWhenUnderRes: Int = R.string.nutrition_budget_remaining_hint,
    hintWhenOverRes: Int = R.string.nutrition_budget_over_hint
) {
    val isOver = remainingKcal < 0
    val magnitude = abs(remainingKcal).roundToInt()
    val accent = if (isOver) BudgetOverColor else BudgetUnderColor
    val title = stringResource(if (isOver) titleWhenOverRes else titleWhenUnderRes)
    val hint = stringResource(if (isOver) hintWhenOverRes else hintWhenUnderRes)
    val valueText = stringResource(
        if (isOver) R.string.nutrition_kcal_over_format else R.string.nutrition_kcal_left_format,
        magnitude
    )
    val a11y = if (isOver) {
        stringResource(R.string.nutrition_budget_over_a11y, magnitude)
    } else {
        stringResource(R.string.nutrition_budget_remaining_a11y, magnitude)
    }

    Row(
        modifier = modifier
            .fillMaxWidth()
            .background(accent.copy(alpha = 0.12f), RoundedCornerShape(12.dp))
            .padding(horizontal = 12.dp, vertical = 10.dp)
            .semantics { contentDescription = a11y },
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Icon(
            imageVector = if (isOver) Icons.Filled.KeyboardArrowUp else Icons.Filled.KeyboardArrowDown,
            contentDescription = null,
            tint = accent,
            modifier = Modifier.size(28.dp)
        )
        Column(modifier = Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.SemiBold)
            Text(hint, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Text(
            valueText,
            style = MaterialTheme.typography.titleSmall,
            fontWeight = FontWeight.Bold,
            color = accent
        )
    }
}
