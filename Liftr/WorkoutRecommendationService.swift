import Foundation
import Supabase

enum WorkoutRecommendationError: LocalizedError {
    case notSignedIn
    case noWorkoutsInWindow
    case loadFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .notSignedIn: return "You need to be signed in."
        case .noWorkoutsInWindow:
            return "No workouts of this type in your last 10 sessions. Log one first, or open Suggest again and choose “Full app catalog” for a starter template."
        case .loadFailed(let m): return m
        }
    }
}

private struct HyroxExRow: Decodable {
    let exercise_code: String
    let exercise_order: Int
    let distance_m: Int?
    let reps: Int?
    let weight_kg: Decimal?
    let duration_sec: Int?
    let height_cm: Int?
    let implement_count: Int?
    let notes: String?
    let exercise_display_name: String?
}

enum WorkoutRecommendationService {
    
    private static let lookbackCount = 10
    private static let targetExerciseCount = 5
    private static let defaultSetsPerExercise = 3
    private static let defaultReps = 12
    
    private static let maxRecommendedSets = 5
    private static let maxInferredSetsFromSetNumber = 8
    private static let maxRecommendedReps = 22
    private static let minRecommendedReps = 6
    private static let highVolumeRepsThreshold = 17
    private static let highVolumeSetsThreshold = 5
    private static let defaultRestBetweenSetsSec = 90
    
    private struct FlatSet {
        let workoutId: Int
        let startedAt: Date?
        let workoutExerciseId: Int
        let exerciseId: Int64
        let orderIndex: Int
        let musclePrimary: String?
        let setNumber: Int
        let reps: Int?
        let weightKg: Decimal?
        let rpe: Decimal?
        let restSec: Int?
    }
    
    static func recommendStrength(
        userId: UUID,
        source: RecommendationDataSource,
        mode: StrengthSuggestionMode,
        catalog: [Exercise],
        exerciseLanguage: ExerciseLanguage
    ) async throws -> [StrengthRecommendationExercise] {
        let client = SupabaseManager.shared.client
        let decoder = JSONDecoder.supabase()
        
        struct WRow: Decodable { let id: Int; let started_at: Date? }
        
        let wRes = try await client
            .from("workouts")
            .select("id, started_at")
            .eq("user_id", value: userId.uuidString)
            .eq("kind", value: "strength")
            .eq("state", value: "published")
            .order("started_at", ascending: false)
            .limit(lookbackCount)
            .execute()
        
        let workouts = try decoder.decode([WRow].self, from: wRes.data)
        if workouts.isEmpty {
            guard source == .fullCatalog, !catalog.isEmpty else {
                throw WorkoutRecommendationError.noWorkoutsInWindow
            }
            return try coldStartStrength(catalog: catalog, exerciseLanguage: exerciseLanguage)
        }
        
        let workoutIds = workouts.map { String($0.id) }
        let startedByWid: [Int: Date?] = Dictionary(uniqueKeysWithValues: workouts.map { ($0.id, $0.started_at) })
        
        struct ExWire: Decodable {
            let id: Int
            let workout_id: Int
            let exercise_id: Int64
            let order_index: Int
            let exercises: MuscleRef?
            struct MuscleRef: Decodable { let muscle_primary: String? }
        }
        
        let exRes = try await client
            .from("workout_exercises")
            .select("id, workout_id, exercise_id, order_index, exercises(muscle_primary)")
            .in("workout_id", values: workoutIds)
            .order("order_index", ascending: true)
            .execute()
        
        let exRows = try decoder.decode([ExWire].self, from: exRes.data)
        let weIds = exRows.map { $0.id }
        
        struct SetWire: Decodable {
            let workout_exercise_id: Int
            let set_number: Int
            let reps: Int?
            let weight_kg: Decimal?
            let rpe: Decimal?
            let rest_sec: Int?
        }
        
        var setRows: [SetWire] = []
        if !weIds.isEmpty {
            let setRes = try await client
                .from("exercise_sets")
                .select("workout_exercise_id, set_number, reps, weight_kg, rpe, rest_sec")
                .in("workout_exercise_id", values: weIds)
                .order("set_number", ascending: true)
                .execute()
            setRows = try decoder.decode([SetWire].self, from: setRes.data)
        }
        
        let setsByWE: [Int: [SetWire]] = Dictionary(grouping: setRows, by: { $0.workout_exercise_id })
        
        var flat: [FlatSet] = []
        for ex in exRows {
            let wid = ex.workout_id
            let st = startedByWid[wid] ?? nil
            let muscle = ex.exercises?.muscle_primary
            if let list = setsByWE[ex.id], !list.isEmpty {
                for s in list {
                    flat.append(FlatSet(
                        workoutId: wid,
                        startedAt: st,
                        workoutExerciseId: ex.id,
                        exerciseId: ex.exercise_id,
                        orderIndex: ex.order_index,
                        musclePrimary: muscle,
                        setNumber: s.set_number,
                        reps: s.reps,
                        weightKg: s.weight_kg,
                        rpe: s.rpe,
                        restSec: s.rest_sec
                    ))
                }
            } else {
                flat.append(FlatSet(
                    workoutId: wid,
                    startedAt: st,
                    workoutExerciseId: ex.id,
                    exerciseId: ex.exercise_id,
                    orderIndex: ex.order_index,
                    musclePrimary: muscle,
                    setNumber: 1,
                    reps: nil,
                    weightKg: nil,
                    rpe: nil,
                    restSec: nil
                ))
            }
        }
        
        switch mode {
        case .prioritizeUndertrainedMuscles:
            return try suggestBalancedStrength(
                flat: flat,
                catalog: catalog,
                source: source,
                exerciseLanguage: exerciseLanguage
            )
        case .prioritizeFrequentLifts:
            return try suggestFrequentStrength(
                flat: flat,
                catalog: catalog,
                source: source,
                exerciseLanguage: exerciseLanguage
            )
        }
    }
    
    private static func normMuscle(_ s: String?) -> String {
        (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
    
    private static func coldStartStrength(catalog: [Exercise], exerciseLanguage: ExerciseLanguage) throws -> [StrengthRecommendationExercise] {
        let pool = catalog.shuffled()
        var result: [StrengthRecommendationExercise] = []
        let w = 20.0
        let rpe: Double? = 8
        for ex in pool.prefix(targetExerciseCount) {
            let setsOut = (1...defaultSetsPerExercise).map { sn in
                StrengthRecommendationSet(setNumber: sn, reps: defaultReps, weightKg: w, rpe: rpe, restSec: defaultRestBetweenSetsSec)
            }
            result.append(StrengthRecommendationExercise(
                exerciseId: ex.id,
                displayName: ex.localizedName(for: exerciseLanguage),
                musclePrimary: ex.muscle_primary,
                sets: setsOut
            ))
        }
        guard !result.isEmpty else { throw WorkoutRecommendationError.loadFailed("Catalog is empty.") }
        return result
    }
    
    private static func decimalToDouble(_ d: Decimal?) -> Double {
        guard let d else { return 0 }
        return NSDecimalNumber(decimal: d).doubleValue
    }

    private static func mergeDuplicateSetNumbers(_ rows: [FlatSet]) -> [FlatSet] {
        let g = Dictionary(grouping: rows, by: \.setNumber)
        return g.keys.sorted().compactMap { k in
            (g[k] ?? []).max { decimalToDouble($0.weightKg) < decimalToDouble($1.weightKg) }
        }
    }

    private static func pickBestWorkoutExerciseSlice(_ rows: [FlatSet]) -> [FlatSet] {
        let g = Dictionary(grouping: rows, by: \.workoutExerciseId)
        guard let best = g.max(by: { $0.value.count < $1.value.count })?.value, !best.isEmpty else {
            return rows
        }
        return best
    }

    private static func expandToInferredFullSession(_ logged: [FlatSet]) -> [FlatSet] {
        guard !logged.isEmpty else { return [] }
        let maxSn = logged.map(\.setNumber).max() ?? 1
        var target = max(logged.count, maxSn, defaultSetsPerExercise)
        target = min(target, maxInferredSetsFromSetNumber)
        
        func sourceForOrdinal(_ ordinal: Int) -> FlatSet {
            if let exact = logged.first(where: { $0.setNumber == ordinal }) { return exact }
            return logged.min(by: { abs($0.setNumber - ordinal) < abs($1.setNumber - ordinal) }) ?? logged.last!
        }
        
        return (1...target).map { ord in
            let src = sourceForOrdinal(ord)
            return FlatSet(
                workoutId: src.workoutId,
                startedAt: src.startedAt,
                workoutExerciseId: src.workoutExerciseId,
                exerciseId: src.exerciseId,
                orderIndex: src.orderIndex,
                musclePrimary: src.musclePrimary,
                setNumber: ord,
                reps: src.reps,
                weightKg: src.weightKg,
                rpe: src.rpe,
                restSec: src.restSec
            )
        }
    }
    
    private static func latestWorkoutId(forExercise exerciseId: Int64, flat: [FlatSet]) -> Int? {
        let rows = flat.filter { $0.exerciseId == exerciseId }
        guard !rows.isEmpty else { return nil }
        let wids = Set(rows.map(\.workoutId))
        func startedKey(_ wid: Int) -> Date {
            rows.first { $0.workoutId == wid }?.startedAt ?? .distantPast
        }
        return wids.max { a, b in
            let da = startedKey(a)
            let db = startedKey(b)
            if da != db { return da < db }
            return a < b
        }
    }
    
    private static func renumberStrengthSets(_ sets: [StrengthRecommendationSet]) -> [StrengthRecommendationSet] {
        sets.enumerated().map { i, s in
            StrengthRecommendationSet(setNumber: i + 1, reps: s.reps, weightKg: s.weightKg, rpe: s.rpe, restSec: s.restSec)
        }
    }
    
    private static func adjustVolumeForRpe(sets: [StrengthRecommendationSet], avgRpe: Double) -> [StrengthRecommendationSet] {
        guard !sets.isEmpty else { return sets }
        var out = sets
        let n = out.count
        let maxReps = out.map(\.reps).max() ?? defaultReps
        
        if avgRpe < 8 {
            let highVolume = maxReps >= highVolumeRepsThreshold || n >= highVolumeSetsThreshold
            if highVolume {
                return renumberStrengthSets(out)
            }
            if n < maxRecommendedSets && maxReps <= highVolumeRepsThreshold - 1 {
                let last = out.last!
                out.append(StrengthRecommendationSet(
                    setNumber: n + 1,
                    reps: last.reps,
                    weightKg: last.weightKg,
                    rpe: last.rpe,
                    restSec: last.restSec
                ))
            } else if maxReps <= maxRecommendedReps - 2 {
                out = out.map { s in
                    StrengthRecommendationSet(
                        setNumber: s.setNumber,
                        reps: min(maxRecommendedReps, s.reps + 2),
                        weightKg: s.weightKg,
                        rpe: s.rpe,
                        restSec: s.restSec
                    )
                }
            }
        }
        
        return renumberStrengthSets(out)
    }
    
    private static func suggestFrequentStrength(
        flat: [FlatSet],
        catalog: [Exercise],
        source: RecommendationDataSource,
        exerciseLanguage: ExerciseLanguage
    ) throws -> [StrengthRecommendationExercise] {
        let historyIds = Set(flat.map(\.exerciseId))
        let pool: [Exercise] = {
            switch source {
            case .recentHistory: return catalog.filter { historyIds.contains($0.id) }
            case .fullCatalog: return catalog
            }
        }()
        guard !pool.isEmpty else { throw WorkoutRecommendationError.loadFailed("No exercises in pool.") }
        
        var workoutsByExercise: [Int64: Set<Int>] = [:]
        for s in flat {
            workoutsByExercise[s.exerciseId, default: []].insert(s.workoutId)
        }
        
        let ranked: [(Exercise, Int)] = pool.map { ex in
            (ex, workoutsByExercise[ex.id]?.count ?? 0)
        }
        let sorted = ranked.sorted { a, b in
            if a.1 != b.1 { return a.1 > b.1 }
            return a.0.id < b.0.id
        }
        
        var chosen: [Exercise] = []
        var used = Set<Int64>()
        for (ex, _) in sorted {
            guard used.insert(ex.id).inserted else { continue }
            chosen.append(ex)
            if chosen.count >= targetExerciseCount { break }
        }
        if chosen.count < targetExerciseCount {
            for ex in pool.shuffled() where chosen.count < targetExerciseCount {
                if used.insert(ex.id).inserted { chosen.append(ex) }
            }
        }
        
        var result: [StrengthRecommendationExercise] = []
        for ex in chosen.prefix(targetExerciseCount) {
            let name = ex.localizedName(for: exerciseLanguage)
            var setsOut = buildSetsForExercise(exerciseId: ex.id, flat: flat, muscle: ex.muscle_primary)
            if setsOut.isEmpty {
                let w = suggestWeight(exerciseId: ex.id, flat: flat)
                let rpe: Double? = 8
                setsOut = (1...defaultSetsPerExercise).map { sn in
                    StrengthRecommendationSet(setNumber: sn, reps: defaultReps, weightKg: w, rpe: rpe, restSec: defaultRestBetweenSetsSec)
                }
            }
            result.append(StrengthRecommendationExercise(
                exerciseId: ex.id,
                displayName: name,
                musclePrimary: ex.muscle_primary,
                sets: setsOut
            ))
        }
        
        if result.isEmpty { throw WorkoutRecommendationError.loadFailed("Could not build a session.") }
        return result
    }
    
    private static func suggestBalancedStrength(
        flat: [FlatSet],
        catalog: [Exercise],
        source: RecommendationDataSource,
        exerciseLanguage: ExerciseLanguage
    ) throws -> [StrengthRecommendationExercise] {
        var muscleSetCounts: [String: Int] = [:]
        for s in flat {
            let m = normMuscle(s.musclePrimary)
            guard !m.isEmpty, m != "cardio" else { continue }
            muscleSetCounts[m, default: 0] += 1
        }
        
        let sortedMuscles = muscleSetCounts.keys.sorted { muscleSetCounts[$0]! < muscleSetCounts[$1]! }
        let targetMuscles: Set<String> = {
            if sortedMuscles.isEmpty {
                return Set(catalog.map { normMuscle($0.muscle_primary) }.filter { !$0.isEmpty && $0 != "cardio" })
            }
            return Set(sortedMuscles.prefix(min(3, sortedMuscles.count)))
        }()
        
        let historyIds = Set(flat.map(\.exerciseId))
        let pool: [Exercise] = {
            switch source {
            case .recentHistory: return catalog.filter { historyIds.contains($0.id) }
            case .fullCatalog: return catalog
            }
        }()
        
        let filtered = pool.filter { targetMuscles.contains(normMuscle($0.muscle_primary)) }
        let pickPool = filtered.isEmpty ? pool : filtered
        
        var chosen: [Exercise] = []
        var used = Set<Int64>()
        let shuffled = pickPool.shuffled()
        for ex in shuffled {
            guard used.insert(ex.id).inserted else { continue }
            chosen.append(ex)
            if chosen.count >= targetExerciseCount { break }
        }
        if chosen.count < targetExerciseCount {
            for ex in pool where chosen.count < targetExerciseCount {
                if used.insert(ex.id).inserted { chosen.append(ex) }
            }
        }
        
        var result: [StrengthRecommendationExercise] = []
        for ex in chosen.prefix(targetExerciseCount) {
            let name = ex.localizedName(for: exerciseLanguage)
            var setsOut = buildSetsForExercise(exerciseId: ex.id, flat: flat, muscle: ex.muscle_primary)
            if setsOut.isEmpty {
                let w = suggestWeight(exerciseId: ex.id, flat: flat)
                let rpe: Double? = 8
                setsOut = (1...defaultSetsPerExercise).map { sn in
                    StrengthRecommendationSet(setNumber: sn, reps: defaultReps, weightKg: w, rpe: rpe, restSec: defaultRestBetweenSetsSec)
                }
            }
            result.append(StrengthRecommendationExercise(
                exerciseId: ex.id,
                displayName: name,
                musclePrimary: ex.muscle_primary,
                sets: setsOut
            ))
        }
        
        if result.isEmpty { throw WorkoutRecommendationError.loadFailed("Could not build a session.") }
        return result
    }
    
    private static func buildSetsForExercise(
        exerciseId: Int64,
        flat: [FlatSet],
        muscle: String?
    ) -> [StrengthRecommendationSet] {
        guard let latestWid = latestWorkoutId(forExercise: exerciseId, flat: flat) else { return [] }
        let rawLast = flat.filter { $0.exerciseId == exerciseId && $0.workoutId == latestWid }
        let slice = pickBestWorkoutExerciseSlice(rawLast)
            .sorted { $0.setNumber < $1.setNumber }
        let mergedLogged = mergeDuplicateSetNumbers(slice)
        guard !mergedLogged.isEmpty else { return [] }
        let inLast = expandToInferredFullSession(mergedLogged)
        
        let rpes = inLast.compactMap { $0.rpe }.map { NSDecimalNumber(decimal: $0).doubleValue }
        let avgRpe = rpes.isEmpty ? 8.0 : rpes.reduce(0, +) / Double(rpes.count)
        
        let fallbackW = suggestWeight(exerciseId: exerciseId, flat: flat)
        var carryTemplate = 0.0
        let withWeight: [StrengthRecommendationSet] = inLast.map { s in
            var template = decimalToDouble(s.weightKg)
            if template <= 0 {
                template = carryTemplate > 0 ? carryTemplate : fallbackW
            } else {
                carryTemplate = template
            }
            let adj = adjustWeight(base: template, avgRpe: avgRpe)
            let reps = max(minRecommendedReps, min(maxRecommendedReps, s.reps ?? defaultReps))
            let rpeOut = s.rpe.map { NSDecimalNumber(decimal: $0).doubleValue }
            return StrengthRecommendationSet(
                setNumber: s.setNumber,
                reps: reps,
                weightKg: roundToHalf(adj),
                rpe: rpeOut,
                restSec: s.restSec ?? defaultRestBetweenSetsSec
            )
        }
        
        return adjustVolumeForRpe(sets: withWeight, avgRpe: avgRpe)
    }
    
    private static func suggestWeight(exerciseId: Int64, flat: [FlatSet]) -> Double {
        guard let latestWid = latestWorkoutId(forExercise: exerciseId, flat: flat) else { return 20 }
        let slice = flat.filter { $0.exerciseId == exerciseId && $0.workoutId == latestWid && $0.weightKg != nil }
        let weights = slice.compactMap { $0.weightKg }.map { NSDecimalNumber(decimal: $0).doubleValue }
        guard !weights.isEmpty else {
            let any = flat.filter { $0.exerciseId == exerciseId && $0.weightKg != nil }
            let fallback = any.compactMap { $0.weightKg }.map { NSDecimalNumber(decimal: $0).doubleValue }
            return roundToHalf(fallback.max() ?? 20)
        }
        let base = weights.max() ?? 20
        let rpes = slice.compactMap { $0.rpe }.map { NSDecimalNumber(decimal: $0).doubleValue }
        let avgRpe = rpes.isEmpty ? 8.0 : rpes.reduce(0, +) / Double(rpes.count)
        return roundToHalf(adjustWeight(base: base, avgRpe: avgRpe))
    }
    
    private static func adjustWeight(base: Double, avgRpe: Double) -> Double {
        if avgRpe < 8 { return base + 2.5 }
        if avgRpe >= 9 { return max(0, base - 2.5) }
        return base
    }
    
    private static func roundToHalf(_ x: Double) -> Double {
        (x * 2).rounded() / 2
    }
    
    private static func beginnerCardioRecommendation(activity: CardioActivityType, rationale: String) -> CardioRecommendation {
        var dur = 30 * 60
        var dist: Double?
        var elev: Int?
        var avg: Int?
        var maxH: Int?
        var incline: Double?
        var cadence: Int?
        var watts: Int?
        var split: Int?
        var laps: Int?
        var pool: Int?
        var style: String?
        
        switch activity {
        case .walk:
            dur = 30 * 60
            dist = 2.2
            elev = 25
            avg = 112
            maxH = 132
        case .run:
            dur = 25 * 60
            dist = 3.0
            avg = 130
            maxH = 155
        case .hike:
            dur = 40 * 60
            dist = 3.5
            elev = 160
            avg = 118
            maxH = 142
        case .treadmill:
            dur = 25 * 60
            dist = 2.0
            avg = 124
            maxH = 148
            incline = 1.0
        case .bike:
            dur = 35 * 60
            dist = 10.0
            avg = 124
            maxH = 150
            cadence = 75
            watts = 105
        case .e_bike:
            dur = 40 * 60
            dist = 14.0
            avg = 108
            maxH = 128
            cadence = 62
            watts = 75
        case .mtb:
            dur = 35 * 60
            dist = 8.0
            elev = 140
            avg = 128
            maxH = 154
            cadence = 72
            watts = 115
        case .indoor_cycling:
            dur = 25 * 60
            dist = 8.0
            avg = 118
            maxH = 142
            cadence = 72
            watts = 95
        case .rowerg:
            dur = 12 * 60
            dist = 2.4
            avg = 132
            maxH = 156
            cadence = 24
            watts = 100
            split = 150
        case .swim_pool:
            dur = 20 * 60
            dist = 0.25
            avg = 122
            maxH = 142
            laps = 10
            pool = 25
            style = "freestyle"
        case .swim_open_water:
            dur = 18 * 60
            dist = 0.7
            avg = 122
            maxH = 148
        }
        
        return CardioRecommendation(
            activity: activity,
            durationSec: dur,
            distanceKm: dist,
            elevationGainM: activity.showsElevation ? elev : nil,
            avgHr: avg,
            maxHr: maxH,
            inclinePercent: activity.showsIncline ? incline : nil,
            cadenceRpm: activity.showsCadenceRpm ? cadence : nil,
            wattsAvg: activity.showsWatts ? watts : nil,
            splitSecPer500m: activity.showsSplit500m ? split : nil,
            swimLaps: activity.showsSwimFields ? laps : nil,
            poolLengthM: activity.showsSwimFields ? pool : nil,
            swimStyle: activity.showsSwimFields ? style : nil,
            rationale: rationale
        )
    }
    
    static func recommendCardio(userId: UUID, source: RecommendationDataSource) async throws -> CardioRecommendation {
        let client = SupabaseManager.shared.client
        let decoder = JSONDecoder.supabase()
        
        struct WRow: Decodable { let id: Int }
        let wRes = try await client
            .from("workouts")
            .select("id")
            .eq("user_id", value: userId.uuidString)
            .eq("kind", value: "cardio")
            .eq("state", value: "published")
            .order("started_at", ascending: false)
            .limit(lookbackCount)
            .execute()
        let wRows = try decoder.decode([WRow].self, from: wRes.data)
        if wRows.isEmpty {
            if source == .fullCatalog {
                return beginnerCardioRecommendation(
                    activity: .walk,
                    rationale: "You don’t have cardio workouts in your history yet. These are easy starter targets (conversation-pace effort)—adjust any field in the form."
                )
            }
            throw WorkoutRecommendationError.noWorkoutsInWindow
        }
        let ids = wRows.map { String($0.id) }
        
        struct CS: Decodable {
            let id: Int
            let modality: String?
            let activity_code: String?
            let duration_sec: Int?
            let distance_km: Decimal?
            let avg_hr: Int?
            let max_hr: Int?
            let elevation_gain_m: Int?
        }
        
        struct CardioStatsWire: Decodable {
            let session_id: Int
            let stats: StatsPayload?
            struct StatsPayload: Decodable {
                let cadence_rpm: Int?
                let watts_avg: Int?
                let incline_pct: Double?
                let swim_laps: Int?
                let pool_length_m: Int?
                let swim_style: String?
                let split_sec_per_500m: Int?
            }
        }
        
        let res = try await client
            .from("cardio_sessions")
            .select("id, workout_id, modality, activity_code, duration_sec, distance_km, avg_hr, max_hr, elevation_gain_m")
            .in("workout_id", values: ids)
            .execute()
        
        let rows = try decoder.decode([CS].self, from: res.data)
        struct EnrichedCardioSession {
            let id: Int
            let code: String
            let duration: Int
            let distance: Double?
            let elevationM: Int?
            let avgHr: Int?
            let maxHr: Int?
        }
        
        var sessions: [EnrichedCardioSession] = []
        for cs in rows {
            let code = (cs.activity_code ?? cs.modality ?? "run").lowercased()
            let dur = cs.duration_sec ?? 3600
            let dist = cs.distance_km.map { NSDecimalNumber(decimal: $0).doubleValue }
            sessions.append(EnrichedCardioSession(
                id: cs.id,
                code: code,
                duration: dur,
                distance: dist,
                elevationM: cs.elevation_gain_m,
                avgHr: cs.avg_hr,
                maxHr: cs.max_hr
            ))
        }
        if sessions.isEmpty {
            if source == .fullCatalog {
                return beginnerCardioRecommendation(
                    activity: .walk,
                    rationale: "No cardio details in those workouts yet. Easy starter targets you can edit—keep intensity comfortable."
                )
            }
            throw WorkoutRecommendationError.loadFailed("No cardio session rows.")
        }
        
        var counts: [String: Int] = [:]
        for s in sessions { counts[s.code, default: 0] += 1 }
        
        let candidateCodes: [String] = {
            switch source {
            case .recentHistory:
                return Array(Set(sessions.map(\.code)))
            case .fullCatalog:
                return CardioActivityType.allCases.map(\.rawValue)
            }
        }()
        
        let sortedByRare = candidateCodes.sorted { (counts[$0] ?? 0) < (counts[$1] ?? 0) }
        let pickedCode = sortedByRare.first ?? "walk"
        let activity = CardioActivityType(rawValue: pickedCode) ?? .walk
        
        let matching = sessions.filter { $0.code == pickedCode }
        let usedCrossActivityFallback = matching.isEmpty
        let scalarPool: [EnrichedCardioSession] = usedCrossActivityFallback ? sessions : matching
        
        let durs = matching.map(\.duration)
        let medianDur = medianInt(durs.isEmpty ? sessions.map(\.duration) : durs)
        
        let distancePool: [EnrichedCardioSession] = {
            if !usedCrossActivityFallback { return matching }
            switch activity {
            case .swim_pool, .swim_open_water:
                let swim = sessions.filter { $0.code == CardioActivityType.swim_pool.rawValue || $0.code == CardioActivityType.swim_open_water.rawValue }
                return swim.isEmpty ? sessions : swim
            default:
                return sessions
            }
        }()
        
        let medianDist = medianDoubleOpt(distancePool.compactMap(\.distance))
        let medianElev = activity.showsElevation ? medianIntOpt(scalarPool.compactMap(\.elevationM)) : nil
        let medAvgHr = medianIntOpt(scalarPool.compactMap(\.avgHr))
        let medMaxHr = medianIntOpt(scalarPool.compactMap(\.maxHr))
        
        var statsBySession: [Int: CardioStatsWire.StatsPayload] = [:]
        let statsSessionIds = usedCrossActivityFallback ? sessions.map(\.id) : matching.map(\.id)
        if !statsSessionIds.isEmpty {
            do {
                let stRes = try await client
                    .from("cardio_session_stats")
                    .select("session_id, stats")
                    .in("session_id", values: statsSessionIds)
                    .execute()
                let parsed = try decoder.decode([CardioStatsWire].self, from: stRes.data)
                for r in parsed {
                    if let st = r.stats { statsBySession[r.session_id] = st }
                }
            } catch {
            }
        }
        
        let inclinePct: Double? = activity.showsIncline
            ? medianDoubleOpt(scalarPool.compactMap { statsBySession[$0.id]?.incline_pct })
            : nil
        let cadence: Int? = activity.showsCadenceRpm
            ? medianIntOpt(scalarPool.compactMap { statsBySession[$0.id]?.cadence_rpm })
            : nil
        let watts: Int? = activity.showsWatts
            ? medianIntOpt(scalarPool.compactMap { statsBySession[$0.id]?.watts_avg })
            : nil
        let split500: Int? = activity.showsSplit500m
            ? medianIntOpt(scalarPool.compactMap { statsBySession[$0.id]?.split_sec_per_500m })
            : nil
        let swimLaps: Int? = activity.showsSwimFields
            ? medianIntOpt(scalarPool.compactMap { statsBySession[$0.id]?.swim_laps })
            : nil
        let poolLen: Int? = activity.showsSwimFields
            ? medianIntOpt(scalarPool.compactMap { statsBySession[$0.id]?.pool_length_m })
            : nil
        let swimStyle: String? = activity.showsSwimFields
            ? scalarPool.compactMap { statsBySession[$0.id]?.swim_style }.first { !$0.isEmpty }
            : nil
        
        var rationale = "Among \(source == .recentHistory ? "activities you logged" : "all app activities"), this one was least frequent in your last \(lookbackCount) cardio workouts."
        if usedCrossActivityFallback {
            rationale += " Values are estimated from your other cardio in this window, since you haven’t logged this activity yet."
        }
        return CardioRecommendation(
            activity: activity,
            durationSec: medianDur,
            distanceKm: medianDist,
            elevationGainM: medianElev,
            avgHr: medAvgHr,
            maxHr: medMaxHr,
            inclinePercent: inclinePct,
            cadenceRpm: cadence,
            wattsAvg: watts,
            splitSecPer500m: split500,
            swimLaps: swimLaps,
            poolLengthM: poolLen,
            swimStyle: swimStyle,
            rationale: rationale
        )
    }
    
    static func recommendSport(userId: UUID, source: RecommendationDataSource) async throws -> SportRecommendation {
        let client = SupabaseManager.shared.client
        let decoder = JSONDecoder.supabase()
        
        struct WRow: Decodable { let id: Int }
        let wRes = try await client
            .from("workouts")
            .select("id")
            .eq("user_id", value: userId.uuidString)
            .eq("kind", value: "sport")
            .eq("state", value: "published")
            .order("started_at", ascending: false)
            .limit(lookbackCount)
            .execute()
        let wRows = try decoder.decode([WRow].self, from: wRes.data)
        if wRows.isEmpty {
            if source == .fullCatalog {
                return .durationOnly(
                    durationMin: 60,
                    rationale: "You don’t have sport workouts in your history yet. Here’s a session length you can use with any sport—adjust as you like."
                )
            }
            throw WorkoutRecommendationError.noWorkoutsInWindow
        }
        let ids = wRows.map { String($0.id) }
        
        struct SS: Decodable {
            let id: Int
            let sport: String?
            let duration_sec: Int?
        }
        
        let res = try await client
            .from("sport_sessions")
            .select("id, sport, duration_sec")
            .in("workout_id", values: ids)
            .execute()
        let rows = try decoder.decode([SS].self, from: res.data)
        struct SportSessionLite {
            let id: Int
            let sport: String
            let durationMin: Int
        }
        var sessions: [SportSessionLite] = []
        for ss in rows {
            guard let sp = ss.sport, !sp.isEmpty else { continue }
            let dm = max(1, ss.duration_sec.map { $0 / 60 } ?? 60)
            sessions.append(SportSessionLite(id: ss.id, sport: sp.lowercased(), durationMin: dm))
        }
        if sessions.isEmpty {
            if source == .fullCatalog {
                return .durationOnly(
                    durationMin: 60,
                    rationale: "No sport details in those sessions yet. Suggested duration only—pick any sport in the form."
                )
            }
            throw WorkoutRecommendationError.loadFailed("No sport session rows.")
        }
        
        var counts: [String: Int] = [:]
        for s in sessions { counts[s.sport, default: 0] += 1 }
        
        let candidates: [String] = {
            switch source {
            case .recentHistory:
                return Array(Set(sessions.map(\.sport)))
            case .fullCatalog:
                return SportType.allCases.map(\.rawValue)
            }
        }()
        
        let sorted = candidates.sorted { (counts[$0] ?? 0) < (counts[$1] ?? 0) }
        guard let raw = sorted.first else {
            throw WorkoutRecommendationError.loadFailed("Could not pick a sport.")
        }
        
        let matching = sessions.filter { $0.sport == raw }
        let allMins = sessions.map(\.durationMin)
        let matchMins = matching.map(\.durationMin)
        let medianMin = medianSportMinutes(matchMins.isEmpty ? allMins : matchMins)
        
        let baseRationale = "Among \(source == .recentHistory ? "sports you logged" : "all app sports"), this one was least frequent in your last \(lookbackCount) sessions."
        
        guard raw == SportType.hyrox.rawValue else {
            var rationale = baseRationale
            rationale += " Suggested session length only—choose whichever sport fits in the form."
            return .durationOnly(durationMin: medianMin, rationale: rationale)
        }
        
        let hyroxSessionIds = sessions.filter { $0.sport == SportType.hyrox.rawValue }.map(\.id)
        var exRows: [HyroxExRow] = []
        if !hyroxSessionIds.isEmpty {
            do {
                let exRes = try await client
                    .from("hyrox_session_exercises")
                    .select("exercise_code, exercise_order, distance_m, reps, weight_kg, duration_sec, height_cm, implement_count, notes, exercise_display_name")
                    .in("session_id", values: hyroxSessionIds)
                    .execute()
                exRows = try decoder.decode([HyroxExRow].self, from: exRes.data)
            } catch {
                exRows = []
            }
        }
        
        let exercises = buildHyroxExerciseRecommendations(from: exRows)
        var rationale = baseRationale
        if exRows.isEmpty {
            rationale += " No Hyrox stations in your history yet—here’s a starter template you can edit."
        } else {
            rationale += " Stations lean on ones you’ve logged less often; metrics are typical values from your Hyrox sessions."
        }
        return .hyrox(durationMin: medianMin, exercises: exercises, rationale: rationale)
    }
    
    private static func buildHyroxExerciseRecommendations(from rows: [HyroxExRow]) -> [HyroxExerciseRecommendation] {
        if rows.isEmpty {
            return Self.hyroxColdStartExercises()
        }
        let byCode = Dictionary(grouping: rows) { $0.exercise_code.lowercased() }
        let stdOrder = Dictionary(uniqueKeysWithValues: HyroxExerciseCode.allCases.enumerated().map { ($0.element.rawValue, $0.offset) })
        
        let codesSorted = byCode.keys.sorted { a, b in
            let ca = byCode[a]?.count ?? 0
            let cb = byCode[b]?.count ?? 0
            if ca != cb { return ca < cb }
            return (stdOrder[a] ?? 999) < (stdOrder[b] ?? 999)
        }
        
        let picked = Array(codesSorted.prefix(6))
        return picked.enumerated().map { idx, code in
            let group = byCode[code] ?? []
            let fields = HyroxExerciseFormatting.formFields(
                exerciseCode: code,
                exerciseDisplayName: group.compactMap(\.exercise_display_name).first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            )
            return HyroxExerciseRecommendation(
                exerciseCode: fields.code,
                customDisplayName: fields.customDisplayName,
                exerciseOrder: idx + 1,
                distanceM: medianIntOpt(group.compactMap(\.distance_m)),
                reps: medianIntOpt(group.compactMap(\.reps)),
                weightKg: medianDoubleOpt(group.compactMap { $0.weight_kg.map { NSDecimalNumber(decimal: $0).doubleValue } }),
                durationSec: medianIntOpt(group.compactMap(\.duration_sec)),
                heightCm: medianIntOpt(group.compactMap(\.height_cm)),
                implementCount: medianIntOpt(group.compactMap(\.implement_count)),
                notes: group.compactMap(\.notes).first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            )
        }
    }
    
    private static func hyroxColdStartExercises() -> [HyroxExerciseRecommendation] {
        [
            HyroxExerciseRecommendation(
                exerciseCode: HyroxExerciseCode.run.rawValue,
                customDisplayName: "",
                exerciseOrder: 1,
                distanceM: 1_000,
                reps: nil,
                weightKg: nil,
                durationSec: nil,
                heightCm: nil,
                implementCount: nil,
                notes: nil
            ),
            HyroxExerciseRecommendation(
                exerciseCode: HyroxExerciseCode.skierg.rawValue,
                customDisplayName: "",
                exerciseOrder: 2,
                distanceM: 1_000,
                reps: nil,
                weightKg: nil,
                durationSec: nil,
                heightCm: nil,
                implementCount: nil,
                notes: nil
            ),
            HyroxExerciseRecommendation(
                exerciseCode: HyroxExerciseCode.row.rawValue,
                customDisplayName: "",
                exerciseOrder: 3,
                distanceM: 500,
                reps: nil,
                weightKg: nil,
                durationSec: nil,
                heightCm: nil,
                implementCount: nil,
                notes: nil
            ),
            HyroxExerciseRecommendation(
                exerciseCode: HyroxExerciseCode.sledPush.rawValue,
                customDisplayName: "",
                exerciseOrder: 4,
                distanceM: 50,
                reps: nil,
                weightKg: nil,
                durationSec: nil,
                heightCm: nil,
                implementCount: nil,
                notes: nil
            )
        ]
    }
    
    private static func medianSportMinutes(_ arr: [Int]) -> Int {
        guard !arr.isEmpty else { return 60 }
        let s = arr.sorted()
        return max(15, s[s.count / 2])
    }
    
    private static func medianInt(_ arr: [Int]) -> Int {
        guard !arr.isEmpty else { return 3600 }
        let s = arr.sorted()
        return s[s.count / 2]
    }
    
    private static func medianIntOpt(_ arr: [Int]) -> Int? {
        guard !arr.isEmpty else { return nil }
        let s = arr.sorted()
        return s[s.count / 2]
    }
    
    private static func medianDoubleOpt(_ arr: [Double]) -> Double? {
        guard !arr.isEmpty else { return nil }
        let s = arr.sorted()
        return s[s.count / 2]
    }
}
