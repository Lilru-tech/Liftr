import Foundation

enum GoalsManager {

    static func currentWeekStart() -> Date {
        var cal = Calendar.current
        cal.firstWeekday = 2
        let now = Date()
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
        return cal.date(from: comps) ?? now
    }

    static func dateOnlyString(_ d: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(identifier: "Europe/Madrid")
        df.dateFormat = "yyyy-MM-dd"
        return df.string(from: d)
    }
    
    private struct RecomputeParams: Encodable {
        let p_user_id: UUID
        let p_week_start: String
    }

    static func recompute(userId: UUID, weekStart: Date? = nil) async throws {
        let ws = weekStart ?? currentWeekStart()
        let params = RecomputeParams(
            p_user_id: userId,
            p_week_start: dateOnlyString(ws)
        )

        _ = try await SupabaseManager.shared.client
            .rpc("recompute_weekly_goal_results", params: params)
            .execute()
    }

    static func fetchGoalsForCurrentWeek(for userId: UUID) async throws -> [GoalRowUI] {
        let weekStart = currentWeekStart()
        let weekStr = dateOnlyString(weekStart)

        try await recompute(userId: userId, weekStart: weekStart)

        let resGoals = try await SupabaseManager.shared.client
            .from("weekly_goals")
            .select("id,user_id,week_start,metric,target_value,updated_at,title,notes")
            .eq("user_id", value: userId.uuidString)
            .eq("week_start", value: weekStr)
            .order("updated_at", ascending: false)
            .execute()

        let goals = try JSONDecoder.supabase().decode([WeeklyGoalRow].self, from: resGoals.data)

        if goals.isEmpty { return [] }

        let goalIds = goals.map { $0.id }
        let resResults = try await SupabaseManager.shared.client
            .from("weekly_goal_results")
            .select("goal_id,user_id,week_start,achieved_value,is_completed,updated_at,completed_at")
            .in("goal_id", values: goalIds.map { String($0) })
            .eq("week_start", value: weekStr)
            .execute()

        let results = try JSONDecoder.supabase().decode([WeeklyGoalResultRow].self, from: resResults.data)
        let resultsByGoal = Dictionary(grouping: results, by: { $0.goal_id })

        return goals.map { g in
            let r = resultsByGoal[g.id]?.first
            return GoalRowUI(
                id: g.id,
                userId: g.user_id,
                weekStart: g.week_start,
                title: (g.title?.isEmpty == false ? g.title! : "Goal"),
                targetValue: g.target_value,
                achievedValue: r?.achieved_value ?? 0,
                isCompleted: r?.is_completed ?? false,
                metric: g.metric.rawValue
            )
        }
    }
    
    static func fetchGoalsAllTime(for userId: UUID, limit: Int = 100) async throws -> [GoalRowUI] {
        let resGoals = try await SupabaseManager.shared.client
            .from("weekly_goals")
            .select("id,user_id,week_start,metric,target_value,updated_at,title,notes")
            .eq("user_id", value: userId.uuidString)
            .order("week_start", ascending: false)
            .limit(limit)
            .execute()

        let goals = try JSONDecoder.supabase().decode([WeeklyGoalRow].self, from: resGoals.data)
        if goals.isEmpty { return [] }

        let goalIds = Array(Set(goals.map { $0.id }))
        let resResults = try await SupabaseManager.shared.client
            .from("weekly_goal_results")
            .select("goal_id,user_id,week_start,achieved_value,is_completed,updated_at,completed_at,target_value,metric")
            .in("goal_id", values: goalIds.map { String($0) })
            .execute()

        let results = try JSONDecoder.supabase().decode([WeeklyGoalResultRow].self, from: resResults.data)

        func key(_ goalId: Int64, _ weekStart: Date) -> String {
            "\(goalId)-\(dateOnlyString(weekStart))"
        }

        let resultsByKey = Dictionary(
            uniqueKeysWithValues: results.map { (key($0.goal_id, $0.week_start), $0) }
        )

        return goals.map { g in
            let r = resultsByKey[key(g.id, g.week_start)]
            return GoalRowUI(
                id: g.id,
                userId: g.user_id,
                weekStart: g.week_start,
                title: (g.title?.isEmpty == false ? g.title! : "Goal"),
                targetValue: g.target_value,
                achievedValue: r?.achieved_value ?? 0,
                isCompleted: r?.is_completed ?? false,
                metric: g.metric.rawValue
            )
        }
    }

    static func createWeeklyGoal(userId: UUID, title: String, targetValue: Int, metric: GoalMetric = .workouts) async throws {
        let weekStart = currentWeekStart()
        let payload = WeeklyGoalInsert(
            user_id: userId,
            week_start: dateOnlyString(weekStart),
            metric: metric,
            target_value: Decimal(targetValue),
            title: title,
            notes: nil
        )

        _ = try await SupabaseManager.shared.client
            .from("weekly_goals")
            .insert(payload)
            .execute()

        try await recompute(userId: userId, weekStart: weekStart)
    }

    static func deleteGoal(userId: UUID, goalId: Int64) async throws {
        _ = try await SupabaseManager.shared.client
            .from("weekly_goal_results")
            .delete()
            .eq("goal_id", value: String(goalId))
            .execute()

        _ = try await SupabaseManager.shared.client
            .from("weekly_goals")
            .delete()
            .eq("id", value: String(goalId))
            .execute()
        
        try await recompute(userId: userId, weekStart: currentWeekStart())
    }
    
    private struct RecommendationParams: Encodable {
        let p_user_id: UUID
        let p_metric: GoalMetric
    }

    static func fetchRecommendation(userId: UUID, metric: GoalMetric) async throws -> Int {
        let params = RecommendationParams(
            p_user_id: userId,
            p_metric: metric
        )

        let res = try await SupabaseManager.shared.client
            .rpc("get_weekly_goal_recommendation", params: params)
            .execute()

        if let v = try? JSONDecoder.supabase().decode(Double.self, from: res.data) {
            return Int(v.rounded())
        }
        if let v = try? JSONDecoder.supabase().decode(Int.self, from: res.data) {
            return v
        }
        return 1
    }
    
    private struct GoalStatsParams: Encodable {
        let p_user_id: UUID
    }

    static func fetchAllTimeStats(userId: UUID) async throws -> GoalStats {
        let params = GoalStatsParams(p_user_id: userId)

        let res = try await SupabaseManager.shared.client
            .rpc("get_goal_stats", params: params)
            .execute()
        
        if let raw = String(data: res.data, encoding: .utf8) {
            print("get_goal_stats raw:", raw)
        }

        if let arr = try? JSONDecoder.supabase().decode([GoalStats].self, from: res.data),
           let first = arr.first {
            return first
        }
        if let one = try? JSONDecoder.supabase().decode(GoalStats.self, from: res.data) {
            return one
        }
        return GoalStats(
            total_goals: 0,
            finished_goals: 0,
            missed_goals: nil,
            finished_percent: 0,
            avg_progress_percent: 0,
            best_progress_percent: 0
        )
    }

    static func fetchWorkoutsContributingToGoal(_ goal: GoalRowUI) async throws -> [WorkoutFeedCardItem] {
        let client = SupabaseManager.shared.client
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        iso.timeZone = .current

        let weekEnd = Calendar.current.date(byAdding: .day, value: 7, to: goal.weekStart) ?? goal.weekStart

        let res = try await client
            .from("workouts")
            .select("id, user_id, kind, title, started_at, ended_at, state, calories_kcal, sport_sessions!sport_sessions_workout_id_fk(sport), cardio_sessions(activity_code)")
            .eq("user_id", value: goal.userId.uuidString)
            .gte("started_at", value: iso.string(from: goal.weekStart))
            .lt("started_at", value: iso.string(from: weekEnd))
            .order("started_at", ascending: false)
            .execute()

        struct SportMini: Decodable { let sport: String }
        struct CardioMini: Decodable { let activity_code: String? }
        struct W: Decodable {
            let id: Int
            let user_id: UUID
            let kind: String
            let title: String?
            let started_at: Date?
            let ended_at: Date?
            let state: String
            let calories_kcal: Decimal?
            let sport_sessions: [SportMini]?
            let cardio_sessions: [CardioMini]?
        }

        let workouts = try JSONDecoder.supabase().decode([W].self, from: res.data)

        let ids = workouts.map { String($0.id) }
        var scores: [Int: Double] = [:]
        if !ids.isEmpty {
            let sRes = try await client
                .from("workout_scores")
                .select("workout_id, score")
                .in("workout_id", values: ids)
                .execute()
            struct S: Decodable { let workout_id: Int; let score: Decimal }
            let sRows = try JSONDecoder.supabase().decode([S].self, from: sRes.data)
            for r in sRows {
                scores[r.workout_id, default: 0] += NSDecimalNumber(decimal: r.score).doubleValue
            }
        }

        struct Prof: Decodable {
            let username: String
            let avatar_url: String?
        }
        let pRes = try await client
            .from("profiles")
            .select("username, avatar_url")
            .eq("user_id", value: goal.userId.uuidString)
            .limit(1)
            .execute()
        let profRows = try JSONDecoder.supabase().decode([Prof].self, from: pRes.data)
        let username = profRows.first?.username ?? "User"
        let avatarURL = profRows.first?.avatar_url

        return workouts.map { w in
            let kcal = w.calories_kcal.map { NSDecimalNumber(decimal: $0).doubleValue }
            let scoreVal = scores[w.id]
            return WorkoutFeedCardItem(
                workoutId: w.id,
                userId: w.user_id,
                kind: w.kind,
                title: w.title,
                state: w.state,
                startedAt: w.started_at,
                endedAt: w.ended_at,
                caloriesKcal: kcal,
                score: scoreVal,
                sport: w.sport_sessions?.first?.sport,
                cardioActivity: w.cardio_sessions?.first?.activity_code,
                username: username,
                avatarURL: avatarURL,
                likeCount: 0,
                isLiked: false,
                coUserAvatarURLs: []
            )
        }
    }
}
