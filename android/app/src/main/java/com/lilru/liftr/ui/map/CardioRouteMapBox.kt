package com.lilru.liftr.ui.map

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
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
    mapHeightDp: Int = 220
) {
    if (routePoints.size < 2) return
    val bg = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.72f)
    val lineColor = Color(0xE02196F3)
    Canvas(
        modifier = modifier
            .fillMaxWidth()
            .height(mapHeightDp.dp)
            .clip(RoundedCornerShape(16.dp))
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
    mapHeightDp: Int = 220
) {
    if (routePoints.size < 2) return
    if (BuildConfig.MAPS_API_KEY.isBlank()) {
        CardioRoutePolylinePreview(routePoints, modifier = modifier, mapHeightDp = mapHeightDp)
        return
    }

    val latLngs = CardioRouteGeoJson.toLatLngList(routePoints)
    val camera = rememberCameraPositionState()
    LaunchedEffect(routePoints) {
        val b = CardioRouteGeoJson.latLngBoundsForRoute(routePoints) ?: return@LaunchedEffect
        runCatching {
            camera.move(CameraUpdateFactory.newLatLngBounds(b, 64))
        }
    }
    GoogleMap(
        modifier = modifier
            .fillMaxWidth()
            .height(mapHeightDp.dp)
            .clip(RoundedCornerShape(16.dp)),
        cameraPositionState = camera,
        properties = MapProperties(isMyLocationEnabled = false),
        uiSettings = MapUiSettings(
            zoomControlsEnabled = false,
            compassEnabled = false,
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

@Composable
fun CardioRouteMapFromGeoJson(
    routeGeojson: String?,
    modifier: Modifier = Modifier,
    mapHeightDp: Int = 220
) {
    val pts = remember(routeGeojson) { CardioRouteGeoJson.parseLineStringLatLng(routeGeojson) }
    if (pts.size < 2) return
    val ctx = LocalContext.current
    Column(modifier = modifier.fillMaxWidth()) {
        CardioRouteMapBox(pts, modifier = Modifier.fillMaxWidth(), mapHeightDp = mapHeightDp)
        TextButton(
            onClick = { startGoogleMapsForRoute(ctx, pts) },
            modifier = Modifier.fillMaxWidth()
        ) {
            Text(stringResource(R.string.home_detail_open_route_maps))
        }
    }
}
