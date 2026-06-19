import Foundation

enum PrFormatting {
    static func activityLabel(kind: String, label: String) -> String {
        let k = kind.lowercased()
        let wire = label.lowercased()
        if k == "cardio" {
            if let t = CardioActivityType(rawValue: wire) { return t.label }
            if wire == "cardio" { return "Cardio" }
            return snakeToTitle(wire)
        }
        if k == "sport" {
            if let t = SportType(rawValue: wire) { return t.label }
            return snakeToTitle(wire)
        }
        return label
    }

    static func activityIcon(kind: String, label: String) -> String {
        let k = kind.lowercased()
        let wire = label.lowercased()
        if k == "strength" { return "💪" }
        if k == "cardio" { return cardioIcon(for: wire) }
        if k == "sport" { return sportIcon(for: wire) }
        return ""
    }

    static func prettyMetricName(_ metric: String, kind: String, label: String) -> String {
        let m = metric.lowercased()
        switch m {
        case "max_hr", "max_avg_hr": return "Max HR"
        case "longest_duration_sec", "max_moving_time_sec": return "Longest duration"
        case "longest_distance_km", "max_total_distance_km": return "Longest distance"
        case "fastest_pace_sec_per_km": return "Fastest pace"
        case "max_elevation_m", "max_vertical_drop_m", "max_total_vertical_m": return "Max elevation"
        case "est_1rm_kg": return "Estimated 1RM"
        case "max_weight_kg": return "Max weight"
        case "best_set_volume_kg": return "Best set volume"
        case "max_reps": return "Max reps"
        case "max_cadence_rpm": return "Max cadence"
        case "max_watts_avg": return "Max watts"
        case "min_split_sec_per_500m": return "Best split"
        case "max_goals": return "Max goals"
        case "max_assists": return "Max assists"
        case "max_shots_on_target": return "Max shots on target"
        case "max_shots_on_goal": return "Max shots on goal"
        case "max_saves": return "Max saves"
        case "max_tackles", "max_tackles_made": return "Max tackles"
        case "max_yellow": return "Max yellow cards"
        case "max_red": return "Max red cards"
        case "max_points": return "Max points"
        case "max_rebounds": return "Max rebounds"
        case "max_steals": return "Max steals"
        case "max_blocks": return "Max blocks"
        case "min_turnovers": return "Fewest turnovers"
        case "max_fouls": return "Max fouls"
        case "max_sets_won": return "Max sets won"
        case "max_games_won": return "Max games won"
        case "max_aces": return "Max aces"
        case "min_double_faults": return "Fewest double faults"
        case "max_winners": return "Max winners"
        case "min_unforced_errors": return "Fewest unforced errors"
        case "max_break_points_won": return "Max break points won"
        case "max_net_points_won": return "Max net points won"
        case "max_digs": return "Max digs"
        case "min_official_time_sec": return "Best official time"
        case "max_runs_count": return "Max runs"
        case "max_speed_kmh": return "Max speed"
        case "max_routes_sent": return "Max routes sent"
        case "max_flashes": return "Max flashes"
        case "max_hits": return "Max hits"
        case "max_penalty_minutes": return "Max penalty minutes"
        case "max_tries": return "Max tries"
        case "max_meters_gained": return "Max meters gained"
        case "max_offloads": return "Max offloads"
        case "max_turnovers_won": return "Max turnovers won"
        default: return snakeToTitle(m)
        }
    }

    static func formatValue(metric: String, value: Double?, label: String = "") -> String {
        guard let v = value else { return "—" }
        let m = metric.lowercased()
        if m.hasSuffix("_kg") || m == "est_1rm_kg" || m == "max_weight_kg" || m == "best_set_volume_kg" {
            return String(format: "%.1f kg", v)
        }
        if m.contains("reps") && !m.contains("sec") {
            return "\(Int(v.rounded())) reps"
        }
        if m == "max_hr" || m == "max_avg_hr" {
            return "\(Int(v.rounded())) bpm"
        }
        if m == "longest_distance_km" || m == "max_total_distance_km" {
            return String(format: "%.1f km", v)
        }
        if m == "max_speed_kmh" {
            return String(format: "%.1f km/h", v)
        }
        if m == "max_elevation_m" || m == "max_vertical_drop_m" || m == "max_total_vertical_m" {
            return "\(Int(v.rounded())) m"
        }
        if m == "max_cadence_rpm" {
            let unit = label.lowercased() == "rowerg" ? "spm" : "rpm"
            return "\(Int(v.rounded())) \(unit)"
        }
        if m == "max_watts_avg" {
            return "\(Int(v.rounded())) W"
        }
        if m == "fastest_pace_sec_per_km" {
            return paceString(fromSeconds: v, suffix: "/km")
        }
        if m == "min_split_sec_per_500m" {
            return paceString(fromSeconds: v, suffix: "/500m")
        }
        if m.hasSuffix("_sec") || m.contains("duration") || m.contains("time") {
            return durationString(fromSeconds: v)
        }
        if m.hasSuffix("_km") {
            return String(format: "%.1f km", v)
        }
        if m.hasSuffix("_kmh") {
            return String(format: "%.1f km/h", v)
        }
        if m.hasSuffix("_m") && !m.contains("min") {
            return "\(Int(v.rounded())) m"
        }
        if m.hasPrefix("max_") || m.hasPrefix("min_") {
            return "\(Int(v.rounded()))"
        }
        return String(format: "%.2f", v)
    }

    static func lowerIsBetter(metric: String) -> Bool {
        let m = metric.lowercased()
        return m.hasPrefix("min_")
            || m.contains("pace")
            || m.contains("fastest")
            || m.contains("official_time")
            || m.contains("split")
            || m.contains("turnover")
            || m.contains("double_fault")
            || m.contains("unforced_error")
    }

    static func metricSortOrder(_ metric: String) -> Int {
        let order = [
            "longest_distance_km", "max_total_distance_km",
            "longest_duration_sec", "max_moving_time_sec", "min_official_time_sec",
            "fastest_pace_sec_per_km", "min_split_sec_per_500m",
            "max_speed_kmh",
            "max_elevation_m", "max_vertical_drop_m", "max_total_vertical_m",
            "max_hr", "max_avg_hr",
            "max_weight_kg", "est_1rm_kg", "best_set_volume_kg", "max_reps",
            "max_cadence_rpm", "max_watts_avg",
            "max_goals", "max_assists", "max_points", "max_tries",
            "max_routes_sent", "max_flashes", "max_runs_count"
        ]
        let m = metric.lowercased()
        if let idx = order.firstIndex(of: m) { return idx }
        return 1000 + m.hashValue % 1000
    }

    static func kindSortOrder(_ kind: String) -> Int {
        switch kind.lowercased() {
        case "strength": return 0
        case "cardio": return 1
        case "sport": return 2
        default: return 3
        }
    }

    private static func sportIcon(for sport: String) -> String {
        switch sport {
        case "padel", "tennis", "squash", "badminton", "table_tennis": return "🎾"
        case "football": return "⚽️"
        case "basketball": return "🏀"
        case "volleyball": return "🏐"
        case "rugby": return "🏉"
        case "hockey", "field_hockey": return "🏑"
        case "handball": return "🤾‍♂️"
        case "hyrox": return "🔥"
        case "ski": return "⛷️"
        case "climbing": return "🧗"
        default: return "🏅"
        }
    }

    private static func cardioIcon(for activity: String) -> String {
        switch activity {
        case "run", "outdoor_run", "trail_run": return "🏃‍♂️"
        case "treadmill": return "🏃‍♀️"
        case "walk", "hike": return "🚶‍♂️"
        case "bike", "e_bike", "mtb", "cycling", "road_cycling": return "🚴‍♂️"
        case "indoor_cycling", "spinning": return "🚲"
        case "rowerg", "rowing": return "🚣‍♂️"
        case "swim_pool": return "🏊‍♂️"
        case "swim_open_water": return "🌊"
        case "cardio": return "❤️‍🔥"
        default: return "❤️‍🔥"
        }
    }

    private static func durationString(fromSeconds secondsDouble: Double) -> String {
        let s = max(0, Int(secondsDouble.rounded()))
        let h = s / 3600
        let m = (s % 3600) / 60
        let sec = s % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, sec) }
        return String(format: "%d:%02d", m, sec)
    }

    private static func paceString(fromSeconds secondsDouble: Double, suffix: String) -> String {
        let s = max(1, Int(secondsDouble.rounded()))
        let m = s / 60
        let sec = s % 60
        return String(format: "%d:%02d %@", m, sec, suffix)
    }

    private static func snakeToTitle(_ s: String) -> String {
        s.replacingOccurrences(of: "_", with: " ").capitalized
    }
}
