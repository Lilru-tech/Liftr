package com.lilru.liftr.territory

import kotlin.math.abs

object TerritoryMapGeometry {
    fun polygonContains(lat: Double, lon: Double, ring: List<Pair<Double, Double>>): Boolean {
        if (ring.size < 3) return false
        var inside = false
        var j = ring.lastIndex
        for (i in ring.indices) {
            val yi = ring[i].first
            val xi = ring[i].second
            val yj = ring[j].first
            val xj = ring[j].second
            val intersects = (yi > lat) != (yj > lat) &&
                lon < (xj - xi) * (lat - yi) / (yj - yi + 1e-12) + xi
            if (intersects) inside = !inside
            j = i
        }
        return inside
    }

    private fun polygonArea(ring: List<Pair<Double, Double>>): Double {
        if (ring.size < 3) return Double.MAX_VALUE
        var area = 0.0
        var j = ring.lastIndex
        for (i in ring.indices) {
            area += (ring[j].second + ring[i].second) * (ring[j].first - ring[i].first)
            j = i
        }
        return abs(area) * 0.5
    }

    fun selectedCell(lat: Double, lon: Double, cells: List<TerritoryMapCellWire>): TerritoryMapCellWire? {
        val matches = cells.filter { cell ->
            val ring = cell.cellGeojson?.ringLatLng().orEmpty()
            ring.size >= 3 && polygonContains(lat, lon, ring)
        }
        if (matches.isEmpty()) return null
        return matches.sortedWith(
            compareByDescending<TerritoryMapCellWire> { it.capturedAt.orEmpty() }
                .thenBy { polygonArea(it.cellGeojson?.ringLatLng().orEmpty()) }
        ).first()
    }
}
