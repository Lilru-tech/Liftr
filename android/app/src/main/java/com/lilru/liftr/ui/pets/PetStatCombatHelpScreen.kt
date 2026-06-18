package com.lilru.liftr.ui.pets

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.lilru.liftr.R
import com.lilru.liftr.ui.components.LiftrBackTopBar

private data class PetStatCombatHelpEntry(val nameRes: Int, val effectRes: Int)

private val petStatCombatGuideEntries = listOf(
    PetStatCombatHelpEntry(R.string.pet_stat_combat_health, R.string.pet_stat_combat_health_effect),
    PetStatCombatHelpEntry(R.string.pet_stat_combat_strength, R.string.pet_stat_combat_strength_effect),
    PetStatCombatHelpEntry(R.string.pet_stat_combat_defense, R.string.pet_stat_combat_defense_effect),
    PetStatCombatHelpEntry(R.string.pet_stat_combat_resistance, R.string.pet_stat_combat_resistance_effect),
    PetStatCombatHelpEntry(R.string.pet_stat_combat_speed, R.string.pet_stat_combat_speed_effect),
    PetStatCombatHelpEntry(R.string.pet_stat_combat_agility, R.string.pet_stat_combat_agility_effect),
    PetStatCombatHelpEntry(R.string.pet_stat_combat_intelligence, R.string.pet_stat_combat_intelligence_effect),
    PetStatCombatHelpEntry(R.string.pet_stat_combat_crit, R.string.pet_stat_combat_crit_effect),
    PetStatCombatHelpEntry(R.string.pet_stat_combat_stamina, R.string.pet_stat_combat_stamina_effect),
    PetStatCombatHelpEntry(R.string.pet_stat_combat_exploration, R.string.pet_stat_combat_exploration_effect),
    PetStatCombatHelpEntry(R.string.pet_stat_combat_happiness, R.string.pet_stat_combat_happiness_effect)
)

@Composable
fun PetStatCombatHelpSheetContent(
    onClose: () -> Unit,
    modifier: Modifier = Modifier
) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            .padding(bottom = 24.dp)
    ) {
        LiftrBackTopBar(onBack = onClose)

        Column(
            modifier = Modifier
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Text(
                text = stringResource(R.string.pet_stat_combat_title),
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.SemiBold
            )
            Text(
                text = stringResource(R.string.pet_stat_combat_intro),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Surface(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(12.dp),
                color = MaterialTheme.colorScheme.surface.copy(alpha = 0.35f)
            ) {
                Column(
                    modifier = Modifier.padding(12.dp),
                    verticalArrangement = Arrangement.spacedBy(4.dp)
                ) {
                    Text(
                        text = stringResource(R.string.pet_stat_combat_handicap_title),
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.SemiBold
                    )
                    Text(
                        text = stringResource(R.string.pet_stat_combat_handicap_description),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
            petStatCombatRulesEntry(
                titleRes = R.string.pet_stat_combat_handicap_battles_title,
                descriptionRes = R.string.pet_stat_combat_handicap_battles_description
            )
            petStatCombatRulesEntry(
                titleRes = R.string.pet_stat_combat_hardcore_challenge_title,
                descriptionRes = R.string.pet_stat_combat_hardcore_challenge_description
            )
            petStatCombatGuideEntries.forEach { entry ->
                Surface(
                    modifier = Modifier.fillMaxWidth(),
                    shape = RoundedCornerShape(12.dp),
                    color = MaterialTheme.colorScheme.surface.copy(alpha = 0.35f)
                ) {
                    Column(
                        modifier = Modifier.padding(12.dp),
                        verticalArrangement = Arrangement.spacedBy(4.dp)
                    ) {
                        Text(
                            text = stringResource(entry.nameRes),
                            style = MaterialTheme.typography.titleSmall,
                            fontWeight = FontWeight.SemiBold
                        )
                        Text(
                            text = stringResource(entry.effectRes),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }
            }
            Text(
                text = stringResource(R.string.pet_stat_combat_footer),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(top = 4.dp, bottom = 8.dp)
            )
        }
    }
}

@Composable
private fun petStatCombatRulesEntry(titleRes: Int, descriptionRes: Int) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(12.dp),
        color = MaterialTheme.colorScheme.surface.copy(alpha = 0.35f)
    ) {
        Column(
            modifier = Modifier.padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            Text(
                text = stringResource(titleRes),
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold
            )
            Text(
                text = stringResource(descriptionRes),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}
