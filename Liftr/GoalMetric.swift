import Foundation

enum GoalMetric: String, CaseIterable, Identifiable, Codable {
    case workouts
    case calories
    case score

    var id: String { rawValue }

    var title: String {
        switch self {
        case .workouts: return "Workouts"
        case .calories: return "Calories"
        case .score: return "Score"
        }
    }

    var unit: String {
        switch self {
        case .workouts: return "workouts/week"
        case .calories: return "kcal/week"
        case .score: return "score/week"
        }
    }
}
