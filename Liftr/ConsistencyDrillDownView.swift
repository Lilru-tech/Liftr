import SwiftUI
import Charts
import Supabase

struct ConsistencyDrillDownView: View {
    let rootKind: String
    let workoutMeta: [Int: (kind: String, durationMin: Int)]

    @State private var slices: [Slice] = []
    @State private var totalDurationMin: Int = 0
    @State private var loading = true
    @State private var error: String?

    struct Slice: Identifiable {
        let id: String
        let title: String
        let count: Int
        let durationMin: Int
    }

    var body: some View {
        Group {
            if loading {
                ProgressView().frame(maxWidth: .infinity, minHeight: 200)
            } else if let error {
                Text(error).foregroundStyle(.red).padding()
            } else if slices.isEmpty {
                Text("No breakdown for this period")
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                scrollContent
            }
        }
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private var navigationTitle: String {
        switch rootKind.lowercased() {
        case "sport": return "Sport detail"
        case "cardio": return "Cardio detail"
        case "strength": return "Strength detail"
        default: return "Detail"
        }
    }

    @ViewBuilder
    private var scrollContent: some View {
        ScrollView {
            VStack(spacing: 12) {
                if #available(iOS 17.0, *) {
                    Chart(slices) { s in
                        SectorMark(
                            angle: .value("Share", Double(totalDurationMin > 0 ? s.durationMin : s.count)),
                            innerRadius: .ratio(0.55),
                            angularInset: 1.5
                        )
                        .foregroundStyle(chartColor(for: s.title))
                    }
                    .frame(height: 220)
                    .padding(.horizontal)
                    .chartLegend(.hidden)
                    .chartPlotStyle { plotArea in
                        plotArea
                            .background(Color.gray.opacity(0.18))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }

                breakdownCard
            }
            .padding(.vertical, 8)
        }
    }

    private func chartColor(for title: String) -> Color {
        let palette: [Double] = [0.02, 0.12, 0.22, 0.45, 0.55, 0.65, 0.75, 0.82]
        let idx = abs(title.hashValue) % palette.count
        return Color(hue: palette[idx], saturation: 0.52, brightness: 0.94)
    }

    private var breakdownCard: some View {
        let ordered = slices.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        let summedSliceCounts = ordered.reduce(0) { $0 + $1.count }
        let uniqueWorkoutsInPeriod = workoutMeta.filter { $0.value.kind.lowercased() == rootKind.lowercased() }.count
        let footerWorkoutLabel = rootKind.lowercased() == "strength" ? uniqueWorkoutsInPeriod : summedSliceCounts
        return VStack(alignment: .leading, spacing: 12) {
            if rootKind.lowercased() == "strength" {
                Text("One session can count toward several muscles; workout totals may add up to more than your strength sessions.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(ordered) { s in
                let pctT = totalDurationMin > 0 ? Double(s.durationMin) / Double(totalDurationMin) : 0
                HStack(alignment: .center, spacing: 10) {
                    Circle()
                        .fill(chartColor(for: s.title))
                        .frame(width: 8, height: 8)
                    Text(s.title)
                        .font(.subheadline.weight(.medium))
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 2) {
                        if totalDurationMin > 0 {
                            Text("\(formatMinutes(s.durationMin)) · \(formatPercent(pctT))")
                                .font(.footnote.weight(.medium).monospacedDigit())
                            Text(s.count == 1 ? "1 workout" : "\(s.count) workouts")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        } else {
                            Text(s.count == 1 ? "1 workout" : "\(s.count) workouts")
                                .font(.footnote.weight(.medium).monospacedDigit())
                        }
                    }
                }
            }

            Divider().opacity(0.35)

            HStack(alignment: .firstTextBaseline) {
                Text("Total")
                    .font(.footnote.weight(.semibold))
                Spacer()
                Text("\(footerWorkoutLabel) workouts · \(formatMinutes(totalDurationMin))")
                    .font(.footnote.weight(.semibold).monospacedDigit())
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.18), lineWidth: 0.8)
        }
        .padding(.horizontal)
    }

    private func formatPercent(_ p: Double) -> String {
        let x = max(0, min(1, p))
        return String(format: "%.0f%%", x * 100)
    }

    private func formatMinutes(_ m: Int) -> String {
        guard m > 0 else { return "0m" }
        let h = m / 60
        let r = m % 60
        if h > 0 { return r > 0 ? "\(h)h \(r)m" : "\(h)h" }
        return "\(r)m"
    }

    private func load() async {
        await MainActor.run {
            loading = true
            error = nil
        }

        let ids = workoutMeta.filter { $0.value.kind.lowercased() == rootKind.lowercased() }.map(\.key)
        guard !ids.isEmpty else {
            await MainActor.run {
                slices = []
                totalDurationMin = 0
                loading = false
            }
            return
        }

        let decoder = JSONDecoder.supabase()
        let client = SupabaseManager.shared.client

        do {
            let result: [Slice]
            switch rootKind.lowercased() {
            case "sport":
                result = try await loadSport(ids: ids, decoder: decoder, client: client)
            case "cardio":
                result = try await loadCardio(ids: ids, decoder: decoder, client: client)
            case "strength":
                result = try await loadStrength(ids: ids, decoder: decoder, client: client)
            default:
                result = []
            }

            let totalM = result.reduce(0) { $0 + $1.durationMin }
            await MainActor.run {
                self.slices = result
                self.totalDurationMin = totalM
                self.loading = false
            }
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
                self.loading = false
            }
        }
    }

    private func loadSport(ids: [Int], decoder: JSONDecoder, client: SupabaseClient) async throws -> [Slice] {
        struct Row: Decodable {
            let workout_id: Int
            let sport: String?
        }
        let res = try await client
            .from("sport_sessions")
            .select("workout_id,sport")
            .in("workout_id", values: ids)
            .execute()
        let rows = try decoder.decode([Row].self, from: res.data)

        var firstSportByWorkout: [Int: String] = [:]
        for r in rows {
            let name = (r.sport ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            if firstSportByWorkout[r.workout_id] == nil {
                firstSportByWorkout[r.workout_id] = name
            }
        }

        return aggregateByLabel(
            workoutIds: ids,
            labelForWorkout: { wid in
                guard let s = firstSportByWorkout[wid] else { return nil }
                return displaySport(s)
            }
        )
    }

    private func loadCardio(ids: [Int], decoder: JSONDecoder, client: SupabaseClient) async throws -> [Slice] {
        struct Row: Decodable {
            let workout_id: Int
            let activity_code: String?
            let modality: String?
        }
        let res = try await client
            .from("cardio_sessions")
            .select("workout_id,activity_code,modality")
            .in("workout_id", values: ids)
            .execute()
        let rows = try decoder.decode([Row].self, from: res.data)

        var firstByWorkout: [Int: String] = [:]
        for r in rows {
            let raw = (r.activity_code?.isEmpty == false ? r.activity_code! : r.modality) ?? ""
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if firstByWorkout[r.workout_id] == nil {
                firstByWorkout[r.workout_id] = trimmed.lowercased()
            }
        }

        return aggregateByLabel(
            workoutIds: ids,
            labelForWorkout: { wid in
                guard let code = firstByWorkout[wid] else { return nil }
                return displayCardioCode(code)
            }
        )
    }

    private func loadStrength(ids: [Int], decoder: JSONDecoder, client: SupabaseClient) async throws -> [Slice] {
        struct MuscleRef: Decodable { let muscle_primary: String? }
        struct Row: Decodable {
            let workout_id: Int
            let exercises: MuscleRef?
        }
        let res = try await client
            .from("workout_exercises")
            .select("workout_id, exercises(muscle_primary)")
            .in("workout_id", values: ids)
            .execute()
        let rows = try decoder.decode([Row].self, from: res.data)

        var musclesByWorkout: [Int: Set<String>] = [:]
        for r in rows {
            let m = (r.exercises?.muscle_primary ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let key: String
            if m.isEmpty || m == "cardio" { key = "other" } else { key = m }
            musclesByWorkout[r.workout_id, default: []].insert(key)
        }

        var countBy: [String: Int] = [:]
        var minBy: [String: Int] = [:]

        for wid in ids {
            let dm = workoutMeta[wid]?.durationMin ?? 0
            let muscles = musclesByWorkout[wid] ?? ["other"]
            let n = max(1, muscles.count)
            let share = dm / n
            for m in muscles {
                let label = displayMuscle(m)
                countBy[label, default: 0] += 1
                minBy[label, default: 0] += share
            }
        }

        return countBy.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }.map { k in
            Slice(id: k, title: k, count: countBy[k] ?? 0, durationMin: minBy[k] ?? 0)
        }
    }

    private func aggregateByLabel(
        workoutIds: [Int],
        labelForWorkout: (Int) -> String?
    ) -> [Slice] {
        var countBy: [String: Int] = [:]
        var minBy: [String: Int] = [:]

        for wid in workoutIds {
            let dm = workoutMeta[wid]?.durationMin ?? 0
            let label = labelForWorkout(wid) ?? "Other"
            countBy[label, default: 0] += 1
            minBy[label, default: 0] += dm
        }

        return countBy.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }.map { k in
            Slice(id: k, title: k, count: countBy[k] ?? 0, durationMin: minBy[k] ?? 0)
        }
    }

    private func displaySport(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).capitalized
    }

    private func displayCardioCode(_ code: String) -> String {
        let c = code.lowercased()
        if let t = CardioActivityType(rawValue: c) {
            return t.label
        }
        return c.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private func displayMuscle(_ key: String) -> String {
        if key == "other" { return "Other" }
        return key.replacingOccurrences(of: "_", with: " ").capitalized
    }
}
