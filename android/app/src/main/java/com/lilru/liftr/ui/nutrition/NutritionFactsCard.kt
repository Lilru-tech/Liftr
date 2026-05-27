package com.lilru.liftr.ui.nutrition

import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.lilru.liftr.R
import kotlin.math.roundToInt

@Composable
fun NutritionFactsCard(
    title: String,
    profile: NutritionProfilePer100g,
    modifier: Modifier = Modifier
) {
    Column(
        modifier
            .fillMaxWidth()
            .border(1.dp, MaterialTheme.colorScheme.outline.copy(alpha = 0.4f), RoundedCornerShape(12.dp))
            .padding(14.dp)
    ) {
        if (title.isNotBlank()) {
            Text(title, style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.Bold)
        }
        Text(stringResource(R.string.nutrition_facts_title), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
        Text(stringResource(R.string.nutrition_facts_serving), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Row(Modifier.fillMaxWidth().padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(stringResource(R.string.nutrition_facts_calories), fontWeight = FontWeight.SemiBold)
            Text("${profile.calories.roundToInt()}", Modifier.weight(1f), fontWeight = FontWeight.Bold, style = MaterialTheme.typography.titleLarge)
        }
        HorizontalDivider(Modifier.padding(vertical = 4.dp), thickness = 4.dp)
        factRow(stringResource(R.string.nutrition_facts_protein), profile.protein, "g")
        factRow(stringResource(R.string.nutrition_facts_carbs), profile.carbs, "g")
        factRow(stringResource(R.string.nutrition_facts_fat), profile.fat, "g")
        HorizontalDivider(Modifier.padding(vertical = 6.dp))
        factRow(stringResource(R.string.nutrition_facts_saturated_fat), profile.saturatedFat, "g", indent = true)
        factRow(stringResource(R.string.nutrition_facts_sugars), profile.sugars, "g", indent = true)
        factRow(stringResource(R.string.nutrition_facts_fiber), profile.fiber, "g", indent = true)
        factRow(stringResource(R.string.nutrition_facts_sodium), profile.sodiumMg, "mg", indent = true)
    }
}

@Composable
private fun factRow(label: String, value: Double, unit: String, indent: Boolean = false) {
    Row(
        Modifier
            .fillMaxWidth()
            .padding(vertical = 3.dp, horizontal = if (indent) 8.dp else 0.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(label, style = MaterialTheme.typography.labelSmall, fontWeight = if (indent) FontWeight.Normal else FontWeight.SemiBold)
        Text(String.format("%.1f %s", value, unit), Modifier.weight(1f), style = MaterialTheme.typography.labelSmall)
    }
}
