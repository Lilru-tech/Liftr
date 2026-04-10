import SwiftUI

struct GoalContributionsView: View {
    let goal: GoalRowUI

    @State private var rows: [WorkoutFeedCardItem] = []
    @State private var loading = true
    @State private var error: String?

    private var summary: GoalContributionsSummary? {
        guard !rows.isEmpty else { return nil }
        return GoalContributionsSummary(rows: rows, goal: goal)
    }

    var body: some View {
        Group {
            if loading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error {
                Text(error)
                    .foregroundStyle(.red)
                    .padding()
            } else if rows.isEmpty {
                ContentUnavailableView(
                    "No workouts",
                    systemImage: "figure.run",
                    description: Text("No logged workouts in this goal's week yet.")
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if let s = summary {
                            summaryCard(s)
                        }

                        ForEach(rows) { item in
                            NavigationLink {
                                WorkoutDetailView(workoutId: item.workoutId, ownerId: item.userId)
                            } label: {
                                WorkoutFeedCard(item: item, dayGroupLabel: nil)
                            }
                            .buttonStyle(.plain)
                            .navigationLinkIndicatorVisibility(.hidden)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
            }
        }
        .navigationTitle(goal.title)
        .navigationBarTitleDisplayMode(.inline)
        .background(Color.clear)
        .gradientBG()
        .task { await load() }
    }

    private func summaryCard(_ s: GoalContributionsSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Week summary")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if let m = GoalMetric(rawValue: goal.metric) {
                    Text(m.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            Text(s.goalProgressLine)
                .font(.caption)
                .foregroundStyle(.secondary)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 100), spacing: 8)],
                alignment: .leading,
                spacing: 8
            ) {
                statTile(title: "Workouts", value: "\(s.workoutCount)")
                statTile(title: "Total score", value: "\(s.totalScore)")
                statTile(title: "Avg score", value: "\(s.avgScore)")
                statTile(title: "Max score", value: "\(s.maxScore)")
                statTile(title: "Total kcal", value: "\(s.totalKcal)")
                statTile(title: "Avg kcal", value: "\(s.avgKcal)")
                statTile(title: "Max kcal", value: "\(s.maxKcal)")
                statTile(title: "Active days", value: "\(s.activeDays)")
            }

            if !s.kindCounts.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("By type")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    kindBreakdownRow(s.kindCounts)
                }
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.18))
        )
    }

    private func statTile(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.white.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(.white.opacity(0.10))
        )
    }

    private func kindBreakdownRow(_ pairs: [(kind: String, count: Int)]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(pairs, id: \.kind) { p in
                    Text("\(p.kind.capitalized) · \(p.count)")
                        .font(.caption2.weight(.semibold))
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(Capsule().fill(.white.opacity(0.10)))
                        .overlay(Capsule().stroke(.white.opacity(0.12)))
                }
            }
        }
    }

    private func load() async {
        await MainActor.run {
            loading = true
            error = nil
        }
        do {
            let data = try await GoalsManager.fetchWorkoutsContributingToGoal(goal)
            await MainActor.run {
                rows = data
                loading = false
            }
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
                loading = false
            }
        }
    }
}

private struct GoalContributionsSummary {
    let workoutCount: Int
    let totalScore: Int
    let avgScore: Int
    let maxScore: Int
    let totalKcal: Int
    let avgKcal: Int
    let maxKcal: Int
    let activeDays: Int
    let kindCounts: [(kind: String, count: Int)]
    let goalProgressLine: String

    init(rows: [WorkoutFeedCardItem], goal: GoalRowUI) {
        workoutCount = rows.count

        let scoreVals = rows.map { $0.score ?? 0 }
        totalScore = Int(scoreVals.reduce(0, +).rounded())
        avgScore = workoutCount > 0 ? Int((scoreVals.reduce(0, +) / Double(workoutCount)).rounded()) : 0
        maxScore = Int((scoreVals.max() ?? 0).rounded())

        let kcalVals = rows.map { $0.caloriesKcal ?? 0 }
        totalKcal = Int(kcalVals.reduce(0, +).rounded())
        avgKcal = workoutCount > 0 ? Int((kcalVals.reduce(0, +) / Double(workoutCount)).rounded()) : 0
        maxKcal = Int((kcalVals.max() ?? 0).rounded())

        var dayKeys = Set<String>()
        let cal = Calendar.current
        let df = DateFormatter()
        df.calendar = cal
        df.timeZone = cal.timeZone
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd"
        for r in rows {
            if let d = r.startedAt {
                dayKeys.insert(df.string(from: d))
            }
        }
        activeDays = dayKeys.count

        var byKind: [String: Int] = [:]
        for r in rows {
            let k = r.kind.lowercased()
            byKind[k, default: 0] += 1
        }
        kindCounts = byKind.map { ($0.key, $0.value) }.sorted { $0.kind < $1.kind }

        let target = Int(NSDecimalNumber(decimal: goal.targetValue).doubleValue.rounded())
        let achieved = Int(NSDecimalNumber(decimal: goal.achievedValue).doubleValue.rounded())
        let pct = target > 0 ? min(999, Int((Double(achieved) / Double(target) * 100).rounded())) : 0

        if let m = GoalMetric(rawValue: goal.metric) {
            switch m {
            case .workouts:
                goalProgressLine = "Target \(target) workouts · Logged \(achieved) · \(pct)%"
            case .calories:
                goalProgressLine = "Target \(target) kcal · Logged \(achieved) · \(pct)%"
            case .score:
                goalProgressLine = "Target \(target) pts · Logged \(achieved) · \(pct)%"
            }
        } else {
            goalProgressLine = "Target \(target) · Logged \(achieved) · \(pct)%"
        }
    }
}
