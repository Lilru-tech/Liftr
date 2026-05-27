import Foundation
import Supabase

enum PremiumStatusClient {
    private static let rpcName = "get_user_premium_status_v1"

    static func fetchIsPremium(client: SupabaseClient = SupabaseManager.shared.client) async -> Bool {
        do {
            let res = try await client.rpc(rpcName).execute()
            if let value = try? JSONDecoder().decode(Bool.self, from: res.data) {
                return value
            }
            if let values = try? JSONDecoder().decode([Bool].self, from: res.data),
               let first = values.first {
                return first
            }
            let trimmed = String(data: res.data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased() ?? ""
            if trimmed == "true" { return true }
            if trimmed == "false" { return false }
            return false
        } catch {
            return false
        }
    }
}
