import SwiftUI
import Charts
import Supabase

struct ConsistencyDrillDownView: View {
    let rootKind: String
    let workoutMeta: [Int: ConsistencyWorkoutMeta]

    @AppStorage("consistencyDrilldownChartMetric") private var consistencyDrilldownChartMetricRaw: String =
        ConsistencyChartMetric.duration.rawValue

    @State private var slices: [Slice] = []
    @State private var totalDurationMin: Int = 0
    @State private var loading = true
    @State private var error: String?

    struct Slice: Identifiable {
        let id: String
        let title: String
        let count: Int
        let durationMin: Int
        let score: Double
        let kcal: Double
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

    private var effectiveDrilldownMetric: ConsistencyChartMetric {
        let chosen = ConsistencyChartMetric(rawValue: consistencyDrilldownChartMetricRaw) ?? .duration
        func total(_ m: ConsistencyChartMetric) -> Double {
            slices.reduce(0.0) {
                $0 + m.measure(durationMin: $1.durationMin, count: $1.count, score: $1.score, kcal: $1.kcal)
            }
        }
        if total(chosen) > 0 { return chosen }
        for m in ConsistencyChartMetric.allCases where total(m) > 0 {
            return m
        }
        return chosen
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
        let metric = effectiveDrilldownMetric
        ScrollView {
            VStack(spacing: 12) {
                Picker("Detail chart", selection: $consistencyDrilldownChartMetricRaw) {
                    ForEach(ConsistencyChartMetric.allCases) { m in
                        Text(m.pickerLabel).tag(m.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                if #available(iOS 17.0, *) {
                    Chart(slices) { s in
                        SectorMark(
                            angle: .value(
                                metric.chartAxisLabel,
                                metric.measure(
                                    durationMin: s.durationMin,
                                    count: s.count,
                                    score: s.score,
                                    kcal: s.kcal
                                )
                            ),
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

                drilldownBreakdownCard(metric: metric)
            }
            .padding(.vertical, 8)
        }
    }

    private var chartColorsByTitle: [String: Color] {
        let titles = Array(Set(slices.map(\.title))).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
        guard !titles.isEmpty else { return [:] }
        let phi = 0.618_033_988_749_895
        var hue = 0.07
        var map: [String: Color] = [:]
        for (i, title) in titles.enumerated() {
            let h = hue.truncatingRemainder(dividingBy: 1.0)
            let saturation = 0.62 + Double(i % 4) * 0.07
            let brightness = 0.86 + Double((i / 4) % 3) * 0.05
            map[title] = Color(hue: h, saturation: saturation, brightness: brightness)
            hue += phi
        }
        return map
    }

    private func chartColor(for title: String) -> Color {
        chartColorsByTitle[title] ?? Color(white: 0.55)
    }

    private func drilldownBreakdownCard(metric: ConsistencyChartMetric) -> some View {
        let ordered = slices.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        let summedSliceCounts = ordered.reduce(0) { $0 + $1.count }
        let uniqueWorkoutsInPeriod = workoutMeta.filter { $0.value.kind.lowercased() == rootKind.lowercased() }.count
        let footerWorkoutLabel = rootKind.lowercased() == "strength" ? uniqueWorkoutsInPeriod : summedSliceCounts
        let totalMetricAmount = ordered.reduce(0.0) {
            $0 + metric.measure(durationMin: $1.durationMin, count: $1.count, score: $1.score, kcal: $1.kcal)
        }
        let totalScore = ordered.reduce(0.0) { $0 + $1.score }
        let totalKcal = ordered.reduce(0.0) { $0 + $1.kcal }
        return VStack(alignment: .leading, spacing: 12) {
            if rootKind.lowercased() == "strength" {
                Text("One session can count toward several muscles; workout totals may add up to more than your strength sessions.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(ordered) { s in
                let v = metric.measure(durationMin: s.durationMin, count: s.count, score: s.score, kcal: s.kcal)
                let pct = totalMetricAmount > 0 ? v / totalMetricAmount : 0
                HStack(alignment: .center, spacing: 10) {
                    Circle()
                        .fill(chartColor(for: s.title))
                        .frame(width: 8, height: 8)
                    Text(s.title)
                        .font(.subheadline.weight(.medium))
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(primaryDrilldownRowTitle(slice: s, metric: metric, pct: pct))
                            .font(.footnote.weight(.medium).monospacedDigit())
                        Text(secondaryDrilldownRowSubtitle(slice: s, metric: metric))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }

            Divider().opacity(0.35)

            HStack(alignment: .firstTextBaseline) {
                Text("Total")
                    .font(.footnote.weight(.semibold))
                Spacer()
                Text(drilldownFooterLine(
                    footerWorkoutLabel: footerWorkoutLabel,
                    totalScore: totalScore,
                    totalKcal: totalKcal
                ))
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

    private func primaryDrilldownRowTitle(slice: Slice, metric: ConsistencyChartMetric, pct: Double) -> String {
        let pctStr = formatPercent(pct)
        switch metric {
        case .duration:
            return "\(formatMinutes(slice.durationMin)) · \(pctStr)"
        case .workouts:
            return "\(slice.count == 1 ? "1 workout" : "\(slice.count) workouts") · \(pctStr)"
        case .score:
            return "\(formatDrillPoints(slice.score)) pts · \(pctStr)"
        case .calories:
            return "\(formatDrillKcal(slice.kcal)) kcal · \(pctStr)"
        }
    }

    private func secondaryDrilldownRowSubtitle(slice: Slice, metric: ConsistencyChartMetric) -> String {
        var parts: [String] = []
        if metric != .workouts {
            parts.append(slice.count == 1 ? "1 workout" : "\(slice.count) workouts")
        }
        if metric != .duration, slice.durationMin > 0 {
            parts.append(formatMinutes(slice.durationMin))
        }
        if metric != .score, slice.score > 0 {
            parts.append("\(formatDrillPoints(slice.score)) pts")
        }
        if metric != .calories, slice.kcal > 0 {
            parts.append("\(formatDrillKcal(slice.kcal)) kcal")
        }
        return parts.isEmpty ? " " : parts.joined(separator: " · ")
    }

    private func drilldownFooterLine(footerWorkoutLabel: Int, totalScore: Double, totalKcal: Double) -> String {
        var parts: [String] = [
            "\(footerWorkoutLabel) workouts",
            "\(formatMinutes(totalDurationMin)) total",
        ]
        if totalScore > 0 {
            parts.append("\(formatDrillPoints(totalScore)) pts")
        }
        if totalKcal > 0 {
            parts.append("\(formatDrillKcal(totalKcal)) kcal")
        }
        return parts.joined(separator: " · ")
    }

    private func formatDrillPoints(_ x: Double) -> String {
        let r = round(x)
        if abs(x - r) < 0.05 { return String(format: "%.0f", r) }
        return String(format: "%.1f", x)
    }

    private func formatDrillKcal(_ x: Double) -> String {
        if x >= 100 { return String(format: "%.0f", x) }
        if x >= 10 { return String(format: "%.1f", x) }
        return String(format: "%.2f", x)
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
        var scoreBy: [String: Double] = [:]
        var kcalBy: [String: Double] = [:]

        for wid in ids {
            let meta = workoutMeta[wid]
            let dm = meta?.durationMin ?? 0
            let sc = meta?.score ?? 0
            let kc = meta?.kcal ?? 0
            let muscles = musclesByWorkout[wid] ?? ["other"]
            let n = max(1, muscles.count)
            let shareDur = dm / n
            let shareSc = sc / Double(n)
            let shareKc = kc / Double(n)
            for m in muscles {
                let label = displayMuscle(m)
                countBy[label, default: 0] += 1
                minBy[label, default: 0] += shareDur
                scoreBy[label, default: 0] += shareSc
                kcalBy[label, default: 0] += shareKc
            }
        }

        return countBy.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }.map { k in
            Slice(
                id: k,
                title: k,
                count: countBy[k] ?? 0,
                durationMin: minBy[k] ?? 0,
                score: scoreBy[k] ?? 0,
                kcal: kcalBy[k] ?? 0
            )
        }
    }

    private func aggregateByLabel(
        workoutIds: [Int],
        labelForWorkout: (Int) -> String?
    ) -> [Slice] {
        var countBy: [String: Int] = [:]
        var minBy: [String: Int] = [:]
        var scoreBy: [String: Double] = [:]
        var kcalBy: [String: Double] = [:]

        for wid in workoutIds {
            let meta = workoutMeta[wid]
            let dm = meta?.durationMin ?? 0
            let sc = meta?.score ?? 0
            let kc = meta?.kcal ?? 0
            let label = labelForWorkout(wid) ?? "Other"
            countBy[label, default: 0] += 1
            minBy[label, default: 0] += dm
            scoreBy[label, default: 0] += sc
            kcalBy[label, default: 0] += kc
        }

        return countBy.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }.map { k in
            Slice(
                id: k,
                title: k,
                count: countBy[k] ?? 0,
                durationMin: minBy[k] ?? 0,
                score: scoreBy[k] ?? 0,
                kcal: kcalBy[k] ?? 0
            )
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
