import SwiftUI

struct PetCombatHeadToHeadSummaryView: View {
    let summary: PetCombatHeadToHeadSummary
    let opponentUsername: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(recordTitle)
                .font(.subheadline.weight(.semibold))

            if let last = summary.lastBattle {
                Text(lastBattleText(last))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var recordTitle: String {
        let name = opponentUsername.map { "@\($0)" } ?? "this opponent"
        return "Record vs \(name): \(summary.wins)W · \(summary.losses)L · \(summary.draws)D (\(summary.winRatePercentText))"
    }

    private func lastBattleText(_ last: PetCombatHeadToHeadLastBattle) -> String {
        let outcome: String
        if last.isDraw {
            outcome = "Draw"
        } else if last.won {
            outcome = "Victory"
        } else {
            outcome = "Defeat"
        }

        var parts = ["Last: \(outcome)"]
        if let rewards = last.rewards, (rewards.xp > 0 || rewards.coins > 0) {
            parts.append("+\(rewards.xp) XP")
            if rewards.coins > 0 {
                parts.append("+\(rewards.coins) coins")
            }
        }
        if let createdAt = last.createdAt {
            parts.append(createdAt.formatted(date: .abbreviated, time: .omitted))
        }
        return parts.joined(separator: " · ")
    }
}
