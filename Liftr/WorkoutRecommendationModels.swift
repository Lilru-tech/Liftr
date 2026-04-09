import Foundation

enum RecommendationDataSource: String, CaseIterable, Identifiable {
    case recentHistory
    case fullCatalog
    case hyrox
    case hyroxRace
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .recentHistory: return "My last 10 workouts"
        case .fullCatalog: return "Full app catalog"
        case .hyrox: return "Hyrox — mixed"
        case .hyroxRace: return "Hyrox — race format"
        }
    }
    
    var detail: String {
        switch self {
        case .recentHistory:
            return "Only exercises or activities you have already logged in your recent training."
        case .fullCatalog:
            return "Include any exercise or activity from the app, not only what you have used before."
        case .hyrox:
            return "Picks stations you’ve trained less in your recent Hyrox sessions and suggests typical distances, loads, and reps for each."
        case .hyroxRace:
            return "Like race day: easy run, then each official station in order, repeated. Run length, how many stations, and loads adapt to you."
        }
    }
}

enum StrengthSuggestionMode: String, CaseIterable, Identifiable {
    case prioritizeUndertrainedMuscles
    case prioritizeFrequentLifts
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .prioritizeUndertrainedMuscles:
            return "Balance muscle groups"
        case .prioritizeFrequentLifts:
            return "Frequent lifts"
        }
    }
    
    var detail: String {
        switch self {
        case .prioritizeUndertrainedMuscles:
            return "Favor muscles you trained less in those 10 sessions."
        case .prioritizeFrequentLifts:
            return "Exercises you programmed most often in those sessions—loads from your latest sets and RPE."
        }
    }
}

struct StrengthRecommendationExercise: Identifiable {
    var id: Int64 { exerciseId }
    let exerciseId: Int64
    let displayName: String
    let musclePrimary: String?
    let sets: [StrengthRecommendationSet]
}

struct StrengthRecommendationSet: Identifiable {
    let id = UUID()
    let setNumber: Int
    let reps: Int
    let weightKg: Double
    let rpe: Double?
    let restSec: Int?
}

struct CardioRecommendation: Equatable {
    let activity: CardioActivityType
    let durationSec: Int
    let distanceKm: Double?
    let elevationGainM: Int?
    let avgHr: Int?
    let maxHr: Int?
    let inclinePercent: Double?
    let cadenceRpm: Int?
    let wattsAvg: Int?
    let splitSecPer500m: Int?
    let swimLaps: Int?
    let poolLengthM: Int?
    let swimStyle: String?
    let rationale: String
    
    init(
        activity: CardioActivityType,
        durationSec: Int,
        distanceKm: Double? = nil,
        elevationGainM: Int? = nil,
        avgHr: Int? = nil,
        maxHr: Int? = nil,
        inclinePercent: Double? = nil,
        cadenceRpm: Int? = nil,
        wattsAvg: Int? = nil,
        splitSecPer500m: Int? = nil,
        swimLaps: Int? = nil,
        poolLengthM: Int? = nil,
        swimStyle: String? = nil,
        rationale: String
    ) {
        self.activity = activity
        self.durationSec = durationSec
        self.distanceKm = distanceKm
        self.elevationGainM = elevationGainM
        self.avgHr = avgHr
        self.maxHr = maxHr
        self.inclinePercent = inclinePercent
        self.cadenceRpm = cadenceRpm
        self.wattsAvg = wattsAvg
        self.splitSecPer500m = splitSecPer500m
        self.swimLaps = swimLaps
        self.poolLengthM = poolLengthM
        self.swimStyle = swimStyle
        self.rationale = rationale
    }
}

struct HyroxExerciseRecommendation: Equatable, Identifiable {
    let exerciseCode: String
    let customDisplayName: String
    let exerciseOrder: Int
    let distanceM: Int?
    let reps: Int?
    let weightKg: Double?
    let durationSec: Int?
    let heightCm: Int?
    let implementCount: Int?
    let notes: String?
    
    var id: String { "\(exerciseOrder)-\(exerciseCode)" }
}

enum SportRecommendation: Equatable {
    case durationOnly(durationMin: Int, rationale: String)
    case hyrox(durationMin: Int, exercises: [HyroxExerciseRecommendation], rationale: String)
}
