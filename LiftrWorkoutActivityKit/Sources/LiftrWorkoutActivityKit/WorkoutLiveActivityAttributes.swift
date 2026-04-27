import Foundation
import ActivityKit

/// Tipo de entreno activo (misma carga de estado en la app y en la Live Activity).
public struct WorkoutLiveActivityAttributes: ActivityAttributes {
    public struct ContentState: Hashable, Codable, Sendable {
        /// Inicio del entreno (cuenta usada con TimelineView para el tiempo en island / lock).
        public var startTime: Date
        public var kind: WorkoutLiveSessionKind

        public init(startTime: Date, kind: WorkoutLiveSessionKind) {
            self.startTime = startTime
            self.kind = kind
        }
    }

    public init() {}
}

public enum WorkoutLiveSessionKind: String, Hashable, Codable, Sendable, CaseIterable {
    case strength
    case sport
    case cardio

    public var shortLabel: String {
        switch self {
        case .strength: "Strength"
        case .sport: "Sport"
        case .cardio: "Cardio"
        }
    }
}
