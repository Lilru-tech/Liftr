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
    let calories_kcal: Decimal?
    let exercise_display_name: String?
}

private struct SportRecSession {
    let id: Int
    let sport: String
    let durationMin: Int
}

enum WorkoutRecommendationService {
    
    private typealias C = WorkoutRecommendationConstants
    
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
        exerciseLanguage: ExerciseLanguage,
        networkInspired: Bool = false,
        excludeRoutineId: Int64? = nil
    ) async throws -> StrengthRecommendationOutput {
        let ctx = await WorkoutRecommendationContext.load(
            userId: userId,
            catalog: catalog,
            includeNetwork: networkInspired || source == .networkInspired
        )
        
        if source == .myRoutines {
            return try await recommendFromSavedStrengthRoutine(
                userId: userId,
                catalog: catalog,
                exerciseLanguage: exerciseLanguage,
                ctx: ctx,
                excludeRoutineId: excludeRoutineId
            )
        }
        
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
            .limit(C.lookbackCount)
            .execute()
        
        let workouts = try decoder.decode([WRow].self, from: wRes.data)
        if workouts.isEmpty {
            guard source == .fullCatalog || source == .networkInspired, !catalog.isEmpty else {
                throw WorkoutRecommendationError.noWorkoutsInWindow
            }
            let exercises = try coldStartStrength(catalog: catalog, exerciseLanguage: exerciseLanguage, ctx: ctx)
            return wrapStrengthOutput(exercises: exercises, ctx: ctx, flat: [], extraRationale: nil)
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
        
        let exercises: [StrengthRecommendationExercise]
        switch mode {
        case .prioritizeUndertrainedMuscles:
            exercises = try suggestBalancedStrength(
                flat: flat,
                catalog: catalog,
                source: source,
                exerciseLanguage: exerciseLanguage,
                ctx: ctx
            )
        case .prioritizeFrequentLifts:
            exercises = try suggestFrequentStrength(
                flat: flat,
                catalog: catalog,
                source: source,
                exerciseLanguage: exerciseLanguage,
                ctx: ctx
            )
        case .chasePRs:
            exercises = try suggestChasePRStrength(
                flat: flat,
                catalog: catalog,
                source: source,
                exerciseLanguage: exerciseLanguage,
                ctx: ctx
            )
        }
        return wrapStrengthOutput(exercises: exercises, ctx: ctx, flat: flat, extraRationale: ctx.partialDataNote)
    }
    
    private static func wrapStrengthOutput(
        exercises: [StrengthRecommendationExercise],
        ctx: WorkoutRecommendationContext,
        flat: [FlatSet],
        extraRationale: String?,
        routineName: String? = nil
    ) -> StrengthRecommendationOutput {
        let favCount = exercises.filter { ctx.favoriteExerciseIds.contains($0.exerciseId) }.count
        var parts: [String] = []
        if favCount > 0 {
            parts.append(favCount == 1 ? "Includes 1 of your favorites." : "Includes \(favCount) of your favorites.")
        }
        if let extra = extraRationale, !extra.isEmpty { parts.append(extra) }
        if let goal = ctx.goalNudge?.summaryLine { parts.append(goal) }
        let freshness = muscleFreshnessEntries(from: flat)
        return StrengthRecommendationOutput(
            exercises: exercises,
            sessionRationale: parts.isEmpty ? nil : parts.joined(separator: " "),
            muscleFreshness: freshness,
            routineName: routineName
        )
    }
    
    private static func muscleFreshnessEntries(from flat: [FlatSet]) -> [MuscleFreshnessEntry] {
        let now = Date()
        var lastByMuscle: [String: Date] = [:]
        for s in flat {
            let m = normMuscle(s.musclePrimary)
            guard !m.isEmpty, m != "cardio", let st = s.startedAt else { continue }
            if let prev = lastByMuscle[m] {
                if st > prev { lastByMuscle[m] = st }
            } else {
                lastByMuscle[m] = st
            }
        }
        return lastByMuscle.keys.sorted().map { muscle in
            let last = lastByMuscle[muscle] ?? .distantPast
            let hours = now.timeIntervalSince(last) / 3600
            let status: MuscleFreshnessEntry.Status = {
                if hours >= 72 { return .fresh }
                if hours >= Double(C.recoveryDeprioritizeHours) { return .recent }
                return .trainedRecently
            }()
            return MuscleFreshnessEntry(id: muscle, muscle: muscle.capitalized, status: status)
        }
    }
    
    private static func recommendFromSavedStrengthRoutine(
        userId: UUID,
        catalog: [Exercise],
        exerciseLanguage: ExerciseLanguage,
        ctx: WorkoutRecommendationContext,
        excludeRoutineId: Int64?
    ) async throws -> StrengthRecommendationOutput {
        let client = SupabaseManager.shared.client
        struct RoutineListRow: Decodable { let id: Int64; let name: String; let updated_at: Date? }
        let rRes = try await client
            .from("strength_routines")
            .select("id, name, updated_at")
            .eq("user_id", value: userId.uuidString)
            .order("updated_at", ascending: true)
            .execute()
        var rows = try JSONDecoder.supabase().decode([RoutineListRow].self, from: rRes.data)
        if let ex = excludeRoutineId {
            rows = rows.filter { $0.id != ex }
        }
        guard let picked = rows.randomElement() ?? rows.first else {
            throw WorkoutRecommendationError.loadFailed("Save a strength routine first, or pick another data source.")
        }
        let detail = try await fetchStrengthRoutineTemplateDetail(client: client, routineId: picked.id)
        let exercises = strengthRecommendationsFromRoutineDetail(detail, catalog: catalog, exerciseLanguage: exerciseLanguage)
        guard !exercises.isEmpty else {
            throw WorkoutRecommendationError.loadFailed("That routine has no exercises.")
        }
        let out = wrapStrengthOutput(
            exercises: exercises,
            ctx: ctx,
            flat: [],
            extraRationale: "Loaded from your routine \"\(picked.name)\".",
            routineName: picked.name
        )
        return out
    }
    
    private static func normMuscle(_ s: String?) -> String {
        (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
    
    private static func coldStartStrength(
        catalog: [Exercise],
        exerciseLanguage: ExerciseLanguage,
        ctx: WorkoutRecommendationContext
    ) throws -> [StrengthRecommendationExercise] {
        let pool = WorkoutRecommendationConstants.biasedShuffle(catalog) { ctx.favoriteExerciseIds.contains($0.id) }
        var result: [StrengthRecommendationExercise] = []
        let w = ctx.defaultColdStartWeightKg()
        let rpe: Double? = 8
        for ex in pool.prefix(C.targetExerciseCount) {
            let setsOut = (1...C.defaultSetsPerExercise).map { sn in
                StrengthRecommendationSet(setNumber: sn, reps: C.defaultReps, weightKg: w, rpe: rpe, restSec: C.defaultRestBetweenSetsSec)
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
        var target = max(logged.count, maxSn, C.defaultSetsPerExercise)
        target = min(target, C.maxInferredSetsFromSetNumber)
        
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
        let maxReps = out.map(\.reps).max() ?? C.defaultReps
        
        if avgRpe < 8 {
            let highVolume = maxReps >= C.highVolumeRepsThreshold || n >= C.highVolumeSetsThreshold
            if highVolume {
                return renumberStrengthSets(out)
            }
            if n < C.maxRecommendedSets && maxReps <= C.highVolumeRepsThreshold - 1 {
                let last = out.last!
                out.append(StrengthRecommendationSet(
                    setNumber: n + 1,
                    reps: last.reps,
                    weightKg: last.weightKg,
                    rpe: last.rpe,
                    restSec: last.restSec
                ))
            } else if maxReps <= C.maxRecommendedReps - 2 {
                out = out.map { s in
                    StrengthRecommendationSet(
                        setNumber: s.setNumber,
                        reps: min(C.maxRecommendedReps, s.reps + 2),
                        weightKg: s.weightKg,
                        rpe: s.rpe,
                        restSec: s.restSec
                    )
                }
            }
        }
        
        return renumberStrengthSets(out)
    }
    
    private static func exercisePool(
        catalog: [Exercise],
        source: RecommendationDataSource,
        historyIds: Set<Int64>,
        ctx: WorkoutRecommendationContext
    ) -> [Exercise] {
        let base: [Exercise] = {
            switch source {
            case .recentHistory, .hyrox, .hyroxRace:
                return catalog.filter { historyIds.contains($0.id) }
            case .fullCatalog, .myRoutines:
                return catalog
            case .networkInspired:
                let networkIds = Set(ctx.networkExerciseFrequency.keys)
                if networkIds.isEmpty { return catalog.filter { historyIds.contains($0.id) } }
                return catalog.filter { networkIds.contains($0.id) || historyIds.contains($0.id) }
            }
        }()
        return base
    }
    
    private static func rankExercisesForNetwork(_ pool: [Exercise], ctx: WorkoutRecommendationContext) -> [Exercise] {
        pool.sorted { a, b in
            let fa = ctx.networkExerciseFrequency[a.id] ?? 0
            let fb = ctx.networkExerciseFrequency[b.id] ?? 0
            if fa != fb { return fa > fb }
            return a.id < b.id
        }
    }
    
    private static func suggestFrequentStrength(
        flat: [FlatSet],
        catalog: [Exercise],
        source: RecommendationDataSource,
        exerciseLanguage: ExerciseLanguage,
        ctx: WorkoutRecommendationContext
    ) throws -> [StrengthRecommendationExercise] {
        let historyIds = Set(flat.map(\.exerciseId))
        let pool = exercisePool(catalog: catalog, source: source, historyIds: historyIds, ctx: ctx)
        guard !pool.isEmpty else { throw WorkoutRecommendationError.loadFailed("No exercises in pool.") }
        
        var workoutsByExercise: [Int64: Set<Int>] = [:]
        for s in flat {
            workoutsByExercise[s.exerciseId, default: []].insert(s.workoutId)
        }
        
        let ranked: [(Exercise, Int)] = pool.map { ex in
            (ex, workoutsByExercise[ex.id]?.count ?? 0)
        }
        var sorted = ranked.sorted { a, b in
            if a.1 != b.1 { return a.1 > b.1 }
            return a.0.id < b.0.id
        }
        if source == .networkInspired, !ctx.networkExerciseFrequency.isEmpty {
            sorted = rankExercisesForNetwork(pool, ctx: ctx).map { ex in
                (ex, workoutsByExercise[ex.id]?.count ?? 0)
            }
        }
        
        var chosen: [Exercise] = []
        var used = Set<Int64>()
        for (ex, _) in sorted {
            guard used.insert(ex.id).inserted else { continue }
            chosen.append(ex)
            if chosen.count >= C.targetExerciseCount { break }
        }
        if chosen.count < C.targetExerciseCount {
            let shuffled = WorkoutRecommendationConstants.biasedShuffle(pool) { ctx.favoriteExerciseIds.contains($0.id) }
            for ex in shuffled where chosen.count < C.targetExerciseCount {
                if used.insert(ex.id).inserted { chosen.append(ex) }
            }
        }
        
        return buildStrengthResultList(chosen: chosen.prefix(C.targetExerciseCount).map { $0 }, flat: flat, catalog: catalog, exerciseLanguage: exerciseLanguage, ctx: ctx)
    }
    
    private static func suggestChasePRStrength(
        flat: [FlatSet],
        catalog: [Exercise],
        source: RecommendationDataSource,
        exerciseLanguage: ExerciseLanguage,
        ctx: WorkoutRecommendationContext
    ) throws -> [StrengthRecommendationExercise] {
        let historyIds = Set(flat.map(\.exerciseId))
        let pool = exercisePool(catalog: catalog, source: source, historyIds: historyIds, ctx: ctx)
        guard !pool.isEmpty else { throw WorkoutRecommendationError.loadFailed("No exercises in pool.") }
        
        var chaseCandidates: [(Exercise, Double)] = []
        for ex in pool {
            guard let pr = ctx.prMaxWeightByExerciseId[ex.id], pr > 0 else { continue }
            let latestW = latestMaxWeight(for: ex.id, flat: flat)
            guard latestW > 0 else { continue }
            if latestW >= pr * (1 - C.prChaseProximityRatio) {
                chaseCandidates.append((ex, pr - latestW))
            }
        }
        chaseCandidates.sort { abs($0.1) < abs($1.1) }
        var chosen = chaseCandidates.prefix(C.targetExerciseCount).map(\.0)
        if chosen.count < C.targetExerciseCount {
            let fallback = try suggestFrequentStrength(
                flat: flat,
                catalog: catalog,
                source: source == .networkInspired ? .recentHistory : source,
                exerciseLanguage: exerciseLanguage,
                ctx: ctx
            )
            let existing = Set(chosen.map(\.id))
            for ex in fallback where chosen.count < C.targetExerciseCount {
                if let match = catalog.first(where: { $0.id == ex.exerciseId }), !existing.contains(match.id) {
                    chosen.append(match)
                }
            }
        }
        guard !chosen.isEmpty else {
            return try suggestFrequentStrength(flat: flat, catalog: catalog, source: source, exerciseLanguage: exerciseLanguage, ctx: ctx)
        }
        return buildStrengthResultList(chosen: chosen, flat: flat, catalog: catalog, exerciseLanguage: exerciseLanguage, ctx: ctx)
    }
    
    private static func latestMaxWeight(for exerciseId: Int64, flat: [FlatSet]) -> Double {
        guard let wid = latestWorkoutId(forExercise: exerciseId, flat: flat) else { return 0 }
        let weights = flat.filter { $0.exerciseId == exerciseId && $0.workoutId == wid }
            .compactMap { $0.weightKg }.map { NSDecimalNumber(decimal: $0).doubleValue }
        return weights.max() ?? 0
    }
    
    private static func buildStrengthResultList(
        chosen: [Exercise],
        flat: [FlatSet],
        catalog: [Exercise],
        exerciseLanguage: ExerciseLanguage,
        ctx: WorkoutRecommendationContext
    ) -> [StrengthRecommendationExercise] {
        var result: [StrengthRecommendationExercise] = []
        for ex in chosen {
            let name = ex.localizedName(for: exerciseLanguage)
            var setsOut = buildSetsForExercise(exerciseId: ex.id, flat: flat, muscle: ex.muscle_primary, ctx: ctx)
            if setsOut.isEmpty {
                let w = suggestWeight(exerciseId: ex.id, flat: flat, ctx: ctx)
                let rpe: Double? = 8
                setsOut = (1...C.defaultSetsPerExercise).map { sn in
                    StrengthRecommendationSet(setNumber: sn, reps: C.defaultReps, weightKg: w, rpe: rpe, restSec: C.defaultRestBetweenSetsSec)
                }
            }
            result.append(StrengthRecommendationExercise(
                exerciseId: ex.id,
                displayName: name,
                musclePrimary: ex.muscle_primary,
                sets: setsOut
            ))
        }
        return result
    }
    
    private static func timeWeightedSetCount(flat: [FlatSet]) -> [String: Double] {
        let now = Date()
        var counts: [String: Double] = [:]
        for s in flat {
            let m = normMuscle(s.musclePrimary)
            guard !m.isEmpty, m != "cardio" else { continue }
            let days = max(0, now.timeIntervalSince(s.startedAt ?? now) / 86400)
            let weight = exp(-days / 7.0)
            counts[m, default: 0] += weight
        }
        return counts
    }
    
    private static func recentlyTrainedMuscles(flat: [FlatSet]) -> Set<String> {
        let cutoff = Date().addingTimeInterval(-Double(C.recoveryDeprioritizeHours) * 3600)
        var out = Set<String>()
        for s in flat {
            guard let st = s.startedAt, st >= cutoff else { continue }
            let m = normMuscle(s.musclePrimary)
            if !m.isEmpty, m != "cardio" { out.insert(m) }
        }
        return out
    }
    
    private static func suggestBalancedStrength(
        flat: [FlatSet],
        catalog: [Exercise],
        source: RecommendationDataSource,
        exerciseLanguage: ExerciseLanguage,
        ctx: WorkoutRecommendationContext
    ) throws -> [StrengthRecommendationExercise] {
        let muscleSetCounts = timeWeightedSetCount(flat: flat)
        let recentMuscles = recentlyTrainedMuscles(flat: flat)
        
        let sortedMuscles = muscleSetCounts.keys.sorted { muscleSetCounts[$0]! < muscleSetCounts[$1]! }
        let targetMuscles: Set<String> = {
            if sortedMuscles.isEmpty {
                return Set(catalog.map { normMuscle($0.muscle_primary) }.filter { !$0.isEmpty && $0 != "cardio" })
            }
            let preferred = sortedMuscles.filter { !recentMuscles.contains($0) }
            let base = preferred.isEmpty ? sortedMuscles : preferred
            return Set(base.prefix(min(3, base.count)))
        }()
        
        let historyIds = Set(flat.map(\.exerciseId))
        let pool = exercisePool(catalog: catalog, source: source, historyIds: historyIds, ctx: ctx)
        
        let filtered = pool.filter { targetMuscles.contains(normMuscle($0.muscle_primary)) }
        let pickPool = filtered.isEmpty ? pool : filtered
        
        var chosen: [Exercise] = []
        var used = Set<Int64>()
        let shuffled = WorkoutRecommendationConstants.biasedShuffle(pickPool) { ctx.favoriteExerciseIds.contains($0.id) }
        for ex in shuffled {
            guard used.insert(ex.id).inserted else { continue }
            chosen.append(ex)
            if chosen.count >= C.targetExerciseCount { break }
        }
        if chosen.count < C.targetExerciseCount {
            for ex in pool where chosen.count < C.targetExerciseCount {
                if used.insert(ex.id).inserted { chosen.append(ex) }
            }
        }
        
        let result = buildStrengthResultList(
            chosen: chosen.prefix(C.targetExerciseCount).map { $0 },
            flat: flat,
            catalog: catalog,
            exerciseLanguage: exerciseLanguage,
            ctx: ctx
        )
        if result.isEmpty { throw WorkoutRecommendationError.loadFailed("Could not build a session.") }
        return result
    }
    
    private static func buildSetsForExercise(
        exerciseId: Int64,
        flat: [FlatSet],
        muscle: String?,
        ctx: WorkoutRecommendationContext
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
        
        let fallbackW = suggestWeight(exerciseId: exerciseId, flat: flat, ctx: ctx)
        let prCap = ctx.prMaxWeightByExerciseId[exerciseId].map { $0 + C.prCapIncrementKg }
        var carryTemplate = 0.0
        let withWeight: [StrengthRecommendationSet] = inLast.map { s in
            var template = decimalToDouble(s.weightKg)
            if template <= 0 {
                template = carryTemplate > 0 ? carryTemplate : fallbackW
            } else {
                carryTemplate = template
            }
            var adj = adjustWeight(base: template, avgRpe: avgRpe)
            if let cap = prCap { adj = min(adj, cap) }
            let reps = max(C.minRecommendedReps, min(C.maxRecommendedReps, s.reps ?? C.defaultReps))
            let rpeOut = s.rpe.map { NSDecimalNumber(decimal: $0).doubleValue }
            return StrengthRecommendationSet(
                setNumber: s.setNumber,
                reps: reps,
                weightKg: C.roundToHalf(adj),
                rpe: rpeOut,
                restSec: s.restSec ?? C.defaultRestBetweenSetsSec
            )
        }
        
        return adjustVolumeForRpe(sets: withWeight, avgRpe: avgRpe)
    }
    
    private static func suggestWeight(exerciseId: Int64, flat: [FlatSet], ctx: WorkoutRecommendationContext) -> Double {
        guard let latestWid = latestWorkoutId(forExercise: exerciseId, flat: flat) else {
            return ctx.defaultColdStartWeightKg()
        }
        let slice = flat.filter { $0.exerciseId == exerciseId && $0.workoutId == latestWid && $0.weightKg != nil }
        let weights = slice.compactMap { $0.weightKg }.map { NSDecimalNumber(decimal: $0).doubleValue }
        guard !weights.isEmpty else {
            let any = flat.filter { $0.exerciseId == exerciseId && $0.weightKg != nil }
            let fallback = any.compactMap { $0.weightKg }.map { NSDecimalNumber(decimal: $0).doubleValue }
            return C.roundToHalf(fallback.max() ?? ctx.defaultColdStartWeightKg())
        }
        let base = weights.max() ?? ctx.defaultColdStartWeightKg()
        let rpes = slice.compactMap { $0.rpe }.map { NSDecimalNumber(decimal: $0).doubleValue }
        let avgRpe = rpes.isEmpty ? 8.0 : rpes.reduce(0, +) / Double(rpes.count)
        var adj = adjustWeight(base: base, avgRpe: avgRpe)
        if let pr = ctx.prMaxWeightByExerciseId[exerciseId] {
            adj = min(adj, pr + C.prCapIncrementKg)
        }
        return C.roundToHalf(adj)
    }
    
    private static func adjustWeight(base: Double, avgRpe: Double) -> Double {
        if avgRpe < 8 { return base + C.rpeWeightDeltaKg }
        if avgRpe >= 9 { return max(0, base - C.rpeWeightDeltaKg) }
        return base
    }
    
    private static func roundToHalf(_ x: Double) -> Double {
        C.roundToHalf(x)
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
    
    static func recommendCardio(userId: UUID, source: RecommendationDataSource, networkInspired: Bool = false) async throws -> CardioRecommendation {
        let ctx = await WorkoutRecommendationContext.load(userId: userId, catalog: [], includeNetwork: networkInspired || source == .networkInspired)
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
            .limit(C.lookbackCount)
            .execute()
        let wRows = try decoder.decode([WRow].self, from: wRes.data)
        if wRows.isEmpty {
            if source == .fullCatalog || source == .networkInspired {
                var rec = beginnerCardioRecommendation(
                    activity: .walk,
                    rationale: "You don't have cardio workouts in your history yet. These are easy starter targets (conversation-pace effort)—adjust any field in the form."
                )
                rec = scaledCardio(rec, ctx: ctx)
                return CardioRecommendation(
                    activity: rec.activity,
                    durationSec: rec.durationSec,
                    distanceKm: rec.distanceKm,
                    elevationGainM: rec.elevationGainM,
                    avgHr: rec.avgHr,
                    maxHr: rec.maxHr,
                    inclinePercent: rec.inclinePercent,
                    cadenceRpm: rec.cadenceRpm,
                    wattsAvg: rec.wattsAvg,
                    splitSecPer500m: rec.splitSecPer500m,
                    swimLaps: rec.swimLaps,
                    poolLengthM: rec.poolLengthM,
                    swimStyle: rec.swimStyle,
                    rationale: ctx.appendGoalLine(to: rec.rationale)
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
            case .recentHistory, .hyrox, .hyroxRace, .myRoutines:
                return Array(Set(sessions.map(\.code)))
            case .fullCatalog, .networkInspired:
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
        var statsLoadNote: String?
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
                statsLoadNote = "Some activity stats were unavailable; core duration and distance still apply."
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
        
        var rationale = "Among \(source == .fullCatalog || source == .networkInspired ? "all app activities" : "activities you logged"), this one was least frequent in your last \(C.lookbackCount) cardio workouts."
        if usedCrossActivityFallback {
            rationale += " Values are estimated from your other cardio in this window, since you haven't logged this activity yet."
        }
        if let statsLoadNote { rationale += " \(statsLoadNote)" }
        rationale = ctx.appendGoalLine(to: rationale)
        let scaledDur = Int(Double(medianDur) * ctx.cardioDurationMultiplier())
        return CardioRecommendation(
            activity: activity,
            durationSec: scaledDur,
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
    
    private static func scaledCardio(_ rec: CardioRecommendation, ctx: WorkoutRecommendationContext) -> CardioRecommendation {
        let mult = ctx.cardioDurationMultiplier()
        guard mult != 1.0 else { return rec }
        return CardioRecommendation(
            activity: rec.activity,
            durationSec: Int(Double(rec.durationSec) * mult),
            distanceKm: rec.distanceKm.map { $0 * mult },
            elevationGainM: rec.elevationGainM,
            avgHr: rec.avgHr,
            maxHr: rec.maxHr,
            inclinePercent: rec.inclinePercent,
            cadenceRpm: rec.cadenceRpm,
            wattsAvg: rec.wattsAvg,
            splitSecPer500m: rec.splitSecPer500m,
            swimLaps: rec.swimLaps,
            poolLengthM: rec.poolLengthM,
            swimStyle: rec.swimStyle,
            rationale: rec.rationale
        )
    }
    
    static func recommendSport(userId: UUID, source: RecommendationDataSource, networkInspired: Bool = false) async throws -> SportRecommendation {
        if source == .myRoutines {
            return try await recommendFromSavedHyroxRoutine(userId: userId)
        }
        let ctx = await WorkoutRecommendationContext.load(userId: userId, catalog: [], includeNetwork: networkInspired)
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
            .limit(C.lookbackCount)
            .execute()
        let wRows = try decoder.decode([WRow].self, from: wRes.data)
        if wRows.isEmpty {
            if source == .fullCatalog {
                return .durationOnly(
                    durationMin: 60,
                    rationale: ctx.appendGoalLine(to: "You don't have sport workouts in your history yet. Here's a session length you can use with any sport—adjust as you like.")
                )
            }
            if source == .hyrox {
                return .hyrox(
                    durationMin: 60,
                    exercises: hyroxColdStartExercises(),
                    rationale: "You don’t have sport workouts in your history yet. Here’s a short Hyrox block: easy run, then station, repeated—adjust distances and loads as you like."
                )
            }
            if source == .hyroxRace {
                let ex = HyroxExerciseFormatting.officialRaceHyroxWithRuns(
                    tier: .openMen,
                    runDistanceM: 1_000,
                    stationCount: 5
                )
                return .hyrox(
                    durationMin: 60,
                    exercises: ex,
                    rationale: "No sport history yet. Moderate race-style block (5 stations + runs). Add stations in the form when you’re ready for more volume."
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
        var sessions: [SportRecSession] = []
        for ss in rows {
            guard let sp = ss.sport, !sp.isEmpty else { continue }
            let dm = max(1, ss.duration_sec.map { $0 / 60 } ?? 60)
            sessions.append(SportRecSession(id: ss.id, sport: sp.lowercased(), durationMin: dm))
        }
        if sessions.isEmpty {
            if source == .fullCatalog {
                return .durationOnly(
                    durationMin: 60,
                    rationale: "No sport details in those sessions yet. Suggested duration only—pick any sport in the form."
                )
            }
            if source == .hyrox {
                return .hyrox(
                    durationMin: 60,
                    exercises: hyroxColdStartExercises(),
                    rationale: "No sport details in those sessions yet. Short Hyrox starter you can edit."
                )
            }
            if source == .hyroxRace {
                let ex = HyroxExerciseFormatting.officialRaceHyroxWithRuns(
                    tier: .openMen,
                    runDistanceM: 1_000,
                    stationCount: 5
                )
                return .hyrox(
                    durationMin: 60,
                    exercises: ex,
                    rationale: "No sport details in those sessions. Moderate race-style block (5 stations + runs, Open men loads)."
                )
            }
            throw WorkoutRecommendationError.loadFailed("No sport session rows.")
        }
        
        if source == .hyrox {
            return try await hyroxSportRecommendation(
                sessions: sessions,
                client: client,
                decoder: decoder
            )
        }
        if source == .hyroxRace {
            return try await hyroxRaceFormatRecommendation(
                sessions: sessions,
                client: client,
                decoder: decoder
            )
        }
        
        var counts: [String: Int] = [:]
        for s in sessions { counts[s.sport, default: 0] += 1 }
        
        let candidates: [String] = {
            switch source {
            case .recentHistory, .myRoutines:
                return Array(Set(sessions.map(\.sport)))
            case .fullCatalog, .networkInspired:
                return SportType.allCases.map(\.rawValue)
            case .hyrox, .hyroxRace:
                return []
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
        
        let baseRationale = "Among \(source == .recentHistory ? "sports you logged" : "all app sports"), this one was least frequent in your last \(C.lookbackCount) sessions."
        
        guard raw == SportType.hyrox.rawValue else {
            let rationale = ctx.appendGoalLine(to: baseRationale + " Suggested session length only—choose whichever sport fits in the form.")
            return .durationOnly(durationMin: medianMin, rationale: rationale)
        }
        
        let hyroxSessionIds = sessions.filter { $0.sport == SportType.hyrox.rawValue }.map(\.id)
        var exRows: [HyroxExRow] = []
        if !hyroxSessionIds.isEmpty {
            do {
                let exRes = try await client
                    .from("hyrox_session_exercises")
                    .select("exercise_code, exercise_order, distance_m, reps, weight_kg, duration_sec, height_cm, implement_count, calories_kcal, exercise_display_name")
                    .in("session_id", values: hyroxSessionIds)
                    .execute()
                exRows = try decoder.decode([HyroxExRow].self, from: exRes.data)
            } catch {
                exRows = []
            }
        }
        
        let exercises = buildHyroxExerciseRecommendations(from: exRows)
        var rationale = ctx.appendGoalLine(to: baseRationale)
        if exRows.isEmpty {
            rationale += " No Hyrox stations in your history yet—here's a starter template you can edit."
        } else {
            rationale += " Stations lean on ones you've logged less often, using typical numbers from your Hyrox sessions."
        }
        return .hyrox(durationMin: medianMin, exercises: exercises, rationale: rationale)
    }
    
    private static func recommendFromSavedHyroxRoutine(userId: UUID) async throws -> SportRecommendation {
        let client = SupabaseManager.shared.client
        struct RoutineListRow: Decodable { let id: Int64; let name: String }
        struct HyroxExWire: Decodable {
            let exercise_code: String
            let exercise_order: Int
            let distance_m: Int?
            let reps: Int?
            let weight_kg: Double?
            let duration_sec: Int?
            let height_cm: Int?
            let implement_count: Int?
            let calories_kcal: Double?
            let exercise_display_name: String?
            let notes: String?
        }
        struct RoutineDetail: Decodable {
            let name: String
            let hyrox_routine_exercises: [HyroxExWire]?
        }
        let rRes = try await client
            .from("hyrox_routines")
            .select("id, name")
            .eq("user_id", value: userId.uuidString)
            .order("updated_at", ascending: true)
            .execute()
        struct IdName: Decodable { let id: Int64; let name: String }
        let rows = try JSONDecoder.supabase().decode([IdName].self, from: rRes.data)
        guard let picked = rows.randomElement() else {
            throw WorkoutRecommendationError.loadFailed("Save a Hyrox routine first, or pick another data source.")
        }
        let detailRes = try await client
            .from("hyrox_routines")
            .select("name, hyrox_routine_exercises(exercise_code, exercise_order, distance_m, reps, weight_kg, duration_sec, height_cm, implement_count, calories_kcal, exercise_display_name, notes)")
            .eq("id", value: Int(picked.id))
            .single()
            .execute()
        let detail = try JSONDecoder.supabase().decode(RoutineDetail.self, from: detailRes.data)
        let ordered = (detail.hyrox_routine_exercises ?? []).sorted { $0.exercise_order < $1.exercise_order }
        let exercises = ordered.map { ex in
            HyroxExerciseRecommendation(
                exerciseCode: ex.exercise_code,
                customDisplayName: ex.exercise_display_name ?? "",
                exerciseOrder: ex.exercise_order,
                distanceM: ex.distance_m,
                reps: ex.reps,
                weightKg: ex.weight_kg,
                durationSec: ex.duration_sec,
                heightCm: ex.height_cm,
                implementCount: ex.implement_count,
                caloriesKcal: ex.calories_kcal.map { Int($0.rounded()) },
                notes: ex.notes
            )
        }.map { HyroxExerciseFormatting.sanitizeHyroxExerciseRecommendation($0) }
        let durationMin = max(35, min(120, exercises.count * 8))
        return .hyrox(
            durationMin: durationMin,
            exercises: exercises.isEmpty ? hyroxColdStartExercises() : exercises,
            rationale: "Loaded from your Hyrox routine \"\(detail.name)\"."
        )
    }
    
    private static func hyroxSportRecommendation(
        sessions: [SportRecSession],
        client: SupabaseClient,
        decoder: JSONDecoder
    ) async throws -> SportRecommendation {
        let hyroxSessions = sessions.filter { $0.sport == SportType.hyrox.rawValue }
        let allMins = sessions.map(\.durationMin)
        let hyroxMins = hyroxSessions.map(\.durationMin)
        let medianMin = medianSportMinutes(hyroxMins.isEmpty ? allMins : hyroxMins)
        
        let hyroxSessionIds = hyroxSessions.map(\.id)
        var exRows: [HyroxExRow] = []
        if !hyroxSessionIds.isEmpty {
            do {
                let exRes = try await client
                    .from("hyrox_session_exercises")
                    .select("exercise_code, exercise_order, distance_m, reps, weight_kg, duration_sec, height_cm, implement_count, calories_kcal, exercise_display_name")
                    .in("session_id", values: hyroxSessionIds)
                    .execute()
                exRows = try decoder.decode([HyroxExRow].self, from: exRes.data)
            } catch {
                exRows = []
            }
        }
        
        let exercises = buildHyroxExerciseRecommendations(from: exRows)
        let rationale: String = {
            if hyroxSessions.isEmpty {
                return "No Hyrox in your last \(C.lookbackCount) sport sessions—duration reflects your other sports. Here's a short race-style starter (runs + stations) you can edit."
            }
            if exRows.isEmpty {
                return "Hyrox duration from your recent Hyrox sessions; station list is a starter template until you log station details."
            }
            return "Hyrox session built from stations you’ve used less often lately, using typical distances and loads from your logs."
        }()
        return .hyrox(durationMin: medianMin, exercises: exercises, rationale: rationale)
    }
    
    private static func hyroxRaceFormatRecommendation(
        sessions: [SportRecSession],
        client: SupabaseClient,
        decoder: JSONDecoder
    ) async throws -> SportRecommendation {
        let hyroxSessions = sessions.filter { $0.sport == SportType.hyrox.rawValue }
        let allMins = sessions.map(\.durationMin)
        let hyroxMins = hyroxSessions.map(\.durationMin)
        let rawDurationMedian = medianSportMinutes(hyroxMins.isEmpty ? allMins : hyroxMins)
        
        let hyroxSessionIds = hyroxSessions.map(\.id)
        var exRows: [HyroxExRow] = []
        if !hyroxSessionIds.isEmpty {
            do {
                let exRes = try await client
                    .from("hyrox_session_exercises")
                    .select("exercise_code, exercise_order, distance_m, reps, weight_kg, duration_sec, height_cm, implement_count, calories_kcal, exercise_display_name")
                    .in("session_id", values: hyroxSessionIds)
                    .execute()
                exRows = try decoder.decode([HyroxExRow].self, from: exRes.data)
            } catch {
                exRows = []
            }
        }
        
        let tier = inferHyroxWeightTier(from: exRows)
        let runM = medianHyroxRunDistanceM(from: exRows)
        let inferringDurationFromOtherSports = hyroxMins.isEmpty && !allMins.isEmpty
        let fromDuration = raceFormatStationCount(forSessionMinutes: rawDurationMedian)
        let experienceCap = raceFormatHyroxExperienceCap(
            hyroxSessionsInWindow: hyroxSessions.count,
            inferringDurationFromOtherSports: inferringDurationFromOtherSports
        )
        let stationCount = min(fromDuration, experienceCap)
        let exercises = HyroxExerciseFormatting.officialRaceHyroxWithRuns(
            tier: tier,
            runDistanceM: runM,
            stationCount: stationCount
        )
        let durationSuggested = max(
            min(rawDurationMedian, stationCount * 15),
            stationCount * 9,
            35
        )
        
        let tierLabel: String = {
            switch tier {
            case .openWomen: return "Open women–style loads"
            case .openMen: return "Open men–style loads"
            case .proMen: return "Pro men–style loads"
            }
        }()
        
        let rationale: String = {
            let runHint = "Each station is preceded by an easy run (\(runM) m—taken from your logs when we can, else 1 km)."
            var countHint = "\(stationCount) official stations in race order"
            if stationCount < 8 {
                countHint += " (we keep volume conservative—add stations in the form for a full race)."
            } else {
                countHint += "."
            }
            if stationCount == experienceCap, experienceCap < fromDuration {
                countHint += " Fewer blocks because you don’t log many Hyrox sessions in this window yet."
            }
            if inferringDurationFromOtherSports, stationCount < fromDuration {
                countHint += " Session length came from other sports, so we didn’t scale all the way to a full Hyrox race."
            }
            if hyroxSessions.isEmpty {
                return "Race-style session: run, station, run, station… \(countHint) \(tierLabel). \(runHint)"
            }
            if exRows.isEmpty {
                return "Race-style flow with runs between stations. \(countHint) \(tierLabel)—verify sled, sandbag, and wall ball weights."
            }
            return "Race-style flow: \(countHint) \(tierLabel). \(runHint)"
        }()
        
        return .hyrox(durationMin: durationSuggested, exercises: exercises, rationale: rationale)
    }
    
    private static func medianHyroxRunDistanceM(from rows: [HyroxExRow]) -> Int {
        let runs = rows.filter { $0.exercise_code.lowercased() == HyroxExerciseCode.run.rawValue }
        let dists = runs.compactMap(\.distance_m).filter { $0 >= 100 }
        guard let m = medianIntOpt(dists), m >= 400 else { return 1_000 }
        return min(m, 5_000)
    }
    
    private static func raceFormatStationCount(forSessionMinutes medianMin: Int) -> Int {
        switch medianMin {
        case ..<32: return 3
        case 32..<48: return 4
        case 48..<62: return 5
        case 62..<80: return 6
        case 80..<100: return 7
        default: return 8
        }
    }
    
    private static func raceFormatHyroxExperienceCap(
        hyroxSessionsInWindow: Int,
        inferringDurationFromOtherSports: Bool
    ) -> Int {
        if inferringDurationFromOtherSports {
            return min(6, max(4, 3 + hyroxSessionsInWindow))
        }
        switch hyroxSessionsInWindow {
        case 0: return 4
        case 1: return 4
        case 2: return 5
        case 3: return 6
        case 4: return 7
        default: return 8
        }
    }
    
    private static func inferHyroxWeightTier(from rows: [HyroxExRow]) -> HyroxWeightTier {
        func medianWeight(code: String) -> Double? {
            let g = rows.filter { $0.exercise_code.lowercased() == code.lowercased() }
            return medianDoubleOpt(g.compactMap { $0.weight_kg.map { NSDecimalNumber(decimal: $0).doubleValue } })
        }
        return HyroxExerciseFormatting.inferHyroxWeightTier(
            sandbagMedian: medianWeight(code: HyroxExerciseCode.sandbagLunges.rawValue),
            wallBallMedian: medianWeight(code: HyroxExerciseCode.wallBall.rawValue),
            sledPushMedian: medianWeight(code: HyroxExerciseCode.sledPush.rawValue)
        )
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
                caloriesKcal: medianIntOpt(group.compactMap { $0.calories_kcal.map { Int(NSDecimalNumber(decimal: $0).doubleValue.rounded()) } }),
                notes: nil
            )
        }
        .map { HyroxExerciseFormatting.sanitizeHyroxExerciseRecommendation($0) }
    }
    
    private static func hyroxColdStartExercises() -> [HyroxExerciseRecommendation] {
        HyroxExerciseFormatting.officialRaceHyroxWithRuns(
            tier: .openMen,
            runDistanceM: 1_000,
            stationCount: 4
        )
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
