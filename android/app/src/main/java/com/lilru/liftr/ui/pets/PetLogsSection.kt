package com.lilru.liftr.ui.pets

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Card
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.lilru.liftr.data.PetLogWire
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

@Composable
fun PetLogsSection(
    logs: List<PetLogWire>,
    hasMore: Boolean,
    onLoadMore: () -> Unit,
    onDeleteAll: () -> Unit,
    modifier: Modifier = Modifier
) {
    Column(modifier = modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        if (logs.isEmpty()) {
            Text(
                "No logs yet",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(vertical = 8.dp)
            )
        } else {
            logs.forEach { log ->
                Card(modifier = Modifier.fillMaxWidth()) {
                    Column(modifier = Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                            Text(log.title(), fontWeight = FontWeight.SemiBold)
                            Text(
                                formatLogDate(log.createdAt),
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                        if (log.showsCombatSubtitle()) {
                            log.subtitle()?.let { subtitle ->
                                Text(subtitle, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                        } else if (log.expGained > 0) {
                            Text("Exp gained: ${log.expGained}", style = MaterialTheme.typography.bodySmall)
                        }
                        log.newLevel?.let {
                            Text("New level: $it", style = MaterialTheme.typography.bodySmall)
                        }
                    }
                }
            }
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                if (hasMore) {
                    TextButton(onClick = onLoadMore) { Text("See more logs...") }
                } else {
                    Row {}
                }
                TextButton(onClick = onDeleteAll) {
                    Text("Delete logs", color = MaterialTheme.colorScheme.error)
                }
            }
        }
    }
}

private fun formatLogDate(raw: String): String = runCatching {
    val dt = Instant.parse(raw).atZone(ZoneId.systemDefault())
    DateTimeFormatter.ofPattern("d/M/yyyy, HH:mm", Locale.getDefault()).format(dt)
}.getOrDefault(raw)
