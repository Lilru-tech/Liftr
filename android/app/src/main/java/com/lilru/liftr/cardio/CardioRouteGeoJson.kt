package com.lilru.liftr.cardio

import com.google.android.gms.maps.model.LatLng
import com.google.android.gms.maps.model.LatLngBounds
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/**
 * Paridad con [Liftr/WorkoutDetailView.swift] `CardioRouteGeoJSONParser` (LineString GeoJSON en BD).
 * Devuelve pares (lat, lon) para [com.google.android.gms.maps.model.LatLng].
 */
object CardioRouteGeoJson {
    private val json = Json { ignoreUnknownKeys = true }

    @Serializable
    private data class LineStringBody(
        val type: String,
        val coordinates: List<List<Double>> = emptyList()
    )

    fun parseLineStringLatLng(geojson: String?): List<Pair<Double, Double>> {
        val raw = geojson?.trim().orEmpty()
        if (raw.isEmpty()) return emptyList()
        return runCatching {
            val obj = json.decodeFromString(LineStringBody.serializer(), raw)
            if (obj.type.lowercase() != "linestring" || obj.coordinates.size < 2) return emptyList()
            obj.coordinates.mapNotNull { pair ->
                if (pair.size < 2) return@mapNotNull null
                val lon = pair[0]
                val lat = pair[1]
                if (lat !in -90.0..90.0 || lon !in -180.0..180.0) return@mapNotNull null
                lat to lon
            }
        }.getOrDefault(emptyList())
    }

    fun toLatLngList(points: List<Pair<Double, Double>>): List<LatLng> =
        points.map { (lat, lon) -> LatLng(lat, lon) }

    fun latLngBoundsForRoute(points: List<Pair<Double, Double>>): LatLngBounds? {
        if (points.size < 2) return null
        var minLat = points[0].first
        var maxLat = minLat
        var minLon = points[0].second
        var maxLon = minLon
        for (p in points) {
            minLat = minOf(minLat, p.first)
            maxLat = maxOf(maxLat, p.first)
            minLon = minOf(minLon, p.second)
            maxLon = maxOf(maxLon, p.second)
        }
        val padLat = maxOf(0.002, (maxLat - minLat) * 0.25)
        val padLon = maxOf(0.002, (maxLon - minLon) * 0.25)
        return LatLngBounds(
            LatLng(minLat - padLat, minLon - padLon),
            LatLng(maxLat + padLat, maxLon + padLon)
        )
    }
}
