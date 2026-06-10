import Foundation

extension PetRarity {
    var sortOrder: Int {
        switch self {
        case .common: return 1
        case .uncommon: return 2
        case .rare: return 3
        case .epic: return 4
        case .legendary: return 5
        case .mythic: return 6
        }
    }

    var nextTier: PetRarity? {
        switch self {
        case .common: return .uncommon
        case .uncommon: return .rare
        case .rare: return .epic
        case .epic: return .legendary
        case .legendary: return .mythic
        case .mythic: return nil
        }
    }

    var upgradeCost: Int? {
        guard nextTier != nil else { return nil }
        return 1000 * Int(pow(2.0, Double(sortOrder - 1)))
    }

    var upgradeMarketImagePath: String? {
        guard let next = nextTier else { return nil }
        return "market/rarity_upgrade_\(rawValue)_to_\(next.rawValue).png"
    }

    var statMultiplier: Double {
        switch self {
        case .common: return 1.00
        case .uncommon: return 1.05
        case .rare: return 1.10
        case .epic: return 1.20
        case .legendary: return 1.35
        case .mythic: return 1.50
        }
    }

    var coinMultiplier: Double {
        switch self {
        case .common: return 1.00
        case .uncommon: return 1.10
        case .rare: return 1.25
        case .epic: return 1.50
        case .legendary: return 2.00
        case .mythic: return 3.00
        }
    }

    func formattedMultiplier(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}

struct RarityUpgradeResult: Decodable, Equatable {
    let petInstanceId: UUID
    let fromRarity: String
    let toRarity: String
    let cost: Int
    let fromStatMultiplier: Double
    let toStatMultiplier: Double
    let fromCoinMultiplier: Double
    let toCoinMultiplier: Double
    let purchaseId: UUID

    enum CodingKeys: String, CodingKey {
        case petInstanceId = "pet_instance_id"
        case fromRarity = "from_rarity"
        case toRarity = "to_rarity"
        case cost
        case fromStatMultiplier = "from_stat_multiplier"
        case toStatMultiplier = "to_stat_multiplier"
        case fromCoinMultiplier = "from_coin_multiplier"
        case toCoinMultiplier = "to_coin_multiplier"
        case purchaseId = "purchase_id"
    }
}
