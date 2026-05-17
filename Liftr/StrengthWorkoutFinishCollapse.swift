import Foundation

enum StrengthWorkoutFinishCollapse {
    struct Line {
        let configId: Int
        let segmentsInRow: Int
        let reps: Int?
        let weightKg: Decimal?
        let rpe: Decimal?
        let restSec: Int?
        let weightSegments: [StrengthWeightSegWire]?
    }

    private struct CollapsedPersistRow {
        let count: Int
        let reps: Int?
        let weightKg: Decimal?
        let rpe: Decimal?
        let restSec: Int?
        let weightSegments: [StrengthWeightSegWire]?
    }

    private struct LegacyKey: Equatable {
        let reps: Int?
        let weightKg: Decimal?
        let rpe: Decimal?
        let restSec: Int?
    }

    static func buildExerciseSaveInputs(
        exerciseIds: [Int],
        performedByExercise: [Int: [Line]]
    ) -> [StrengthWorkoutExerciseSaveInput] {
        exerciseIds.map { exerciseId in
            let lines = performedByExercise[exerciseId] ?? []
            let chunks = chunkCompletedLines(lines)
            let rowsOut = chunks.flatMap { chunkToPersistRows($0) }
            let sets = rowsOut.map { row in
                StrengthWorkoutSetSaveInput(
                    set_number: row.count,
                    order_index: nil,
                    reps: row.reps,
                    weight_kg: row.weightKg.map { NSDecimalNumber(decimal: $0).doubleValue },
                    rpe: row.rpe.map { NSDecimalNumber(decimal: $0).doubleValue },
                    rest_sec: row.restSec,
                    weight_segments: row.weightSegments
                )
            }
            return StrengthWorkoutExerciseSaveInput(
                workout_exercise_id: exerciseId,
                exercise_id: nil,
                order_index: nil,
                notes: nil,
                custom_name: nil,
                sets: sets
            )
        }
    }

    private static func chunkCompletedLines(_ lines: [Line]) -> [[Line]] {
        guard !lines.isEmpty else { return [] }
        var out: [[Line]] = []
        var cur: [Line] = [lines[0]]
        for i in 1..<lines.count {
            let line = lines[i]
            if line.configId == cur[0].configId {
                cur.append(line)
            } else {
                out.append(cur)
                cur = [line]
            }
        }
        out.append(cur)
        return out
    }

    private static func collapseLegacyChunk(_ chunk: [Line]) -> [CollapsedPersistRow] {
        if chunk.isEmpty { return [] }
        var collapsed: [CollapsedPersistRow] = []
        var currentKey: LegacyKey?
        var count = 0
        for line in chunk {
            let key = LegacyKey(reps: line.reps, weightKg: line.weightKg, rpe: line.rpe, restSec: line.restSec)
            if let cur = currentKey, cur == key {
                count += 1
            } else {
                if let cur = currentKey {
                    collapsed.append(
                        CollapsedPersistRow(
                            count: count,
                            reps: cur.reps,
                            weightKg: cur.weightKg,
                            rpe: cur.rpe,
                            restSec: cur.restSec,
                            weightSegments: nil
                        )
                    )
                }
                currentKey = key
                count = 1
            }
        }
        if let cur = currentKey {
            collapsed.append(
                CollapsedPersistRow(
                    count: count,
                    reps: cur.reps,
                    weightKg: cur.weightKg,
                    rpe: cur.rpe,
                    restSec: cur.restSec,
                    weightSegments: nil
                )
            )
        }
        return collapsed
    }

    private static func collapseSegmentChunk(_ chunk: [Line]) -> [CollapsedPersistRow] {
        if chunk.count == 1, let f = chunk.first, let ws = f.weightSegments, ws.count >= 2 {
            let firstSeg = ws[0]
            return [
                CollapsedPersistRow(
                    count: 1,
                    reps: firstSeg.reps,
                    weightKg: Decimal(firstSeg.weight_kg),
                    rpe: f.rpe,
                    restSec: f.restSec,
                    weightSegments: ws
                )
            ]
        }
        let k = max(2, chunk.first?.segmentsInRow ?? 1)
        let n = chunk.count % k == 0 ? chunk.count / k : 1
        let tail = Array(chunk.suffix(k))
        let segs: [StrengthWeightSegWire] = tail.compactMap { line in
            guard let r = line.reps, let w = line.weightKg else { return nil }
            let d = NSDecimalNumber(decimal: w).doubleValue
            return StrengthWeightSegWire(reps: r, weight_kg: d)
        }
        if segs.count != tail.count {
            return [
                CollapsedPersistRow(
                    count: 1,
                    reps: tail.first?.reps,
                    weightKg: tail.first?.weightKg,
                    rpe: chunk.first(where: { $0.rpe != nil })?.rpe,
                    restSec: tail.last?.restSec,
                    weightSegments: nil
                )
            ]
        }
        let validSegs = segs.count >= 2 ? segs : nil
        return [
            CollapsedPersistRow(
                count: n,
                reps: tail.first?.reps,
                weightKg: tail.first?.weightKg,
                rpe: chunk.first(where: { $0.rpe != nil })?.rpe,
                restSec: tail.last?.restSec,
                weightSegments: validSegs
            )
        ]
    }

    private static func chunkToPersistRows(_ chunk: [Line]) -> [CollapsedPersistRow] {
        if chunk.isEmpty { return [] }
        if chunk[0].segmentsInRow <= 1 {
            return collapseLegacyChunk(chunk)
        }
        return collapseSegmentChunk(chunk)
    }
}
