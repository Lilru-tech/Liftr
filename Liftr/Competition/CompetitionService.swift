import Foundation
import Supabase

final class CompetitionService {
    static let shared = CompetitionService()
    private init() {}

    private var client: SupabaseClient { SupabaseManager.shared.client }
    private struct CompetitionInsertPayload: Encodable {
        let created_by: String
        let user_a: String
        let user_b: String
        let status: String
        let invite_expires_at: String
    }

    private struct CompetitionGoalInsertPayload: Encodable {
        let competition_id: Int
        let time_limit_at: String?
        let metric: String?
        let target_value: Double?
    }

    private struct CompetitionBlockUpsertPayload: Encodable {
        let blocker_id: String
        let blocked_id: String
    }
    
    private struct ReviewWorkoutParams: Encodable {
        let p_competition_workout_id: Int
        let p_accept: Bool
    }

    func expirePendingIfNeeded() async {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        iso.timeZone = .current
        let nowStr = iso.string(from: Date())

        do {
            _ = try await client
                .from("competitions")
                .update([
                    "status": "expired",
                    "finished_at": nowStr
                ])
                .eq("status", value: "pending")
                .lt("invite_expires_at", value: nowStr)
                .execute()
        } catch {
            print("[Competitions][expirePendingIfNeeded] error:", error.localizedDescription)
        }
    }

    func fetchCompetitions(for userId: UUID) async throws -> [CompetitionRow] {
        let res = try await client
            .from("competitions")
            .select("*")
            .or("user_a.eq.\(userId.uuidString),user_b.eq.\(userId.uuidString)")
            .order("created_at", ascending: false)
            .execute()

        return try JSONDecoder.supabase().decode([CompetitionRow].self, from: res.data)
    }

    func fetchGoals(for competitionIds: [Int]) async throws -> [Int: CompetitionGoalRow] {
        guard !competitionIds.isEmpty else { return [:] }

        let res = try await client
            .from("competition_goals")
            .select("*")
            .in("competition_id", values: competitionIds)
            .execute()

        let rows = try JSONDecoder.supabase().decode([CompetitionGoalRow].self, from: res.data)
        var dict: [Int: CompetitionGoalRow] = [:]
        for g in rows { dict[g.competition_id] = g }
        return dict
    }

    func fetchProfiles(userIds: [UUID]) async throws -> [UUID: ProfileLiteRow] {
        let ids = Array(Set(userIds))
        guard !ids.isEmpty else { return [:] }

        let res = try await client
            .from("profiles")
            .select("user_id,username,avatar_url")
            .in("user_id", values: ids.map { $0.uuidString })
            .execute()

        let rows = try JSONDecoder.supabase().decode([ProfileLiteRow].self, from: res.data)
        var dict: [UUID: ProfileLiteRow] = [:]
        for p in rows { dict[p.user_id] = p }
        return dict
    }

    func fetchProgress(for competitionIds: [Int]) async throws -> [Int: [UUID: CompetitionProgress]] {
        guard !competitionIds.isEmpty else { return [:] }

        let res = try await client
            .from("competition_workouts")
            .select("competition_id,workout_owner_id,status,score_snapshot,calories_snapshot")
            .in("competition_id", values: competitionIds)
            .eq("status", value: "accepted")
            .execute()

        struct Row: Decodable {
            let competition_id: Int
            let workout_owner_id: UUID
            let status: String
            let score_snapshot: Decimal?
            let calories_snapshot: Decimal?
        }

        let rows = try JSONDecoder.supabase().decode([Row].self, from: res.data)

        var out: [Int: [UUID: CompetitionProgress]] = [:]
        for r in rows {
            var byUser = out[r.competition_id] ?? [:]
            var prog = byUser[r.workout_owner_id] ?? CompetitionProgress()
            prog.workoutsCount += 1
            prog.scoreTotal += NSDecimalNumber(decimal: (r.score_snapshot ?? 0)).doubleValue
            prog.caloriesTotal += NSDecimalNumber(decimal: (r.calories_snapshot ?? 0)).doubleValue
            byUser[r.workout_owner_id] = prog
            out[r.competition_id] = byUser
        }
        return out
    }

    func createCompetition(
        creatorId: UUID,
        opponentId: UUID,
        metric: CompetitionMetric?,
        targetValue: Double?,
        timeLimitAt: Date?,
        inviteHours: Int = 48
    ) async throws -> Int {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        iso.timeZone = .current

        let expires = Calendar.current.date(byAdding: .hour, value: inviteHours, to: Date()) ?? Date().addingTimeInterval(48*3600)

        let insert = CompetitionInsertPayload(
            created_by: creatorId.uuidString,
            user_a: creatorId.uuidString,
            user_b: opponentId.uuidString,
            status: "pending",
            invite_expires_at: iso.string(from: expires)
        )

        let res = try await client
            .from("competitions")
            .insert(insert, returning: .representation)
            .select("id")
            .single()
            .execute()

        struct IdRow: Decodable { let id: Int }
        let row = try JSONDecoder.supabase().decode(IdRow.self, from: res.data)
        let compId = row.id

        let goalInsert = CompetitionGoalInsertPayload(
            competition_id: compId,
            time_limit_at: timeLimitAt.map { iso.string(from: $0) },
            metric: metric?.rawValue,
            target_value: targetValue
        )

        _ = try await client
            .from("competition_goals")
            .insert(goalInsert)
            .execute()

        return compId
    }

    func acceptCompetition(competitionId: Int) async throws {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        iso.timeZone = .current
        let nowStr = iso.string(from: Date())

        _ = try await client
            .from("competitions")
            .update([
                "status": "active",
                "accepted_at": nowStr
            ])
            .eq("id", value: competitionId)
            .execute()
    }

    func declineCompetition(competitionId: Int) async throws {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        iso.timeZone = .current
        let nowStr = iso.string(from: Date())

        _ = try await client
            .from("competitions")
            .update([
                "status": "declined",
                "declined_at": nowStr,
                "finished_at": nowStr
            ])
            .eq("id", value: competitionId)
            .execute()
    }

    func cancelCompetition(competitionId: Int) async throws {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        iso.timeZone = .current
        let nowStr = iso.string(from: Date())

        _ = try await client
            .from("competitions")
            .update([
                "status": "cancelled",
                "cancelled_at": nowStr,
                "finished_at": nowStr
            ])
            .eq("id", value: competitionId)
            .execute()
    }

    func blockUser(me: UUID, other: UUID) async throws {
        let insert = CompetitionBlockUpsertPayload(
            blocker_id: me.uuidString,
            blocked_id: other.uuidString
        )
        _ = try await client
            .from("competition_blocks")
            .upsert(insert, onConflict: "blocker_id,blocked_id")
            .execute()
    }

    func unblockUser(me: UUID, other: UUID) async throws {
        _ = try await client
            .from("competition_blocks")
            .delete()
            .eq("blocker_id", value: me.uuidString)
            .eq("blocked_id", value: other.uuidString)
            .execute()
    }
    
    func submitWorkoutToCompetition(competitionId: Int, workoutId: Int) async throws {
        try await client.rpc("submit_workout_to_competition", params: [
            "p_competition_id": competitionId,
            "p_workout_id": workoutId
        ]).execute()
    }

    func reviewWorkout(competitionWorkoutId: Int, accept: Bool) async throws {
        let params = ReviewWorkoutParams(
            p_competition_workout_id: competitionWorkoutId,
            p_accept: accept
        )
        
        try await client
            .rpc("review_competition_workout", params: params)
            .execute()
    }

    func fetchPendingWorkoutReviews(for userId: UUID) async throws -> [CompetitionWorkoutRow] {
        let res = try await client
            .from("competition_workouts")
            .select("""
                id, competition_id, workout_id, workout_owner_id,
                status, score_snapshot, calories_snapshot, created_at, updated_at,
                competitions!inner(user_a,user_b)
            """)
            .eq("status", value: "pending")
            .neq("workout_owner_id", value: userId.uuidString)
            .execute()

        return try JSONDecoder.supabase().decode([CompetitionWorkoutRow].self, from: res.data)
    }
    
    func fetchCompetitionWorkouts(competitionId: Int) async throws -> [CompetitionWorkoutRow] {
        let res = try await client
            .from("competition_workouts")
            .select("id, competition_id, workout_id, workout_owner_id, status, score_snapshot, calories_snapshot, created_at, updated_at")
            .eq("competition_id", value: competitionId)
            .order("created_at", ascending: false)
            .execute()

        return try JSONDecoder.supabase().decode([CompetitionWorkoutRow].self, from: res.data)
    }

    func fetchWorkoutsLite(ids: [Int]) async throws -> [Int: WorkoutLiteRow] {
        guard !ids.isEmpty else { return [:] }

        let res = try await client
            .from("workouts")
            .select("id,user_id,title,kind,started_at,calories_kcal")
            .in("id", values: ids)
            .execute()

        let rows = try JSONDecoder.supabase().decode([WorkoutLiteRow].self, from: res.data)
        var dict: [Int: WorkoutLiteRow] = [:]
        for w in rows { dict[w.id] = w }
        return dict
    }
    
    func fetchMyActiveCompetitionId() async -> Int? {
        guard let session = try? await client.auth.session else { return nil }
        let uid = session.user.id.uuidString
        
        let res = try? await client
            .from("competitions")
            .select("id")
            .eq("status", value: "active")
            .or("user_a.eq.\(uid),user_b.eq.\(uid)")
            .limit(1)
            .single()
            .execute()
        
        struct Row: Decodable { let id: Int }
        if let data = res?.data,
           let row = try? JSONDecoder.supabase().decode(Row.self, from: data) {
            return row.id
        }
        return nil
    }
    
    func fetchActiveOrPendingCompetitionBetween(me: UUID, other: UUID) async throws -> CompetitionRow? {
        let res = try await client
            .from("competitions")
            .select("*")
            .in("status", values: ["active", "pending"])
            .or("and(user_a.eq.\(me.uuidString),user_b.eq.\(other.uuidString)),and(user_a.eq.\(other.uuidString),user_b.eq.\(me.uuidString))")
            .order("created_at", ascending: false)
            .limit(1)
            .execute()

        let rows = try JSONDecoder.supabase().decode([CompetitionRow].self, from: res.data)
        return rows.first
    }
}
