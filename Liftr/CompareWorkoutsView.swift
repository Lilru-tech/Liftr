import SwiftUI
import Supabase

struct CompareWorkoutsView: View {
    let currentWorkoutId: Int
    let myOtherWorkoutId: Int

    struct ComparableMetric: Identifiable, Decodable {
        let metric: String
        let unit: String
        let left_value: Double
        let right_value: Double
        var id: String { metric }
        var diff: Double { left_value - right_value }
        var diffPct: Double? {
            guard right_value != 0 else { return nil }
            let pct = (left_value - right_value) / right_value * 100.0
            return abs(pct) < 0.05 ? 0.0 : pct
        }
    }

    @Environment(\.dismiss) private var dismiss
    @State private var loading = false
    @State private var error: String?
    @State private var metrics: [ComparableMetric] = []
    @State private var workoutKind: String? = nil
    @State private var bothMine = false
    private static let leftColor  = Color(red: 0.82, green: 0.12, blue: 0.18)
    private static let rightColor = Color(red: 0.02, green: 0.55, blue: 0.32)

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
                HStack(spacing: 6) {
                    Text(bothMine ? "Yours" : "His/Her").foregroundStyle(CompareWorkoutsView.leftColor)
                    Text("vs").foregroundStyle(.secondary)
                    Text("Yours").foregroundStyle(CompareWorkoutsView.rightColor)
                    Text("— \(k.capitalized)").foregroundStyle(.secondary)
                }
                .font(.subheadline)
            }

            if loading {
                ProgressView().padding(.top, 12)
            } else if let e = error {
                Text(e).foregroundStyle(.red).padding(.top, 12)
            } else if metrics.isEmpty {
                Text("Nothing to compare for these workouts. Please add more data to your workout")
                    .foregroundStyle(.secondary)
                    .padding(.top, 12)
            } else {
                List(metrics) { m in
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

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(Self.prettyMetric(m.metric))
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    if let pct = m.diffPct {
                        Text(pctString(pct))
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.ultraThinMaterial, in: Capsule())
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
                    let outerW  = geo.size.width
                    let usableW = max(0, outerW - 20)
                    let maxV    = max(m.left_value, m.right_value, 0.0001)
                    let leftW   = CGFloat(m.left_value  / maxV) * usableW
                    let rightW  = CGFloat(m.right_value / maxV) * usableW

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
        private static func prettyMetric(_ m: String) -> String {
            switch m {
            case "distance_km": return "Distance"
            case "duration_sec": return "Duration"
            case "avg_pace_sec_per_km": return "Avg pace"
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

            default: return m.replacingOccurrences(of: "_", with: " ").capitalized
            }
        }
    }

    private func load() async {
        await MainActor.run { loading = true; error = nil; metrics = [] }
        defer { Task { await MainActor.run { loading = false } } }

        let client = SupabaseManager.shared.client
        let decoder = JSONDecoder.supabase()

        struct WRow: Decodable { let id: Int; let kind: String; let title: String?; let user_id: UUID }

        do {
            let lRes = try await client.from("workouts").select("id, kind, title, user_id").eq("id", value: currentWorkoutId).single().execute()
            let rRes = try await client.from("workouts").select("id, kind, title, user_id").eq("id", value: myOtherWorkoutId).single().execute()
            let L = try decoder.decode(WRow.self, from: lRes.data)
            let R = try decoder.decode(WRow.self, from: rRes.data)

            guard L.kind.lowercased() == R.kind.lowercased() else {
                await MainActor.run { error = "Workouts are different types (\(L.kind) vs \(R.kind))."; }
                return
            }

            await MainActor.run {
                workoutKind = L.kind
                bothMine = (L.user_id == R.user_id)
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
    }

    private func buildCardioMetrics(decoder: JSONDecoder, client: SupabaseClient) async throws {
        let lQ = try await client.from("cardio_sessions").select("*").eq("workout_id", value: currentWorkoutId).single().execute()
        let rQ = try await client.from("cardio_sessions").select("*").eq("workout_id", value: myOtherWorkoutId).single().execute()
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

        add("distance_km", "km", d(L.distance_km), d(R.distance_km))
        add("duration_sec", "sec", L.duration_sec.map(Double.init), R.duration_sec.map(Double.init))
        add("avg_pace_sec_per_km", "sec_per_km", L.avg_pace_sec_per_km.map(Double.init), R.avg_pace_sec_per_km.map(Double.init))
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
            .eq("workout_id", value: myOtherWorkoutId).single().execute()
        async let lW = client.from("workouts")
            .select("duration_min, started_at, ended_at")
            .eq("id", value: currentWorkoutId).single().execute()
        async let rW = client.from("workouts")
            .select("duration_min, started_at, ended_at")
            .eq("id", value: myOtherWorkoutId).single().execute()

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

    private func buildStrengthMetrics(decoder: JSONDecoder, client: SupabaseClient) async throws {
        struct WMeta: Decodable {
            let duration_min: Int?
            let started_at: Date?
            let ended_at: Date?
        }
        struct WE: Decodable { let id: Int }
        struct SetRow: Decodable {
            let reps: Int?
            let weight_kg: Decimal?
            let rpe: Decimal?
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
                    hardSetsCount: 0
                )
            }

            let setsRes = try await client
                .from("exercise_sets")
                .select("reps, weight_kg, rpe")
                .in("workout_exercise_id", values: exIds)
                .execute()
            let sets = try decoder.decode([SetRow].self, from: setsRes.data)

            var totalReps = 0
            var totalVolumeKg = 0.0
            var maxWeightKg: Double? = nil
            var maxSetVolumeKg: Double? = nil
            var rpeSum = 0.0
            var rpeCount = 0
            var hardSets = 0

            for s in sets {
                let reps = max(s.reps ?? 0, 0)
                let w = s.weight_kg.map { NSDecimalNumber(decimal: $0).doubleValue } ?? 0
                totalReps += reps

                let setVol = Double(reps) * w
                totalVolumeKg += setVol

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
                    rpeSum += r
                    rpeCount += 1
                    if r >= 8.0 { hardSets += 1 }
                }
            }

            let avgRpe = rpeCount > 0 ? (rpeSum / Double(rpeCount)) : nil

            return StrengthStats(
                exercisesCount: exIds.count,
                setsCount: sets.count,
                totalReps: totalReps,
                totalVolumeKg: totalVolumeKg,
                maxWeightKg: maxWeightKg,
                maxSetVolumeKg: maxSetVolumeKg,
                avgRpe: avgRpe,
                hardSetsCount: hardSets
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
            .eq("id", value: myOtherWorkoutId)
            .single()
            .execute()
        async let lStatsAsync = stats(for: currentWorkoutId)
        async let rStatsAsync = stats(for: myOtherWorkoutId)

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

        await MainActor.run { metrics = out }
    }

    private func makeMetric(_ m: String, _ unit: String, _ lv: Double?, _ rv: Double?) -> ComparableMetric? {
        guard let lv, let rv else { return nil }
        return .init(metric: m, unit: unit, left_value: lv, right_value: rv)
    }
}
