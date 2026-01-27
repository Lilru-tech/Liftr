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
        return GoalStats(total_goals: 0, finished_goals: 0, finished_percent: 0, avg_progress_percent: 0, best_progress_percent: 0)
    }
}
