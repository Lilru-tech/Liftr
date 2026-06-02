import Foundation

func strengthSetMultiplicities(sortedSetNumbers: [Int]) -> [Int] {
    let r = sortedSetNumbers.count
    guard r > 0 else { return [] }
    if sortedSetNumbers == Array(1...r) {
        return Array(repeating: 1, count: r)
    }
    return sortedSetNumbers.map { max($0, 1) }
}

func strengthSortedSetRows<Row>(
    _ rows: [Row],
    orderIndex: (Row) -> Int?,
    id: (Row) -> Int,
    setNumber: (Row) -> Int
) -> [Row] {
    rows.sorted { a, b in
        let ao = orderIndex(a) ?? Int.max
        let bo = orderIndex(b) ?? Int.max
        if ao != bo { return ao < bo }
        return id(a) < id(b)
    }
}

func strengthSetRowsWithMultiplicities<Row>(
    _ rows: [Row],
    orderIndex: (Row) -> Int?,
    id: (Row) -> Int,
    setNumber: (Row) -> Int
) -> [(row: Row, multiplier: Int)] {
    let sorted = strengthSortedSetRows(rows, orderIndex: orderIndex, id: id, setNumber: setNumber)
    let mults = strengthSetMultiplicities(sortedSetNumbers: sorted.map(setNumber))
    return zip(sorted, mults).map { ($0, $1) }
}

struct StrengthDetailAggregates {
    let totalSets: Int
    let totalReps: Int
    let avgRpe: Double?
}

func exerciseSetSegmentVolumeKg(
    reps: Int?,
    weightKg: Decimal?,
    weightSegments: [StrengthWeightSegWire]?
) -> Double {
    if let segments = weightSegments, segments.count >= 2 {
        return segments.reduce(0.0) { partial, segment in
            partial + Double(max(segment.reps, 0)) * max(segment.weight_kg, 0)
        }
    }
    let repVal = max(reps ?? 0, 0)
    let weightVal = weightKg.map { NSDecimalNumber(decimal: $0).doubleValue } ?? 0
    return Double(repVal) * max(weightVal, 0)
}

func strengthDetailVolumeKg<Row>(
    setsByExercise: [Int: [Row]],
    orderIndex: (Row) -> Int?,
    id: (Row) -> Int,
    setNumber: (Row) -> Int,
    reps: (Row) -> Int?,
    weightKg: (Row) -> Decimal?,
    weightSegments: (Row) -> [StrengthWeightSegWire]?
) -> Double {
    var total = 0.0
    for rows in setsByExercise.values {
        let paired = strengthSetRowsWithMultiplicities(
            rows,
            orderIndex: orderIndex,
            id: id,
            setNumber: setNumber
        )
        for (row, mult) in paired {
            let segmentVolume = exerciseSetSegmentVolumeKg(
                reps: reps(row),
                weightKg: weightKg(row),
                weightSegments: weightSegments(row)
            )
            total += segmentVolume * Double(mult)
        }
    }
    return total
}

func strengthDetailAggregates<Row>(
    setsByExercise: [Int: [Row]],
    orderIndex: (Row) -> Int?,
    id: (Row) -> Int,
    setNumber: (Row) -> Int,
    reps: (Row) -> Int?,
    rpe: (Row) -> Decimal?
) -> StrengthDetailAggregates {
    var totalSets = 0
    var totalReps = 0
    var rpeWeightedSum = 0.0
    var rpeWeightTotal = 0.0

    for rows in setsByExercise.values {
        let paired = strengthSetRowsWithMultiplicities(
            rows,
            orderIndex: orderIndex,
            id: id,
            setNumber: setNumber
        )
        for (row, mult) in paired {
            totalSets += mult
            let repVal = max(reps(row) ?? 0, 0)
            totalReps += repVal * mult
            if let rpeDec = rpe(row) {
                let r = NSDecimalNumber(decimal: rpeDec).doubleValue
                let m = Double(mult)
                rpeWeightedSum += r * m
                rpeWeightTotal += m
            }
        }
    }

    let avgRpe = rpeWeightTotal > 0 ? (rpeWeightedSum / rpeWeightTotal) : nil
    return StrengthDetailAggregates(
        totalSets: totalSets,
        totalReps: totalReps,
        avgRpe: avgRpe
    )
}
