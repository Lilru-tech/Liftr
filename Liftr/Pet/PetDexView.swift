import SwiftUI

struct PetDexView: View {
    @State private var dexData: PetDexData?
    @State private var rarities: [PetRarityConfigRow] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var searchText = ""
    @State private var selectedSpecies: PetDexSpeciesEntry?

    private let gridColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    private var filteredSpecies: [PetDexSpeciesEntry] {
        let all = dexData?.species ?? []
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return all }
        return all.filter { row in
            row.displayName.lowercased().contains(query)
                || row.petType.lowercased().contains(query)
                || row.description.lowercased().contains(query)
        }
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading Pet Dex...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage {
                VStack(spacing: 16) {
                    Text(errorMessage)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Retry") {
                        Task { await load() }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(24)
            } else if let dexData {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        summaryHeader(dexData)
                        if !rarities.isEmpty {
                            PetRarityGuideSection(rarities: rarities)
                        }
                        searchBar

                        if filteredSpecies.isEmpty {
                            Text("No species match your search.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            LazyVGrid(columns: gridColumns, spacing: 12) {
                                ForEach(filteredSpecies) { row in
                                    Button {
                                        selectedSpecies = row
                                    } label: {
                                        dexSpeciesCard(row)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(16)
                }
            }
        }
        .task { await load() }
        .sheet(item: $selectedSpecies) { row in
            PetSpeciesDetailSheet(petType: row.petType, showsDexStats: true)
                .presentationDetents([.large])
                .presentationBackground(.clear)
        }
    }

    @ViewBuilder
    private func summaryHeader(_ data: PetDexData) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(data.speciesDiscovered) of \(data.totalSpecies) species fought")
                .font(.headline)
            Text("Rarities: \(data.raritiesDiscovered)/\(data.totalRarities) · Stages: \(data.stagesDiscovered)/\(data.totalFightableStages)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search species", text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.08)))
    }

    @ViewBuilder
    private func dexSpeciesCard(_ row: PetDexSpeciesEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                if row.isDiscovered, let url = row.eggImageURL {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFit()
                        default:
                            Image(systemName: "pawprint.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(height: 72)
                } else {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.black.opacity(0.45))
                        .frame(height: 72)
                        .overlay {
                            Text("???")
                                .font(.title3.weight(.bold))
                                .foregroundStyle(.white.opacity(0.75))
                        }
                }
            }

            Text(row.isDiscovered
                 ? (row.displayName.isEmpty ? row.petType.petDisplayTitle : row.displayName)
                 : "???")
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .foregroundStyle(row.isDiscovered ? .primary : .secondary)

            if row.isDiscovered {
                Text("\(row.totalBattles) battles · \(row.wins)W-\(row.losses)L-\(row.draws)D")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func load() async {
        isLoading = dexData == nil
        errorMessage = nil
        do {
            async let dex = PetService.shared.fetchMyPetDex()
            async let rarityRows = PetService.shared.fetchRarityConfig()
            dexData = try await dex
            rarities = try await rarityRows
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
