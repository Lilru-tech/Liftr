import Foundation
import Testing
import CoreLocation
@testable import Liftr

struct TerritoryCaptureRegressionTests {
    @Test func captureMessageWhenCellsTaken() {
        let summary = TerritoryCaptureSummary(
            ok: true,
            route_kind: "open",
            cells_gained: 12,
            cells_taken: 4,
            bbox: nil,
            already_applied: false,
            reason: nil
        )
        #expect(TerritoryCapturePresentation.message(for: summary) == "Captured 12 map cells, taking 4 from others.")
    }

    @Test func captureMessageWhenOnlyGained() {
        let summary = TerritoryCaptureSummary(
            ok: true,
            route_kind: "closed",
            cells_gained: 8,
            cells_taken: 0,
            bbox: nil,
            already_applied: false,
            reason: nil
        )
        #expect(TerritoryCapturePresentation.message(for: summary) == "Captured 8 map cells.")
    }

    @Test func workoutDetailLabelWhenCellsTaken() {
        #expect(TerritoryCapturePresentation.workoutDetailLabel(gained: 12, taken: 4) == "12 cells (4 from others)")
    }

    @Test func workoutDetailLabelWhenOnlyGained() {
        #expect(TerritoryCapturePresentation.workoutDetailLabel(gained: 8, taken: 0) == "8 cells")
    }

    @Test func historicalBackfillDoneOnlyWhenQueueEmpty() {
        #expect(TerritoryCaptureClient.shouldMarkHistoricalBackfillDone(hasMore: false))
        #expect(!TerritoryCaptureClient.shouldMarkHistoricalBackfillDone(hasMore: true))
    }

    @Test func polygonRingParsesGeoJson() {
        let polygon = TerritoryGeoJSONPolygon(
            type: "Polygon",
            coordinates: [[[-3.7, 40.41], [-3.69, 40.41], [-3.69, 40.42], [-3.7, 40.41]]]
        )
        #expect(polygon.ring.count == 4)
        #expect(polygon.ring[0].latitude == 40.41)
        #expect(polygon.ring[0].longitude == -3.7)
    }

    @Test func backfillResponseDecodes() throws {
        let data = Data("""
        {"ok":true,"processed":3,"cells_gained":42,"cells_taken":1,"has_more":false}
        """.utf8)
        let decoded = try JSONDecoder().decode(TerritoryBackfillResponse.self, from: data)
        #expect(decoded.ok)
        #expect(decoded.processed == 3)
        #expect(decoded.has_more == false)
    }

    @Test func territoryShareLeaderboardDecodes() throws {
        let ownerId = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let data = Data("""
        [{"rank":1,"user_id":"11111111-1111-1111-1111-111111111111","username":"runner","avatar_url":null,"owned_cells":12,"territory_share_pct":4.25}]
        """.utf8)
        let decoded = try JSONDecoder().decode([TerritoryShareLeaderRow].self, from: data)
        #expect(decoded.count == 1)
        #expect(decoded[0].user_id == ownerId)
        #expect(decoded[0].territory_share_pct == 4.25)
    }

    @Test func citySummaryLabelIncludesMunicipalityTotals() {
        let city = TerritoryCityRegionRow(
            city_key: "osm:relation:12345",
            display_name: "Tarragona",
            center_lat: 41.12,
            center_lon: 1.24,
            captured_cells: 571,
            total_capture_cells: 65309,
            my_owned_cells: 363,
            owned_cells: 363
        )
        #expect(TerritoryCaptureClient.citySummaryLabel(for: city) == "Tarragona · 571 / 65309 cells")
    }

    @Test func nearestCityKeyPrefersClosestRegion() {
        let cities = [
            TerritoryCityRegionRow(
                city_key: "far",
                display_name: "Far",
                center_lat: 40.0,
                center_lon: 0.0,
                captured_cells: 1,
                total_capture_cells: 10,
                my_owned_cells: 0,
                owned_cells: 0
            ),
            TerritoryCityRegionRow(
                city_key: "near",
                display_name: "Near",
                center_lat: 41.1189,
                center_lon: 1.2445,
                captured_cells: 2,
                total_capture_cells: 20,
                my_owned_cells: 2,
                owned_cells: 2
            )
        ]
        #expect(
            TerritoryCaptureClient.nearestCityKey(to: 41.12, longitude: 1.24, from: cities) == "near"
        )
    }

    @Test func preferredCityKeyPrefersOwnedCities() {
        let cities = [
            TerritoryCityRegionRow(
                city_key: "global",
                display_name: "Global",
                center_lat: 40.0,
                center_lon: 0.0,
                captured_cells: 100,
                total_capture_cells: 1000,
                my_owned_cells: 0,
                owned_cells: 0
            ),
            TerritoryCityRegionRow(
                city_key: "mine",
                display_name: "Mine",
                center_lat: 41.1189,
                center_lon: 1.2445,
                captured_cells: 2,
                total_capture_cells: 20,
                my_owned_cells: 2,
                owned_cells: 2
            )
        ]
        #expect(
            TerritoryCaptureClient.preferredCityKey(
                latitude: 41.12,
                longitude: 1.24,
                from: cities
            ) == "mine"
        )
    }

    @Test func captureFailureMessageForMissingRoute() {
        #expect(
            TerritoryCapturePresentation.failureMessage(reason: "missing_route")
            == "Territory capture needs a GPS route on this workout."
        )
    }

    @Test func territoryCityRegionsDecode() throws {
        let data = Data("""
        [{"city_key":"osm:relation:12345","display_name":"Tarragona","center_lat":41.12,"center_lon":1.24,"captured_cells":363,"total_capture_cells":12480,"my_owned_cells":363}]
        """.utf8)
        let decoded = try JSONDecoder().decode([TerritoryCityRegionRow].self, from: data)
        #expect(decoded.count == 1)
        #expect(decoded[0].city_key == "osm:relation:12345")
        #expect(decoded[0].display_name == "Tarragona")
        #expect(decoded[0].captured_cells == 363)
        #expect(decoded[0].total_capture_cells == 12480)
        #expect(decoded[0].my_owned_cells == 363)
    }

    @Test func pendingTerritoryCityRegionsDecode() throws {
        let data = Data("""
        [{"city_key":"pending:41.55:2.12","display_name":"Resolving area · 41.55, 2.12","center_lat":41.55,"center_lon":2.12,"captured_cells":105,"my_owned_cells":105}]
        """.utf8)
        let decoded = try JSONDecoder().decode([TerritoryCityRegionRow].self, from: data)
        #expect(decoded.count == 1)
        #expect(decoded[0].city_key == "pending:41.55:2.12")
        #expect(TerritoryCaptureClient.citySummaryLabel(for: decoded[0]) == "Resolving area · 41.55, 2.12 · 105 cells")
    }

    @Test func pendingTerritoryCityKeyDetection() {
        #expect(TerritoryCaptureClient.isPendingTerritoryCityKey("pending:41.55:2.12"))
        #expect(!TerritoryCaptureClient.isPendingTerritoryCityKey("osm:relation:12345"))
        #expect(!TerritoryCaptureClient.isPendingTerritoryCityKey(nil))
    }

    @Test func filterTerritoryCitiesMatchesDisplayName() {
        let cities = [
            TerritoryCityRegionRow(
                city_key: "osm:relation:1",
                display_name: "Tarragona",
                center_lat: 41.12,
                center_lon: 1.24,
                captured_cells: 10,
                total_capture_cells: 100,
                my_owned_cells: 5,
                owned_cells: 5
            ),
            TerritoryCityRegionRow(
                city_key: "osm:relation:2",
                display_name: "Sabadell",
                center_lat: 41.55,
                center_lon: 2.11,
                captured_cells: 8,
                total_capture_cells: 80,
                my_owned_cells: 0,
                owned_cells: 0
            )
        ]
        let filtered = TerritoryCaptureClient.filterTerritoryCities(cities, query: "saba")
        #expect(filtered.count == 1)
        #expect(filtered.first?.city_key == "osm:relation:2")
    }

    @Test func selectedTerritoryCityPrefersOwnedPool() {
        let cities = [
            TerritoryCityRegionRow(
                city_key: "far",
                display_name: "Far",
                center_lat: 40.0,
                center_lon: 0.0,
                captured_cells: 1,
                total_capture_cells: 10,
                my_owned_cells: 0,
                owned_cells: 0
            ),
            TerritoryCityRegionRow(
                city_key: "mine",
                display_name: "Mine",
                center_lat: 41.12,
                center_lon: 1.24,
                captured_cells: 2,
                total_capture_cells: 20,
                my_owned_cells: 2,
                owned_cells: 2
            )
        ]
        let selected = TerritoryCaptureClient.selectedTerritoryCity(
            from: cities,
            preferredKey: nil,
            referenceLatitude: 41.12,
            referenceLongitude: 1.24
        )
        #expect(selected?.city_key == "mine")
    }

    @Test func pendingResolveCoordinatesPreferBucketKey() throws {
        let data = Data("""
        [{"city_key":"pending:36.28:-6.10","display_name":"Resolving area · 36.28, -6.10","center_lat":36.2800834012035,"center_lon":-6.09945049492908,"captured_cells":99,"my_owned_cells":99}]
        """.utf8)
        let decoded = try JSONDecoder().decode([TerritoryCityRegionRow].self, from: data)
        let coordinates = TerritoryCaptureClient.pendingResolveCoordinates(for: decoded[0])
        #expect(coordinates?.lat == 36.28)
        #expect(coordinates?.lon == -6.10)
        let bucket = TerritoryCaptureClient.pendingBucketCoordinates(for: decoded[0])
        #expect(bucket?.lat == 36.28)
        #expect(bucket?.lon == -6.10)
    }

    @Test func ownerColorsDifferForDistinctOwners() {
        let first = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
        let second = UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!
        #expect(TerritoryOwnerColors.color(for: first) != TerritoryOwnerColors.color(for: second))
    }

    @Test func ownerColorIsStable() {
        let ownerId = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        #expect(TerritoryOwnerColors.color(for: ownerId) == TerritoryOwnerColors.color(for: ownerId))
    }

    @Test func polygonSelectionPicksCell() {
        let ownerId = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let cell = TerritoryMapCellRow(
            cell_id: "1:1",
            cell_geojson: TerritoryGeoJSONPolygon(
                type: "Polygon",
                coordinates: [[[-3.7, 40.41], [-3.69, 40.41], [-3.69, 40.42], [-3.7, 40.41]]]
            ),
            owner_user_id: ownerId,
            owner_username: "runner",
            owner_avatar_url: nil,
            captured_at: nil,
            is_mine: false
        )
        let coordinate = CLLocationCoordinate2D(latitude: 40.415, longitude: -3.695)
        let selected = TerritoryMapGeometry.selectedCell(at: coordinate, in: [cell])
        #expect(selected?.cell_id == "1:1")
    }
}
