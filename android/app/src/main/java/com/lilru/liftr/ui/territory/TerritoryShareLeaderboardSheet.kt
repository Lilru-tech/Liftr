package com.lilru.liftr.ui.territory

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextField
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.lilru.liftr.prefs.LiftrPreferences
import com.lilru.liftr.territory.TerritoryCaptureClient
import com.lilru.liftr.territory.TerritoryCityRegionRowWire
import com.lilru.liftr.territory.TerritoryShareLeaderRowWire
import com.lilru.liftr.ui.components.LiftrAvatar
import com.lilru.liftr.ui.theme.liftrAppBackgroundGradientOpaque
import io.github.jan.supabase.SupabaseClient

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TerritoryShareLeaderboardSheet(
    supabase: SupabaseClient,
    onDismiss: () -> Unit,
    initialLatitude: Double? = null,
    initialLongitude: Double? = null
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val context = LocalContext.current
    val themeId = LiftrPreferences.backgroundTheme(context)
    var scope by remember { mutableStateOf("global") }
    var rows by remember { mutableStateOf<List<TerritoryShareLeaderRowWire>>(emptyList()) }
    var cities by remember { mutableStateOf<List<TerritoryCityRegionRowWire>>(emptyList()) }
    var selectedCityKey by remember { mutableStateOf<String?>(null) }
    var cityMenuExpanded by remember { mutableStateOf(false) }
    var loading by remember { mutableStateOf(true) }

    LaunchedEffect(scope, selectedCityKey, initialLatitude, initialLongitude) {
        loading = true
        var fetchedCities = cities
        if (fetchedCities.isEmpty()) {
            fetchedCities = TerritoryCaptureClient.fetchTerritoryCityRegions(supabase)
            cities = fetchedCities
        }
        var cityKey = selectedCityKey
        if (cityKey.isNullOrBlank()) {
            cityKey = TerritoryCaptureClient.nearestCityKey(
                latitude = initialLatitude,
                longitude = initialLongitude,
                cities = fetchedCities
            ) ?: fetchedCities.firstOrNull()?.cityKey
            if (!cityKey.isNullOrBlank() && selectedCityKey == null) {
                selectedCityKey = cityKey
                return@LaunchedEffect
            }
        }
        if (cityKey.isNullOrBlank()) {
            rows = emptyList()
            loading = false
            return@LaunchedEffect
        }
        rows = TerritoryCaptureClient.fetchTerritoryCityShareLeaderboard(
            supabase = supabase,
            cityKey = cityKey,
            scope = scope
        )
        loading = false
    }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = MaterialTheme.colorScheme.surface,
        scrimColor = Color.Black.copy(alpha = 0.55f)
    ) {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .liftrAppBackgroundGradientOpaque(themeId)
        ) {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(horizontal = 16.dp, vertical = 8.dp)
            ) {
                Text(
                    text = "Territory share",
                    style = MaterialTheme.typography.titleLarge,
                    modifier = Modifier.padding(bottom = 12.dp)
                )
                if (cities.size > 1) {
                    val selectedCity = cities.firstOrNull { it.cityKey == selectedCityKey }
                    ExposedDropdownMenuBox(
                        expanded = cityMenuExpanded,
                        onExpandedChange = { cityMenuExpanded = it },
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(bottom = 12.dp)
                    ) {
                        TextField(
                            value = selectedCity?.let(TerritoryCaptureClient::citySummaryLabel) ?: "City",
                            onValueChange = {},
                            readOnly = true,
                            label = { Text("City") },
                            trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = cityMenuExpanded) },
                            modifier = Modifier
                                .menuAnchor()
                                .fillMaxWidth()
                        )
                        ExposedDropdownMenu(
                            expanded = cityMenuExpanded,
                            onDismissRequest = { cityMenuExpanded = false }
                        ) {
                            cities.forEach { city ->
                                DropdownMenuItem(
                                    text = { Text(TerritoryCaptureClient.citySummaryLabel(city)) },
                                    onClick = {
                                        selectedCityKey = city.cityKey
                                        cityMenuExpanded = false
                                    }
                                )
                            }
                        }
                    }
                } else {
                    cities.firstOrNull()?.let { city ->
                        Text(
                            text = TerritoryCaptureClient.citySummaryLabel(city),
                            style = MaterialTheme.typography.titleSmall,
                            modifier = Modifier.padding(bottom = 12.dp)
                        )
                    }
                }
                SingleChoiceSegmentedButtonRow(modifier = Modifier.fillMaxWidth()) {
                    SegmentedButton(
                        selected = scope == "global",
                        onClick = { scope = "global" },
                        shape = SegmentedButtonDefaults.itemShape(index = 0, count = 2)
                    ) { Text("Global") }
                    SegmentedButton(
                        selected = scope == "friends",
                        onClick = { scope = "friends" },
                        shape = SegmentedButtonDefaults.itemShape(index = 1, count = 2)
                    ) { Text("Friends") }
                }
                if (loading) {
                    CircularProgressIndicator(
                        modifier = Modifier
                            .align(Alignment.CenterHorizontally)
                            .padding(24.dp)
                    )
                } else if (rows.isEmpty()) {
                    Text(
                        text = "No territory yet",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(top = 24.dp)
                    )
                } else {
                    LazyColumn(modifier = Modifier.padding(top = 12.dp)) {
                        items(rows, key = { it.userId }) { row ->
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(vertical = 10.dp),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Text(
                                    text = "${row.rank}.",
                                    style = MaterialTheme.typography.titleMedium,
                                    modifier = Modifier.padding(end = 8.dp)
                                )
                                LiftrAvatar(
                                    imageUrl = row.avatarUrl,
                                    displayName = row.username,
                                    size = 36.dp
                                )
                                Column(
                                    modifier = Modifier
                                        .weight(1f)
                                        .padding(horizontal = 12.dp)
                                ) {
                                    Text(
                                        text = row.username?.let { "@$it" } ?: "Unknown",
                                        style = MaterialTheme.typography.bodyLarge
                                    )
                                    Text(
                                        text = "${row.ownedCells ?: 0} cells",
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant
                                    )
                                }
                                Text(
                                    text = String.format("%.2f%%", row.territorySharePct ?: 0.0),
                                    style = MaterialTheme.typography.titleMedium
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}
