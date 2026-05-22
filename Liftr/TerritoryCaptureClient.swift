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
    let last_workout_id: Int64?
    let captured_at: Date?
    let is_mine: Bool?
    var id: String { cell_id }

    var ring: [CLLocationCoordinate2D] { cell_geojson?.ring ?? [] }
}

struct TerritorySummaryResponse: Decodable {
    let total_cells: Int?
    let cells_gained_last_7d: Int?
    let capture_workouts_last_7d: Int?
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

struct TerritoryCaptureEventRow: Decodable, Hashable {
    let cells_gained: Int?
    let cells_taken: Int?
}

struct TerritoryWorkoutTakeoverRow: Decodable, Identifiable, Hashable {
    let victim_user_id: UUID?
    let victim_username: String?
    let victim_avatar_url: String?
    let cells_taken: Int?
    let share_taken_pct: Double?
    var id: String { victim_user_id?.uuidString ?? victim_username ?? "victim" }
}

enum TerritoryCaptureClient {
    private static func shouldIgnoreCancelledError(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled { return true }
        return error.localizedDescription.lowercased() == "cancelled"
    }

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
            guard !shouldIgnoreCancelledError(error) else { return nil }
            await MainActor.run {
                AppState.shared.territoryCaptureToast = TerritoryCapturePresentation.failureMessage(for: error)
            }
            return nil
        }
    }

    static func fetchCaptureEvent(workoutId: Int) async -> TerritoryCaptureEventRow? {
        do {
            let res = try await SupabaseManager.shared.client
                .from("territory_capture_events")
                .select("cells_gained, cells_taken")
                .eq("workout_id", value: workoutId)
                .limit(1)
                .execute()
            let rows = try JSONDecoder.supabase().decode([TerritoryCaptureEventRow].self, from: res.data)
            guard let row = rows.first, (row.cells_gained ?? 0) > 0 else { return nil }
            return row
        } catch {
            return nil
        }
    }

    static func fetchWorkoutTakeovers(workoutId: Int) async -> [TerritoryWorkoutTakeoverRow] {
        let params = WorkoutIdParams(p_workout_id: Int64(workoutId))
        do {
            let res = try await SupabaseManager.shared.client
                .rpc("list_workout_territory_takeovers_v1", params: params)
                .execute()
            return try JSONDecoder.supabase().decode([TerritoryWorkoutTakeoverRow].self, from: res.data)
        } catch {
            return []
        }
    }

    static func fetchTerritoryPreviewCells(routeGeoJSON: String) async -> [TerritoryPreviewCell] {
        let params = RouteGeoJSONParams(p_route_geojson: routeGeoJSON)
        do {
            let res = try await SupabaseManager.shared.client
                .rpc("preview_territory_capture_v1", params: params)
                .execute()
            let decoded = try JSONDecoder.supabase().decode(TerritoryPreviewResponse.self, from: res.data)
            guard decoded.ok != false else { return [] }
            return decoded.cells ?? []
        } catch {
            return []
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
            guard !shouldIgnoreCancelledError(error) else { return nil }
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
            if userId == nil && !shouldIgnoreCancelledError(error) {
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
        limit: Int = 5_000
    ) async -> [TerritoryMapCellRow] {
        let effectiveLimit = min(5_000, max(limit, 1))
        print("[TerritoryMap][RPC] start minLat=\(minLat) minLon=\(minLon) maxLat=\(maxLat) maxLon=\(maxLon) limit=\(effectiveLimit)")
        let pageSize = min(500, effectiveLimit)
        let params = MapParams(
            p_min_lat: minLat,
            p_min_lon: minLon,
            p_max_lat: maxLat,
            p_max_lon: maxLon,
            p_limit: effectiveLimit
        )
        do {
            var allRows: [TerritoryMapCellRow] = []
            var offset = 0
            var totalBytes = 0
            while offset < effectiveLimit {
                let pageLimit = min(pageSize, effectiveLimit - offset)
                let res = try await SupabaseManager.shared.client
                    .rpc("get_territory_map_v1", params: params)
                    .range(from: offset, to: offset + pageLimit - 1)
                    .execute()
                totalBytes += res.data.count
                let pageRows = try JSONDecoder.supabase().decode([TerritoryMapCellRow].self, from: res.data)
                print("[TerritoryMap][RPC] page offset=\(offset) rows=\(pageRows.count) bytes=\(res.data.count)")
                allRows.append(contentsOf: pageRows)
                guard pageRows.count == pageLimit else {
                    break
                }
                offset += pageLimit
            }
            let owners = Set(allRows.compactMap(\.owner_user_id)).count
            let mine = allRows.filter { $0.is_mine == true }.count
            print("[TerritoryMap][RPC] success rows=\(allRows.count) owners=\(owners) mine=\(mine) bytes=\(totalBytes)")
            return allRows
        } catch {
            print("[TerritoryMap][RPC] failed error=\(error.localizedDescription)")
            return []
        }
    }

    static func fetchTerritoryCityRegions(
        query: String? = nil,
        ownedFirst: Bool = true,
        limit: Int = 200
    ) async -> [TerritoryCityRegionRow] {
        struct Params: Encodable {
            let p_query: String?
            let p_limit: Int
            let p_owned_first: Bool
        }
        do {
            let res = try await SupabaseManager.shared.client
                .rpc(
                    "list_territory_city_regions_v1",
                    params: Params(
                        p_query: query?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true ? nil : query,
                        p_limit: limit,
                        p_owned_first: ownedFirst
                    )
                )
                .execute()
            let rows = try JSONDecoder.supabase().decode([TerritoryCityRegionRow].self, from: res.data)
            return deduplicatedTerritoryCities(rows)
        } catch {
            logTerritoryShare("city regions fetch failed error=\(error.localizedDescription)")
            return []
        }
    }

    static func deduplicatedTerritoryCities(_ cities: [TerritoryCityRegionRow]) -> [TerritoryCityRegionRow] {
        var selectedByIdentity: [String: TerritoryCityRegionRow] = [:]
        var orderedIdentities: [String] = []
        for city in cities {
            let identity = territoryCityIdentity(for: city)
            if let existing = selectedByIdentity[identity] {
                if shouldPreferTerritoryCity(city, over: existing) {
                    selectedByIdentity[identity] = city
                }
            } else {
                selectedByIdentity[identity] = city
                orderedIdentities.append(identity)
            }
        }
        return orderedIdentities.compactMap { selectedByIdentity[$0] }
    }

    static func filterTerritoryCities(_ cities: [TerritoryCityRegionRow], query: String) -> [TerritoryCityRegionRow] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return cities }
        return cities.filter { city in
            let name = city.display_name?.lowercased() ?? ""
            let key = city.city_key?.lowercased() ?? ""
            return name.contains(needle) || key.contains(needle)
        }
    }

    private static func territoryCityIdentity(for city: TerritoryCityRegionRow) -> String {
        let name = city.display_name?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let name, !name.isEmpty {
            return "name:\(name)"
        }
        return "key:\(city.city_key ?? city.id)"
    }

    private static func shouldPreferTerritoryCity(
        _ candidate: TerritoryCityRegionRow,
        over current: TerritoryCityRegionRow
    ) -> Bool {
        let candidateOwned = candidate.my_owned_cells ?? candidate.owned_cells ?? 0
        let currentOwned = current.my_owned_cells ?? current.owned_cells ?? 0
        if candidateOwned != currentOwned {
            return candidateOwned > currentOwned
        }
        let candidateCaptured = candidate.captured_cells ?? 0
        let currentCaptured = current.captured_cells ?? 0
        if candidateCaptured != currentCaptured {
            return candidateCaptured > currentCaptured
        }
        let candidateTotal = candidate.total_capture_cells ?? 0
        let currentTotal = current.total_capture_cells ?? 0
        if candidateTotal != currentTotal {
            return candidateTotal > currentTotal
        }
        return (candidate.city_key ?? "") < (current.city_key ?? "")
    }

    static func selectedTerritoryCity(
        from cities: [TerritoryCityRegionRow],
        preferredKey: String?,
        referenceLatitude: Double?,
        referenceLongitude: Double?
    ) -> TerritoryCityRegionRow? {
        if let preferredKey,
           let match = cities.first(where: { $0.city_key == preferredKey }) {
            return match
        }
        if let referenceLatitude, let referenceLongitude,
           let key = nearestCityKey(to: referenceLatitude, longitude: referenceLongitude, from: cities),
           let match = cities.first(where: { $0.city_key == key }) {
            return match
        }
        if let key = preferredCityKey(latitude: referenceLatitude, longitude: referenceLongitude, from: cities),
           let match = cities.first(where: { $0.city_key == key }) {
            return match
        }
        return cities.first
    }

    static let recentTerritoryCityKeysKey = "recentTerritoryCityKeysV1"
    static let recentTerritoryCityKeysLimit = 5

    static func recentTerritoryCityKeys() -> [String] {
        UserDefaults.standard.stringArray(forKey: recentTerritoryCityKeysKey) ?? []
    }

    static func recordRecentTerritoryCityKey(_ cityKey: String?) {
        guard let cityKey, !cityKey.isEmpty, !isPendingTerritoryCityKey(cityKey) else { return }
        var keys = recentTerritoryCityKeys().filter { $0 != cityKey }
        keys.insert(cityKey, at: 0)
        if keys.count > recentTerritoryCityKeysLimit {
            keys = Array(keys.prefix(recentTerritoryCityKeysLimit))
        }
        UserDefaults.standard.set(keys, forKey: recentTerritoryCityKeysKey)
    }

    static func fetchTerritoryTotalCellsLeaderboard(
        scope: String = "global",
        limit: Int = 100
    ) async -> [TerritoryShareLeaderRow] {
        struct Params: Encodable {
            let p_scope: String
            let p_limit: Int
        }
        do {
            let res = try await SupabaseManager.shared.client
                .rpc(
                    "get_territory_total_cells_leaderboard_v1",
                    params: Params(p_scope: scope, p_limit: limit)
                )
                .execute()
            return try JSONDecoder.supabase().decode([TerritoryShareLeaderRow].self, from: res.data)
        } catch {
            return []
        }
    }

    static func isPendingTerritoryCityKey(_ cityKey: String?) -> Bool {
        cityKey?.hasPrefix("pending:") == true
    }

    static func pendingResolveCoordinates(for city: TerritoryCityRegionRow) -> (lat: Double, lon: Double)? {
        if let cityKey = city.city_key, isPendingTerritoryCityKey(cityKey) {
            let parts = cityKey.split(separator: ":", omittingEmptySubsequences: false)
            if parts.count >= 3,
               let lat = Double(parts[1]),
               let lon = Double(parts[2]) {
                return (lat, lon)
            }
        }
        if let lat = city.center_lat, let lon = city.center_lon {
            return (lat, lon)
        }
        return nil
    }

    static func pendingBucketCoordinates(for city: TerritoryCityRegionRow) -> (lat: Double, lon: Double)? {
        guard let cityKey = city.city_key, isPendingTerritoryCityKey(cityKey) else { return nil }
        let parts = cityKey.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count >= 3,
              let lat = Double(parts[1]),
              let lon = Double(parts[2]) else { return nil }
        return (lat, lon)
    }

    static func logTerritoryShare(_ message: String) {
        print("[TerritoryShare] \(message)")
    }

    private actor TerritoryMunicipalityRefreshGate {
        static let shared = TerritoryMunicipalityRefreshGate()
        private var activeRefresh: Task<[TerritoryCityRegionRow], Never>?

        func run(_ operation: @escaping () async -> [TerritoryCityRegionRow]) async -> [TerritoryCityRegionRow] {
            if let activeRefresh {
                return await activeRefresh.value
            }
            let task = Task {
                await operation()
            }
            activeRefresh = task
            let result = await task.value
            activeRefresh = nil
            return result
        }
    }

    static func refreshPendingTerritoryCityRegions(
        maxResolveItems: Int = 2,
        maxBatches: Int = 8,
        timeBudgetSeconds: TimeInterval = 60,
        onUpdate: (@MainActor ([TerritoryCityRegionRow]) -> Void)? = nil
    ) async -> [TerritoryCityRegionRow] {
        let started = Date()
        let deadline = started.addingTimeInterval(timeBudgetSeconds)
        var refreshed = await fetchTerritoryCityRegions()
        var batchesRun = 0
        while batchesRun < maxBatches, Date() < deadline {
            let pending = refreshed.filter { isPendingTerritoryCityKey($0.city_key) }
            logTerritoryShare("refresh batch=\(batchesRun + 1) total=\(refreshed.count) pending=\(pending.count)")
            guard !pending.isEmpty else { break }
            let resolveLimit = max(1, min(maxResolveItems, pending.count))
            for index in 0..<resolveLimit {
                logTerritoryShare("resolve batch=\(batchesRun + 1) queue item=\(index + 1)/\(resolveLimit)")
                await invokeTerritoryMunicipalityResolve(
                    limit: 1,
                    processQueue: true,
                    runAssignmentBackfill: false
                )
                if index + 1 < resolveLimit {
                    try? await Task.sleep(nanoseconds: 800_000_000)
                }
            }
            refreshed = await fetchTerritoryCityRegions()
            if let onUpdate {
                await onUpdate(refreshed)
            }
            batchesRun += 1
        }
        let remainingPending = refreshed.filter { isPendingTerritoryCityKey($0.city_key) }.count
        let elapsedMs = Int(Date().timeIntervalSince(started) * 1000)
        logTerritoryShare("refresh finished batches=\(batchesRun) elapsedMs=\(elapsedMs) pending=\(remainingPending)")
        return refreshed
    }

    static func refreshPendingTerritoryCityRegionsInBackground(
        maxResolveItems: Int = 2,
        maxBatches: Int = 8,
        onUpdate: @escaping @MainActor ([TerritoryCityRegionRow]) -> Void
    ) {
        Task.detached(priority: .utility) {
            _ = await TerritoryMunicipalityRefreshGate.shared.run {
                await refreshPendingTerritoryCityRegions(
                    maxResolveItems: maxResolveItems,
                    maxBatches: maxBatches,
                    onUpdate: onUpdate
                )
            }
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

    static let historicalBackfillDoneKey = "territoryHistoricalBackfillCompletedV2"

    static func shouldMarkHistoricalBackfillDone(hasMore: Bool) -> Bool {
        !hasMore
    }

    static func backfillHistoricalCaptures(batchSize: Int = 5, maxBatchesPerVisit: Int = 40) async {
        if UserDefaults.standard.bool(forKey: historicalBackfillDoneKey) {
            refreshTerritoryMunicipalitiesInBackground()
            return
        }
        let params = BackfillParams(p_limit: batchSize)
        var shouldMarkDone = false
        for _ in 0..<maxBatchesPerVisit {
            do {
                let res = try await SupabaseManager.shared.client
                    .rpc("backfill_my_territory_captures_v1", params: params)
                    .execute()
                let batch = try JSONDecoder.supabase().decode(TerritoryBackfillResponse.self, from: res.data)
                guard batch.ok else { break }
                let processed = batch.processed ?? 0
                if processed == 0 { break }
                if shouldMarkHistoricalBackfillDone(hasMore: batch.has_more == true) {
                    shouldMarkDone = true
                    break
                }
            } catch {
                break
            }
        }
        if shouldMarkDone {
            UserDefaults.standard.set(true, forKey: historicalBackfillDoneKey)
        }
        refreshTerritoryMunicipalitiesInBackground()
    }

    static func refreshTerritoryMunicipalitiesInBackground(limit: Int = 1) {
        Task.detached(priority: .utility) {
            await invokeTerritoryMunicipalityResolve(
                limit: limit,
                processQueue: true,
                runAssignmentBackfill: false
            )
        }
    }

    private static func invokeTerritoryMunicipalityResolve(
        limit: Int,
        processQueue: Bool,
        runAssignmentBackfill: Bool,
        latitude: Double? = nil,
        longitude: Double? = nil,
        bucketLatitude: Double? = nil,
        bucketLongitude: Double? = nil
    ) async {
        struct Payload: Encodable {
            let limit: Int?
            let max_items: Int?
            let process_queue: Bool
            let run_assignment_backfill: Bool
            let lat: Double?
            let lon: Double?
            let bucket_lat: Double?
            let bucket_lon: Double?
        }
        struct ResolveResponse: Decodable {
            let ok: Bool?
            let error: String?
            struct ResolveError: Decodable {
                let error: String?
            }
            let errors: [ResolveError]?
        }
        do {
            let response: ResolveResponse = try await SupabaseManager.shared.client.functions
                .invoke(
                    "resolve-territory-municipality",
                    options: .init(
                        body: Payload(
                            limit: limit,
                            max_items: limit,
                            process_queue: processQueue,
                            run_assignment_backfill: runAssignmentBackfill,
                            lat: latitude,
                            lon: longitude,
                            bucket_lat: bucketLatitude,
                            bucket_lon: bucketLongitude
                        )
                    )
                )
            if response.ok == false {
                logTerritoryShare("municipality resolve failed error=\(response.error ?? "unknown")")
            } else if let errors = response.errors, !errors.isEmpty {
                let messages = errors.compactMap(\.error).joined(separator: "; ")
                logTerritoryShare("municipality resolve partial errors=\(messages)")
            }
        } catch {
            logTerritoryShare("municipality resolve failed error=\(error.localizedDescription)")
        }
    }

    private static func invokeTerritoryMunicipalityResolve(limit: Int) async {
        await invokeTerritoryMunicipalityResolve(
            limit: limit,
            processQueue: true,
            runAssignmentBackfill: false
        )
    }

    static func citySummaryLabel(for city: TerritoryCityRegionRow) -> String {
        let name = city.display_name ?? city.city_key ?? "City"
        let captured = city.captured_cells ?? 0
        if let total = city.total_capture_cells, total > 0 {
            return "\(name) · \(captured) / \(total) cells"
        }
        return "\(name) · \(captured) cells"
    }

    static func profileCitySummaryLabel(for city: TerritoryCityRegionRow) -> String {
        let name = city.display_name ?? city.city_key ?? "City"
        let owned = city.my_owned_cells ?? city.owned_cells ?? 0
        let communityCaptured = city.captured_cells ?? 0
        if let total = city.total_capture_cells, total > owned, total >= communityCaptured {
            return "\(name) · you own \(owned) of \(total) cells"
        }
        return "\(name) · you own \(owned) cells"
    }
}

enum TerritoryCapturePresentation {
    static func profileTerritorySummaryLine(
        totalCells: Int,
        cellsGained7d: Int,
        workouts7d: Int,
        isOwnProfile: Bool
    ) -> String {
        let prefix = isOwnProfile ? "You own \(totalCells) cells" : "Owns \(totalCells) cells"
        guard cellsGained7d > 0 || workouts7d > 0 else { return prefix }
        let workoutWord = workouts7d == 1 ? "workout" : "workouts"
        let newWord = cellsGained7d == 1 ? "new cell" : "new cells"
        return "\(prefix) · \(cellsGained7d) \(newWord) (in \(workouts7d) \(workoutWord)) in the last 7 days"
    }

    static func mapTerritory7dLine(cellsGained7d: Int, workouts7d: Int) -> String? {
        guard cellsGained7d > 0 || workouts7d > 0 else { return nil }
        let newCellsWord = cellsGained7d == 1 ? "new cell" : "new cells"
        let workoutWord = workouts7d == 1 ? "workout" : "workouts"
        return "7d: \(cellsGained7d) \(newCellsWord) (\(workouts7d) \(workoutWord))"
    }

    static func workoutDetailLabel(gained: Int, taken: Int) -> String {
        if taken > 0 {
            return "\(gained) cells (\(taken) from others)"
        }
        return "\(gained) cells"
    }

    static func takeoverRowSubtitle(cells: Int, sharePct: Double) -> String {
        let shareText = sharePct.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", sharePct)
            : String(format: "%.1f", sharePct)
        return "\(cells) cells · \(shareText)%"
    }

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
