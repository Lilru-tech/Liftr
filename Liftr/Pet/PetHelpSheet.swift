import SwiftUI

struct PetHelpSheet: View {
    @State private var rarities: [PetRarityConfigRow] = []
    @State private var species: [PetTypeCatalogRow] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    private let gridColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading pet guide...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage {
                    VStack(spacing: 16) {
                        Text(errorMessage)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Retry") {
                            Task { await load() }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            Text("Pet information")
                                .font(.title2.weight(.semibold))

                            raritiesSection
                            speciesSection
                        }
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
            .padding(18)
            .navigationBarTitleDisplayMode(.inline)
        }
        .gradientBG()
        .task { await load() }
    }

    @ViewBuilder
    private var raritiesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rarities")
                .font(.headline)

            Text("Rolled when incubation starts. Higher tiers boost stat gains and hourly coin generation.")
                .font(.body)
                .foregroundStyle(.secondary)

            let totalWeight = max(1, rarities.reduce(0) { $0 + $1.dropWeight })

            ForEach(rarities) { row in
                rarityRow(row, totalWeight: totalWeight)
            }
        }
    }

    @ViewBuilder
    private func rarityRow(_ row: PetRarityConfigRow, totalWeight: Int) -> some View {
        let rarity = PetRarity(databaseValue: row.rarity) ?? .common
        let dropPercent = Double(row.dropWeight) / Double(totalWeight) * 100
        let upgradeCost = rarity.upgradeCost

        VStack(alignment: .leading, spacing: 8) {
            PetRarityBadge(rarity: rarity)

            VStack(alignment: .leading, spacing: 4) {
                Text("Drop chance: \(PetHelpFormatting.dropPercent(dropPercent))")
                Text("Stat multiplier: \(PetHelpFormatting.multiplier(row.statMultiplier))")
                Text("Coin multiplier: \(PetHelpFormatting.multiplier(row.coinMultiplier))")
                if let upgradeCost, let next = rarity.nextTier {
                    Text("Upgrade to \(next.displayName): \(PetHelpFormatting.coins(upgradeCost)) coins")
                } else {
                    Text("Max tier")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private var speciesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pet species")
                .font(.headline)
                .padding(.top, 6)

            Text("Species are chosen at random when you start incubation. You can reroll before hatch.")
                .font(.body)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: gridColumns, spacing: 12) {
                ForEach(species) { row in
                    speciesCard(row)
                }
            }
        }
    }

    @ViewBuilder
    private func speciesCard(_ row: PetTypeCatalogRow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let url = row.imageURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                    case .failure:
                        Image(systemName: "egg.fill")
                            .font(.title)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    default:
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 72)
            }

            Text(row.displayName.isEmpty ? row.name.petDisplayTitle : row.displayName)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)

            if !row.description.isEmpty {
                Text(row.description)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func load() async {
        isLoading = rarities.isEmpty && species.isEmpty
        errorMessage = nil
        do {
            async let rarityRows = PetService.shared.fetchRarityConfig()
            async let typeRows = PetService.shared.fetchPetTypeCatalog()
            rarities = try await rarityRows
            species = try await typeRows
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

private enum PetHelpFormatting {
    static func dropPercent(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded == rounded.rounded() {
            return "\(Int(rounded))%"
        }
        return String(format: "%.1f%%", rounded)
    }

    static func multiplier(_ value: Double) -> String {
        String(format: "%.2f×", value)
    }

    static func coins(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
