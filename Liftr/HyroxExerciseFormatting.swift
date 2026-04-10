import Foundation
enum HyroxExerciseCode: String, CaseIterable, Identifiable {
    case run
    case skierg
    case burpeeBroadJump = "burpee_broad_jump"
    case sledPush = "sled_push"
    case sledPull = "sled_pull"
    case row
    case farmerCarry = "farmer_carry"
    case sandbagLunges = "sandbag_lunges"
    case wallBall = "wall_ball"
    case atlasCarry = "atlas_carry"
    case boxJumpOver = "box_jump_over"
    case deadBallOverTrunk = "dead_ball_over_trunk"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .run: return "Run"
        case .skierg: return "SkiErg"
        case .burpeeBroadJump: return "Burpee Broad Jump"
        case .sledPush: return "Sled Push"
        case .sledPull: return "Sled Pull"
        case .row: return "Row"
        case .farmerCarry: return "Farmer Carry"
        case .sandbagLunges: return "Sandbag Lunges"
        case .wallBall: return "Wall Ball"
        case .atlasCarry: return "Atlas Carry"
        case .boxJumpOver: return "Box Jump Over"
        case .deadBallOverTrunk: return "Dead Ball Over Trunk"
        }
    }
}

enum HyroxWeightTier: String, CaseIterable, Identifiable {
    case openWomen
    case openMen
    case proMen

    var id: String { rawValue }

    var sledPushKg: Double {
        switch self {
        case .openWomen: return 102
        case .openMen: return 152
        case .proMen: return 202
        }
    }

    var sledPullKg: Double {
        switch self {
        case .openWomen: return 78
        case .openMen: return 103
        case .proMen: return 153
        }
    }

    var farmerCarryKgPerImplement: Double {
        switch self {
        case .openWomen: return 16
        case .openMen: return 24
        case .proMen: return 32
        }
    }

    var sandbagKg: Double {
        switch self {
        case .openWomen: return 10
        case .openMen: return 20
        case .proMen: return 30
        }
    }

    var wallBallKg: Double {
        switch self {
        case .openWomen: return 4
        case .openMen: return 6
        case .proMen: return 9
        }
    }
}

enum HyroxExerciseFormatting {
    static let customExerciseCode = "custom"
    static func label(code: String, displayName: String?, notes: String? = nil) -> String {
        if let d = displayName?.trimmingCharacters(in: .whitespacesAndNewlines), !d.isEmpty {
            return d
        }
        let trimmedNotes = notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        let isNonStandard = (code == customExerciseCode) || (HyroxExerciseCode(rawValue: code) == nil)
        if isNonStandard, let n = trimmedNotes, !n.isEmpty {
            let firstLine = n.split(whereSeparator: \.isNewline).first.map(String.init) ?? n
            let line = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if !line.isEmpty { return line }
        }
        switch code {
        case "run": return "Run"
        case "skierg": return "SkiErg"
        case "burpee_broad_jump": return "Burpee Broad Jump"
        case "sled_push": return "Sled Push"
        case "sled_pull": return "Sled Pull"
        case "row": return "Row"
        case "farmer_carry": return "Farmer Carry"
        case "sandbag_lunges": return "Sandbag Lunges"
        case "wall_ball": return "Wall Ball"
        case "atlas_carry": return "Atlas Carry"
        case "box_jump_over": return "Box Jump Over"
        case "dead_ball_over_trunk": return "Dead Ball Over Trunk"
        default:
            return code.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    static func formFields(exerciseCode: String, exerciseDisplayName: String?) -> (code: String, customDisplayName: String) {
        if HyroxExerciseCode(rawValue: exerciseCode) != nil {
            return (exerciseCode, "")
        }
        if exerciseCode == customExerciseCode {
            return (customExerciseCode, exerciseDisplayName ?? "")
        }
        return (exerciseCode, exerciseDisplayName ?? "")
    }

    static func persistedPayload(exerciseCode: String, customDisplayName: String, notes: String? = nil) -> (code: String, displayName: String?) {
        let trimmed = customDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let fromNotes = displayNameFromNotesFirstLine(notes)

        if HyroxExerciseCode(rawValue: exerciseCode) != nil {
            return (exerciseCode, nil)
        }
        if exerciseCode == customExerciseCode {
            let name: String?
            if !trimmed.isEmpty {
                name = trimmed
            } else {
                name = fromNotes
            }
            return (customExerciseCode, name)
        }
        let name: String? = trimmed.isEmpty ? fromNotes : trimmed
        return (exerciseCode, name)
    }

    private static func displayNameFromNotesFirstLine(_ notes: String?) -> String? {
        guard let n = notes?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty else { return nil }
        let first = n.split(whereSeparator: \.isNewline).first.map(String.init) ?? n
        let t = first.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    struct HyroxExerciseRowInput {
        let exerciseOrder: Int
        let exerciseCode: String
        let customDisplayName: String
        let notes: String
    }

    static func hyroxDisplayNameColumnUpdates(rows: [HyroxExerciseRowInput]) -> [(exerciseOrder: Int, displayName: String)] {
        rows.compactMap { row in
            let p = persistedPayload(
                exerciseCode: row.exerciseCode,
                customDisplayName: row.customDisplayName,
                notes: row.notes
            )
            guard let d = p.displayName else { return nil }
            return (row.exerciseOrder, d)
        }
    }

    static func pickerTag(for exerciseCode: String) -> String {
        if HyroxExerciseCode(rawValue: exerciseCode) != nil {
            return exerciseCode
        }
        return customExerciseCode
    }

    static func inferHyroxWeightTier(sandbagMedian: Double?, wallBallMedian: Double?, sledPushMedian: Double?) -> HyroxWeightTier {
        let v = sandbagMedian ?? wallBallMedian ?? sledPushMedian
        guard let v else { return .openMen }
        if v < 15 { return .openWomen }
        if v < 26 { return .openMen }
        return .proMen
    }

    private static func officialRaceStationSequence(tier: HyroxWeightTier) -> [HyroxExerciseRecommendation] {
        let w = tier
        var o = 1
        func line(
            _ code: HyroxExerciseCode,
            distanceM: Int? = nil,
            reps: Int? = nil,
            weightKg: Double? = nil,
            heightCm: Int? = nil,
            implementCount: Int? = nil
        ) -> HyroxExerciseRecommendation {
            defer { o += 1 }
            return HyroxExerciseRecommendation(
                exerciseCode: code.rawValue,
                customDisplayName: "",
                exerciseOrder: o,
                distanceM: distanceM,
                reps: reps,
                weightKg: weightKg,
                durationSec: nil,
                heightCm: heightCm,
                implementCount: implementCount,
                notes: nil
            )
        }
        return [
            line(.skierg, distanceM: 1_000),
            line(.sledPull, distanceM: 50, weightKg: w.sledPullKg),
            line(.sledPush, distanceM: 50, weightKg: w.sledPushKg),
            line(.burpeeBroadJump, distanceM: 80),
            line(.row, distanceM: 1_000),
            line(.farmerCarry, distanceM: 200, weightKg: w.farmerCarryKgPerImplement, implementCount: 2),
            line(.sandbagLunges, distanceM: 100, weightKg: w.sandbagKg),
            line(.wallBall, reps: 100, weightKg: w.wallBallKg)
        ]
    }

    static func officialRaceHyroxWithRuns(
        tier: HyroxWeightTier,
        runDistanceM: Int,
        stationCount: Int
    ) -> [HyroxExerciseRecommendation] {
        let w = tier
        let runM = min(max(runDistanceM, 400), 5_000)
        let stationsFull = officialRaceStationSequence(tier: w)
        let n = min(8, max(3, min(stationCount, 8)))
        let picked = Array(stationsFull.prefix(n))

        var order = 1
        var out: [HyroxExerciseRecommendation] = []
        for station in picked {
            out.append(
                HyroxExerciseRecommendation(
                    exerciseCode: HyroxExerciseCode.run.rawValue,
                    customDisplayName: "",
                    exerciseOrder: order,
                    distanceM: runM,
                    reps: nil,
                    weightKg: nil,
                    durationSec: nil,
                    heightCm: nil,
                    implementCount: nil,
                    notes: nil
                )
            )
            order += 1
            out.append(
                HyroxExerciseRecommendation(
                    exerciseCode: station.exerciseCode,
                    customDisplayName: station.customDisplayName,
                    exerciseOrder: order,
                    distanceM: station.distanceM,
                    reps: station.reps,
                    weightKg: station.weightKg,
                    durationSec: station.durationSec,
                    heightCm: station.heightCm,
                    implementCount: station.implementCount,
                    notes: nil
                )
            )
            order += 1
        }
        return out.map { sanitizeHyroxExerciseRecommendation($0) }
    }

    static func sanitizeHyroxExerciseRecommendation(_ ex: HyroxExerciseRecommendation) -> HyroxExerciseRecommendation {
        let code = ex.exerciseCode.lowercased()
        if let std = HyroxExerciseCode(rawValue: code) {
            return sanitizeStandard(std, ex)
        }
        return sanitizeCustomStation(ex)
    }

    private static func sanitizeStandard(_ t: HyroxExerciseCode, _ ex: HyroxExerciseRecommendation) -> HyroxExerciseRecommendation {
        var d = ex.distanceM
        var r = ex.reps
        var w = ex.weightKg
        var dur = ex.durationSec
        var h = ex.heightCm
        var imp = ex.implementCount

        switch t {
        case .run:
            if d == nil || d! < 200 { d = 1_000 }
            if let dv = d { d = min(max(dv, 400), 5_000) }
            if let rv = r, rv > 30 { r = nil }
            w = nil
            h = nil
            imp = nil
        case .skierg, .row:
            if d == nil || d! < 200 || d! > 6_000 { d = 1_000 }
            if let dv = d { d = min(max(dv, 200), 5_000) }
            r = nil
            w = nil
            h = nil
            imp = nil
            if let du = dur, du > 3_600 { dur = 3_600 }
        case .sledPush, .sledPull:
            if d == nil || d! > 500 { d = 50 }
            if let dv = d { d = min(max(dv, 25), 200) }
            if let rv = r, rv > 20 { r = nil }
            h = nil
            imp = nil
            if let wv = w, wv > 350 || wv < 20 { w = nil }
        case .burpeeBroadJump:
            if let dv = d, dv >= 40, dv <= 200 {
                d = dv
            } else if let rv = r, rv >= 40, rv <= 200, (d == nil || d! < 40) {
                d = rv
                r = nil
            } else {
                d = 80
                r = nil
            }
            w = nil
            h = nil
            imp = nil
            dur = nil
        case .farmerCarry:
            if d == nil || d! > 1_000 { d = 200 }
            if let dv = d { d = min(max(dv, 50), 400) }
            r = nil
            h = nil
            if imp == nil || imp == 0 { imp = 2 }
            if let wv = w, wv > 60 || wv < 4 { w = nil }
        case .sandbagLunges:
            if let dv = d, dv >= 40, dv <= 300 {
                d = dv
            } else {
                d = 100
            }
            r = nil
            h = nil
            imp = nil
            if let wv = w {
                let snapped = [10.0, 20.0, 30.0].min(by: { abs($0 - wv) < abs($1 - wv) })!
                w = snapped
            }
            dur = nil
        case .wallBall:
            d = nil
            h = nil
            imp = nil
            if let rv = r, rv >= 30, rv <= 150 {
                r = rv
            } else {
                r = 100
            }
            if let wv = w {
                if wv > 12 || wv < 2 {
                    w = nil
                } else {
                    let snapped = [4.0, 6.0, 9.0].min(by: { abs($0 - wv) < abs($1 - wv) })!
                    w = snapped
                }
            }
        case .boxJumpOver:
            if let rv = r, rv > 200 { r = min(rv, 120) }
            if let hv = h, hv > 200 || hv < 20 { h = nil }
            w = nil
            imp = nil
            if let dv = d, dv > 500 { d = nil }
        default:
            if let rv = r, rv > 500 { r = nil }
            if let dv = d, dv > 50_000 { d = nil }
            if let hv = h, hv > 400 { h = nil }
        }

        return HyroxExerciseRecommendation(
            exerciseCode: ex.exerciseCode,
            customDisplayName: ex.customDisplayName,
            exerciseOrder: ex.exerciseOrder,
            distanceM: d,
            reps: r,
            weightKg: w,
            durationSec: dur,
            heightCm: h,
            implementCount: imp,
            notes: nil
        )
    }

    private static func sanitizeCustomStation(_ ex: HyroxExerciseRecommendation) -> HyroxExerciseRecommendation {
        let r = ex.reps.map { min($0, 500) }
        let d = ex.distanceM.map { min($0, 50_000) }
        let h = ex.heightCm.map { min($0, 400) }
        return HyroxExerciseRecommendation(
            exerciseCode: ex.exerciseCode,
            customDisplayName: ex.customDisplayName,
            exerciseOrder: ex.exerciseOrder,
            distanceM: d,
            reps: r,
            weightKg: ex.weightKg,
            durationSec: ex.durationSec.map { min($0, 36_000) },
            heightCm: h,
            implementCount: ex.implementCount.map { min($0, 50) },
            notes: nil
        )
    }
}
