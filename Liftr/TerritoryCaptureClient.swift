import CoreLocation
import Foundation
import Supabase

struct TerritoryBBox: Decodable, Hashable {
    let min_lat: Double?
    let min_lon: Double?
    let max_lat: Double?
    let max_lon: Double?

    var centerCoordinate: CLLocationCoordinate2D? {
        guard
            let minLat = min_lat,
            let minLon = min_lon,
            let maxLat = max_lat,
            let maxLon = max_lon
        else { return nil }
        return CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2.0,
            longitude: (minLon + maxLon) / 2.0
        )
    }
}

struct TerritoryCaptureSummary: Decodable, Hashable {
    let ok: Bool
    let route_kind: String?
    let cells_gained: Int?
    let cells_taken: Int?
    let bbox: TerritoryBBox?
    let already_applied: Bool?
    let reason: String?
}

struct TerritoryPreviewCell: Decodable, Identifiable, Hashable {
    let cell_id: String
    let cell_geojson: TerritoryGeoJSONPolygon?
    var id: String { cell_id }
}

struct TerritoryPreviewResponse: Decodable {
    let ok: Bool
    let route_kind: String?
    let cells_count: Int?
    let cells: [TerritoryPreviewCell]?
    let bbox: TerritoryBBox?
    let reason: String?
}

struct TerritoryGeoJSONPolygon: Decodable, Hashable {
    let type: String?
    let coordinates: [[[Double]]]?

    var ring: [CLLocationCoordinate2D] {
        guard let ring = coordinates?.first else { return [] }
        return ring.compactMap { pair in
            guard pair.count >= 2 else { return nil }
            return CLLocationCoordinate2D(latitude: pair[1], longitude: pair[0])
        }
    }
}

struct TerritoryMapCellRow: Decodable, Identifiable, Hashable {
    let cell_id: String
    let cell_geojson: TerritoryGeoJSONPolygon?
    let owner_user_id: UUID?
    let owner_username: String?
    let owner_avatar_url: String?
    let captured_at: Date?
    let is_mine: Bool?
    var id: String { cell_id }

    var ring: [CLLocationCoordinate2D] { cell_geojson?.ring ?? [] }
}

struct TerritorySummaryResponse: Decodable {
    let total_cells: Int?
    let cells_last_7d: Int?
    let approx_area_m2: Double?
}

struct TerritoryShareLeaderRow: Decodable, Identifiable, Hashable {
    let rank: Int
    let user_id: UUID
    let username: String?
    let avatar_url: String?
    let owned_cells: Int?
    let territory_share_pct: Double?
    var id: UUID { user_id }
}

struct TerritoryCityRegionRow: Decodable, Identifiable, Hashable {
    let city_key: String?
    let display_name: String?
    let center_lat: Double?
    let center_lon: Double?
    let captured_cells: Int?
    let total_capture_cells: Int?
    let my_owned_cells: Int?
    let owned_cells: Int?
    var id: String { city_key ?? display_name ?? "city" }
}

struct TerritoryBackfillResponse: Decodable {
    let ok: Bool
    let processed: Int?
    let cells_gained: Int?
    let cells_taken: Int?
    let has_more: Bool?
}

struct TerritoryRecentTakeoverRow: Decodable, Identifiable, Hashable {
    let workout_id: Int64?
    let other_user_id: UUID?
    let other_username: String?
    let cells_taken: Int?
    let share_taken_pct: Double?
    let created_at: Date?
    var id: String { "\(workout_id ?? 0)-\(other_user_id?.uuidString ?? "user")" }
}

enum TerritoryCaptureClient {
    private struct WorkoutIdParams: Encodable {
        let p_workout_id: Int64
    }

    private struct RouteGeoJSONParams: Encodable {
        let p_route_geojson: String
    }

    private struct MapParams: Encodable {
        let p_min_lat: Double
        let p_min_lon: Double
        let p_max_lat: Double
        let p_max_lon: Double
        let p_limit: Int
    }

    private struct BackfillParams: Encodable {
        let p_limit: Int
    }

    private struct RecentTakeoversParams: Encodable {
        let p_user_id: UUID?
        let p_limit: Int
    }

    private struct UserTerritorySummaryParams: Encodable {
        let p_user_id: UUID
    }

    private struct UserTerritoryTopCitiesParams: Encodable {
        let p_user_id: UUID
        let p_limit: Int
    }

    private struct TerritoryCityShareLeaderboardParams: Encodable {
        let p_city_key: String
        let p_scope: String
        let p_limit: Int
    }

    static func applyCapture(workoutId: Int) async -> TerritoryCaptureSummary? {
        let params = WorkoutIdParams(p_workout_id: Int64(workoutId))
        do {
            let res = try await SupabaseManager.shared.client
                .rpc("apply_territory_capture_v1", params: params)
                .execute()
            return try JSONDecoder.supabase().decode(TerritoryCaptureSummary.self, from: res.data)
        } catch {
            await MainActor.run {
                AppState.shared.territoryCaptureToast = TerritoryCapturePresentation.failureMessage(for: error)
            }
            return nil
        }
    }

    static func previewCapture(routeGeoJSON: String) async -> TerritoryPreviewResponse? {
        let params = RouteGeoJSONParams(p_route_geojson: routeGeoJSON)
        do {
            let res = try await SupabaseManager.shared.client
                .rpc("preview_territory_capture_v1", params: params)
                .execute()
            let decoded = try JSONDecoder.supabase().decode(TerritoryPreviewResponse.self, from: res.data)
            if decoded.ok == false {
                await MainActor.run {
                    AppState.shared.territoryCaptureToast = TerritoryCapturePresentation.failureMessage(reason: decoded.reason)
                }
            }
            return decoded
        } catch {
            await MainActor.run {
                AppState.shared.territoryCaptureToast = TerritoryCapturePresentation.failureMessage(for: error)
            }
            return nil
        }
    }

    static func fetchRecentTakeovers(userId: UUID? = nil, limit: Int = 3) async -> [TerritoryRecentTakeoverRow] {
        let params = RecentTakeoversParams(p_user_id: userId, p_limit: limit)
        do {
            let res = try await SupabaseManager.shared.client
                .rpc("list_territory_recent_takeovers_v1", params: params)
                .execute()
            return try JSONDecoder.supabase().decode([TerritoryRecentTakeoverRow].self, from: res.data)
        } catch {
            return []
        }
    }

    static func fetchTerritorySummary(userId: UUID? = nil) async -> TerritorySummaryResponse? {
        do {
            if let userId {
                let params = UserTerritorySummaryParams(p_user_id: userId)
                let res = try await SupabaseManager.shared.client
                    .rpc("get_territory_summary_v1", params: params)
                    .execute()
                return try JSONDecoder.supabase().decode(TerritorySummaryResponse.self, from: res.data)
            }
            let res = try await SupabaseManager.shared.client
                .rpc("get_my_territory_summary_v1")
                .execute()
            return try JSONDecoder.supabase().decode(TerritorySummaryResponse.self, from: res.data)
        } catch {
            if userId == nil {
                await MainActor.run {
                    AppState.shared.territoryCaptureToast = TerritoryCapturePresentation.failureMessage(for: error)
                }
            }
            return nil
        }
    }

    static func fetchUserTerritoryTopCities(userId: UUID, limit: Int = 3) async -> [TerritoryCityRegionRow] {
        let params = UserTerritoryTopCitiesParams(p_user_id: userId, p_limit: limit)
        do {
            let res = try await SupabaseManager.shared.client
                .rpc("list_user_territory_top_cities_v1", params: params)
                .execute()
            let rows = try JSONDecoder.supabase().decode([TerritoryCityRegionRow].self, from: res.data)
            return rows.map { row in
                TerritoryCityRegionRow(
                    city_key: row.city_key,
                    display_name: row.display_name,
                    center_lat: row.center_lat,
                    center_lon: row.center_lon,
                    captured_cells: row.captured_cells,
                    total_capture_cells: row.total_capture_cells,
                    my_owned_cells: row.my_owned_cells ?? row.owned_cells,
                    owned_cells: row.owned_cells
                )
            }
        } catch {
            return []
        }
    }

    static func fetchMySummary() async -> TerritorySummaryResponse? {
        await fetchTerritorySummary(userId: nil)
    }

    static func storeCaptureReferenceCoordinate(from summary: TerritoryCaptureSummary) {
        guard summary.ok, let bbox = summary.bbox else { return }
        guard
            let minLat = bbox.min_lat,
            let minLon = bbox.min_lon,
            let maxLat = bbox.max_lat,
            let maxLon = bbox.max_lon
        else { return }
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2.0,
            longitude: (minLon + maxLon) / 2.0
        )
        Task { @MainActor in
            AppState.shared.territoryReferenceCoordinate = center
        }
    }

    static func fetchMapCells(
        minLat: Double,
        minLon: Double,
        maxLat: Double,
        maxLon: Double,
        limit: Int = 500
    ) async -> [TerritoryMapCellRow] {
        let params = MapParams(
            p_min_lat: minLat,
            p_min_lon: minLon,
            p_max_lat: maxLat,
            p_max_lon: maxLon,
            p_limit: limit
        )
        do {
            let res = try await SupabaseManager.shared.client
                .rpc("get_territory_map_v1", params: params)
                .execute()
            return try JSONDecoder.supabase().decode([TerritoryMapCellRow].self, from: res.data)
        } catch {
            await MainActor.run {
                AppState.shared.territoryCaptureToast = TerritoryCapturePresentation.failureMessage(for: error)
            }
            return []
        }
    }

    static func fetchTerritoryCityRegions() async -> [TerritoryCityRegionRow] {
        do {
            let res = try await SupabaseManager.shared.client
                .rpc("list_territory_city_regions_v1")
                .execute()
            return try JSONDecoder.supabase().decode([TerritoryCityRegionRow].self, from: res.data)
        } catch {
            return []
        }
    }

    static func fetchTerritoryCityShareLeaderboard(
        cityKey: String,
        scope: String = "global",
        limit: Int = 100
    ) async -> [TerritoryShareLeaderRow] {
        let params = TerritoryCityShareLeaderboardParams(
            p_city_key: cityKey,
            p_scope: scope,
            p_limit: limit
        )
        do {
            let res = try await SupabaseManager.shared.client
                .rpc("get_territory_city_share_leaderboard_v1", params: params)
                .execute()
            return try JSONDecoder.supabase().decode([TerritoryShareLeaderRow].self, from: res.data)
        } catch {
            return []
        }
    }

    static func nearestCityKey(
        to latitude: Double,
        longitude: Double,
        from cities: [TerritoryCityRegionRow]
    ) -> String? {
        guard !cities.isEmpty else { return nil }
        return cities.min { lhs, rhs in
            let lhsDistance = cityDistanceSquared(lhs, latitude: latitude, longitude: longitude)
            let rhsDistance = cityDistanceSquared(rhs, latitude: latitude, longitude: longitude)
            return lhsDistance < rhsDistance
        }?.city_key
    }

    private static func cityDistanceSquared(
        _ city: TerritoryCityRegionRow,
        latitude: Double,
        longitude: Double
    ) -> Double {
        let lat = city.center_lat ?? 0
        let lon = city.center_lon ?? 0
        let dLat = lat - latitude
        let dLon = lon - longitude
        return dLat * dLat + dLon * dLon
    }

    static func fetchTerritoryShareLeaderboard(scope: String = "global", limit: Int = 100) async -> [TerritoryShareLeaderRow] {
        let cities = await fetchTerritoryCityRegions()
        guard let cityKey = cities.first?.city_key, !cityKey.isEmpty else { return [] }
        return await fetchTerritoryCityShareLeaderboard(cityKey: cityKey, scope: scope, limit: limit)
    }

    static func preferredCityKey(
        latitude: Double?,
        longitude: Double?,
        from cities: [TerritoryCityRegionRow]
    ) -> String? {
        let owned = cities.filter { ($0.my_owned_cells ?? 0) > 0 }
        let pool = owned.isEmpty ? cities : owned
        guard !pool.isEmpty else { return nil }
        guard let latitude, let longitude else {
            return pool.first?.city_key
        }
        return nearestCityKey(to: latitude, longitude: longitude, from: pool)
    }

    static func backfillHistoricalCaptures(batchSize: Int = 5, maxBatches: Int = 8) async {
        if UserDefaults.standard.bool(forKey: "territoryHistoricalBackfillDone") {
            refreshTerritoryMunicipalitiesInBackground()
            return
        }
        let params = BackfillParams(p_limit: batchSize)
        var processedAny = false
        for _ in 0..<maxBatches {
            do {
                let res = try await SupabaseManager.shared.client
                    .rpc("backfill_my_territory_captures_v1", params: params)
                    .execute()
                let batch = try JSONDecoder.supabase().decode(TerritoryBackfillResponse.self, from: res.data)
                guard batch.ok else { break }
                let processed = batch.processed ?? 0
                if processed == 0 { break }
                processedAny = processedAny || processed > 0
                if batch.has_more != true { break }
            } catch {
                break
            }
        }
        if processedAny {
            UserDefaults.standard.set(true, forKey: "territoryHistoricalBackfillDone")
        }
        refreshTerritoryMunicipalitiesInBackground()
    }

    static func refreshTerritoryMunicipalitiesInBackground(limit: Int = 1) {
        Task.detached(priority: .utility) {
            await invokeTerritoryMunicipalityResolve(limit: limit, timeoutSeconds: 8)
        }
    }

    private static func invokeTerritoryMunicipalityResolve(limit: Int, timeoutSeconds: UInt64) async {
        struct Payload: Encodable {
            let limit: Int
            let max_items: Int
            let process_queue: Bool
            let run_assignment_backfill: Bool
        }
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                do {
                    _ = try await SupabaseManager.shared.client.functions
                        .invoke(
                            "resolve-territory-municipality",
                            options: .init(
                                body: Payload(
                                    limit: limit,
                                    max_items: limit,
                                    process_queue: true,
                                    run_assignment_backfill: false
                                )
                            )
                        )
                } catch {
                }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: timeoutSeconds * 1_000_000_000)
            }
            _ = await group.next()
            group.cancelAll()
        }
    }

    static func citySummaryLabel(for city: TerritoryCityRegionRow) -> String {
        let name = city.display_name ?? city.city_key ?? "City"
        let captured = city.captured_cells ?? 0
        if let total = city.total_capture_cells, total > 0 {
            return "\(name) · \(captured) / \(total) cells"
        }
        return "\(name) · \(captured) cells"
    }
}

enum TerritoryCapturePresentation {
    static func message(for summary: TerritoryCaptureSummary) -> String? {
        guard summary.ok else {
            return failureMessage(reason: summary.reason)
        }
        let gained = summary.cells_gained ?? 0
        let taken = summary.cells_taken ?? 0
        if gained == 0 { return nil }
        var parts = ["Captured \(gained) map cells"]
        if taken > 0 {
            parts.append("taking \(taken) from others")
        }
        if let bbox = summary.bbox,
           let lat = bbox.min_lat,
           let lon = bbox.min_lon {
            parts.append(String(format: "near %.3f, %.3f", lat, lon))
        }
        return parts.joined(separator: ", ") + "."
    }

    static func failureMessage(reason: String?) -> String {
        switch reason {
        case "activity_not_eligible":
            return "Territory capture only applies to outdoor GPS cardio."
        case "missing_route":
            return "Territory capture needs a GPS route on this workout."
        case "route_too_short":
            return "Route is too short to capture territory."
        case "speed_unrealistic":
            return "Route speed looks unrealistic for territory capture."
        case "no_cells":
            return "No territory cells were captured on this route."
        case "capture_geom_failed":
            return "Territory capture could not build a capture area."
        default:
            return "Territory capture could not be applied."
        }
    }

    static func failureMessage(for error: Error) -> String {
        let text = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            return "Territory capture could not be applied."
        }
        return "Territory capture failed: \(text)"
    }
}
