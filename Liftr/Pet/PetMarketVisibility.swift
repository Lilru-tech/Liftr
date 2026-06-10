import Foundation

enum PetMarketVisibility {
    static func inventoryQuantity(_ inventory: [PetInventoryRow], itemType: String) -> Int {
        inventory.first(where: { $0.itemType == itemType })?.quantity ?? 0
    }

    static func shouldShowMarketItem(
        _ item: PetMarketItemRow,
        petData: PetFullData?
    ) -> Bool {
        let hasPet = petData?.pet != nil
        let inventory = petData?.inventory ?? []

        switch item.itemType {
        case "pet_egg":
            return !hasPet && inventoryQuantity(inventory, itemType: "pet_egg") == 0
        case "incubator":
            return !hasPet && inventoryQuantity(inventory, itemType: "incubator") == 0
        case "pet_rarity_upgrade":
            guard let pet = petData?.pet,
                  let rarity = PetRarity(databaseValue: pet.rarity),
                  rarity != .mythic else { return false }
            return true
        case "pet_energy_capacity":
            guard let energy = petData?.energy else { return true }
            return energy.max < PetEnergyPricing.maxCapacity
        default:
            if PetFoodItemType.all.contains(item.itemType) {
                return hasPet
            }
            return true
        }
    }

    static func inventoryCategory(for itemType: String) -> String {
        switch itemType {
        case "pet_egg", "incubator":
            return "eggs_devices"
        default:
            return "pet_food"
        }
    }

    static func categoryTitle(_ category: String) -> String {
        switch category {
        case "eggs_devices": return "Eggs & Devices"
        case "pet_food": return "Pet Food"
        case "pet_upgrades": return "Pet Upgrades"
        default: return category.capitalized
        }
    }

    static func hasIncubator(_ inventory: [PetInventoryRow]) -> Bool {
        inventoryQuantity(inventory, itemType: "incubator") > 0
    }

    static func canIncubate(petData: PetFullData?) -> Bool {
        guard petData?.pet == nil else { return false }
        let inventory = petData?.inventory ?? []
        return inventoryQuantity(inventory, itemType: "pet_egg") > 0
            && inventoryQuantity(inventory, itemType: "incubator") > 0
    }
}
