import Foundation

enum WorkoutSavePerfFlow: String {
    case editStrength
    case activeFinish
}

enum WorkoutSavePerf {
    #if DEBUG
    private static var activeSpans: [String: Date] = [:]
    #endif

    static func begin(_ flow: WorkoutSavePerfFlow) {
        #if DEBUG
        let key = flow.rawValue
        activeSpans[key] = Date()
        print("[WorkoutSavePerf] begin flow=\(key)")
        #endif
    }

    static func mark(
        _ flow: WorkoutSavePerfFlow,
        _ segment: String,
        exerciseCount: Int? = nil,
        setCount: Int? = nil,
        linkedWorkoutCount: Int? = nil
    ) {
        #if DEBUG
        let key = flow.rawValue
        let now = Date()
        let elapsedMs: Int
        if let start = activeSpans[key] {
            elapsedMs = Int((now.timeIntervalSince(start) * 1000).rounded())
        } else {
            elapsedMs = 0
        }
        var parts = ["[WorkoutSavePerf]", "flow=\(key)", "segment=\(segment)", "elapsedMs=\(elapsedMs)"]
        if let exerciseCount { parts.append("exercises=\(exerciseCount)") }
        if let setCount { parts.append("sets=\(setCount)") }
        if let linkedWorkoutCount { parts.append("linkedWorkouts=\(linkedWorkoutCount)") }
        print(parts.joined(separator: " "))
        #endif
    }

    static func end(_ flow: WorkoutSavePerfFlow) {
        #if DEBUG
        let key = flow.rawValue
        let elapsedMs: Int
        if let start = activeSpans.removeValue(forKey: key) {
            elapsedMs = Int((Date().timeIntervalSince(start) * 1000).rounded())
        } else {
            elapsedMs = 0
        }
        print("[WorkoutSavePerf] end flow=\(key) totalMs=\(elapsedMs)")
        #endif
    }

    static func measure<T>(
        _ flow: WorkoutSavePerfFlow,
        _ segment: String,
        exerciseCount: Int? = nil,
        setCount: Int? = nil,
        linkedWorkoutCount: Int? = nil,
        operation: () async throws -> T
    ) async rethrows -> T {
        #if DEBUG
        let started = Date()
        defer {
            let ms = Int((Date().timeIntervalSince(started) * 1000).rounded())
            var parts = ["[WorkoutSavePerf]", "flow=\(flow.rawValue)", "segment=\(segment)", "segmentMs=\(ms)"]
            if let exerciseCount { parts.append("exercises=\(exerciseCount)") }
            if let setCount { parts.append("sets=\(setCount)") }
            if let linkedWorkoutCount { parts.append("linkedWorkouts=\(linkedWorkoutCount)") }
            print(parts.joined(separator: " "))
        }
        return try await operation()
        #else
        return try await operation()
        #endif
    }
}
