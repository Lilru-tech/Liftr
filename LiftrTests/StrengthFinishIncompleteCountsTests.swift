import XCTest
@testable import Liftr

final class StrengthFinishIncompleteCountsTests: XCTestCase {
    private struct StubExercise: Identifiable {
        let id: Int
        let totalSets: Int
        let completedIndex: Int
    }

    func testCountsIncompleteSetsAndExercises() {
        let exercises = [
            StubExercise(id: 1, totalSets: 3, completedIndex: 1),
            StubExercise(id: 2, totalSets: 2, completedIndex: 0),
            StubExercise(id: 3, totalSets: 0, completedIndex: 0)
        ]
        let result = StrengthFinishIncompleteCounting.counts(
            exercises: exercises,
            totalSets: { $0.totalSets },
            completedSetIndex: { $0.completedIndex }
        )
        XCTAssertEqual(result.exercises, 1)
        XCTAssertEqual(result.sets, 4)
    }

    func testAggregateSumsLanes() {
        let a = StrengthFinishIncompleteCounts(exercises: 1, sets: 2)
        let b = StrengthFinishIncompleteCounts(exercises: 2, sets: 3)
        let total = StrengthFinishIncompleteCounts.aggregate([a, b])
        XCTAssertEqual(total.exercises, 3)
        XCTAssertEqual(total.sets, 5)
    }
}
