import SwiftUI

enum PetCombatHpBarStyle {
    static func color(for ratio: Double) -> Color {
        let percent = ratio * 100
        switch percent {
        case 80...: return Color(hex: "#22C55E")
        case 60..<80: return Color(hex: "#EAB308")
        case 40..<60: return Color(hex: "#F97316")
        case 20..<40: return Color(hex: "#EF4444")
        default: return Color(hex: "#991B1B")
        }
    }
}

struct PetCombatHpBar: View {
    let current: Int
    let maxHp: Int

    private var safeMax: Int { max(maxHp, 1) }
    private var ratio: Double { min(1, max(0, Double(current) / Double(safeMax))) }

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.18))
                    Capsule()
                        .fill(PetCombatHpBarStyle.color(for: ratio))
                        .frame(width: geo.size.width * ratio)
                }
            }
            .frame(height: 8)

            Text("\(current)/\(safeMax) HP")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .animation(.easeInOut(duration: 0.35), value: current)
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
