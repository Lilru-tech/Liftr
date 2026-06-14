import SwiftUI

struct PetCombatRecordsSection: View {
    var showsHeader: Bool = true

    @State private var stats: PetCombatUserStats?
    @State private var isLoading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsHeader {
                Text("Arena Records")
                    .font(.subheadline.weight(.semibold))
            }

            if isLoading {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Loading records…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if let stats, stats.totalBattles > 0 {
                recordsGrid(stats)
            } else {
                Text("No arena battles yet. Challenge a friend's pet!")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task { await load() }
    }

    @ViewBuilder
    private func recordsGrid(_ stats: PetCombatUserStats) -> some View {
        let pairs: [(String, String)] = [
            ("Battles", "\(stats.totalBattles) (\(stats.wins)W-\(stats.losses)L-\(stats.draws)D)"),
            ("Win streak", "\(stats.currentWinStreak) (best \(stats.bestWinStreak))"),
            ("Max hit dealt", "\(stats.maxDamageDealt)"),
            ("Max hit taken", "\(stats.maxDamageTaken)"),
            ("Total dmg dealt", "\(stats.totalDamageDealt)"),
            ("Total dmg taken", "\(stats.totalDamageTaken)"),
            ("Crits landed", "\(stats.critsLanded)"),
            ("Dodges", "\(stats.dodgesPerformed)"),
            ("Longest battle", "\(stats.longestBattleTurns) turns")
        ]
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            ForEach(pairs, id: \.0) { label, value in
                HStack {
                    Text(label).font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    Text(value).font(.caption.weight(.semibold))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func load() async {
        defer { isLoading = false }
        stats = try? await PetService.shared.fetchCombatUserStats()
    }
}
