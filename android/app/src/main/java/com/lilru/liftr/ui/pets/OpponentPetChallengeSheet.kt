package com.lilru.liftr.ui.pets

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.lilru.liftr.data.PetCombatChallengeMode
import com.lilru.liftr.data.PetCombatHeadToHeadSummaryWire
import com.lilru.liftr.data.PetCombatPetSummaryWire
import com.lilru.liftr.data.PetCombatPreviewWire
import com.lilru.liftr.prefs.LiftrPreferences
import com.lilru.liftr.ui.theme.liftrAppBackgroundGradient

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun OpponentPetChallengeSheet(
    preview: PetCombatPreviewWire,
    defenderPet: PetCombatPetSummaryWire,
    headToHead: PetCombatHeadToHeadSummaryWire?,
    opponentUsername: String?,
    backgroundThemeId: String,
    onDismiss: () -> Unit,
    onChallenge: (Boolean) -> Unit,
    modifier: Modifier = Modifier
) {
    val context = LocalContext.current
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    var showUnbalancedDialog by remember { mutableStateOf(false) }
    var dontShowAgain by remember { mutableStateOf(false) }
    var skipWarningState by remember { mutableStateOf(LiftrPreferences.skipPetCombatUnbalancedWarning(context)) }
    var selectedMode by remember {
        mutableStateOf(PetCombatChallengeMode.fromRaw(LiftrPreferences.petCombatChallengeMode(context)))
    }

    fun resolvedSavedMode(): PetCombatChallengeMode =
        if (preview.isAttackerUnderdog()) {
            PetCombatChallengeMode.fromRaw(LiftrPreferences.petCombatChallengeMode(context))
        } else {
            PetCombatChallengeMode.BALANCED
        }

    fun proceedToChallenge(disableNerfChoice: Boolean) {
        onDismiss()
        onChallenge(disableNerfChoice)
    }

    fun handleChallengeTap() {
        if (!preview.isStatUnbalanced()) {
            proceedToChallenge(false)
            return
        }
        if (skipWarningState && !preview.isAttackerUnderdog()) {
            proceedToChallenge(false)
            return
        }
        selectedMode = resolvedSavedMode()
        dontShowAgain = false
        showUnbalancedDialog = true
    }

    fun confirmChallenge() {
        if (dontShowAgain && !preview.isAttackerUnderdog()) {
            LiftrPreferences.setSkipPetCombatUnbalancedWarning(context, true)
            skipWarningState = true
        }
        LiftrPreferences.setPetCombatChallengeMode(context, selectedMode.rawValue)
        val disableNerf = preview.isAttackerUnderdog() && selectedMode.disableNerfChoice
        showUnbalancedDialog = false
        proceedToChallenge(disableNerf)
    }

    Box(modifier = modifier) {
        ModalBottomSheet(
            onDismissRequest = onDismiss,
            sheetState = sheetState,
            containerColor = Color.Transparent,
            dragHandle = null
        ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .liftrAppBackgroundGradient(backgroundThemeId)
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                TextButton(onClick = onDismiss) { Text("Close") }
            }

            Column(
                modifier = Modifier.fillMaxWidth(),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                PetCombatSummaryImage(pet = defenderPet, height = 120.dp)
                Text(defenderPet.displayName(), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                PetRarityBadge(defenderPet.rarity)
            }

            if (headToHead != null && headToHead.totalBattles > 0) {
                PetCombatHeadToHeadSummaryView(
                    summary = headToHead,
                    opponentUsername = opponentUsername
                )
            }

            val attacker = preview.attacker
            val defender = preview.defender
            if (attacker?.pet != null && defender?.pet != null && attacker.stats != null && defender.stats != null) {
                PetCombatComparisonStats(
                    attackerName = attacker.pet.displayName(),
                    defenderName = defender.pet.displayName(),
                    attackerLevel = attacker.pet.currentLevel,
                    defenderLevel = defender.pet.currentLevel,
                    attackerStats = attacker.stats,
                    defenderStats = defender.stats
                )
            }

            preview.energy?.let { energy ->
                Surface(
                    modifier = Modifier.fillMaxWidth(),
                    shape = RoundedCornerShape(12.dp),
                    color = Color.White.copy(alpha = 0.06f)
                ) {
                    Row(
                        modifier = Modifier.padding(12.dp),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        PetEnergyBadge(energy = energy, label = "Your energy")
                        Text(
                            "Challenging costs 1 energy",
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }
            }

            if (preview.canChallenge) {
                Button(
                    onClick = { handleChallengeTap() },
                    modifier = Modifier.fillMaxWidth(),
                    colors = ButtonDefaults.buttonColors(containerColor = Color(0xFFFF9800))
                ) {
                    Text("Challenge Pet", fontWeight = FontWeight.SemiBold)
                }
            } else {
                preview.blockReasonText()?.let {
                    Text(
                        it,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.fillMaxWidth()
                    )
                }
            }

            Spacer(modifier = Modifier.padding(bottom = 24.dp))
        }
        }

        if (showUnbalancedDialog) {
            PetCombatUnbalancedMatchDialog(
                isUnderdog = preview.isAttackerUnderdog(),
                selectedMode = selectedMode,
                onModeChange = { selectedMode = it },
                hardcoreBonusLabel = preview.hardcoreBonusLabel(),
                dontShowAgain = dontShowAgain,
                onDontShowAgainChange = { dontShowAgain = it },
                onDismiss = { showUnbalancedDialog = false },
                onFight = { confirmChallenge() }
            )
        }
    }
}
