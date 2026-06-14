import Foundation
import Supabase

final class CompetitionService {
    static let shared = CompetitionService()
    private init() {}

    private var client: SupabaseClient { SupabaseManager.shared.client }
    private struct CreateCompetitionParams: Encodable {
        let p_opponent_id: String
        let p_time_limit_at: String?
        let p_metric: String?
        let p_target_value: Double?
        let p_expire_hours: Int
        let p_bet_amount: Int
    }

    private struct CompetitionIdParams: Encodable {
        let p_competition_id: Int
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
        do {
            _ = try await client
                .rpc("expire_stale_competition_invites_v1")
                .execute()
        } catch {
            print("[Competitions][expirePendingIfNeeded] error:", error.localizedDescription)
        }
    }

    func fetchMaxBet(opponentId: UUID) async throws -> Int {
        struct Params: Encodable {
            let p_opponent_id: String
        }
        struct Row: Decodable {
            let competition_get_max_bet_v1: Int?
        }
        let res = try await client
            .rpc("competition_get_max_bet_v1", params: Params(p_opponent_id: opponentId.uuidString))
            .execute()
        if let scalar = try? JSONDecoder.supabase().decode(Int.self, from: res.data) {
            return max(0, scalar)
        }
        let row = try JSONDecoder.supabase().decode(Row.self, from: res.data)
        return max(0, row.competition_get_max_bet_v1 ?? 0)
    }

    func fetchEscrowSummary() async throws -> CompetitionEscrowSummary {
        let res = try await client
            .rpc("get_my_competition_escrow_summary_v1")
            .execute()
        return try JSONDecoder.supabase().decode(CompetitionEscrowSummary.self, from: res.data)
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
        inviteHours: Int = 48,
        betAmount: Int = 0
    ) async throws -> Int {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        iso.timeZone = .current

        let params = CreateCompetitionParams(
            p_opponent_id: opponentId.uuidString,
            p_time_limit_at: timeLimitAt.map { iso.string(from: $0) },
            p_metric: metric?.rawValue,
            p_target_value: targetValue,
            p_expire_hours: inviteHours,
            p_bet_amount: max(0, betAmount)
        )

        let res = try await client
            .rpc("rpc_create_competition", params: params)
            .execute()

        if let scalar = try? JSONDecoder.supabase().decode(Int.self, from: res.data) {
            await CoinManager.shared.refreshBalanceAfterMutation(notifyIfEarned: false)
            return scalar
        }

        struct IdRow: Decodable { let rpc_create_competition: Int? }
        let row = try JSONDecoder.supabase().decode(IdRow.self, from: res.data)
        let compId = row.rpc_create_competition ?? 0
        await CoinManager.shared.refreshBalanceAfterMutation(notifyIfEarned: false)
        return compId
    }

    func acceptCompetition(competitionId: Int) async throws {
        try await client
            .rpc("accept_competition", params: CompetitionIdParams(p_competition_id: competitionId))
            .execute()
        await CoinManager.shared.refreshBalanceAfterMutation(notifyIfEarned: true)
    }

    func declineCompetition(competitionId: Int) async throws {
        try await client
            .rpc("decline_competition", params: CompetitionIdParams(p_competition_id: competitionId))
            .execute()
        await CoinManager.shared.refreshBalanceAfterMutation(notifyIfEarned: true)
    }

    func cancelCompetition(competitionId: Int) async throws {
        try await client
            .rpc("cancel_competition_invite", params: CompetitionIdParams(p_competition_id: competitionId))
            .execute()
        await CoinManager.shared.refreshBalanceAfterMutation(notifyIfEarned: true)
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
