import Foundation

struct PetInstanceRow: Codable, Equatable {
    let id: UUID
    let userId: UUID
    let petType: String
    let customName: String?
    let evolutionStage: String
    let currentXp: Int
    let currentLevel: Int
    let rarity: String
    let hatchAt: Date?
    let isEquipped: Bool
    let isActive: Bool
    let rerollCount: Int
    let totalFeedings: Int
    let imageUrl: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case petType = "pet_type"
        case customName = "custom_name"
        case evolutionStage = "evolution_stage"
        case currentXp = "current_xp"
        case currentLevel = "current_level"
        case rarity
        case hatchAt = "hatch_at"
        case isEquipped = "is_equipped"
        case isActive = "is_active"
        case rerollCount = "reroll_count"
        case totalFeedings = "total_feedings"
        case imageUrl = "image_url"
    }

    var rarityEnum: PetRarity { PetRarity(databaseValue: rarity) ?? .common }

    var imageURL: URL? {
        if let imageUrl, !imageUrl.isEmpty, let url = URL(string: imageUrl) {
            return url
        }
        return PetImageURLBuilder.imageURL(petType: petType, evolutionStage: evolutionStage)
    }

    var imageURLCandidates: [URL] {
        var urls: [URL] = []
        if let primary = imageURL {
            urls.append(primary)
        }
        for candidate in PetImageURLBuilder.imageURLCandidates(petType: petType, evolutionStage: evolutionStage) {
            if !urls.contains(candidate) {
                urls.append(candidate)
            }
        }
        return urls
    }

    var displayTitle: String {
        if let customName, !customName.isEmpty { return customName }
        return petType.replacingOccurrences(of: "_", with: " ").capitalized
    }

    var isIncubatingEgg: Bool {
        evolutionStage.lowercased() == "egg" && (hatchAt ?? .distantPast) > Date()
    }

    var isPendingHatch: Bool {
        evolutionStage.lowercased() == "egg" && hatchAt != nil && (hatchAt ?? .distantPast) <= Date()
    }

    var isEggStage: Bool {
        evolutionStage.lowercased() == "egg"
    }
}

enum PetRerollPricing {
    static func cost(rerollCount: Int) -> Int {
        Int(floor(50 * pow(1.1, Double(rerollCount))))
    }
}

extension String {
    var petDisplayTitle: String {
        replacingOccurrences(of: "_", with: " ").capitalized
    }
}

struct PetStatsRow: Codable, Equatable {
    let petInstanceId: UUID
    let health: Int
    let strength: Int
    let defense: Int
    let speed: Int
    let intelligence: Int
    let agility: Int
    let stamina: Int
    let criticalRate: Int
    let resistance: Int
    let exploration: Int
    let happiness: Int

    enum CodingKeys: String, CodingKey {
        case petInstanceId = "pet_instance_id"
        case health, strength, defense, speed, intelligence, agility, stamina
        case criticalRate = "critical_rate"
        case resistance, exploration, happiness
    }
}

struct PetInventoryRow: Codable, Equatable, Identifiable {
    let id: UUID
    let userId: UUID
    let itemType: String
    let quantity: Int

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case itemType = "item_type"
        case quantity
    }
}

struct PetFullData: Codable, Equatable {
    let pet: PetInstanceRow?
    let stats: PetStatsRow?
    let inventory: [PetInventoryRow]
    let xpRequired: Int
    let canEvolve: Bool
    let energy: ProfileEnergy?

    enum CodingKeys: String, CodingKey {
        case pet, stats, inventory
        case xpRequired = "xp_required"
        case canEvolve = "can_evolve"
        case energy
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if c.contains(.pet), !(try c.decodeNil(forKey: .pet)) {
            pet = try? c.decode(PetInstanceRow.self, forKey: .pet)
        } else {
            pet = nil
        }
        stats = try c.decodeIfPresent(PetStatsRow.self, forKey: .stats)
        inventory = try c.decodeIfPresent([PetInventoryRow].self, forKey: .inventory) ?? []
        xpRequired = try c.decodeIfPresent(Int.self, forKey: .xpRequired) ?? 0
        canEvolve = try c.decodeIfPresent(Bool.self, forKey: .canEvolve) ?? false
        energy = try c.decodeIfPresent(ProfileEnergy.self, forKey: .energy)
    }
}

struct PetMarketItemRow: Codable, Identifiable, Equatable {
    let itemType: String
    let displayName: String
    let description: String
    let price: Int
    let category: String
    let imagePath: String?
    let isActive: Bool

    var id: String { itemType }

    enum CodingKeys: String, CodingKey {
        case itemType = "item_type"
        case displayName = "display_name"
        case description, price, category
        case imagePath = "image_path"
        case isActive = "is_active"
    }

    var imageURL: URL? { PetImageURLBuilder.marketItemURL(path: imagePath) }
}

struct PetRarityConfigRow: Codable, Identifiable, Equatable {
    let rarity: String
    let displayName: String
    let colorHex: String
    let dropWeight: Int
    let coinMultiplier: Double
    let statMultiplier: Double
    let sortOrder: Int

    var id: String { rarity }

    enum CodingKeys: String, CodingKey {
        case rarity
        case displayName = "display_name"
        case colorHex = "color_hex"
        case dropWeight = "drop_weight"
        case coinMultiplier = "coin_multiplier"
        case statMultiplier = "stat_multiplier"
        case sortOrder = "sort_order"
    }
}

struct PetTypeCatalogRow: Codable, Identifiable, Equatable {
    let name: String
    let displayName: String
    let description: String
    let imageEgg: String?

    var id: String { name }

    enum CodingKeys: String, CodingKey {
        case name
        case displayName = "display_name"
        case description
        case imageEgg = "image_egg"
    }

    var imageURL: URL? {
        if let imageEgg, !imageEgg.isEmpty, let url = URL(string: imageEgg) {
            return url
        }
        return PetImageURLBuilder.imageURL(petType: name, evolutionStage: "egg")
    }
}

struct PetDexStats: Codable, Equatable {
    let totalBattles: Int
    let wins: Int
    let losses: Int
    let draws: Int
    let firstFoughtAt: Date?
    let lastFoughtAt: Date?
    let raritiesSeen: [String]
    let stagesSeen: [String]

    enum CodingKeys: String, CodingKey {
        case totalBattles = "total_battles"
        case wins, losses, draws
        case firstFoughtAt = "first_fought_at"
        case lastFoughtAt = "last_fought_at"
        case raritiesSeen = "rarities_seen"
        case stagesSeen = "stages_seen"
    }
}

struct PetDexSpeciesEntry: Codable, Identifiable, Equatable {
    let petType: String
    let displayName: String
    let description: String
    let imageEgg: String?
    let isDiscovered: Bool
    let totalBattles: Int
    let wins: Int
    let losses: Int
    let draws: Int
    let firstFoughtAt: Date?
    let lastFoughtAt: Date?
    let raritiesSeen: [String]
    let stagesSeen: [String]

    var id: String { petType }

    enum CodingKeys: String, CodingKey {
        case petType = "pet_type"
        case displayName = "display_name"
        case description
        case imageEgg = "image_egg"
        case isDiscovered = "is_discovered"
        case totalBattles = "total_battles"
        case wins, losses, draws
        case firstFoughtAt = "first_fought_at"
        case lastFoughtAt = "last_fought_at"
        case raritiesSeen = "rarities_seen"
        case stagesSeen = "stages_seen"
    }

    var eggImageURL: URL? {
        if let imageEgg, !imageEgg.isEmpty, let url = URL(string: imageEgg) {
            return url
        }
        return PetImageURLBuilder.imageURL(petType: petType, evolutionStage: "egg")
    }
}

struct PetDexData: Codable, Equatable {
    let speciesDiscovered: Int
    let totalSpecies: Int
    let raritiesDiscovered: Int
    let totalRarities: Int
    let stagesDiscovered: Int
    let totalFightableStages: Int
    let species: [PetDexSpeciesEntry]

    enum CodingKeys: String, CodingKey {
        case speciesDiscovered = "species_discovered"
        case totalSpecies = "total_species"
        case raritiesDiscovered = "rarities_discovered"
        case totalRarities = "total_rarities"
        case stagesDiscovered = "stages_discovered"
        case totalFightableStages = "total_fightable_stages"
        case species
    }
}

struct PetSpeciesDetail: Codable, Equatable {
    let petType: String
    let displayName: String
    let description: String
    let imageEgg: String?
    let imageBaby: String?
    let imageKid: String?
    let imageTeen: String?
    let imageAdult: String?
    let imageElder: String?
    let discoveredStages: [String]
    let dex: PetDexStats?

    enum CodingKeys: String, CodingKey {
        case petType = "pet_type"
        case displayName = "display_name"
        case description
        case imageEgg = "image_egg"
        case imageBaby = "image_baby"
        case imageKid = "image_kid"
        case imageTeen = "image_teen"
        case imageAdult = "image_adult"
        case imageElder = "image_elder"
        case discoveredStages = "discovered_stages"
        case dex
    }

    func imageURL(for stage: String) -> URL? {
        let raw: String? = switch stage.lowercased() {
        case "egg": imageEgg
        case "baby": imageBaby
        case "kid": imageKid
        case "teen": imageTeen
        case "adult": imageAdult
        case "elder": imageElder
        default: nil
        }
        if let raw, !raw.isEmpty, let url = URL(string: raw) {
            return url
        }
        return PetImageURLBuilder.imageURL(petType: petType, evolutionStage: stage)
    }

    func isStageDiscovered(_ stage: String) -> Bool {
        if stage.lowercased() == "egg" { return true }
        return discoveredStages.contains { $0.lowercased() == stage.lowercased() }
    }
}

enum PetEvolutionStages {
    static let ordered: [String] = ["egg", "baby", "kid", "teen", "adult", "elder"]

    static func displayName(for stage: String) -> String {
        stage.capitalized
    }
}

enum PetFoodItemType {
    static let all: [String] = ["food_baby", "food_kid", "food_teen", "food_adult", "food_elder"]

    static func displayName(for itemType: String) -> String {
        switch itemType {
        case "food_baby": return "Baby Snack"
        case "food_kid": return "Kid Cookies"
        case "food_teen": return "Teen Treat"
        case "food_adult": return "Adult Biscuit"
        case "food_elder": return "Elder Delight"
        case "pet_egg": return "Mysterious Egg"
        case "incubator": return "Egg Incubator"
        default: return itemType.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}
