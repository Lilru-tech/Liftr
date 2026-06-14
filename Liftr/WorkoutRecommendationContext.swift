import Foundation
import Supabase

private struct StrengthPRRow: Decodable {
    let kind: String
    let label: String
    let metric: String
    let value: Double
}

struct GoalRecommendationNudge: Equatable {
    let workoutsRemaining: Int?
    let caloriesRemaining: Double?
    let summaryLine: String?
}

struct MuscleFreshnessEntry: Identifiable, Equatable {
    enum Status: String, Equatable {
        case fresh
        case recent
        case trainedRecently
    }
    let id: String
    let muscle: String
    let status: Status
}

struct StrengthRecommendationOutput: Equatable {
    let exercises: [StrengthRecommendationExercise]
    let sessionRationale: String?
    let muscleFreshness: [MuscleFreshnessEntry]
    let routineName: String?
}

struct WorkoutRecommendationContext: Equatable {
    var profileWeightKg: Double?
    var profileSex: String?
    var profileAgeYears: Int?
    var favoriteExerciseIds: Set<Int64> = []
    var prMaxWeightByExerciseId: [Int64: Double] = [:]
    var goalNudge: GoalRecommendationNudge?
    var publishedStrengthCount: Int = 0
    var networkExerciseFrequency: [Int64: Int] = [:]
    var partialDataNote: String?

    var isBeginnerLifter: Bool { publishedStrengthCount < WorkoutRecommendationConstants.beginnerStrengthSessionThreshold }

    static func load(
        userId: UUID,
        catalog: [Exercise],
        includeNetwork: Bool
    ) async -> WorkoutRecommendationContext {
        let client = SupabaseManager.shared.client
        let decoder = JSONDecoder.supabase()
        var ctx = WorkoutRecommendationContext()

        struct ProfileRow: Decodable {
            let weight_kg: Double?
            let sex: String?
            let date_of_birth: String?
        }
        if let pRes = try? await client
            .from("profiles")
            .select("weight_kg, sex, date_of_birth")
            .eq("user_id", value: userId.uuidString)
            .single()
            .execute(),
           let profile = try? decoder.decode(ProfileRow.self, from: pRes.data) {
            ctx.profileWeightKg = profile.weight_kg
            ctx.profileSex = profile.sex
            if let dob = profile.date_of_birth {
                let df = DateFormatter()
                df.locale = Locale(identifier: "en_US_POSIX")
                df.dateFormat = "yyyy-MM-dd"
                if let birth = df.date(from: dob) {
                    ctx.profileAgeYears = Calendar.current.dateComponents([.year], from: birth, to: Date()).year
                }
            }
        }

        struct FavRow: Decodable { let exercise_id: Int64 }
        if let fRes = try? await client.from("user_favorite_exercises").select("exercise_id").eq("user_id", value: userId.uuidString).execute(),
           let rows = try? decoder.decode([FavRow].self, from: fRes.data) {
            ctx.favoriteExerciseIds = Set(rows.map(\.exercise_id))
        }

        if let prRes = try? await client.rpc("get_user_prs", params: ["p_user_id": userId.uuidString, "p_kind": "strength"]).execute(),
           let prs = try? decoder.decode([StrengthPRRow].self, from: prRes.data) {
            ctx.prMaxWeightByExerciseId = mapStrengthPrsToExerciseIds(prs: prs, catalog: catalog)
        }

        struct CountRow: Decodable { let id: Int }
        if let cRes = try? await client
            .from("workouts")
            .select("id")
            .eq("user_id", value: userId.uuidString)
            .eq("kind", value: "strength")
            .eq("state", value: "published")
            .execute(),
           let counts = try? decoder.decode([CountRow].self, from: cRes.data) {
            ctx.publishedStrengthCount = counts.count
        }

        ctx.goalNudge = await loadGoalNudge(userId: userId, client: client, decoder: decoder)

        if includeNetwork {
            let (freq, note) = await loadNetworkExerciseFrequency(userId: userId, client: client, decoder: decoder)
            ctx.networkExerciseFrequency = freq
            if let note { ctx.partialDataNote = note }
        }

        return ctx
    }

    func defaultColdStartWeightKg() -> Double {
        WorkoutRecommendationConstants.defaultColdStartWeightKg(
            profileWeightKg: profileWeightKg,
            isBeginner: isBeginnerLifter
        )
    }

    func appendGoalLine(to rationale: String) -> String {
        guard let line = goalNudge?.summaryLine, !line.isEmpty else { return rationale }
        if rationale.isEmpty { return line }
        return rationale + " " + line
    }

    func cardioDurationMultiplier() -> Double {
        guard let rem = goalNudge?.caloriesRemaining, rem > 0 else { return 1.0 }
        if rem > 500 { return 1.15 }
        if rem > 200 { return 1.08 }
        return 1.0
    }

    private static func mapStrengthPrsToExerciseIds(prs: [StrengthPRRow], catalog: [Exercise]) -> [Int64: Double] {
        var out: [Int64: Double] = [:]
        let weightMetrics = Set(["weight_kg", "max_weight_kg", "weight"])
        for pr in prs where pr.kind.lowercased() == "strength" && weightMetrics.contains(pr.metric.lowercased()) {
            let normLabel = pr.label.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).lowercased()
            guard !normLabel.isEmpty else { continue }
            for ex in catalog {
                let names = ([ex.name] + [ex.name_en, ex.name_es].compactMap { $0 })
                    .map { $0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).lowercased() }
                if names.contains(normLabel) {
                    out[ex.id] = max(out[ex.id] ?? 0, pr.value)
                }
            }
        }
        return out
    }

    private static func loadGoalNudge(userId: UUID, client: SupabaseClient, decoder: JSONDecoder) async -> GoalRecommendationNudge? {
        let weekStr = GoalsManager.dateOnlyString(GoalsManager.currentWeekStart())
        struct GoalRow: Decodable {
            let id: Int64
            let metric: String
            let target_value: Double
        }
        struct ResultRow: Decodable {
            let goal_id: Int64
            let achieved_value: Double?
            let is_completed: Bool?
        }
        guard let gRes = try? await client
            .from("weekly_goals")
            .select("id, metric, target_value")
            .eq("user_id", value: userId.uuidString)
            .eq("week_start", value: weekStr)
            .execute(),
              let goals = try? decoder.decode([GoalRow].self, from: gRes.data),
              !goals.isEmpty else { return nil }

        let ids = goals.map { String($0.id) }
        var resultsByGoal: [Int64: ResultRow] = [:]
        if let rRes = try? await client
            .from("weekly_goal_results")
            .select("goal_id, achieved_value, is_completed")
            .in("goal_id", values: ids)
            .eq("week_start", value: weekStr)
            .execute(),
           let results = try? decoder.decode([ResultRow].self, from: rRes.data) {
            for r in results { resultsByGoal[r.goal_id] = r }
        }

        var workoutsRemaining: Int?
        var caloriesRemaining: Double?
        var lines: [String] = []

        for g in goals {
            let achieved = resultsByGoal[g.id]?.achieved_value ?? 0
            let done = resultsByGoal[g.id]?.is_completed ?? false
            if done { continue }
            switch g.metric.lowercased() {
            case "workouts":
                let rem = max(0, Int(g.target_value.rounded()) - Int(achieved.rounded()))
                if rem > 0 && rem <= 2 {
                    workoutsRemaining = rem
                    lines.append(rem == 1 ? "You're 1 workout away from this week's workout goal." : "You're \(rem) workouts away from this week's workout goal.")
                }
            case "calories":
                let rem = max(0, g.target_value - achieved)
                if rem > 150 {
                    caloriesRemaining = rem
                    lines.append("Calorie goal still open this week—a slightly longer session can help.")
                }
            default:
                break
            }
        }

        guard !lines.isEmpty else { return nil }
        return GoalRecommendationNudge(
            workoutsRemaining: workoutsRemaining,
            caloriesRemaining: caloriesRemaining,
            summaryLine: lines.joined(separator: " ")
        )
    }

    private static func loadNetworkExerciseFrequency(
        userId: UUID,
        client: SupabaseClient,
        decoder: JSONDecoder
    ) async -> ([Int64: Int], String?) {
        struct FollowRow: Decodable { let followee_id: UUID }
        guard let fRes = try? await client
            .from("follows")
            .select("followee_id")
            .eq("follower_id", value: userId.uuidString)
            .limit(50)
            .execute(),
              let follows = try? decoder.decode([FollowRow].self, from: fRes.data),
              !follows.isEmpty else { return ([:], nil) }

        let followeeIds = follows.map { $0.followee_id.uuidString }
        let since = Calendar.current.date(byAdding: .day, value: -WorkoutRecommendationConstants.networkLookbackDays, to: Date()) ?? Date()
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]

        struct WRow: Decodable { let id: Int }
        guard let wRes = try? await client
            .from("workouts")
            .select("id")
            .in("user_id", values: followeeIds)
            .eq("kind", value: "strength")
            .eq("state", value: "published")
            .gte("started_at", value: iso.string(from: since))
            .limit(100)
            .execute(),
              let workouts = try? decoder.decode([WRow].self, from: wRes.data),
              !workouts.isEmpty else {
            return ([:], "Your network hasn't logged strength workouts recently—we used your own history.")
        }

        let wids = workouts.map { String($0.id) }
        struct ExRow: Decodable { let exercise_id: Int64 }
        guard let exRes = try? await client
            .from("workout_exercises")
            .select("exercise_id")
            .in("workout_id", values: wids)
            .execute(),
              let exRows = try? decoder.decode([ExRow].self, from: exRes.data) else {
            return ([:], "Could not load network exercise trends.")
        }

        var freq: [Int64: Int] = [:]
        for row in exRows { freq[row.exercise_id, default: 0] += 1 }
        return (freq, nil)
    }
}

enum WorkoutRecommendationConstants {
    static let lookbackCount = 10
    static let targetExerciseCount = 5
    static let defaultSetsPerExercise = 3
    static let defaultReps = 12
    static let maxRecommendedSets = 5
    static let maxInferredSetsFromSetNumber = 8
    static let maxRecommendedReps = 22
    static let minRecommendedReps = 6
    static let highVolumeRepsThreshold = 17
    static let highVolumeSetsThreshold = 5
    static let defaultRestBetweenSetsSec = 90
    static let rpeWeightDeltaKg = 2.5
    static let recoveryDeprioritizeHours = 48
    static let favoriteSelectionBoost = 2
    static let prChaseProximityRatio = 0.05
    static let prCapIncrementKg = 2.5
    static let beginnerStrengthSessionThreshold = 5
    static let networkLookbackDays = 7

    static func defaultColdStartWeightKg(profileWeightKg: Double?, isBeginner: Bool) -> Double {
        if let w = profileWeightKg, w > 0 {
            let factor = isBeginner ? 0.12 : 0.18
            let raw = w * factor
            return roundToHalf(min(60, max(5, raw)))
        }
        return isBeginner ? 15 : 20
    }

    static func roundToHalf(_ x: Double) -> Double {
        (x * 2).rounded() / 2
    }

    static func biasedShuffle<T>(_ items: [T], isBoosted: (T) -> Bool) -> [T] {
        var boosted: [T] = []
        var rest: [T] = []
        for item in items {
            if isBoosted(item) {
                for _ in 0..<favoriteSelectionBoost { boosted.append(item) }
            } else {
                rest.append(item)
            }
        }
        return (boosted + rest).shuffled()
    }
}

func strengthRecommendationsFromRoutineDetail(
    _ detail: StrengthTemplateDetailWire,
    catalog: [Exercise],
    exerciseLanguage: ExerciseLanguage
) -> [StrengthRecommendationExercise] {
    let muscleById = Dictionary(uniqueKeysWithValues: catalog.map { ($0.id, $0.muscle_primary) })
    let exs = (detail.strength_routine_exercises ?? []).sorted { $0.order_index < $1.order_index }
    return exs.compactMap { ex -> StrengthRecommendationExercise? in
        let setsSorted = (ex.strength_routine_sets ?? []).sorted { $0.set_number < $1.set_number }
        let setsOut: [StrengthRecommendationSet] = setsSorted.enumerated().map { idx, s in
            StrengthRecommendationSet(
                setNumber: idx + 1,
                reps: max(WorkoutRecommendationConstants.minRecommendedReps, s.reps ?? WorkoutRecommendationConstants.defaultReps),
                weightKg: WorkoutRecommendationConstants.roundToHalf(s.weight_kg ?? 0),
                rpe: s.rpe,
                restSec: s.rest_sec ?? WorkoutRecommendationConstants.defaultRestBetweenSetsSec
            )
        }
        let fallbackSets = setsOut.isEmpty
            ? (1...WorkoutRecommendationConstants.defaultSetsPerExercise).map { sn in
                StrengthRecommendationSet(
                    setNumber: sn,
                    reps: WorkoutRecommendationConstants.defaultReps,
                    weightKg: 20,
                    rpe: 8,
                    restSec: WorkoutRecommendationConstants.defaultRestBetweenSetsSec
                )
            }
            : setsOut
        let displayName: String = {
            if let cn = ex.custom_name?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines), !cn.isEmpty { return cn }
            if let cat = catalog.first(where: { $0.id == ex.exercise_id }) {
                return cat.localizedName(for: exerciseLanguage)
            }
            return "Exercise \(ex.exercise_id)"
        }()
        return StrengthRecommendationExercise(
            exerciseId: ex.exercise_id,
            displayName: displayName,
            musclePrimary: muscleById[ex.exercise_id].flatMap { $0 },
            sets: fallbackSets
        )
    }
}
