import Foundation
import Supabase

struct StrengthWorkoutSaveResult: Decodable {
    let workout_id: Int
    let user_id: UUID
    let kind: String
    let title: String?
    let started_at: Date?
    let ended_at: Date?
    let state: String?
    let score: Double?
}

struct StrengthWorkoutFinishLinkedInput: Encodable {
    let workout_id: Int
    let exercises: [StrengthWorkoutExerciseSaveInput]
}

struct StrengthWorkoutExerciseSaveInput: Encodable {
    let workout_exercise_id: Int
    let exercise_id: Int?
    let order_index: Int?
    let notes: String?
    let custom_name: String?
    let sets: [StrengthWorkoutSetSaveInput]
}

struct StrengthWorkoutSetSaveInput: Encodable {
    let set_number: Int
    let order_index: Int?
    let reps: Int?
    let weight_kg: Double?
    let rpe: Double?
    let rest_sec: Int?
    let weight_segments: [StrengthWeightSegWire]?
}

private struct UpdateStrengthWorkoutV1Params: Encodable {
    let p_workout_id: Int
    let p_title: String?
    let p_notes: String?
    let p_started_at: String
    let p_ended_at: String?
    let p_perceived_intensity: String?
    let p_exercises: [StrengthWorkoutExerciseSaveInput]

    private enum CodingKeys: String, CodingKey {
        case p_workout_id
        case p_title
        case p_notes
        case p_started_at
        case p_ended_at
        case p_perceived_intensity
        case p_exercises
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(p_workout_id, forKey: .p_workout_id)
        try container.encode(p_started_at, forKey: .p_started_at)
        try container.encode(p_exercises, forKey: .p_exercises)
        if let p_title {
            try container.encode(p_title, forKey: .p_title)
        } else {
            try container.encodeNil(forKey: .p_title)
        }
        if let p_notes {
            try container.encode(p_notes, forKey: .p_notes)
        } else {
            try container.encodeNil(forKey: .p_notes)
        }
        if let p_ended_at {
            try container.encode(p_ended_at, forKey: .p_ended_at)
        } else {
            try container.encodeNil(forKey: .p_ended_at)
        }
        if let p_perceived_intensity {
            try container.encode(p_perceived_intensity, forKey: .p_perceived_intensity)
        } else {
            try container.encodeNil(forKey: .p_perceived_intensity)
        }
    }
}

private struct FinishStrengthWorkoutV1Params: Encodable {
    let p_workout_id: Int
    let p_ended_at: String
    let p_paused_sec: Int
    let p_exercises: [StrengthWorkoutExerciseSaveInput]
    let p_linked: [StrengthWorkoutFinishLinkedInput]
}

enum StrengthWorkoutSaveRPC {
    static func updateStrengthWorkoutV1(
        client: SupabaseClient,
        workoutId: Int,
        title: String?,
        notes: String?,
        startedAt: String,
        endedAt: String?,
        perceivedIntensity: String?,
        exercises: [StrengthWorkoutExerciseSaveInput]
    ) async throws -> StrengthWorkoutSaveResult {
        let params = UpdateStrengthWorkoutV1Params(
            p_workout_id: workoutId,
            p_title: title,
            p_notes: notes,
            p_started_at: startedAt,
            p_ended_at: endedAt,
            p_perceived_intensity: perceivedIntensity,
            p_exercises: exercises
        )
        let res = try await client
            .rpc("update_strength_workout_v1", params: params)
            .execute()
        return try JSONDecoder.supabase().decode(StrengthWorkoutSaveResult.self, from: res.data)
    }

    static func finishStrengthWorkoutV1(
        client: SupabaseClient,
        workoutId: Int,
        endedAt: String,
        pausedSec: Int,
        exercises: [StrengthWorkoutExerciseSaveInput],
        linked: [StrengthWorkoutFinishLinkedInput]
    ) async throws -> [StrengthWorkoutSaveResult] {
        let params = FinishStrengthWorkoutV1Params(
            p_workout_id: workoutId,
            p_ended_at: endedAt,
            p_paused_sec: pausedSec,
            p_exercises: exercises,
            p_linked: linked
        )
        let res = try await client
            .rpc("finish_strength_workout_v1", params: params)
            .execute()
        return try JSONDecoder.supabase().decode([StrengthWorkoutSaveResult].self, from: res.data)
    }
}
