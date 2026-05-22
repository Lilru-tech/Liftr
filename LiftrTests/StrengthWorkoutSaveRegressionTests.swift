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

    @Test func strengthSetSaveInputEncodesDropSetSegments() throws {
        let input = StrengthWorkoutSetSaveInput(
            set_number: 1,
            order_index: 1,
            reps: 10,
            weight_kg: 80,
            rpe: 8,
            rest_sec: 90,
            weight_segments: [
                StrengthWeightSegWire(reps: 10, weight_kg: 80),
                StrengthWeightSegWire(reps: 8, weight_kg: 70)
            ]
        )
        let data = try JSONEncoder().encode(input)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let segments = try #require(json["weight_segments"] as? [[String: Any]])
        #expect(segments.count == 2)
        #expect(segments[0]["reps"] as? Int == 10)
        #expect(segments[1]["weight_kg"] as? Double == 70)
    }

    @Test func compactSupersetMetadataClearsSingletonAndRenumbersPositions() {
        let groupA = UUID()
        let groupB = UUID()

        var first = EditableExercise()
        first.exerciseId = 1
        first.supersetGroupId = groupA
        first.supersetPosition = 4

        var second = EditableExercise()
        second.exerciseId = 2
        second.supersetGroupId = groupA
        second.supersetPosition = 9

        var third = EditableExercise()
        third.exerciseId = 3
        third.supersetGroupId = groupB
        third.supersetPosition = 1

        let compacted = compactSupersetMetadata([first, second, third])

        #expect(compacted.map(\.orderIndex) == [1, 2, 3])
        #expect(compacted[0].supersetGroupId == groupA)
        #expect(compacted[0].supersetPosition == 1)
        #expect(compacted[1].supersetGroupId == groupA)
        #expect(compacted[1].supersetPosition == 2)
        #expect(compacted[2].supersetGroupId == nil)
        #expect(compacted[2].supersetPosition == nil)
    }

    @Test func strengthRoutineContentFingerprintIncludesSupersetMetadata() {
        let group = UUID()
        var withSuperset = EditableExercise()
        withSuperset.exerciseId = 10
        withSuperset.supersetGroupId = group
        withSuperset.supersetPosition = 1
        withSuperset.sets = [EditableSet(setNumber: 1, reps: 8)]

        var withoutSuperset = EditableExercise()
        withoutSuperset.exerciseId = 10
        withoutSuperset.sets = [EditableSet(setNumber: 1, reps: 8)]

        let hashA = strengthRoutineContentFingerprint(from: [withSuperset])
        let hashB = strengthRoutineContentFingerprint(from: [withoutSuperset])
        #expect(hashA != hashB)
    }

    @Test func compactSupersetMetadataForEditClearsSingletonAndRenumbersPositions() {
        let groupA = UUID()
        let groupB = UUID()

        let first = EditWorkoutMetaSheet.SEditableExercise(
            workoutExerciseId: 1,
            exerciseId: 1,
            orderIndex: 1,
            name: "A",
            alias: "",
            notes: "",
            supersetGroupId: groupA,
            supersetPosition: 4,
            sets: []
        )
        let second = EditWorkoutMetaSheet.SEditableExercise(
            workoutExerciseId: 2,
            exerciseId: 2,
            orderIndex: 2,
            name: "B",
            alias: "",
            notes: "",
            supersetGroupId: groupA,
            supersetPosition: 9,
            sets: []
        )
        let third = EditWorkoutMetaSheet.SEditableExercise(
            workoutExerciseId: 3,
            exerciseId: 3,
            orderIndex: 3,
            name: "C",
            alias: "",
            notes: "",
            supersetGroupId: groupB,
            supersetPosition: 1,
            sets: []
        )

        let compacted = compactSupersetMetadataForEdit([first, second, third])

        #expect(compacted.map(\.orderIndex) == [1, 2, 3])
        #expect(compacted[0].supersetGroupId == groupA)
        #expect(compacted[0].supersetPosition == 1)
        #expect(compacted[1].supersetGroupId == groupA)
        #expect(compacted[1].supersetPosition == 2)
        #expect(compacted[2].supersetGroupId == nil)
        #expect(compacted[2].supersetPosition == nil)
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

    @Test func collapseKeepsAddedExerciseIdsInLaneOrder() {
        let lines = [
            StrengthWorkoutFinishCollapse.Line(
                configId: 1,
                segmentsInRow: 1,
                reps: 10,
                weightKg: 40,
                rpe: nil,
                restSec: 60,
                weightSegments: nil
            )
        ]
        let inputs = StrengthWorkoutFinishCollapse.buildExerciseSaveInputs(
            exerciseIds: [10, 20],
            performedByExercise: [20: lines]
        )
        #expect(inputs.map(\.workout_exercise_id) == [10, 20])
        #expect(inputs[0].sets.isEmpty)
        #expect(inputs[1].sets.count == 1)
    }
}
