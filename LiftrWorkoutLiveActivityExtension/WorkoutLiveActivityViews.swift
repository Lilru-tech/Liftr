import ActivityKit
import LiftrWorkoutActivityKit
import SwiftUI

@inline(__always)
fileprivate func formatWorkoutElapsed(_ sec: Int) -> String {
    let h = sec / 3600
    let m = (sec % 3600) / 60
    let s = sec % 60
    if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
    return String(format: "%d:%02d", m, s)
}

@inline(__always)
fileprivate func formatWorkoutElapsedShort(_ sec: Int) -> String {
    let m = (sec % 3600) / 60
    let s = sec % 60
    return String(format: "%d:%02d", m, s)
}

@available(iOS 16.2, *)
struct WorkoutLiveActivityLockView: View {
    let context: ActivityViewContext<WorkoutLiveActivityAttributes>

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: kindIcon)
                .font(.title2)
                .foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 2) {
                Text("Liftr")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
                Text(context.state.kind.shortLabel)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.7))
            }
            Spacer(minLength: 0)
            elapsingView
        }
        .activityBackgroundTint(Color.black.opacity(0.5))
    }

    @ViewBuilder
    private var elapsingView: some View {
        let start = context.state.startTime
        if context.state.isPaused {
            Text(formatWorkoutElapsed(max(0, context.state.pausedElapsedSeconds)))
                .font(.title3.weight(.semibold).monospacedDigit())
                .foregroundStyle(.white)
        } else {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                let sec = max(0, Int(Date().timeIntervalSince(start)))
                Text(formatWorkoutElapsed(sec))
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.white)
            }
        }
    }

    private var kindIcon: String {
        switch context.state.kind {
        case .strength: "dumbbell.fill"
        case .sport: "sportscourt.fill"
        case .cardio: "figure.run"
        }
    }
}

@available(iOS 16.2, *)
struct WorkoutLiveActivityDynamicIsland: View {
    let context: ActivityViewContext<WorkoutLiveActivityAttributes>

    var body: some View {
        DynamicIsland {
            DynamicIslandExpandedRegion(.leading) {
                Image(systemName: kindIcon)
                    .font(.title2)
            }
            DynamicIslandExpandedRegion(.trailing) {
                Text(context.state.kind.shortLabel)
                    .font(.headline)
            }
            DynamicIslandExpandedRegion(.bottom) {
                let start = context.state.startTime
                if context.state.isPaused {
                    Text(formatWorkoutElapsed(max(0, context.state.pausedElapsedSeconds)))
                        .font(.title2.weight(.semibold).monospacedDigit())
                } else {
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        let sec = max(0, Int(Date().timeIntervalSince(start)))
                        Text(formatWorkoutElapsed(sec))
                            .font(.title2.weight(.semibold).monospacedDigit())
                    }
                }
            }
        } compactLeading: {
            Image(systemName: "stopwatch")
                .font(.caption2.weight(.semibold))
        } compactTrailing: {
            let start = context.state.startTime
            if context.state.isPaused {
                Text(formatWorkoutElapsedShort(max(0, context.state.pausedElapsedSeconds)))
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .minimumScaleFactor(0.7)
            } else {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    let sec = max(0, Int(Date().timeIntervalSince(start)))
                    Text(formatWorkoutElapsedShort(sec))
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .minimumScaleFactor(0.7)
                }
            }
        } minimal: {
            Image(systemName: "stopwatch")
        }
    }

    private var kindIcon: String {
        switch context.state.kind {
        case .strength: "dumbbell.fill"
        case .sport: "sportscourt.fill"
        case .cardio: "figure.run"
        }
    }
}
