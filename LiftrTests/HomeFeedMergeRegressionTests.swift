import Foundation
import Testing
@testable import Liftr

struct HomeFeedMergeRegressionTests {
    private struct Item: Identifiable, Equatable {
        let id: Int
        let startedAt: Date?
        let title: String
    }

    @Test func mergeReplacesDuplicateWorkoutIdsWithIncomingItems() {
        let now = Date(timeIntervalSince1970: 1_000)
        let existing = [
            Item(id: 1, startedAt: now, title: "Old Padel"),
            Item(id: 2, startedAt: now.addingTimeInterval(-100), title: "Run")
        ]
        let incoming = [
            Item(id: 1, startedAt: now, title: "Updated Padel"),
            Item(id: 3, startedAt: now.addingTimeInterval(-50), title: "Ride")
        ]

        let merged = HomeFeedMerge.merge(
            existing: existing,
            incoming: incoming,
            id: { $0.id },
            startedAt: { $0.startedAt }
        )

        #expect(merged.map(\.id) == [1, 3, 2])
        #expect(merged.count == 3)
        #expect(merged.first(where: { $0.id == 1 })?.title == "Updated Padel")
    }

    @Test func mergeCollapsesDuplicateItemsWithinIncomingPage() {
        let now = Date(timeIntervalSince1970: 2_000)
        let incoming = [
            Item(id: 4, startedAt: now, title: "First"),
            Item(id: 4, startedAt: now, title: "Second")
        ]

        let merged = HomeFeedMerge.merge(
            existing: [],
            incoming: incoming,
            id: { $0.id },
            startedAt: { $0.startedAt }
        )

        #expect(merged == [Item(id: 4, startedAt: now, title: "Second")])
    }

    @Test func generationCheckRejectsStaleResults() {
        let current = UUID()
        let stale = UUID()

        #expect(HomeFeedMerge.shouldApplyResult(currentGeneration: current, resultGeneration: current))
        #expect(!HomeFeedMerge.shouldApplyResult(currentGeneration: current, resultGeneration: stale))
    }
}
