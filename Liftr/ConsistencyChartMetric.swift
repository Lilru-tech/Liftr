import Foundation

enum ConsistencyChartMetric: String, CaseIterable, Identifiable {
    case duration
    case workouts
    case score
    case calories

    var id: String { rawValue }

    var pickerLabel: String {
        switch self {
        case .duration: return "Time"
        case .workouts: return "Workouts"
        case .score: return "Score"
        case .calories: return "Calories"
        }
    }

    var chartAxisLabel: String {
        switch self {
        case .duration: return "Minutes"
        case .workouts: return "Workouts"
        case .score: return "Score"
        case .calories: return "kcal"
        }
    }

    func measure(durationMin: Int, count: Int, score: Double, kcal: Double) -> Double {
        switch self {
        case .duration: return Double(durationMin)
        case .workouts: return Double(count)
        case .score: return max(0, score)
        case .calories: return max(0, kcal)
        }
    }
}

struct ConsistencyWorkoutMeta: Hashable {
    let kind: String
    let durationMin: Int
    let score: Double
    let kcal: Double
}
