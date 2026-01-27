import SwiftUI

struct GoalsView: View {
    @EnvironmentObject var app: AppState

    let userId: UUID?
    let viewedUsername: String

    @State private var goals: [GoalRowUI] = []
    @State private var loading = false
    @State private var error: String?
    @State private var showNewGoal = false
    @State private var showDuplicateAlert = false
    @State private var summaryScope: SummaryScope = .week
    @State private var allTimeStats: GoalStats?
    @State private var duplicateMessage = ""
    @State private var showCompleted = false
    private var effectiveUserId: UUID? { userId ?? app.userId }
    private var isOwnProfile: Bool { effectiveUserId != nil && effectiveUserId == app.userId }
    private var currentWeekStart: Date { GoalsManager.currentWeekStart() }
    private var finishedGoalsUI: [GoalRowUI] { goals.filter { isFinished($0) } }
    private var activeGoals: [GoalRowUI] { goals.filter { !isFinished($0) } }
    private var activeGoalIds: [Int64] { activeGoals.map(\.id) }
    private var totalGoals: Int { goals.count }
    private var finishedGoals: Int { finishedGoalsUI.count }
    private var finishedPercent: Int { totalGoals == 0 ? 0 : Int((Double(finishedGoals) / Double(totalGoals) * 100.0).rounded()) }
    private var avgProgressPercent: Int { totalGoals == 0 ? 0 : Int((goals.map(\.progressRatio).reduce(0,+) / Double(totalGoals) * 100.0).rounded()) }
    private var summaryTotal: Int {
        summaryScope == .week ? totalGoals : (allTimeStats?.total_goals ?? 0)
    }
    private var summaryFinished: Int {
        summaryScope == .week ? finishedGoals : (allTimeStats?.finished_goals ?? 0)
    }
    private var summaryAvg: Int {
        summaryScope == .week ? avgProgressPercent : Int((allTimeStats?.avg_progress_percent ?? 0).rounded())
    }
    private var summaryBest: Int {
        Int((allTimeStats?.best_progress_percent ?? 0).rounded())
    }
    private var summaryPercentText: String {
        let v = summaryScope == .week ? Double(finishedPercent) : (allTimeStats?.finished_percent ?? 0)
        return "\(Int(v.rounded()))%"
    }

    private var finishedAvgPercent: Int {
        guard !finishedGoalsUI.isEmpty else { return 0 }
        let avg = finishedGoalsUI
            .map { min(1.0, $0.progressRatio) }
            .reduce(0, +) / Double(finishedGoalsUI.count)
        return Int((avg * 100.0).rounded())
    }
    
    private func isFinished(_ g: GoalRowUI) -> Bool {
        if g.isCompleted { return true }
        let weekEnd = Calendar.current.date(byAdding: .day, value: 7, to: g.weekStart) ?? g.weekStart
        return Date() >= weekEnd
    }
    
    private var existingMetricsThisWeek: Set<GoalMetric> {
        let weekStr = GoalsManager.dateOnlyString(currentWeekStart)
        return Set(
            goals
                .filter { GoalsManager.dateOnlyString($0.weekStart) == weekStr }
                .compactMap { GoalMetric(rawValue: $0.metric) }
        )
    }
    
    var body: some View {
        VStack(spacing: 12) {
            if goals.isEmpty {
                header
            } else {
                VStack(spacing: 8) {
                    Picker("", selection: $summaryScope) {
                        Text("Week").tag(SummaryScope.week)
                        Text(allTimeStats == nil ? "All time…" : "All time").tag(SummaryScope.allTime)
                    }
                    .onChange(of: summaryScope) { _, _ in
                        Task { await load() }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

                    summaryCard
                }
            }

            if loading {
                ProgressView().padding(.top, 24)
            } else if let error {
                Text(error).foregroundStyle(.red).padding(.horizontal)
            } else if goals.isEmpty {
                Spacer()

                VStack(spacing: 8) {
                    Text(isOwnProfile ? "No goals yet" : "No goals to show")
                        .font(.headline)
                    Text(isOwnProfile ? "Add your first one." : "This user hasn't created goals for this week.")
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

                Spacer()
            } else {
                List {
                    if !activeGoals.isEmpty {
                        Section {
                            ForEach(activeGoals) { g in
                                goalCard(g)
                                    .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                                    .listRowBackground(Color.clear)
                            }
                            .if(isOwnProfile) { view in
                                view.onDelete { idxSet in
                                    Task { await deleteActiveGoals(at: idxSet) }
                                }
                            }
                        } header: {
                            ZStack {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(.ultraThinMaterial)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .stroke(.white.opacity(0.18))
                                    )

                                HStack(spacing: 10) {
                                    Text("Active")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.primary.opacity(0.75))
                                    
                                    Spacer()

                                    Text("\(activeGoals.count)")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.primary.opacity(0.75))
                                    
                                }
                                .padding(.vertical, 10)
                                .padding(.horizontal, 12)
                            }
                            .padding(.horizontal, 12)
                            .padding(.top, 6)
                            .textCase(nil)
                        }
                    }

                    if !finishedGoalsUI.isEmpty {
                        Section {
                            Button {
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                                    showCompleted.toggle()
                                }
                            } label: {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(.ultraThinMaterial)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                .stroke(.white.opacity(0.18))
                                        )

                                    HStack(spacing: 10) {
                                        Text("Finished")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.primary.opacity(0.75))

                                        Spacer()

                                        Text("\(finishedAvgPercent)%")
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(.primary.opacity(0.75))

                                        Text("\(finishedGoalsUI.count)")
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(.primary.opacity(0.75))

                                        Image(systemName: showCompleted ? "chevron.down" : "chevron.right")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.primary.opacity(0.75))
                                    }
                                    .padding(.vertical, 10)
                                    .padding(.horizontal, 12)
                                }
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))

                            if showCompleted {
                                ForEach(finishedGoalsUI) { g in
                                    goalCard(g)
                                        .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                                        .listRowBackground(Color.clear)
                                }
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .listRowSeparator(.hidden)
                .listSectionSeparator(.hidden)
                .background(Color.clear)
            }
        }
        .navigationTitle(isOwnProfile ? "My Goals" : "\(viewedUsername)'s Goals")
        .toolbar {
            if isOwnProfile {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showNewGoal = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                }
            }
        }
        .sheet(isPresented: $showNewGoal) {
            NewGoalSheet(
                userId: effectiveUserId,
                existingMetrics: existingMetricsThisWeek
            ) { title, target, metric in
                if goals.contains(where: { $0.metric == metric.rawValue }) {
                    duplicateMessage = "You already have a \(metric.title) goal for this week."
                    showDuplicateAlert = true
                    return
                }
                Task { await createGoal(title: title, target: target, metric: metric) }
            }
            .gradientBG()
            .foregroundStyle(.primary)
            .presentationDetents([.fraction(0.48)])
            .presentationDragIndicator(.visible)
        }
        .alert("Goal already exists", isPresented: $showDuplicateAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(duplicateMessage)
        }
        .task {
            await load()
            await loadAllTimeStats()
        }
    }
    
    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(summaryScope == .week ? "This week summary" : "All time summary")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(summaryPercentText)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                summaryPill(title: "Total", value: "\(summaryTotal)")
                summaryPill(title: "Finished", value: "\(summaryFinished)")
                summaryPill(title: "Avg", value: "\(summaryAvg)%")
                if summaryScope == .allTime {
                    summaryPill(title: "Best", value: "\(summaryBest)%")
                }
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.18))
        )
        .padding(.horizontal)
    }

    private func summaryPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(Capsule().fill(.white.opacity(0.10)))
        .overlay(Capsule().stroke(.white.opacity(0.12)))
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "target")
                .foregroundStyle(.secondary)

            Text("Track your objectives")
                .font(.subheadline.weight(.semibold))

            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.18))
        )
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal)
    }

    private func progressColor(for ratio: Double, isCompleted: Bool) -> Color {
        if isCompleted { return .gray.opacity(0.55) }

        if ratio >= 2.0 { return .purple }
        if ratio >= 1.0 { return .yellow }
        if ratio >= 0.8 { return .green }
        if ratio >= 0.6 { return .blue }
        if ratio >= 0.4 { return .orange }
        if ratio >= 0.2 { return .red.opacity(0.8) }
        return .red
    }
    
    private func progressSummaryView(for g: GoalRowUI) -> some View {
        let achievedInt = NSDecimalNumber(decimal: g.achievedValue).intValue
        let targetInt = max(1, NSDecimalNumber(decimal: g.targetValue).intValue)
        let percent = Int((g.progressRatio * 100.0).rounded())

        return VStack(alignment: .trailing, spacing: 2) {
            Text("\(achievedInt)/\(targetInt)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Text("\(percent)%")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
    
    private func goalCard(_ g: GoalRowUI) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(.white.opacity(0.18)))

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(g.title)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)

                    Spacer()

                    progressSummaryView(for: g)
                }

                ProgressView(value: g.progress)
                    .progressViewStyle(.linear)
                    .tint(progressColor(for: g.progressRatio, isCompleted: g.isCompleted))
                
                HStack(spacing: 10) {
                    HStack(spacing: 6) {
                        if g.isCompleted {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                        } else if isFinished(g) {
                            Image(systemName: "clock.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        let expired = isFinished(g) && !g.isCompleted

                        Text(g.isCompleted ? "Completed" : (expired ? "Expired" : "Active"))
                            .font(.caption2.weight(.semibold))
                    }
                    .padding(.vertical, 3)
                    .padding(.horizontal, 8)
                    .background(
                        Capsule().fill(
                            g.isCompleted
                            ? Color.gray.opacity(0.16)
                            : ( (isFinished(g) ? Color.gray.opacity(0.16) : Color.green.opacity(0.20)) )
                        )
                    )
                    .overlay(Capsule().stroke(.white.opacity(0.12)))

                    Spacer()
                    
                    if isOwnProfile && !g.isCompleted && !isFinished(g) {
                        Button {
                            Task { await refresh() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .padding(12)
            .opacity(g.isCompleted ? 0.78 : 1.0)
        }
    }

    private func load() async {
        guard let uid = effectiveUserId else { return }
        loading = true
        error = nil
        defer { loading = false }

        do {
            let rows: [GoalRowUI]
            if summaryScope == .week {
                rows = try await GoalsManager.fetchGoalsForCurrentWeek(for: uid)
            } else {
                rows = try await GoalsManager.fetchGoalsAllTime(for: uid)
            }
            await MainActor.run { goals = rows }
            await MainActor.run { goals = rows }
        } catch {
            await MainActor.run { self.error = error.localizedDescription }
        }
    }
    
    private func loadAllTimeStats() async {
        guard let uid = effectiveUserId else { return }
        do {
            let stats = try await GoalsManager.fetchAllTimeStats(userId: uid)
            await MainActor.run { self.allTimeStats = stats }
        } catch {
            await MainActor.run {
                self.error = "All-time stats error: \(error.localizedDescription)"
            }
        }
    }

    private func createGoal(title: String, target: Int, metric: GoalMetric) async {
        guard let uid = effectiveUserId else { return }
        do {
            try await GoalsManager.createWeeklyGoal(userId: uid, title: title, targetValue: target, metric: metric)
            await load()
            await loadAllTimeStats()
        } catch {
            await MainActor.run {
                let msg = error.localizedDescription
                if msg.contains("weekly_goals_unique") {
                    self.error = "You already have a goal for this metric this week."
                } else {
                    self.error = msg
                }
            }
        }
    }

    private func deleteActiveGoals(at offsets: IndexSet) async {
        let ids = offsets.map { activeGoals[$0].id }
        do {
            for id in ids {
                guard let uid = effectiveUserId else { return }
                try await GoalsManager.deleteGoal(userId: uid, goalId: id)
            }
            await load()
            await loadAllTimeStats()
        } catch {
            await MainActor.run { self.error = error.localizedDescription }
        }
    }
    
    private func refresh() async {
        await load()
        await loadAllTimeStats()
    }
}

private extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

private enum SummaryScope: String, CaseIterable, Identifiable {
    case week = "Week"
    case allTime = "All time"
    var id: String { rawValue }
}

struct GoalStats: Decodable {
    let total_goals: Int
    let finished_goals: Int
    let finished_percent: Double
    let avg_progress_percent: Double
    let best_progress_percent: Double
}

private struct NewGoalSheet: View {
    let userId: UUID?
    let existingMetrics: Set<GoalMetric>
    var onCreate: (String, Int, GoalMetric) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var metric: GoalMetric = .workouts
    @State private var title: String = ""
    @State private var target: String = ""
    @State private var loadingSuggestion = false
    @State private var didUserEditTitle = false
    
    private var metricAlreadyExists: Bool {
        existingMetrics.contains(metric)
    }
    
    var body: some View {
        VStack(spacing: 14) {
            Text("New Goal").font(.headline)

            Picker("Metric", selection: $metric) {
                ForEach(GoalMetric.allCases) { m in
                    Text(m.title).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: metric) { _, _ in
                didUserEditTitle = false
                Task { await loadSuggestion(forceOverwrite: true) }
            }
            if metricAlreadyExists {
                Text("You already created a \(metric.title) goal for this week.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Title")
                    .font(.caption)
                    .foregroundColor(.black)

                TextField("e.g. \(metric.title) goal", text: $title)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: title) { oldValue, newValue in
                        if !newValue.isEmpty && newValue != "\(metric.title) goal" {
                            didUserEditTitle = true
                        }
                    }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Target")
                    .font(.caption)
                    .foregroundColor(.black)

                TextField(metric.unit, text: $target)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)

                Text("Recommendation is based on your recent activity (last 8 weeks). If you’re new, we use a typical average.")
                    .font(.caption2)
                    .foregroundColor(.black)
                    .multilineTextAlignment(.leading)
                    .padding(.top, 4)
            }

            if loadingSuggestion {
                ProgressView().padding(.top, 4)
            } else {
                Button("Use recommended target") {
                    Task { await loadSuggestion(forceOverwrite: true) }
                }
                .font(.caption)
            }

            Button {
                let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
                let v = Int(target.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
                guard !t.isEmpty, v > 0 else { return }
                onCreate(t, v, metric)
                dismiss()
            } label: {
                Text("Create")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(
                metricAlreadyExists ||
                title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                (Int(target) ?? 0) <= 0
            )
        }
        .padding(16)
        .task { await loadSuggestion() }
    }

    private func loadSuggestion(forceOverwrite: Bool = false) async {
        guard let uid = userId else { return }
        loadingSuggestion = true
        defer { loadingSuggestion = false }

        do {
            let rec = try await GoalsManager.fetchRecommendation(userId: uid, metric: metric)
            if forceOverwrite || target.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                await MainActor.run {
                    target = String(max(1, rec))
                }
            }
            if !didUserEditTitle {
                await MainActor.run {
                    title = "\(metric.title) goal"
                }
            }
        } catch {
        }
    }
}
