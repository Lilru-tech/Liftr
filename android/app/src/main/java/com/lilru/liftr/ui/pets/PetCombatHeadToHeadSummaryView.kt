package com.lilru.liftr.ui.pets

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.lilru.liftr.data.PetCombatHeadToHeadLastBattleWire
import com.lilru.liftr.data.PetCombatHeadToHeadSummaryWire
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

@Composable
fun PetCombatHeadToHeadSummaryView(
    summary: PetCombatHeadToHeadSummaryWire,
    opponentUsername: String?,
    modifier: Modifier = Modifier
) {
    val opponentLabel = opponentUsername?.let { "@$it" } ?: "this opponent"
    Column(
        modifier = modifier
            .fillMaxWidth()
            .background(
                MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f),
                RoundedCornerShape(12.dp)
            )
            .padding(12.dp)
    ) {
        Text(
            text = "Record vs $opponentLabel: ${summary.wins}W · ${summary.losses}L · ${summary.draws}D (${summary.winRatePercentText()})",
            style = MaterialTheme.typography.bodyMedium,
            fontWeight = FontWeight.SemiBold
        )
        summary.lastBattle?.let { last ->
            Text(
                text = lastBattleText(last),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(top = 6.dp)
            )
        }
    }
}

private fun lastBattleText(last: PetCombatHeadToHeadLastBattleWire): String {
    val outcome = when {
        last.isDraw -> "Draw"
        last.won -> "Victory"
        else -> "Defeat"
    }
    val parts = mutableListOf("Last: $outcome")
    val rewards = last.rewards
    if (rewards != null && (rewards.xp > 0 || rewards.coins > 0)) {
        parts.add("+${rewards.xp} XP")
        if (rewards.coins > 0) {
            parts.add("+${rewards.coins} coins")
        }
    }
    last.createdAt?.let { raw ->
        runCatching {
            val dt = Instant.parse(raw).atZone(ZoneId.systemDefault())
            DateTimeFormatter.ofPattern("MMM d", Locale.getDefault()).format(dt)
        }.getOrNull()?.let { parts.add(it) }
    }
    return parts.joinToString(" · ")
}
