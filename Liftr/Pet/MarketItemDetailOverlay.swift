import SwiftUI

struct MarketItemDetailOverlay: View {
    let item: PetMarketItemRow
    let userCoins: Int
    let onClose: () -> Void
    let onPurchaseSuccess: () -> Void

    @State private var isBuying = false
    @State private var errorMessage: String?

    private var isFood: Bool { PetFoodItemType.all.contains(item.itemType) }

    var body: some View {
        VStack(spacing: 16) {
            AsyncImage(url: item.imageURL) { phase in
                switch phase {
                case .empty:
                    ProgressView().frame(height: 120)
                case .success(let img):
                    img.resizable().scaledToFit().frame(height: 120)
                case .failure:
                    Image(systemName: "photo")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                        .frame(height: 120)
                @unknown default:
                    EmptyView()
                }
            }

            Text(item.displayName)
                .font(.title2.bold())

            Text(item.description)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            HStack(spacing: 4) {
                Text("Price: \(item.price)")
                Image(systemName: "bitcoinsign.circle.fill")
                    .foregroundStyle(.yellow)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(item.price > userCoins ? .red : .green)

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            if isFood {
                VStack(spacing: 8) {
                    Text("Select quantity")
                        .font(.subheadline)
                    HStack(spacing: 12) {
                        ForEach([1, 5, 10, 25], id: \.self) { qty in
                            Button("\(qty)") {
                                Task { await purchase(quantity: qty) }
                            }
                            .disabled(item.price * qty > userCoins || isBuying)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            } else {
                Button {
                    Task { await purchase(quantity: 1) }
                } label: {
                    HStack {
                        if isBuying { ProgressView().controlSize(.small) }
                        Text("Buy")
                            .font(.body.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(item.price > userCoins || isBuying)
            }

            Button("Close", action: onClose)
                .font(.subheadline)
        }
        .padding(24)
        .frame(maxWidth: 340)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(radius: 12)
    }

    private func purchase(quantity: Int) async {
        isBuying = true
        defer { isBuying = false }
        do {
            try await PetService.shared.buyItem(itemType: item.itemType, quantity: quantity)
            onPurchaseSuccess()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
