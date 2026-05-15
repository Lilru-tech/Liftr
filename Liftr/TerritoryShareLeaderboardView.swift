import SwiftUI

struct TerritoryShareLeaderboardView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var app: AppState
    @State private var scope: LBScope = .global
    @State private var rows: [TerritoryShareLeaderRow] = []
    @State private var cities: [TerritoryCityRegionRow] = []
    @State private var selectedCityKey: String?
    @State private var loading = true
    @State private var pendingRefreshStarted = false
    @State private var cityPickerOpen = false
    @State private var showMap = false

    private let initialLatitude: Double?
    private let initialLongitude: Double?

    init(initialLatitude: Double? = nil, initialLongitude: Double? = nil) {
        self.initialLatitude = initialLatitude
        self.initialLongitude = initialLongitude
    }

    private var selectedCity: TerritoryCityRegionRow? {
        TerritoryCaptureClient.selectedTerritoryCity(
            from: cities,
            preferredKey: selectedCityKey,
            referenceLatitude: initialLatitude,
            referenceLongitude: initialLongitude
        )
    }

    private var canOpenSelectedCityOnMap: Bool {
        guard let cityKey = selectedCity?.city_key else { return false }
        return !TerritoryCaptureClient.isPendingTerritoryCityKey(cityKey)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                GradientBackground()
                VStack(spacing: 12) {
                    if cities.count > 1 {
                        TerritoryCityPickerButton(selectedCity: selectedCity) {
                            cityPickerOpen = true
                        }
                        .padding(.horizontal)
                    } else if let city = cities.first {
                        Text(TerritoryCaptureClient.citySummaryLabel(for: city))
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)
                    }

                    Picker("Scope", selection: $scope) {
                        ForEach(LBScope.allCases) { value in
                            Text(value.rawValue).tag(value)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

                    if loading {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if rows.isEmpty {
                        ContentUnavailableView("No territory yet", systemImage: "map")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List(rows) { row in
                            HStack(spacing: 12) {
                                Text("\(row.rank).")
                                    .font(.headline)
                                    .frame(width: 30, alignment: .trailing)
                                AvatarView(urlString: row.avatar_url)
                                    .frame(width: 36, height: 36)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(row.username.map { "@\($0)" } ?? "Unknown")
                                        .font(.subheadline.weight(.semibold))
                                    Text("\(row.owned_cells ?? 0) cells")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(shareLabel(for: row.territory_share_pct))
                                    .font(.headline)
                                    .monospacedDigit()
                            }
                            .listRowBackground(row.user_id == app.userId ? Color.white.opacity(0.12) : Color.clear)
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                    }
                }
            }
            .navigationTitle("Territory share")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if canOpenSelectedCityOnMap {
                        Button("View on map") {
                            showMap = true
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task(id: "\(scope.rawValue)|\(selectedCityKey ?? "")") {
                await loadLeaderboard()
            }
            .sheet(isPresented: $cityPickerOpen) {
                TerritoryCitySearchSheet(
                    selectedCityKey: $selectedCityKey,
                    referenceLatitude: initialLatitude,
                    referenceLongitude: initialLongitude
                ) { city in
                    selectedCityKey = city.city_key
                    Task { await loadLeaderboard() }
                }
                .presentationDetents([.medium, .large])
            }
            .fullScreenCover(isPresented: $showMap) {
                NavigationStack {
                    TerritoryMapView(
                        initialLatitude: selectedCity?.center_lat,
                        initialLongitude: selectedCity?.center_lon
                    )
                    .environmentObject(app)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Close") { showMap = false }
                        }
                    }
                }
            }
        }
        .presentationBackground(.clear)
    }

    private func loadLeaderboard() async {
        await MainActor.run { loading = true }
        let started = Date()
        let fetchedCities: [TerritoryCityRegionRow]
        if cities.isEmpty {
            fetchedCities = await TerritoryCaptureClient.fetchTerritoryCityRegions()
            let pendingCount = fetchedCities.filter { TerritoryCaptureClient.isPendingTerritoryCityKey($0.city_key) }.count
            let elapsedMs = Int(Date().timeIntervalSince(started) * 1000)
            TerritoryCaptureClient.logTerritoryShare("load cities count=\(fetchedCities.count) pending=\(pendingCount) elapsedMs=\(elapsedMs)")
        } else {
            fetchedCities = cities
        }
        let cityKey = await MainActor.run { () -> String? in
            cities = fetchedCities
            if selectedCityKey == nil {
                selectedCityKey = TerritoryCaptureClient.selectedTerritoryCity(
                    from: fetchedCities,
                    preferredKey: nil,
                    referenceLatitude: initialLatitude,
                    referenceLongitude: initialLongitude
                )?.city_key
            }
            return selectedCityKey ?? fetchedCities.first?.city_key
        }
        guard let cityKey, !cityKey.isEmpty else {
            TerritoryCaptureClient.logTerritoryShare("load leaderboard skipped missing cityKey")
            await MainActor.run {
                rows = []
                loading = false
            }
            return
        }
        TerritoryCaptureClient.recordRecentTerritoryCityKey(cityKey)
        let leaderboardStarted = Date()
        let scopeValue = scope == .global ? "global" : "friends"
        let fetched = await TerritoryCaptureClient.fetchTerritoryCityShareLeaderboard(
            cityKey: cityKey,
            scope: scopeValue
        )
        let leaderboardElapsedMs = Int(Date().timeIntervalSince(leaderboardStarted) * 1000)
        TerritoryCaptureClient.logTerritoryShare("load leaderboard cityKey=\(cityKey) scope=\(scopeValue) rows=\(fetched.count) elapsedMs=\(leaderboardElapsedMs)")
        await MainActor.run {
            rows = fetched
            loading = false
        }
        if !pendingRefreshStarted,
           fetchedCities.contains(where: { TerritoryCaptureClient.isPendingTerritoryCityKey($0.city_key) }) {
            pendingRefreshStarted = true
            TerritoryCaptureClient.refreshPendingTerritoryCityRegionsInBackground { updated in
                let pendingCount = updated.filter { TerritoryCaptureClient.isPendingTerritoryCityKey($0.city_key) }.count
                TerritoryCaptureClient.logTerritoryShare("background cities count=\(updated.count) pending=\(pendingCount)")
                cities = updated
            }
        }
    }

    private func shareLabel(for value: Double?) -> String {
        guard let value else { return "0%" }
        return String(format: "%.2f%%", value)
    }
}
