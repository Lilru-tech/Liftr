import SwiftUI

struct PetInventoryDisplayItem: Identifiable, Equatable {
    let itemType: String
    let displayName: String
    let description: String
    let imagePath: String?
    let quantity: Int
    let category: String

    var id: String { itemType }

    var imageURL: URL? { PetImageURLBuilder.marketItemURL(path: imagePath) }

    static func from(
        inventory: PetInventoryRow,
        catalog: [PetMarketItemRow]
    ) -> PetInventoryDisplayItem? {
        guard inventory.quantity > 0 else { return nil }
        let meta = catalog.first(where: { $0.itemType == inventory.itemType })
        return PetInventoryDisplayItem(
            itemType: inventory.itemType,
            displayName: meta?.displayName ?? PetFoodItemType.displayName(for: inventory.itemType),
            description: meta?.description ?? "",
            imagePath: meta?.imagePath ?? "market/\(inventory.itemType).png",
            quantity: inventory.quantity,
            category: meta?.category ?? PetMarketVisibility.inventoryCategory(for: inventory.itemType)
        )
    }
}

struct PetInventoryItemCard: View {
    let item: PetInventoryDisplayItem
    let onTap: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 6) {
                AsyncImage(url: item.imageURL) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .frame(width: 70, height: 70)
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(width: 70, height: 70)
                    case .failure:
                        Image(systemName: "photo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 70, height: 70)
                            .foregroundStyle(.secondary)
                    @unknown default:
                        EmptyView()
                    }
                }

                Text(item.displayName)
                    .font(.caption.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(height: 32)
                    .frame(maxWidth: .infinity)

                if item.quantity > 1 {
                    Text("×\(item.quantity)")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(height: 16)
                } else {
                    Color.clear.frame(height: 16)
                }
            }
            .frame(width: 100, height: 160)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
            .onTapGesture(perform: onTap)

            if item.quantity > 1 {
                Text("\(item.quantity)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue, in: Capsule())
                    .padding(6)
            }
        }
    }
}
