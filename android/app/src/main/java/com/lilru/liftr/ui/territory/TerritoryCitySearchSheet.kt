package com.lilru.liftr.ui.territory

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.lilru.liftr.prefs.LiftrPreferences
import com.lilru.liftr.territory.TerritoryCaptureClient
import com.lilru.liftr.territory.TerritoryCityRegionRowWire
import com.lilru.liftr.ui.theme.liftrAppBackgroundGradientOpaque
import io.github.jan.supabase.SupabaseClient
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TerritoryCitySearchSheet(
    supabase: SupabaseClient,
    selectedCityKey: String?,
    referenceLatitude: Double?,
    referenceLongitude: Double?,
    onDismiss: () -> Unit,
    onSelect: (TerritoryCityRegionRowWire) -> Unit
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val context = LocalContext.current
    val themeId = LiftrPreferences.backgroundTheme(context)
    var searchText by remember { mutableStateOf("") }
    var cities by remember { mutableStateOf<List<TerritoryCityRegionRowWire>>(emptyList()) }
  var loading by remember { mutableStateOf(true) }
    val coroutineScope = rememberCoroutineScope()

    suspend fun loadCities(query: String?) {
        loading = true
        cities = TerritoryCaptureClient.fetchTerritoryCityRegions(
            supabase = supabase,
            query = query,
            ownedFirst = true
        )
        loading = false
    }

    LaunchedEffect(Unit) {
        loadCities(null)
        TerritoryCaptureClient.refreshPendingTerritoryCityRegionsInBackground(
            supabase = supabase,
            scope = coroutineScope
        ) { updated ->
            cities = updated
        }
    }

    LaunchedEffect(searchText) {
        val trimmed = searchText.trim()
        if (trimmed.length < 2) {
            loadCities(null)
            return@LaunchedEffect
        }
        delay(250)
        loadCities(trimmed)
    }

    val displayedCities = remember(cities, searchText) {
        val trimmed = searchText.trim()
        if (trimmed.length < 2) cities else TerritoryCaptureClient.filterTerritoryCities(cities, trimmed)
    }
    val recentCities = remember(cities) {
        TerritoryCaptureClient.recentTerritoryCityKeys(context).mapNotNull { key ->
            cities.firstOrNull { it.cityKey == key }
        }
    }
    val ownedCities = remember(cities) {
        cities.filter { (it.myOwnedCells ?: 0) > 0 }
    }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = MaterialTheme.colorScheme.surface,
        scrimColor = Color.Black.copy(alpha = 0.55f)
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .liftrAppBackgroundGradientOpaque(themeId)
                .padding(horizontal = 16.dp, vertical = 8.dp)
        ) {
            Text(
                text = "Choose city",
                style = MaterialTheme.typography.titleLarge,
                modifier = Modifier.padding(bottom = 12.dp)
            )
            OutlinedTextField(
                value = searchText,
                onValueChange = { searchText = it },
                modifier = Modifier.fillMaxWidth(),
                label = { Text("Search cities") },
                singleLine = true
            )
            if (loading && displayedCities.isEmpty()) {
                Text(
                    text = "Loading…",
                    modifier = Modifier.padding(top = 24.dp)
                )
            } else if (displayedCities.isEmpty()) {
                Text(
                    text = "No cities match your search",
                    modifier = Modifier.padding(top = 24.dp)
                )
            } else {
                LazyColumn(modifier = Modifier.padding(top = 12.dp)) {
                    if (recentCities.isNotEmpty() && searchText.trim().length < 2) {
                        item { Text("Recent", style = MaterialTheme.typography.labelLarge) }
                        items(recentCities, key = { "recent-${it.cityKey}" }) { city ->
                            TerritoryCitySearchRow(
                                city = city,
                                selected = city.cityKey == selectedCityKey,
                                onClick = {
                                    TerritoryCaptureClient.recordRecentTerritoryCityKey(context, city.cityKey)
                                    onSelect(city)
                                }
                            )
                        }
                    }
                    if (ownedCities.isNotEmpty() && searchText.trim().length < 2) {
                        item { Text("Your cities", style = MaterialTheme.typography.labelLarge) }
                        items(ownedCities, key = { "owned-${it.cityKey}" }) { city ->
                            TerritoryCitySearchRow(
                                city = city,
                                selected = city.cityKey == selectedCityKey,
                                onClick = {
                                    TerritoryCaptureClient.recordRecentTerritoryCityKey(context, city.cityKey)
                                    onSelect(city)
                                }
                            )
                        }
                    }
                    item { Text("All cities", style = MaterialTheme.typography.labelLarge) }
                    items(displayedCities, key = { it.cityKey ?: it.displayName ?: it.hashCode().toString() }) { city ->
                        TerritoryCitySearchRow(
                            city = city,
                            selected = city.cityKey == selectedCityKey,
                            onClick = {
                                TerritoryCaptureClient.recordRecentTerritoryCityKey(context, city.cityKey)
                                onSelect(city)
                            }
                        )
                    }
                }
            }
            TextButton(onClick = onDismiss, modifier = Modifier.padding(top = 8.dp)) {
                Text("Done")
            }
        }
    }
}

@Composable
private fun TerritoryCitySearchRow(
    city: TerritoryCityRegionRowWire,
    selected: Boolean,
    onClick: () -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(vertical = 10.dp)
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(text = city.displayName ?: city.cityKey ?: "City")
            Text(
                text = TerritoryCaptureClient.citySummaryLabel(city),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
        if (selected) {
            Text("✓", color = MaterialTheme.colorScheme.primary)
        }
    }
}

@Composable
fun TerritoryCityPickerButton(
    selectedCity: TerritoryCityRegionRowWire?,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 14.dp, vertical = 10.dp)
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text("City", style = MaterialTheme.typography.labelSmall)
            Text(
                text = selectedCity?.let(TerritoryCaptureClient::citySummaryLabel) ?: "Select city",
                style = MaterialTheme.typography.bodyLarge
            )
        }
        Text("Search", style = MaterialTheme.typography.labelMedium)
    }
}
