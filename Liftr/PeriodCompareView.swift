import SwiftUI
import Supabase
import Charts

private struct PeriodCompareSummary: Decodable {
    let workout_count: Int
    let duration_min: Int64
    let calories_kcal: Double
    let score: Double
    let distance_km: Double
    let volume_kg: Double
}

private struct PeriodCompareBreakdownRow: Decodable {
    let label: String
    let workout_count: Int
    let duration_min: Int64
    let calories_kcal: Double
    let score: Double
    let distance_km: Double
    let volume_kg: Double
}

private struct PeriodCompareSide: Decodable {
    let summary: PeriodCompareSummary
    let breakdown: [PeriodCompareBreakdownRow]
}

private struct PeriodCompareRoot: Decodable {
    let period_a: PeriodCompareSide
    let period_b: PeriodCompareSide
}

private struct PeriodSummaryBarPoint: Identifiable {
    var id: String { "\(periodKey)|\(metricKey)" }
    let metricKey: String
    let periodKey: String
    let periodLabel: String
    let value: Double
}

private enum PeriodCompareKind: String, CaseIterable, Identifiable {
    case all, strength, cardio, sport
    var id: String { rawValue }
    var label: String {
        switch self {
        case .all: return "All"
        case .strength: return "Strength"
        case .cardio: return "Cardio"
        case .sport: return "Sport"
        }
    }
}

private enum OverviewChartMetric: String, Identifiable {
    case overall
    case workouts, time, calories, score, distance, volume
    var id: String { rawValue }
    var shortTitle: String {
        switch self {
        case .overall: return "Overall"
        case .workouts: return "Workouts"
        case .time: return "Time"
        case .calories: return "Calories"
        case .score: return "Score"
        case .distance: return "km"
        case .volume: return "Vol (kg)"
        }
    }
    func value(from s: PeriodCompareSummary) -> Double {
        switch self {
        case .overall: return 0
        case .workouts: return Double(s.workout_count)
        case .time: return Double(s.duration_min)
        case .calories: return s.calories_kcal
        case .score: return s.score
        case .distance: return s.distance_km
        case .volume: return s.volume_kg
        }
    }
}

private func overallBalancePcts(a: PeriodCompareSummary, b: PeriodCompareSummary) -> (pctA: Double, pctB: Double) {
    let pairs: [(Double, Double)] = [
        (Double(a.workout_count), Double(b.workout_count)),
        (Double(a.duration_min), Double(b.duration_min)),
        (a.calories_kcal, b.calories_kcal),
        (a.score, b.score)
    ]
    var sumA = 0.0
    for (x, y) in pairs {
        let t = x + y
        sumA += t <= 0 ? 50.0 : 100.0 * x / t
    }
    let avgA = sumA / Double(pairs.count)
    return (avgA, 100.0 - avgA)
}

private func availableOverviewMetrics(a: PeriodCompareSide, b: PeriodCompareSide) -> [OverviewChartMetric] {
    var m: [OverviewChartMetric] = [.overall, .workouts, .time, .calories, .score]
    if a.summary.distance_km > 0 || b.summary.distance_km > 0 { m.append(.distance) }
    if a.summary.volume_kg > 0 || b.summary.volume_kg > 0 { m.append(.volume) }
    return m
}

private enum PeriodDatePreset: String, CaseIterable, Identifiable {
    case sevenVsSeven
    case weekAligned
    case twentyEightVsTwentyEight
    var id: String { rawValue }

    func label(crossUser: Bool) -> String {
        if crossUser {
            switch self {
            case .sevenVsSeven: return "Last 7 days (same window)"
            case .weekAligned: return "This week (same window)"
            case .twentyEightVsTwentyEight: return "Last 28 days (same window)"
            }
        }
        switch self {
        case .sevenVsSeven: return "7 vs 7 days"
        case .weekAligned: return "This week vs aligned last week"
        case .twentyEightVsTwentyEight: return "28 vs 28 days"
        }
    }
}

private func inclusiveDayCount(start: Date, endInclusive: Date, cal: Calendar) -> Int {
    let s = cal.startOfDay(for: start)
    let e = cal.startOfDay(for: endInclusive)
    return cal.dateComponents([.day], from: s, to: e).day! + 1
}

private func relDeltaCaption(va: Double, vb: Double) -> String? {
    guard va > 0 || vb > 0 else { return nil }
    if va <= 0 { return "B vs A: new (A was 0)" }
    let pct = 100.0 * (vb - va) / va
    return String(format: "B vs A: %+d%%", Int(round(pct)))
}

struct PeriodCompareView: View {
    let viewerUserId: UUID
    @Environment(\.dismiss) private var dismiss

    @State private var kind: PeriodCompareKind = .all
    @State private var userBId: UUID
    @State private var followees: [LightweightProfile] = []
    @State private var loadingFollowees = false
    @State private var loadingCompare = false
    @State private var error: String?
    @State private var resultA: PeriodCompareSide?
    @State private var resultB: PeriodCompareSide?
    @State private var overviewMetric: OverviewChartMetric = .overall

    @State private var periodAStart: Date
    @State private var periodAEndInclusive: Date
    @State private var periodBStart: Date
    @State private var periodBEndInclusive: Date
    @State private var figuresPerDay: Bool = false

    private let chartPeriodA = "A"
    private let chartPeriodB = "B"

    init(viewerUserId: UUID) {
        self.viewerUserId = viewerUserId
        _userBId = State(initialValue: viewerUserId)
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let aStart = cal.date(byAdding: .day, value: -14, to: today) ?? today
        let aEnd = cal.date(byAdding: .day, value: -8, to: today) ?? today
        let bStart = cal.date(byAdding: .day, value: -7, to: today) ?? today
        _periodAStart = State(initialValue: aStart)
        _periodAEndInclusive = State(initialValue: aEnd)
        _periodBStart = State(initialValue: bStart)
        _periodBEndInclusive = State(initialValue: today)
    }

    var body: some View {
        NavigationStack {
            GradientBackground {
                Form {
                    Section {
                        SectionCard {
                            FieldRowPlain("Kind") {
                                Picker("", selection: $kind) {
                                    ForEach(PeriodCompareKind.allCases) { k in
                                        Text(k.label).tag(k)
                                    }
                                }
                                .pickerStyle(.menu)
                            }
                            Divider()
                            FieldRowPlain("Compare with") {
                                Picker("", selection: $userBId) {
                                    Text("Me (same user)").tag(viewerUserId)
                                    ForEach(followees) { p in
                                        Text(p.username ?? p.user_id.uuidString.prefix(8).description).tag(p.user_id)
                                    }
                                }
                                .pickerStyle(.menu)
                                .disabled(loadingFollowees)
                            }
                            Text("Only workouts saved in Liftr in these date ranges. Not a full “who’s fitter” comparison.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            if userBId != viewerUserId {
                                Text("Your totals use Period A dates; the other person uses Period B. Quick ranges set the same window on both sides so the comparison is fair.")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Divider()
                            Text("Quick ranges")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(PeriodDatePreset.allCases) { p in
                                        Button {
                                            applyDatePreset(p)
                                        } label: {
                                            Text(p.label(crossUser: userBId != viewerUserId))
                                                .font(.caption)
                                                .lineLimit(2)
                                                .multilineTextAlignment(.center)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 8)
                                                .background(Color.primary.opacity(0.08))
                                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    } header: {
                        Text("SETUP").foregroundStyle(.secondary)
                    }
                    .listRowBackground(Color.clear)

                    Section {
                        SectionCard {
                            FieldRowPlain("Start") {
                                DatePicker("", selection: $periodAStart, displayedComponents: .date)
                            }
                            Divider()
                            FieldRowPlain("End (inclusive)") {
                                DatePicker("", selection: $periodAEndInclusive, displayedComponents: .date)
                            }
                        }
                    } header: {
                        Text("PERIOD A (YOU)").foregroundStyle(.secondary)
                    }
                    .listRowBackground(Color.clear)

                    Section {
                        SectionCard {
                            FieldRowPlain("Start") {
                                DatePicker("", selection: $periodBStart, displayedComponents: .date)
                            }
                            Divider()
                            FieldRowPlain("End (inclusive)") {
                                DatePicker("", selection: $periodBEndInclusive, displayedComponents: .date)
                            }
                        }
                    } header: {
                        Text("PERIOD B").foregroundStyle(.secondary)
                    }
                    .listRowBackground(Color.clear)

                    Section {
                        SectionCard {
                            Button {
                                Task { await runCompare() }
                            } label: {
                                HStack {
                                    Spacer()
                                    if loadingCompare {
                                        ProgressView()
                                        Text("Comparing…")
                                    } else {
                                        Text("Compare").fontWeight(.semibold)
                                    }
                                    Spacer()
                                }
                            }
                            .disabled(loadingCompare || loadingFollowees)
                        }
                    }
                    .listRowBackground(Color.clear)

                    if let error {
                        Section {
                            SectionCard {
                                Text(error).foregroundStyle(.red)
                            }
                        }
                        .listRowBackground(Color.clear)
                    }

                    if let a = resultA, let b = resultB {
                        let cal = Calendar.current
                        let daysA = inclusiveDayCount(start: periodAStart, endInclusive: periodAEndInclusive, cal: cal)
                        let daysB = inclusiveDayCount(start: periodBStart, endInclusive: periodBEndInclusive, cal: cal)
                        if daysA != daysB {
                            Section {
                                SectionCard {
                                    Text("Periods have different lengths — totals aren’t directly comparable. Use “per day” or pick matching ranges.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .listRowBackground(Color.clear)
                        }
                        if a.summary.workout_count == 0 && b.summary.workout_count == 0 {
                            Section {
                                SectionCard {
                                    Text("No logged workouts in either period for this filter.")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .listRowBackground(Color.clear)
                        } else {
                            if a.summary.workout_count == 0 {
                                Section {
                                    SectionCard {
                                        Text("No logged workouts in period A for this filter.")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .listRowBackground(Color.clear)
                            }
                            if b.summary.workout_count == 0 {
                                Section {
                                    SectionCard {
                                        Text("No logged workouts in period B for this filter.")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .listRowBackground(Color.clear)
                            }
                        }
                        Section {
                            SectionCard {
                                let avail = availableOverviewMetrics(a: a, b: b)
                                Picker("Metric to show", selection: $overviewMetric) {
                                    ForEach(avail) { m in
                                        Text(m.shortTitle).tag(m)
                                    }
                                }
                                .pickerStyle(.menu)
                                overviewSingleChart(a: a, b: b, metric: overviewMetric)
                                    .frame(height: 200)
                                chartLegend()
                            }
                        } header: {
                            Text("OVERVIEW").foregroundStyle(.secondary)
                        } footer: {
                            if overviewMetric == .overall {
                                Text("Average of A’s % share across workouts, time, calories & score (50 ≈ even split). Bars show that balance on a 0–100 scale.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Raw values for the selected metric.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .listRowBackground(Color.clear)

                        if !mergedBreakdownRows(a: a.breakdown, b: b.breakdown).isEmpty {
                            Section {
                                SectionCard {
                                    breakdownPercentSideBySide(a: a.breakdown, b: b.breakdown)
                                    chartLegend()
                                }
                            } header: {
                                Text("BY TYPE").foregroundStyle(.secondary)
                            } footer: {
                                Text("% of each period’s workouts by type (A and B side by side).")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .listRowBackground(Color.clear)
                        }

                        Section {
                            SectionCard {
                                Toggle("Show per day", isOn: $figuresPerDay)
                                figuresVisualCompare(
                                    a: a.summary,
                                    b: b.summary,
                                    daysA: max(1, daysA),
                                    daysB: max(1, daysB),
                                    perDay: figuresPerDay
                                )
                            }
                        } header: {
                            Text("FIGURES").foregroundStyle(.secondary)
                        } footer: {
                            Group {
                                if figuresPerDay {
                                    Text("Values are divided by the number of days in each period. The strip splits the combined A+B total for each row.")
                                } else {
                                    Text("The strip splits the combined A+B total for each metric.")
                                }
                            }
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }
                        .listRowBackground(Color.clear)

                        Section {
                            SectionCard {
                                breakdownMergedDetail(a: a.breakdown, b: b.breakdown)
                            }
                        } header: {
                            Text("BREAKDOWN (DETAIL)").foregroundStyle(.secondary)
                        } footer: {
                            Text("Numbers by training type in one place. The chart above shows workout mix as percentages.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .listRowBackground(Color.clear)
                    }
                }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
                .listRowBackground(Color.clear)
                .listSectionSpacing(10)
            }
            .navigationTitle("Compare periods")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task { await loadFollowees() }
            .onChange(of: resultA?.summary.workout_count) { _, _ in
                syncOverviewMetricSelection()
            }
        }
    }

    private func syncOverviewMetricSelection() {
        guard let a = resultA, let b = resultB else { return }
        let avail = availableOverviewMetrics(a: a, b: b)
        if !avail.contains(overviewMetric) {
            overviewMetric = avail.first ?? .overall
        }
    }

    private func chartLegendLabelB() -> String {
        if userBId == viewerUserId {
            let df = DateFormatter()
            df.locale = .current
            df.dateStyle = .medium
            df.timeStyle = .none
            return "B · \(df.string(from: periodBStart)) – \(df.string(from: periodBEndInclusive))"
        }
        if let name = followees.first(where: { $0.user_id == userBId })?.username,
           !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "B · \(name)"
        }
        return "B · \(userBId.uuidString.prefix(8))"
    }

    @ViewBuilder
    private func chartLegend() -> some View {
        let labelB = chartLegendLabelB()
        HStack(alignment: .top, spacing: 12) {
            HStack(alignment: .top, spacing: 6) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.accentColor)
                    .frame(width: 10, height: 10)
                    .padding(.top, 2)
                Text("A · You")
                    .font(.caption)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(alignment: .top, spacing: 6) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.orange)
                    .frame(width: 10, height: 10)
                    .padding(.top, 2)
                Text(labelB)
                    .font(.caption)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func overviewSingleChart(a: PeriodCompareSide, b: PeriodCompareSide, metric: OverviewChartMetric) -> some View {
        if metric == .overall {
            let bal = overallBalancePcts(a: a.summary, b: b.summary)
            let pts: [PeriodSummaryBarPoint] = [
                .init(metricKey: "overall", periodKey: chartPeriodA, periodLabel: "A", value: bal.pctA),
                .init(metricKey: "overall", periodKey: chartPeriodB, periodLabel: "B", value: bal.pctB)
            ]
            Chart(pts) { p in
                BarMark(
                    x: .value("Period", p.periodLabel),
                    y: .value("% share", p.value)
                )
                .foregroundStyle(by: .value("Period", p.periodKey))
            }
            .chartForegroundStyleScale([
                chartPeriodA: Color.accentColor,
                chartPeriodB: Color.orange
            ])
            .chartLegend(.hidden)
            .chartYScale(domain: 0...100)
            .chartYAxis { AxisMarks(position: .leading) }
        } else {
            let va = metric.value(from: a.summary)
            let vb = metric.value(from: b.summary)
            let pts: [PeriodSummaryBarPoint] = [
                .init(metricKey: metric.rawValue, periodKey: chartPeriodA, periodLabel: "A", value: va),
                .init(metricKey: metric.rawValue, periodKey: chartPeriodB, periodLabel: "B", value: vb)
            ]
            Chart(pts) { p in
                BarMark(
                    x: .value("Period", p.periodLabel),
                    y: .value("Value", p.value)
                )
                .foregroundStyle(by: .value("Period", p.periodKey))
            }
            .chartForegroundStyleScale([
                chartPeriodA: Color.accentColor,
                chartPeriodB: Color.orange
            ])
            .chartLegend(.hidden)
            .chartYAxis { AxisMarks(position: .leading) }
        }
    }

    private func mergedBreakdownRows(a: [PeriodCompareBreakdownRow], b: [PeriodCompareBreakdownRow]) -> [(label: String, wa: Int, wb: Int)] {
        let keys = Set(a.map(\.label)).union(b.map(\.label)).sorted()
        return keys.compactMap { k in
            let wa = a.first(where: { $0.label == k })?.workout_count ?? 0
            let wb = b.first(where: { $0.label == k })?.workout_count ?? 0
            guard wa > 0 || wb > 0 else { return nil }
            return (k.capitalized, wa, wb)
        }
    }

    @ViewBuilder
    private func breakdownPercentSideBySide(a: [PeriodCompareBreakdownRow], b: [PeriodCompareBreakdownRow]) -> some View {
        let rows = mergedBreakdownRows(a: a, b: b)
        let totalA = max(1, rows.reduce(0) { $0 + $1.wa })
        let totalB = max(1, rows.reduce(0) { $0 + $1.wb })
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                let pctA = 100.0 * Double(r.wa) / Double(totalA)
                let pctB = 100.0 * Double(r.wb) / Double(totalB)
                VStack(alignment: .leading, spacing: 8) {
                    Text(r.label)
                        .font(.subheadline.weight(.semibold))
                    HStack(alignment: .top, spacing: 12) {
                        pctColumn(letter: "A", pct: pctA, count: r.wa, color: Color.accentColor)
                        pctColumn(letter: "B", pct: pctB, count: r.wb, color: Color.orange)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func pctColumn(letter: String, pct: Double, count: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(letter)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(String(format: "%.0f%%", pct))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(color)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.12))
                    Capsule()
                        .fill(color)
                        .frame(width: geo.size.width * CGFloat(min(1, max(0, pct / 100))))
                }
            }
            .frame(height: 8)
            Text("\(count) workouts")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func breakdownMergedDetail(a: [PeriodCompareBreakdownRow], b: [PeriodCompareBreakdownRow]) -> some View {
        let keys = Set(a.map(\.label)).union(b.map(\.label)).sorted()
        if keys.isEmpty {
            Text("No breakdown for these periods").foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(keys.enumerated()), id: \.offset) { idx, k in
                    let ra = a.first { $0.label == k }
                    let rb = b.first { $0.label == k }
                    if idx > 0 {
                        Divider().opacity(0.35)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text(k.capitalized)
                            .font(.subheadline.weight(.semibold))
                        HStack(alignment: .top, spacing: 12) {
                            breakdownMergedColumn(title: "A · You", row: ra)
                            Spacer(minLength: 8)
                            breakdownMergedColumn(title: "B", row: rb)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func breakdownMergedColumn(title: String, row: PeriodCompareBreakdownRow?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if let r = row {
                Text("\(r.workout_count) wo · \(r.duration_min) min")
                    .font(.caption)
                Text("kcal \(fmt1(r.calories_kcal)) · score \(fmt1(r.score))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("—")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func figuresVisualCompare(
        a: PeriodCompareSummary,
        b: PeriodCompareSummary,
        daysA: Int,
        daysB: Int,
        perDay: Bool
    ) -> some View {
        let sa = perDay ? 1.0 / Double(daysA) : 1.0
        let sb = perDay ? 1.0 / Double(daysB) : 1.0
        VStack(alignment: .leading, spacing: 14) {
            figureSplitRow(title: "Workouts", va: Double(a.workout_count) * sa, vb: Double(b.workout_count) * sb) { String(format: "%.0f", $0) }
            figureSplitRow(title: "Time (min)", va: Double(a.duration_min) * sa, vb: Double(b.duration_min) * sb) { String(format: "%.0f", $0) }
            figureSplitRow(title: "Calories", va: a.calories_kcal * sa, vb: b.calories_kcal * sb) { String(format: "%.1f", $0) }
            figureSplitRow(title: "Score", va: a.score * sa, vb: b.score * sb) { String(format: "%.1f", $0) }
            if a.distance_km > 0 || b.distance_km > 0 {
                figureSplitRow(title: "Distance km", va: a.distance_km * sa, vb: b.distance_km * sb) { String(format: "%.2f", $0) }
            }
            if a.volume_kg > 0 || b.volume_kg > 0 {
                figureSplitRow(title: "Volume (kg)", va: a.volume_kg * sa, vb: b.volume_kg * sb) { String(format: "%.1f", $0) }
            }
            if perDay {
                Text("Values are divided by the number of days in each period.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func figureSplitRow(title: String, va: Double, vb: Double, fmt: (Double) -> String) -> some View {
        let sum = max(va + vb, 1e-9)
        let fracA = CGFloat(min(1, max(0, va / sum)))
        let delta = relDeltaCaption(va: va, vb: vb)
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            HStack(alignment: .center, spacing: 8) {
                Text(fmt(va))
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 76, alignment: .leading)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                GeometryReader { geo in
                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(Color.accentColor)
                            .frame(width: geo.size.width * fracA)
                        Rectangle()
                            .fill(Color.orange)
                    }
                }
                .frame(height: 10)
                .clipShape(Capsule())
                Text(fmt(vb))
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Color.orange)
                    .frame(width: 76, alignment: .trailing)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            if let delta {
                Text(delta)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func applyDatePreset(_ preset: PeriodDatePreset) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let comparingWithSomeoneElse = userBId != viewerUserId
        switch preset {
        case .sevenVsSeven:
            let bEnd = today
            let bStart = cal.date(byAdding: .day, value: -6, to: today) ?? today
            if comparingWithSomeoneElse {
                periodAStart = bStart
                periodAEndInclusive = bEnd
                periodBStart = bStart
                periodBEndInclusive = bEnd
            } else {
                periodBEndInclusive = bEnd
                periodBStart = bStart
                periodAEndInclusive = cal.date(byAdding: .day, value: -7, to: today) ?? today
                periodAStart = cal.date(byAdding: .day, value: -13, to: today) ?? today
            }
        case .weekAligned:
            guard let weekInterval = cal.dateInterval(of: .weekOfYear, for: today) else { return }
            let thisWeekStart = weekInterval.start
            if comparingWithSomeoneElse {
                periodAStart = thisWeekStart
                periodAEndInclusive = today
                periodBStart = thisWeekStart
                periodBEndInclusive = today
            } else {
                let daysSpan = cal.dateComponents([.day], from: thisWeekStart, to: today).day! + 1
                periodBStart = thisWeekStart
                periodBEndInclusive = today
                let aStart = cal.date(byAdding: .day, value: -7, to: thisWeekStart) ?? thisWeekStart
                periodAStart = aStart
                periodAEndInclusive = cal.date(byAdding: .day, value: daysSpan - 1, to: aStart) ?? aStart
            }
        case .twentyEightVsTwentyEight:
            let bEnd = today
            let bStart = cal.date(byAdding: .day, value: -27, to: today) ?? today
            if comparingWithSomeoneElse {
                periodAStart = bStart
                periodAEndInclusive = bEnd
                periodBStart = bStart
                periodBEndInclusive = bEnd
            } else {
                periodBEndInclusive = bEnd
                periodBStart = bStart
                periodAEndInclusive = cal.date(byAdding: .day, value: -28, to: today) ?? today
                periodAStart = cal.date(byAdding: .day, value: -55, to: today) ?? today
            }
        }
    }

    private func fmt1(_ x: Double) -> String {
        String(format: "%.1f", x)
    }

    private func isoTimestamptz(_ d: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: d)
    }

    private func intervalBounds(start: Date, endInclusive: Date, cal: Calendar) -> (Date, Date)? {
        let s = cal.startOfDay(for: start)
        guard let endEx = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: endInclusive)) else { return nil }
        guard endEx > s else { return nil }
        return (s, endEx)
    }

    private func aj(_ s: String) throws -> AnyJSON { try AnyJSON(s) }

    private func loadFollowees() async {
        await MainActor.run { loadingFollowees = true; error = nil }
        defer { Task { @MainActor in loadingFollowees = false } }
        do {
            let client = SupabaseManager.shared.client
            let session = try await client.auth.session
            let fRes = try await client
                .from("follows")
                .select("followee_id")
                .eq("follower_id", value: session.user.id)
                .execute()
            struct FRow: Decodable { let followee_id: UUID }
            let fRows = try JSONDecoder().decode([FRow].self, from: fRes.data)
            let ids = fRows.map(\.followee_id).filter { $0 != session.user.id }
            guard !ids.isEmpty else {
                await MainActor.run { followees = [] }
                return
            }
            let pRes = try await client
                .from("profiles")
                .select("user_id,username,avatar_url")
                .in("user_id", values: ids)
                .order("username", ascending: true)
                .limit(500)
                .execute()
            let rows = try JSONDecoder().decode([LightweightProfile].self, from: pRes.data)
            await MainActor.run { followees = rows }
        } catch {
            await MainActor.run {
                followees = []
                self.error = error.localizedDescription
            }
        }
    }

    private func runCompare() async {
        await MainActor.run {
            loadingCompare = true
            error = nil
            resultA = nil
            resultB = nil
        }
        defer { Task { @MainActor in loadingCompare = false } }
        let cal = Calendar.current
        guard let (aStart, aEnd) = intervalBounds(start: periodAStart, endInclusive: periodAEndInclusive, cal: cal),
              let (bStart, bEnd) = intervalBounds(start: periodBStart, endInclusive: periodBEndInclusive, cal: cal) else {
            await MainActor.run { error = "Each period needs a start date before the end date." }
            return
        }
        do {
            let client = SupabaseManager.shared.client
            let session = try await client.auth.session
            var params: [String: AnyJSON] = [:]
            params["p_user_a"] = try aj(session.user.id.uuidString)
            params["p_user_b"] = try aj(userBId.uuidString)
            params["p_kind"] = try aj(kind.rawValue)
            params["p_a_start"] = try aj(isoTimestamptz(aStart))
            params["p_a_end"] = try aj(isoTimestamptz(aEnd))
            params["p_b_start"] = try aj(isoTimestamptz(bStart))
            params["p_b_end"] = try aj(isoTimestamptz(bEnd))

            let res = try await client
                .rpc("get_period_training_compare_v1", params: params)
                .execute()

            let root = try decodeCompareRoot(from: res.data)
            await MainActor.run {
                resultA = root.period_a
                resultB = root.period_b
                overviewMetric = .overall
            }
        } catch {
            await MainActor.run { self.error = error.localizedDescription }
        }
    }

    private func decodeCompareRoot(from data: Data) throws -> PeriodCompareRoot {
        let dec = JSONDecoder()
        if let obj = try? dec.decode(PeriodCompareRoot.self, from: data) {
            return obj
        }
        if let arr = try? dec.decode([PeriodCompareRoot].self, from: data), let first = arr.first {
            return first
        }
        struct Wrap: Decodable { let data: PeriodCompareRoot }
        if let w = try? dec.decode(Wrap.self, from: data) {
            return w.data
        }
        throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Unexpected RPC shape"))
    }
}
