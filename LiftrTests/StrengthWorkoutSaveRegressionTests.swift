import Foundation
import Testing
@testable import Liftr

struct StrengthWorkoutSaveRegressionTests {
    @Test func strengthExerciseSaveInputEncodesOrderIndex() throws {
        let input = StrengthWorkoutExerciseSaveInput(
            workout_exercise_id: 10,
            exercise_id: 20,
            order_index: 2,
            notes: nil,
            custom_name: nil,
            sets: []
        )
        let data = try JSONEncoder().encode(input)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["order_index"] as? Int == 2)
    }

    @Test func strengthSetSaveInputEncodesOrderIndexSeparatelyFromSetNumber() throws {
        let input = StrengthWorkoutSetSaveInput(
            set_number: 3,
            order_index: 1,
            reps: 8,
            weight_kg: 80,
            rpe: nil,
            rest_sec: nil,
            weight_segments: nil
        )
        let data = try JSONEncoder().encode(input)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["set_number"] as? Int == 3)
        #expect(json["order_index"] as? Int == 1)
    }

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
