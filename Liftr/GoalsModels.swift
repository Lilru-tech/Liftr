import Foundation

struct WeeklyGoalRow: Codable, Identifiable {
    let id: Int64
    let user_id: UUID
    let week_start: Date
    let metric: GoalMetric
    let target_value: Decimal
    let updated_at: Date?
    let title: String?
    let notes: String?
}

struct WeeklyGoalResultRow: Codable, Identifiable {
    let goal_id: Int64
    let user_id: UUID
    let week_start: Date
    let achieved_value: Decimal
    let is_completed: Bool
    let updated_at: Date?
    let completed_at: Date?

    var id: String { "\(goal_id)-\(week_start.timeIntervalSince1970)" }
}


struct GoalRowUI: Identifiable {
    let id: Int64
    let userId: UUID
    let weekStart: Date
    var title: String
    var targetValue: Decimal
    var achievedValue: Decimal
    var isCompleted: Bool
    var metric: String

    var progressRatio: Double {
        let target = NSDecimalNumber(decimal: targetValue).doubleValue
        guard target > 0 else { return 0 }
        let achieved = NSDecimalNumber(decimal: achievedValue).doubleValue
        return achieved / target
    }

    var progress: Double {
        min(1.0, progressRatio)
    }
}

struct WeeklyGoalInsert: Encodable {
    let user_id: UUID
    let week_start: String
    let metric: GoalMetric
    let target_value: Decimal
    let title: String?
    let notes: String?
}

struct WeeklyGoalUpdate: Encodable {
    let target_value: Decimal?
    let title: String?
    let notes: String?
    let metric: GoalMetric?
}
