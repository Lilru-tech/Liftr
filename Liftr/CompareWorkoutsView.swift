import SwiftUI
import Supabase

fileprivate let hyroxCustomPairingSeparator = "\u{001E}"

struct CompareWorkoutsView: View {
    let currentWorkoutId: Int
    let other: CompareOtherTarget
    let averageRightLabel: String?

    @State private var rightWorkoutIdForBuild: Int = 0

    init(currentWorkoutId: Int, other: CompareOtherTarget, averageRightLabel: String? = nil) {
        self.currentWorkoutId = currentWorkoutId
        self.other = other
        self.averageRightLabel = averageRightLabel
        if case .workout(let id) = other {
            _rightWorkoutIdForBuild = State(initialValue: id)
        }
    }

    init(currentWorkoutId: Int, myOtherWorkoutId: Int) {
        self.init(
            currentWorkoutId: currentWorkoutId,
            other: .workout(myOtherWorkoutId)
        )
    }

    struct ComparableMetric: Identifiable, Decodable {
        let metric: String
        let unit: String
        let left_value: Double
        let right_value: Double
        var id: String { metric }
        var diff: Double { left_value - right_value }
        var rawDiffPct: Double? {
            guard right_value != 0 else { return nil }
            return (left_value - right_value) / right_value * 100.0
        }
        var diffPct: Double? { rawDiffPct }

        var hasNonZeroValues: Bool {
            abs(left_value) > 1e-9 || abs(right_value) > 1e-9
        }
    }

    @Environment(\.dismiss) private var dismiss
    @State private var loading = false
    @State private var error: String?
    @State private var metrics: [ComparableMetric] = []
    @State private var workoutKind: String? = nil
    @State private var bothMine = false
    @State private var leftLabel: String = "Workout A"
    @State private var rightLabel: String = "Workout B"
    @State private var leftUserName: String? = nil
    @State private var rightUserName: String? = nil
    private static let leftColor  = Color(red: 0.02, green: 0.55, blue: 0.32)
    private static let rightColor = Color(red: 0.82, green: 0.12, blue: 0.18)

    private static func metricDirection(_ metric: String) -> Double {
        if metric.hasPrefix("hyrox.station."), metric.hasSuffix(".duration_sec") {
            return -1.0
        }
        switch metric {
        case "avg_pace_sec_per_km",
             "fastest_km_pace_sec",
             "split_sec_per_500m",
             "sec_per_km",
             "sec_per_500m",
             "avg_hr",
             "max_hr",
             "score_against",
             "hx_penalty_time_sec",
             "hx_official_time_sec",
             "hx_rank_overall",
             "hx_rank_category",
             "hx_no_reps":
            return -1.0
        case "total_rest_sec", "avg_rest_sec", "rest_pct_of_session":
            return -1.0
        default:
            return 1.0
        }
    }

    private static func barPairFractions(left: Double, right: Double, metric: String) -> (CGFloat, CGFloat) {
        let maxV0 = max(left, right, 0.0001)
        if metricDirection(metric) >= 0 {
            return (CGFloat(left / maxV0), CGFloat(right / maxV0))
        }
        let e = 1e-6
        let sL = 1.0 / max(left, e)
        let sR = 1.0 / max(right, e)
        let m = max(sL, sR)
        if m < 1e-20 { return (0.5, 0.5) }
        return (CGFloat(sL / m), CGFloat(sR / m))
    }

    private static func winnerForegroundStyle(forSignedPct signed: Double) -> Color {
        if abs(signed) < 0.05 { return .secondary }
        return signed > 0 ? leftColor : rightColor
    }

    private func clamp(_ x: Double, _ lo: Double, _ hi: Double) -> Double {
        min(hi, max(lo, x))
    }

    private var displayMetrics: [ComparableMetric] {
        metrics.filter(\.hasNonZeroValues)
    }

    private var overallSignedPcts: [Double] {
        displayMetrics.compactMap { m -> Double? in
            guard let p = m.rawDiffPct else { return nil }
            let signed = p * Self.metricDirection(m.metric)
            return clamp(signed, -150, 150)
        }
    }

    private var overallPct: Double? {
        guard !overallSignedPcts.isEmpty else { return nil }
        return overallSignedPcts.reduce(0, +) / Double(overallSignedPcts.count)
    }

    private var overallCount: Int { overallSignedPcts.count }

    private static func overallPctFormat(_ v: Double) -> String {
        let a = abs(v)
        if a < 10 { return String(format: "%+.2f%%", v) }
        return String(format: "%+.1f%%", v)
    }
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.headline.weight(.semibold))
                        .padding(8)
                        .background(.ultraThinMaterial, in: Circle())
                }
                Spacer()
            }

            Text("Compare workouts")
                .font(.title3.weight(.semibold))

            if let k = workoutKind {
                VStack(spacing: 6) {
                    Text(leftLabel)
                        .foregroundStyle(CompareWorkoutsView.leftColor)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("vs")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text(rightLabel)
                        .foregroundStyle(CompareWorkoutsView.rightColor)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("— \(k.capitalized)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline)
                .padding(.horizontal, 4)
            }

            if loading {
                ProgressView().padding(.top, 12)
            } else if let e = error {
                Text(e).foregroundStyle(.red).padding(.top, 12)
            } else if metrics.isEmpty {
                Text("Nothing to compare for these workouts. Please add more data to your workout")
                    .foregroundStyle(.secondary)
                    .padding(.top, 12)
            } else if displayMetrics.isEmpty {
                Text("No metrics to compare (all values are zero for both workouts).")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 12)
            } else {
                if let o = overallPct {
                    OverallSummaryCard(valuePct: o, count: overallCount, totalRows: displayMetrics.count)
                        .padding(.bottom, 6)
                }

                List(displayMetrics) { m in
                    ComparisonRow(m: m)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 14, trailing: 0))
                        .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
                .scrollIndicators(.hidden)
                .scrollContentBackground(.hidden)
            }

            Spacer(minLength: 8)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 16)
        .navigationTitle("Compare")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Close") { dismiss() }
            }
        }
        .task { await load() }
    }

    private struct ComparisonRow: View {
        let m: CompareWorkoutsView.ComparableMetric

        private var pctBadge: (raw: Double, signed: Double)? {
            guard let p = m.rawDiffPct else { return nil }
            let signed = p * CompareWorkoutsView.metricDirection(m.metric)
            return (p, signed)
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(Self.prettyMetric(m.metric))
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    if let b = pctBadge {
                        Text(pctString(b.signed))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(CompareWorkoutsView.winnerForegroundStyle(forSignedPct: b.signed))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background {
                                ZStack {
                                    Capsule().fill(.ultraThinMaterial)
                                    if abs(b.signed) >= 0.05 {
                                        Capsule().fill(CompareWorkoutsView.winnerForegroundStyle(forSignedPct: b.signed).opacity(0.22))
                                    }
                                }
                            }
                    }
                }

                HStack(spacing: 10) {
                    Text(formatValue(m.left_value, unit: m.unit))
                        .font(.caption)
                        .foregroundStyle(CompareWorkoutsView.leftColor)
                    Text("vs")
                        .font(.caption)
                        .foregroundStyle(.secondary.opacity(0.7))
                    Text(formatValue(m.right_value, unit: m.unit))
                        .font(.caption)
                        .foregroundStyle(CompareWorkoutsView.rightColor)
                }

                GeometryReader { geo in
                    let usableW = max(0, geo.size.width - 20)
                    let (lf, rf) = CompareWorkoutsView.barPairFractions(
                        left: m.left_value,
                        right: m.right_value,
                        metric: m.metric
                    )
                    let leftW = lf * usableW
                    let rightW = rf * usableW

                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.white.opacity(0.12))
                            )
                            .padding(.horizontal, 10)

                        VStack(alignment: .leading, spacing: 8) {
                            Capsule()
                                .fill(LinearGradient(
                                    gradient: Gradient(colors: [CompareWorkoutsView.leftColor,
                                                                CompareWorkoutsView.leftColor.opacity(0.7)]),
                                    startPoint: .leading, endPoint: .trailing
                                ))
                                .frame(width: leftW, height: 10)
                                .shadow(color: CompareWorkoutsView.leftColor.opacity(0.25), radius: 1, x: 0, y: 0)

                            Capsule()
                                .fill(LinearGradient(
                                    gradient: Gradient(colors: [CompareWorkoutsView.rightColor,
                                                                CompareWorkoutsView.rightColor.opacity(0.7)]),
                                    startPoint: .leading, endPoint: .trailing
                                ))
                                .frame(width: rightW, height: 10)
                                .shadow(color: CompareWorkoutsView.rightColor.opacity(0.25), radius: 1, x: 0, y: 0)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 10)
                    }

                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .frame(height: 56)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.10)))
            .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 3)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }

        private func pctString(_ v: Double) -> String {
            String(format: "%+.1f%%", v)
        }
        private func formatValue(_ v: Double, unit: String) -> String {
            switch unit {
            case "km":       return String(format: "%.2f km", v)
            case "kg":       return String(format: "%.1f kg", v)
            case "sec":      return secs(v)
            case "sec_per_km": return secsPerKm(v)
            case "sec_per_100m": return secsPer100m(v)
            case "sec_per_500m": return secsPer500(v)
            case "bpm":      return String(format: "%.0f bpm", v)
            case "m":        return String(format: "%.0f m", v)
            case "W":        return String(format: "%.0f W", v)
            case "pct":      return String(format: "%.1f %%", v)
            case "count", "sets", "games", "pts", "laps", "min":
                return String(format: "%.0f %@", v, unit == "count" ? "" : unit)
            case "kg_per_min":
                return String(format: "%.1f kg/min", v)
            case "sets_per_min":
                return String(format: "%.2f sets/min", v)
            case "reps_per_min":
                return String(format: "%.2f reps/min", v)
            case "kg_per_rep":
                return String(format: "%.2f kg/rep", v)
            case "kg_per_set":
                return String(format: "%.2f kg/set", v)
            case "rpe":
                return String(format: "%.1f", v)
            case "reps_per_exercise":
                return String(format: "%.1f reps/ex", v)
            case "sets_per_exercise":
                return String(format: "%.1f sets/ex", v)
            default:
                return String(format: "%.2f %@", v, unit)
            }
        }
        private func secs(_ v: Double) -> String {
            let s = max(0, Int(v.rounded()))
            let h = s/3600, m = (s%3600)/60, sec = s%60
            return h > 0 ? String(format:"%d:%02d:%02d",h,m,sec) : String(format:"%d:%02d",m,sec)
        }
        private func secsPerKm(_ v: Double) -> String {
            let s = max(0, Int(v.rounded()))
            return String(format:"%d:%02d /km", s/60, s%60)
        }
        private func secsPer500(_ v: Double) -> String {
            let s = max(0, Int(v.rounded()))
            return String(format:"%d:%02d /500m", s/60, s%60)
        }
        private func secsPer100m(_ v: Double) -> String {
            let s = max(0, Int(v.rounded()))
            return String(format:"%d:%02d /100m", s/60, s%60)
        }
        private static func prettyMetric(_ m: String) -> String {
            switch m {
            case "distance_km": return "Distance"
            case "duration_sec": return "Duration"
            case "avg_pace_sec_per_km": return "Avg pace"
            case "fastest_km_pace_sec": return "Fastest km"
            case "avg_hr": return "Avg HR"
            case "max_hr": return "Max HR"
            case "elevation_gain_m": return "Elevation gain"
            case "cadence": return "Cadence"
            case "watts_avg": return "Avg watts"
            case "incline_pct": return "Incline"
            case "swim_laps": return "Laps"
            case "pool_length_m": return "Pool length"
            case "split_sec_per_500m": return "Split /500m"
            case "score_for": return "Score for"
            case "score_against": return "Score against"
            case "rk_sets_won": return "Sets won"
            case "rk_sets_lost": return "Sets lost"
            case "rk_games_won": return "Games won"
            case "rk_games_lost": return "Games lost"
            case "rk_aces": return "Aces"
            case "rk_double_faults": return "Double faults"
            case "rk_winners": return "Winners"
            case "rk_unforced_errors": return "Unforced errors"
            case "rk_break_points_won": return "Break points won"
            case "rk_break_points_total": return "Break points total"
            case "rk_net_points_won": return "Net points won"
            case "rk_net_points_total": return "Net points total"
            case "bb_points": return "Points"
            case "bb_rebounds": return "Rebounds"
            case "bb_assists": return "Assists"
            case "bb_steals": return "Steals"
            case "bb_blocks": return "Blocks"
            case "bb_fg_made": return "FG made"
            case "bb_fg_attempted": return "FG attempted"
            case "bb_three_made": return "3PT made"
            case "bb_three_attempted": return "3PT attempted"
            case "bb_ft_made": return "FT made"
            case "bb_ft_attempted": return "FT attempted"
            case "bb_turnovers": return "Turnovers"
            case "bb_fouls": return "Fouls"
            case "fb_minutes_played": return "Minutes played"
            case "fb_goals": return "Goals"
            case "fb_assists": return "Assists"
            case "fb_shots_on_target": return "Shots on target"
            case "fb_passes_completed": return "Passes completed"
            case "fb_passes_attempted": return "Passes attempted"
            case "fb_tackles": return "Tackles"
            case "fb_interceptions": return "Interceptions"
            case "fb_saves": return "Saves"
            case "fb_yellow_cards": return "Yellow cards"
            case "fb_red_cards": return "Red cards"
            case "exercises_count": return "Exercises"
            case "sets_count": return "Sets"
            case "total_volume_kg": return "Total volume"
            case "total_reps": return "Total reps"
            case "avg_weight_per_rep_kg": return "Avg weight / rep"
            case "avg_weight_per_set_kg": return "Avg weight / set"
            case "volume_per_min_kg": return "Volume / min"
            case "sets_per_min": return "Sets / min"
            case "reps_per_min": return "Reps / min"
            case "max_weight_kg": return "Heaviest set"
            case "max_set_volume_kg": return "Top set volume"
            case "avg_rpe": return "Average RPE"
            case "hard_sets_count": return "Hard sets (RPE ≥ 8)"
            case "avg_reps_per_exercise": return "Reps / exercise"
            case "avg_sets_per_exercise": return "Sets / exercise"
            case "total_rest_sec": return "Planned rest (total)"
            case "avg_rest_sec": return "Planned rest (avg per set)"
            case "rest_pct_of_session": return "Planned rest (% of session)"
            case "vb_points": return "Points"
            case "vb_aces": return "Aces"
            case "vb_blocks": return "Blocks"
            case "vb_digs": return "Digs"
            case "hb_minutes_played": return "Minutes played"
            case "hb_goals": return "Goals"
            case "hb_shots": return "Shots"
            case "hb_shots_on_target": return "Shots on target"
            case "hb_assists": return "Assists"
            case "hb_steals": return "Steals"
            case "hb_blocks": return "Blocks"
            case "hb_turnovers_lost": return "Turnovers lost"
            case "hb_seven_m_goals": return "7 m goals"
            case "hb_seven_m_attempts": return "7 m attempts"
            case "hb_saves": return "Saves"
            case "hb_yellow_cards": return "Yellow cards"
            case "hb_two_min_suspensions": return "2-min suspensions"
            case "hb_red_cards": return "Red cards"
            case "hk_minutes_played": return "Minutes played"
            case "hk_goals": return "Goals"
            case "hk_assists": return "Assists"
            case "hk_shots_on_goal": return "Shots on goal"
            case "hk_plus_minus": return "+/-"
            case "hk_hits": return "Hits"
            case "hk_blocks": return "Blocks"
            case "hk_faceoffs_won": return "Faceoffs won"
            case "hk_faceoffs_total": return "Faceoffs total"
            case "hk_saves": return "Saves"
            case "hk_penalty_minutes": return "Penalty minutes"
            case "rg_minutes_played": return "Minutes played"
            case "rg_tries": return "Tries"
            case "rg_conversions_made": return "Conversions made"
            case "rg_conversions_attempted": return "Conversions attempted"
            case "rg_penalty_goals_made": return "Penalty goals made"
            case "rg_penalty_goals_attempted": return "Penalty goals attempted"
            case "rg_runs": return "Runs"
            case "rg_meters_gained": return "Meters gained"
            case "rg_offloads": return "Offloads"
            case "rg_tackles_made": return "Tackles made"
            case "rg_tackles_missed": return "Tackles missed"
            case "rg_turnovers_won": return "Turnovers won"
            case "rg_yellow_cards": return "Yellow cards"
            case "rg_red_cards": return "Red cards"
            case "hx_official_time_sec": return "Official time"
            case "hx_rank_overall": return "Overall rank"
            case "hx_rank_category": return "Category rank"
            case "hx_no_reps": return "No-reps"
            case "hx_penalty_time_sec": return "Penalty time"
            case "hx_avg_hr": return "Avg HR"
            case "hx_max_hr": return "Max HR"

            default:
                if m.hasPrefix("hyrox.station.") {
                    return Self.prettyHyroxStationMetric(m)
                }
                return m.replacingOccurrences(of: "_", with: " ").capitalized
            }
        }

        private static func prettyHyroxStationMetric(_ m: String) -> String {
            let comps = m.split(separator: ".")
            guard comps.count >= 4, comps[0] == "hyrox", comps[1] == "station" else {
                return m.replacingOccurrences(of: "_", with: " ").capitalized
            }
            let field = String(comps.last!)
            let occKey = comps.dropFirst(2).dropLast().joined(separator: ".")
            let station = hyroxOccurrenceLabel(occKey)
            let fieldLabel: String
            switch field {
            case "distance_m": fieldLabel = "Distance"
            case "reps": fieldLabel = "Reps"
            case "duration_sec": fieldLabel = "Duration"
            case "weight_kg": fieldLabel = "Weight"
            case "implement_count": fieldLabel = "Implements"
            default: fieldLabel = field.replacingOccurrences(of: "_", with: " ").capitalized
            }
            return "\(station) · \(fieldLabel)"
        }

        private static func hyroxOccurrenceLabel(_ key: String) -> String {
            if key.hasPrefix("custom\(hyroxCustomPairingSeparator)") {
                let sep = hyroxCustomPairingSeparator
                let parts = key.split(separator: Character(sep), omittingEmptySubsequences: false).map(String.init)
                guard parts.count == 3,
                      parts[0] == "custom",
                      let ord = Int(parts[2]), ord >= 1
                else {
                    return key.replacingOccurrences(of: "_", with: " ").capitalized
                }
                let title = parts[1].localizedCapitalized
                return ord == 1 ? title : "\(title) (\(ord))"
            }

            guard let u = key.lastIndex(of: "_") else {
                return key.replacingOccurrences(of: "_", with: " ").capitalized
            }
            let suffix = key[key.index(after: u)...]
            guard let ord = Int(suffix), ord >= 1 else {
                return key.replacingOccurrences(of: "_", with: " ").capitalized
            }
            let code = String(key[..<u])
            let name = HyroxExerciseFormatting.label(code: code, displayName: nil, notes: nil)
            return ord == 1 ? name : "\(name) (\(ord))"
        }
    }
    
    private struct OverallSummaryCard: View {
        let valuePct: Double
        let count: Int
        let totalRows: Int

        private var subtitle: String {
            if count == totalRows {
                return "Based on \(count) metrics"
            }
            return "Based on \(count) of \(totalRows) metrics (rest need non-zero right value for %)"
        }

        var body: some View {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Overall")
                        .font(.subheadline.weight(.semibold))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(CompareWorkoutsView.overallPctFormat(valuePct))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(CompareWorkoutsView.winnerForegroundStyle(forSignedPct: valuePct))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background {
                        ZStack {
                            Capsule().fill(.ultraThinMaterial)
                            if abs(valuePct) >= 0.05 {
                                Capsule().fill(CompareWorkoutsView.winnerForegroundStyle(forSignedPct: valuePct).opacity(0.22))
                            }
                        }
                    }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.10)))
        }
    }

    private func load() async {
        await MainActor.run { loading = true; error = nil; metrics = [] }
        defer { Task { await MainActor.run { loading = false } } }

        let client = SupabaseManager.shared.client
        let decoder = JSONDecoder.supabase()

        if case .average(let scope, let poolIds, let sampleCount) = other {
            await loadAverageMetrics(
                poolIds: poolIds,
                scope: scope,
                sampleCount: sampleCount,
                decoder: decoder,
                client: client
            )
            return
        }

        guard case .workout(let otherId) = other else { return }
        await MainActor.run { rightWorkoutIdForBuild = otherId }

        struct URow: Decodable {
            let user_id: UUID
            let username: String?
        }

        struct WRow: Decodable {
            let id: Int
            let kind: String
            let title: String?
            let user_id: UUID
            let started_at: Date?
        }
        
        do {
            let lRes = try await client
                .from("workouts")
                .select("id, kind, title, user_id, started_at")
                .eq("id", value: currentWorkoutId)
                .single()
                .execute()

            let rRes = try await client
                .from("workouts")
                .select("id, kind, title, user_id, started_at")
                .eq("id", value: rightWorkoutIdForBuild)
                .single()
                .execute()
            let L = try decoder.decode(WRow.self, from: lRes.data)
            let R = try decoder.decode(WRow.self, from: rRes.data)
            
            @Sendable func fetchUserName(_ id: UUID) async -> String? {
                do {
                    let res = try await client
                        .from("profiles")
                        .select("user_id, username")
                        .eq("user_id", value: id)
                        .single()
                        .execute()

                    if let raw = String(data: res.data, encoding: .utf8) {
                        print("fetchUserName raw JSON:", raw)
                    }

                    let u: URow = try decoder.decode(URow.self, from: res.data)
                    let name = (u.username ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    return name.isEmpty ? nil : name
                } catch {
                    print("fetchUserName(\(id)) error:", error)
                    return nil
                }
            }
            
            func makeLabel(_ w: WRow, fallback: String, nameOverride: String?, forceUserName: Bool) -> String {
                if forceUserName {
                    let n = (nameOverride ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    return n.isEmpty ? fallback : n
                }

                if let n = nameOverride?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty {
                    return n
                }

                let t = (w.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty { return t }

                return fallback
            }

            func compareDateSuffix(_ date: Date?, other: Date?) -> String {
                guard let date = date else { return "" }
                let f = DateFormatter()
                f.locale = Locale.current
                if let other = other, Calendar.current.isDate(date, inSameDayAs: other) {
                    f.dateFormat = "dd/MM/yyyy HH:mm"
                } else {
                    f.dateFormat = "dd/MM/yyyy"
                }
                return " (\(f.string(from: date)))"
            }

            guard L.kind.lowercased() == R.kind.lowercased() else {
                await MainActor.run { error = "Workouts are different types (\(L.kind) vs \(R.kind))."; }
                return
            }
            
            var aName: String? = nil
            var bName: String? = nil

            if L.user_id != R.user_id {
                async let ln = fetchUserName(L.user_id)
                async let rn = fetchUserName(R.user_id)
                (aName, bName) = await (ln, rn)
            }

            await MainActor.run {
                workoutKind = L.kind
                bothMine = (L.user_id == R.user_id)

                leftUserName = aName
                rightUserName = bName

                let showNames = (L.user_id != R.user_id)

                let leftBase = makeLabel(
                    L,
                    fallback: showNames ? "User" : "Workout A",
                    nameOverride: showNames ? aName : nil,
                    forceUserName: showNames
                )
                let rightBase = makeLabel(
                    R,
                    fallback: showNames ? "User" : "Workout B",
                    nameOverride: showNames ? bName : nil,
                    forceUserName: showNames
                )
                leftLabel = leftBase + compareDateSuffix(L.started_at, other: R.started_at)
                rightLabel = rightBase + compareDateSuffix(R.started_at, other: L.started_at)
            }

            switch L.kind.lowercased() {
            case "cardio":
                try await buildCardioMetrics(decoder: decoder, client: client)
            case "sport":
                try await buildSportMetrics(decoder: decoder, client: client)
            case "strength":
                try await buildStrengthMetrics(decoder: decoder, client: client)
            default:
                await MainActor.run { error = "Unsupported workout kind." }
            }
        } catch {
            await MainActor.run { self.error = error.localizedDescription }
        }
    }

    private func loadAverageMetrics(
        poolIds: [Int],
        scope: CompareAverageScope,
        sampleCount: Int,
        decoder: JSONDecoder,
        client: SupabaseClient
    ) async {
        struct WRow: Decodable {
            let id: Int
            let kind: String
            let title: String?
            let started_at: Date?
        }
        guard poolIds.count >= CompareAveragePoolLoader.minSamples else {
            await MainActor.run { error = "Not enough workouts for average." }
            return
        }
        do {
            let lRes = try await client
                .from("workouts")
                .select("id, kind, title, started_at")
                .eq("id", value: currentWorkoutId)
                .single()
                .execute()
            let L = try decoder.decode(WRow.self, from: lRes.data)
            let kind = L.kind.lowercased()
            var perSession: [[ComparableMetric]] = []
            for pid in poolIds {
                await MainActor.run { rightWorkoutIdForBuild = pid }
                await MainActor.run { metrics = [] }
                switch kind {
                case "cardio":
                    try await buildCardioMetrics(decoder: decoder, client: client)
                case "sport":
                    try await buildSportMetrics(decoder: decoder, client: client)
                case "strength":
                    try await buildStrengthMetrics(decoder: decoder, client: client)
                default:
                    await MainActor.run { error = "Unsupported workout kind." }
                    return
                }
                let snap = await MainActor.run { metrics }
                if !snap.isEmpty { perSession.append(snap) }
            }
            let averaged = averageCompareMetrics(perSession)
            let t = (L.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let leftBase = t.isEmpty ? "Workout A" : t
            let leftSuffix: String = {
                guard let d = L.started_at else { return "" }
                let f = DateFormatter()
                f.locale = Locale.current
                f.dateFormat = "dd/MM/yyyy"
                return " (\(f.string(from: d)))"
            }()
            let right = averageRightLabel ?? compareAverageRightLabel(scope: scope, sampleCount: sampleCount)
            await MainActor.run {
                workoutKind = L.kind
                bothMine = true
                leftLabel = leftBase + leftSuffix
                rightLabel = right
                metrics = averaged
            }
        } catch {
            await MainActor.run { self.error = error.localizedDescription }
        }
    }

    private struct CardioRow: Decodable {
        let id: Int
        let activity_code: String?
        let modality: String?
        let distance_km: Decimal?
        let duration_sec: Int?
        let avg_hr: Int?
        let max_hr: Int?
        let avg_pace_sec_per_km: Int?
        let elevation_gain_m: Int?
    }
    private struct CardioExtrasWire: Decodable { let stats: Extras? }
    private struct Extras: Decodable {
        let cadence_rpm: Int?
        let watts_avg: Int?
        let incline_pct: Double?
        let swim_laps: Int?
        let pool_length_m: Int?
        let split_sec_per_500m: Int?
        let km_split_pace_sec: [Int]?
    }
    
    private static func fastestKmPaceSecFromSplits(_ splits: [Int]?) -> Double? {
        guard let s = splits?.filter({ $0 > 0 }), !s.isEmpty else { return nil }
        return s.map(Double.init).min()
    }

    private func buildCardioMetrics(decoder: JSONDecoder, client: SupabaseClient) async throws {
        let lQ = try await client.from("cardio_sessions").select("*").eq("workout_id", value: currentWorkoutId).single().execute()
        let rQ = try await client.from("cardio_sessions").select("*").eq("workout_id", value: rightWorkoutIdForBuild).single().execute()
        let L = try decoder.decode(CardioRow.self, from: lQ.data)
        let R = try decoder.decode(CardioRow.self, from: rQ.data)
        let la = (L.activity_code ?? L.modality ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let ra = (R.activity_code ?? R.modality ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !la.isEmpty, la == ra else {
            await MainActor.run { error = "Cardio activities differ (\(la) vs \(ra))." }
            return
        }

        func extras(for sessionId: Int) async throws -> Extras? {
            let q = try await client.from("cardio_session_stats").select("stats").eq("session_id", value: sessionId).single().execute()
            return try JSONDecoder.supabase().decode(CardioExtrasWire.self, from: q.data).stats
        }
        let LE = try? await extras(for: L.id)
        let RE = try? await extras(for: R.id)

        var out: [ComparableMetric] = []
        func add(_ metric: String, _ unit: String, _ lv: Double?, _ rv: Double?) {
            guard let lv, let rv else { return }
            out.append(.init(metric: metric, unit: unit, left_value: lv, right_value: rv))
        }
        func d(_ dec: Decimal?) -> Double? { dec.map { NSDecimalNumber(decimal: $0).doubleValue } }

        let swimCompare = CardioSwimDisplay.isSwimActivity(code: la)
        if swimCompare {
            add("distance_km", "m", d(L.distance_km).map { $0 * 1000 }, d(R.distance_km).map { $0 * 1000 })
            add(
                "avg_pace_sec_per_km",
                "sec_per_100m",
                L.avg_pace_sec_per_km.map { Double(CardioSwimDisplay.secPer100m(fromSecPerKm: $0)) },
                R.avg_pace_sec_per_km.map { Double(CardioSwimDisplay.secPer100m(fromSecPerKm: $0)) }
            )
        } else {
            add("distance_km", "km", d(L.distance_km), d(R.distance_km))
            add("avg_pace_sec_per_km", "sec_per_km", L.avg_pace_sec_per_km.map(Double.init), R.avg_pace_sec_per_km.map(Double.init))
        }
        add("duration_sec", "sec", L.duration_sec.map(Double.init), R.duration_sec.map(Double.init))
        if let le = LE, let re = RE,
           let lFast = Self.fastestKmPaceSecFromSplits(le.km_split_pace_sec),
           let rFast = Self.fastestKmPaceSecFromSplits(re.km_split_pace_sec) {
            add("fastest_km_pace_sec", "sec_per_km", lFast, rFast)
        }
        add("avg_hr", "bpm", L.avg_hr.map(Double.init), R.avg_hr.map(Double.init))
        add("max_hr", "bpm", L.max_hr.map(Double.init), R.max_hr.map(Double.init))
        add("elevation_gain_m", "m", L.elevation_gain_m.map(Double.init), R.elevation_gain_m.map(Double.init))

        if let le = LE, let re = RE {
            add("cadence", "rpm_spm", le.cadence_rpm.map(Double.init), re.cadence_rpm.map(Double.init))
            add("watts_avg", "W", le.watts_avg.map(Double.init), re.watts_avg.map(Double.init))
            add("incline_pct", "pct", le.incline_pct, re.incline_pct)
            add("swim_laps", "laps", le.swim_laps.map(Double.init), re.swim_laps.map(Double.init))
            add("pool_length_m", "m", le.pool_length_m.map(Double.init), re.pool_length_m.map(Double.init))
            add("split_sec_per_500m", "sec_per_500m", le.split_sec_per_500m.map(Double.init), re.split_sec_per_500m.map(Double.init))
        }

        await MainActor.run { metrics = out }
    }

    private struct SportRow: Decodable { let id: Int; let sport: String; let duration_sec: Int?; let score_for: Int?; let score_against: Int? }

    private func buildSportMetrics(decoder: JSONDecoder, client: SupabaseClient) async throws {
        struct SportRow: Decodable {
            let id: Int
            let sport: String
            let duration_sec: Int?
            let score_for: Int?
            let score_against: Int?
        }
        struct WMeta: Decodable {
            let duration_min: Int?
            let started_at: Date?
            let ended_at: Date?
        }

        async let lS = client.from("sport_sessions")
            .select("id, sport, duration_sec, score_for, score_against")
            .eq("workout_id", value: currentWorkoutId).single().execute()
        async let rS = client.from("sport_sessions")
            .select("id, sport, duration_sec, score_for, score_against")
            .eq("workout_id", value: rightWorkoutIdForBuild).single().execute()
        async let lW = client.from("workouts")
            .select("duration_min, started_at, ended_at")
            .eq("id", value: currentWorkoutId).single().execute()
        async let rW = client.from("workouts")
            .select("duration_min, started_at, ended_at")
            .eq("id", value: rightWorkoutIdForBuild).single().execute()

        let L = try decoder.decode(SportRow.self, from: try await lS.data)
        let R = try decoder.decode(SportRow.self, from: try await rS.data)
        let LM = try decoder.decode(WMeta.self, from: try await lW.data)
        let RM = try decoder.decode(WMeta.self, from: try await rW.data)

        let ls = L.sport.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let rs = R.sport.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard ls == rs else {
            await MainActor.run { error = "Different sports (\(ls) vs \(rs))." }
            return
        }

        func bestDurationSec(_ sess: Int?, _ meta: WMeta) -> Int? {
            if let s = sess, s > 0 { return s }
            if let m = meta.duration_min, m > 0 { return m * 60 }
            if let s = meta.started_at, let e = meta.ended_at {
                let sec = Int(e.timeIntervalSince(s).rounded())
                return sec > 0 ? sec : nil
            }
            return nil
        }

        var out: [ComparableMetric] = []
        func add(_ metric: String, _ unit: String, _ lv: Double?, _ rv: Double?) {
            guard let lv, let rv else { return }
            out.append(.init(metric: metric, unit: unit, left_value: lv, right_value: rv))
        }

        let lDurSec = bestDurationSec(L.duration_sec, LM)
        let rDurSec = bestDurationSec(R.duration_sec, RM)
        add("duration_sec", "sec", lDurSec.map(Double.init), rDurSec.map(Double.init))
        add("score_for", "pts", L.score_for.map(Double.init), R.score_for.map(Double.init))
        add("score_against", "pts", L.score_against.map(Double.init), R.score_against.map(Double.init))

        switch ls {
        case "padel", "tennis", "badminton", "squash", "table_tennis":
            struct RK: Decodable {
                let sets_won: Int?; let sets_lost: Int?
                let games_won: Int?; let games_lost: Int?
                let aces: Int?; let double_faults: Int?
                let winners: Int?; let unforced_errors: Int?
                let break_points_won: Int?; let break_points_total: Int?
                let net_points_won: Int?;  let net_points_total: Int?
            }
            let lRK = try? await client.from("racket_session_stats").select("*").eq("session_id", value: L.id).single().execute()
            let rRK = try? await client.from("racket_session_stats").select("*").eq("session_id", value: R.id).single().execute()
            if let lRK, let rRK {
                let a = try? decoder.decode(RK.self, from: lRK.data)
                let b = try? decoder.decode(RK.self, from: rRK.data)
                if let a, let b {
                    add("rk_sets_won", "sets", a.sets_won.map(Double.init), b.sets_won.map(Double.init))
                    add("rk_sets_lost", "sets", a.sets_lost.map(Double.init), b.sets_lost.map(Double.init))
                    add("rk_games_won", "games", a.games_won.map(Double.init), b.games_won.map(Double.init))
                    add("rk_games_lost", "games", a.games_lost.map(Double.init), b.games_lost.map(Double.init))
                    add("rk_aces", "count", a.aces.map(Double.init), b.aces.map(Double.init))
                    add("rk_double_faults", "count", a.double_faults.map(Double.init), b.double_faults.map(Double.init))
                    add("rk_winners", "count", a.winners.map(Double.init), b.winners.map(Double.init))
                    add("rk_unforced_errors", "count", a.unforced_errors.map(Double.init), b.unforced_errors.map(Double.init))
                    add("rk_break_points_won", "count", a.break_points_won.map(Double.init), b.break_points_won.map(Double.init))
                    add("rk_break_points_total", "count", a.break_points_total.map(Double.init), b.break_points_total.map(Double.init))
                    add("rk_net_points_won", "count", a.net_points_won.map(Double.init), b.net_points_won.map(Double.init))
                    add("rk_net_points_total", "count", a.net_points_total.map(Double.init), b.net_points_total.map(Double.init))
                }
            }

        case "basketball":
            struct BB: Decodable {
                let points: Int?; let rebounds: Int?; let assists: Int?; let steals: Int?; let blocks: Int?
                let fg_made: Int?; let fg_attempted: Int?
                let three_made: Int?; let three_attempted: Int?
                let ft_made: Int?; let ft_attempted: Int?
                let turnovers: Int?; let fouls: Int?
            }
            let lBB = try? await client.from("basketball_session_stats").select("*").eq("session_id", value: L.id).single().execute()
            let rBB = try? await client.from("basketball_session_stats").select("*").eq("session_id", value: R.id).single().execute()
            if let lBB, let rBB {
                let a = try? decoder.decode(BB.self, from: lBB.data)
                let b = try? decoder.decode(BB.self, from: rBB.data)
                if let a, let b {
                    add("bb_points", "pts", a.points.map(Double.init), b.points.map(Double.init))
                    add("bb_rebounds", "count", a.rebounds.map(Double.init), b.rebounds.map(Double.init))
                    add("bb_assists", "count", a.assists.map(Double.init), b.assists.map(Double.init))
                    add("bb_steals", "count", a.steals.map(Double.init), b.steals.map(Double.init))
                    add("bb_blocks", "count", a.blocks.map(Double.init), b.blocks.map(Double.init))
                    add("bb_fg_made", "count", a.fg_made.map(Double.init), b.fg_made.map(Double.init))
                    add("bb_fg_attempted", "count", a.fg_attempted.map(Double.init), b.fg_attempted.map(Double.init))
                    add("bb_three_made", "count", a.three_made.map(Double.init), b.three_made.map(Double.init))
                    add("bb_three_attempted", "count", a.three_attempted.map(Double.init), b.three_attempted.map(Double.init))
                    add("bb_ft_made", "count", a.ft_made.map(Double.init), b.ft_made.map(Double.init))
                    add("bb_ft_attempted", "count", a.ft_attempted.map(Double.init), b.ft_attempted.map(Double.init))
                    add("bb_turnovers", "count", a.turnovers.map(Double.init), b.turnovers.map(Double.init))
                    add("bb_fouls", "count", a.fouls.map(Double.init), b.fouls.map(Double.init))
                }
            }

        case "football":
            struct FB: Decodable {
                let minutes_played: Int?
                let goals: Int?
                let assists: Int?
                let shots_on_target: Int?
                let passes_completed: Int?
                let passes_attempted: Int?
                let tackles: Int?
                let interceptions: Int?
                let saves: Int?
                let yellow_cards: Int?
                let red_cards: Int?
            }
            let lFB = try? await client.from("football_session_stats").select("*").eq("session_id", value: L.id).single().execute()
            let rFB = try? await client.from("football_session_stats").select("*").eq("session_id", value: R.id).single().execute()
            if let lFB, let rFB {
                let a = try? decoder.decode(FB.self, from: lFB.data)
                let b = try? decoder.decode(FB.self, from: rFB.data)
                if let a, let b {
                    add("fb_minutes_played", "min", a.minutes_played.map(Double.init), b.minutes_played.map(Double.init))
                    add("fb_goals", "count", a.goals.map(Double.init), b.goals.map(Double.init))
                    add("fb_assists", "count", a.assists.map(Double.init), b.assists.map(Double.init))
                    add("fb_shots_on_target", "count", a.shots_on_target.map(Double.init), b.shots_on_target.map(Double.init))
                    add("fb_passes_completed", "count", a.passes_completed.map(Double.init), b.passes_completed.map(Double.init))
                    add("fb_passes_attempted", "count", a.passes_attempted.map(Double.init), b.passes_attempted.map(Double.init))
                    add("fb_tackles", "count", a.tackles.map(Double.init), b.tackles.map(Double.init))
                    add("fb_interceptions", "count", a.interceptions.map(Double.init), b.interceptions.map(Double.init))
                    add("fb_saves", "count", a.saves.map(Double.init), b.saves.map(Double.init))
                    add("fb_yellow_cards", "count", a.yellow_cards.map(Double.init), b.yellow_cards.map(Double.init))
                    add("fb_red_cards", "count", a.red_cards.map(Double.init), b.red_cards.map(Double.init))
                }
            }

        case "handball":
            struct HB: Decodable {
                let minutes_played: Int?
                let goals: Int?
                let shots: Int?
                let shots_on_target: Int?
                let assists: Int?
                let steals: Int?
                let blocks: Int?
                let turnovers_lost: Int?
                let seven_m_goals: Int?
                let seven_m_attempts: Int?
                let saves: Int?
                let yellow_cards: Int?
                let two_min_suspensions: Int?
                let red_cards: Int?
            }
            let lHB = try? await client.from("handball_session_stats").select("*").eq("session_id", value: L.id).single().execute()
            let rHB = try? await client.from("handball_session_stats").select("*").eq("session_id", value: R.id).single().execute()
            if let lHB, let rHB {
                let a = try? decoder.decode(HB.self, from: lHB.data)
                let b = try? decoder.decode(HB.self, from: rHB.data)
                if let a, let b {
                    add("hb_minutes_played", "min", a.minutes_played.map(Double.init), b.minutes_played.map(Double.init))
                    add("hb_goals", "count", a.goals.map(Double.init), b.goals.map(Double.init))
                    add("hb_shots", "count", a.shots.map(Double.init), b.shots.map(Double.init))
                    add("hb_shots_on_target", "count", a.shots_on_target.map(Double.init), b.shots_on_target.map(Double.init))
                    add("hb_assists", "count", a.assists.map(Double.init), b.assists.map(Double.init))
                    add("hb_steals", "count", a.steals.map(Double.init), b.steals.map(Double.init))
                    add("hb_blocks", "count", a.blocks.map(Double.init), b.blocks.map(Double.init))
                    add("hb_turnovers_lost", "count", a.turnovers_lost.map(Double.init), b.turnovers_lost.map(Double.init))
                    add("hb_seven_m_goals", "count", a.seven_m_goals.map(Double.init), b.seven_m_goals.map(Double.init))
                    add("hb_seven_m_attempts", "count", a.seven_m_attempts.map(Double.init), b.seven_m_attempts.map(Double.init))
                    add("hb_saves", "count", a.saves.map(Double.init), b.saves.map(Double.init))
                    add("hb_yellow_cards", "count", a.yellow_cards.map(Double.init), b.yellow_cards.map(Double.init))
                    add("hb_two_min_suspensions", "count", a.two_min_suspensions.map(Double.init), b.two_min_suspensions.map(Double.init))
                    add("hb_red_cards", "count", a.red_cards.map(Double.init), b.red_cards.map(Double.init))
                }
            }

        case "hockey":
            struct HK: Decodable {
                let minutes_played: Int?
                let goals: Int?
                let assists: Int?
                let shots_on_goal: Int?
                let plus_minus: Int?
                let hits: Int?
                let blocks: Int?
                let faceoffs_won: Int?
                let faceoffs_total: Int?
                let saves: Int?
                let penalty_minutes: Int?
            }
            let lHK = try? await client.from("hockey_session_stats").select("*").eq("session_id", value: L.id).single().execute()
            let rHK = try? await client.from("hockey_session_stats").select("*").eq("session_id", value: R.id).single().execute()
            if let lHK, let rHK {
                let a = try? decoder.decode(HK.self, from: lHK.data)
                let b = try? decoder.decode(HK.self, from: rHK.data)
                if let a, let b {
                    add("hk_minutes_played", "min", a.minutes_played.map(Double.init), b.minutes_played.map(Double.init))
                    add("hk_goals", "count", a.goals.map(Double.init), b.goals.map(Double.init))
                    add("hk_assists", "count", a.assists.map(Double.init), b.assists.map(Double.init))
                    add("hk_shots_on_goal", "count", a.shots_on_goal.map(Double.init), b.shots_on_goal.map(Double.init))
                    add("hk_plus_minus", "count", a.plus_minus.map(Double.init), b.plus_minus.map(Double.init))
                    add("hk_hits", "count", a.hits.map(Double.init), b.hits.map(Double.init))
                    add("hk_blocks", "count", a.blocks.map(Double.init), b.blocks.map(Double.init))
                    add("hk_faceoffs_won", "count", a.faceoffs_won.map(Double.init), b.faceoffs_won.map(Double.init))
                    add("hk_faceoffs_total", "count", a.faceoffs_total.map(Double.init), b.faceoffs_total.map(Double.init))
                    add("hk_saves", "count", a.saves.map(Double.init), b.saves.map(Double.init))
                    add("hk_penalty_minutes", "min", a.penalty_minutes.map(Double.init), b.penalty_minutes.map(Double.init))
                }
            }

        case "rugby":
            struct RG: Decodable {
                let minutes_played: Int?
                let tries: Int?
                let conversions_made: Int?
                let conversions_attempted: Int?
                let penalty_goals_made: Int?
                let penalty_goals_attempted: Int?
                let runs: Int?
                let meters_gained: Int?
                let offloads: Int?
                let tackles_made: Int?
                let tackles_missed: Int?
                let turnovers_won: Int?
                let yellow_cards: Int?
                let red_cards: Int?
            }
            let lRG = try? await client.from("rugby_session_stats").select("*").eq("session_id", value: L.id).single().execute()
            let rRG = try? await client.from("rugby_session_stats").select("*").eq("session_id", value: R.id).single().execute()
            if let lRG, let rRG {
                let a = try? decoder.decode(RG.self, from: lRG.data)
                let b = try? decoder.decode(RG.self, from: rRG.data)
                if let a, let b {
                    add("rg_minutes_played", "min", a.minutes_played.map(Double.init), b.minutes_played.map(Double.init))
                    add("rg_tries", "count", a.tries.map(Double.init), b.tries.map(Double.init))
                    add("rg_conversions_made", "count", a.conversions_made.map(Double.init), b.conversions_made.map(Double.init))
                    add("rg_conversions_attempted", "count", a.conversions_attempted.map(Double.init), b.conversions_attempted.map(Double.init))
                    add("rg_penalty_goals_made", "count", a.penalty_goals_made.map(Double.init), b.penalty_goals_made.map(Double.init))
                    add("rg_penalty_goals_attempted", "count", a.penalty_goals_attempted.map(Double.init), b.penalty_goals_attempted.map(Double.init))
                    add("rg_runs", "count", a.runs.map(Double.init), b.runs.map(Double.init))
                    add("rg_meters_gained", "m", a.meters_gained.map(Double.init), b.meters_gained.map(Double.init))
                    add("rg_offloads", "count", a.offloads.map(Double.init), b.offloads.map(Double.init))
                    add("rg_tackles_made", "count", a.tackles_made.map(Double.init), b.tackles_made.map(Double.init))
                    add("rg_tackles_missed", "count", a.tackles_missed.map(Double.init), b.tackles_missed.map(Double.init))
                    add("rg_turnovers_won", "count", a.turnovers_won.map(Double.init), b.turnovers_won.map(Double.init))
                    add("rg_yellow_cards", "count", a.yellow_cards.map(Double.init), b.yellow_cards.map(Double.init))
                    add("rg_red_cards", "count", a.red_cards.map(Double.init), b.red_cards.map(Double.init))
                }
            }

        case "hyrox":
            struct HX: Decodable {
                let official_time_sec: Int?
                let rank_overall: Int?
                let rank_category: Int?
                let no_reps: Int?
                let penalty_time_sec: Int?
                let avg_hr: Int?
                let max_hr: Int?
            }
            let lHX = try? await client.from("hyrox_session_stats").select("*").eq("session_id", value: L.id).single().execute()
            let rHX = try? await client.from("hyrox_session_stats").select("*").eq("session_id", value: R.id).single().execute()
            if let lHX, let rHX {
                let a = try? decoder.decode(HX.self, from: lHX.data)
                let b = try? decoder.decode(HX.self, from: rHX.data)
                if let a, let b {
                    add("hx_official_time_sec", "sec", a.official_time_sec.map(Double.init), b.official_time_sec.map(Double.init))
                    add("hx_rank_overall", "rank", a.rank_overall.map(Double.init), b.rank_overall.map(Double.init))
                    add("hx_rank_category", "rank", a.rank_category.map(Double.init), b.rank_category.map(Double.init))
                    add("hx_no_reps", "count", a.no_reps.map(Double.init), b.no_reps.map(Double.init))
                    add("hx_penalty_time_sec", "sec", a.penalty_time_sec.map(Double.init), b.penalty_time_sec.map(Double.init))
                    add("hx_avg_hr", "bpm", a.avg_hr.map(Double.init), b.avg_hr.map(Double.init))
                    add("hx_max_hr", "bpm", a.max_hr.map(Double.init), b.max_hr.map(Double.init))
                }
            }

            try await appendHyroxExerciseComparisonMetrics(
                leftSessionId: L.id,
                rightSessionId: R.id,
                decoder: decoder,
                client: client,
                append: { m, u, lv, rv in add(m, u, lv, rv) }
            )

        case "volleyball":
            struct VB: Decodable { let points: Int?; let aces: Int?; let blocks: Int?; let digs: Int? }
            let lVB = try? await client.from("volleyball_session_stats").select("*").eq("session_id", value: L.id).single().execute()
            let rVB = try? await client.from("volleyball_session_stats").select("*").eq("session_id", value: R.id).single().execute()
            if let lVB, let rVB {
                let a = try? decoder.decode(VB.self, from: lVB.data)
                let b = try? decoder.decode(VB.self, from: rVB.data)
                if let a, let b {
                    add("vb_points", "count", a.points.map(Double.init), b.points.map(Double.init))
                    add("vb_aces", "count", a.aces.map(Double.init), b.aces.map(Double.init))
                    add("vb_blocks", "count", a.blocks.map(Double.init), b.blocks.map(Double.init))
                    add("vb_digs", "count", a.digs.map(Double.init), b.digs.map(Double.init))
                }
            }

        default: break
        }

        await MainActor.run { metrics = out }
    }

    private func appendHyroxExerciseComparisonMetrics(
        leftSessionId: Int,
        rightSessionId: Int,
        decoder: JSONDecoder,
        client: SupabaseClient,
        append: (String, String, Double?, Double?) -> Void
    ) async throws {
        struct HyroxExerciseCompareRow: Decodable {
            let exercise_code: String
            let exercise_order: Int
            let distance_m: Int?
            let reps: Int?
            let weight_kg: Decimal?
            let duration_sec: Int?
            let implement_count: Int?
            let exercise_display_name: String?
        }

        func rowsByOccurrence(_ rows: [HyroxExerciseCompareRow]) -> [String: HyroxExerciseCompareRow] {
            var countByCode: [String: Int] = [:]
            var countByCustomDisplayNorm: [String: Int] = [:]
            var dict: [String: HyroxExerciseCompareRow] = [:]
            let sep = hyroxCustomPairingSeparator
            for r in rows.sorted(by: { $0.exercise_order < $1.exercise_order }) {
                let c = r.exercise_code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard !c.isEmpty else { continue }

                let key: String
                if c == HyroxExerciseFormatting.customExerciseCode {
                    let raw = (r.exercise_display_name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !raw.isEmpty else { continue }
                    let norm = raw.folding(options: .diacriticInsensitive, locale: .current).lowercased()
                    countByCustomDisplayNorm[norm, default: 0] += 1
                    let ord = countByCustomDisplayNorm[norm]!
                    key = "custom\(sep)\(norm)\(sep)\(ord)"
                } else {
                    countByCode[c, default: 0] += 1
                    let ord = countByCode[c]!
                    key = "\(c)_\(ord)"
                }
                dict[key] = r
            }
            return dict
        }

        async let leftQ = client
            .from("hyrox_session_exercises")
            .select("exercise_code,exercise_order,distance_m,reps,weight_kg,duration_sec,implement_count,exercise_display_name")
            .eq("session_id", value: leftSessionId)
            .order("exercise_order", ascending: true)
            .execute()
        async let rightQ = client
            .from("hyrox_session_exercises")
            .select("exercise_code,exercise_order,distance_m,reps,weight_kg,duration_sec,implement_count,exercise_display_name")
            .eq("session_id", value: rightSessionId)
            .order("exercise_order", ascending: true)
            .execute()

        let leftRows = try decoder.decode([HyroxExerciseCompareRow].self, from: try await leftQ.data)
        let rightRows = try decoder.decode([HyroxExerciseCompareRow].self, from: try await rightQ.data)

        let leftMap = rowsByOccurrence(leftRows)
        let rightMap = rowsByOccurrence(rightRows)
        let commonKeys = Set(leftMap.keys).intersection(rightMap.keys)
        let keysSorted = commonKeys.sorted {
            (leftMap[$0]?.exercise_order ?? 0) < (leftMap[$1]?.exercise_order ?? 0)
        }

        let decToD: (Decimal?) -> Double? = { $0.map { NSDecimalNumber(decimal: $0).doubleValue } }

        for key in keysSorted {
            guard let a = leftMap[key], let b = rightMap[key] else { continue }
            func m(_ field: String) -> String { "hyrox.station.\(key).\(field)" }
            append(m("distance_m"), "m", a.distance_m.map(Double.init), b.distance_m.map(Double.init))
            append(m("reps"), "count", a.reps.map(Double.init), b.reps.map(Double.init))
            append(m("duration_sec"), "sec", a.duration_sec.map(Double.init), b.duration_sec.map(Double.init))
            append(m("weight_kg"), "kg", decToD(a.weight_kg), decToD(b.weight_kg))
            append(m("implement_count"), "count", a.implement_count.map(Double.init), b.implement_count.map(Double.init))
        }
    }

    private func buildStrengthMetrics(decoder: JSONDecoder, client: SupabaseClient) async throws {
        struct WMeta: Decodable {
            let duration_min: Int?
            let started_at: Date?
            let ended_at: Date?
        }
        struct WE: Decodable { let id: Int }
        struct SetRow: Decodable {
            let id: Int
            let workout_exercise_id: Int
            let set_number: Int
            let reps: Int?
            let weight_kg: Decimal?
            let rpe: Decimal?
            let rest_sec: Int?
        }
        struct StrengthStats {
            let exercisesCount: Int
            let setsCount: Int
            let totalReps: Int
            let totalVolumeKg: Double
            let maxWeightKg: Double?
            let maxSetVolumeKg: Double?
            let avgRpe: Double?
            let hardSetsCount: Int
            let totalRestSec: Double
            let avgRestSec: Double?
        }

        @Sendable
        func stats(for workoutId: Int) async throws -> StrengthStats {
            let exRes = try await client
                .from("workout_exercises")
                .select("id")
                .eq("workout_id", value: workoutId)
                .execute()
            let exIds = try decoder.decode([WE].self, from: exRes.data).map { $0.id }

            guard !exIds.isEmpty else {
                return StrengthStats(
                    exercisesCount: 0,
                    setsCount: 0,
                    totalReps: 0,
                    totalVolumeKg: 0,
                    maxWeightKg: nil,
                    maxSetVolumeKg: nil,
                    avgRpe: nil,
                    hardSetsCount: 0,
                    totalRestSec: 0,
                    avgRestSec: nil
                )
            }

            let setsRes = try await client
                .from("exercise_sets")
                .select("id, workout_exercise_id, set_number, reps, weight_kg, rpe, rest_sec")
                .in("workout_exercise_id", values: exIds)
                .execute()
            let sets = try decoder.decode([SetRow].self, from: setsRes.data)

            var setsByExercise: [Int: [SetRow]] = [:]
            for s in sets {
                setsByExercise[s.workout_exercise_id, default: []].append(s)
            }

            struct VolRow: Decodable { let total_volume_kg: Decimal? }
            var totalVolumeKg = 0.0
            do {
                let volRes = try await client
                    .from("vw_workout_volume")
                    .select("total_volume_kg")
                    .eq("workout_id", value: workoutId)
                    .single()
                    .execute()
                let volRow = try decoder.decode(VolRow.self, from: volRes.data)
                totalVolumeKg = volRow.total_volume_kg.map { NSDecimalNumber(decimal: $0).doubleValue } ?? 0
            } catch {
                totalVolumeKg = 0
            }

            var totalReps = 0
            var maxWeightKg: Double? = nil
            var maxSetVolumeKg: Double? = nil
            var rpeWeightedSum = 0.0
            var rpeWeightTotal = 0.0
            var hardSets = 0
            var setsCount = 0
            var totalRestSec = 0.0
            var restMultWeight = 0.0

            for (_, var rows) in setsByExercise {
                rows.sort { $0.id < $1.id }
                let nums = rows.map(\.set_number)
                let mults = strengthSetMultiplicities(sortedSetNumbers: nums)
                for (s, mult) in zip(rows, mults) {
                    setsCount += mult

                    let reps = max(s.reps ?? 0, 0)
                    let w = s.weight_kg.map { NSDecimalNumber(decimal: $0).doubleValue } ?? 0
                    totalReps += reps * mult

                    let setVol = Double(reps) * w

                    if w > 0 {
                        if let current = maxWeightKg {
                            if w > current { maxWeightKg = w }
                        } else {
                            maxWeightKg = w
                        }
                    }
                    if setVol > 0 {
                        if let current = maxSetVolumeKg {
                            if setVol > current { maxSetVolumeKg = setVol }
                        } else {
                            maxSetVolumeKg = setVol
                        }
                    }

                    if let rpeDec = s.rpe {
                        let r = NSDecimalNumber(decimal: rpeDec).doubleValue
                        let m = Double(mult)
                        rpeWeightedSum += r * m
                        rpeWeightTotal += m
                        if r >= 8.0 { hardSets += mult }
                    }

                    let restVal = max(s.rest_sec ?? 0, 0)
                    let mRest = Double(mult)
                    totalRestSec += Double(restVal) * mRest
                    if restVal > 0 {
                        restMultWeight += mRest
                    }
                }
            }

            let avgRpe = rpeWeightTotal > 0 ? (rpeWeightedSum / rpeWeightTotal) : nil
            let avgRestSec = restMultWeight > 0 ? (totalRestSec / restMultWeight) : nil

            return StrengthStats(
                exercisesCount: exIds.count,
                setsCount: setsCount,
                totalReps: totalReps,
                totalVolumeKg: totalVolumeKg,
                maxWeightKg: maxWeightKg,
                maxSetVolumeKg: maxSetVolumeKg,
                avgRpe: avgRpe,
                hardSetsCount: hardSets,
                totalRestSec: totalRestSec,
                avgRestSec: avgRestSec
            )
        }

        func bestDurationSec(_ meta: WMeta) -> Double? {
            if let m = meta.duration_min, m > 0 {
                return Double(m * 60)
            }
            if let s = meta.started_at, let e = meta.ended_at {
                let sec = e.timeIntervalSince(s)
                return sec > 0 ? sec : nil
            }
            return nil
        }

        async let lMetaRes = client
            .from("workouts")
            .select("duration_min, started_at, ended_at")
            .eq("id", value: currentWorkoutId)
            .single()
            .execute()
        async let rMetaRes = client
            .from("workouts")
            .select("duration_min, started_at, ended_at")
            .eq("id", value: rightWorkoutIdForBuild)
            .single()
            .execute()
        async let lStatsAsync = stats(for: currentWorkoutId)
        async let rStatsAsync = stats(for: rightWorkoutIdForBuild)

        let lMeta = try decoder.decode(WMeta.self, from: try await lMetaRes.data)
        let rMeta = try decoder.decode(WMeta.self, from: try await rMetaRes.data)
        let lStats = try await lStatsAsync
        let rStats = try await rStatsAsync

        let lDurSec = bestDurationSec(lMeta)
        let rDurSec = bestDurationSec(rMeta)

        func perMin(_ value: Double, durationSec: Double?) -> Double? {
            guard let durationSec, durationSec > 0 else { return nil }
            let minutes = durationSec / 60.0
            guard minutes > 0 else { return nil }
            return value / minutes
        }

        func add(_ metric: String, _ unit: String, _ lv: Double?, _ rv: Double?, to array: inout [ComparableMetric]) {
            guard let lv, let rv else { return }
            array.append(.init(metric: metric, unit: unit, left_value: lv, right_value: rv))
        }

        var out: [ComparableMetric] = []

        add("duration_sec", "sec", lDurSec, rDurSec, to: &out)
        add("total_volume_kg", "kg", lStats.totalVolumeKg, rStats.totalVolumeKg, to: &out)
        add("exercises_count", "count", Double(lStats.exercisesCount), Double(rStats.exercisesCount), to: &out)
        add("sets_count", "count", Double(lStats.setsCount), Double(rStats.setsCount), to: &out)
        add("total_reps", "count", Double(lStats.totalReps), Double(rStats.totalReps), to: &out)

        let lAvgWeightPerRep = (lStats.totalReps > 0) ? lStats.totalVolumeKg / Double(lStats.totalReps) : nil
        let rAvgWeightPerRep = (rStats.totalReps > 0) ? rStats.totalVolumeKg / Double(rStats.totalReps) : nil
        add("avg_weight_per_rep_kg", "kg_per_rep", lAvgWeightPerRep, rAvgWeightPerRep, to: &out)

        let lAvgWeightPerSet = (lStats.setsCount > 0) ? lStats.totalVolumeKg / Double(lStats.setsCount) : nil
        let rAvgWeightPerSet = (rStats.setsCount > 0) ? rStats.totalVolumeKg / Double(rStats.setsCount) : nil
        add("avg_weight_per_set_kg", "kg_per_set", lAvgWeightPerSet, rAvgWeightPerSet, to: &out)

        let lAvgRepsPerExercise = (lStats.exercisesCount > 0) ? Double(lStats.totalReps) / Double(lStats.exercisesCount) : nil
        let rAvgRepsPerExercise = (rStats.exercisesCount > 0) ? Double(rStats.totalReps) / Double(rStats.exercisesCount) : nil
        add("avg_reps_per_exercise", "reps_per_exercise", lAvgRepsPerExercise, rAvgRepsPerExercise, to: &out)

        let lAvgSetsPerExercise = (lStats.exercisesCount > 0) ? Double(lStats.setsCount) / Double(lStats.exercisesCount) : nil
        let rAvgSetsPerExercise = (rStats.exercisesCount > 0) ? Double(rStats.setsCount) / Double(rStats.exercisesCount) : nil
        add("avg_sets_per_exercise", "sets_per_exercise", lAvgSetsPerExercise, rAvgSetsPerExercise, to: &out)

        let lVolPerMin = perMin(lStats.totalVolumeKg, durationSec: lDurSec)
        let rVolPerMin = perMin(rStats.totalVolumeKg, durationSec: rDurSec)
        add("volume_per_min_kg", "kg_per_min", lVolPerMin, rVolPerMin, to: &out)

        let lSetsPerMin = perMin(Double(lStats.setsCount), durationSec: lDurSec)
        let rSetsPerMin = perMin(Double(rStats.setsCount), durationSec: rDurSec)
        add("sets_per_min", "sets_per_min", lSetsPerMin, rSetsPerMin, to: &out)

        let lRepsPerMin = perMin(Double(lStats.totalReps), durationSec: lDurSec)
        let rRepsPerMin = perMin(Double(rStats.totalReps), durationSec: rDurSec)
        add("reps_per_min", "reps_per_min", lRepsPerMin, rRepsPerMin, to: &out)
        add("max_weight_kg", "kg", lStats.maxWeightKg, rStats.maxWeightKg, to: &out)
        add("max_set_volume_kg", "kg", lStats.maxSetVolumeKg, rStats.maxSetVolumeKg, to: &out)
        add("avg_rpe", "rpe", lStats.avgRpe, rStats.avgRpe, to: &out)
        add("hard_sets_count", "count", Double(lStats.hardSetsCount), Double(rStats.hardSetsCount), to: &out)

        add("total_rest_sec", "sec", lStats.totalRestSec, rStats.totalRestSec, to: &out)
        add("avg_rest_sec", "sec", lStats.avgRestSec, rStats.avgRestSec, to: &out)
        func restPct(_ totalRest: Double, _ durationSec: Double?) -> Double? {
            guard let d = durationSec, d > 0 else { return nil }
            return 100.0 * totalRest / d
        }
        add("rest_pct_of_session", "pct", restPct(lStats.totalRestSec, lDurSec), restPct(rStats.totalRestSec, rDurSec), to: &out)

        await MainActor.run { metrics = out }
    }

    private func makeMetric(_ m: String, _ unit: String, _ lv: Double?, _ rv: Double?) -> ComparableMetric? {
        guard let lv, let rv else { return nil }
        return .init(metric: m, unit: unit, left_value: lv, right_value: rv)
    }
}

enum CompareWorkoutCandidateOrdering {
    static func sortForPicker(
        _ rows: [WorkoutDetailView.CompareCandidate],
        baselineWorkoutId: Int,
        kind: String
    ) async -> [WorkoutDetailView.CompareCandidate] {
        let byDateDesc: (WorkoutDetailView.CompareCandidate, WorkoutDetailView.CompareCandidate) -> Bool = {
            $0.started_at > $1.started_at
        }
        guard !rows.isEmpty else { return rows }

        do {
            switch kind.lowercased() {
            case "strength":
                return try await sortStrength(rows, baseline: baselineWorkoutId, byDateDesc: byDateDesc)
            case "sport":
                return try await sortSport(rows, baseline: baselineWorkoutId, byDateDesc: byDateDesc)
            case "cardio":
                return try await sortCardio(rows, baseline: baselineWorkoutId, byDateDesc: byDateDesc)
            default:
                return rows.sorted(by: byDateDesc)
            }
        } catch {
            return rows.sorted(by: byDateDesc)
        }
    }

    private static func sortStrength(
        _ rows: [WorkoutDetailView.CompareCandidate],
        baseline: Int,
        byDateDesc: (WorkoutDetailView.CompareCandidate, WorkoutDetailView.CompareCandidate) -> Bool
    ) async throws -> [WorkoutDetailView.CompareCandidate] {
        let ids = Array(Set([baseline] + rows.map(\.candidate_id)))
        let muscleByW = try await fetchPrimaryMusclesByWorkout(ids: ids)
        let baselineMuscles = muscleByW[baseline] ?? []

        func strengthTier(_ c: WorkoutDetailView.CompareCandidate) -> Int {
            guard !baselineMuscles.isEmpty else { return 2 }
            let cm = muscleByW[c.candidate_id] ?? []
            if cm.isEmpty { return 2 }
            if baselineMuscles == cm { return 0 }
            if !baselineMuscles.isDisjoint(with: cm) { return 1 }
            return 2
        }

        return rows.sorted { a, b in
            let ta = strengthTier(a), tb = strengthTier(b)
            if ta != tb { return ta < tb }
            return byDateDesc(a, b)
        }
    }

    private static func sortSport(
        _ rows: [WorkoutDetailView.CompareCandidate],
        baseline: Int,
        byDateDesc: (WorkoutDetailView.CompareCandidate, WorkoutDetailView.CompareCandidate) -> Bool
    ) async throws -> [WorkoutDetailView.CompareCandidate] {
        guard let raw = try await fetchBaselineSport(workoutId: baseline) else {
            return rows.sorted(by: byDateDesc)
        }
        let b = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !b.isEmpty else { return rows.sorted(by: byDateDesc) }
        func matches(_ c: WorkoutDetailView.CompareCandidate) -> Bool {
            (c.sport ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == b
        }
        return rows.sorted { a, b in
            let ma = matches(a), mb = matches(b)
            if ma != mb { return ma && !mb }
            return byDateDesc(a, b)
        }
    }

    private static func sortCardio(
        _ rows: [WorkoutDetailView.CompareCandidate],
        baseline: Int,
        byDateDesc: (WorkoutDetailView.CompareCandidate, WorkoutDetailView.CompareCandidate) -> Bool
    ) async throws -> [WorkoutDetailView.CompareCandidate] {
        guard let b = try await fetchBaselineCardioCode(workoutId: baseline), !b.isEmpty else {
            return rows.sorted(by: byDateDesc)
        }
        func normActivity(_ c: WorkoutDetailView.CompareCandidate) -> String {
            (c.activity ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        func matches(_ c: WorkoutDetailView.CompareCandidate) -> Bool {
            normActivity(c) == b
        }
        return rows.sorted { a, b in
            let ma = matches(a), mb = matches(b)
            if ma != mb { return ma && !mb }
            return byDateDesc(a, b)
        }
    }

    private static func fetchPrimaryMusclesByWorkout(ids: [Int]) async throws -> [Int: Set<String>] {
        guard !ids.isEmpty else { return [:] }
        let client = SupabaseManager.shared.client
        let res = try await client
            .from("workout_exercises")
            .select("workout_id, exercises(muscle_primary)")
            .in("workout_id", values: ids)
            .execute()
        struct MuscleRef: Decodable { let muscle_primary: String? }
        struct Row: Decodable {
            let workout_id: Int
            let exercises: MuscleRef?
        }
        let decoded = try JSONDecoder.supabase().decode([Row].self, from: res.data)
        var map: [Int: Set<String>] = [:]
        for r in decoded {
            let m = (r.exercises?.muscle_primary ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if m.isEmpty || m == "cardio" { continue }
            map[r.workout_id, default: []].insert(m)
        }
        return map
    }

    private static func fetchBaselineSport(workoutId: Int) async throws -> String? {
        let res = try await SupabaseManager.shared.client
            .from("sport_sessions")
            .select("sport")
            .eq("workout_id", value: workoutId)
            .limit(1)
            .execute()
        struct R: Decodable { let sport: String? }
        let rows = try JSONDecoder.supabase().decode([R].self, from: res.data)
        return rows.first?.sport
    }

    private static func fetchBaselineCardioCode(workoutId: Int) async throws -> String? {
        let res = try await SupabaseManager.shared.client
            .from("cardio_sessions")
            .select("activity_code, modality")
            .eq("workout_id", value: workoutId)
            .limit(1)
            .execute()
        struct R: Decodable {
            let activity_code: String?
            let modality: String?
        }
        let rows = try JSONDecoder.supabase().decode([R].self, from: res.data)
        guard let r = rows.first else { return nil }
        let raw = (r.activity_code?.isEmpty == false ? r.activity_code! : r.modality) ?? ""
        return raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
