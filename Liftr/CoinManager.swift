import Foundation
import SwiftUI
import Supabase

enum CoinSourcesPeriod: String, CaseIterable, Identifiable {
    case week
    case month
    case year
    case allTime

    var id: String { rawValue }

    var label: String {
        switch self {
        case .week: return "Week"
        case .month: return "Month"
        case .year: return "Year"
        case .allTime: return "All time"
        }
    }
}

struct CoinSourceSlice: Identifiable {
    let sourceKey: String
    let totalAmount: Int

    var id: String { sourceKey }
    var label: String { CoinManager.sourceCategoryLabel(for: sourceKey) }
    var color: Color { CoinManager.sourceCategoryColor(for: sourceKey) }
}

@MainActor
final class CoinManager: ObservableObject {
    static let shared = CoinManager()

    @Published private(set) var balance: Int = 0

    private struct BalanceRow: Decodable {
        let coins_balance: Int?
    }

    private struct TransactionRow: Decodable {
        let amount: Int
        let action_type: String
        let created_at: Date
    }

    private var lastEarnToastAt: Date?
    private let earnToastDebounce: TimeInterval = 2
    private var hasEstablishedBalanceBaseline = false
    private let earnToastMaxAge: TimeInterval = 120

    private init() {}

    func syncBalance(_ value: Int) {
        balance = max(0, value)
        hasEstablishedBalanceBaseline = true
    }

    func resetSession() {
        balance = 0
        hasEstablishedBalanceBaseline = false
        lastEarnToastAt = nil
    }

    func refreshBalance(notifyIfEarned: Bool = false) async {
        guard let userId = AppState.shared.userId else { return }

        let previousBalance = balance
        let client = SupabaseManager.shared.client

        do {
            let rows: [BalanceRow] = try await client
                .from("profiles")
                .select("coins_balance")
                .eq("user_id", value: userId.uuidString)
                .limit(1)
                .execute()
                .value

            guard let row = rows.first else { return }
            balance = max(0, row.coins_balance ?? 0)

            if !hasEstablishedBalanceBaseline {
                hasEstablishedBalanceBaseline = true
                return
            }

            if notifyIfEarned, balance > previousBalance {
                await showEarnToast(userId: userId, fallbackDelta: balance - previousBalance)
            }
        } catch {
            print("CoinManager refreshBalance error:", error.localizedDescription)
        }
    }

    func refreshBalanceAfterMutation(notifyIfEarned: Bool = true) async {
        await refreshBalance(notifyIfEarned: notifyIfEarned)
    }

    private func showEarnToast(userId: UUID, fallbackDelta: Int) async {
        let now = Date()
        if let last = lastEarnToastAt, now.timeIntervalSince(last) < earnToastDebounce {
            return
        }

        let client = SupabaseManager.shared.client

        do {
            var params: [String: AnyJSON] = [:]
            params["p_limit"] = AnyJSON(5)
            let res = try await client
                .rpc("list_my_coin_transactions_v1", params: params)
                .execute()
            let rows = try JSONDecoder.supabase().decode([TransactionRow].self, from: res.data)

            guard let recent = rows.first(where: { $0.amount > 0 }) else { return }
            let age = now.timeIntervalSince(recent.created_at)
            guard age >= 0, age < earnToastMaxAge else { return }

            let amount = recent.amount
            let label = Self.displayLabel(for: recent.action_type)
            let message = "+\(amount) Liftr Coins · \(label)"

            lastEarnToastAt = now
            AppState.shared.coinEarnToast = message
        } catch {
            return
        }
    }

    nonisolated static func formattedAmount(_ amount: Int) -> String {
        amount >= 0 ? "+\(amount)" : "\(amount)"
    }

    nonisolated static func displayLabel(for actionType: String) -> String {
        switch actionType {
        case "like_given": return "Like given"
        case "comment_added": return "Comment added"
        case "user_followed": return "Follow"
        case "earned_follower": return "New follower"
        case "achievement_unlocked": return "Achievement"
        case "workout_logged": return "Workout logged"
        case "workout_pet_training_bonus": return "Pet workout bonus"
        case "workout_coin_doubling_v1": return "Workout reward boost"
        case "workout_economy_rebalance_v1": return "Workout economy update"
        case "pet_passive_economy_rebalance_v1": return "Pet passive rebalance"
        case "workout_economy_reduction_30pct_v1": return "Workout economy adjustment"
        case "pet_passive_economy_reduction_30pct_v1": return "Pet passive adjustment"
        case "weekly_goal_perfect_week": return "Perfect week"
        case "workout_consistency_streak": return "7-day streak"
        case "competition_bet_escrow": return "Competition stake"
        case "competition_bet_win": return "Competition win"
        case "competition_bet_refund_draw": return "Competition draw refund"
        case "competition_bet_refund_cancelled": return "Competition refund"
        case "pet_coins_generated": return "Pet coins"
        case "pet_market_purchase": return "Pet shop purchase"
        case "pet_egg_reroll": return "Egg reroll"
        case "pet_rarity_upgrade": return "Pet rarity upgrade"
        case "nutrition_ingredient_logged": return "Food logged"
        case "nutrition_recipe_logged": return "Recipe logged"
        case "nutrition_ingredient_created": return "Ingredient created"
        case "nutrition_recipe_created": return "Recipe created"
        default:
            if actionType.isEmpty { return "Coins earned" }
            return actionType
                .replacingOccurrences(of: "_", with: " ")
                .capitalized
        }
    }

    nonisolated static func sourceCategoryLabel(for key: String) -> String {
        switch key {
        case "workouts": return "Workouts"
        case "pet_workout_bonus": return "Pet workout bonus"
        case "pet_coins": return "Pet coins"
        case "social": return "Social"
        case "nutrition": return "Nutrition"
        case "achievements": return "Achievements"
        case "goals_streaks": return "Goals & streaks"
        case "competition": return "Competition"
        case "pet_combat": return "Pet combat"
        case "other": return "Other"
        default:
            return key.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    nonisolated static func sourceCategoryColor(for key: String) -> Color {
        switch key {
        case "workouts": return Color(red: 0.12, green: 0.53, blue: 0.90)
        case "pet_workout_bonus": return Color(red: 0.61, green: 0.15, blue: 0.69)
        case "pet_coins": return Color(red: 1.0, green: 0.76, blue: 0.03)
        case "social": return Color(red: 0.91, green: 0.12, blue: 0.39)
        case "nutrition": return Color(red: 0.30, green: 0.69, blue: 0.31)
        case "achievements": return Color(red: 1.0, green: 0.34, blue: 0.13)
        case "goals_streaks": return Color(red: 0.0, green: 0.74, blue: 0.83)
        case "competition": return Color(red: 0.47, green: 0.33, blue: 0.28)
        case "pet_combat": return Color(red: 0.40, green: 0.23, blue: 0.72)
        default: return Color(red: 0.62, green: 0.62, blue: 0.62)
        }
    }

    nonisolated static func coinSourcesTimeWindow(for period: CoinSourcesPeriod) -> (start: Date?, end: Date?) {
        guard period != .allTime else { return (nil, nil) }

        var cal = Calendar.current
        cal.timeZone = .current
        let now = Date()
        let dayStart = cal.startOfDay(for: now)

        switch period {
        case .allTime:
            return (nil, nil)
        case .week:
            let start = cal.date(byAdding: .day, value: -6, to: dayStart) ?? dayStart
            let end = cal.date(byAdding: .day, value: 1, to: dayStart) ?? now
            return (start, end)
        case .month:
            let start = cal.date(byAdding: .day, value: -29, to: dayStart) ?? dayStart
            let end = cal.date(byAdding: .day, value: 1, to: dayStart) ?? now
            return (start, end)
        case .year:
            let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now
            let start = cal.date(byAdding: .month, value: -11, to: monthStart) ?? monthStart
            let end = cal.date(byAdding: .day, value: 1, to: dayStart) ?? now
            return (start, end)
        }
    }
}
