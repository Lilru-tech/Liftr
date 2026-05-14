import Foundation
import Supabase

enum BodyWeightSource: String, Codable, CaseIterable, Hashable {
    case manual
    case appleHealth = "apple_health"
    case healthConnect = "health_connect"
}

struct BodyWeightEntry: Decodable, Identifiable, Hashable {
    let id: UUID
    let user_id: UUID
    let measured_at: Date
    let weight_kg: Double
    let source: String
    let external_sample_id: String?
    let created_at: Date?
    let updated_at: Date?

    var sourceKind: BodyWeightSource {
        BodyWeightSource(rawValue: source) ?? .manual
    }
}

struct BodyWeightUpsertResult: Decodable, Hashable {
    let entry_id: UUID?
    let inserted: Bool?
    let duplicate: Bool?
}

struct BodyWeightChartPoint: Identifiable, Hashable {
    let id: UUID
    let label: String
    let value: Double
    let measuredAt: Date
}

enum BodyWeightRangePreset: String, CaseIterable, Identifiable {
    case days30
    case days90
    case days365

    var id: String { rawValue }

    var title: String {
        switch self {
        case .days30: return "30 days"
        case .days90: return "90 days"
        case .days365: return "365 days"
        }
    }

    func startDate(relativeTo now: Date = Date()) -> Date {
        let days: Int
        switch self {
        case .days30: days = 30
        case .days90: days = 90
        case .days365: days = 365
        }
        return Calendar.current.date(byAdding: .day, value: -days, to: now) ?? now
    }
}

enum BodyWeightPresentation {
    static func formatKg(_ value: Double) -> String {
        String(format: "%.1f kg", value)
    }

    static func deltaText(current: Double, previous: Double?) -> String? {
        guard let previous else { return nil }
        let delta = current - previous
        if abs(delta) < 0.05 { return "No change vs previous entry" }
        let sign = delta > 0 ? "+" : ""
        return "\(sign)\(String(format: "%.1f", delta)) kg vs previous entry"
    }

    static func periodDeltaText(entries: [BodyWeightEntry], days: Int, now: Date = Date()) -> String? {
        let sorted = entries.sorted { $0.measured_at < $1.measured_at }
        guard let latest = sorted.last else { return nil }
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: now) else { return nil }
        let baseline = sorted.last(where: { $0.measured_at <= cutoff }) ?? sorted.first
        guard let baseline, baseline.id != latest.id || baseline.measured_at <= cutoff else { return nil }
        let delta = latest.weight_kg - baseline.weight_kg
        if abs(delta) < 0.05 { return "No net change in the last \(days) days" }
        let sign = delta > 0 ? "+" : ""
        return "\(sign)\(String(format: "%.1f", delta)) kg in the last \(days) days"
    }

    static func chartPoints(from entries: [BodyWeightEntry], preset: BodyWeightRangePreset, now: Date = Date()) -> [BodyWeightChartPoint] {
        let start = preset.startDate(relativeTo: now)
        let filtered = entries
            .filter { $0.measured_at >= start }
            .sorted { $0.measured_at < $1.measured_at }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return filtered.map {
            BodyWeightChartPoint(
                id: $0.id,
                label: formatter.string(from: $0.measured_at),
                value: $0.weight_kg,
                measuredAt: $0.measured_at
            )
        }
    }

    static func sourceLabel(_ source: BodyWeightSource) -> String {
        switch source {
        case .manual: return "Manual"
        case .appleHealth: return "Apple Health"
        case .healthConnect: return "Health Connect"
        }
    }
}

enum BodyWeightClient {
    private struct UpsertParams: Encodable {
        let p_measured_at: String
        let p_weight_kg: Double
        let p_source: String
        let p_external_sample_id: String?
    }

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static func listEntries(limit: Int = 500) async throws -> [BodyWeightEntry] {
        let res = try await SupabaseManager.shared.client
            .from("body_weight_entries")
            .select("id,user_id,measured_at,weight_kg,source,external_sample_id,created_at,updated_at")
            .order("measured_at", ascending: false)
            .limit(limit)
            .execute()
        return try JSONDecoder.supabase().decode([BodyWeightEntry].self, from: res.data)
    }

    static func upsertEntry(
        measuredAt: Date,
        weightKg: Double,
        source: BodyWeightSource,
        externalSampleId: String? = nil
    ) async throws -> BodyWeightUpsertResult {
        let params = UpsertParams(
            p_measured_at: iso.string(from: measuredAt),
            p_weight_kg: weightKg,
            p_source: source.rawValue,
            p_external_sample_id: externalSampleId
        )
        let res = try await SupabaseManager.shared.client
            .rpc("upsert_body_weight_entry", params: params)
            .execute()
        return try JSONDecoder.supabase().decode(BodyWeightUpsertResult.self, from: res.data)
    }

    static func deleteEntry(id: UUID) async throws {
        _ = try await SupabaseManager.shared.client
            .from("body_weight_entries")
            .delete()
            .eq("id", value: id.uuidString)
            .execute()
    }

    static func updateManualEntry(id: UUID, measuredAt: Date, weightKg: Double) async throws {
        let payload: [String: AnyEncodable] = [
            "measured_at": AnyEncodable(iso.string(from: measuredAt)),
            "weight_kg": AnyEncodable(weightKg),
            "source": AnyEncodable(BodyWeightSource.manual.rawValue)
        ]
        _ = try await SupabaseManager.shared.client
            .from("body_weight_entries")
            .update(payload)
            .eq("id", value: id.uuidString)
            .execute()
    }
}
