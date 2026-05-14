import SwiftUI

struct TerritoryCityPickerButton: View {
    let selectedCity: TerritoryCityRegionRow?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("City")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(selectedCityLabel)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                Image(systemName: "magnifyingglass")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 0.8)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Choose territory city")
    }

    private var selectedCityLabel: String {
        guard let selectedCity else { return "Select city" }
        return TerritoryCaptureClient.citySummaryLabel(for: selectedCity)
    }
}

struct TerritoryCitySearchSheet: View {
    @Binding var selectedCityKey: String?
    let referenceLatitude: Double?
    let referenceLongitude: Double?
    let onSelect: (TerritoryCityRegionRow) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var cities: [TerritoryCityRegionRow] = []
    @State private var loading = true
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            GradientBackground()
            NavigationStack {
                Group {
                    if loading && cities.isEmpty {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if displayedCities.isEmpty {
                        ContentUnavailableView.search(text: searchText)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List {
                            if !recentCities.isEmpty && searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Section("Recent") {
                                    cityRows(recentCities)
                                }
                            }
                            if !ownedCities.isEmpty && searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Section("Your cities") {
                                    cityRows(ownedCities)
                                }
                            }
                            Section(recentCities.isEmpty && ownedCities.isEmpty ? "Cities" : "All cities") {
                                cityRows(displayedCities)
                            }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                    }
                }
                .navigationTitle("Choose city")
                .searchable(text: $searchText, prompt: "Search cities")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
                    }
                }
            }
        }
        .presentationBackground(.clear)
        .task {
            await loadCities(query: nil)
            TerritoryCaptureClient.refreshPendingTerritoryCityRegionsInBackground { updated in
                cities = updated
            }
        }
        .onChange(of: searchText) { _, newValue in
            searchTask?.cancel()
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.count < 2 {
                searchTask = Task {
                    await loadCities(query: nil)
                }
                return
            }
            searchTask = Task {
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard !Task.isCancelled else { return }
                await loadCities(query: trimmed)
            }
        }
    }

    private var displayedCities: [TerritoryCityRegionRow] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count < 2 {
            return cities
        }
        return TerritoryCaptureClient.filterTerritoryCities(cities, query: trimmed)
    }

    private var recentCities: [TerritoryCityRegionRow] {
        let keys = TerritoryCaptureClient.recentTerritoryCityKeys()
        return keys.compactMap { key in cities.first { $0.city_key == key } }
    }

    private var ownedCities: [TerritoryCityRegionRow] {
        cities.filter { ($0.my_owned_cells ?? 0) > 0 }
    }

    @ViewBuilder
    private func cityRows(_ rows: [TerritoryCityRegionRow]) -> some View {
        ForEach(rows) { city in
            Button {
                selectedCityKey = city.city_key
                TerritoryCaptureClient.recordRecentTerritoryCityKey(city.city_key)
                onSelect(city)
                dismiss()
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(city.display_name ?? city.city_key ?? "City")
                            .foregroundStyle(.primary)
                        Text(TerritoryCaptureClient.citySummaryLabel(for: city))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if selectedCityKey == city.city_key {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }
            .listRowBackground(Color.clear)
        }
    }

    private func loadCities(query: String?) async {
        await MainActor.run { loading = true }
        let fetched = await TerritoryCaptureClient.fetchTerritoryCityRegions(
            query: query,
            ownedFirst: true
        )
        await MainActor.run {
            cities = fetched
            if selectedCityKey == nil {
                selectedCityKey = TerritoryCaptureClient.selectedTerritoryCity(
                    from: fetched,
                    preferredKey: nil,
                    referenceLatitude: referenceLatitude,
                    referenceLongitude: referenceLongitude
                )?.city_key
            }
            loading = false
        }
    }
}
