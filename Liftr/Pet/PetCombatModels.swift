import Foundation

struct ProfileEnergy: Codable, Equatable {
    let current: Int
    let max: Int
    let lastRefresh: Date?
    let nextRefreshAt: Date?
    let regenMinutes: Int?

    enum CodingKeys: String, CodingKey {
        case current, max
        case lastRefresh = "last_refresh"
        case nextRefreshAt = "next_refresh_at"
        case regenMinutes = "regen_minutes"
    }

    var isFull: Bool { current >= max }
}

enum PetEnergyPricing {
    static let maxCapacity = 15

    static func upgradeCost(maxEnergy: Int) -> Int {
        Int(5000 * pow(2.0, Double(max(maxEnergy, 5) - 5)))
    }
}

struct EnergyUpgradeResult: Codable, Equatable {
    let maxEnergy: Int
    let currentEnergy: Int
    let cost: Int
    let purchaseId: UUID

    enum CodingKeys: String, CodingKey {
        case maxEnergy = "max_energy"
        case currentEnergy = "current_energy"
        case cost
        case purchaseId = "purchase_id"
    }
}

struct PetCombatRewards: Codable, Equatable {
    let xp: Int
    let coins: Int
}

struct PetCombatPetSummary: Codable, Equatable {
    let id: UUID
    let customName: String?
    let petType: String
    let evolutionStage: String
    let currentLevel: Int
    let rarity: String
    let imageUrl: String?
    let name: String?

    enum CodingKeys: String, CodingKey {
        case id
        case customName = "custom_name"
        case petType = "pet_type"
        case evolutionStage = "evolution_stage"
        case currentLevel = "current_level"
        case rarity
        case imageUrl = "image_url"
        case name
    }

    var displayName: String {
        if let name, !name.isEmpty { return name }
        if let customName, !customName.isEmpty { return customName }
        return petType.petDisplayTitle
    }

    var imageURL: URL? {
        if let imageUrl, !imageUrl.isEmpty, let url = URL(string: imageUrl) {
            return url
        }
        return PetImageURLBuilder.imageURL(petType: petType, evolutionStage: evolutionStage)
    }
}

struct PetCombatStatsSummary: Codable, Equatable {
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
        case health, strength, defense, speed, intelligence, agility, stamina, resistance, exploration, happiness
        case criticalRate = "critical_rate"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        health = try container.decodeIfPresent(Int.self, forKey: .health) ?? 0
        strength = try container.decodeIfPresent(Int.self, forKey: .strength) ?? 0
        defense = try container.decodeIfPresent(Int.self, forKey: .defense) ?? 0
        speed = try container.decodeIfPresent(Int.self, forKey: .speed) ?? 0
        intelligence = try container.decodeIfPresent(Int.self, forKey: .intelligence) ?? 0
        agility = try container.decodeIfPresent(Int.self, forKey: .agility) ?? 0
        stamina = try container.decodeIfPresent(Int.self, forKey: .stamina) ?? 0
        criticalRate = try container.decodeIfPresent(Int.self, forKey: .criticalRate) ?? 0
        resistance = try container.decodeIfPresent(Int.self, forKey: .resistance) ?? 0
        exploration = try container.decodeIfPresent(Int.self, forKey: .exploration) ?? 0
        happiness = try container.decodeIfPresent(Int.self, forKey: .happiness) ?? 0
    }

    var combatStatPoolTotal: Int {
        health + strength + defense + speed + agility + stamina + resistance + criticalRate + intelligence + exploration
    }

    var comparisonStatPoolTotal: Int {
        Int(floor(Double(health) * 0.25))
            + strength + defense + speed + agility + stamina + resistance + criticalRate + intelligence + exploration
    }
}

enum PetCombatStatBalancing {
    private static let handicapThresholdPct = 125

    static func isUnbalanced(attacker: PetCombatStatsSummary, defender: PetCombatStatsSummary) -> Bool {
        let poolA = attacker.comparisonStatPoolTotal
        let poolB = defender.comparisonStatPoolTotal
        let stronger = max(poolA, poolB)
        let weaker = min(poolA, poolB)
        return stronger * 100 > weaker * handicapThresholdPct
    }
}

struct PetCombatStatBalancingSummary: Codable, Equatable {
    let isUnbalanced: Bool
    let attackerStatPool: Int
    let defenderStatPool: Int
    let attackerPoolBattle: Int?
    let defenderPoolBattle: Int?
    let strongerSide: String?
    let hardcoreBuffMultiplier: Double?
    let hardcoreBonusPercent: Int?

    enum CodingKeys: String, CodingKey {
        case isUnbalanced = "is_unbalanced"
        case attackerStatPool = "attacker_stat_pool"
        case defenderStatPool = "defender_stat_pool"
        case attackerPoolBattle = "attacker_pool_battle"
        case defenderPoolBattle = "defender_pool_battle"
        case strongerSide = "stronger_side"
        case hardcoreBuffMultiplier = "hardcore_buff_multiplier"
        case hardcoreBonusPercent = "hardcore_bonus_percent"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isUnbalanced = try container.decodeIfPresent(Bool.self, forKey: .isUnbalanced) ?? false
        attackerStatPool = try container.decodeIfPresent(Int.self, forKey: .attackerStatPool) ?? 0
        defenderStatPool = try container.decodeIfPresent(Int.self, forKey: .defenderStatPool) ?? 0
        attackerPoolBattle = try container.decodeIfPresent(Int.self, forKey: .attackerPoolBattle)
        defenderPoolBattle = try container.decodeIfPresent(Int.self, forKey: .defenderPoolBattle)
        strongerSide = try container.decodeIfPresent(String.self, forKey: .strongerSide)
        hardcoreBuffMultiplier = try container.decodeIfPresent(Double.self, forKey: .hardcoreBuffMultiplier)
        hardcoreBonusPercent = try container.decodeIfPresent(Int.self, forKey: .hardcoreBonusPercent)
    }
}

enum PetCombatChallengeMode: String, CaseIterable, Identifiable {
    case balanced
    case hardcore

    var id: String { rawValue }

    var disableNerfChoice: Bool { self == .hardcore }

    var title: String {
        switch self {
        case .balanced: return "Balanced Mode (Safe)"
        case .hardcore: return "Hardcore Mode (No Nerf)"
        }
    }
}

struct PetCombatSide: Codable, Equatable {
    let userId: UUID
    let username: String?
    let pet: PetCombatPetSummary?
    let stats: PetCombatStatsSummary?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case username, pet, stats
    }
}

struct PetCombatPreview: Codable, Equatable {
    let canChallenge: Bool
    let blockReason: String?
    let cooldownExpiresAt: Date?
    let statBalancing: PetCombatStatBalancingSummary?
    let attacker: PetCombatSide?
    let defender: PetCombatSide?
    let energy: ProfileEnergy?

    enum CodingKeys: String, CodingKey {
        case canChallenge = "can_challenge"
        case blockReason = "block_reason"
        case cooldownExpiresAt = "cooldown_expires_at"
        case statBalancing = "stat_balancing"
        case attacker, defender, energy
    }

    var isStatUnbalanced: Bool {
        if let statBalancing {
            return statBalancing.isUnbalanced
        }
        guard let attackerStats = attacker?.stats, let defenderStats = defender?.stats else {
            return false
        }
        return PetCombatStatBalancing.isUnbalanced(attacker: attackerStats, defender: defenderStats)
    }

    var isAttackerUnderdog: Bool {
        statBalancing?.strongerSide == "defender"
    }

    var hardcoreBonusLabel: String? {
        guard let percent = statBalancing?.hardcoreBonusPercent, percent > 0 else { return nil }
        return "+\(percent)% Coins & XP"
    }

    var effectiveCanChallenge: Bool {
        if canChallenge { return true }
        if blockReason == "cooldown_active",
           let cooldownExpiresAt,
           cooldownExpiresAt <= Date() {
            return true
        }
        return false
    }

    var blockReasonText: String? {
        guard let blockReason else { return nil }
        switch blockReason {
        case "self_challenge": return "You cannot challenge yourself."
        case "attacker_no_pet": return "You need a hatched pet to challenge."
        case "defender_no_pet": return "This user has no pet to challenge."
        case "attacker_egg": return "Your pet must hatch before battling."
        case "defender_egg": return "This user's pet has not hatched yet."
        case "no_energy": return "No arena energy left. You regain 1 energy every 4 hours."
        case "cooldown_active":
            if let cooldownExpiresAt, cooldownExpiresAt > Date() {
                let formatter = RelativeDateTimeFormatter()
                return "You can challenge again \(formatter.localizedString(for: cooldownExpiresAt, relativeTo: Date()))."
            }
            if cooldownExpiresAt == nil {
                return "You recently battled this user. Try again later."
            }
            return nil
        default: return blockReason.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}

struct PetBattlePetSnapshot: Codable, Equatable {
    let userId: UUID
    let petInstanceId: UUID
    let name: String
    let petType: String
    let evolutionStage: String
    let level: Int
    let rarity: String
    let imageUrl: String?
    let maxHp: Int?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case petInstanceId = "pet_instance_id"
        case name
        case petType = "pet_type"
        case evolutionStage = "evolution_stage"
        case level, rarity
        case imageUrl = "image_url"
        case maxHp = "max_hp"
    }

    func resolvedMaxHp(fallback: Int = 1) -> Int {
        if let maxHp, maxHp > 0 { return maxHp }
        return max(fallback, 1)
    }

    var imageURL: URL? {
        if let imageUrl, !imageUrl.isEmpty, let url = URL(string: imageUrl) {
            return url
        }
        return PetImageURLBuilder.imageURL(petType: petType, evolutionStage: evolutionStage)
    }
}

struct PetBattleTurn: Codable, Equatable, Identifiable {
    let turn: Int
    let actor: String
    let action: String
    let damage: Int
    let isCritical: Bool
    let attackerHpAfter: Int
    let defenderHpAfter: Int
    let message: String

    var id: Int { turn }

    enum CodingKeys: String, CodingKey {
        case turn, actor, action, damage, message
        case isCritical = "is_critical"
        case attackerHpAfter = "attacker_hp_after"
        case defenderHpAfter = "defender_hp_after"
    }
}

struct PetBattleResultSummary: Codable, Equatable {
    let winner: String?
    let winnerUserId: UUID?
    let totalTurns: Int
    let isDraw: Bool

    enum CodingKeys: String, CodingKey {
        case winner
        case winnerUserId = "winner_user_id"
        case totalTurns = "total_turns"
        case isDraw = "is_draw"
    }
}

struct PetBattleLog: Codable, Equatable {
    let version: Int
    let attackerPet: PetBattlePetSnapshot
    let defenderPet: PetBattlePetSnapshot
    let turns: [PetBattleTurn]
    let result: PetBattleResultSummary

    enum CodingKeys: String, CodingKey {
        case version, turns, result
        case attackerPet = "attacker_pet"
        case defenderPet = "defender_pet"
    }
}

struct PetCombatResult: Codable, Equatable {
    let combatId: UUID
    let winnerUserId: UUID?
    let attackerRewards: PetCombatRewards
    let defenderRewards: PetCombatRewards
    let battleLog: PetBattleLog
    let energy: ProfileEnergy?

    enum CodingKeys: String, CodingKey {
        case combatId = "combat_id"
        case winnerUserId = "winner_user_id"
        case attackerRewards = "attacker_rewards"
        case defenderRewards = "defender_rewards"
        case battleLog = "battle_log"
        case energy
    }
}

struct PetCombatUserStats: Codable, Equatable {
    let maxDamageDealt: Int
    let maxDamageTaken: Int
    let totalDamageDealt: Int
    let totalDamageTaken: Int
    let critsLanded: Int
    let dodgesPerformed: Int
    let totalBattles: Int
    let wins: Int
    let losses: Int
    let draws: Int
    let currentWinStreak: Int
    let bestWinStreak: Int
    let longestBattleTurns: Int

    enum CodingKeys: String, CodingKey {
        case maxDamageDealt = "max_damage_dealt"
        case maxDamageTaken = "max_damage_taken"
        case totalDamageDealt = "total_damage_dealt"
        case totalDamageTaken = "total_damage_taken"
        case critsLanded = "crits_landed"
        case dodgesPerformed = "dodges_performed"
        case totalBattles = "total_battles"
        case wins, losses, draws
        case currentWinStreak = "current_win_streak"
        case bestWinStreak = "best_win_streak"
        case longestBattleTurns = "longest_battle_turns"
    }
}

struct PetCombatHeadToHeadLastBattle: Codable, Equatable {
    let createdAt: Date?
    let won: Bool
    let isDraw: Bool
    let yourRole: String?
    let rewards: PetCombatRewards?

    enum CodingKeys: String, CodingKey {
        case createdAt = "created_at"
        case won
        case isDraw = "is_draw"
        case yourRole = "your_role"
        case rewards
    }
}

struct PetCombatHeadToHeadSummary: Codable, Equatable {
    let wins: Int
    let losses: Int
    let draws: Int
    let totalBattles: Int
    let winRate: Double
    let lastBattle: PetCombatHeadToHeadLastBattle?

    enum CodingKeys: String, CodingKey {
        case wins, losses, draws
        case totalBattles = "total_battles"
        case winRate = "win_rate"
        case lastBattle = "last_battle"
    }

    var winRatePercentText: String {
        guard totalBattles > 0 else { return "0%" }
        return "\(Int((winRate * 100).rounded()))%"
    }
}
