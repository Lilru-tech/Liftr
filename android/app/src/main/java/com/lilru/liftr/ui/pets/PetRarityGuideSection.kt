package com.lilru.liftr.ui.pets

import androidx.compose.animation.animateContentSize
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.lilru.liftr.R
import com.lilru.liftr.data.PetRarityConfigWire
import java.text.NumberFormat
import kotlin.math.roundToInt

@Composable
fun PetRarityGuideSection(
    rarities: List<PetRarityConfigWire>,
    modifier: Modifier = Modifier
) {
    val totalWeight = rarities.sumOf { it.dropWeight }.coerceAtLeast(1)
    var isExpanded by remember { mutableStateOf(false) }

    Surface(
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(12.dp),
        color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.35f)
    ) {
        Column(
            modifier = Modifier
                .animateContentSize()
                .padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable { isExpanded = !isExpanded },
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = stringResource(R.string.pet_dex_rarities_headline),
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold
                )
                Icon(
                    imageVector = if (isExpanded) Icons.Filled.ExpandLess else Icons.Filled.ExpandMore,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }

            if (isExpanded) {
                Text(
                    text = stringResource(R.string.pet_dex_rarities_intro),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                rarities.forEach { row ->
                    PetRarityGuideRow(row = row, totalWeight = totalWeight)
                }
            }
        }
    }
}

@Composable
fun PetRarityGuideRow(
    row: PetRarityConfigWire,
    totalWeight: Int,
    modifier: Modifier = Modifier
) {
    val dropPercent = row.dropWeight.toDouble() / totalWeight.toDouble() * 100.0
    val upgradeCost = PetRarityUpgrade.upgradeCost(row.rarity)
    val nextTier = PetRarityUpgrade.nextTier(row.rarity)

    Surface(
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(12.dp),
        color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.35f)
    ) {
        Column(
            modifier = Modifier.padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            PetRarityBadge(row.rarity)
            Text(
                text = stringResource(
                    R.string.pet_dex_rarity_drop,
                    formatDropPercent(dropPercent)
                ),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Text(
                text = stringResource(
                    R.string.pet_dex_rarity_stat_multiplier,
                    PetRarityUpgrade.formattedMultiplier(row.statMultiplier)
                ),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Text(
                text = stringResource(
                    R.string.pet_dex_rarity_coin_multiplier,
                    PetRarityUpgrade.formattedMultiplier(row.coinMultiplier)
                ),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Text(
                text = if (upgradeCost != null && nextTier != null) {
                    stringResource(
                        R.string.pet_dex_rarity_upgrade_cost,
                        petRarityLabel(row.rarity),
                        petRarityLabel(nextTier),
                        formatCoins(upgradeCost)
                    )
                } else {
                    stringResource(R.string.pet_dex_rarity_max_tier)
                },
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

private fun formatDropPercent(value: Double): String {
    val rounded = (value * 10.0).roundToInt() / 10.0
    return if (rounded == rounded.toInt().toDouble()) {
        "${rounded.toInt()}%"
    } else {
        String.format("%.1f%%", rounded)
    }
}

private fun formatCoins(value: Int): String =
    NumberFormat.getIntegerInstance().format(value)
