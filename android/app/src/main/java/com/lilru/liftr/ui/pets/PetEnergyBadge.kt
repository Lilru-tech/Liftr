package com.lilru.liftr.ui.pets

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.lilru.liftr.data.ProfileEnergyWire
import java.time.Instant
import java.time.OffsetDateTime
import kotlinx.coroutines.delay

@Composable
fun PetEnergyBadge(
    energy: ProfileEnergyWire,
    modifier: Modifier = Modifier,
    label: String? = null,
    horizontalAlignment: Alignment.Horizontal = Alignment.Start
) {
    Column(
        modifier = modifier,
        horizontalAlignment = horizontalAlignment,
        verticalArrangement = Arrangement.spacedBy(2.dp)
    ) {
        label?.let {
            Text(
                it,
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            Icon(
                Icons.Filled.Bolt,
                contentDescription = null,
                tint = Color(0xFFFF9800),
                modifier = Modifier.size(18.dp)
            )
            Text("${energy.current}/${energy.max}", fontWeight = FontWeight.SemiBold)
        }
        if (energy.isFull) {
            Text(
                "Full",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        } else {
            val target = remember(energy.nextRefreshAt) {
                energy.nextRefreshAt?.let(::parseEnergyInstant)
            }
            if (target != null) {
                var now by remember { mutableStateOf(Instant.now()) }
                LaunchedEffect(target) {
                    while (true) {
                        now = Instant.now()
                        delay(30_000)
                    }
                }
                Text(
                    "+1 in ${energyCountdownText(now, target)}",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }
}

private fun parseEnergyInstant(raw: String): Instant? =
    runCatching { Instant.parse(raw) }.getOrNull()
        ?: runCatching { OffsetDateTime.parse(raw).toInstant() }.getOrNull()

internal fun energyCountdownText(now: Instant, target: Instant): String {
    val remaining = maxOf(0L, target.epochSecond - now.epochSecond)
    val hours = remaining / 3600
    val minutes = (remaining % 3600) / 60
    return when {
        hours > 0 -> "${hours}h ${minutes}m"
        minutes > 0 -> "${minutes}m"
        else -> "<1m"
    }
}
