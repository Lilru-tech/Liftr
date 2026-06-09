import Foundation

struct PetMarketItemPresentation {
    let effectivePrice: Int
    let subtitle: String?
    let imagePath: String?

    static func make(item: PetMarketItemRow, petData: PetFullData?) -> PetMarketItemPresentation {
        guard item.itemType == "pet_rarity_upgrade",
              let pet = petData?.pet,
              let current = PetRarity(databaseValue: pet.rarity),
              let next = current.nextTier,
              let cost = current.upgradeCost else {
            return PetMarketItemPresentation(effectivePrice: item.price, subtitle: nil, imagePath: item.imagePath)
        }
        return PetMarketItemPresentation(
            effectivePrice: cost,
            subtitle: "\(current.displayName) → \(next.displayName)",
            imagePath: current.upgradeMarketImagePath ?? item.imagePath
        )
    }

    var imageURL: URL? {
        PetImageURLBuilder.marketItemURL(path: imagePath)
    }

    static func modalTitle(item: PetMarketItemRow, petData: PetFullData?) -> String {
        guard item.itemType == "pet_rarity_upgrade",
              let pet = petData?.pet,
              let current = PetRarity(databaseValue: pet.rarity),
              let next = current.nextTier else {
            return item.displayName
        }
        return "Upgrade your pet from \(current.displayName) to \(next.displayName)"
    }
}
