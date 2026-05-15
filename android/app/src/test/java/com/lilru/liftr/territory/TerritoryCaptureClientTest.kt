package com.lilru.liftr.territory

import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Test

class TerritoryCaptureClientTest {
    @Test
    fun captureMessageWhenCellsTaken() {
        val summary = TerritoryCaptureSummaryWire(
            ok = true,
            routeKind = "open",
            cellsGained = 12,
            cellsTaken = 4
        )
        assertEquals(
            "Captured 12 map cells, taking 4 from others.",
            TerritoryCaptureClient.captureMessage(summary)
        )
    }

    @Test
    fun workoutDetailLabelWhenCellsTaken() {
        assertEquals(
            "12 cells (4 from others)",
            TerritoryCaptureClient.workoutDetailLabel(12, 4)
        )
    }

    @Test
    fun workoutDetailLabelWhenOnlyGained() {
        assertEquals(
            "8 cells",
            TerritoryCaptureClient.workoutDetailLabel(8, 0)
        )
    }

    @Test
    fun takeoverRowSubtitleFormatsCellsAndShare() {
        assertEquals(
            "120 cells · 12.5%",
            TerritoryCaptureClient.takeoverRowSubtitle(120, 12.5)
        )
        assertEquals(
            "8 cells · 4%",
            TerritoryCaptureClient.takeoverRowSubtitle(8, 4.0)
        )
    }

    @Test
    fun workoutTakeoverRowDecodes() {
        val decoded = Json { ignoreUnknownKeys = true }.decodeFromString<List<TerritoryWorkoutTakeoverRowWire>>(
            """
            [{"victim_user_id":"22222222-2222-2222-2222-222222222222","victim_username":"runner","victim_avatar_url":"https://example.com/a.jpg","cells_taken":120,"share_taken_pct":12.5}]
            """.trimIndent()
        )
        assertEquals(1, decoded.size)
        assertEquals("22222222-2222-2222-2222-222222222222", decoded[0].victimUserId)
        assertEquals("runner", decoded[0].victimUsername)
        assertEquals(120, decoded[0].cellsTaken)
        assertEquals(12.5, decoded[0].shareTakenPct)
    }

    @Test
    fun historicalBackfillDoneOnlyWhenQueueEmpty() {
        assertEquals(true, TerritoryCaptureClient.shouldMarkHistoricalBackfillDone(false))
        assertEquals(false, TerritoryCaptureClient.shouldMarkHistoricalBackfillDone(true))
    }

    @Test
    fun backfillResponseDecodes() {
        val decoded = Json { ignoreUnknownKeys = true }.decodeFromString<TerritoryBackfillResponseWire>(
            """{"ok":true,"processed":3,"cells_gained":42,"cells_taken":1,"has_more":false}"""
        )
        assertEquals(true, decoded.ok)
        assertEquals(3, decoded.processed)
        assertEquals(false, decoded.hasMore)
    }

    @Test
    fun territoryShareLeaderboardDecodes() {
        val decoded = Json { ignoreUnknownKeys = true }.decodeFromString<List<TerritoryShareLeaderRowWire>>(
            """[{"rank":1,"user_id":"11111111-1111-1111-1111-111111111111","username":"runner","owned_cells":12,"territory_share_pct":4.25}]"""
        )
        assertEquals(1, decoded.size)
        assertEquals("runner", decoded[0].username)
        assertEquals(4.25, decoded[0].territorySharePct ?: 0.0, 0.001)
    }

    @Test
    fun profileTerritorySummaryLineOwnProfileWithActivity() {
        assertEquals(
            "You own 218 cells · 208 new cells (in 2 workouts) in the last 7 days",
            TerritoryCaptureClient.profileTerritorySummaryLine(
                totalCells = 218,
                cellsGained7d = 208,
                workouts7d = 2,
                isOwnProfile = true
            )
        )
    }

    @Test
    fun profileTerritorySummaryLineOtherProfileWithActivity() {
        assertEquals(
            "Owns 218 cells · 208 new cells (in 2 workouts) in the last 7 days",
            TerritoryCaptureClient.profileTerritorySummaryLine(
                totalCells = 218,
                cellsGained7d = 208,
                workouts7d = 2,
                isOwnProfile = false
            )
        )
    }

    @Test
    fun profileTerritorySummaryLineSingularWorkout() {
        assertEquals(
            "You own 50 cells · 12 new cells (in 1 workout) in the last 7 days",
            TerritoryCaptureClient.profileTerritorySummaryLine(
                totalCells = 50,
                cellsGained7d = 12,
                workouts7d = 1,
                isOwnProfile = true
            )
        )
    }

    @Test
    fun profileTerritorySummaryLineOmits7dWhenZero() {
        assertEquals(
            "You own 218 cells",
            TerritoryCaptureClient.profileTerritorySummaryLine(
                totalCells = 218,
                cellsGained7d = 0,
                workouts7d = 0,
                isOwnProfile = true
            )
        )
    }

    @Test
    fun mapTerritory7dLineFormatsCellsAndWorkouts() {
        assertEquals(
            "7d: 208 new cells (2 workouts)",
            TerritoryCaptureClient.mapTerritory7dLine(cellsGained7d = 208, workouts7d = 2)
        )
    }

    @Test
    fun mapTerritory7dLineSingular() {
        assertEquals(
            "7d: 1 new cell (1 workout)",
            TerritoryCaptureClient.mapTerritory7dLine(cellsGained7d = 1, workouts7d = 1)
        )
    }

    @Test
    fun mapTerritory7dLineNullWhenZero() {
        assertEquals(null, TerritoryCaptureClient.mapTerritory7dLine(cellsGained7d = 0, workouts7d = 0))
    }

    @Test
    fun territorySummaryWireDecodes7dBreakdown() {
        val decoded = Json { ignoreUnknownKeys = true }.decodeFromString<TerritorySummaryWire>(
            """{"total_cells":218,"cells_gained_last_7d":208,"capture_workouts_last_7d":2,"cells_last_7d":2}"""
        )
        assertEquals(218, decoded.totalCells)
        assertEquals(208, decoded.cellsGainedLast7d)
        assertEquals(2, decoded.captureWorkoutsLast7d)
    }

    @Test
    fun profileCitySummaryLabelShowsOwnedCellsWithValidTotal() {
        val city = TerritoryCityRegionRowWire(
            cityKey = "osm:relation:12345",
            displayName = "Tarragona",
            capturedCells = 2754,
            totalCaptureCells = 65309,
            myOwnedCells = 45
        )
        assertEquals(
            "Tarragona · you own 45 of 65309 cells",
            TerritoryCaptureClient.profileCitySummaryLabel(city)
        )
    }

    @Test
    fun profileCitySummaryLabelOmitsBadTotal() {
        val city = TerritoryCityRegionRowWire(
            cityKey = "osm:relation:12345",
            displayName = "Tarragona",
            capturedCells = 2754,
            totalCaptureCells = 2,
            myOwnedCells = 45
        )
        assertEquals(
            "Tarragona · you own 45 cells",
            TerritoryCaptureClient.profileCitySummaryLabel(city)
        )
    }

    @Test
    fun citySummaryLabelIncludesMunicipalityTotals() {
        val city = TerritoryCityRegionRowWire(
            cityKey = "osm:relation:12345",
            displayName = "Tarragona",
            centerLat = 41.12,
            centerLon = 1.24,
            capturedCells = 571,
            totalCaptureCells = 65309
        )
        assertEquals("Tarragona · 571 / 65309 cells", TerritoryCaptureClient.citySummaryLabel(city))
    }

    @Test
    fun nearestCityKeyPrefersClosestRegion() {
        val cities = listOf(
            TerritoryCityRegionRowWire(
                cityKey = "far",
                displayName = "Far",
                centerLat = 40.0,
                centerLon = 0.0,
                capturedCells = 1,
                totalCaptureCells = 10
            ),
            TerritoryCityRegionRowWire(
                cityKey = "near",
                displayName = "Near",
                centerLat = 41.1189,
                centerLon = 1.2445,
                capturedCells = 2,
                totalCaptureCells = 20
            )
        )
        assertEquals(
            "near",
            TerritoryCaptureClient.nearestCityKey(41.12, 1.24, cities)
        )
    }

    @Test
    fun preferredCityKeyPrefersOwnedCities() {
        val cities = listOf(
            TerritoryCityRegionRowWire(
                cityKey = "global",
                displayName = "Global",
                centerLat = 40.0,
                centerLon = 0.0,
                capturedCells = 100,
                totalCaptureCells = 1000,
                myOwnedCells = 0
            ),
            TerritoryCityRegionRowWire(
                cityKey = "mine",
                displayName = "Mine",
                centerLat = 41.1189,
                centerLon = 1.2445,
                capturedCells = 2,
                totalCaptureCells = 20,
                myOwnedCells = 2
            )
        )
        assertEquals(
            "mine",
            TerritoryCaptureClient.preferredCityKey(41.12, 1.24, cities)
        )
    }

    @Test
    fun captureFailureMessageForMissingRoute() {
        assertEquals(
            "Territory capture needs a GPS route on this workout.",
            TerritoryCaptureClient.captureFailureMessage("missing_route")
        )
    }

    @Test
    fun territoryCityRegionsDecode() {
        val decoded = Json { ignoreUnknownKeys = true }.decodeFromString<List<TerritoryCityRegionRowWire>>(
            """[{"city_key":"osm:relation:12345","display_name":"Tarragona","center_lat":41.12,"center_lon":1.24,"captured_cells":363,"total_capture_cells":12480,"my_owned_cells":363}]"""
        )
        assertEquals(1, decoded.size)
        assertEquals("osm:relation:12345", decoded[0].cityKey)
        assertEquals("Tarragona", decoded[0].displayName)
        assertEquals(363, decoded[0].capturedCells)
        assertEquals(12480, decoded[0].totalCaptureCells)
        assertEquals(363, decoded[0].myOwnedCells)
    }

    @Test
    fun pendingTerritoryCityRegionsDecode() {
        val decoded = Json { ignoreUnknownKeys = true }.decodeFromString<List<TerritoryCityRegionRowWire>>(
            """[{"city_key":"pending:41.55:2.12","display_name":"Resolving area · 41.55, 2.12","center_lat":41.55,"center_lon":2.12,"captured_cells":105,"my_owned_cells":105}]"""
        )
        assertEquals(1, decoded.size)
        assertEquals("pending:41.55:2.12", decoded[0].cityKey)
        assertEquals(
            "Resolving area · 41.55, 2.12 · 105 cells",
            TerritoryCaptureClient.citySummaryLabel(decoded[0])
        )
    }

    @Test
    fun pendingTerritoryCityKeyDetection() {
        assert(TerritoryCaptureClient.isPendingTerritoryCityKey("pending:41.55:2.12"))
        assert(!TerritoryCaptureClient.isPendingTerritoryCityKey("osm:relation:12345"))
        assert(!TerritoryCaptureClient.isPendingTerritoryCityKey(null))
    }

    @Test
    fun filterTerritoryCitiesMatchesDisplayName() {
        val cities = listOf(
            TerritoryCityRegionRowWire(
                cityKey = "osm:relation:1",
                displayName = "Tarragona",
                centerLat = 41.12,
                centerLon = 1.24,
                capturedCells = 10,
                totalCaptureCells = 100,
                myOwnedCells = 5
            ),
            TerritoryCityRegionRowWire(
                cityKey = "osm:relation:2",
                displayName = "Sabadell",
                centerLat = 41.55,
                centerLon = 2.11,
                capturedCells = 8,
                totalCaptureCells = 80,
                myOwnedCells = 0
            )
        )
        val filtered = TerritoryCaptureClient.filterTerritoryCities(cities, "saba")
        assertEquals(1, filtered.size)
        assertEquals("osm:relation:2", filtered.first().cityKey)
    }

    @Test
    fun pendingResolveCoordinatesPreferBucketKey() {
        val city = Json { ignoreUnknownKeys = true }.decodeFromString<TerritoryCityRegionRowWire>(
            """{"city_key":"pending:36.28:-6.10","display_name":"Resolving area · 36.28, -6.10","center_lat":36.2800834012035,"center_lon":-6.09945049492908,"captured_cells":99,"my_owned_cells":99}"""
        )
        val coordinates = TerritoryCaptureClient.pendingResolveCoordinates(city)
        assertEquals(36.28, coordinates?.first)
        assertEquals(-6.10, coordinates?.second)
        val bucket = TerritoryCaptureClient.pendingBucketCoordinates(city)
        assertEquals(36.28, bucket?.first)
        assertEquals(-6.10, bucket?.second)
    }

    @Test
    fun ownerColorsDifferForDistinctOwners() {
        val first = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
        val second = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
        assert(TerritoryOwnerColors.color(first) != TerritoryOwnerColors.color(second))
    }

    @Test
    fun ownerColorIsStable() {
        val ownerId = "22222222-2222-2222-2222-222222222222"
        assertEquals(
            TerritoryOwnerColors.color(ownerId),
            TerritoryOwnerColors.color(ownerId)
        )
    }

    @Test
    fun polygonSelectionPicksCell() {
        val ring = listOf(
            40.41 to -3.7,
            40.41 to -3.69,
            40.42 to -3.69,
            40.41 to -3.7
        )
        val selected = TerritoryMapGeometry.selectedCell(
            lat = 40.415,
            lon = -3.695,
            cells = listOf(
                TerritoryMapCellWire(
                    cellId = "1:1",
                    ownerUserId = "33333333-3333-3333-3333-333333333333",
                    ownerUsername = "runner",
                    cellGeojson = TerritoryGeoJsonPolygonWire(
                        type = "Polygon",
                        coordinates = listOf(ring.map { listOf(it.second, it.first) })
                    )
                )
            )
        )
        assertEquals("1:1", selected?.cellId)
    }
}
