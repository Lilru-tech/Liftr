import SwiftUI

struct CoinsBalanceBadge: View {
    let balance: Int
    var compact: Bool = false
    var onTap: (() -> Void)? = nil

    private var displayBalance: Int {
        max(0, balance)
    }

    var body: some View {
        let content = Label {
            Text("\(displayBalance)")
                .font(compact ? .caption2.weight(.bold) : .caption.weight(.semibold))
                .monospacedDigit()
        } icon: {
            Image(systemName: "bitcoinsign.circle.fill")
                .font(compact ? .caption2 : .caption)
                .foregroundStyle(Color.yellow.opacity(0.95))
        }
        .labelStyle(.titleAndIcon)
        .padding(.vertical, compact ? 3 : 4)
        .padding(.horizontal, compact ? 6 : 8)
        .background(Capsule().fill(Color.white.opacity(0.12)))
        .overlay(Capsule().stroke(Color.white.opacity(0.12)))
        .foregroundStyle(.primary)
        .accessibilityLabel("Liftr Coins balance \(displayBalance)")

        if let onTap {
            Button(action: onTap) { content }
                .buttonStyle(.plain)
        } else {
            content
        }
    }
}
