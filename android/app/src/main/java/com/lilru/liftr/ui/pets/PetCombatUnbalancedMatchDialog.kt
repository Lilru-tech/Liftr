package com.lilru.liftr.ui.pets

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Checkbox
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.lilru.liftr.R
import com.lilru.liftr.data.PetCombatChallengeMode

@Composable
fun PetCombatUnbalancedMatchDialog(
    isUnderdog: Boolean,
    selectedMode: PetCombatChallengeMode,
    onModeChange: (PetCombatChallengeMode) -> Unit,
    hardcoreBonusLabel: String?,
    dontShowAgain: Boolean,
    onDontShowAgainChange: (Boolean) -> Unit,
    onDismiss: () -> Unit,
    onFight: () -> Unit
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = {
            Text(
                text = stringResource(R.string.pet_combat_unbalanced_title),
                fontWeight = FontWeight.SemiBold
            )
        },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(
                    text = if (isUnderdog) {
                        stringResource(R.string.pet_combat_unbalanced_underdog_body)
                    } else {
                        stringResource(R.string.pet_combat_unbalanced_bully_body)
                    },
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )

                if (isUnderdog) {
                    SingleChoiceSegmentedButtonRow(modifier = Modifier.fillMaxWidth()) {
                        PetCombatChallengeMode.entries.forEachIndexed { index, mode ->
                            SegmentedButton(
                                selected = selectedMode == mode,
                                onClick = { onModeChange(mode) },
                                shape = SegmentedButtonDefaults.itemShape(
                                    index = index,
                                    count = PetCombatChallengeMode.entries.size
                                )
                            ) {
                                Text(
                                    text = when (mode) {
                                        PetCombatChallengeMode.BALANCED -> stringResource(R.string.pet_combat_mode_balanced_short)
                                        PetCombatChallengeMode.HARDCORE -> stringResource(R.string.pet_combat_mode_hardcore_short)
                                    },
                                    style = MaterialTheme.typography.labelSmall
                                )
                            }
                        }
                    }

                    Text(
                        text = modeDescription(selectedMode, hardcoreBonusLabel),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }

                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Checkbox(
                        checked = dontShowAgain,
                        onCheckedChange = onDontShowAgainChange
                    )
                    Text(
                        text = stringResource(R.string.pet_combat_unbalanced_dont_show),
                        style = MaterialTheme.typography.bodyMedium
                    )
                }
            }
        },
        confirmButton = {
            TextButton(onClick = onFight) {
                Text(stringResource(R.string.pet_combat_unbalanced_fight), fontWeight = FontWeight.SemiBold)
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text(stringResource(R.string.pet_combat_unbalanced_cancel))
            }
        }
    )
}

private fun modeDescription(mode: PetCombatChallengeMode, hardcoreBonusLabel: String?): String =
    when (mode) {
        PetCombatChallengeMode.BALANCED ->
            "Balanced Mode caps the opponent at a +5% stat advantage. Normal handicap reward rules apply."
        PetCombatChallengeMode.HARDCORE ->
            hardcoreBonusLabel?.let {
                "Hardcore Mode keeps the opponent at full stats. Winning grants a dynamically scaled bonus ($it)."
            } ?: "Hardcore Mode keeps the opponent at full stats. Winning grants a dynamically scaled bonus based on the stat gap."
    }
