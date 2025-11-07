import SwiftUI

enum CardioActivityType: String, CaseIterable, Identifiable {
    case run, walk, hike, treadmill
    case bike, e_bike, mtb, indoor_cycling
    case rowerg
    case swim_pool, swim_open_water

    var id: String { rawValue }

    var label: String {
        switch self {
        case .run: "Run"
        case .walk: "Walk"
        case .hike: "Hike"
        case .treadmill: "Treadmill"
        case .bike: "Bike"
        case .e_bike: "E-Bike"
        case .mtb: "MTB"
        case .indoor_cycling: "Indoor cycling"
        case .rowerg: "RowErg"
        case .swim_pool: "Swim (pool)"
        case .swim_open_water: "Swim (open water)"
        }
    }

    var showsElevation: Bool {
        switch self {
        case .swim_pool, .swim_open_water, .rowerg, .indoor_cycling, .treadmill: false
        default: true
        }
    }
    var showsIncline: Bool { self == .treadmill }
    var showsCadenceRpm: Bool { [.indoor_cycling, .bike, .e_bike, .mtb, .rowerg].contains(self) }
    var showsWatts: Bool { [.indoor_cycling, .rowerg, .bike, .mtb].contains(self) }
    var showsSplit500m: Bool { self == .rowerg }
    var showsSwimFields: Bool { self == .swim_pool }
}
