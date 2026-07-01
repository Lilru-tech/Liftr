import Foundation
import SwiftUI

struct WeeklyTasksHomeSummary: Decodable, Equatable {
    let week_start: Date
    let accepted_count: Int
    let accept_slots_remaining: Int
    let available_count: Int
    let completed_count_this_week: Int

    var hasPickableTasks: Bool {
        accept_slots_remaining > 0 && available_count > 0
    }
}

enum WeeklyTasksHomeBadgeState {
    private static let lastSeenCountKey = "weeklyTasksLastSeenCompletedCount"
    private static let lastSeenWeekStartKey = "weeklyTasksLastSeenWeekStart"

    private static var defaults: UserDefaults { .standard }

    private static func weekStartKey(_ weekStart: Date) -> String {
        ISO8601DateFormatter().string(from: weekStart)
    }

    private static func effectiveLastSeenCount(for summary: WeeklyTasksHomeSummary) -> Int {
        let storedWeek = defaults.string(forKey: lastSeenWeekStartKey)
        let currentWeek = weekStartKey(summary.week_start)
        if storedWeek != currentWeek {
            return 0
        }
        return defaults.integer(forKey: lastSeenCountKey)
    }

    static func hasUnseenCompletion(_ summary: WeeklyTasksHomeSummary) -> Bool {
        summary.completed_count_this_week > effectiveLastSeenCount(for: summary)
    }

    static func markSeen(_ summary: WeeklyTasksHomeSummary) {
        defaults.set(summary.completed_count_this_week, forKey: lastSeenCountKey)
        defaults.set(weekStartKey(summary.week_start), forKey: lastSeenWeekStartKey)
    }

    static func accentDotColor(for summary: WeeklyTasksHomeSummary) -> Color? {
        if hasUnseenCompletion(summary) {
            return Color(red: 0.204, green: 0.780, blue: 0.349)
        }
        if summary.hasPickableTasks {
            return Color(red: 1.0, green: 0.584, blue: 0.0)
        }
        return nil
    }

    static func pillShowsPickSubtitle(for summary: WeeklyTasksHomeSummary) -> Bool {
        summary.hasPickableTasks
    }
}

enum WeeklyTasksHomeSummaryLoader {
    static func fetch() async -> WeeklyTasksHomeSummary? {
        do {
            let res = try await SupabaseManager.shared.client
                .rpc("get_my_weekly_tasks_home_summary_v1")
                .execute()
            return try JSONDecoder.supabase().decode(WeeklyTasksHomeSummary.self, from: res.data)
        } catch {
            return nil
        }
    }

    static func markSeenIfPossible() async {
        guard let summary = await fetch() else { return }
        WeeklyTasksHomeBadgeState.markSeen(summary)
    }
}
