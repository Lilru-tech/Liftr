package com.lilru.liftr.ui.map

import android.content.Context
import android.content.Intent
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
import com.google.maps.android.compose.GoogleMap
import com.google.maps.android.compose.MapProperties
import com.google.maps.android.compose.MapUiSettings
import com.google.maps.android.compose.Polyline
import com.google.maps.android.compose.rememberCameraPositionState
import com.lilru.liftr.BuildConfig
import com.lilru.liftr.R
import com.lilru.liftr.cardio.CardioRouteGeoJson

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
fun CardioRouteMapBox(
    /** Pares (lat, lon), al menos 2 para dibujar. */
    routePoints: List<Pair<Double, Double>>,
    modifier: Modifier = Modifier,
    mapHeightDp: Int = 220,
    expandToFill: Boolean = false,
    useRichMapControls: Boolean = false
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
        Polyline(
            points = latLngs,
            color = Color(0xE02196F3),
            width = 12f
        )
    }
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
