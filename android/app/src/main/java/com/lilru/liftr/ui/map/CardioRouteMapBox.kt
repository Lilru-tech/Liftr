package com.lilru.liftr.ui.map

import android.content.Context
import android.content.Intent
import android.location.Location
import android.net.Uri
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.google.android.gms.maps.CameraUpdateFactory
import com.google.android.gms.maps.model.LatLng
import com.google.maps.android.compose.GoogleMap
import com.google.maps.android.compose.MapProperties
import com.google.maps.android.compose.MapUiSettings
import com.google.maps.android.compose.Polygon
import com.google.maps.android.compose.Polyline
import com.google.maps.android.compose.rememberCameraPositionState
import com.lilru.liftr.BuildConfig
import com.lilru.liftr.R
import com.lilru.liftr.cardio.CardioRouteGeoJson
import com.lilru.liftr.territory.TerritoryMapCellWire
import com.lilru.liftr.territory.TerritoryOwnerColors

/**
 * Abre la ruta en Google Maps (equivalente práctico a Apple Maps en iOS).
 */
fun startGoogleMapsForRoute(context: Context, points: List<Pair<Double, Double>>) {
    if (points.size < 2) return
    val path = points.joinToString("/") { "${it.first},${it.second}" }
    val uri = Uri.parse("https://www.google.com/maps/dir/$path")
    val gms = Intent(Intent.ACTION_VIEW, uri).apply { setPackage("com.google.android.apps.maps") }
    runCatching { context.startActivity(gms) }.onFailure {
        context.startActivity(Intent(Intent.ACTION_VIEW, uri))
    }
}

/** Centra Google Maps en un punto (p. ej. mitad de un segmento). */
fun startGoogleMapsAtPoint(context: Context, lat: Double, lon: Double, label: String? = null) {
    if (!lat.isFinite() || !lon.isFinite()) return
    val q = if (label.isNullOrBlank()) {
        "$lat,$lon"
    } else {
        Uri.encode("$lat,$lon ($label)")
    }
    val uri = Uri.parse("https://www.google.com/maps/search/?api=1&query=$q")
    val gms = Intent(Intent.ACTION_VIEW, uri).apply { setPackage("com.google.android.apps.maps") }
    runCatching { context.startActivity(gms) }.onFailure {
        context.startActivity(Intent(Intent.ACTION_VIEW, uri))
    }
}

@Composable
fun CardioRoutePolylinePreview(
    routePoints: List<Pair<Double, Double>>,
    modifier: Modifier = Modifier,
    mapHeightDp: Int = 220,
    expandToFill: Boolean = false
) {
    if (routePoints.size < 2) return
    val bg = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.72f)
    val lineColor = Color(0xE02196F3)
    val sizeMod = if (expandToFill) {
        Modifier.fillMaxWidth().fillMaxHeight()
    } else {
        Modifier.fillMaxWidth().height(mapHeightDp.dp)
    }
    val clipMod = if (expandToFill) Modifier else Modifier.clip(RoundedCornerShape(16.dp))
    Canvas(
        modifier = modifier
            .then(sizeMod)
            .then(clipMod)
            .background(bg)
    ) {
        val pad = 14.dp.toPx()
        val w = (size.width - 2 * pad).coerceAtLeast(1f)
        val h = (size.height - 2 * pad).coerceAtLeast(1f)
        val minLat = routePoints.minOf { it.first }
        val maxLat = routePoints.maxOf { it.first }
        val minLon = routePoints.minOf { it.second }
        val maxLon = routePoints.maxOf { it.second }
        val dLat = (maxLat - minLat).coerceAtLeast(1e-8)
        val dLon = (maxLon - minLon).coerceAtLeast(1e-8)
        fun project(lat: Double, lon: Double): Offset {
            val x = pad + ((lon - minLon) / dLon * w).toFloat()
            val y = pad + ((maxLat - lat) / dLat * h).toFloat()
            return Offset(x, y)
        }
        val path = Path().apply {
            val o = project(routePoints[0].first, routePoints[0].second)
            moveTo(o.x, o.y)
            for (i in 1 until routePoints.size) {
                val p = project(routePoints[i].first, routePoints[i].second)
                lineTo(p.x, p.y)
            }
        }
        drawPath(
            path = path,
            color = lineColor,
            style = Stroke(width = 8.dp.toPx(), cap = StrokeCap.Round)
        )
    }
}

@Composable
fun TerritoryCellsMapPreview(
    cells: List<TerritoryMapCellWire>,
    modifier: Modifier = Modifier,
    expandToFill: Boolean = false
) {
    val paintedCells = remember(cells) {
        cells.mapNotNull { cell ->
            val ring = cell.cellGeojson?.ringLatLng().orEmpty()
            if (ring.size < 3) null else {
                val ownerKey = cell.ownerUserId?.takeIf { it.isNotBlank() } ?: cell.cellId
                Triple(cell, ownerKey, ring)
            }
        }
    }
    if (paintedCells.isEmpty()) return
    val bg = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.72f)
    val sizeMod = if (expandToFill) {
        Modifier.fillMaxWidth().fillMaxHeight()
    } else {
        Modifier.fillMaxWidth().height(220.dp)
    }
    val clipMod = if (expandToFill) Modifier else Modifier.clip(RoundedCornerShape(16.dp))
    Canvas(
        modifier = modifier
            .then(sizeMod)
            .then(clipMod)
            .background(bg)
    ) {
        val allPoints = paintedCells.flatMap { it.third }
        val pad = 14.dp.toPx()
        val w = (size.width - 2 * pad).coerceAtLeast(1f)
        val h = (size.height - 2 * pad).coerceAtLeast(1f)
        val minLat = allPoints.minOf { it.first }
        val maxLat = allPoints.maxOf { it.first }
        val minLon = allPoints.minOf { it.second }
        val maxLon = allPoints.maxOf { it.second }
        val dLat = (maxLat - minLat).coerceAtLeast(1e-8)
        val dLon = (maxLon - minLon).coerceAtLeast(1e-8)
        fun project(lat: Double, lon: Double): Offset {
            val x = pad + ((lon - minLon) / dLon * w).toFloat()
            val y = pad + ((maxLat - lat) / dLat * h).toFloat()
            return Offset(x, y)
        }
        paintedCells.forEach { (cell, ownerKey, ring) ->
            val path = Path().apply {
                val first = project(ring[0].first, ring[0].second)
                moveTo(first.x, first.y)
                for (index in 1 until ring.size) {
                    val point = project(ring[index].first, ring[index].second)
                    lineTo(point.x, point.y)
                }
                close()
            }
            val isMine = cell.isMine == true
            drawPath(
                path = path,
                color = TerritoryOwnerColors.fill(ownerKey, isMine)
            )
            drawPath(
                path = path,
                color = TerritoryOwnerColors.stroke(ownerKey, isMine),
                style = Stroke(width = TerritoryOwnerColors.strokeWidth(isMine))
            )
        }
    }
}

@Composable
fun CardioRouteMapBox(
    /** Pares (lat, lon), al menos 2 para dibujar. */
    routePoints: List<Pair<Double, Double>>,
    modifier: Modifier = Modifier,
    mapHeightDp: Int = 220,
    expandToFill: Boolean = false,
    useRichMapControls: Boolean = false,
    territoryPreviewRings: List<List<Pair<Double, Double>>> = emptyList()
) {
    if (routePoints.size < 2) return
    if (BuildConfig.MAPS_API_KEY.isBlank()) {
        CardioRoutePolylinePreview(
            routePoints,
            modifier = modifier,
            mapHeightDp = mapHeightDp,
            expandToFill = expandToFill
        )
        return
    }

    val latLngs = CardioRouteGeoJson.toLatLngList(routePoints)
    val camera = rememberCameraPositionState()
    val paddingPx = if (expandToFill) 96 else 64
    LaunchedEffect(routePoints, expandToFill) {
        val b = CardioRouteGeoJson.latLngBoundsForRoute(routePoints) ?: return@LaunchedEffect
        runCatching {
            camera.move(CameraUpdateFactory.newLatLngBounds(b, paddingPx))
        }
    }
    val mapModifier = if (expandToFill) {
        modifier.fillMaxWidth().fillMaxHeight()
    } else {
        modifier.fillMaxWidth().height(mapHeightDp.dp).clip(RoundedCornerShape(16.dp))
    }
    GoogleMap(
        modifier = mapModifier,
        cameraPositionState = camera,
        properties = MapProperties(isMyLocationEnabled = false),
        uiSettings = MapUiSettings(
            zoomControlsEnabled = useRichMapControls,
            compassEnabled = useRichMapControls,
            myLocationButtonEnabled = false
        )
    ) {
        territoryPreviewRings.forEach { ring ->
            if (ring.size >= 3) {
                Polygon(
                    points = ring.map { (lat, lon) -> LatLng(lat, lon) },
                    fillColor = Color(0x3800C853),
                    strokeColor = Color(0xFF00C853),
                    strokeWidth = 1f
                )
            }
        }
        Polyline(
            points = latLngs,
            color = Color(0xE02196F3),
            width = 12f
        )
    }
}

private fun fractionAlongRouteForNearestVertex(
    routePoints: List<Pair<Double, Double>>,
    tap: LatLng
): Double {
    if (routePoints.size < 2) return 0.0
    val res = FloatArray(1)
    var bestI = 0
    var bestD = Float.MAX_VALUE
    for (i in routePoints.indices) {
        val p = routePoints[i]
        Location.distanceBetween(p.first, p.second, tap.latitude, tap.longitude, res)
        if (res[0] < bestD) {
            bestD = res[0]
            bestI = i
        }
    }
    var total = 0.0
    var cum = 0.0
    for (k in 1 until routePoints.size) {
        val a = routePoints[k - 1]
        val b = routePoints[k]
        Location.distanceBetween(a.first, a.second, b.first, b.second, res)
        val seg = res[0].toDouble()
        if (k <= bestI) cum += seg
        total += seg
    }
    if (total <= 0.0) {
        return (bestI.toDouble() / (routePoints.size - 1).coerceAtLeast(1)).coerceIn(0.0, 1.0)
    }
    return (cum / total).coerceIn(0.0, 1.0)
}

/**
 * Mapa compacto: toque → fracción 0…1 por longitud acumulada hasta el vértice más cercano (paridad iOS / PostGIS).
 */
@Composable
fun CardioRouteSegmentTapMap(
    routePoints: List<Pair<Double, Double>>,
    onPickFraction: (Double) -> Unit,
    modifier: Modifier = Modifier,
    mapHeightDp: Int = 200
) {
    if (routePoints.size < 2) return
    if (BuildConfig.MAPS_API_KEY.isBlank()) {
        var showFullscreen by remember { mutableStateOf(false) }
        Column(modifier = modifier.fillMaxWidth()) {
            Box(modifier = Modifier.fillMaxWidth()) {
                CardioRoutePolylinePreview(
                    routePoints,
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(mapHeightDp.dp)
                )
                TextButton(
                    onClick = { showFullscreen = true },
                    modifier = Modifier
                        .align(Alignment.TopEnd)
                        .padding(4.dp)
                ) {
                    Text(stringResource(R.string.cardio_map_expand))
                }
            }
        }
        CardioRouteFullscreenMapDialog(
            visible = showFullscreen,
            onDismiss = { showFullscreen = false },
            routePoints = routePoints,
            showOpenInGoogleMaps = true
        )
        return
    }
    val latLngs = CardioRouteGeoJson.toLatLngList(routePoints)
    val camera = rememberCameraPositionState()
    LaunchedEffect(routePoints) {
        val b = CardioRouteGeoJson.latLngBoundsForRoute(routePoints) ?: return@LaunchedEffect
        runCatching { camera.move(CameraUpdateFactory.newLatLngBounds(b, 64)) }
    }
    var showFullscreen by remember { mutableStateOf(false) }
    Column(modifier = modifier.fillMaxWidth()) {
        Box(modifier = Modifier.fillMaxWidth()) {
            GoogleMap(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(mapHeightDp.dp)
                    .clip(RoundedCornerShape(16.dp)),
                cameraPositionState = camera,
                properties = MapProperties(isMyLocationEnabled = false),
                uiSettings = MapUiSettings(zoomControlsEnabled = false, compassEnabled = false),
                onMapClick = { latLng ->
                    onPickFraction(fractionAlongRouteForNearestVertex(routePoints, latLng))
                }
            ) {
                Polyline(
                    points = latLngs,
                    color = Color(0xE02196F3),
                    width = 12f
                )
            }
            TextButton(
                onClick = { showFullscreen = true },
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .padding(4.dp)
            ) {
                Text(stringResource(R.string.cardio_map_expand))
            }
        }
    }
    CardioRouteFullscreenMapDialog(
        visible = showFullscreen,
        onDismiss = { showFullscreen = false },
        routePoints = routePoints,
        showOpenInGoogleMaps = true
    )
}

/**
 * Mapa de ruta a pantalla completa con cierre y opción de abrir en Google Maps.
 */
@Composable
fun CardioRouteFullscreenMapDialog(
    visible: Boolean,
    onDismiss: () -> Unit,
    routePoints: List<Pair<Double, Double>>,
    showOpenInGoogleMaps: Boolean = false
) {
    if (!visible || routePoints.size < 2) return
    val ctx = LocalContext.current
    Dialog(
        onDismissRequest = onDismiss,
        properties = DialogProperties(
            usePlatformDefaultWidth = false,
            decorFitsSystemWindows = false
        )
    ) {
        Surface(
            modifier = Modifier.fillMaxSize(),
            color = MaterialTheme.colorScheme.surface
        ) {
            Column(Modifier.fillMaxSize()) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 4.dp, vertical = 4.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    TextButton(onClick = onDismiss) {
                        Text(stringResource(R.string.cardio_map_close))
                    }
                    Spacer(Modifier.weight(1f))
                }
                CardioRouteMapBox(
                    routePoints = routePoints,
                    modifier = Modifier
                        .weight(1f)
                        .fillMaxWidth(),
                    expandToFill = true,
                    useRichMapControls = true
                )
                if (showOpenInGoogleMaps) {
                    TextButton(
                        onClick = {
                            startGoogleMapsForRoute(ctx, routePoints)
                            onDismiss()
                        },
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text(stringResource(R.string.home_detail_open_route_maps))
                    }
                }
            }
        }
    }
}

@Composable
fun CardioRouteMapFromGeoJson(
    routeGeojson: String?,
    modifier: Modifier = Modifier,
    mapHeightDp: Int = 220
) {
    val pts = remember(routeGeojson) { CardioRouteGeoJson.parseLineStringLatLng(routeGeojson) }
    if (pts.size < 2) return
    val ctx = LocalContext.current
    var showFullscreen by remember { mutableStateOf(false) }
    Column(modifier = modifier.fillMaxWidth()) {
        Box(modifier = Modifier.fillMaxWidth()) {
            CardioRouteMapBox(pts, modifier = Modifier.fillMaxWidth(), mapHeightDp = mapHeightDp)
            TextButton(
                onClick = { showFullscreen = true },
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .padding(4.dp)
            ) {
                Text(stringResource(R.string.cardio_map_expand))
            }
        }
        TextButton(
            onClick = { startGoogleMapsForRoute(ctx, pts) },
            modifier = Modifier.fillMaxWidth()
        ) {
            Text(stringResource(R.string.home_detail_open_route_maps))
        }
    }
    CardioRouteFullscreenMapDialog(
        visible = showFullscreen,
        onDismiss = { showFullscreen = false },
        routePoints = pts,
        showOpenInGoogleMaps = true
    )
}
