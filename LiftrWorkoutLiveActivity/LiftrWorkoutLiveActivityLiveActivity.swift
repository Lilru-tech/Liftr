//
//  LiftrWorkoutLiveActivityLiveActivity.swift
//  LiftrWorkoutLiveActivity
//
//  Created by David Gomez sanchez on 23/4/26.
//

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
                // En Live Activity, `Text(…, .timer)` se actualiza solo; `TimelineView` suele quedar congelada (0:00).
                SessionWorkoutTimer(start: context.state.startTime, font: .title3.weight(.semibold))
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
                    SessionWorkoutTimer(start: context.state.startTime, font: .title2.weight(.semibold))
                }
            } compactLeading: {
                // Ancho fijo: el icono no participa en un HStack “infinito” con el trailing.
                Image(systemName: "stopwatch")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 18, height: 15, alignment: .center)
            } compactTrailing: {
                // `Text(…, .timer)` pide ancho de layout enorme; el contenedor fija el tamaño de la píldora compacta.
                DynamicIslandCompactTimer(start: context.state.startTime)
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

// MARK: - Crono (usa `Text(…, .timer)`: en ActivityKit avanza; `TimelineView` no tick en la isla/lock y se queda en 0:00)

private struct SessionWorkoutTimer: View {
    var start: Date
    var font: Font

    var body: some View {
        Text(start, style: .timer)
            .font(font)
            .monospacedDigit()
            .foregroundStyle(.white)
    }
}

/// Crono del compact: mismo `Text(…, .timer)` (sigue actualizando), envuelto en un ancho fijo para no alargar la isla.
private struct DynamicIslandCompactTimer: View {
    var start: Date

    private static let slotWidth: CGFloat = 58

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            Text(start, style: .timer)
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
