import Foundation
import Supabase

struct StrengthRoutinePersistOutcome: Equatable {
    let alsoHasAnotherRoutineWithSameProgram: Bool
}

enum StrengthRoutineRemotePersistence {
    static func nextSortOrderForInsert(
        client: SupabaseClient,
        userId: UUID,
        folderId: Int64?
    ) async throws -> Int {
        try await nextRoutineSortOrderForInsert(client: client, userId: userId, folderId: folderId)
    }

    static func insertStrengthRoutineTemplate(
        client: SupabaseClient,
        userId: UUID,
        name: String,
        folderId: Int64?,
        exercises: [EditableExercise],
        replaceRoutineId: Int64? = nil
    ) async throws -> StrengthRoutinePersistOutcome {
        let strengthItems = exercises.compactMap { $0.toStrengthItem() }
        guard !strengthItems.isEmpty else {
            throw NSError(
                domain: "StrengthRoutine",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Add at least one exercise with reps before saving a routine."]
            )
        }

        struct RoutineIdRow: Decodable { let id: Int64 }
        struct RoutineExerciseIdRow: Decodable { let id: Int64 }

        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return StrengthRoutinePersistOutcome(alsoHasAnotherRoutineWithSameProgram: false)
        }

        let contentHash = strengthRoutineContentFingerprint(from: exercises)

        if let rid = replaceRoutineId {
            _ = try await client
                .from("strength_routines")
                .delete()
                .eq("id", value: Int(rid))
                .eq("user_id", value: userId)
                .execute()
        }

        let nextSort = try await nextRoutineSortOrderForInsert(client: client, userId: userId, folderId: folderId)

        struct StrengthRoutineRowInsert: Encodable {
            let user_id: UUID
            let name: String
            let folder_id: Int64?
            let content_hash: String
            let sort_order: Int
        }

        let headerRes = try await client
            .from("strength_routines")
            .insert(
                StrengthRoutineRowInsert(
                    user_id: userId,
                    name: trimmed,
                    folder_id: folderId,
                    content_hash: contentHash,
                    sort_order: nextSort
                ),
                returning: .representation
            )
            .select("id")
            .limit(1)
            .execute()

        let idRows = try JSONDecoder.supabase().decode([RoutineIdRow].self, from: headerRes.data)
        guard let routineId = idRows.first?.id else {
            throw NSError(
                domain: "StrengthRoutine",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Routine was not saved (could not read the new routine)."]
            )
        }

        struct StrengthRoutineExerciseRowInsert: Encodable {
            let routine_id: Int64
            let exercise_id: Int64
            let order_index: Int
            let notes: String?
            let custom_name: String?
        }

        struct StrengthRoutineSetRowInsert: Encodable {
            let routine_exercise_id: Int64
            let set_number: Int
            let reps: Int?
            let weight_kg: Double?
            let rpe: Double?
            let rest_sec: Int?
            let notes: String?
            let weight_segments: [StrengthWeightSegWire]?
        }

        for item in strengthItems {
            let exRes = try await client
                .from("strength_routine_exercises")
                .insert(
                    StrengthRoutineExerciseRowInsert(
                        routine_id: routineId,
                        exercise_id: item.exercise_id,
                        order_index: item.order_index,
                        notes: item.notes,
                        custom_name: item.custom_name
                    ),
                    returning: .representation
                )
                .select("id")
                .limit(1)
                .execute()

            let exIdRows = try JSONDecoder.supabase().decode([RoutineExerciseIdRow].self, from: exRes.data)
            guard let exerciseRowId = exIdRows.first?.id else {
                throw NSError(
                    domain: "StrengthRoutine",
                    code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "Routine was not saved (exercise row missing)."]
                )
            }

            let setRows: [StrengthRoutineSetRowInsert] = item.sets.map { s in
                let ws: [StrengthWeightSegWire]? = {
                    guard let segs = s.weight_segments, segs.count >= 2 else { return nil }
                    return segs.map { StrengthWeightSegWire(reps: $0.reps, weight_kg: $0.weight_kg) }
                }()
                return StrengthRoutineSetRowInsert(
                    routine_exercise_id: exerciseRowId,
                    set_number: s.set_number,
                    reps: s.reps,
                    weight_kg: s.weight_kg,
                    rpe: s.rpe,
                    rest_sec: s.rest_sec,
                    notes: s.notes,
                    weight_segments: ws
                )
            }
            if !setRows.isEmpty {
                _ = try await client.from("strength_routine_sets").insert(setRows).execute()
            }
        }

        let dupCount = try await otherRoutinesWithSameContentCount(
            client: client,
            userId: userId,
            folderId: folderId,
            contentHash: contentHash,
            excludingRoutineId: routineId
        )
        return StrengthRoutinePersistOutcome(alsoHasAnotherRoutineWithSameProgram: dupCount > 0)
    }
}

private func nextRoutineSortOrderForInsert(
    client: SupabaseClient,
    userId: UUID,
    folderId: Int64?
) async throws -> Int {
    struct R: Decodable { let sort_order: Int? }
    let res: [R]
    if let fid = folderId {
        let r = try await client
            .from("strength_routines")
            .select("sort_order")
            .eq("user_id", value: userId)
            .eq("folder_id", value: Int(fid))
            .order("sort_order", ascending: false)
            .limit(1)
            .execute()
        res = try JSONDecoder.supabase().decode([R].self, from: r.data)
    } else {
        let r = try await client
            .from("strength_routines")
            .select("sort_order")
            .eq("user_id", value: userId)
            .is("folder_id", value: nil)
            .order("sort_order", ascending: false)
            .limit(1)
            .execute()
        res = try JSONDecoder.supabase().decode([R].self, from: r.data)
    }
    return (res.first?.sort_order ?? 0) + 1
}

private func otherRoutinesWithSameContentCount(
    client: SupabaseClient,
    userId: UUID,
    folderId: Int64?,
    contentHash: String,
    excludingRoutineId: Int64
) async throws -> Int {
    struct R: Decodable { let id: Int64 }
    let res: [R]
    if let fid = folderId {
        let r = try await client
            .from("strength_routines")
            .select("id")
            .eq("user_id", value: userId)
            .eq("content_hash", value: contentHash)
            .eq("folder_id", value: Int(fid))
            .neq("id", value: Int(excludingRoutineId))
            .limit(8)
            .execute()
        res = try JSONDecoder.supabase().decode([R].self, from: r.data)
    } else {
        let r = try await client
            .from("strength_routines")
            .select("id")
            .eq("user_id", value: userId)
            .eq("content_hash", value: contentHash)
            .is("folder_id", value: nil)
            .neq("id", value: Int(excludingRoutineId))
            .limit(8)
            .execute()
        res = try JSONDecoder.supabase().decode([R].self, from: r.data)
    }
    return res.count
}
