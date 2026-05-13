package com.lilru.liftr.ui.territory

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.lilru.liftr.territory.TerritoryCaptureClient
import com.lilru.liftr.territory.TerritoryCityRegionRowWire
import com.lilru.liftr.territory.TerritoryRecentTakeoverRowWire
import com.lilru.liftr.territory.TerritorySummaryWire
import io.github.jan.supabase.SupabaseClient

@Composable
fun TerritoryProfileHubCard(
    supabase: SupabaseClient,
    profileUserId: String,
    isOwnProfile: Boolean,
    onOpenMap: () -> Unit,
    modifier: Modifier = Modifier
) {
    var summary by remember { mutableStateOf<TerritorySummaryWire?>(null) }
    var cities by remember { mutableStateOf<List<TerritoryCityRegionRowWire>>(emptyList()) }
    var takeovers by remember { mutableStateOf<List<TerritoryRecentTakeoverRowWire>>(emptyList()) }
    var loading by remember { mutableStateOf(true) }

    val topCities = cities
        .filter { (it.myOwnedCells ?: it.ownedCells ?: 0) > 0 }
        .sortedByDescending { it.myOwnedCells ?: it.ownedCells ?: 0 }
        .take(3)

    LaunchedEffect(supabase, profileUserId, isOwnProfile) {
        loading = true
        if (isOwnProfile) {
            summary = TerritoryCaptureClient.fetchTerritorySummary(supabase, userId = null)
            cities = TerritoryCaptureClient.fetchTerritoryCityRegions(supabase)
            takeovers = TerritoryCaptureClient.fetchRecentTakeovers(supabase, userId = null, limit = 3)
        } else {
            summary = TerritoryCaptureClient.fetchTerritorySummary(supabase, userId = profileUserId)
            cities = TerritoryCaptureClient.fetchUserTerritoryTopCities(supabase, profileUserId)
            takeovers = TerritoryCaptureClient.fetchRecentTakeovers(supabase, userId = profileUserId, limit = 3)
        }
        loading = false
    }

    Card(
        modifier = modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.38f)
        )
    ) {
        Column(
            modifier = Modifier.padding(14.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text("Territory", style = MaterialTheme.typography.titleMedium)
                TextButton(onClick = onOpenMap) {
                    Text("Open map")
                }
            }

            when {
                loading -> CircularProgressIndicator()
                summary != null -> {
                    val s = summary!!
                    val total = s.totalCells ?: 0
                    val week = s.cellsLast7d ?: 0
                    Text(
                        text = if (isOwnProfile) {
                            "You own $total cells · $week captured in the last 7 days"
                        } else {
                            "Owns $total cells · $week captured in the last 7 days"
                        },
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    if (topCities.isEmpty()) {
                        Text(
                            text = if (isOwnProfile) {
                                "Finish an outdoor GPS cardio workout to start capturing territory."
                            } else {
                                "This athlete has not captured any territory yet."
                            },
                            style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    } else {
                        topCities.forEach { city ->
                            Text(
                                text = TerritoryCaptureClient.citySummaryLabel(city),
                                style = MaterialTheme.typography.labelMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    }
                    if (takeovers.isNotEmpty()) {
                        Text(
                            text = "Recent takeovers",
                            style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                        takeovers.forEach { takeover ->
                            val username = takeover.otherUsername ?: "user"
                            val cells = takeover.cellsTaken ?: 0
                            val share = takeover.shareTakenPct ?: 0.0
                            Text(
                                text = "Took $cells cells ($share% of @$username)",
                                style = MaterialTheme.typography.labelMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    }
                }
                else -> {
                    Text(
                        text = "Territory summary is unavailable right now.",
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
        }
    }
}
