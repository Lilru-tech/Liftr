import ActivityKit
import LiftrWorkoutActivityKit
import WidgetKit
import SwiftUI

struct LiftrWorkoutLiveActivityLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutLiveActivityAttributes.self) { context in
            HStack(spacing: 10) {
                Image(systemName: kindIcon(context.state.kind))
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
                SessionWorkoutTimer(
                    start: context.state.startTime,
                    isPaused: context.state.isPaused,
                    pausedElapsedSeconds: context.state.pausedElapsedSeconds,
                    font: .title3.weight(.semibold)
                )
                    .multilineTextAlignment(.trailing)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .activityBackgroundTint(Color.black.opacity(0.5))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: kindIcon(context.state.kind))
                        .font(.title2)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.kind.shortLabel)
                        .font(.headline)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    SessionWorkoutTimer(
                        start: context.state.startTime,
                        isPaused: context.state.isPaused,
                        pausedElapsedSeconds: context.state.pausedElapsedSeconds,
                        font: .title2.weight(.semibold)
                    )
                }
            } compactLeading: {
                Image(systemName: "stopwatch")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 18, height: 15, alignment: .center)
            }
            compactTrailing: {
                DynamicIslandCompactTimer(
                    start: context.state.startTime,
                    isPaused: context.state.isPaused,
                    pausedElapsedSeconds: context.state.pausedElapsedSeconds
                )
            } minimal: {
                Image(systemName: "stopwatch")
            }
        }
    }

    private func kindIcon(_ kind: WorkoutLiveSessionKind) -> String {
        switch kind {
        case .strength: "dumbbell.fill"
        case .sport: "sportscourt.fill"
        case .cardio: "figure.run"
        }
    }
}

@inline(__always)
private func formatWorkoutLiveActivityElapsed(_ sec: Int) -> String {
    let h = sec / 3600
    let m = (sec % 3600) / 60
    let s = sec % 60
    if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
    return String(format: "%d:%02d", m, s)
}

@inline(__always)
private func formatWorkoutLiveActivityElapsedShort(_ sec: Int) -> String {
    let m = (sec % 3600) / 60
    let s = sec % 60
    return String(format: "%d:%02d", m, s)
}

private struct SessionWorkoutTimer: View {
    var start: Date
    var isPaused: Bool
    var pausedElapsedSeconds: Int
    var font: Font

    var body: some View {
        Group {
            if isPaused {
                Text(formatWorkoutLiveActivityElapsed(max(0, pausedElapsedSeconds)))
            } else {
                Text(start, style: .timer)
            }
        }
            .font(font)
            .monospacedDigit()
            .foregroundStyle(.white)
    }
}

private struct DynamicIslandCompactTimer: View {
    var start: Date
    var isPaused: Bool
    var pausedElapsedSeconds: Int

    private static let slotWidth: CGFloat = 58

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            Group {
                if isPaused {
                    Text(formatWorkoutLiveActivityElapsedShort(max(0, pausedElapsedSeconds)))
                } else {
                    Text(start, style: .timer)
                }
            }
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.42)
        }
        .frame(width: Self.slotWidth, alignment: .trailing)
        .clipped()
    }
}
