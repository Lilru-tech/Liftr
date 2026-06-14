import SwiftUI

struct PetRarityGuideSection: View {
    let rarities: [PetRarityConfigRow]
    @State private var isExpanded = false

    private var totalWeight: Int {
        max(1, rarities.reduce(0) { $0 + $1.dropWeight })
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Rolled when incubation starts. Higher tiers boost stat gains and hourly coin generation.")
                    .font(.body)
                    .foregroundStyle(.secondary)

                ForEach(rarities) { row in
                    PetRarityGuideRow(row: row, totalWeight: totalWeight)
                }
            }
            .padding(.top, 8)
        } label: {
            Text("Rarities")
                .font(.headline)
        }
    }
}

struct PetRarityGuideRow: View {
    let row: PetRarityConfigRow
    let totalWeight: Int

    var body: some View {
        let rarity = PetRarity(databaseValue: row.rarity) ?? .common
        let dropPercent = Double(row.dropWeight) / Double(totalWeight) * 100
        let upgradeCost = rarity.upgradeCost

        VStack(alignment: .leading, spacing: 8) {
            PetRarityBadge(rarity: rarity)

            VStack(alignment: .leading, spacing: 4) {
                Text("Drop chance: \(PetRarityFormatting.dropPercent(dropPercent))")
                Text("Stat multiplier: \(PetRarityFormatting.multiplier(row.statMultiplier))")
                Text("Coin multiplier: \(PetRarityFormatting.multiplier(row.coinMultiplier))")
                if let upgradeCost, let next = rarity.nextTier {
                    Text("Upgrade to \(next.displayName): \(PetRarityFormatting.coins(upgradeCost)) coins")
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
}

enum PetRarityFormatting {
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
