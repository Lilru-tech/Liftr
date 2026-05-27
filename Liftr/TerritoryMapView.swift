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
    @State private var drawableCellsInView: [TerritoryMapCellRow] = []
    @State private var cellsToRender: [TerritoryMapCellRow] = []
    @State private var cellBoundingBoxes: [String: TerritoryMapGeometry.GeographicBoundingBox] = [:]
    @State private var refreshTask: Task<Void, Never>?
    @State private var loadedSnapshotRegion: MKCoordinateRegion?
    @State private var expansionRecommendations: [TerritoryExpansionRecommendationRow] = []
    @State private var loadingExpansion = false
    @State private var expansionError: String?
    @State private var lastUserLocation: CLLocationCoordinate2D?
    @State private var expansionFetchTask: Task<Void, Never>?
    @State private var cellsFetchTask: Task<[TerritoryMapCellRow], Never>?
    @State private var isBootstrappingMap = true

    private static let mapCellFetchLimit = 5_000
    private static let maxRenderedHexCells = 5_000
    private static let otherRenderedHexCellsTarget = maxRenderedHexCells

    private static let drawRegionInflationFactor = 1.12
    private static let pruneCacheMaxEntries = 6_000
    private static let pruneRegionSpanMultiplier = 1.75
    private static let snapshotFetchRegionMultiplier = 1.4
    private static let mapFetchDebounceNanoseconds: UInt64 = 550_000_000

    private static func log(_ message: String) {
        print("[TerritoryMap][View] \(message)")
    }

    private func recomputeDrawableCells() {
        let drawRegion = Self.inflatedRegion(
            visibleRegion,
            latitudeFactor: Self.drawRegionInflationFactor,
            longitudeFactor: Self.drawRegionInflationFactor
        )
        drawableCellsInView = cellCache.values.filter { cell in
            guard let bbox = boundingBox(for: cell) else { return false }
            return TerritoryMapGeometry.intersects(region: drawRegion, bbox: bbox)
        }.sorted { $0.cell_id < $1.cell_id }
        updateCellsToRender()
        Self.log("recompute cache=\(cellCache.count) visible=\(drawableCellsInView.count) render=\(cellsToRender.count) region=\(Self.regionLog(visibleRegion))")
    }

    private func dynamicFetchLimit(for region: MKCoordinateRegion) -> Int {
        let span = max(region.span.latitudeDelta, region.span.longitudeDelta)
        if span > 0.45 { return 1_200 }
        if span > 0.30 { return 2_500 }
        return Self.mapCellFetchLimit
    }

    private func dynamicRenderCap(for region: MKCoordinateRegion) -> Int {
        let span = max(region.span.latitudeDelta, region.span.longitudeDelta)
        if span > 0.45 { return 900 }
        if span > 0.30 { return 2_000 }
        return Self.maxRenderedHexCells
    }

    private func updateCellsToRender() {
        if showMineOnly {
            cellsToRender = drawableCellsInView.filter { $0.is_mine == true }
            return
        }
        let mine = drawableCellsInView.filter { $0.is_mine == true }
        let others = drawableCellsInView.filter { !($0.is_mine == true) }
        let cap = dynamicRenderCap(for: visibleRegion)
        if drawableCellsInView.count <= cap {
            cellsToRender = drawableCellsInView
            return
        }
        let othersCap = max(0, cap - mine.count)
        let selectedOthers = TerritoryMapGeometry.ownerBalancedCells(
            others,
            maxCount: othersCap,
            otherTarget: othersCap
        )
        cellsToRender = mine + selectedOthers
    }

    private var visibleCells: [TerritoryMapCellRow] {
        if showMineOnly {
            return drawableCellsInView.filter { $0.is_mine == true }
        }
        return drawableCellsInView
    }

    private var ownedCellsInView: Int {
        visibleCells.filter { $0.is_mine == true }.count
    }

    var body: some View {
        ZStack(alignment: .top) {
            TerritoryMapRepresentable(
                region: visibleRegion,
                cells: cellsToRender,
                suggestionCells: expansionRecommendations,
                onRegionChange: handleMapRegionChange,
                onSelectCell: { selectedCell = $0 },
                onUserLocationUpdate: { lastUserLocation = $0 }
            )
            .ignoresSafeArea(edges: .bottom)
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
                    if visibleCells.count > dynamicRenderCap(for: visibleRegion) {
                        Text("Showing a simplified view in this area for performance.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if mineFetchLikelyCapped {
                        Text(
                            "Showing a simplified view of your cells in this area — pan or zoom to load more."
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

            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button {
                        toggleExpansionSuggestions()
                    } label: {
                        HStack(spacing: 8) {
                            if loadingExpansion {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Text("Suggest Expansion Zone")
                                .font(.subheadline.weight(.semibold))
                                .multilineTextAlignment(.trailing)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .disabled(loadingExpansion)
                    .padding(.trailing, 12)
                    .padding(.bottom, 72)
                }
            }

            if let expansionError {
                Text(expansionError)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(.leading, 8)
                    .padding(.bottom, 140)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task {
            await MainActor.run {
                cellCache = [:]
                lastFetchKey = ""
                drawableCellsInView = []
                cellsToRender = []
                cellBoundingBoxes = [:]
                loadedSnapshotRegion = nil
                isBootstrappingMap = true
            }
            let center = Self.coordinate(
                latitude: initialLatitude,
                longitude: initialLongitude,
                fallback: app.territoryReferenceCoordinate
            )
            let initialRegion = Self.region(around: center, span: initialSpan)
            visibleRegion = initialRegion
            recomputeDrawableCells()
            if let center {
                app.territoryReferenceCoordinate = center
            }
            async let summaryLoad: Void = loadSummary()
            async let cellsLoad: Void = performSnapshotFetch(for: initialRegion)
            _ = await summaryLoad
            _ = await cellsLoad
            await MainActor.run {
                isBootstrappingMap = false
            }
        }
        .onDisappear {
            refreshTask?.cancel()
            refreshTask = nil
            cellsFetchTask?.cancel()
            cellsFetchTask = nil
            expansionFetchTask?.cancel()
            expansionFetchTask = nil
        }
        .onChange(of: showMineOnly) { _, _ in
            updateCellsToRender()
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

    private static func computeCellBoundingBoxes(
        for rows: [TerritoryMapCellRow]
    ) async -> [String: TerritoryMapGeometry.GeographicBoundingBox] {
        await Task.detached(priority: .userInitiated) {
            var boxes: [String: TerritoryMapGeometry.GeographicBoundingBox] = [:]
            boxes.reserveCapacity(rows.count)
            for row in rows {
                if let bbox = TerritoryMapGeometry.geographicBoundingBox(ring: row.ring) {
                    boxes[row.cell_id] = bbox
                }
            }
            return boxes
        }.value
    }

    private static func regionLog(_ region: MKCoordinateRegion) -> String {
        String(
            format: "center=(%.5f,%.5f) span=(%.5f,%.5f)",
            region.center.latitude,
            region.center.longitude,
            region.span.latitudeDelta,
            region.span.longitudeDelta
        )
    }

    private static func paddedFetchRegion(for region: MKCoordinateRegion) -> MKCoordinateRegion {
        inflatedRegion(
            region,
            latitudeFactor: snapshotFetchRegionMultiplier,
            longitudeFactor: snapshotFetchRegionMultiplier
        )
    }

    private static func regionContains(_ outer: MKCoordinateRegion, visible inner: MKCoordinateRegion) -> Bool {
        let outerMinLat = outer.center.latitude - outer.span.latitudeDelta / 2
        let outerMaxLat = outer.center.latitude + outer.span.latitudeDelta / 2
        let outerMinLon = outer.center.longitude - outer.span.longitudeDelta / 2
        let outerMaxLon = outer.center.longitude + outer.span.longitudeDelta / 2
        let innerMinLat = inner.center.latitude - inner.span.latitudeDelta / 2
        let innerMaxLat = inner.center.latitude + inner.span.latitudeDelta / 2
        let innerMinLon = inner.center.longitude - inner.span.longitudeDelta / 2
        let innerMaxLon = inner.center.longitude + inner.span.longitudeDelta / 2
        return innerMinLat >= outerMinLat
            && innerMaxLat <= outerMaxLat
            && innerMinLon >= outerMinLon
            && innerMaxLon <= outerMaxLon
    }

    private func boundingBox(for cell: TerritoryMapCellRow) -> TerritoryMapGeometry.GeographicBoundingBox? {
        if let cached = cellBoundingBoxes[cell.cell_id] {
            return cached
        }
        guard let bbox = TerritoryMapGeometry.geographicBoundingBox(ring: cell.ring) else {
            return nil
        }
        cellBoundingBoxes[cell.cell_id] = bbox
        return bbox
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
                  let bbox = boundingBox(for: cell)
            else { return true }
            return !TerritoryMapGeometry.intersects(region: keepRegion, bbox: bbox)
        }
        for key in keysToRemove {
            cellCache.removeValue(forKey: key)
            cellBoundingBoxes.removeValue(forKey: key)
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

    private func handleMapRegionChange(_ region: MKCoordinateRegion) {
        visibleRegion = region
        AppState.shared.territoryReferenceCoordinate = region.center
        recomputeDrawableCells()
        Self.log("regionChanged \(Self.regionLog(region))")
        guard !isBootstrappingMap else {
            Self.log("skip viewport fetch during bootstrap")
            return
        }
        enqueueSnapshotFetchIfNeeded(for: region)
    }

    private func enqueueSnapshotFetchIfNeeded(for region: MKCoordinateRegion) {
        if let loadedSnapshotRegion,
           Self.regionContains(loadedSnapshotRegion, visible: region) {
            Self.log("skip viewport fetch loaded region contains visible \(Self.regionLog(region))")
            return
        }
        refreshTask?.cancel()
        Self.log("enqueue viewport fetch \(Self.regionLog(region))")
        refreshTask = Task {
            try? await Task.sleep(nanoseconds: Self.mapFetchDebounceNanoseconds)
            guard !Task.isCancelled else { return }
            await performSnapshotFetch(for: region)
        }
    }

    private func performSnapshotFetch(for visibleRegion: MKCoordinateRegion) async {
        let fetchRegion = Self.paddedFetchRegion(for: visibleRegion)
        let fetchLimit = dynamicFetchLimit(for: visibleRegion)
        await fetchCells(
            minLat: fetchRegion.center.latitude - fetchRegion.span.latitudeDelta / 2.0,
            minLon: fetchRegion.center.longitude - fetchRegion.span.longitudeDelta / 2.0,
            maxLat: fetchRegion.center.latitude + fetchRegion.span.latitudeDelta / 2.0,
            maxLon: fetchRegion.center.longitude + fetchRegion.span.longitudeDelta / 2.0,
            fetchKey: String(
                format: "%.4f|%.4f|%.4f|%.4f",
                fetchRegion.center.latitude - fetchRegion.span.latitudeDelta / 2.0,
                fetchRegion.center.longitude - fetchRegion.span.longitudeDelta / 2.0,
                fetchRegion.center.latitude + fetchRegion.span.latitudeDelta / 2.0,
                fetchRegion.center.longitude + fetchRegion.span.longitudeDelta / 2.0
            ),
            loadedRegion: fetchRegion,
            fetchLimit: fetchLimit
        )
    }

    private func fetchCells(
        minLat: Double,
        minLon: Double,
        maxLat: Double,
        maxLon: Double,
        fetchKey key: String,
        loadedRegion: MKCoordinateRegion?,
        fetchLimit: Int
    ) async {
        let skipFetch = await MainActor.run {
            key == lastFetchKey && loadedSnapshotRegion != nil
        }
        guard !skipFetch else {
            Self.log("skip fetch key=\(key)")
            return
        }

        Self.log("fetch start key=\(key) bounds=(\(minLat),\(minLon),\(maxLat),\(maxLon)) limit=\(fetchLimit)")

        await MainActor.run {
            cellsFetchTask?.cancel()
            lastFetchKey = key
            loading = cellCache.isEmpty
        }

        let task = Task {
            await TerritoryCaptureClient.fetchMapCells(
                minLat: minLat,
                minLon: minLon,
                maxLat: maxLat,
                maxLon: maxLon,
                limit: fetchLimit
            )
        }
        await MainActor.run {
            cellsFetchTask = task
        }

        let rows = await task.value

        guard !Task.isCancelled else {
            await MainActor.run {
                loading = false
            }
            Self.log("fetch cancelled key=\(key)")
            return
        }

        let boundingBoxes = await Self.computeCellBoundingBoxes(for: rows)

        await MainActor.run {
            let previousCount = cellCache.count
            for row in rows {
                cellCache[row.cell_id] = row
            }
            for (cellId, bbox) in boundingBoxes {
                cellBoundingBoxes[cellId] = bbox
            }
            loadedSnapshotRegion = loadedRegion
            pruneCellCacheIfNeeded()
            recomputeDrawableCells()
            let mineCount = rows.filter { $0.is_mine == true }.count
            let othersCount = rows.count - mineCount
            let capped = rows.count >= fetchLimit
            mineFetchLikelyCapped = capped && mineCount > 0
            othersMayBeTruncated = !showMineOnly && othersCount > 0 && capped
            if summary != nil {
                loadError = nil
            }
            loading = false
            Self.log("fetch finish key=\(key) rows=\(rows.count) cacheBefore=\(previousCount) cacheAfter=\(cellCache.count) mine=\(mineCount) others=\(othersCount)")
        }
    }

    private func toggleExpansionSuggestions() {
        if !expansionRecommendations.isEmpty {
            expansionRecommendations = []
            expansionError = nil
            return
        }
        expansionFetchTask?.cancel()
        expansionFetchTask = Task {
            await loadExpansionSuggestions()
        }
    }

    private func expansionQueryCoordinate() -> CLLocationCoordinate2D {
        let center = visibleRegion.center
        guard let gps = lastUserLocation else { return center }
        let gpsLocation = CLLocation(latitude: gps.latitude, longitude: gps.longitude)
        let centerLocation = CLLocation(latitude: center.latitude, longitude: center.longitude)
        if gpsLocation.distance(from: centerLocation) <= 2_000 {
            return gps
        }
        return center
    }

    private func loadExpansionSuggestions() async {
        guard let userId = SupabaseManager.shared.client.auth.currentUser?.id else {
            await MainActor.run {
                expansionError = "Sign in to see expansion suggestions."
                expansionRecommendations = []
            }
            return
        }

        if (summary?.total_cells ?? 0) == 0 {
            await MainActor.run {
                expansionError = "Capture territory with an outdoor workout first."
                expansionRecommendations = []
            }
            return
        }

        let query = expansionQueryCoordinate()
        let radiusMeters = TerritoryMapGeometry.expansionSearchRadiusMeters(for: visibleRegion)
        await MainActor.run {
            loadingExpansion = true
            expansionError = nil
        }

        let result = await TerritoryCaptureClient.fetchRecommendedExpansionCells(
            userId: userId,
            lat: query.latitude,
            lng: query.longitude,
            radiusMeters: radiusMeters
        )

        guard !Task.isCancelled else { return }

        await MainActor.run {
            loadingExpansion = false
            if let message = result.errorMessage {
                expansionRecommendations = []
                expansionError = message
                return
            }
            expansionRecommendations = result.cells
            if result.cells.isEmpty {
                expansionError = "No expansion zones found near this map view. Pan closer to your cells and try again."
            } else {
                expansionError = nil
            }
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
