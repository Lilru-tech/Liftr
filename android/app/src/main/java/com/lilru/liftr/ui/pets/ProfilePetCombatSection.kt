package com.lilru.liftr.ui.pets

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import coil.compose.SubcomposeAsyncImage
import com.lilru.liftr.data.PetCombatPetSummaryWire
import com.lilru.liftr.data.PetCombatStatsSummaryWire
import com.lilru.liftr.data.PetService

@Composable
fun PetCombatSummaryImage(
    pet: PetCombatPetSummaryWire,
    modifier: Modifier = Modifier,
    height: Dp = 120.dp,
    contentPadding: Dp = 0.dp
) {
    val imageUrl = PetService.resolvedCombatPetImageUrl(pet)

    SubcomposeAsyncImage(
        model = imageUrl,
        contentDescription = null,
        modifier = modifier
            .height(height)
            .padding(contentPadding),
        contentScale = ContentScale.Fit,
        loading = {
            CircularProgressIndicator(modifier = Modifier.height(height))
        }
    )
}

@Composable
fun PetCombatComparisonStats(
    attackerName: String,
    defenderName: String,
    attackerLevel: Int,
    defenderLevel: Int,
    attackerStats: PetCombatStatsSummaryWire,
    defenderStats: PetCombatStatsSummaryWire,
    modifier: Modifier = Modifier
) {
    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(Modifier.fillMaxWidth()) {
            Text(attackerName, modifier = Modifier.weight(1f), style = MaterialTheme.typography.labelSmall, maxLines = 1)
            Text("vs", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Text(defenderName, modifier = Modifier.weight(1f), style = MaterialTheme.typography.labelSmall, maxLines = 1)
        }
        statRow("Level", attackerLevel, defenderLevel)
        statRow("Health", attackerStats.health, defenderStats.health)
        statRow("Strength", attackerStats.strength, defenderStats.strength)
        statRow("Defense", attackerStats.defense, defenderStats.defense)
        statRow("Speed", attackerStats.speed, defenderStats.speed)
        statRow("Intelligence", attackerStats.intelligence, defenderStats.intelligence)
        statRow("Agility", attackerStats.agility, defenderStats.agility)
        statRow("Stamina", attackerStats.stamina, defenderStats.stamina)
        statRow("Crit", attackerStats.criticalRate, defenderStats.criticalRate)
        statRow("Resistance", attackerStats.resistance, defenderStats.resistance)
        statRow("Explore", attackerStats.exploration, defenderStats.exploration)
        statRow("Happiness", attackerStats.happiness, defenderStats.happiness)
    }
}

@Composable
private fun statRow(label: String, left: Int, right: Int) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Text("$left", modifier = Modifier.weight(1f), style = MaterialTheme.typography.labelSmall)
        Text(label, modifier = Modifier.weight(1f), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text("$right", modifier = Modifier.weight(1f), style = MaterialTheme.typography.labelSmall)
    }
}
