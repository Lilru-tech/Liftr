import CoreLocation
import MapKit
import SwiftUI

struct TerritoryMapView: View {
    @EnvironmentObject private var app: AppState

    private static let defaultRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 41.1189, longitude: 1.2445),
        span: MKCoordinateSpan(latitudeDelta: 0.12, longitudeDelta: 0.12)
    )

    private let initialLatitude: Double?
    private let initialLongitude: Double?
    private let initialSpan: Double

    init(
        initialLatitude: Double? = nil,
        initialLongitude: Double? = nil,
        initialSpan: Double = 0.12
    ) {
        self.initialLatitude = initialLatitude
        self.initialLongitude = initialLongitude
        self.initialSpan = initialSpan
    }

    @State private var mapCameraPosition: MapCameraPosition = .region(defaultRegion)
    @State private var visibleRegion = defaultRegion
    @State private var cellCache: [String: TerritoryMapCellRow] = [:]
    @State private var summary: TerritorySummaryResponse?
    @State private var loading = false
    @State private var lastFetchKey = ""
    @State private var selectedCell: TerritoryMapCellRow?
    @State private var profileUser: TerritoryProfileUser?
    @State private var showLeaderboard = false
    @State private var showMineOnly = false
    @State private var loadError: String?
    @State private var othersMayBeTruncated = false
    @State private var mineFetchLikelyCapped = false

    private static let mapCellFetchLimit = 500
    private static let othersSlotsReservedOnServer = min(200, max(mapCellFetchLimit / 2, 1))

    private static var maxMineCellsPerMapRequest: Int {
        mapCellFetchLimit - othersSlotsReservedOnServer
    }
    private static let drawRegionInflationFactor = 1.12
    private static let pruneCacheMaxEntries = 10_000
    private static let pruneRegionSpanMultiplier = 2.5

    private var cellsIntersectingDrawRegion: [TerritoryMapCellRow] {
        let drawRegion = Self.inflatedRegion(visibleRegion, latitudeFactor: Self.drawRegionInflationFactor, longitudeFactor: Self.drawRegionInflationFactor)
        return cellCache.values.filter { cell in
            guard let bbox = TerritoryMapGeometry.geographicBoundingBox(ring: cell.ring) else { return false }
            return TerritoryMapGeometry.intersects(region: drawRegion, bbox: bbox)
        }.sorted { $0.cell_id < $1.cell_id }
    }

    private var visibleCells: [TerritoryMapCellRow] {
        let intersecting = cellsIntersectingDrawRegion
        if showMineOnly {
            return intersecting.filter { $0.is_mine == true }
        }
        return intersecting
    }

    private var ownedCellsInView: Int {
        visibleCells.filter { $0.is_mine == true }.count
    }

    var body: some View {
        ZStack(alignment: .top) {
            MapReader { proxy in
                Map(position: $mapCameraPosition) {
                    ForEach(visibleCells) { cell in
                        let ring = cell.ring
                        if ring.count >= 3, let ownerId = cell.owner_user_id {
                            MapPolygon(coordinates: ring)
                                .foregroundStyle(TerritoryOwnerColors.fill(for: ownerId, isMine: cell.is_mine == true))
                                .stroke(
                                    TerritoryOwnerColors.stroke(for: ownerId, isMine: cell.is_mine == true),
                                    lineWidth: TerritoryOwnerColors.strokeWidth(isMine: cell.is_mine == true)
                                )
                        }
                    }
                }
                .mapControls {
                    MapUserLocationButton()
                    MapCompass()
                }
                .contentShape(Rectangle())
                .onTapGesture { point in
                    guard let coordinate = proxy.convert(point, from: .local) else { return }
                    selectedCell = TerritoryMapGeometry.selectedCell(at: coordinate, in: Array(cellCache.values))
                }
                .ignoresSafeArea(edges: .bottom)
                .onMapCameraChange(frequency: .onEnd) { context in
                    visibleRegion = context.region
                    AppState.shared.territoryReferenceCoordinate = context.region.center
                    Task { await refreshVisibleCells(for: context.region) }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let summary {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 12) {
                        Text("You own \(summary.total_cells ?? 0) cells")
                        Spacer()
                        Button("Leaderboard") {
                            showLeaderboard = true
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.blue)
                    }
                    if let weekLine = TerritoryCapturePresentation.mapTerritory7dLine(
                        cellsGained7d: summary.cells_gained_last_7d ?? 0,
                        workouts7d: summary.capture_workouts_last_7d ?? 0
                    ) {
                        Text(weekLine)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text("Public map · colored cells are owned territory · brighter cells are yours")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Toggle("Show only my cells", isOn: $showMineOnly)
                        .font(.caption)
                    if !visibleCells.isEmpty && ownedCellsInView == 0 {
                        Text("\(visibleCells.count) cells in view belong to other players")
                            .font(.caption)
                    }
                    if mineFetchLikelyCapped {
                        Text(
                            "Showing up to \(Self.maxMineCellsPerMapRequest) of your newest cells in this area — pan or zoom to load more."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    if othersMayBeTruncated && !showMineOnly {
                        Text("Some other players' cells are hidden in this area.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                .padding(8)
            }

            if let loadError {
                Text(loadError)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .padding(8)
            }

            if loading {
                ProgressView()
                    .padding(12)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task {
            await MainActor.run {
                cellCache = [:]
                lastFetchKey = ""
            }
            let center = Self.coordinate(
                latitude: initialLatitude,
                longitude: initialLongitude,
                fallback: app.territoryReferenceCoordinate
            )
            let initialRegion = Self.region(around: center, span: initialSpan)
            mapCameraPosition = .region(initialRegion)
            visibleRegion = initialRegion
            if let center {
                app.territoryReferenceCoordinate = center
            }
            async let summaryLoad: Void = loadSummary()
            async let cellsLoad: Void = refreshVisibleCells(for: initialRegion)
            _ = await summaryLoad
            _ = await cellsLoad
            Task(priority: .utility) {
                await TerritoryCaptureClient.backfillHistoricalCaptures()
                await loadSummary()
            }
        }
        .sheet(item: $selectedCell) { cell in
            TerritoryCellDetailSheet(
                cell: cell,
                onViewProfile: { userId in
                    profileUser = TerritoryProfileUser(id: userId)
                    selectedCell = nil
                }
            )
            .presentationDetents([.height(220)])
        }
        .sheet(isPresented: $showLeaderboard) {
            TerritoryShareLeaderboardView(
                initialLatitude: visibleRegion.center.latitude,
                initialLongitude: visibleRegion.center.longitude
            )
        }
        .fullScreenCover(item: $profileUser) { profile in
            NavigationStack {
                ProfileView(userId: profile.id)
                    .environmentObject(app)
                    .gradientBG()
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Close") {
                                profileUser = nil
                            }
                        }
                    }
            }
        }
    }

    private static func coordinate(
        latitude: Double?,
        longitude: Double?,
        fallback: CLLocationCoordinate2D?
    ) -> CLLocationCoordinate2D? {
        if let latitude, let longitude {
            return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
        return fallback
    }

    private static func region(around coordinate: CLLocationCoordinate2D?, span: Double) -> MKCoordinateRegion {
        guard let coordinate else { return defaultRegion }
        return MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span)
        )
    }

    private static func region(around coordinate: CLLocationCoordinate2D?) -> MKCoordinateRegion {
        region(around: coordinate, span: 0.12)
    }

    private static func inflatedRegion(
        _ region: MKCoordinateRegion,
        latitudeFactor: Double,
        longitudeFactor: Double
    ) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: region.center,
            span: MKCoordinateSpan(
                latitudeDelta: region.span.latitudeDelta * latitudeFactor,
                longitudeDelta: region.span.longitudeDelta * longitudeFactor
            )
        )
    }

    private func pruneCellCacheIfNeeded() {
        guard cellCache.count > Self.pruneCacheMaxEntries else { return }
        let keepRegion = Self.inflatedRegion(
            visibleRegion,
            latitudeFactor: Self.pruneRegionSpanMultiplier,
            longitudeFactor: Self.pruneRegionSpanMultiplier
        )
        let keysToRemove = cellCache.keys.filter { key in
            guard let cell = cellCache[key],
                  let bbox = TerritoryMapGeometry.geographicBoundingBox(ring: cell.ring)
            else { return true }
            return !TerritoryMapGeometry.intersects(region: keepRegion, bbox: bbox)
        }
        for key in keysToRemove {
            cellCache.removeValue(forKey: key)
        }
    }

    private func loadSummary() async {
        let loaded = await TerritoryCaptureClient.fetchMySummary()
        await MainActor.run {
            summary = loaded
            if loaded == nil {
                loadError = "Territory summary could not be loaded."
            } else {
                loadError = nil
            }
        }
    }

    private func refreshVisibleCells(for region: MKCoordinateRegion) async {
        let minLat = region.center.latitude - region.span.latitudeDelta / 2.0
        let maxLat = region.center.latitude + region.span.latitudeDelta / 2.0
        let minLon = region.center.longitude - region.span.longitudeDelta / 2.0
        let maxLon = region.center.longitude + region.span.longitudeDelta / 2.0
        let key = String(format: "%.4f|%.4f|%.4f|%.4f", minLat, minLon, maxLat, maxLon)
        guard key != lastFetchKey else { return }
        lastFetchKey = key
        await MainActor.run { loading = true }
        let rows = await TerritoryCaptureClient.fetchMapCells(
            minLat: minLat,
            minLon: minLon,
            maxLat: maxLat,
            maxLon: maxLon,
            limit: Self.mapCellFetchLimit
        )
        await MainActor.run {
            for row in rows {
                cellCache[row.cell_id] = row
            }
            pruneCellCacheIfNeeded()
            let mineCount = rows.filter { $0.is_mine == true }.count
            let othersCount = rows.count - mineCount
            let othersBudget = max(0, Self.mapCellFetchLimit - mineCount)
            mineFetchLikelyCapped = mineCount >= Self.maxMineCellsPerMapRequest
            othersMayBeTruncated = !showMineOnly
                && othersCount > 0
                && othersBudget > 0
                && othersCount >= othersBudget
            loading = false
        }
    }
}

private struct TerritoryProfileUser: Identifiable {
    let id: UUID
}

private struct TerritoryCellDetailSheet: View {
    let cell: TerritoryMapCellRow
    let onViewProfile: (UUID) -> Void

    private var capturedLabel: String {
        guard let capturedAt = cell.captured_at else { return "Captured recently" }
        return capturedAt.formatted(date: .abbreviated, time: .shortened)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                if let ownerId = cell.owner_user_id {
                    Circle()
                        .fill(TerritoryOwnerColors.color(for: ownerId))
                        .frame(width: 14, height: 14)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(cell.owner_username.map { "@\($0)" } ?? "Unknown owner")
                        .font(.headline)
                    Text(capturedLabel)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            if let ownerId = cell.owner_user_id {
                Button("View profile") {
                    onViewProfile(ownerId)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
