import Foundation

struct PetLog: Identifiable, Equatable {
    let id: Int64
    let eventType: String
    let itemType: String?
    let expGained: Int
    let newLevel: Int?
    let statsDelta: [String: Int]?
    let details: [String: String]?
    let createdAt: Date

    static func title(for log: PetLog) -> String {
        switch log.eventType {
        case "item_used", "fed":
            if let name = log.details?["reason"] ?? log.itemType {
                return "Used \(name.replacingOccurrences(of: "_", with: " ").capitalized)"
            }
            return "Used item"
        case "level_up":
            return "Level up"
        case "incubation_started":
            return "Incubation started"
        case "hatched":
            return "Hatched"
        case "evolution":
            return "Evolution"
        case "rarity_upgrade":
            if let from = log.details?["from_rarity"], let to = log.details?["to_rarity"] {
                let fromLabel = from.replacingOccurrences(of: "_", with: " ").capitalized
                let toLabel = to.replacingOccurrences(of: "_", with: " ").capitalized
                return "Rarity upgrade: \(fromLabel) → \(toLabel)"
            }
            return "Rarity upgrade"
        case "coins_generated":
            if let coins = log.details?["coins"], !coins.isEmpty {
                return "Coins generated: +\(coins)"
            }
            return "Coins generated"
        case "workout_pet_bonus":
            if let message = log.details?["message"], !message.isEmpty {
                return message
            }
            if let coins = log.details?["coins"], !coins.isEmpty {
                return "Your pet helped you earn +\(coins) coins!"
            }
            return "Pet workout bonus"
        case "combat":
            let opponent = combatOpponentName(from: log.details)
            if log.details?["is_draw"] == "true" {
                return "Draw vs \(opponent)"
            }
            if log.details?["won"] == "true" {
                return "Victory vs \(opponent)"
            }
            return "Defeat vs \(opponent)"
        default:
            return log.eventType
                .replacingOccurrences(of: "_", with: " ")
                .capitalized
        }
    }

    static func subtitle(for log: PetLog) -> String? {
        guard log.eventType == "combat" else { return nil }
        if log.details?["is_draw"] == "true" {
            return combatRewardText(xp: log.expGained, coins: Int(log.details?["coins_gained"] ?? "") ?? 0)
        }
        if log.details?["won"] == "true" {
            return combatRewardText(
                xp: log.expGained,
                coins: Int(log.details?["coins_gained"] ?? "") ?? 0
            )
        }
        return "No rewards"
    }

    private static func combatOpponentName(from details: [String: String]?) -> String {
        if let username = details?["opponent_username"], !username.isEmpty {
            return "@\(username)"
        }
        return "opponent"
    }

    private static func combatRewardText(xp: Int, coins: Int) -> String {
        var parts: [String] = []
        if xp > 0 { parts.append("+\(xp) XP") }
        if coins > 0 { parts.append("+\(coins) coins") }
        return parts.isEmpty ? "No rewards" : parts.joined(separator: " · ")
    }
}

struct PetLogRow: Codable {
    let id: Int64
    let eventType: String
    let itemType: String?
    let expGained: Int
    let newLevel: Int?
    let statsDelta: [String: Int]?
    let details: [String: String]?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case eventType = "event_type"
        case itemType = "item_type"
        case expGained = "exp_gained"
        case newLevel = "new_level"
        case statsDelta = "stats_delta"
        case details
        case createdAt = "created_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int64.self, forKey: .id)
        eventType = try c.decode(String.self, forKey: .eventType)
        itemType = try c.decodeIfPresent(String.self, forKey: .itemType)
        expGained = try c.decodeIfPresent(Int.self, forKey: .expGained) ?? 0
        newLevel = try c.decodeIfPresent(Int.self, forKey: .newLevel)
        statsDelta = try c.decodeIfPresent([String: Int].self, forKey: .statsDelta)
        details = try Self.decodeDetails(from: c)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
    }

    private static func decodeDetails(from container: KeyedDecodingContainer<CodingKeys>) throws -> [String: String]? {
        guard container.contains(.details) else { return nil }
        if let stringDict = try? container.decode([String: String].self, forKey: .details) {
            return stringDict
        }
        if let mixed = try? container.decode([String: PetLogDetailValue].self, forKey: .details) {
            return mixed.mapValues(\.stringValue)
        }
        return nil
    }

    var petLog: PetLog {
        PetLog(
            id: id,
            eventType: eventType,
            itemType: itemType,
            expGained: expGained,
            newLevel: newLevel,
            statsDelta: statsDelta,
            details: details,
            createdAt: createdAt
        )
    }
}

private enum PetLogDetailValue: Decodable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case object([String: PetLogDetailValue])
    case array([PetLogDetailValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode([String: PetLogDetailValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([PetLogDetailValue].self) {
            self = .array(value)
        } else {
            self = .null
        }
    }

    var stringValue: String {
        switch self {
        case .string(let value): return value
        case .int(let value): return String(value)
        case .double(let value): return String(value)
        case .bool(let value): return value ? "true" : "false"
        case .object, .array, .null: return ""
        }
    }
}
