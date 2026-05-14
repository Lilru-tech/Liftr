package com.lilru.liftr.ui.territory

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.google.android.gms.maps.CameraUpdateFactory
import com.google.android.gms.maps.model.CameraPosition
import com.google.android.gms.maps.model.LatLng
import com.google.android.gms.maps.model.LatLngBounds
import com.google.maps.android.compose.GoogleMap
import com.google.maps.android.compose.MapEffect
import com.google.maps.android.compose.MapProperties
import com.google.maps.android.compose.MapUiSettings
import com.google.maps.android.compose.Polygon
import com.google.maps.android.compose.rememberCameraPositionState
import com.lilru.liftr.BuildConfig
import com.lilru.liftr.prefs.LiftrPreferences
import com.lilru.liftr.territory.TerritoryCaptureClient
import com.lilru.liftr.territory.TerritoryMapCellWire
import com.lilru.liftr.territory.TerritoryMapGeometry
import com.lilru.liftr.territory.TerritoryOwnerColors
import com.lilru.liftr.territory.TerritorySummaryWire
import com.lilru.liftr.ui.map.TerritoryCellsMapPreview
import io.github.jan.supabase.SupabaseClient
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.util.UUID

private val defaultTerritoryCenter = LatLng(41.1189, 1.2445)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TerritoryMapScreen(
    supabase: SupabaseClient,
    onOpenProfile: (UUID) -> Unit = {},
    initialLatitude: Double? = null,
    initialLongitude: Double? = null,
    modifier: Modifier = Modifier
) {
    var cells by remember { mutableStateOf<List<TerritoryMapCellWire>>(emptyList()) }
    var summary by remember { mutableStateOf<TerritorySummaryWire?>(null) }
    var loading by remember { mutableStateOf(false) }
    var lastFetchKey by remember { mutableStateOf("") }
    var selectedCell by remember { mutableStateOf<TerritoryMapCellWire?>(null) }
    var showLeaderboard by remember { mutableStateOf(false) }
    var showMineOnly by remember { mutableStateOf(false) }
    var summaryError by remember { mutableStateOf<String?>(null) }
    var hasFramedCells by remember { mutableStateOf(false) }
    val cellSheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val context = LocalContext.current
    val referenceCoordinate = remember(context, initialLatitude, initialLongitude) {
        if (initialLatitude != null && initialLongitude != null) {
            initialLatitude to initialLongitude
        } else {
            LiftrPreferences.territoryReferenceCoordinate(context)
        }
    }
    val cameraPositionState = rememberCameraPositionState {
        val center = referenceCoordinate?.let { (lat, lon) -> LatLng(lat, lon) } ?: defaultTerritoryCenter
        position = CameraPosition.fromLatLngZoom(center, 12f)
    }

    LaunchedEffect(initialLatitude, initialLongitude) {
        val center = referenceCoordinate?.let { (lat, lon) -> LatLng(lat, lon) } ?: return@LaunchedEffect
        LiftrPreferences.setTerritoryReferenceCoordinate(context, center.latitude, center.longitude)
        cameraPositionState.move(CameraUpdateFactory.newLatLngZoom(center, 12f))
    }

    suspend fun refreshForCamera() {
        val target = cameraPositionState.position.target
        val zoom = cameraPositionState.position.zoom
        val latDelta = 360.0 / (1 shl zoom.toInt().coerceAtLeast(1)).toDouble()
        val lonDelta = latDelta
        val minLat = target.latitude - latDelta / 2.0
        val maxLat = target.latitude + latDelta / 2.0
        val minLon = target.longitude - lonDelta / 2.0
        val maxLon = target.longitude + lonDelta / 2.0
        val key = "%.4f|%.4f|%.4f|%.4f".format(minLat, minLon, maxLat, maxLon)
        if (key == lastFetchKey) return
        lastFetchKey = key
        loading = true
        cells = TerritoryCaptureClient.fetchMapCells(
            supabase = supabase,
            minLat = minLat,
            minLon = minLon,
            maxLat = maxLat,
            maxLon = maxLon
        )
        val drawableCells = cells.count { (it.cellGeojson?.ringLatLng()?.size ?: 0) >= 3 }
        TerritoryMapDiagnostics.logCellsFetched(cells.size, drawableCells)
        loading = false
    }

    val visibleCells = if (showMineOnly) cells.filter { it.isMine == true } else cells

    LaunchedEffect(Unit) {
        TerritoryMapDiagnostics.logStartup(context)
    }

    LaunchedEffect(supabase) {
        launch {
            summary = TerritoryCaptureClient.fetchMySummary(supabase)
            summaryError = if (summary == null) "Territory summary could not be loaded." else null
        }
        refreshForCamera()
        launch {
            TerritoryCaptureClient.backfillHistoricalCaptures(supabase, context)
            summary = TerritoryCaptureClient.fetchMySummary(supabase)
        }
        lastFetchKey = ""
        refreshForCamera()
    }

    LaunchedEffect(cameraPositionState.position) {
        delay(350)
        refreshForCamera()
    }

    LaunchedEffect(visibleCells) {
        if (hasFramedCells || visibleCells.isEmpty()) return@LaunchedEffect
        val points = visibleCells.flatMap { it.cellGeojson?.ringLatLng().orEmpty() }
        if (points.size < 2) return@LaunchedEffect
        val boundsBuilder = LatLngBounds.Builder()
        points.forEach { (lat, lon) ->
            boundsBuilder.include(LatLng(lat, lon))
        }
        runCatching {
            cameraPositionState.move(CameraUpdateFactory.newLatLngBounds(boundsBuilder.build(), 96))
            hasFramedCells = true
        }
    }

    Box(modifier = modifier.fillMaxSize()) {
        if (BuildConfig.MAPS_API_KEY.isBlank()) {
            Column(
                modifier = Modifier
                    .align(Alignment.Center)
                    .padding(24.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Text(
                    text = "Map polygons require Google Maps.",
                    style = MaterialTheme.typography.bodyMedium
                )
                Text(
                    text = "Add a Maps API key to see territory cells on the map.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            val previewCells = visibleCells.filter {
                (it.cellGeojson?.ringLatLng()?.size ?: 0) >= 3
            }
            if (previewCells.isNotEmpty()) {
                TerritoryCellsMapPreview(
                    cells = previewCells,
                    modifier = Modifier.fillMaxSize(),
                    expandToFill = true
                )
            }
        } else {
            val mapProperties = remember {
                MapProperties(isMyLocationEnabled = true)
            }
            GoogleMap(
                modifier = Modifier.fillMaxSize(),
                cameraPositionState = cameraPositionState,
                properties = mapProperties,
                uiSettings = MapUiSettings(myLocationButtonEnabled = true, zoomControlsEnabled = false),
                onMapClick = { latLng ->
                    selectedCell = TerritoryMapGeometry.selectedCell(latLng.latitude, latLng.longitude, visibleCells)
                }
            ) {
                MapEffect(Unit) { map ->
                    map.setOnMapLoadedCallback {
                        TerritoryMapDiagnostics.logMapLoaded()
                    }
                }
                visibleCells.forEach { cell ->
                    val ring = cell.cellGeojson?.ringLatLng().orEmpty()
                    if (ring.size < 3) return@forEach
                    val ownerKey = cell.ownerUserId?.takeIf { it.isNotBlank() } ?: cell.cellId
                    val isMine = cell.isMine == true
                    Polygon(
                        points = ring.map { (lat, lon) -> LatLng(lat, lon) },
                        fillColor = TerritoryOwnerColors.fill(ownerKey, isMine),
                        strokeColor = TerritoryOwnerColors.stroke(ownerKey, isMine),
                        strokeWidth = TerritoryOwnerColors.strokeWidth(isMine)
                    )
                }
            }
        }

        summary?.let { s ->
            val ownedInView = visibleCells.count { it.isMine == true }
            Surface(
                modifier = Modifier
                    .align(Alignment.TopCenter)
                    .fillMaxWidth()
                    .padding(horizontal = 8.dp, vertical = 8.dp),
                shape = RoundedCornerShape(12.dp),
                color = MaterialTheme.colorScheme.surface.copy(alpha = 0.94f),
                tonalElevation = 2.dp
            ) {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 12.dp, vertical = 10.dp),
                    verticalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            text = "You own ${s.totalCells ?: 0} cells",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                        Text(
                            text = "7d captures: ${s.cellsLast7d ?: 0}",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.padding(start = 16.dp)
                        )
                        TextButton(onClick = { showLeaderboard = true }) {
                            Text("Leaderboard")
                        }
                    }
                    Text(
                        text = "Public map · colored cells are owned territory · brighter cells are yours",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        Text(
                            text = "Show only my cells",
                            style = MaterialTheme.typography.labelSmall
                        )
                        Switch(checked = showMineOnly, onCheckedChange = { showMineOnly = it })
                    }
                    if (visibleCells.isNotEmpty() && ownedInView == 0) {
                        Text(
                            text = "${visibleCells.size} cells in view belong to other players",
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }
            }
        }

        summaryError?.let { message ->
            Text(
                text = message,
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier
                    .align(Alignment.TopCenter)
                    .padding(8.dp)
            )
        }

        if (loading) {
            CircularProgressIndicator(modifier = Modifier.align(Alignment.Center))
        }
    }

    if (selectedCell != null) {
        ModalBottomSheet(
            onDismissRequest = { selectedCell = null },
            sheetState = cellSheetState
        ) {
            val cell = selectedCell!!
            Column(modifier = Modifier.padding(20.dp)) {
                Text(
                    text = cell.ownerUsername?.let { "@$it" } ?: "Unknown owner",
                    style = MaterialTheme.typography.titleMedium
                )
                Text(
                    text = cell.capturedAt?.let { "Captured $it" } ?: "Captured recently",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(top = 4.dp, bottom = 16.dp)
                )
                cell.ownerUserId?.let { ownerId ->
                    Button(onClick = {
                        runCatching { UUID.fromString(ownerId) }.getOrNull()?.let(onOpenProfile)
                        selectedCell = null
                    }) {
                        Text("View profile")
                    }
                }
            }
        }
    }

    if (showLeaderboard) {
        TerritoryShareLeaderboardSheet(
            supabase = supabase,
            onDismiss = { showLeaderboard = false },
            initialLatitude = cameraPositionState.position.target.latitude,
            initialLongitude = cameraPositionState.position.target.longitude
        )
    }
}
