import Foundation

enum PetLogFilterCategory: String, CaseIterable, Identifiable {
    case feeding
    case levelUp = "level_up"
    case eggHatch = "egg_hatch"
    case evolution
    case rarityUpgrade = "rarity_upgrade"
    case passiveCoins = "passive_coins"
    case workoutBonus = "workout_bonus"
    case combat

    var id: String { rawValue }

    var label: String {
        switch self {
        case .feeding: return "Feeding & items"
        case .levelUp: return "Level up"
        case .eggHatch: return "Egg & hatch"
        case .evolution: return "Evolution"
        case .rarityUpgrade: return "Rarity upgrade"
        case .passiveCoins: return "Passive pet coins"
        case .workoutBonus: return "Workout bonus"
        case .combat: return "Combat"
        }
    }

    static func categoryKey(for eventType: String) -> String? {
        switch eventType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "fed", "item_used": return PetLogFilterCategory.feeding.rawValue
        case "level_up": return PetLogFilterCategory.levelUp.rawValue
        case "incubation_started", "hatched": return PetLogFilterCategory.eggHatch.rawValue
        case "evolution": return PetLogFilterCategory.evolution.rawValue
        case "rarity_upgrade": return PetLogFilterCategory.rarityUpgrade.rawValue
        case "coins_generated": return PetLogFilterCategory.passiveCoins.rawValue
        case "workout_pet_bonus": return PetLogFilterCategory.workoutBonus.rawValue
        case "combat": return PetLogFilterCategory.combat.rawValue
        default: return nil
        }
    }

    static func isVisible(eventType: String, disabledKeys: Set<String>) -> Bool {
        guard let key = categoryKey(for: eventType) else { return true }
        return !disabledKeys.contains(key)
    }

    static func filter(_ logs: [PetLog], disabledKeys: Set<String>) -> [PetLog] {
        logs.filter { isVisible(eventType: $0.eventType, disabledKeys: disabledKeys) }
    }
}

enum LogFilterPreferences {
    static let petDisabledStorageKey = "petLogDisabledCategories"
    static let coinDisabledStorageKey = "coinLogDisabledCategories"
    private static let separator = "\u{001F}"

    static func decodeDisabledCategories(_ raw: String) -> Set<String> {
        guard !raw.isEmpty else { return [] }
        return Set(raw.split(separator: Character(separator)).map(String.init).filter { !$0.isEmpty })
    }

    static func encodeDisabledCategories(_ keys: Set<String>) -> String {
        keys.sorted().joined(separator: separator)
    }
}
