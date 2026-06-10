import SwiftUI

struct PetEnergyBadge: View {
    let energy: ProfileEnergy
    var label: String? = nil
    var alignment: HorizontalAlignment = .leading

    var body: some View {
        VStack(alignment: alignment, spacing: 2) {
            if let label {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Label("\(energy.current)/\(energy.max)", systemImage: "bolt.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
            if energy.isFull {
                Text("Full")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if let next = energy.nextRefreshAt {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text("+1 in \(Self.countdownText(from: context.date, to: next))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
    }

    static func countdownText(from now: Date, to target: Date) -> String {
        let remaining = Swift.max(0, Int(target.timeIntervalSince(now)))
        let hours = remaining / 3600
        let minutes = (remaining % 3600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m" }
        return "<1m"
    }
}
