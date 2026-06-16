import SwiftUI

struct PetMarketItemCard: View {
    let item: PetMarketItemRow
    let userCoins: Int
    var effectivePrice: Int? = nil
    var subtitle: String? = nil
    var imagePath: String? = nil
    let onTap: () -> Void

    private var displayPrice: Int { effectivePrice ?? item.price }
    private var displayImageURL: URL? {
        if let imagePath { return PetImageURLBuilder.marketItemURL(path: imagePath) }
        return item.imageURL
    }

    var body: some View {
        VStack(spacing: 6) {
            MarketItemImage(url: displayImageURL, size: 88)

            Text(item.displayName)
                .font(.caption.weight(.semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(height: subtitle == nil ? 32 : 20)
                .frame(maxWidth: .infinity)

            if let subtitle {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .frame(height: 12)
            }

            HStack(spacing: 4) {
                Image(systemName: "bitcoinsign.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.yellow)
                Text("\(displayPrice)")
                    .font(.footnote)
            }
            .foregroundStyle(displayPrice > userCoins ? .red : .green)
            .frame(height: 16)
        }
        .frame(width: 100, height: 168)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
        .accessibilityIdentifier("market.item.\(item.itemType)")
        .onTapGesture(perform: onTap)
    }
}
