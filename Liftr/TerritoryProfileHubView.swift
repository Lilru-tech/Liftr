import SwiftUI

struct TerritoryProfileHubView: View {
    let profileUserId: UUID
    let isOwnProfile: Bool

    @State private var summary: TerritorySummaryResponse?
    @State private var cities: [TerritoryCityRegionRow] = []
    @State private var takeovers: [TerritoryRecentTakeoverRow] = []
    @State private var loading = true

    private var topCities: [TerritoryCityRegionRow] {
        cities
            .filter { ownedCells(for: $0) > 0 }
            .sorted { ownedCells(for: $0) > ownedCells(for: $1) }
            .prefix(3)
            .map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Territory")
                    .font(.headline)
                Spacer()
                NavigationLink {
                    TerritoryMapView()
                } label: {
                    Text("Open map")
                        .font(.subheadline.weight(.semibold))
                }
            }

            if loading {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if let summary {
                Text(summaryLine(summary))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if topCities.isEmpty {
                    Text(emptyTerritoryMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(topCities) { city in
                        Text(TerritoryCaptureClient.citySummaryLabel(for: city))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if !takeovers.isEmpty {
                    Text("Recent takeovers")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                    ForEach(takeovers) { takeover in
                        Text(takeoverSummary(takeover))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("Territory summary is unavailable right now.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal)
        .task(id: profileUserId) {
            loading = true
            if isOwnProfile {
                async let summaryLoad = TerritoryCaptureClient.fetchTerritorySummary(userId: nil)
                async let citiesLoad = TerritoryCaptureClient.fetchTerritoryCityRegions()
                async let takeoversLoad = TerritoryCaptureClient.fetchRecentTakeovers(userId: nil, limit: 3)
                summary = await summaryLoad
                cities = await citiesLoad
                takeovers = await takeoversLoad
            } else {
                async let summaryLoad = TerritoryCaptureClient.fetchTerritorySummary(userId: profileUserId)
                async let citiesLoad = TerritoryCaptureClient.fetchUserTerritoryTopCities(userId: profileUserId)
                async let takeoversLoad = TerritoryCaptureClient.fetchRecentTakeovers(userId: profileUserId, limit: 3)
                summary = await summaryLoad
                cities = await citiesLoad
                takeovers = await takeoversLoad
            }
            loading = false
        }
    }

    private var emptyTerritoryMessage: String {
        if isOwnProfile {
            return "Finish an outdoor GPS cardio workout to start capturing territory."
        }
        return "This athlete has not captured any territory yet."
    }

    private func summaryLine(_ summary: TerritorySummaryResponse) -> String {
        let total = summary.total_cells ?? 0
        let week = summary.cells_last_7d ?? 0
        if isOwnProfile {
            return "You own \(total) cells · \(week) captured in the last 7 days"
        }
        return "Owns \(total) cells · \(week) captured in the last 7 days"
    }

    private func ownedCells(for city: TerritoryCityRegionRow) -> Int {
        city.my_owned_cells ?? city.owned_cells ?? 0
    }

    private func takeoverSummary(_ takeover: TerritoryRecentTakeoverRow) -> String {
        let username = takeover.other_username ?? "user"
        let cells = takeover.cells_taken ?? 0
        let share = takeover.share_taken_pct ?? 0
        return "Took \(cells) cells (\(share)% of @\(username))"
    }
}
