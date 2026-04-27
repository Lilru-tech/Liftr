import ActivityKit
import SwiftUI
import WidgetKit
import LiftrWorkoutActivityKit

@main
struct LiftrWorkoutLiveWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutLiveActivityAttributes.self) { context in
            WorkoutLiveActivityLockView(context: context)
        } dynamicIsland: { context in
            WorkoutLiveActivityDynamicIsland(context: context)
        }
    }
}
