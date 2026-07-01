import SwiftUI
import Supabase

struct UserWeeklyTaskRow: Decodable, Identifiable {
    var id: UUID { task_id }
    let task_id: UUID
    let title: String
    let description: String
    let category: String
    let target_metric: String
    let target_value: Double?
    let target_secondary: Double?
    let reward_xp: Int
    let reward_coins: Int
    let reward_task_points: Int
    let difficulty_band: String?
    let status: String
    let generated_at: Date?
    let expires_at: Date?
    let accepted_at: Date?
    let completed_at: Date?
    let progress_value: Double?
    let week_start: Date?
    let week_end: Date?
    let accepted_count: Int?
    let accept_slots_remaining: Int?
    let refresh_count: Int?
    let free_refresh_available: Bool?
    let next_refresh_cost_coins: Int?

    var isAccepted: Bool { status == "accepted" }
    var isCompleted: Bool { status == "completed" }
    var isGenerated: Bool { status == "generated" }
    var isLocked: Bool { isGenerated && (accept_slots_remaining ?? 0) <= 0 }

    var progressRatio: Double? {
        guard let target = target_value, target > 0, let progress = progress_value else { return nil }
        return min(1.0, progress / target)
    }
}

private struct WeeklyTasksEmptyRpcParams: Encodable {}

private struct AcceptUserTaskParams: Encodable {
    let p_task_id: UUID
}

private struct UnacceptUserTaskParams: Encodable {
    let p_task_id: UUID
}

@MainActor
final class PersonalWeeklyTasksLoader: ObservableObject {
    @Published var tasks: [UserWeeklyTaskRow] = []
    @Published var loading = false
    @Published var error: String?
    @Published var acceptingTaskId: UUID?
    @Published var unacceptingTaskId: UUID?
    @Published var refreshingMenu = false

    var acceptedCount: Int { tasks.first?.accepted_count ?? 0 }
    var acceptSlotsRemaining: Int { tasks.first?.accept_slots_remaining ?? 3 }
    var refreshCount: Int { tasks.first?.refresh_count ?? 0 }
    var freeRefreshAvailable: Bool { tasks.first?.free_refresh_available ?? (refreshCount == 0) }
    var nextRefreshCostCoins: Int? { tasks.first?.next_refresh_cost_coins }
    var canRefreshMenu: Bool { refreshCount < 3 }
    var allMenuTasksCompleted: Bool { !tasks.isEmpty && tasks.allSatisfy(\.isCompleted) }
    var showRefreshMenu: Bool { canRefreshMenu && !allMenuTasksCompleted }
    var weekEnd: Date? { tasks.first?.week_end }

    func load() {
        Task { await refresh() }
    }

    func refresh() async {
        loading = true
        defer { loading = false }
        error = nil
        do {
            let res = try await SupabaseManager.shared.client
                .rpc("list_my_weekly_tasks_v1", params: WeeklyTasksEmptyRpcParams())
                .execute()
            let rows = try JSONDecoder.supabase().decode([UserWeeklyTaskRow].self, from: res.data)
            self.tasks = rows
        } catch {
            self.error = Self.friendlyLoadError(error)
            self.tasks = []
        }
    }

    func accept(taskId: UUID) async -> Bool {
        acceptingTaskId = taskId
        defer { acceptingTaskId = nil }
        do {
            _ = try await SupabaseManager.shared.client
                .rpc("accept_user_task_v1", params: AcceptUserTaskParams(p_task_id: taskId))
                .execute()
            await refresh()
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    func unaccept(taskId: UUID) async -> Bool {
        unacceptingTaskId = taskId
        defer { unacceptingTaskId = nil }
        do {
            _ = try await SupabaseManager.shared.client
                .rpc("unaccept_user_task_v1", params: UnacceptUserTaskParams(p_task_id: taskId))
                .execute()
            await refresh()
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    func refreshMenu() async -> Bool {
        refreshingMenu = true
        defer { refreshingMenu = false }
        do {
            _ = try await SupabaseManager.shared.client
                .rpc("refresh_my_weekly_tasks_v1", params: WeeklyTasksEmptyRpcParams())
                .execute()
            await refresh()
            return true
        } catch {
            self.error = Self.friendlyRefreshError(error)
            return false
        }
    }

    static func friendlyLoadError(_ error: Error) -> String {
        let msg = error.localizedDescription
        if msg.range(of: "read-only transaction", options: .caseInsensitive) != nil {
            return "Couldn't load weekly tasks. Redeploy the latest tasks SQL, then try again."
        }
        return "Couldn't load weekly tasks. Pull down to retry."
    }

    static func friendlyRefreshError(_ error: Error) -> String {
        let msg = error.localizedDescription.lowercased()
        if msg.contains("insufficient_coins") {
            return "Not enough coins for this refresh."
        }
        if msg.contains("weekly_task_refresh_cap") {
            return "You've used all menu refreshes this week."
        }
        return error.localizedDescription
    }
}

struct PersonalWeeklyTasksView: View {
    @StateObject private var loader = PersonalWeeklyTasksLoader()
    @State private var taskToUnaccept: UserWeeklyTaskRow?
    @State private var showRefreshConfirm = false
    @State private var selectedTask: UserWeeklyTaskRow?
    @State private var showHistory = false

    var body: some View {
        Group {
            if loader.loading && loader.tasks.isEmpty {
                ProgressView("Loading weekly tasks…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = loader.error, loader.tasks.isEmpty {
                ContentUnavailableView("Couldn't load tasks", systemImage: "exclamationmark.triangle", description: Text(err))
            } else if loader.tasks.isEmpty {
                ContentUnavailableView("No tasks this week", systemImage: "tray", description: Text("Check back on Monday for a new menu."))
            } else {
                List {
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Pick up to 3 tasks. Complete them to earn XP, coins, and Task Points — finished tasks free a slot for another.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            if let countdown = newMenuCountdownText {
                                Text(countdown)
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .listRowBackground(Color.clear)
                    }
                    Section {
                        ForEach(loader.tasks) { task in
                            PersonalWeeklyTaskCard(
                                task: task,
                                isAccepting: loader.acceptingTaskId == task.id,
                                isUnaccepting: loader.unacceptingTaskId == task.id,
                                onTap: { selectedTask = task },
                                onAccept: {
                                    Task { _ = await loader.accept(taskId: task.id) }
                                },
                                onUnaccept: {
                                    taskToUnaccept = task
                                }
                            )
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            .listRowBackground(Color.clear)
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .refreshable { await loader.refresh() }
            }
        }
        .navigationTitle("Weekly tasks")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 8) {
                    Button {
                        showHistory = true
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.body.weight(.semibold))
                            .weeklyTasksToolbarPill()
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Task history")
                    if loader.showRefreshMenu {
                        Button {
                            showRefreshConfirm = true
                        } label: {
                            Group {
                                if loader.refreshingMenu {
                                    ProgressView()
                                } else {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                        .font(.body.weight(.semibold))
                                }
                            }
                            .weeklyTasksToolbarPill()
                        }
                        .buttonStyle(.plain)
                        .disabled(loader.refreshingMenu)
                    } else if loader.allMenuTasksCompleted, let countdown = newMenuCountdownText {
                        Text(countdown)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .weeklyTasksToolbarPill()
                    }
                    Text("\(loader.acceptedCount)/3")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .weeklyTasksToolbarPill()
                }
            }
        }
        .confirmationDialog(
            "Refresh menu?",
            isPresented: $showRefreshConfirm,
            titleVisibility: .visible
        ) {
            Button(refreshConfirmActionTitle, role: .none) {
                Task { _ = await loader.refreshMenu() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(refreshConfirmMessage)
        }
        .alert(
            "Unaccept task?",
            isPresented: Binding(
                get: { taskToUnaccept != nil },
                set: { if !$0 { taskToUnaccept = nil } }
            )
        ) {
            Button("Unaccept", role: .destructive) {
                guard let task = taskToUnaccept else { return }
                Task { _ = await loader.unaccept(taskId: task.id) }
                taskToUnaccept = nil
            }
            Button("Cancel", role: .cancel) {
                taskToUnaccept = nil
            }
        } message: {
            Text("Remove this task from your active list? You can accept it again later.")
        }
        .task {
            await loader.refresh()
            await WeeklyTasksHomeSummaryLoader.markSeenIfPossible()
        }
        .navigationDestination(isPresented: $showHistory) {
            WeeklyTasksHistoryView()
        }
        .navigationDestination(item: $selectedTask) { task in
            WeeklyTaskContributionsView(task: task)
        }
    }

    private var refreshConfirmActionTitle: String {
        if loader.freeRefreshAvailable {
            return "Refresh for free"
        }
        if let cost = loader.nextRefreshCostCoins, cost > 0 {
            return "Refresh for \(cost) coins"
        }
        return "Refresh"
    }

    private var refreshConfirmMessage: String {
        if loader.freeRefreshAvailable {
            return "Replace unaccepted tasks with a new set. Accepted tasks stay."
        }
        if let cost = loader.nextRefreshCostCoins, cost > 0 {
            return "Replace unaccepted tasks for \(cost) coins. Accepted tasks stay."
        }
        return "Replace unaccepted tasks with a new set."
    }

    private var newMenuCountdownText: String? {
        guard loader.allMenuTasksCompleted, let end = loader.weekEnd else { return nil }
        let now = Date()
        guard end > now else { return "New tasks soon" }
        let interval = end.timeIntervalSince(now)
        let days = Int(interval / 86_400)
        if days >= 1 {
            return "New tasks in \(days) day\(days == 1 ? "" : "s")"
        }
        let hours = max(1, Int(interval / 3_600))
        return "New tasks in \(hours) hour\(hours == 1 ? "" : "s")"
    }
}

private struct PersonalWeeklyTaskCard: View {
    let task: UserWeeklyTaskRow
    let isAccepting: Bool
    let isUnaccepting: Bool
    var onTap: () -> Void
    var onAccept: () -> Void
    var onUnaccept: () -> Void

    private var categoryLabel: String {
        switch task.category.lowercased() {
        case "cardio": return "Cardio"
        case "strength": return "Strength"
        case "sport": return "Sport"
        default: return task.category.capitalized
        }
    }

    private var statusLabel: String {
        switch task.status {
        case "accepted": return "Accepted"
        case "completed": return "Completed"
        case "expired": return "Expired"
        default: return "Available"
        }
    }

    private var statusColor: Color {
        if task.isCompleted { return .green }
        if task.isAccepted { return .orange }
        return .blue
    }

    private var cardBorderColor: Color {
        if task.isCompleted { return .green.opacity(0.55) }
        if task.isAccepted { return .orange.opacity(0.55) }
        if task.isGenerated { return .blue.opacity(0.35) }
        return .white.opacity(0.18)
    }

    private var progressTint: Color {
        task.isCompleted ? .green : .orange
    }

    private var difficultyLabel: String? {
        guard let band = task.difficulty_band, !band.isEmpty else { return nil }
        return band.capitalized
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(cardBorderColor, lineWidth: task.isAccepted || task.isCompleted ? 2 : 1)
                )

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(categoryLabel)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.15), in: Capsule())
                    if let difficultyLabel {
                        Text(difficultyLabel)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    HStack(spacing: 4) {
                        if task.isCompleted {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption)
                        }
                        Text(statusLabel)
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(statusColor.opacity(0.12), in: Capsule())
                }

                Text(task.title)
                    .font(.headline)
                Text(task.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if task.isCompleted {
                    Text("Rewards claimed: \(task.reward_xp) XP · \(task.reward_coins) coins · \(task.reward_task_points) TP")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                } else {
                    HStack(spacing: 12) {
                        Label("\(task.reward_xp) XP", systemImage: "star.fill")
                        Label("\(task.reward_coins)", systemImage: "bitcoinsign.circle.fill")
                        Label("\(task.reward_task_points) TP", systemImage: "flag.fill")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                }

                if task.showsProgressBlock {
                    HStack {
                        Text("Progress")
                            .font(.caption.weight(.semibold))
                        Spacer()
                        Text("\(task.progressPercentInt)%")
                            .font(.caption.weight(.bold).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(value: task.displayProgressRatio)
                        .tint(progressTint)
                    Text("\(task.progressCurrentLabel) / \(task.progressTargetLabel)")
                        .font(.caption2.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                if task.isGenerated {
                    Button(action: onAccept) {
                        HStack {
                            Spacer()
                            if isAccepting {
                                ProgressView()
                            } else {
                                Text(task.isLocked ? "Slots full" : "Accept task")
                                    .font(.subheadline.weight(.semibold))
                            }
                            Spacer()
                        }
                        .padding(.vertical, 10)
                        .background(task.isLocked ? Color.gray.opacity(0.2) : Color.orange.opacity(0.9), in: RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(task.isLocked ? Color.secondary : Color.white)
                    }
                    .buttonStyle(.plain)
                    .disabled(task.isLocked || isAccepting)
                }

                if task.isAccepted {
                    Button(action: onUnaccept) {
                        HStack {
                            Spacer()
                            if isUnaccepting {
                                ProgressView()
                            } else {
                                Text("Unaccept")
                                    .font(.subheadline.weight(.semibold))
                            }
                            Spacer()
                        }
                        .padding(.vertical, 10)
                        .background(Color.gray.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(isUnaccepting)
                }
            }
            .padding(14)
        }
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture(perform: onTap)
    }
}

private struct WeeklyTasksToolbarPillModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.18)))
    }
}

private extension View {
    func weeklyTasksToolbarPill() -> some View {
        modifier(WeeklyTasksToolbarPillModifier())
    }
}
