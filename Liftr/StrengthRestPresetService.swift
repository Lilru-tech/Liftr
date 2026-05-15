import Foundation
import Supabase

enum StrengthRestPresetService {
    static let defaultPresets = [30, 60, 90, 120, 180]
    static let lookbackWeeks = 8
    static let minSetsWithRest = 5
    static let maxRestSec = 600

    static func computePresets(restSeconds: [Int]) -> [Int] {
        let filtered = restSeconds.filter { $0 > 0 && $0 <= maxRestSec }
        guard filtered.count >= minSetsWithRest else {
            return defaultPresets
        }

        var counts: [Int: Int] = [:]
        for rest in filtered {
            counts[rest, default: 0] += 1
        }

        let ranked = counts.sorted { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value > rhs.value }
            return lhs.key > rhs.key
        }

        var chosen = ranked.prefix(5).map(\.key)
        if chosen.count < 5 {
            for preset in defaultPresets where !chosen.contains(preset) {
                chosen.append(preset)
                if chosen.count == 5 { break }
            }
        }
        return chosen.sorted()
    }

    static func fetchQuickRestPresets(userId: UUID) async -> [Int] {
        do {
            let restSeconds = try await loadRestSeconds(userId: userId)
            return computePresets(restSeconds: restSeconds)
        } catch {
            return defaultPresets
        }
    }

    private static func loadRestSeconds(userId: UUID) async throws -> [Int] {
        let client = SupabaseManager.shared.client
        let decoder = JSONDecoder.supabase()
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        iso.timeZone = .current

        let cutoff = Calendar.current.date(byAdding: .day, value: -(lookbackWeeks * 7), to: Date()) ?? Date()

        struct WRow: Decodable { let id: Int }

        let wRes = try await client
            .from("workouts")
            .select("id")
            .eq("user_id", value: userId.uuidString)
            .eq("kind", value: "strength")
            .eq("state", value: "published")
            .gte("started_at", value: iso.string(from: cutoff))
            .execute()

        let workouts = try decoder.decode([WRow].self, from: wRes.data)
        if workouts.isEmpty { return [] }

        let workoutIds = workouts.map { String($0.id) }

        struct ExWire: Decodable { let id: Int }

        let exRes = try await client
            .from("workout_exercises")
            .select("id")
            .in("workout_id", values: workoutIds)
            .execute()

        let exRows = try decoder.decode([ExWire].self, from: exRes.data)
        let weIds = exRows.map { String($0.id) }
        if weIds.isEmpty { return [] }

        struct SetWire: Decodable { let rest_sec: Int? }

        let setRes = try await client
            .from("exercise_sets")
            .select("rest_sec")
            .in("workout_exercise_id", values: weIds)
            .execute()

        let setRows = try decoder.decode([SetWire].self, from: setRes.data)
        return setRows.compactMap(\.rest_sec)
    }
}
