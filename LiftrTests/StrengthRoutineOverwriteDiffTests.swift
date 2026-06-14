import Foundation
import Testing
@testable import Liftr

struct StrengthRoutineOverwriteDiffTests {
    private func item(exerciseId: Int64, orderIndex: Int, sets: [StrengthProgramSet]) -> StrengthProgramItem {
        StrengthProgramItem(
            exerciseId: exerciseId,
            orderIndex: orderIndex,
            notes: nil,
            customName: nil,
            sets: sets
        )
    }

    private func set(
        num: Int,
        rowOrder: Int? = nil,
        reps: Int? = nil,
        weight: Double? = nil,
        rpe: Double? = nil,
        rest: Int? = nil
    ) -> StrengthProgramSet {
        StrengthProgramSet(
            setNumber: num,
            rowOrder: rowOrder,
            reps: reps,
            weightKg: weight,
            rpe: rpe,
            restSec: rest,
            notes: nil,
            weightSegments: nil
        )
    }

    private func diff(
        proposed: [StrengthProgramItem],
        routine: [StrengthProgramItem]
    ) -> [StrengthRoutineOverwriteDiffLine] {
        buildStrengthRoutineOverwriteDiffLines(
            proposed: proposed,
            routine: routine,
            exerciseDisplayName: { _ in "Exercise" }
        )
    }

    @Test func repsChangeDetected() {
        let proposed = [item(exerciseId: 1, orderIndex: 1, sets: [set(num: 1, reps: 12)])]
        let routine = [item(exerciseId: 1, orderIndex: 1, sets: [set(num: 1, reps: 10)])]
        let lines = diff(proposed: proposed, routine: routine)
        #expect(lines.contains { $0.fieldTitle == "Reps" && $0.oldValue == "10" && $0.newValue == "12" })
    }

    @Test func weightChangeDetected() {
        let proposed = [item(exerciseId: 1, orderIndex: 1, sets: [set(num: 1, weight: 60.5)])]
        let routine = [item(exerciseId: 1, orderIndex: 1, sets: [set(num: 1, weight: 60.0)])]
        let lines = diff(proposed: proposed, routine: routine)
        #expect(lines.contains { $0.fieldTitle == "Weight" })
    }

    @Test func rpeNilToValueDetected() {
        let proposed = [item(exerciseId: 1, orderIndex: 1, sets: [set(num: 1, rpe: 8.0)])]
        let routine = [item(exerciseId: 1, orderIndex: 1, sets: [set(num: 1, rpe: nil)])]
        let lines = diff(proposed: proposed, routine: routine)
        #expect(lines.contains { $0.fieldTitle == "RPE" && $0.oldValue == "—" && $0.newValue == "8.0" })
    }

    @Test func rpeWithinEpsilonNotDetected() {
        let proposed = [item(exerciseId: 1, orderIndex: 1, sets: [set(num: 1, rpe: 8.0005)])]
        let routine = [item(exerciseId: 1, orderIndex: 1, sets: [set(num: 1, rpe: 8.0)])]
        let lines = diff(proposed: proposed, routine: routine)
        #expect(!lines.contains { $0.fieldTitle == "RPE" })
    }

    @Test func restChangeDetected() {
        let proposed = [item(exerciseId: 1, orderIndex: 1, sets: [set(num: 1, rest: 120)])]
        let routine = [item(exerciseId: 1, orderIndex: 1, sets: [set(num: 1, rest: 90)])]
        let lines = diff(proposed: proposed, routine: routine)
        #expect(lines.contains { $0.fieldTitle == "Rest" && $0.oldValue == "90 s" && $0.newValue == "120 s" })
    }

    @Test func addedSetDetected() {
        let proposed = [
            item(
                exerciseId: 1,
                orderIndex: 1,
                sets: [set(num: 1, reps: 10), set(num: 2, reps: 10), set(num: 3, reps: 10), set(num: 4, reps: 10)]
            )
        ]
        let routine = [
            item(
                exerciseId: 1,
                orderIndex: 1,
                sets: [set(num: 1, reps: 10), set(num: 2, reps: 10), set(num: 3, reps: 10)]
            )
        ]
        let lines = diff(proposed: proposed, routine: routine)
        #expect(lines.contains { $0.fieldTitle == "Sets" || $0.fieldTitle == "Added set" })
    }

    @Test func exerciseStructureMatchIgnoresSetCount() {
        let threeSets = [
            item(
                exerciseId: 1,
                orderIndex: 1,
                sets: [set(num: 1), set(num: 2), set(num: 3)]
            )
        ]
        let fourSets = [
            item(
                exerciseId: 1,
                orderIndex: 1,
                sets: [set(num: 1), set(num: 2), set(num: 3), set(num: 4)]
            )
        ]
        #expect(exerciseStructureMatch(threeSets, fourSets))
    }

    @Test func exerciseStructureMatchRequiresSameExerciseIds() {
        let a = [item(exerciseId: 1, orderIndex: 1, sets: [set(num: 1)])]
        let b = [item(exerciseId: 2, orderIndex: 1, sets: [set(num: 1)])]
        #expect(!exerciseStructureMatch(a, b))
    }

    @Test func timesMultiplierShowsAddedSetNotRemoved() {
        let routine = [item(exerciseId: 1, orderIndex: 1, sets: [set(num: 1, reps: 10)])]
        let proposed = [item(exerciseId: 1, orderIndex: 1, sets: [set(num: 2, reps: 10)])]
        let lines = diff(proposed: proposed, routine: routine)
        #expect(lines.contains { $0.fieldTitle == "Added set" && $0.setNumber == 2 })
        #expect(!lines.contains { $0.fieldTitle == "Removed set" })
        #expect(lines.contains { $0.fieldTitle == "Sets" && $0.oldValue == "1" && $0.newValue == "2" })
    }

    @Test func unchangedMultiplierContentFingerprintMatches() {
        let routine = [item(exerciseId: 1, orderIndex: 1, sets: [set(num: 1, reps: 10, weight: 50)])]
        let unchanged = [item(exerciseId: 1, orderIndex: 1, sets: [set(num: 1, reps: 10, weight: 50)])]
        #expect(strengthRoutineContentFingerprint(from: routine) == strengthRoutineContentFingerprint(from: unchanged))
    }

    @Test func timesMultiplierChangesContentFingerprint() {
        let routine = [item(exerciseId: 1, orderIndex: 1, sets: [set(num: 1, reps: 10, weight: 50)])]
        let doubled = [item(exerciseId: 1, orderIndex: 1, sets: [set(num: 2, reps: 10, weight: 50)])]
        #expect(strengthRoutineContentFingerprint(from: routine) != strengthRoutineContentFingerprint(from: doubled))
    }

    @Test func collapseMultiplierExpandsToTwoSetsForDiff() {
        let routine = [item(exerciseId: 1, orderIndex: 1, sets: [set(num: 1, reps: 10)])]
        let collapsedPerformed = [item(exerciseId: 1, orderIndex: 1, sets: [set(num: 2, reps: 10)])]
        let lines = diff(proposed: collapsedPerformed, routine: routine)
        #expect(!lines.isEmpty)
        #expect(lines.contains { $0.fieldTitle == "Added set" || $0.fieldTitle == "Sets" })
        #expect(!lines.contains { $0.fieldTitle == "Removed set" })
    }

    @Test func expandedSetsForCompareEmitsSequentialNumbers() {
        let expanded = expandedStrengthProgramSetsForCompare([set(num: 2, reps: 8)])
        #expect(expanded.count == 2)
        #expect(expanded.map(\.setNumber) == [1, 2])
        #expect(expanded.allSatisfy { $0.reps == 8 })
    }

    @Test func preferredRoutineCompareIgnoresOrderIndexValues() {
        let routine = [item(exerciseId: 10, orderIndex: 50, sets: [set(num: 1, reps: 10)])]
        let proposed = [item(exerciseId: 10, orderIndex: 1, sets: [set(num: 1, reps: 12)])]
        #expect(exerciseStructureMatch(proposed, routine))
        let lines = diff(proposed: proposed, routine: routine)
        #expect(lines.contains { $0.fieldTitle == "Reps" })
    }

    @Test func repsChangeWithDifferentOrderIndexStillDiffs() {
        let routine = [
            item(exerciseId: 1, orderIndex: 100, sets: [set(num: 1, reps: 8)]),
            item(exerciseId: 2, orderIndex: 200, sets: [set(num: 1, reps: 10)])
        ]
        let proposed = [
            item(exerciseId: 1, orderIndex: 1, sets: [set(num: 1, reps: 8)]),
            item(exerciseId: 2, orderIndex: 2, sets: [set(num: 1, reps: 12)])
        ]
        #expect(exerciseStructureMatch(proposed, routine))
        let lines = diff(proposed: proposed, routine: routine)
        #expect(lines.contains { $0.fieldTitle == "Reps" && $0.newValue == "12" })
    }

    @Test func addSetRowWithNewPrescriptionShowsBlankOldValues() {
        let routine = [item(exerciseId: 1, orderIndex: 1, sets: [
            set(num: 1, rowOrder: 1, reps: 1, weight: 1, rpe: 1, rest: 1)
        ])]
        let proposed = [item(exerciseId: 1, orderIndex: 1, sets: [
            set(num: 2, rowOrder: 1, reps: 1, weight: 1, rpe: 1, rest: 1),
            set(num: 1, rowOrder: 2, reps: 2, weight: 2, rpe: 2, rest: 2)
        ])]
        let lines = diff(proposed: proposed, routine: routine)
        #expect(!lines.contains { $0.fieldTitle == "Reps" && $0.setNumber == 1 && $0.oldValue == "1" && $0.newValue == "2" })
        #expect(lines.contains { $0.fieldTitle == "Reps" && $0.oldValue == "—" && $0.newValue == "2" })
        #expect(lines.contains { $0.fieldTitle == "Added set" })
    }

    private func expandedReps(_ items: [StrengthProgramItem]) -> [Int?] {
        expandedStrengthProgramItemsForCompare(items).flatMap { ex in
            ex.sets.sorted { $0.setNumber < $1.setNumber }.map(\.reps)
        }
    }

    @Test func selectiveMergeAppliesOnlyCheckedRepsChanges() {
        let routine = [
            item(exerciseId: 1, orderIndex: 1, sets: [
                set(num: 1, reps: 2), set(num: 2, reps: 2)
            ]),
            item(exerciseId: 2, orderIndex: 2, sets: [
                set(num: 1, reps: 3), set(num: 2, reps: 3), set(num: 3, reps: 3)
            ])
        ]
        let proposed = [
            item(exerciseId: 1, orderIndex: 1, sets: [
                set(num: 1, reps: 2), set(num: 2, reps: 2), set(num: 3, reps: 2)
            ]),
            item(exerciseId: 2, orderIndex: 2, sets: [
                set(num: 1, reps: 4), set(num: 2, reps: 4), set(num: 3, reps: 4)
            ])
        ]
        let lines = diff(proposed: proposed, routine: routine)
        let addSetId = lines.first { $0.fieldTitle == "Added set" && $0.exerciseOrderIndex == 1 }!.id
        let merged = mergeStrengthRoutineWithSelectedChanges(
            routine: routine,
            proposed: proposed,
            selectedLineIds: [addSetId]
        )
        let ex1Reps = expandedStrengthProgramItemsForCompare(merged)
            .first { $0.exerciseId == 1 }!
            .sets.sorted { $0.setNumber < $1.setNumber }
            .map(\.reps)
        #expect(ex1Reps == [2, 2, 2])
        let ex2Reps = expandedStrengthProgramItemsForCompare(merged)
            .first { $0.exerciseId == 2 }!
            .sets.sorted { $0.setNumber < $1.setNumber }
            .map(\.reps)
        #expect(ex2Reps == [3, 3, 3])
    }

    @Test func selectiveMergeAppliesOnlyCheckedExerciseReps() {
        let routine = [
            item(exerciseId: 1, orderIndex: 1, sets: [
                set(num: 1, reps: 2), set(num: 2, reps: 2)
            ]),
            item(exerciseId: 2, orderIndex: 2, sets: [
                set(num: 1, reps: 3), set(num: 2, reps: 3), set(num: 3, reps: 3)
            ])
        ]
        let proposed = [
            item(exerciseId: 1, orderIndex: 1, sets: [
                set(num: 1, reps: 2), set(num: 2, reps: 2), set(num: 3, reps: 2)
            ]),
            item(exerciseId: 2, orderIndex: 2, sets: [
                set(num: 1, reps: 4), set(num: 2, reps: 4), set(num: 3, reps: 4)
            ])
        ]
        let lines = diff(proposed: proposed, routine: routine)
        let repIds = Set(lines.filter { $0.fieldTitle == "Reps" && $0.exerciseOrderIndex == 2 }.map(\.id))
        let merged = mergeStrengthRoutineWithSelectedChanges(
            routine: routine,
            proposed: proposed,
            selectedLineIds: repIds
        )
        let ex1Count = expandedStrengthProgramItemsForCompare(merged)
            .first { $0.exerciseId == 1 }!
            .sets.count
        #expect(ex1Count == 2)
        let ex2Reps = expandedStrengthProgramItemsForCompare(merged)
            .first { $0.exerciseId == 2 }!
            .sets.sorted { $0.setNumber < $1.setNumber }
            .map(\.reps)
        #expect(ex2Reps == [4, 4, 4])
    }

    @Test func allSelectedMergeMatchesFullProposedExpanded() {
        let routine = [item(exerciseId: 1, orderIndex: 1, sets: [set(num: 1, reps: 10)])]
        let proposed = [item(exerciseId: 1, orderIndex: 1, sets: [
            set(num: 1, reps: 10), set(num: 2, reps: 12)
        ])]
        let lines = diff(proposed: proposed, routine: routine)
        let allIds = actionableOverwriteDiffLineIds(from: lines)
        let merged = mergeStrengthRoutineWithSelectedChanges(
            routine: routine,
            proposed: proposed,
            selectedLineIds: allIds
        )
        let mergedExpanded = expandedStrengthProgramItemsForCompare(merged)
        let proposedExpanded = expandedStrengthProgramItemsForCompare(proposed)
        #expect(mergedExpanded.count == proposedExpanded.count)
        #expect(mergedExpanded[0].sets.map(\.reps) == proposedExpanded[0].sets.map(\.reps))
    }

    @Test func uncheckedAddedSetIgnoresFieldLinesForNewSet() {
        let routine = [item(exerciseId: 1, orderIndex: 1, sets: [set(num: 1, reps: 1)])]
        let proposed = [item(exerciseId: 1, orderIndex: 1, sets: [
            set(num: 2, rowOrder: 1, reps: 1),
            set(num: 1, rowOrder: 2, reps: 2)
        ])]
        let lines = diff(proposed: proposed, routine: routine)
        let repLine = lines.first { $0.fieldTitle == "Reps" }!.id
        let merged = mergeStrengthRoutineWithSelectedChanges(
            routine: routine,
            proposed: proposed,
            selectedLineIds: [repLine]
        )
        #expect(expandedStrengthProgramItemsForCompare(merged).first!.sets.count == 1)
    }
}
