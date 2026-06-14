import SwiftUI
import Supabase

struct TrackedAchievementsView: View {
    @EnvironmentObject private var app: AppState

    @State private var items: [AchievementRow] = []
    @State private var loading = false
    @State private var error: String?
    @State private var selected: AchievementRow?
    @State private var trackError: String?
    @State private var trackBusy = false
    @State private var showAllAchievements = false

    private var trackedItems: [AchievementRow] {
        items.filter(\.is_tracked).sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    var body: some View {
        VStack(spacing: 12) {
            header

            if loading {
                Spacer()
                ProgressView()
                Spacer()
            } else if let error {
                Spacer()
                Text(error).foregroundStyle(.red).padding()
                Spacer()
            } else if trackedItems.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(trackedItems) { row in
                        Button {
                            selected = row
                        } label: {
                            TrackedAchievementRowView(row: row)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("Tracked achievements")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load(showLoadingIndicator: true) }
        .refreshable { await recomputeAndReload() }
        .sheet(item: $selected) { row in
            AchievementDetailSheet(
                row: row,
                isOwnProfile: true,
                trackedCount: trackedItems.count,
                trackBusy: trackBusy,
                trackError: trackError,
                onShareToChat: { selected = nil },
                onToggleTrack: { Task { await toggleTrack(for: row) } }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
            .environmentObject(app)
        }
        .navigationDestination(isPresented: $showAllAchievements) {
            AchievementsGridView(userId: app.userId, viewedUsername: "You")
                .gradientBG()
        }
    }

    private var header: some View {
        HStack {
            Text("\(trackedItems.count)/5 tracked")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.top, 4)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "checkmark.circle")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("No tracked achievements")
                .font(.headline)
            Text("Open Achievements, pick a locked goal, and tap Track this achievement.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Button("Browse achievements") {
                showAllAchievements = true
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
    }

    private func load(showLoadingIndicator: Bool = false) async {
        guard let uid = app.userId else { return }
        if showLoadingIndicator { loading = true }
        defer { if showLoadingIndicator { loading = false } }

        do {
            let res = try await SupabaseManager.shared.client
                .rpc("get_user_achievements", params: ["p_user_id": uid.uuidString])
                .execute()
            let rows = try JSONDecoder.supabase().decode([AchievementRow].self, from: res.data)
            await MainActor.run {
                items = rows
                error = nil
            }
        } catch {
            guard !isBenignFetchCancellation(error) else { return }
            await MainActor.run { self.error = error.localizedDescription }
        }
    }

    private func recomputeAndReload() async {
        guard let uid = app.userId else { return }
        do {
            _ = try await SupabaseManager.shared.client
                .rpc("check_and_unlock_achievements_for", params: ["p_user_id": uid.uuidString])
                .execute()
        } catch {
            guard !isBenignFetchCancellation(error) else { return }
        }
        await CoinManager.shared.refreshBalanceAfterMutation(notifyIfEarned: true)
        await load(showLoadingIndicator: false)
    }

    private struct ToggleTrackResponse: Decodable {
        let tracked: Bool
        let tracked_count: Int
    }

    @MainActor
    private func toggleTrack(for row: AchievementRow) async {
        guard !trackBusy else { return }
        trackBusy = true
        trackError = nil
        defer { trackBusy = false }

        do {
            let res = try await SupabaseManager.shared.client
                .rpc("toggle_tracked_achievement_v1", params: ["p_achievement_id": row.achievement_id])
                .execute()
            let payload = try JSONDecoder.supabase().decode(ToggleTrackResponse.self, from: res.data)
            let nowTracked = payload.tracked
            items = items.map { item in
                guard item.achievement_id == row.achievement_id else { return item }
                var copy = item
                copy.is_tracked = nowTracked
                return copy
            }
            if !nowTracked {
                selected = nil
            } else if var sel = selected, sel.achievement_id == row.achievement_id {
                sel.is_tracked = nowTracked
                selected = sel
            }
        } catch {
            let msg = error.localizedDescription.lowercased()
            if msg.contains("tracked_limit_reached") {
                trackError = "You can track up to 5 achievements."
            } else {
                trackError = error.localizedDescription
            }
        }
    }
}

private struct TrackedAchievementRowView: View {
    let row: AchievementRow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.ultraThinMaterial)
                        .frame(width: 48, height: 48)
                    Image(systemName: symbolForAchievement(code: row.code, category: row.category))
                        .font(.system(size: 22))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(prettySubtype(from: row.code, fallbackCategory: row.category))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Text("\(row.progressPercentInt)%")
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: row.progressFraction)
                .tint(Color.accentColor)

            if let cur = row.progress_current, let tgt = row.requirement_value, tgt > 0 {
                Text("\(formatTrackedNumber(cur)) / \(formatTrackedNumber(tgt))")
                    .font(.caption.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            } else if row.progress_current == nil, row.requirement_value != nil {
                Text("Pull to refresh to update progress.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.18)))
    }

    private func formatTrackedNumber(_ v: Double) -> String {
        if abs(v - Double(Int(v))) < 0.000_1 {
            return String(Int(v))
        }
        return String(format: "%.1f", v)
    }
}
