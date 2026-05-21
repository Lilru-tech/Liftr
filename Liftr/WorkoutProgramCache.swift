import Foundation

enum WorkoutProgramCache {
    struct CachedExercise: Codable, Equatable {
        let id: Int
        let exercise_id: Int64
        let order_index: Int
        let superset_group_id: UUID?
        let superset_position: Int?
        let notes: String?
        let custom_name: String?
        let exercise_name: String?
    }

    struct CachedSet: Codable, Equatable {
        let id: Int
        let workout_exercise_id: Int
        let set_number: Int
        let order_index: Int?
        let reps: Int?
        let weight_kg: Decimal?
        let rpe: Decimal?
        let rest_sec: Int?
        let notes: String?
    }

    struct Entry: Codable, Equatable {
        let workoutId: Int
        let cachedAt: Date
        let exercises: [CachedExercise]
        let setsByExerciseId: [Int: [CachedSet]]
    }

    private static let storageKeyPrefix = "liftr.workoutProgramCache.v1."
    private static var memory: [Int: Entry] = [:]

    static func store(workoutId: Int, exercises: [CachedExercise], setsByExerciseId: [Int: [CachedSet]]) {
        let entry = Entry(
            workoutId: workoutId,
            cachedAt: Date(),
            exercises: exercises,
            setsByExerciseId: setsByExerciseId
        )
        memory[workoutId] = entry
        if let data = try? JSONEncoder().encode(entry) {
            UserDefaults.standard.set(data, forKey: storageKeyPrefix + String(workoutId))
        }
    }

    static func entry(for workoutId: Int) -> Entry? {
        if let hit = memory[workoutId] { return hit }
        guard let data = UserDefaults.standard.data(forKey: storageKeyPrefix + String(workoutId)),
              let decoded = try? JSONDecoder().decode(Entry.self, from: data)
        else { return nil }
        memory[workoutId] = decoded
        return decoded
    }

    static func hasProgram(for workoutId: Int) -> Bool {
        guard let e = entry(for: workoutId) else { return false }
        return !e.exercises.isEmpty
    }
}
