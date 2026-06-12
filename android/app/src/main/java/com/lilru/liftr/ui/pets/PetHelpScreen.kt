package com.lilru.liftr.ui.pets

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import coil.compose.AsyncImage
import com.lilru.liftr.R
import com.lilru.liftr.data.PetRarityConfigWire
import com.lilru.liftr.data.PetService
import com.lilru.liftr.data.PetTypeCatalogWire
import com.lilru.liftr.ui.components.LiftrBackTopBar
import io.github.jan.supabase.SupabaseClient
import java.text.NumberFormat
import kotlin.math.roundToInt

@Composable
fun PetHelpSheetContent(
    supabase: SupabaseClient,
    onClose: () -> Unit,
    modifier: Modifier = Modifier
) {
    val vm: PetHelpViewModel = viewModel(factory = PetHelpViewModelFactory(supabase))
    val ui by vm.uiState.collectAsStateWithLifecycle()

    LaunchedEffect(Unit) {
        vm.loadIfNeeded()
    }

    Column(
        modifier = modifier
            .fillMaxWidth()
            .padding(bottom = 24.dp)
    ) {
        LiftrBackTopBar(onBack = onClose)

        when {
            ui.loading -> {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(240.dp),
                    contentAlignment = Alignment.Center
                ) {
                    CircularProgressIndicator()
                }
            }
            ui.error != null -> {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 24.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    Text(
                        text = ui.error.orEmpty(),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    Button(onClick = { vm.retry() }) {
                        Text(stringResource(R.string.pet_help_retry))
                    }
                }
            }
            else -> {
                PetHelpLoadedContent(
                    rarities = ui.rarities,
                    species = ui.species
                )
            }
        }
    }
}

@Composable
private fun PetHelpLoadedContent(
    rarities: List<PetRarityConfigWire>,
    species: List<PetTypeCatalogWire>,
    modifier: Modifier = Modifier
) {
    val scroll = rememberScrollState()
    val totalWeight = rarities.sumOf { it.dropWeight }.coerceAtLeast(1)

    Column(
        modifier = modifier
            .fillMaxWidth()
            .verticalScroll(scroll)
            .padding(horizontal = 16.dp)
    ) {
        Text(
            text = stringResource(R.string.pet_help_title),
            style = MaterialTheme.typography.titleLarge
        )
        Spacer(Modifier.height(16.dp))

        Text(
            text = stringResource(R.string.pet_help_rarities_headline),
            style = MaterialTheme.typography.titleMedium
        )
        Spacer(Modifier.height(6.dp))
        Text(
            text = stringResource(R.string.pet_help_rarities_intro),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Spacer(Modifier.height(12.dp))

        rarities.forEach { row ->
            PetHelpRarityRow(row = row, totalWeight = totalWeight)
            Spacer(Modifier.height(8.dp))
        }

        Spacer(Modifier.height(16.dp))
        Text(
            text = stringResource(R.string.pet_help_species_headline),
            style = MaterialTheme.typography.titleMedium
        )
        Spacer(Modifier.height(6.dp))
        Text(
            text = stringResource(R.string.pet_help_species_intro),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Spacer(Modifier.height(12.dp))

        species.chunked(2).forEach { rowSpecies ->
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                rowSpecies.forEach { row ->
                    PetHelpSpeciesCard(
                        row = row,
                        modifier = Modifier.weight(1f)
                    )
                }
                if (rowSpecies.size == 1) {
                    Spacer(modifier = Modifier.weight(1f))
                }
            }
            Spacer(Modifier.height(12.dp))
        }
    }
}

@Composable
private fun PetHelpRarityRow(
    row: PetRarityConfigWire,
    totalWeight: Int
) {
    val dropPercent = row.dropWeight.toDouble() / totalWeight.toDouble() * 100.0
    val upgradeCost = PetRarityUpgrade.upgradeCost(row.rarity)
    val nextTier = PetRarityUpgrade.nextTier(row.rarity)

    Surface(
        modifier = Modifier.fillMaxWidth(),
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
                    R.string.pet_help_rarity_drop,
                    formatDropPercent(dropPercent)
                ),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Text(
                text = stringResource(
                    R.string.pet_help_rarity_stat_multiplier,
                    PetRarityUpgrade.formattedMultiplier(row.statMultiplier)
                ),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Text(
                text = stringResource(
                    R.string.pet_help_rarity_coin_multiplier,
                    PetRarityUpgrade.formattedMultiplier(row.coinMultiplier)
                ),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Text(
                text = if (upgradeCost != null && nextTier != null) {
                    stringResource(
                        R.string.pet_help_rarity_upgrade_cost,
                        petRarityLabel(row.rarity),
                        petRarityLabel(nextTier),
                        formatCoins(upgradeCost)
                    )
                } else {
                    stringResource(R.string.pet_help_rarity_max_tier)
                },
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

@Composable
private fun PetHelpSpeciesCard(
    row: PetTypeCatalogWire,
    modifier: Modifier = Modifier
) {
    Surface(
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(12.dp),
        color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.35f)
    ) {
        Column(
            modifier = Modifier.padding(10.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            AsyncImage(
                model = PetService.catalogEggImageUrl(row),
                contentDescription = null,
                modifier = Modifier
                    .fillMaxWidth()
                    .height(72.dp)
            )
            Text(
                text = row.displayName.ifBlank { row.name.replace('_', ' ').replaceFirstChar { it.uppercase() } },
                style = MaterialTheme.typography.labelLarge,
                fontWeight = FontWeight.SemiBold,
                maxLines = 2
            )
            if (row.description.isNotBlank()) {
                Text(
                    text = row.description,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 4
                )
            }
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
