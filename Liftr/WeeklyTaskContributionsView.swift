import SwiftUI
import Supabase

enum WeeklyTaskProgressFormat {
    static func formatValue(metric: String, value: Double, secondary: Double? = nil) -> String {
        switch metric {
        case "pace_sec_per_km":
            let mins = Int(value / 60)
            let secs = Int(value.truncatingRemainder(dividingBy: 60))
            return String(format: "%d:%02d", mins, secs)
        case "duration_sec":
            return String(Int((value / 60).rounded()))
        case "distance_km", "volume_kg", "max_weight_kg":
            if value == value.rounded() && abs(value - value.rounded()) < 0.05 {
                return String(format: "%.1f", value)
            }
            return String(format: "%.1f", value)
        default:
            return String(Int(value.rounded()))
        }
    }

    static func formatWithUnit(metric: String, value: Double) -> String {
        let v = formatValue(metric: metric, value: value)
        switch metric {
        case "calories_kcal": return "\(v) kcal"
        case "distance_km": return "\(v) km"
        case "duration_sec", "sport_weekly_minutes", "hyrox_weekly_minutes": return "\(v) min"
        case "sport_sessions_weekly":
            let n = Int(value.rounded())
            return n == 1 ? "1 session" : "\(n) sessions"
        case "volume_kg", "max_weight_kg": return "\(v) kg"
        case "total_reps": return "\(v) reps"
        case "total_sets": return "\(v) sets"
        case "routes_sent":
            let n = Int(value.rounded())
            return n == 1 ? "1 route" : "\(n) routes"
        case "problems_sent":
            let n = Int(value.rounded())
            return n == 1 ? "1 problem" : "\(n) problems"
        case "pace_sec_per_km": return "\(v) min/km"
        default: return v
        }
    }
}

extension UserWeeklyTaskRow {
    var progressPercentInt: Int {
        if isCompleted { return 100 }
        guard let target = target_value, target > 0 else { return 0 }
        let progress = progress_value ?? 0
        return min(100, max(0, Int((progress / target * 100).rounded())))
    }

    var displayProgressRatio: Double {
        Double(progressPercentInt) / 100.0
    }

    var showsProgressBlock: Bool {
        isAccepted || isCompleted
    }

    var progressCurrentLabel: String {
        WeeklyTaskProgressFormat.formatWithUnit(
            metric: target_metric,
            value: isCompleted ? (target_value ?? 0) : (progress_value ?? 0)
        )
    }

    var progressTargetLabel: String {
        WeeklyTaskProgressFormat.formatWithUnit(
            metric: target_metric,
            value: target_value ?? 0
        )
    }
}

extension UserWeeklyTaskRow: Hashable {
    static func == (lhs: UserWeeklyTaskRow, rhs: UserWeeklyTaskRow) -> Bool {
        lhs.task_id == rhs.task_id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(task_id)
    }
}

private struct TaskIdParams: Encodable {
    let p_task_id: UUID
}

struct UserTaskDetailRow: Decodable {
    let task_id: UUID
    let title: String
    let description: String
    let category: String
    let target_metric: String
    let target_value: Double?
    let reward_xp: Int
    let reward_coins: Int
    let reward_task_points: Int
    let difficulty_band: String?
    let status: String
    let progress_value: Double?
    let progress_percent: Int?
    let progress_current_label: String?
    let progress_target_label: String?
}

struct UserTaskWorkoutContributionRow: Decodable, Identifiable {
    var id: Int { workout_id }
    let workout_id: Int
    let kind: String
    let title: String?
    let started_at: Date?
    let state: String
    let calories_kcal: Double?
    let contribution_value: Double?
    let qualifies: Bool
    let contribution_label: String?
}

struct WeeklyTaskContributionsView: View {
    let task: UserWeeklyTaskRow

    @State private var detail: UserTaskDetailRow?
    @State private var workoutRows: [WorkoutFeedCardItem] = []
    @State private var contributions: [UserTaskWorkoutContributionRow] = []
    @State private var loading = true
    @State private var error: String?

    private var qualifyingCount: Int {
        contributions.filter(\.qualifies).count
    }

    private var bestContributionLabel: String? {
        contributions
            .map { ($0.contribution_value ?? 0, $0.contribution_label) }
            .max(by: { $0.0 < $1.0 })?
            .1
    }

    var body: some View {
        Group {
            if loading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error {
                ContentUnavailableView("Couldn't load task", systemImage: "exclamationmark.triangle", description: Text(error))
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if let detail {
                            detailHeader(detail)
                        }
                        summaryCard
                        if workoutRows.isEmpty {
                            Text("No workouts logged this week that count toward this task yet.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 8)
                        } else {
                            ForEach(workoutRows) { item in
                                let contrib = contributions.first { $0.workout_id == item.workoutId }
                                NavigationLink {
                                    WorkoutDetailView(workoutId: item.workoutId, ownerId: item.userId)
                                } label: {
                                    VStack(alignment: .leading, spacing: 6) {
                                        if let label = contrib?.contribution_label, !label.isEmpty {
                                            HStack {
                                                Text(label)
                                                    .font(.caption.weight(.semibold))
                                                    .foregroundStyle(contrib?.qualifies == true ? Color.green : Color.orange)
                                                if contrib?.qualifies == true {
                                                    Text("Qualifies")
                                                        .font(.caption2.weight(.bold))
                                                        .padding(.horizontal, 6)
                                                        .padding(.vertical, 2)
                                                        .background(Color.green.opacity(0.15), in: Capsule())
                                                }
                                                Spacer()
                                            }
                                        }
                                        WorkoutFeedCard(item: item, dayGroupLabel: nil)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
            }
        }
        .navigationTitle(detail?.title ?? task.title)
        .navigationBarTitleDisplayMode(.inline)
        .background(Color.clear)
        .gradientBG()
        .task { await load() }
    }

    @ViewBuilder
    private func detailHeader(_ d: UserTaskDetailRow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(d.category.capitalized)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.15), in: Capsule())
                if let band = d.difficulty_band, !band.isEmpty {
                    Text(band.capitalized)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(d.status.capitalized)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Text(d.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if d.status == "accepted" || d.status == "completed" {
                HStack {
                    Text("Progress")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(d.progress_percent ?? task.progressPercentInt)%")
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: Double(d.progress_percent ?? task.progressPercentInt) / 100.0)
                    .tint(.orange)
                Text("\(d.progress_current_label ?? task.progressCurrentLabel) / \(d.progress_target_label ?? task.progressTargetLabel)")
                    .font(.caption.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                Label("\(d.reward_xp) XP", systemImage: "star.fill")
                Label("\(d.reward_coins)", systemImage: "bitcoinsign.circle.fill")
                Label("\(d.reward_task_points) TP", systemImage: "flag.fill")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(.white.opacity(0.18)))
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Week summary")
                .font(.subheadline.weight(.semibold))
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Workouts")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(workoutRows.count)")
                        .font(.title3.weight(.bold))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Qualifying")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(qualifyingCount)")
                        .font(.title3.weight(.bold))
                }
                if let best = bestContributionLabel {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Best")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(best)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(.white.opacity(0.18)))
    }

    private func load() async {
        await MainActor.run {
            loading = true
            error = nil
        }
        do {
            let client = SupabaseManager.shared.client
            let detailRes = try await client
                .rpc("get_user_task_detail_v1", params: TaskIdParams(p_task_id: task.task_id))
                .execute()
            let detailRows = try JSONDecoder.supabase().decode([UserTaskDetailRow].self, from: detailRes.data)
            let contribRes = try await client
                .rpc("list_user_task_workouts_v1", params: TaskIdParams(p_task_id: task.task_id))
                .execute()
            let contribRows = try JSONDecoder.supabase().decode([UserTaskWorkoutContributionRow].self, from: contribRes.data)

            guard let uid = try? await client.auth.session.user.id else {
                throw NSError(domain: "WeeklyTask", code: 1, userInfo: [NSLocalizedDescriptionKey: "Not signed in"])
            }

            struct Prof: Decodable {
                let username: String
                let avatar_url: String?
            }
            let pRes = try await client
                .from("profiles")
                .select("username, avatar_url")
                .eq("user_id", value: uid.uuidString)
                .limit(1)
                .execute()
            let prof = try JSONDecoder.supabase().decode([Prof].self, from: pRes.data).first
            let username = prof?.username ?? "User"
            let avatarURL = prof?.avatar_url

            let ids = contribRows.map { String($0.workout_id) }
            var scores: [Int: Double] = [:]
            if !ids.isEmpty {
                let sRes = try await client
                    .from("workout_scores")
                    .select("workout_id, score")
                    .in("workout_id", values: ids)
                    .execute()
                struct S: Decodable { let workout_id: Int; let score: Decimal }
                let sRows = try JSONDecoder.supabase().decode([S].self, from: sRes.data)
                for r in sRows {
                    scores[r.workout_id, default: 0] += NSDecimalNumber(decimal: r.score).doubleValue
                }
            }

            let feedItems = contribRows.map { w in
                WorkoutFeedCardItem(
                    workoutId: w.workout_id,
                    userId: uid,
                    kind: w.kind,
                    title: w.title,
                    state: w.state,
                    startedAt: w.started_at,
                    endedAt: nil,
                    caloriesKcal: w.calories_kcal,
                    score: scores[w.workout_id],
                    sport: nil,
                    cardioActivity: nil,
                    username: username,
                    avatarURL: avatarURL,
                    likeCount: 0,
                    isLiked: false,
                    coUserAvatarURLs: []
                )
            }

            await MainActor.run {
                detail = detailRows.first
                contributions = contribRows
                workoutRows = feedItems
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
