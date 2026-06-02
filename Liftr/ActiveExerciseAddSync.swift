import Foundation
import Supabase

enum ActiveExerciseAddSyncStatus: Equatable {
    case idle
    case pending
    case syncing
    case synced
    case willRetry
}

extension Notification.Name {
    static let activeExerciseAddDidSync = Notification.Name("activeExerciseAddDidSync")
    static let activeExerciseAddSyncStatusChanged = Notification.Name("activeExerciseAddSyncStatusChanged")
}

enum ActiveExerciseAddSync {
    struct PendingSet: Codable, Equatable {
        let reps: Int?
        let weightKg: Double?
        let rpe: Double?
        let restSec: Int?
        let weightSegments: [StrengthWeightSegWire]?
    }

    struct PendingExerciseAdd: Codable, Equatable {
        let localExerciseId: Int
        let workoutId: Int
        let lane: String
        let catalogExerciseId: Int64
        let orderIndex: Int
        let supersetGroupId: UUID?
        let supersetPosition: Int?
        let exerciseName: String
        let sets: [PendingSet]
        let enqueuedAt: Date
    }

    private struct WorkoutExerciseInsert: Encodable {
        let workout_id: Int
        let exercise_id: Int
        let order_index: Int
        let superset_group_id: UUID?
        let superset_position: Int?
        let notes: String?
        let custom_name: String?
    }

    private struct WorkoutSetInsert: Encodable {
        let workout_exercise_id: Int
        let set_number: Int
        let order_index: Int
        let reps: Int?
        let weight_kg: Double?
        let rpe: Double?
        let rest_sec: Int?
        let weight_segments: [StrengthWeightSegWire]?
    }

    private struct InsertedWorkoutExerciseId: Decodable {
        let id: Int
    }

    private static let storageKey = "liftr.pendingActiveExerciseAdds.v1"
    private static let localIdCounterKey = "liftr.pendingActiveExerciseAdds.localIdCounter"
    private static var syncTask: Task<Void, Never>?
    private static var statusByWorkoutId: [Int: ActiveExerciseAddSyncStatus] = [:]

    static func nextLocalExerciseId() -> Int {
        let current = UserDefaults.standard.integer(forKey: localIdCounterKey)
        let next = current == 0 ? -1 : current - 1
        UserDefaults.standard.set(next, forKey: localIdCounterKey)
        return next
    }

    static func status(for workoutId: Int) -> ActiveExerciseAddSyncStatus {
        statusByWorkoutId[workoutId] ?? .idle
    }

    static func isPending(_ workoutId: Int) -> Bool {
        let s = status(for: workoutId)
        if s == .pending || s == .syncing || s == .willRetry { return true }
        return loadPending().contains { $0.workoutId == workoutId }
    }

    static func hasPending(forWorkoutId workoutId: Int) -> Bool {
        loadPending().contains { $0.workoutId == workoutId }
    }

    static func pendingLocalIds(forWorkoutId workoutId: Int) -> Set<Int> {
        Set(loadPending().filter { $0.workoutId == workoutId }.map(\.localExerciseId))
    }

    @discardableResult
    static func enqueue(_ items: [PendingExerciseAdd]) -> [PendingExerciseAdd] {
        guard !items.isEmpty else { return [] }
        var pending = loadPending()
        for item in items {
            pending.removeAll { $0.localExerciseId == item.localExerciseId }
            pending.append(item)
            setStatus(.pending, workoutId: item.workoutId)
        }
        savePending(pending)
        Task { await syncPending() }
        return items
    }

    static func remove(localExerciseId: Int) {
        var pending = loadPending()
        let removed = pending.filter { $0.localExerciseId == localExerciseId }
        pending.removeAll { $0.localExerciseId == localExerciseId }
        savePending(pending)
        for item in removed {
            if !pending.contains(where: { $0.workoutId == item.workoutId }) {
                setStatus(.idle, workoutId: item.workoutId)
            }
        }
    }

    static func syncPending() async {
        if let running = syncTask, !running.isCancelled {
            await running.value
            return
        }
        let task = Task {
            let items = loadPending().sorted {
                if $0.workoutId != $1.workoutId { return $0.workoutId < $1.workoutId }
                if $0.orderIndex != $1.orderIndex { return $0.orderIndex < $1.orderIndex }
                return $0.localExerciseId < $1.localExerciseId
            }
            guard !items.isEmpty else { return }
            var touchedWorkoutIds = Set<Int>()
            for item in items {
                touchedWorkoutIds.insert(item.workoutId)
                await setStatusAsync(.syncing, workoutId: item.workoutId)
                let ok = await performInsertWithRetries(item: item)
                if ok {
                    removePending(localExerciseId: item.localExerciseId)
                } else {
                    await setStatusAsync(.willRetry, workoutId: item.workoutId)
                }
            }
            for wid in touchedWorkoutIds {
                if !loadPending().contains(where: { $0.workoutId == wid }) {
                    await setStatusAsync(.synced, workoutId: wid)
                }
            }
        }
        syncTask = task
        await task.value
        syncTask = nil
    }

    static func syncPending(forWorkoutId workoutId: Int) async {
        if let running = syncTask, !running.isCancelled {
            await running.value
        }
        let items = loadPending()
            .filter { $0.workoutId == workoutId }
            .sorted {
                if $0.orderIndex != $1.orderIndex { return $0.orderIndex < $1.orderIndex }
                return $0.localExerciseId < $1.localExerciseId
            }
        guard !items.isEmpty else { return }
        await setStatusAsync(.syncing, workoutId: workoutId)
        for item in items {
            let ok = await performInsertWithRetries(item: item)
            if ok {
                removePending(localExerciseId: item.localExerciseId)
            } else {
                await setStatusAsync(.willRetry, workoutId: workoutId)
                return
            }
        }
        if !loadPending().contains(where: { $0.workoutId == workoutId }) {
            await setStatusAsync(.synced, workoutId: workoutId)
        }
    }

    private static func performInsertWithRetries(item: PendingExerciseAdd) async -> Bool {
        do {
            let serverId = try await WorkoutStartSync.withRetries {
                try await performInsert(item: item)
            }
            NotificationCenter.default.post(
                name: .activeExerciseAddDidSync,
                object: nil,
                userInfo: [
                    "localExerciseId": item.localExerciseId,
                    "serverExerciseId": serverId,
                    "workoutId": item.workoutId,
                    "lane": item.lane
                ]
            )
            NotificationCenter.default.post(name: .workoutDidChange, object: item.workoutId)
            return true
        } catch {
            if !WorkoutStartSync.isRetriable(error) {
                removePending(localExerciseId: item.localExerciseId)
            }
            return false
        }
    }

    private static func performInsert(item: PendingExerciseAdd) async throws -> Int {
        guard let exerciseId = Int(exactly: item.catalogExerciseId) else {
            throw NSError(
                domain: "ActiveExerciseAddSync",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid catalog exercise id."]
            )
        }

        let client = SupabaseManager.shared.client
        let insertedData = try await client
            .from("workout_exercises")
            .insert(
                WorkoutExerciseInsert(
                    workout_id: item.workoutId,
                    exercise_id: exerciseId,
                    order_index: item.orderIndex,
                    superset_group_id: item.supersetGroupId,
                    superset_position: item.supersetPosition,
                    notes: nil,
                    custom_name: nil
                )
            )
            .select("id")
            .execute()
            .data

        let insertedRows = try JSONDecoder.supabase().decode([InsertedWorkoutExerciseId].self, from: insertedData)
        guard let inserted = insertedRows.first else {
            throw NSError(
                domain: "ActiveExerciseAddSync",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "No workout_exercise id returned."]
            )
        }

        let setRows = item.sets.enumerated().map { idx, set in
            WorkoutSetInsert(
                workout_exercise_id: inserted.id,
                set_number: 1,
                order_index: idx + 1,
                reps: set.reps,
                weight_kg: set.weightKg,
                rpe: set.rpe,
                rest_sec: set.restSec,
                weight_segments: set.weightSegments
            )
        }

        if !setRows.isEmpty {
            _ = try await client
                .from("exercise_sets")
                .insert(setRows)
                .execute()
        }

        return inserted.id
    }

    private static func loadPending() -> [PendingExerciseAdd] {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return [] }
        return (try? JSONDecoder().decode([PendingExerciseAdd].self, from: data)) ?? []
    }

    private static func savePending(_ items: [PendingExerciseAdd]) {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private static func removePending(localExerciseId: Int) {
        var pending = loadPending()
        pending.removeAll { $0.localExerciseId == localExerciseId }
        savePending(pending)
    }

    private static func statusToken(_ status: ActiveExerciseAddSyncStatus) -> String {
        switch status {
        case .idle: return "idle"
        case .pending: return "pending"
        case .syncing: return "syncing"
        case .synced: return "synced"
        case .willRetry: return "willRetry"
        }
    }

    private static func setStatus(_ status: ActiveExerciseAddSyncStatus, workoutId: Int) {
        statusByWorkoutId[workoutId] = status
        NotificationCenter.default.post(
            name: .activeExerciseAddSyncStatusChanged,
            object: nil,
            userInfo: ["workoutId": workoutId, "status": statusToken(status)]
        )
    }

    @MainActor
    private static func setStatusAsync(_ status: ActiveExerciseAddSyncStatus, workoutId: Int) async {
        setStatus(status, workoutId: workoutId)
    }
}
