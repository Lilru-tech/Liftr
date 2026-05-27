import Foundation
import Testing
@testable import Liftr

struct BodyWeightRegressionTests {
    @Test func deltaTextWhenNoChange() {
        #expect(BodyWeightPresentation.deltaText(current: 80.0, previous: 80.0) == "No change vs previous entry")
    }

    @Test func deltaTextWhenIncreased() {
        #expect(BodyWeightPresentation.deltaText(current: 81.2, previous: 80.0) == "+1.2 kg vs previous entry")
    }

    @Test func periodDeltaUsesLatestAndBaseline() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let old = Date(timeIntervalSince1970: 1_699_000_000)
        let entries = [
            BodyWeightEntry(
                id: UUID(),
                user_id: UUID(),
                measured_at: old,
                weight_kg: 80.0,
                source: "manual",
                external_sample_id: nil,
                created_at: nil,
                updated_at: nil
            ),
            BodyWeightEntry(
                id: UUID(),
                user_id: UUID(),
                measured_at: now,
                weight_kg: 81.0,
                source: "manual",
                external_sample_id: nil,
                created_at: nil,
                updated_at: nil
            )
        ]
        #expect(BodyWeightPresentation.periodDeltaText(entries: entries, days: 30, now: now) == "+1.0 kg in the last 30 days")
    }

    @Test func chartPointsRespectRange() {
        let now = Date()
        let old = Calendar.current.date(byAdding: .day, value: -120, to: now) ?? now
        let recent = Calendar.current.date(byAdding: .day, value: -10, to: now) ?? now
        let entries = [
            BodyWeightEntry(
                id: UUID(),
                user_id: UUID(),
                measured_at: old,
                weight_kg: 70.0,
                source: "manual",
                external_sample_id: nil,
                created_at: nil,
                updated_at: nil
            ),
            BodyWeightEntry(
                id: UUID(),
                user_id: UUID(),
                measured_at: recent,
                weight_kg: 72.0,
                source: "manual",
                external_sample_id: nil,
                created_at: nil,
                updated_at: nil
            )
        ]
        let points = BodyWeightPresentation.chartPoints(from: entries, preset: .days30, now: now)
        #expect(points.count == 1)
        #expect(points[0].value == 72.0)
    }

    @Test func upsertResultDecodes() throws {
        let data = Data("""
        {"entry_id":"11111111-1111-1111-1111-111111111111","inserted":true,"duplicate":false}
        """.utf8)
        let decoded = try JSONDecoder().decode(BodyWeightUpsertResult.self, from: data)
        #expect(decoded.inserted == true)
        #expect(decoded.duplicate == false)
    }
}
