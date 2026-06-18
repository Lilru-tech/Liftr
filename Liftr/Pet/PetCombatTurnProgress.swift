import SwiftUI

struct PetCombatTurnProgress: View {
    let currentTurn: Int
    let totalTurns: Int

    private var progress: Double {
        guard totalTurns > 0 else { return 0 }
        return min(Double(max(currentTurn, 0)) / Double(totalTurns), 1)
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text("Turn \(max(currentTurn, 0)) / \(totalTurns)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.12))
                    Capsule()
                        .fill(Color.orange.opacity(0.85))
                        .frame(width: geo.size.width * progress)
                }
            }
            .frame(width: 88, height: 4)
            .animation(.easeOut(duration: 0.35), value: progress)
        }
    }
}
