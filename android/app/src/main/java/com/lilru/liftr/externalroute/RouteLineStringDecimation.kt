package com.lilru.liftr.externalroute

data class LatLng(val latitude: Double, val longitude: Double)

object RouteLineStringDecimation {
    const val MAX_STORED_COORDINATES = 2000

    fun decimate(coords: List<LatLng>): List<LatLng> {
        if (coords.size <= MAX_STORED_COORDINATES) return coords
        val maxPoints = MAX_STORED_COORDINATES
        val n = coords.size
        val denom = maxPoints - 1
        return buildList(maxPoints) {
            for (i in 0 until maxPoints) {
                val idx = (i * (n - 1)) / denom
                add(coords[idx])
            }
        }
    }

    fun encodeGeoJsonLineString(coords: List<LatLng>): String? {
        if (coords.size < 2) return null
        val parts = coords.joinToString(",") { "[${it.longitude},${it.latitude}]" }
        return """{"type":"LineString","coordinates":[$parts]}"""
    }
}
