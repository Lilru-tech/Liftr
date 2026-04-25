import Foundation
import ActivityKit
import LiftrWorkoutActivityKit

@MainActor
enum WorkoutLiveActivityManager {
    private static var current: Activity<WorkoutLiveActivityAttributes>?

    static var isSupported: Bool {
        if #available(iOS 16.2, *) {
            ActivityAuthorizationInfo().areActivitiesEnabled
        } else {
            false
        }
    }

    static func startIfAvailable(startTime: Date, kind: WorkoutLiveSessionKind) {
        Task { @MainActor in
            if #available(iOS 16.2, *) {
                await start(startTime: startTime, kind: kind)
            }
        }
    }

    static func endIfAvailable() {
        Task { @MainActor in
            if #available(iOS 16.2, *) {
                await end()
            }
        }
    }

    @available(iOS 16.2, *)
    static func start(startTime: Date, kind: WorkoutLiveSessionKind) async {
        guard isSupported else { return }
        await end()
        let state = WorkoutLiveActivityAttributes.ContentState(startTime: startTime, kind: kind)
        do {
            current = try Activity.request(
                attributes: WorkoutLiveActivityAttributes(),
                content: .init(state: state, staleDate: nil),
                pushType: nil
            )
        } catch {
        }
    }

    @available(iOS 16.2, *)
    static func end() async {
        guard let a = current else { return }
        await a.end(nil, dismissalPolicy: .immediate)
        current = nil
    }
}
