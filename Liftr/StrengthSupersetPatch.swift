import Foundation
import Supabase

struct StrengthRoutineExerciseRowInsert: Encodable {
    let routine_id: Int64
    let exercise_id: Int64
    let order_index: Int
    let notes: String?
    let custom_name: String?
    let superset_group_id: UUID?
    let superset_position: Int?

    private enum CodingKeys: String, CodingKey {
        case routine_id, exercise_id, order_index, notes, custom_name
        case superset_group_id, superset_position
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(routine_id, forKey: .routine_id)
        try container.encode(exercise_id, forKey: .exercise_id)
        try container.encode(order_index, forKey: .order_index)
        try container.encodeIfPresent(notes, forKey: .notes)
        try container.encodeIfPresent(custom_name, forKey: .custom_name)
        if let superset_group_id {
            try container.encode(superset_group_id, forKey: .superset_group_id)
        } else {
            try container.encodeNil(forKey: .superset_group_id)
        }
        if let superset_position {
            try container.encode(superset_position, forKey: .superset_position)
        } else {
            try container.encodeNil(forKey: .superset_position)
        }
    }
}

struct WorkoutExerciseSupersetPatch: Encodable {
    let superset_group_id: UUID?
    let superset_position: Int?

    private enum CodingKeys: String, CodingKey {
        case superset_group_id, superset_position
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let superset_group_id {
            try container.encode(superset_group_id, forKey: .superset_group_id)
        } else {
            try container.encodeNil(forKey: .superset_group_id)
        }
        if let superset_position {
            try container.encode(superset_position, forKey: .superset_position)
        } else {
            try container.encodeNil(forKey: .superset_position)
        }
    }
}

struct WorkoutExerciseSupersetPatchInput {
    let workoutExerciseId: Int
    let supersetGroupId: UUID?
    let supersetPosition: Int?
}

enum StrengthSupersetPatch {
    static func patchWorkoutExerciseSupersets(
        client: SupabaseClient,
        exercises: [WorkoutExerciseSupersetPatchInput]
    ) async throws {
        for exercise in exercises {
            _ = try await client
                .from("workout_exercises")
                .update(
                    WorkoutExerciseSupersetPatch(
                        superset_group_id: exercise.supersetGroupId,
                        superset_position: exercise.supersetPosition
                    )
                )
                .eq("id", value: exercise.workoutExerciseId)
                .execute()
        }
    }

    private struct CreatedWorkoutExerciseRow: Decodable {
        let id: Int
        let order_index: Int
    }

    static func patchSupersetsForCreatedWorkouts(
        client: SupabaseClient,
        workoutIds: [Int64],
        programs: [[EditableExercise]]
    ) async throws {
        for (idx, workoutId) in workoutIds.enumerated() {
            guard programs.indices.contains(idx) else { continue }
            let program = normalizedSupersetPrograms(programs[idx])
            guard program.contains(where: { $0.supersetGroupId != nil }) else { continue }

            let res = try await client
                .from("workout_exercises")
                .select("id, order_index")
                .eq("workout_id", value: Int(workoutId))
                .order("order_index", ascending: true)
                .execute()
            let rows = try JSONDecoder.supabase().decode([CreatedWorkoutExerciseRow].self, from: res.data)

            var patches: [WorkoutExerciseSupersetPatchInput] = []
            for row in rows {
                let exercise = program.first(where: { $0.orderIndex == row.order_index })
                patches.append(
                    WorkoutExerciseSupersetPatchInput(
                        workoutExerciseId: row.id,
                        supersetGroupId: exercise?.supersetGroupId,
                        supersetPosition: exercise?.supersetPosition
                    )
                )
            }
            try await patchWorkoutExerciseSupersets(client: client, exercises: patches)
        }
    }
}
