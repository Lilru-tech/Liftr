import SwiftUI

struct FeedFoodOverlay: View {
    let itemType: String
    let ownedQuantity: Int
    let onClose: () -> Void
    let onFeedSuccess: () -> Void

    @State private var isFeeding = false
    @State private var errorMessage: String?

    private let quantityOptions = [1, 5, 10, 25]

    var body: some View {
        VStack(spacing: 16) {
            AsyncImage(url: PetImageURLBuilder.marketItemURL(path: "market/\(itemType).png")) { phase in
                switch phase {
                case .empty:
                    ProgressView().frame(height: 120)
                case .success(let img):
                    img.resizable().scaledToFit().frame(height: 120)
                case .failure:
                    Image(systemName: "leaf.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                        .frame(height: 120)
                @unknown default:
                    EmptyView()
                }
            }

            Text(PetFoodItemType.displayName(for: itemType))
                .font(.title2.bold())

            Text("Owned: ×\(ownedQuantity)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            VStack(spacing: 8) {
                Text("Select quantity")
                    .font(.subheadline)
                HStack(spacing: 12) {
                    ForEach(quantityOptions, id: \.self) { qty in
                        Button("\(qty)") {
                            Task { await feed(quantity: qty) }
                        }
                        .accessibilityIdentifier("feed.overlay.qty.\(qty)")
                        .accessibilityLabel("Feed quantity \(qty)")
                        .disabled(qty > ownedQuantity || isFeeding)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                        .opacity(qty > ownedQuantity ? 0.4 : 1)
                    }
                }
            }

            if isFeeding {
                ProgressView()
            }

            Button("Close", action: onClose)
                .font(.subheadline)
                .accessibilityIdentifier("feed.overlay.close")
        }
        .padding(24)
        .frame(maxWidth: 340)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(radius: 12)
    }

    private func feed(quantity: Int) async {
        isFeeding = true
        defer { isFeeding = false }
        do {
            try await PetService.shared.feed(itemType: itemType, quantity: quantity)
            onFeedSuccess()
            onClose()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
