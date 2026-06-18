import SwiftUI

struct PetCombatVictoryCard: View {
    let result: PetCombatResult
    let currentUserId: UUID
    let onDismiss: () -> Void

    private var didWin: Bool {
        result.winnerUserId == currentUserId
    }

    private var rewards: PetCombatRewards {
        result.attackerRewards
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(result.battleLog.result.isDraw ? "Draw" : (didWin ? "Victory" : "Defeat"))
                    .font(.subheadline.weight(.bold))
                if rewards.xp > 0 || rewards.coins > 0 {
                    Text("+\(rewards.xp) XP · +\(rewards.coins) coins")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No rewards this time.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let energy = result.energy {
                    Text("Energy \(energy.current)/\(energy.max)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            Button("Done", action: onDismiss)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct PetCombatOutcomeBadge: View {
    enum Style {
        case victory
        case defeat
        case draw
    }

    let style: Style

    var body: some View {
        HStack(spacing: 4) {
            if style == .victory {
                Image(systemName: "crown.fill")
                    .font(.caption2)
            }
            Text(label)
                .font(.caption.weight(.bold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(backgroundColor, in: Capsule())
        .foregroundStyle(foregroundColor)
        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
    }

    private var label: String {
        switch style {
        case .victory: return "Victory"
        case .defeat: return "Defeat"
        case .draw: return "Draw"
        }
    }

    private var backgroundColor: Color {
        switch style {
        case .victory: return Color(hex: "#FACC15").opacity(0.95)
        case .defeat: return Color(hex: "#475569").opacity(0.92)
        case .draw: return Color.orange.opacity(0.85)
        }
    }

    private var foregroundColor: Color {
        switch style {
        case .victory: return Color(hex: "#713F12")
        case .defeat: return .white
        case .draw: return .white
        }
    }
}

private extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
