import SwiftUI
import Supabase

struct WeeklyTasksHistoryStats: Decodable {
    let total_accepted: Int
    let total_completed: Int
    let total_expired: Int
    let completion_rate_percent: Int
    let total_xp_earned: Int
    let total_coins_earned: Int
    let total_task_points_earned: Int
    let current_week_accepted: Int
    let current_week_completed: Int
}

struct WeeklyTasksHistoryTaskRow: Decodable, Identifiable {
    var id: UUID { task_id }
    let task_id: UUID
    let title: String
    let category: String
    let difficulty_band: String?
    let status: String
    let accepted_at: Date?
    let completed_at: Date?
    let week_start: Date?
    let target_metric: String
    let target_value: Double?
    let reward_xp: Int
    let reward_coins: Int
    let reward_task_points: Int
}

struct WeeklyTasksHistoryPayload: Decodable {
    let stats: WeeklyTasksHistoryStats
    let completed_tasks: [WeeklyTasksHistoryTaskRow]
    let total_completed_tasks: Int
    let has_more: Bool
}

private struct WeeklyTasksHistoryParams: Encodable {
    let p_tasks_limit: Int
    let p_tasks_offset: Int
}

@MainActor
final class WeeklyTasksHistoryLoader: ObservableObject {
    @Published var stats: WeeklyTasksHistoryStats?
    @Published var completedTasks: [WeeklyTasksHistoryTaskRow] = []
    @Published var totalCompletedTasks: Int = 0
    @Published var hasMore = false
    @Published var loading = false
    @Published var loadingMore = false
    @Published var error: String?

    private let pageSize = 10
    private var nextOffset = 0

    func load() {
        Task { await refresh() }
    }

    func refresh() async {
        loading = true
        defer { loading = false }
        error = nil
        nextOffset = 0
        do {
            let res = try await SupabaseManager.shared.client
                .rpc(
                    "get_my_weekly_tasks_history_v1",
                    params: WeeklyTasksHistoryParams(p_tasks_limit: pageSize, p_tasks_offset: 0)
                )
                .execute()
            let decoded = try JSONDecoder.supabase().decode(WeeklyTasksHistoryPayload.self, from: res.data)
            self.stats = decoded.stats
            self.completedTasks = decoded.completed_tasks
            self.totalCompletedTasks = decoded.total_completed_tasks
            self.hasMore = decoded.has_more
            self.nextOffset = decoded.completed_tasks.count
        } catch {
            self.error = error.localizedDescription
            self.stats = nil
            self.completedTasks = []
            self.totalCompletedTasks = 0
            self.hasMore = false
        }
    }

    func loadMore() async {
        guard hasMore, !loadingMore else { return }
        loadingMore = true
        defer { loadingMore = false }
        do {
            let res = try await SupabaseManager.shared.client
                .rpc(
                    "get_my_weekly_tasks_history_v1",
                    params: WeeklyTasksHistoryParams(p_tasks_limit: pageSize, p_tasks_offset: nextOffset)
                )
                .execute()
            let decoded = try JSONDecoder.supabase().decode(WeeklyTasksHistoryPayload.self, from: res.data)
            self.stats = decoded.stats
            self.completedTasks.append(contentsOf: decoded.completed_tasks)
            self.totalCompletedTasks = decoded.total_completed_tasks
            self.hasMore = decoded.has_more
            self.nextOffset += decoded.completed_tasks.count
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct WeeklyTasksHistoryView: View {
    @StateObject private var loader = WeeklyTasksHistoryLoader()

    var body: some View {
        Group {
            if loader.loading && loader.stats == nil {
                ProgressView("Loading history…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = loader.error, loader.stats == nil {
                ContentUnavailableView("Couldn't load history", systemImage: "exclamationmark.triangle", description: Text(err))
            } else {
                List {
                    if let stats = loader.stats {
                        Section {
                            summaryCard(stats)
                                .listRowBackground(Color.clear)
                                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        }
                    }
                    Section {
                        if loader.totalCompletedTasks == 0 {
                            ContentUnavailableView(
                                "No completed tasks yet",
                                systemImage: "checkmark.circle",
                                description: Text("Finished weekly tasks will appear here.")
                            )
                            .listRowBackground(Color.clear)
                        } else {
                            ForEach(loader.completedTasks) { task in
                                historyTaskRow(task)
                                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                                    .listRowBackground(Color.clear)
                            }
                            if loader.hasMore {
                                Button {
                                    Task { await loader.loadMore() }
                                } label: {
                                    HStack {
                                        Spacer()
                                        if loader.loadingMore {
                                            ProgressView()
                                        } else {
                                            Text("See more tasks")
                                                .font(.subheadline.weight(.semibold))
                                        }
                                        Spacer()
                                    }
                                    .padding(.vertical, 8)
                                }
                                .buttonStyle(.plain)
                                .listRowBackground(Color.clear)
                            }
                        }
                    } header: {
                        Text("Completed tasks")
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .refreshable { await loader.refresh() }
            }
        }
        .navigationTitle("Task history")
        .navigationBarTitleDisplayMode(.inline)
        .gradientBG()
        .onAppear { loader.load() }
    }

    private func summaryCard(_ stats: WeeklyTasksHistoryStats) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("All time")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("Completed \(stats.completion_rate_percent)%")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 10)], spacing: 10) {
                summaryPill(title: "Accepted", value: "\(stats.total_accepted)")
                summaryPill(title: "Completed", value: "\(stats.total_completed)")
                summaryPill(title: "Missed", value: "\(stats.total_expired)")
                summaryPill(title: "XP", value: "\(stats.total_xp_earned)")
                summaryPill(title: "Coins", value: "\(stats.total_coins_earned)")
                summaryPill(title: "TP", value: "\(stats.total_task_points_earned)")
            }
            Text("This week: \(stats.current_week_completed) completed · \(stats.current_week_accepted) active")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(.white.opacity(0.18)))
    }

    private func summaryPill(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func historyTaskRow(_ task: WeeklyTasksHistoryTaskRow) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.green.opacity(0.55), lineWidth: 2)
                )

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(task.category.capitalized)
                        .font(.caption.weight(.semibold))
                    if let band = task.difficulty_band, !band.isEmpty {
                        Text(band.capitalized)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption2)
                        Text("Completed")
                            .font(.caption.weight(.medium))
                    }
                    .foregroundStyle(.green)
                }
                Text(task.title)
                    .font(.headline)
                if let completedAt = task.completed_at {
                    Text(completedDateLabel(completedAt))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                Text("+\(task.reward_xp) XP · \(task.reward_coins) coins · \(task.reward_task_points) TP")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
            }
            .padding(14)
        }
    }

    private func completedDateLabel(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .none
        return fmt.string(from: date)
    }
}
