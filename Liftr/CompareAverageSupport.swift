import Foundation
import Supabase

enum CompareAverageScope: String {
    case mine
    case global
}

enum CompareOtherTarget: Equatable {
    case workout(Int)
    case average(scope: CompareAverageScope, workoutIds: [Int], sampleCount: Int)
}

struct CompareAverageOption {
    let scope: CompareAverageScope
    let workoutIds: [Int]
    let sampleCount: Int
    let typeLabel: String
}

enum ComparePickerEntry: Identifiable {
    case average(CompareAverageOption)
    case session(WorkoutDetailView.CompareCandidate)

    var id: String {
        switch self {
        case .average(let o):
            return "avg-\(o.scope.rawValue)"
        case .session(let c):
            return "s-\(c.id)"
        }
    }
}

struct ComparePickerState {
    var sessions: [WorkoutDetailView.CompareCandidate] = []
    var myAverage: CompareAverageOption?
    var globalAverage: CompareAverageOption?

    var hasAnyOption: Bool {
        !sessions.isEmpty || myAverage != nil || globalAverage != nil
    }

    var entries: [ComparePickerEntry] {
        var out: [ComparePickerEntry] = []
        if let m = myAverage { out.append(.average(m)) }
        if let g = globalAverage { out.append(.average(g)) }
        out.append(contentsOf: sessions.map { .session($0) })
        return out
    }
}

enum CompareAveragePoolLoader {
    static let mineLimit = 10
    static let globalLimit = 50
    static let minSamples = 2

    private struct PoolRow: Decodable {
        let workout_id: Int
        let started_at: String?
    }

    static func typeLabel(for workout: WorkoutDetailView.WorkoutDetailRow) -> String {
        let t = (workout.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { return t }
        switch workout.kind.lowercased() {
        case "sport": return "Sport"
        case "cardio": return "Cardio"
        default: return "Workout"
        }
    }

    static func loadPickerAverages(
        baselineWorkoutId: Int,
        typeLabel: String
    ) async -> (CompareAverageOption?, CompareAverageOption?) {
        async let mineIds = fetchPool(baselineWorkoutId: baselineWorkoutId, scope: .mine, limit: mineLimit)
        async let globalIds = fetchPool(baselineWorkoutId: baselineWorkoutId, scope: .global, limit: globalLimit)
        let (m, g) = await (mineIds, globalIds)
        let mine = m.count >= minSamples
            ? CompareAverageOption(scope: .mine, workoutIds: m, sampleCount: m.count, typeLabel: typeLabel)
            : nil
        let global = g.count >= minSamples
            ? CompareAverageOption(scope: .global, workoutIds: g, sampleCount: g.count, typeLabel: typeLabel)
            : nil
        return (mine, global)
    }

    private static func fetchPool(
        baselineWorkoutId: Int,
        scope: CompareAverageScope,
        limit: Int
    ) async -> [Int] {
        struct Params: Encodable {
            let p_baseline_workout: Int
            let p_scope: String
            let p_limit: Int
        }
        do {
            let res = try await SupabaseManager.shared.client
                .rpc(
                    "list_compare_average_pool_v1",
                    params: Params(
                        p_baseline_workout: baselineWorkoutId,
                        p_scope: scope.rawValue,
                        p_limit: limit
                    )
                )
                .execute()
            let rows = try JSONDecoder.supabase().decode([PoolRow].self, from: res.data)
            return rows.map(\.workout_id)
        } catch {
            #if DEBUG
            print("list_compare_average_pool_v1 failed scope=\(scope.rawValue) baseline=\(baselineWorkoutId): \(error)")
            #endif
            return []
        }
    }
}

func averageCompareMetrics(_ perSession: [[CompareWorkoutsView.ComparableMetric]]) -> [CompareWorkoutsView.ComparableMetric] {
    guard let first = perSession.first, !first.isEmpty else { return [] }
    let leftByKey = Dictionary(uniqueKeysWithValues: first.map { ($0.metric, $0.left_value) })
    var units: [String: String] = [:]
    var rightAcc: [String: [Double]] = [:]
    for rows in perSession {
        for r in rows {
            units[r.metric] = r.unit
            rightAcc[r.metric, default: []].append(r.right_value)
        }
    }
    let keys = Set(leftByKey.keys).union(rightAcc.keys).sorted()
    return keys.compactMap { key -> CompareWorkoutsView.ComparableMetric? in
        guard let left = leftByKey[key], let rights = rightAcc[key], !rights.isEmpty else { return nil }
        let avg = rights.reduce(0, +) / Double(rights.count)
        return CompareWorkoutsView.ComparableMetric(
            metric: key,
            unit: units[key] ?? "count",
            left_value: left,
            right_value: avg
        )
    }
}

func compareAverageRightLabel(scope: CompareAverageScope, sampleCount: Int) -> String {
    let title = scope == .mine ? "My average" : "Global average"
    return "\(title) (\(sampleCount))"
}

func compareAveragePickerTitle(_ option: CompareAverageOption) -> String {
    option.scope == .mine ? "My average" : "Global average"
}

func shouldShowComparePicker(_ picker: ComparePickerState) -> Bool {
    let avgCount = (picker.myAverage != nil ? 1 : 0) + (picker.globalAverage != nil ? 1 : 0)
    return picker.sessions.count + avgCount > 1
}

func compareAverageMatchesSearch(_ option: CompareAverageOption, query: String) -> Bool {
    let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !q.isEmpty else { return true }
    return compareAveragePickerTitle(option).lowercased().contains(q)
        || option.typeLabel.lowercased().contains(q)
}

func filterComparePickerSessions(
    _ picker: ComparePickerState,
    query: String
) -> [WorkoutDetailView.CompareCandidate] {
    let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !q.isEmpty else { return picker.sessions }
    return picker.sessions.filter { c in
        if c.displayTitle.lowercased().contains(q) { return true }
        if let u = c.owner_username, !u.isEmpty, u.lowercased().contains(q) { return true }
        if c.started_at.formatted(date: .abbreviated, time: .shortened).lowercased().contains(q) { return true }
        return false
    }
}

func singleCompareTarget(_ picker: ComparePickerState) -> CompareOtherTarget? {
    var options: [CompareOtherTarget] = []
    if let m = picker.myAverage {
        options.append(.average(scope: m.scope, workoutIds: m.workoutIds, sampleCount: m.sampleCount))
    }
    if let g = picker.globalAverage {
        options.append(.average(scope: g.scope, workoutIds: g.workoutIds, sampleCount: g.sampleCount))
    }
    options.append(contentsOf: picker.sessions.map { .workout($0.id) })
    return options.count == 1 ? options.first : nil
}
