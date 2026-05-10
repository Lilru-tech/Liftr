import Foundation
import ActivityKit

/// Tipo de entreno activo (misma carga de estado en la app y en la Live Activity).
public struct WorkoutLiveActivityAttributes: ActivityAttributes {
    public struct ContentState: Hashable, Codable, Sendable {
        /// Inicio del entreno (cuenta usada con TimelineView para el tiempo en island / lock).
        public var startTime: Date
        public var kind: WorkoutLiveSessionKind
        public var isPaused: Bool
        public var pausedElapsedSeconds: Int

        enum CodingKeys: String, CodingKey {
            case startTime
            case kind
            case isPaused
            case pausedElapsedSeconds
        }

        public init(startTime: Date, kind: WorkoutLiveSessionKind, isPaused: Bool = false, pausedElapsedSeconds: Int = 0) {
            self.startTime = startTime
            self.kind = kind
            self.isPaused = isPaused
            self.pausedElapsedSeconds = pausedElapsedSeconds
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            startTime = try c.decode(Date.self, forKey: .startTime)
            kind = try c.decode(WorkoutLiveSessionKind.self, forKey: .kind)
            isPaused = try c.decodeIfPresent(Bool.self, forKey: .isPaused) ?? false
            pausedElapsedSeconds = try c.decodeIfPresent(Int.self, forKey: .pausedElapsedSeconds) ?? 0
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(startTime, forKey: .startTime)
            try c.encode(kind, forKey: .kind)
            try c.encode(isPaused, forKey: .isPaused)
            try c.encode(pausedElapsedSeconds, forKey: .pausedElapsedSeconds)
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
