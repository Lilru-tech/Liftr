import Foundation

enum ClimbingEnvironment: String, CaseIterable, Identifiable {
    case indoor, outdoor
    var id: String { rawValue }
    var label: String {
        switch self {
        case .indoor: return "Indoor"
        case .outdoor: return "Outdoor"
        }
    }
}

enum ClimbingStyle: String, CaseIterable, Identifiable {
    case boulder, top_rope, lead, trad, mixed
    var id: String { rawValue }
    var wire: String { rawValue }
    var label: String {
        switch self {
        case .boulder: return "Boulder"
        case .top_rope: return "Top rope"
        case .lead: return "Lead"
        case .trad: return "Trad"
        case .mixed: return "Mixed"
        }
    }
}

enum ClimbingGradeSystem: String, CaseIterable, Identifiable {
    case v_scale, font, french, yds
    var id: String { rawValue }
    var wire: String { rawValue }
    var label: String {
        switch self {
        case .v_scale: return "V-scale"
        case .font: return "Font"
        case .french: return "French"
        case .yds: return "YDS"
        }
    }

    static func grades(for system: ClimbingGradeSystem) -> [String] {
        switch system {
        case .v_scale:
            return (0...12).map { "V\($0)" }
        case .font:
            return ["4", "4+", "5", "5+", "6A", "6A+", "6B", "6B+", "6C", "6C+", "7A", "7A+", "7B", "7B+", "7C", "7C+", "8A", "8A+", "8B", "8B+", "8C", "8C+", "9A"]
        case .french:
            return ["3", "4", "4+", "5a", "5b", "5c", "6a", "6a+", "6b", "6b+", "6c", "6c+", "7a", "7a+", "7b", "7b+", "7c", "7c+", "8a", "8a+", "8b", "8b+", "8c", "8c+", "9a"]
        case .yds:
            return ["5.5", "5.6", "5.7", "5.8", "5.9", "5.10a", "5.10b", "5.10c", "5.10d", "5.11a", "5.11b", "5.11c", "5.11d", "5.12a", "5.12b", "5.12c", "5.12d", "5.13a", "5.13b", "5.13c", "5.13d", "5.14a", "5.14b", "5.14c", "5.14d", "5.15a"]
        }
    }
}

struct ClimbingRouteForm: Identifiable, Hashable {
    let id = UUID()
    var routeName: String = ""
    var style: ClimbingStyle = .boulder
    var gradeSystem: ClimbingGradeSystem = .v_scale
    var gradeValue: String = ""
    var attempts: String = ""
    var sent: Bool = false
    var flash: Bool = false
    var notes: String = ""
}

enum ClimbingRouteFormatting {
    static func sanitizeGradeValue(_ value: String, for system: ClimbingGradeSystem) -> String {
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !v.isEmpty else { return "" }
        return ClimbingGradeSystem.grades(for: system).contains(v) ? v : ""
    }

    static func sanitizeClimbingForm(_ sport: inout SportForm) {
        sport.clHighestGradeValue = sanitizeGradeValue(sport.clHighestGradeValue, for: sport.clHighestGradeSystem)
        for index in sport.clRoutes.indices {
            sport.clRoutes[index].gradeValue = sanitizeGradeValue(
                sport.clRoutes[index].gradeValue,
                for: sport.clRoutes[index].gradeSystem
            )
        }
    }

    static func displayGrade(system: ClimbingGradeSystem, value: String) -> String {
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !v.isEmpty else { return "—" }
        switch system {
        case .v_scale:
            if v.uppercased().hasPrefix("V") { return v.uppercased() }
            return "V\(v)"
        case .font, .french:
            return v
        case .yds:
            if v.hasPrefix("5.") { return v }
            return "5.\(v)"
        }
    }

    static func syncSessionSummary(from routes: [ClimbingRouteForm], into sport: inout SportForm) {
        let sentRoutes = routes.filter(\.sent)
        sport.clRoutesSent = "\(sentRoutes.count)"
        let attempts = routes.compactMap { Int($0.attempts.trimmingCharacters(in: .whitespacesAndNewlines)) }.reduce(0, +)
        sport.clRoutesAttempted = attempts > 0 ? "\(attempts)" : "\(max(sentRoutes.count, routes.count))"
        sport.clFlashes = "\(sentRoutes.filter(\.flash).count)"

        if let best = sentRoutes.max(by: { gradeRank($0) < gradeRank($1) }) {
            sport.clHighestGradeSystem = best.gradeSystem
            sport.clHighestGradeValue = sanitizeGradeValue(best.gradeValue, for: best.gradeSystem)
        }
    }

    private static func gradeRank(_ route: ClimbingRouteForm) -> Double {
        let v = route.gradeValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !v.isEmpty else { return -1 }
        switch route.gradeSystem {
        case .v_scale:
            let n = v.replacingOccurrences(of: "V", with: "", options: .caseInsensitive)
            return Double(n) ?? -1
        case .font, .french:
            return Double(ClimbingGradeSystem.grades(for: route.gradeSystem).firstIndex(of: v) ?? -1)
        case .yds:
            return Double(ClimbingGradeSystem.grades(for: .yds).firstIndex(of: v) ?? -1)
        }
    }
}
