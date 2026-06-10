import SwiftUI

struct PetCombatSummaryImage: View {
    let pet: PetCombatPetSummary
    var height: CGFloat = 120
    var padding: CGFloat = 0

    var body: some View {
        AsyncImage(url: pet.imageURL) { phase in
            switch phase {
            case .empty:
                ProgressView()
                    .frame(height: height)
            case .success(let image):
                image
                    .resizable()
                    .scaledToFit()
                    .padding(padding)
                    .frame(height: height)
            case .failure:
                Image(systemName: "pawprint.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                    .frame(height: height)
            @unknown default:
                EmptyView()
            }
        }
    }
}

struct PetCombatComparisonStats: View {
    let attackerName: String
    let defenderName: String
    let attackerStats: PetCombatStatsSummary
    let defenderStats: PetCombatStatsSummary
    let attackerLevel: Int
    let defenderLevel: Int

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(attackerName)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                Text("vs")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(defenderName)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
            }

            statCompareRow(label: "Level", left: attackerLevel, right: defenderLevel)
            statCompareRow(label: "Health", left: attackerStats.health, right: defenderStats.health)
            statCompareRow(label: "Strength", left: attackerStats.strength, right: defenderStats.strength)
            statCompareRow(label: "Defense", left: attackerStats.defense, right: defenderStats.defense)
            statCompareRow(label: "Speed", left: attackerStats.speed, right: defenderStats.speed)
            statCompareRow(label: "Intelligence", left: attackerStats.intelligence, right: defenderStats.intelligence)
            statCompareRow(label: "Agility", left: attackerStats.agility, right: defenderStats.agility)
            statCompareRow(label: "Stamina", left: attackerStats.stamina, right: defenderStats.stamina)
            statCompareRow(label: "Crit", left: attackerStats.criticalRate, right: defenderStats.criticalRate)
            statCompareRow(label: "Resistance", left: attackerStats.resistance, right: defenderStats.resistance)
            statCompareRow(label: "Explore", left: attackerStats.exploration, right: defenderStats.exploration)
            statCompareRow(label: "Happiness", left: attackerStats.happiness, right: defenderStats.happiness)
        }
    }

    private func statCompareRow(label: String, left: Int, right: Int) -> some View {
        HStack(spacing: 8) {
            Text("\(left)")
                .font(.caption2.monospacedDigit())
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(left >= right ? .primary : .secondary)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(width: 72)
            Text("\(right)")
                .font(.caption2.monospacedDigit())
                .frame(maxWidth: .infinity, alignment: .trailing)
                .foregroundStyle(right >= left ? .primary : .secondary)
        }
    }
}
