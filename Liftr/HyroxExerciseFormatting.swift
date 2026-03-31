import Foundation
enum HyroxExerciseCode: String, CaseIterable, Identifiable {
    case run
    case skierg
    case burpeeBroadJump = "burpee_broad_jump"
    case sledPush = "sled_push"
    case sledPull = "sled_pull"
    case row
    case farmerCarry = "farmer_carry"
    case sandbagLunges = "sandbag_lunges"
    case wallBall = "wall_ball"
    case atlasCarry = "atlas_carry"
    case boxJumpOver = "box_jump_over"
    case deadBallOverTrunk = "dead_ball_over_trunk"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .run: return "Run"
        case .skierg: return "SkiErg"
        case .burpeeBroadJump: return "Burpee Broad Jump"
        case .sledPush: return "Sled Push"
        case .sledPull: return "Sled Pull"
        case .row: return "Row"
        case .farmerCarry: return "Farmer Carry"
        case .sandbagLunges: return "Sandbag Lunges"
        case .wallBall: return "Wall Ball"
        case .atlasCarry: return "Atlas Carry"
        case .boxJumpOver: return "Box Jump Over"
        case .deadBallOverTrunk: return "Dead Ball Over Trunk"
        }
    }
}

enum HyroxExerciseFormatting {
    static let customExerciseCode = "custom"
    static func label(code: String, displayName: String?) -> String {
        if let d = displayName?.trimmingCharacters(in: .whitespacesAndNewlines), !d.isEmpty {
            return d
        }
        switch code {
        case "run": return "Run"
        case "skierg": return "SkiErg"
        case "burpee_broad_jump": return "Burpee Broad Jump"
        case "sled_push": return "Sled Push"
        case "sled_pull": return "Sled Pull"
        case "row": return "Row"
        case "farmer_carry": return "Farmer Carry"
        case "sandbag_lunges": return "Sandbag Lunges"
        case "wall_ball": return "Wall Ball"
        case "atlas_carry": return "Atlas Carry"
        case "box_jump_over": return "Box Jump Over"
        case "dead_ball_over_trunk": return "Dead Ball Over Trunk"
        default:
            return code.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    static func formFields(exerciseCode: String, exerciseDisplayName: String?) -> (code: String, customDisplayName: String) {
        if HyroxExerciseCode(rawValue: exerciseCode) != nil {
            return (exerciseCode, "")
        }
        if exerciseCode == customExerciseCode {
            return (customExerciseCode, exerciseDisplayName ?? "")
        }
        return (exerciseCode, exerciseDisplayName ?? "")
    }

    static func persistedPayload(exerciseCode: String, customDisplayName: String) -> (code: String, displayName: String?) {
        let trimmed = customDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if HyroxExerciseCode(rawValue: exerciseCode) != nil {
            return (exerciseCode, nil)
        }
        if exerciseCode == customExerciseCode {
            return (customExerciseCode, trimmed.isEmpty ? nil : trimmed)
        }
        return (exerciseCode, trimmed.isEmpty ? nil : trimmed)
    }

    static func pickerTag(for exerciseCode: String) -> String {
        if HyroxExerciseCode(rawValue: exerciseCode) != nil {
            return exerciseCode
        }
        return customExerciseCode
    }
}
