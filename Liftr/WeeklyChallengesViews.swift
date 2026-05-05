import SwiftUI
import UIKit
import Supabase

private struct WeeklyChallengesEmptyRpcParams: Encodable {}

// MARK: - RPC models (snake_case keys from PostgREST)

struct ActiveChallengeListRow: Decodable, Identifiable {
    var id: UUID { instance_id }
    let instance_id: UUID
    let template_code: String
    let title: String
    let description: String
    let cadence: String
    let period_start: Date
    let period_end: Date
    let max_winners: Int
    let claims_count: Int64
    let metric_kind: String
    let threshold_numeric: Double?
    let threshold_secondary: Double?
    let challenge_category: String?
    let scope_activity_code: String?
    let scope_sport: String?
    let scope_muscle_primary: String?
    let viewer_rank: Int?
    let viewer_claimed: Bool?

    /// True when the signed-in user has a podium slot on this instance (requires RPC with viewer_claimed).
    var viewerOnPodium: Bool { viewer_claimed == true }

    var resolvedCategory: String {
        let c = challenge_category?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let c, !c.isEmpty { return c }
        switch metric_kind {
        case "cumulative_cardio_km", "cardio_session_pace_gate": return "cardio"
        case "cumulative_sport_sessions": return "sport"
        default: return "strength"
        }
    }
}

struct ChallengeInstanceDetailRow: Decodable {
    let instance_id: UUID
    let template_code: String
    let title: String
    let description: String
    let cadence: String
    let period_start: Date
    let period_end: Date
    let max_winners: Int
    let claims_count: Int64
    let metric_kind: String
    let threshold_numeric: Double?
    let threshold_secondary: Double?
    let viewer_rank: Int?
    let viewer_claimed: Bool
    let viewer_workout_id: Int64?
}

struct ChallengeClaimLeaderRow: Decodable, Identifiable {
    var id: String { "\(user_id)-\(rank)" }
    let rank: Int
    let user_id: UUID
    let username: String?
    let avatar_url: String?
    let adjudication_ts: Date
    let workout_id: Int64?
}

struct ChallengeMyProgressRow: Decodable {
    let progress_value: Double?
    let target_value: Double?
    let secondary_cap: Double?
    let metric_kind: String?
    let is_eligible: Bool?
}

@MainActor
final class WeeklyChallengesLoader: ObservableObject {
    @Published var items: [ActiveChallengeListRow] = []
    @Published var loading = false
    @Published var error: String?

    func load() {
        Task { await refresh() }
    }

    func refresh() async {
        loading = true
        defer { loading = false }
        error = nil
        do {
            let res = try await SupabaseManager.shared.client
                .rpc("list_active_challenges_v1", params: WeeklyChallengesEmptyRpcParams())
                .execute()
            let rows = try JSONDecoder.supabase().decode([ActiveChallengeListRow].self, from: res.data)
            self.items = rows
        } catch {
            self.error = Self.friendlyLoadError(error)
            self.items = []
        }
    }

    static func friendlyLoadError(_ error: Error) -> String {
        let msg = error.localizedDescription
        if msg.range(of: "read-only transaction", options: .caseInsensitive) != nil {
            return "Couldn’t load challenges. Redeploy the latest weekly-challenges SQL (RPCs must be VOLATILE), then try again."
        }
        return "Couldn’t load challenges. Pull down to retry."
    }
}

private func formatChallengeProgress(
    metricKind: String,
    progress: Double?,
    target: Double?,
    secondary: Double?
) -> String {
    let p = progress ?? 0
    let t = target ?? 0
    switch metricKind {
    case "cumulative_cardio_km":
        return String(format: "%.1f / %.0f km", p, t)
    case "single_set_max_kg":
        return String(format: "%.0f / %.0f kg (best single set)", p, t)
    case "cardio_session_pace_gate":
        let capMin = Int(secondary ?? 3600) / 60
        return String(format: "%.1f km (goal ≥ %.0f km in ≤ %d min)", p, t, capMin)
    case "cumulative_sport_sessions":
        return String(format: "%.0f / %.0f sport workouts", p, t)
    case "cumulative_strength_workouts":
        return String(format: "%.0f / %.0f strength workouts", p, t)
    case "cumulative_strength_reps":
        return String(format: "%.0f / %.0f reps", p, t)
    case "cumulative_strength_sets":
        return String(format: "%.0f / %.0f sets", p, t)
    case "cumulative_strength_volume_kg":
        return String(format: "%.0f / %.0f kg volume", p, t)
    case "single_set_max_reps":
        return String(format: "%.0f / %.0f reps (best set)", p, t)
    case "strength_workouts_touching_muscle":
        return String(format: "%.0f / %.0f focused workouts", p, t)
    default:
        return "—"
    }
}

private var challengeHubListRowBackground: some View {
    RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(Color.white.opacity(0.14))
}

private func challengePeriodEndCaption(cadence: String, periodEnd: Date) -> String {
    let c = cadence.lowercased()
    if c == "once" { return "Does not expire" }
    let y = Calendar.current.component(.year, from: periodEnd)
    if y >= 2090 { return "Does not expire" }
    return "Ends \(periodEnd.formatted(date: .abbreviated, time: .omitted))"
}

private enum ChallengeHubCategoryFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case cardio = "Cardio"
    case strength = "Strength"
    case sport = "Sport"
    var id: String { rawValue }
    var wire: String? {
        switch self {
        case .all: return nil
        case .cardio: return "cardio"
        case .strength: return "strength"
        case .sport: return "sport"
        }
    }
}

private enum ChallengeHubCadenceFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case week = "Weekly"
    case month = "Monthly"
    case once = "Open"
    var id: String { rawValue }
    var wire: String? {
        switch self {
        case .all: return nil
        case .week: return "week"
        case .month: return "month"
        case .once: return "once"
        }
    }
}

private enum ChallengeHubParticipationFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case onPodium = "On podium"
    var id: String { rawValue }
}

private func challengeCadenceLabel(_ raw: String) -> String {
    switch raw.lowercased() {
    case "week": return "Weekly"
    case "month": return "Monthly"
    case "once": return "Open"
    default: return raw.capitalized
    }
}

/// Full-screen hub from Ranking FAB: list all active challenges.
struct WeeklyChallengesHubView: View {
    @ObservedObject var loader: WeeklyChallengesLoader
    var onDismiss: (() -> Void)?

    @State private var searchText = ""
    @State private var categoryFilter: ChallengeHubCategoryFilter = .all
    @State private var cadenceFilter: ChallengeHubCadenceFilter = .all
    @State private var participationFilter: ChallengeHubParticipationFilter = .all

    private var filteredItems: [ActiveChallengeListRow] {
        var rows = loader.items
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !q.isEmpty {
            rows = rows.filter {
                $0.title.lowercased().contains(q)
                    || $0.description.lowercased().contains(q)
                    || $0.template_code.lowercased().contains(q)
            }
        }
        if participationFilter == .onPodium {
            rows = rows.filter { $0.viewerOnPodium }
        }
        if let want = categoryFilter.wire {
            rows = rows.filter { $0.resolvedCategory == want }
        }
        if let wantCad = cadenceFilter.wire {
            rows = rows.filter { $0.cadence.lowercased() == wantCad }
        }
        return rows
    }

    var body: some View {
        Group {
            if loader.loading && loader.items.isEmpty {
                ProgressView("Loading challenges…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = loader.error, loader.items.isEmpty {
                VStack(spacing: 12) {
                    Text(err)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                    if onDismiss != nil {
                        Button("Close") { onDismiss?() }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if loader.items.isEmpty {
                VStack(spacing: 12) {
                    Text("No active challenges right now.")
                        .foregroundStyle(.secondary)
                    if onDismiss != nil {
                        Button("Close") { onDismiss?() }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    Section {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Limited podium slots; not achievements or personal weekly goals. Published workouts in the window count.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    Text("Type")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    ForEach(ChallengeHubCategoryFilter.allCases) { f in
                                        filterChip(title: f.rawValue, selected: categoryFilter == f) {
                                            categoryFilter = f
                                        }
                                    }
                                }
                            }
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    Text("When")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    ForEach(ChallengeHubCadenceFilter.allCases) { f in
                                        filterChip(title: f.rawValue, selected: cadenceFilter == f) {
                                            cadenceFilter = f
                                        }
                                    }
                                }
                            }
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    Text("You")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    ForEach(ChallengeHubParticipationFilter.allCases) { f in
                                        filterChip(title: f.rawValue, selected: participationFilter == f) {
                                            participationFilter = f
                                        }
                                    }
                                }
                            }
                        }
                        .listRowBackground(Color.clear)
                    }
                    if filteredItems.isEmpty {
                        Section {
                            Text("No challenges match your filters.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .listRowBackground(Color.clear)
                        }
                    } else {
                        ForEach(filteredItems) { row in
                            NavigationLink {
                                WeeklyChallengeDetailView(instanceId: row.instance_id)
                                    .gradientBG()
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(challengeCadenceLabel(row.cadence))
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 3)
                                            .background(Capsule().fill(Color(uiColor: .tertiarySystemFill)))
                                        Spacer()
                                    }
                                    Text(row.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    if row.viewerOnPodium, let vr = row.viewer_rank {
                                        Text("You’re #\(vr) on the podium")
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(.green)
                                    }
                                    Text("\(row.claims_count) / \(row.max_winners) slots · \(challengePeriodEndCaption(cadence: row.cadence, periodEnd: row.period_end))")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 4)
                            }
                            .listRowBackground(
                                challengeHubListRowBackground
                                    .padding(.vertical, 3)
                                    .padding(.horizontal, 2)
                            )
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("Challenges")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search challenges")
        .toolbar {
            if onDismiss != nil {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { onDismiss?() }
                }
            }
        }
        .task { await loader.refresh() }
        .refreshable { await loader.refresh() }
    }

    private func filterChip(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(selected ? Color.accentColor.opacity(0.35) : Color.white.opacity(0.12))
                )
                .foregroundStyle(selected ? Color.primary : Color.secondary)
        }
        .buttonStyle(.plain)
    }
}

struct WeeklyChallengeDetailView: View {
    let instanceId: UUID
    var onClose: (() -> Void)? = nil

    @State private var detail: ChallengeInstanceDetailRow?
    @State private var leaderboard: [ChallengeClaimLeaderRow] = []
    @State private var progress: ChallengeMyProgressRow?
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        Group {
            if loading {
                ProgressView()
            } else if let error {
                Text(error)
                    .foregroundStyle(.secondary)
            } else if let d = detail {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if onClose != nil {
                            HStack {
                                Spacer()
                                Button("Close") { onClose?() }
                                    .font(.subheadline.weight(.semibold))
                            }
                        }
                        Text(challengeCadenceLabel(d.cadence))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color(uiColor: .tertiarySystemFill)))
                        Text(d.title)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.primary)
                        Text(d.description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if let pr = progress, let mk = pr.metric_kind {
                            Text("Your progress: \(formatChallengeProgress(metricKind: mk, progress: pr.progress_value, target: pr.target_value, secondary: pr.secondary_cap))")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)
                            if pr.is_eligible == true && d.viewer_claimed == false {
                                Text("You meet the criteria; if a slot is open, publishing the workout should record your claim.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if d.viewer_claimed, let r = d.viewer_rank {
                            Text("You’re on the podium (#\(r)).")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.green)
                        }
                        Text("Standings (\(d.claims_count) / \(d.max_winners))")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        if leaderboard.isEmpty {
                            Text("No winners in this period yet.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(leaderboard) { row in
                                HStack(spacing: 10) {
                                    Text("#\(row.rank)")
                                        .font(.subheadline.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                        .frame(width: 28, alignment: .trailing)
                                    AvatarView(urlString: row.avatar_url)
                                        .frame(width: 36, height: 36)
                                    VStack(alignment: .leading, spacing: 2) {
                                        NavigationLink {
                                            ProfileView(userId: row.user_id).gradientBG()
                                        } label: {
                                            Text(row.username ?? "User")
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(.primary)
                                        }
                                        .buttonStyle(.plain)
                                        Text(row.adjudication_ts.formatted(date: .abbreviated, time: .shortened))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                    .padding()
                }
            } else {
                Text("Challenge not found")
            }
        }
        .task { await load() }
    }

    private func load() async {
        loading = true
        error = nil
        defer { loading = false }
        struct IdParams: Encodable {
            let p_instance_id: UUID
        }
        struct LimParams: Encodable {
            let p_instance_id: UUID
            let p_limit: Int
        }
        do {
            let dRes = try await SupabaseManager.shared.client
                .rpc("get_challenge_instance_detail_v1", params: IdParams(p_instance_id: instanceId))
                .execute()
            let dRows = try JSONDecoder.supabase().decode([ChallengeInstanceDetailRow].self, from: dRes.data)
            detail = dRows.first

            let lRes = try await SupabaseManager.shared.client
                .rpc("get_challenge_instance_leaderboard_v1", params: LimParams(p_instance_id: instanceId, p_limit: 20))
                .execute()
            leaderboard = try JSONDecoder.supabase().decode([ChallengeClaimLeaderRow].self, from: lRes.data)

            let pRes = try await SupabaseManager.shared.client
                .rpc("get_challenge_my_progress_v1", params: IdParams(p_instance_id: instanceId))
                .execute()
            let pRows = try JSONDecoder.supabase().decode([ChallengeMyProgressRow].self, from: pRes.data)
            progress = pRows.first
        } catch {
            self.error = WeeklyChallengesLoader.friendlyLoadError(error)
        }
    }
}
