import Foundation
import Testing
@testable import Liftr

struct StrengthWorkoutSaveRegressionTests {
    @Test func collapseLegacyIdenticalSets() {
        let lines = [
            StrengthWorkoutFinishCollapse.Line(
                configId: 1,
                segmentsInRow: 1,
                reps: 10,
                weightKg: 60,
                rpe: nil,
                restSec: 90,
                weightSegments: nil
            ),
            StrengthWorkoutFinishCollapse.Line(
                configId: 1,
                segmentsInRow: 1,
                reps: 10,
                weightKg: 60,
                rpe: nil,
                restSec: 90,
                weightSegments: nil
            )
        ]
        let inputs = StrengthWorkoutFinishCollapse.buildExerciseSaveInputs(
            exerciseIds: [42],
            performedByExercise: [42: lines]
        )
        #expect(inputs.count == 1)
        #expect(inputs[0].sets.count == 1)
        #expect(inputs[0].sets[0].set_number == 2)
        #expect(inputs[0].sets[0].reps == 10)
        #expect(inputs[0].sets[0].weight_kg == 60)
    }

    @Test func collapseDropSetSegments() {
        let segments = [
            StrengthWeightSegWire(reps: 10, weight_kg: 80),
            StrengthWeightSegWire(reps: 8, weight_kg: 70)
        ]
        let lines = [
            StrengthWorkoutFinishCollapse.Line(
                configId: 1,
                segmentsInRow: 2,
                reps: 10,
                weightKg: 80,
                rpe: 8,
                restSec: 120,
                weightSegments: segments
            )
        ]
        let inputs = StrengthWorkoutFinishCollapse.buildExerciseSaveInputs(
            exerciseIds: [7],
            performedByExercise: [7: lines]
        )
        #expect(inputs[0].sets.count == 1)
        #expect(inputs[0].sets[0].weight_segments?.count == 2)
        #expect(inputs[0].sets[0].set_number == 1)
    }

    @Test func collapseSplitsOnConfigChange() {
        let lines = [
            StrengthWorkoutFinishCollapse.Line(
                configId: 1,
                segmentsInRow: 1,
                reps: 8,
                weightKg: 50,
                rpe: nil,
                restSec: nil,
                weightSegments: nil
            ),
            StrengthWorkoutFinishCollapse.Line(
                configId: 2,
                segmentsInRow: 1,
                reps: 6,
                weightKg: 55,
                rpe: nil,
                restSec: nil,
                weightSegments: nil
            )
        ]
        let inputs = StrengthWorkoutFinishCollapse.buildExerciseSaveInputs(
            exerciseIds: [3],
            performedByExercise: [3: lines]
        )
        #expect(inputs[0].sets.count == 2)
        #expect(inputs[0].sets[0].reps == 8)
        #expect(inputs[0].sets[1].reps == 6)
    }
}
