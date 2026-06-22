import Foundation
import Supabase

enum ActiveWorkoutSessionCheckpoint {
    static let maxAge: TimeInterval = 7 * 24 * 60 * 60
    private static let storageKey = "liftr.activeWorkoutCheckpoint.v1"

    enum Kind: String, Codable {
        case strength
        case cardio
        case sport
    }

    struct PerformedSetSnapshot: Codable, Equatable {
        let reps: Int?
        let weight_kg: Double?
        let rpe: Double?
        let rest_sec: Int?
        let configId: Int
        let segmentsInRow: Int
        let weight_segments: [StrengthWeightSegWire]?
    }

    struct SetRowSnapshot: Codable, Equatable {
        let id: Int
        let workout_exercise_id: Int
        let set_number: Int
        let order_index: Int?
        let reps: Int?
        let weight_kg: Double?
        let rpe: Double?
        let rest_sec: Int?
        let weight_segments: [StrengthWeightSegWire]?
    }

    struct StrengthPayload: Codable, Equatable {
        let currentExerciseIndex: Int
        let currentSetIndex: Int
        let currentSetIndexByExercise: [Int: Int]
        let performedSetsByExercise: [Int: [PerformedSetSnapshot]]
        let setsByExercise: [Int: [SetRowSnapshot]]
        let restEndEpochByExercise: [Int: Double]
        let isResting: Bool
        let guestWorkoutId: Int?
        let guest2WorkoutId: Int?
        let guestPerformedSetsByExercise: [Int: [PerformedSetSnapshot]]
        let guest2PerformedSetsByExercise: [Int: [PerformedSetSnapshot]]
        let guestCurrentSetIndexByExercise: [Int: Int]
        let guest2CurrentSetIndexByExercise: [Int: Int]
        let showCountdown: Bool
    }

    struct CardioPayload: Codable, Equatable {
        let elapsedSec: Int
        let isSessionRunning: Bool
        let distanceText: String
        let routePoints: [[Double]]
        let kmSplitCumulativeSec: [Int]
        let timerMode: String
        let remainingSec: Int
        let initialTargetSec: Int
        let gpsProfileRaw: String
        let showCountdown: Bool
    }

    struct SportHyroxExerciseSnapshot: Codable, Equatable {
        let id: Int
        let exercise_code: String
        let exercise_order: Int
        let zone_order: Int?
        let distance_m: Int?
        let reps: Int?
        let weight_kg: Double?
        let duration_sec: Int?
        let height_cm: Int?
        let implement_count: Int?
        let calories_kcal: Double?
        let notes: String?
        let custom_display_name: String?
    }

    struct SportPayload: Codable, Equatable {
        let elapsedSec: Int
        let isSessionRunning: Bool
        let remainingSec: Int
        let initialTargetSec: Int
        let timerMode: String
        let showCountdown: Bool
        let hyroxExerciseIndex: Int
        let completedHyroxExerciseIds: [Int]
        let hyroxExercises: [SportHyroxExerciseSnapshot]
        let scoreForText: String
        let scoreAgainstText: String
        let matchResultRaw: String
        let matchScoreText: String
        let locationText: String
        let sessionNotesText: String
    }

    struct Entry: Codable, Equatable, Identifiable {
        var id: Int { workoutId }
        let workoutId: Int
        let kind: Kind
        let savedAt: Date
        let sessionStartedAt: Date?
        let accumulatedPausedSec: Int
        let isSessionPaused: Bool
        let pauseBeganAt: Date?
        let strength: StrengthPayload?
        let cardio: CardioPayload?
        let sport: SportPayload?

        func summaryLine() -> String {
            switch kind {
            case .strength:
                let sets = strength?.performedSetsByExercise.values.reduce(0) { $0 + $1.count } ?? 0
                return String(localized: "\(sets) sets completed")
            case .cardio:
                let min = (cardio?.elapsedSec ?? 0) / 60
                let dist = cardio?.distanceText.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !dist.isEmpty, dist != "0" {
                    return String(localized: "\(min) min · \(dist) km")
                }
                return String(localized: "\(min) min elapsed")
            case .sport:
                let min = (sport?.elapsedSec ?? 0) / 60
                if let hyrox = sport, !hyrox.hyroxExercises.isEmpty {
                    return String(localized: "\(min) min · \(hyrox.completedHyroxExerciseIds.count) stations done")
                }
                return String(localized: "\(min) min elapsed")
            }
        }

        func kindLabel() -> String {
            switch kind {
            case .strength: return String(localized: "strength")
            case .cardio: return String(localized: "cardio")
            case .sport: return String(localized: "sport")
            }
        }
    }

    static func load() -> Entry? {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(Entry.self, from: data)
    }

    static func store(_ entry: Entry) {
        if let data = try? JSONEncoder().encode(entry) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    static func clearIfWorkout(_ workoutId: Int) {
        guard load()?.workoutId == workoutId else { return }
        clear()
    }

    static func isStale(_ entry: Entry, now: Date = Date()) -> Bool {
        now.timeIntervalSince(entry.savedAt) > maxAge
    }

    private struct WorkoutOngoingRow: Decodable {
        let id: Int
        let user_id: UUID
        let ended_at: Date?
        let kind: String
    }

    static func findRecoverable(client: SupabaseClient = SupabaseManager.shared.client) async -> Entry? {
        guard let entry = load() else { return nil }
        if isStale(entry) {
            clear()
            return nil
        }
        do {
            let row: WorkoutOngoingRow = try await client
                .from("workouts")
                .select("id, user_id, ended_at, kind")
                .eq("id", value: entry.workoutId)
                .single()
                .execute()
                .value
            if row.ended_at != nil {
                clear()
                return nil
            }
            let uid = try await client.auth.session.user.id
            if row.user_id != uid {
                clear()
                return nil
            }
            return entry
        } catch {
            return entry
        }
    }
}

enum ActiveWorkoutRecoveryFinish {
    @MainActor
    static func finishNow(entry: ActiveWorkoutSessionCheckpoint.Entry) async -> String? {
        switch entry.kind {
        case .strength:
            return await finishStrength(entry)
        case .cardio:
            return await finishCardio(entry)
        case .sport:
            return await finishSport(entry)
        }
    }

    private static func finishStrength(_ entry: ActiveWorkoutSessionCheckpoint.Entry) async -> String? {
        guard let strength = entry.strength else { return String(localized: "Missing workout data") }
        let client = SupabaseManager.shared.client
        struct WeRow: Decodable {
            let id: Int
            let order_index: Int
        }
        let rows: [WeRow]
        do {
            rows = try await client
                .from("workout_exercises")
                .select("id, order_index")
                .eq("workout_id", value: entry.workoutId)
                .order("order_index")
                .execute()
                .value
        } catch {
            return error.localizedDescription
        }
        let performedMap = strength.performedSetsByExercise.mapValues { snaps in
            snaps.map {
                StrengthWorkoutFinishCollapse.Line(
                    configId: $0.configId,
                    segmentsInRow: $0.segmentsInRow,
                    reps: $0.reps,
                    weightKg: $0.weight_kg.map { Decimal($0) },
                    rpe: $0.rpe.map { Decimal($0) },
                    restSec: $0.rest_sec,
                    weightSegments: $0.weight_segments
                )
            }
        }
        let hostExercises = StrengthWorkoutFinishCollapse.buildExerciseSaveInputs(
            exerciseIds: rows.map(\.id),
            performedByExercise: performedMap
        )
        var linked: [StrengthWorkoutFinishLinkedInput] = []
        if let gid = strength.guestWorkoutId {
            let guestRows: [WeRow] = (try? await client
                .from("workout_exercises")
                .select("id, order_index")
                .eq("workout_id", value: gid)
                .order("order_index")
                .execute()
                .value) ?? []
            let guestPerformed = strength.guestPerformedSetsByExercise.mapValues { snaps in
                snaps.map {
                    StrengthWorkoutFinishCollapse.Line(
                        configId: $0.configId,
                        segmentsInRow: $0.segmentsInRow,
                        reps: $0.reps,
                        weightKg: $0.weight_kg.map { Decimal($0) },
                        rpe: $0.rpe.map { Decimal($0) },
                        restSec: $0.rest_sec,
                        weightSegments: $0.weight_segments
                    )
                }
            }
            linked.append(
                StrengthWorkoutFinishLinkedInput(
                    workout_id: gid,
                    exercises: StrengthWorkoutFinishCollapse.buildExerciseSaveInputs(
                        exerciseIds: guestRows.map(\.id),
                        performedByExercise: guestPerformed
                    )
                )
            )
        }
        if let g2id = strength.guest2WorkoutId {
            let guest2Rows: [WeRow] = (try? await client
                .from("workout_exercises")
                .select("id, order_index")
                .eq("workout_id", value: g2id)
                .order("order_index")
                .execute()
                .value) ?? []
            let guest2Performed = strength.guest2PerformedSetsByExercise.mapValues { snaps in
                snaps.map {
                    StrengthWorkoutFinishCollapse.Line(
                        configId: $0.configId,
                        segmentsInRow: $0.segmentsInRow,
                        reps: $0.reps,
                        weightKg: $0.weight_kg.map { Decimal($0) },
                        rpe: $0.rpe.map { Decimal($0) },
                        restSec: $0.rest_sec,
                        weightSegments: $0.weight_segments
                    )
                }
            }
            linked.append(
                StrengthWorkoutFinishLinkedInput(
                    workout_id: g2id,
                    exercises: StrengthWorkoutFinishCollapse.buildExerciseSaveInputs(
                        exerciseIds: guest2Rows.map(\.id),
                        performedByExercise: guest2Performed
                    )
                )
            )
        }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let endedAtIso = iso.string(from: Date())
        var pausedSec = entry.accumulatedPausedSec
        if entry.isSessionPaused, let began = entry.pauseBeganAt {
            pausedSec += max(0, Int(Date().timeIntervalSince(began)))
        }
        do {
            let results = try await StrengthWorkoutSaveRPC.finishStrengthWorkoutV1(
                client: client,
                workoutId: entry.workoutId,
                endedAt: endedAtIso,
                pausedSec: pausedSec,
                exercises: hostExercises,
                linked: linked
            )
            for result in results {
                NotificationCenter.default.post(name: .workoutDidChange, object: result.workout_id)
            }
            ActiveWorkoutSessionCheckpoint.clear()
            return nil
        } catch {
            if WorkoutStartSync.isRetriable(error) {
                WorkoutFinishSync.enqueue(
                    workoutId: entry.workoutId,
                    endedAtIso: endedAtIso,
                    pausedSec: pausedSec,
                    exercises: hostExercises,
                    linked: linked
                )
                ActiveWorkoutSessionCheckpoint.clear()
                return nil
            }
            return error.localizedDescription
        }
    }

    private static func finishCardio(_ entry: ActiveWorkoutSessionCheckpoint.Entry) async -> String? {
        guard let cardio = entry.cardio else { return String(localized: "Missing workout data") }
        let client = SupabaseManager.shared.client
        struct CardioRow: Decodable { let id: Int }
        struct WorkoutStateRow: Decodable { let state: String? }
        do {
            let cardioRow: CardioRow = try await client
                .from("cardio_sessions")
                .select("id")
                .eq("workout_id", value: entry.workoutId)
                .single()
                .execute()
                .value
            let distKm = Double(cardio.distanceText.replacingOccurrences(of: ",", with: ".")) ?? 0
            let routeGeo: String? = {
                let pts = cardio.routePoints
                guard pts.count >= 2 else { return nil }
                let coords = pts.map { "[\($0[1]),\($0[0])]" }.joined(separator: ",")
                return "{\"type\":\"LineString\",\"coordinates\":[\(coords)]}"
            }()
            struct CardioPatch: Encodable {
                let duration_sec: Int
                let distance_km: Double?
                let route_geojson: String?
            }
            _ = try await client
                .from("cardio_sessions")
                .update(CardioPatch(
                    duration_sec: cardio.elapsedSec,
                    distance_km: distKm > 0 ? distKm : nil,
                    route_geojson: routeGeo
                ))
                .eq("id", value: cardioRow.id)
                .execute()
            let stateRow: WorkoutStateRow? = try? await client
                .from("workouts")
                .select("state")
                .eq("id", value: entry.workoutId)
                .single()
                .execute()
                .value
            struct WorkoutFinish: Encodable {
                let ended_at: Date
                let state: String?
            }
            _ = try await client
                .from("workouts")
                .update(WorkoutFinish(
                    ended_at: Date(),
                    state: stateRow?.state == "planned" ? "published" : nil
                ))
                .eq("id", value: entry.workoutId)
                .execute()
            NotificationCenter.default.post(name: .workoutDidChange, object: entry.workoutId)
            ActiveWorkoutSessionCheckpoint.clear()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private static func finishSport(_ entry: ActiveWorkoutSessionCheckpoint.Entry) async -> String? {
        guard let sport = entry.sport else { return String(localized: "Missing workout data") }
        let client = SupabaseManager.shared.client
        struct SportRow: Decodable { let id: Int }
        struct WorkoutStateRow: Decodable { let state: String? }
        do {
            let sportRow: SportRow = try await client
                .from("sport_sessions")
                .select("id")
                .eq("workout_id", value: entry.workoutId)
                .single()
                .execute()
                .value
            struct SportPatch: Encodable {
                let duration_sec: Int
                let score_for: Int?
                let score_against: Int?
                let match_result: String?
                let match_score_text: String?
                let location: String?
                let notes: String?
            }
            let scoreFor = Int(sport.scoreForText.trimmingCharacters(in: .whitespacesAndNewlines))
            let scoreAgainst = Int(sport.scoreAgainstText.trimmingCharacters(in: .whitespacesAndNewlines))
            _ = try await client
                .from("sport_sessions")
                .update(SportPatch(
                    duration_sec: sport.elapsedSec,
                    score_for: scoreFor,
                    score_against: scoreAgainst,
                    match_result: sport.matchResultRaw.nilIfEmpty,
                    match_score_text: sport.matchScoreText.nilIfEmpty,
                    location: sport.locationText.nilIfEmpty,
                    notes: sport.sessionNotesText.nilIfEmpty
                ))
                .eq("id", value: sportRow.id)
                .execute()
            let stateRow: WorkoutStateRow? = try? await client
                .from("workouts")
                .select("state")
                .eq("id", value: entry.workoutId)
                .single()
                .execute()
                .value
            struct WorkoutFinish: Encodable {
                let ended_at: Date
                let state: String?
            }
            _ = try await client
                .from("workouts")
                .update(WorkoutFinish(
                    ended_at: Date(),
                    state: stateRow?.state == "planned" ? "published" : nil
                ))
                .eq("id", value: entry.workoutId)
                .execute()
            NotificationCenter.default.post(name: .workoutDidChange, object: entry.workoutId)
            ActiveWorkoutSessionCheckpoint.clear()
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
