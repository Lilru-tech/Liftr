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
            return (left_value - right_value) / right_value * 100.0
        }
    }

    @Environment(\.dismiss) private var dismiss
    @State private var loading = false
    @State private var error: String?
    @State private var metrics: [ComparableMetric] = []
    @State private var workoutKind: String? = nil

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
                    Text("His/Her").foregroundStyle(.red)
                    Text("vs").foregroundStyle(.secondary)
                    Text("Yours").foregroundStyle(.green)
                    Text("— \(k.capitalized)").foregroundStyle(.secondary)
                }
                .font(.subheadline)
            }

            if loading {
                ProgressView().padding(.top, 12)
            } else if let e = error {
                Text(e).foregroundStyle(.red).padding(.top, 12)
            } else if metrics.isEmpty {
                Text("Nothing to compare for these workouts.")
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
                        .foregroundStyle(.red)
                    Text("vs")
                        .font(.caption)
                        .foregroundStyle(.secondary.opacity(0.7))
                    Text(formatValue(m.right_value, unit: m.unit))
                        .font(.caption)
                        .foregroundStyle(.green)
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
                                    gradient: Gradient(colors: [Color.red, Color.red.opacity(0.7)]),
                                    startPoint: .leading, endPoint: .trailing
                                ))
                                .frame(width: leftW, height: 10)
                                .shadow(color: Color.red.opacity(0.18), radius: 1, x: 0, y: 0)

                            Capsule()
                                .fill(LinearGradient(
                                    gradient: Gradient(colors: [Color.green, Color.green.opacity(0.7)]),
                                    startPoint: .leading, endPoint: .trailing
                                ))
                                .frame(width: rightW, height: 10)
                                .shadow(color: Color.green.opacity(0.18), radius: 1, x: 0, y: 0)
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
            default: return m.replacingOccurrences(of: "_", with: " ").capitalized
            }
        }
    }

    private func load() async {
        await MainActor.run { loading = true; error = nil; metrics = [] }
        defer { Task { await MainActor.run { loading = false } } }

        let client = SupabaseManager.shared.client
        let decoder = JSONDecoder.supabase()

        struct WRow: Decodable { let id: Int; let kind: String; let title: String? }

        do {
            let lRes = try await client.from("workouts").select("id, kind, title").eq("id", value: currentWorkoutId).single().execute()
            let rRes = try await client.from("workouts").select("id, kind, title").eq("id", value: myOtherWorkoutId).single().execute()
            let L = try decoder.decode(WRow.self, from: lRes.data)
            let R = try decoder.decode(WRow.self, from: rRes.data)

            guard L.kind.lowercased() == R.kind.lowercased() else {
                await MainActor.run { error = "Workouts are different types (\(L.kind) vs \(R.kind))."; }
                return
            }

            await MainActor.run {
                workoutKind = L.kind
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
        let lQ = try await client.from("sport_sessions").select("id, sport, duration_sec, score_for, score_against").eq("workout_id", value: currentWorkoutId).single().execute()
        let rQ = try await client.from("sport_sessions").select("id, sport, duration_sec, score_for, score_against").eq("workout_id", value: myOtherWorkoutId).single().execute()
        let L = try decoder.decode(SportRow.self, from: lQ.data)
        let R = try decoder.decode(SportRow.self, from: rQ.data)

        let ls = L.sport.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let rs = R.sport.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard ls == rs else {
            await MainActor.run { error = "Different sports (\(ls) vs \(rs))." }
            return
        }

        var out: [ComparableMetric] = []
        func add(_ metric: String, _ unit: String, _ lv: Double?, _ rv: Double?) {
            guard let lv, let rv else { return }
            out.append(.init(metric: metric, unit: unit, left_value: lv, right_value: rv))
        }

        add("duration_sec", "sec", L.duration_sec.map(Double.init), R.duration_sec.map(Double.init))
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

        case "football", "handball", "hockey", "rugby":
            struct FB: Decodable {
                let minutes_played: Int?; let goals: Int?; let assists: Int?; let shots_on_target: Int?
                let passes_completed: Int?; let passes_attempted: Int?
                let tackles: Int?; let interceptions: Int?; let saves: Int?
                let yellow_cards: Int?; let red_cards: Int?
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

        default:
            break
        }

        await MainActor.run { metrics = out }
    }

    private func buildStrengthMetrics(decoder: JSONDecoder, client: SupabaseClient) async throws {
        struct V: Decodable { let total_volume_kg: Decimal? }
        @Sendable func volume(for id: Int) async throws -> Double? {
            do {
                let q = try await client.from("vw_workout_volume").select("total_volume_kg").eq("workout_id", value: id).single().execute()
                let v = try decoder.decode(V.self, from: q.data).total_volume_kg
                return v.map { NSDecimalNumber(decimal: $0).doubleValue }
            } catch { return nil }
        }

        @Sendable func exercisesCount(for id: Int) async throws -> Int? {
            let q = try await client.from("workout_exercises").select("id", head: true, count: .exact).eq("workout_id", value: id).execute()
            return q.count
        }

        @Sendable func setsCount(for id: Int) async throws -> Int? {
            let idsQ = try await client.from("workout_exercises").select("id").eq("workout_id", value: id).execute()
            struct Row: Decodable { let id: Int }
            let ids = try decoder.decode([Row].self, from: idsQ.data).map { $0.id }
            guard !ids.isEmpty else { return 0 }
            let sQ = try await client.from("exercise_sets").select("id", head: true, count: .exact).in("workout_exercise_id", values: ids).execute()
            return sQ.count
        }

        async let lVol = volume(for: currentWorkoutId)
        async let rVol = volume(for: myOtherWorkoutId)
        async let lEx  = exercisesCount(for: currentWorkoutId)
        async let rEx  = exercisesCount(for: myOtherWorkoutId)
        async let lSets = setsCount(for: currentWorkoutId)
        async let rSets = setsCount(for: myOtherWorkoutId)

        let out = [
            makeMetric("total_volume_kg", "kg", try await lVol, try await rVol),
            makeMetric("exercises_count", "count", (try await lEx).map(Double.init), (try await rEx).map(Double.init)),
            makeMetric("sets_count", "count", (try await lSets).map(Double.init), (try await rSets).map(Double.init))
        ].compactMap { $0 }

        await MainActor.run { metrics = out }
    }

    private func makeMetric(_ m: String, _ unit: String, _ lv: Double?, _ rv: Double?) -> ComparableMetric? {
        guard let lv, let rv else { return nil }
        return .init(metric: m, unit: unit, left_value: lv, right_value: rv)
    }
}
