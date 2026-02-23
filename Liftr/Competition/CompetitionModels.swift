import Foundation

enum CompetitionStatus: String, Decodable, Encodable, CaseIterable {
    case pending, active, declined, expired, cancelled, finished
}

struct CompetitionRow: Decodable, Identifiable {
    let id: Int
    let created_by: UUID
    let user_a: UUID
    let user_b: UUID
    let status: CompetitionStatus
    let invite_expires_at: Date
    let accepted_at: Date?
    let declined_at: Date?
    let cancelled_at: Date?
    let finished_at: Date?
    let winner_user_id: UUID?
    let created_at: Date
    let updated_at: Date
}

struct CompetitionGoalRow: Decodable {
    let competition_id: Int
    let time_limit_at: Date?
    let metric: String?
    let target_value: Decimal?
    let created_at: Date
}

struct ProfileLiteRow: Decodable, Identifiable {
    let user_id: UUID
    let username: String
    let avatar_url: String?
    var id: UUID { user_id }
}

struct CompetitionWorkoutRow: Decodable, Identifiable {
    let id: Int
    let competition_id: Int
    let workout_id: Int
    let workout_owner_id: UUID
    let status: String
    let score_snapshot: Decimal?
    let calories_snapshot: Decimal?
    let created_at: Date
    let updated_at: Date
}

struct CompetitionProgress {
    var workoutsCount: Int = 0
    var scoreTotal: Double = 0
    var caloriesTotal: Double = 0
}

struct WorkoutLiteRow: Decodable, Identifiable {
    let id: Int
    let user_id: UUID
    let title: String?
    let kind: String?
    let started_at: Date
    let calories_kcal: Decimal?
}

enum CompetitionMetric: String, CaseIterable {
    case workouts, calories, score
    
    var title: String {
        switch self {
        case .workouts: return "Workouts"
        case .calories: return "Calories"
        case .score:    return "Score"
        }
    }
    
    var systemImage: String {
        switch self {
        case .workouts: return "figure.strengthtraining.traditional"
        case .calories: return "flame.fill"
        case .score:    return "bolt.fill"
        }
    }
}
