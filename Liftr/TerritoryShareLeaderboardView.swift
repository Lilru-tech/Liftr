import SwiftUI

struct TerritoryShareLeaderboardView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var scope: LBScope = .global
    @State private var rows: [TerritoryShareLeaderRow] = []
    @State private var cities: [TerritoryCityRegionRow] = []
    @State private var selectedCityKey: String?
    @State private var loading = true

    private let initialLatitude: Double?
    private let initialLongitude: Double?

    init(initialLatitude: Double? = nil, initialLongitude: Double? = nil) {
        self.initialLatitude = initialLatitude
        self.initialLongitude = initialLongitude
    }

    var body: some View {
        NavigationStack {
            ZStack {
                GradientBackground()
                VStack(spacing: 12) {
                    if cities.count > 1 {
                        Picker("City", selection: Binding(
                            get: {
                                selectedCityKey
                                    ?? cities.first?.city_key
                                    ?? cities.first?.id
                                    ?? ""
                            },
                            set: { selectedCityKey = $0 }
                        )) {
                            ForEach(cities) { city in
                                Text(TerritoryCaptureClient.citySummaryLabel(for: city))
                                    .tag(city.city_key ?? city.id)
                            }
                        }
                        .pickerStyle(.menu)
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
                            .listRowBackground(Color.clear)
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                    }
                }
            }
            .navigationTitle("Territory share")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task(id: "\(scope.rawValue)|\(selectedCityKey ?? "")") {
                await loadLeaderboard()
            }
        }
        .presentationBackground(.clear)
    }

    private func loadLeaderboard() async {
        await MainActor.run { loading = true }
        let fetchedCities = await TerritoryCaptureClient.fetchTerritoryCityRegions()
        let cityKey = await MainActor.run { () -> String? in
            cities = fetchedCities
            if selectedCityKey == nil {
                if let initialLatitude, let initialLongitude {
                    selectedCityKey = TerritoryCaptureClient.nearestCityKey(
                        to: initialLatitude,
                        longitude: initialLongitude,
                        from: fetchedCities
                    )
                }
                if selectedCityKey == nil {
                    selectedCityKey = fetchedCities.first?.city_key
                }
            }
            return selectedCityKey ?? fetchedCities.first?.city_key
        }
        guard let cityKey, !cityKey.isEmpty else {
            await MainActor.run {
                rows = []
                loading = false
            }
            return
        }
        let scopeValue = scope == .global ? "global" : "friends"
        let fetched = await TerritoryCaptureClient.fetchTerritoryCityShareLeaderboard(
            cityKey: cityKey,
            scope: scopeValue
        )
        await MainActor.run {
            rows = fetched
            loading = false
        }
    }

    private func shareLabel(for value: Double?) -> String {
        guard let value else { return "0%" }
        return String(format: "%.2f%%", value)
    }
}
