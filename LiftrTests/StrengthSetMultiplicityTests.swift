import Foundation
import Testing
@testable import Liftr

struct StrengthSetMultiplicityTests {
    @Test func legacySequentialSetNumbersCountAsOneEach() {
        let mults = strengthSetMultiplicities(sortedSetNumbers: [1, 2, 3])
        #expect(mults == [1, 1, 1])
        #expect(mults.reduce(0, +) == 3)
    }

    @Test func explicitTimesUseSetNumberAsMultiplier() {
        let mults = strengthSetMultiplicities(sortedSetNumbers: [4, 2])
        #expect(mults == [4, 2])
        #expect(mults.reduce(0, +) == 6)
    }

    @Test func detailAggregatesApplyMultipliersToRepsAndRpe() {
        struct Row {
            let id: Int
            let order_index: Int?
            let set_number: Int
            let reps: Int?
            let rpe: Decimal?
        }
        let rows: [Row] = [
            Row(id: 1, order_index: 1, set_number: 2, reps: 12, rpe: Decimal(string: "8.0")),
            Row(id: 2, order_index: 2, set_number: 1, reps: 10, rpe: Decimal(string: "9.0"))
        ]
        let agg = strengthDetailAggregates(
            setsByExercise: [1: rows],
            orderIndex: { $0.order_index },
            id: { $0.id },
            setNumber: { $0.set_number },
            reps: { $0.reps },
            rpe: { $0.rpe }
        )
        #expect(agg.totalSets == 3)
        #expect(agg.totalReps == 34)
        #expect(agg.avgRpe != nil)
        if let avg = agg.avgRpe {
            #expect(abs(avg - 8.333333333333334) < 0.0001)
        }
    }

    @Test func rowsWithMultiplicitiesPreserveSortOrder() {
        struct Row {
            let id: Int
            let order_index: Int?
            let set_number: Int
        }
        let rows = [
            Row(id: 20, order_index: 2, set_number: 1),
            Row(id: 10, order_index: 1, set_number: 3)
        ]
        let paired = strengthSetRowsWithMultiplicities(
            rows,
            orderIndex: { $0.order_index },
            id: { $0.id },
            setNumber: { $0.set_number }
        )
        #expect(paired.count == 2)
        #expect(paired[0].row.id == 10)
        #expect(paired[0].multiplier == 3)
        #expect(paired[1].row.id == 20)
        #expect(paired[1].multiplier == 1)
    }

    @Test func collapsedSetMultipliesVolume() {
        struct Row {
            let id: Int
            let order_index: Int?
            let set_number: Int
            let reps: Int?
            let weight_kg: Decimal?
            let weight_segments: [StrengthWeightSegWire]?
        }
        let rows: [Row] = [
            Row(id: 1, order_index: 1, set_number: 5, reps: 12, weight_kg: Decimal(string: "60"), weight_segments: nil)
        ]
        let volume = strengthDetailVolumeKg(
            setsByExercise: [1: rows],
            orderIndex: { $0.order_index },
            id: { $0.id },
            setNumber: { $0.set_number },
            reps: { $0.reps },
            weightKg: { $0.weight_kg },
            weightSegments: { $0.weight_segments }
        )
        #expect(abs(volume - 3600) < 0.001)
    }

    @Test func sequentialSetsDoNotMultiplyVolume() {
        struct Row {
            let id: Int
            let order_index: Int?
            let set_number: Int
            let reps: Int?
            let weight_kg: Decimal?
            let weight_segments: [StrengthWeightSegWire]?
        }
        let rows: [Row] = [
            Row(id: 1, order_index: 1, set_number: 1, reps: 10, weight_kg: Decimal(string: "50"), weight_segments: nil),
            Row(id: 2, order_index: 2, set_number: 2, reps: 10, weight_kg: Decimal(string: "50"), weight_segments: nil),
            Row(id: 3, order_index: 3, set_number: 3, reps: 10, weight_kg: Decimal(string: "50"), weight_segments: nil)
        ]
        let volume = strengthDetailVolumeKg(
            setsByExercise: [1: rows],
            orderIndex: { $0.order_index },
            id: { $0.id },
            setNumber: { $0.set_number },
            reps: { $0.reps },
            weightKg: { $0.weight_kg },
            weightSegments: { $0.weight_segments }
        )
        #expect(abs(volume - 1500) < 0.001)
    }

    @Test func dropSetSegmentsSumBeforeMultiplier() {
        struct Row {
            let id: Int
            let order_index: Int?
            let set_number: Int
            let reps: Int?
            let weight_kg: Decimal?
            let weight_segments: [StrengthWeightSegWire]?
        }
        let rows: [Row] = [
            Row(
                id: 1,
                order_index: 1,
                set_number: 2,
                reps: 8,
                weight_kg: Decimal(string: "80"),
                weight_segments: [
                    StrengthWeightSegWire(reps: 8, weight_kg: 80),
                    StrengthWeightSegWire(reps: 4, weight_kg: 60)
                ]
            )
        ]
        let volume = strengthDetailVolumeKg(
            setsByExercise: [1: rows],
            orderIndex: { $0.order_index },
            id: { $0.id },
            setNumber: { $0.set_number },
            reps: { $0.reps },
            weightKg: { $0.weight_kg },
            weightSegments: { $0.weight_segments }
        )
        #expect(abs(volume - 1760) < 0.001)
    }
}
