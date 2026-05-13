import CoreLocation
import MapKit
import SwiftUI

struct TerritoryMapView: View {
    @EnvironmentObject private var app: AppState

    private static let defaultRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 41.1189, longitude: 1.2445),
        span: MKCoordinateSpan(latitudeDelta: 0.12, longitudeDelta: 0.12)
    )

    @State private var mapCameraPosition: MapCameraPosition = .region(defaultRegion)
    @State private var visibleRegion = defaultRegion
    @State private var cells: [TerritoryMapCellRow] = []
    @State private var summary: TerritorySummaryResponse?
    @State private var loading = false
    @State private var lastFetchKey = ""
    @State private var selectedCell: TerritoryMapCellRow?
    @State private var profileUserId: UUID?
    @State private var showProfile = false
    @State private var showLeaderboard = false
    @State private var showMineOnly = false
    @State private var loadError: String?

    private var visibleCells: [TerritoryMapCellRow] {
        if showMineOnly {
            return cells.filter { $0.is_mine == true }
        }
        return cells
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
                    selectedCell = TerritoryMapGeometry.selectedCell(at: coordinate, in: cells)
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
                        Text("7d captures: \(summary.cells_last_7d ?? 0)")
                        Spacer()
                        Button("Leaderboard") {
                            showLeaderboard = true
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.blue)
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
            let initialRegion = Self.region(around: app.territoryReferenceCoordinate)
            mapCameraPosition = .region(initialRegion)
            visibleRegion = initialRegion
            async let summaryLoad: Void = loadSummary()
            async let cellsLoad: Void = refreshVisibleCells(for: initialRegion)
            _ = await summaryLoad
            _ = await cellsLoad
            Task(priority: .utility) {
                await TerritoryCaptureClient.backfillHistoricalCaptures()
                await loadSummary()
            }
            lastFetchKey = ""
            await refreshVisibleCells(for: visibleRegion)
        }
        .sheet(item: $selectedCell) { cell in
            TerritoryCellDetailSheet(
                cell: cell,
                onViewProfile: { userId in
                    selectedCell = nil
                    profileUserId = userId
                    showProfile = true
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
        .fullScreenCover(isPresented: $showProfile) {
            if let userId = profileUserId {
                NavigationStack {
                    ProfileView(userId: userId)
                        .gradientBG()
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button("Close") {
                                    showProfile = false
                                    profileUserId = nil
                                }
                            }
                        }
                }
            }
        }
    }

    private static func region(around coordinate: CLLocationCoordinate2D?) -> MKCoordinateRegion {
        guard let coordinate else { return defaultRegion }
        return MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.12, longitudeDelta: 0.12)
        )
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
            maxLon: maxLon
        )
        await MainActor.run {
            cells = rows
            loading = false
        }
    }
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
