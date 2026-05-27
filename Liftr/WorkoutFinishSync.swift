import Foundation
import Supabase

enum WorkoutFinishSyncStatus: Equatable {
    case idle
    case pending
    case syncing
    case synced
    case willRetry
}

extension Notification.Name {
    static let workoutFinishSyncStatusChanged = Notification.Name("workoutFinishSyncStatusChanged")
}

enum WorkoutFinishSync {
    struct PendingFinish: Codable {
        let workoutId: Int
        let endedAtIso: String
        let pausedSec: Int
        let exercises: [StrengthWorkoutExerciseSaveInput]
        let linked: [StrengthWorkoutFinishLinkedInput]
        let enqueuedAt: Date
    }

    private static let storageKey = "liftr.pendingWorkoutFinishes.v1"
    private static var syncTask: Task<Void, Never>?
    private static var statusByWorkoutId: [Int: WorkoutFinishSyncStatus] = [:]

    static func status(for workoutId: Int) -> WorkoutFinishSyncStatus {
        statusByWorkoutId[workoutId] ?? .idle
    }

    static func isPending(_ workoutId: Int) -> Bool {
        let s = status(for: workoutId)
        return s == .pending || s == .syncing || s == .willRetry
    }

    static func hasAnyPending() -> Bool {
        !loadPending().isEmpty
    }

    @discardableResult
    static func enqueue(
        workoutId: Int,
        endedAtIso: String,
        pausedSec: Int,
        exercises: [StrengthWorkoutExerciseSaveInput],
        linked: [StrengthWorkoutFinishLinkedInput]
    ) -> PendingFinish {
        let item = PendingFinish(
            workoutId: workoutId,
            endedAtIso: endedAtIso,
            pausedSec: pausedSec,
            exercises: exercises,
            linked: linked,
            enqueuedAt: Date()
        )
        var pending = loadPending()
        pending.removeAll { $0.workoutId == workoutId }
        pending.append(item)
        savePending(pending)
        setStatus(.pending, workoutId: workoutId)
        Task { await syncPending() }
        return item
    }

    static func syncPending() async {
        if let running = syncTask, !running.isCancelled {
            await running.value
            return
        }
        let task = Task {
            let items = loadPending()
            guard !items.isEmpty else { return }
            for item in items {
                await setStatusAsync(.syncing, workoutId: item.workoutId)
                let ok = await performFinishWithRetries(item: item)
                if ok {
                    removePending(workoutId: item.workoutId)
                    await setStatusAsync(.synced, workoutId: item.workoutId)
                } else {
                    await setStatusAsync(.willRetry, workoutId: item.workoutId)
                }
            }
        }
        syncTask = task
        await task.value
        syncTask = nil
    }

    private static func performFinishWithRetries(item: PendingFinish) async -> Bool {
        do {
            try await WorkoutStartSync.withRetries {
                let results = try await StrengthWorkoutSaveRPC.finishStrengthWorkoutV1(
                    client: SupabaseManager.shared.client,
                    workoutId: item.workoutId,
                    endedAt: item.endedAtIso,
                    pausedSec: item.pausedSec,
                    exercises: item.exercises,
                    linked: item.linked
                )
                for result in results {
                    NotificationCenter.default.post(name: .workoutDidChange, object: result.workout_id)
                }
            }
            return true
        } catch {
            if !WorkoutStartSync.isRetriable(error) {
                removePending(workoutId: item.workoutId)
            }
            return false
        }
    }

    private static func loadPending() -> [PendingFinish] {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return [] }
        return (try? JSONDecoder().decode([PendingFinish].self, from: data)) ?? []
    }

    private static func savePending(_ items: [PendingFinish]) {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private static func removePending(workoutId: Int) {
        var pending = loadPending()
        pending.removeAll { $0.workoutId == workoutId }
        savePending(pending)
    }

    private static func statusToken(_ status: WorkoutFinishSyncStatus) -> String {
        switch status {
        case .idle: return "idle"
        case .pending: return "pending"
        case .syncing: return "syncing"
        case .synced: return "synced"
        case .willRetry: return "willRetry"
        }
    }

    private static func setStatus(_ status: WorkoutFinishSyncStatus, workoutId: Int) {
        statusByWorkoutId[workoutId] = status
        NotificationCenter.default.post(
            name: .workoutFinishSyncStatusChanged,
            object: nil,
            userInfo: ["workoutId": workoutId, "status": statusToken(status)]
        )
    }

    @MainActor
    private static func setStatusAsync(_ status: WorkoutFinishSyncStatus, workoutId: Int) async {
        setStatus(status, workoutId: workoutId)
    }
}
