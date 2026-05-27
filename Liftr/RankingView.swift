import SwiftUI
import Supabase

private func shouldIgnoreLeaderboardFetchError(_ error: Error) -> Bool {
    if error is CancellationError { return true }
    if let u = error as? URLError, u.code == .cancelled { return true }
    return false
}

struct LeaderRow: Decodable, Identifiable {
    var id: UUID { user_id }
    let rank: Int
    let user_id: UUID
    let username: String?
    let avatar_url: String?
    let total_score: Decimal
    let workouts_cnt: Int
}

struct CaloriesLeaderRow: Decodable, Identifiable {
    var id: UUID { user_id }
    let rank: Int
    let user_id: UUID
    let username: String?
    let avatar_url: String?
    let total_kcal: Decimal
    let workouts_cnt: Int
}

struct LevelRankRow: Decodable, Identifiable {
    var id: UUID { user_id }
    let rank: Int
    let user_id: UUID
    let username: String?
    let avatar_url: String?
    let level: Int
    let xp: Int64
}

struct GoalsLeaderRow: Decodable, Identifiable {
    var id: UUID { user_id }
    let rank: Int
    let user_id: UUID
    let username: String?
    let avatar_url: String?
    let completed_goals: Int64
    let goal_weeks: Int64
}

struct DuelsLeaderRow: Decodable, Identifiable {
    var id: UUID { user_id }
    let rank: Int
    let user_id: UUID
    let username: String?
    let avatar_url: String?
    let wins: Int64
    let duels_finished: Int64
}

struct WorkoutLeaderRow: Decodable, Identifiable {
    var id: String { "\(workout_id)-\(rank)" }
    let rank: Int
    let workout_id: Int64
    let user_id: UUID
    let username: String?
    let avatar_url: String?
    let kind: String
    let title: String?
    let started_at: Date
    let score: Decimal
}

struct StrengthVolumeLeaderRow: Decodable, Identifiable {
    var id: UUID { user_id }
    let rank: Int
    let user_id: UUID
    let username: String?
    let avatar_url: String?
    let total_volume_kg: Decimal
    let workouts_cnt: Int
}

struct CardioDistanceLeaderRow: Decodable, Identifiable {
    var id: UUID { user_id }
    let rank: Int
    let user_id: UUID
    let username: String?
    let avatar_url: String?
    let total_distance_km: Decimal
    let workouts_cnt: Int
}

struct SportWinsLeaderRow: Decodable, Identifiable {
    var id: UUID { user_id }
    let rank: Int
    let user_id: UUID
    let username: String?
    let avatar_url: String?
    let wins: Int64
    let matches_played: Int64
}

struct CardioElevationLeaderRow: Decodable, Identifiable {
    var id: UUID { user_id }
    let rank: Int
    let user_id: UUID
    let username: String?
    let avatar_url: String?
    let total_elevation_m: Int64
    let workouts_cnt: Int
}

struct CardioDurationLeaderRow: Decodable, Identifiable {
    var id: UUID { user_id }
    let rank: Int
    let user_id: UUID
    let username: String?
    let avatar_url: String?
    let total_duration_sec: Int64
    let workouts_cnt: Int
}

struct CardioBestPaceLeaderRow: Decodable, Identifiable {
    var id: UUID { user_id }
    let rank: Int
    let user_id: UUID
    let username: String?
    let avatar_url: String?
    let best_pace_sec_per_km: Int
    let qualifying_workouts_cnt: Int
}

struct StrengthRepsLeaderRow: Decodable, Identifiable {
    var id: UUID { user_id }
    let rank: Int
    let user_id: UUID
    let username: String?
    let avatar_url: String?
    let total_reps: Int64
    let workouts_cnt: Int
}

struct StrengthSetsLeaderRow: Decodable, Identifiable {
    var id: UUID { user_id }
    let rank: Int
    let user_id: UUID
    let username: String?
    let avatar_url: String?
    let total_sets: Int64
    let workouts_cnt: Int
}

struct StrengthMaxWeightLeaderRow: Decodable, Identifiable {
    var id: UUID { user_id }
    let rank: Int
    let user_id: UUID
    let username: String?
    let avatar_url: String?
    let max_weight_kg: Decimal
    let workouts_cnt: Int
}

struct SportDurationLeaderRow: Decodable, Identifiable {
    var id: UUID { user_id }
    let rank: Int
    let user_id: UUID
    let username: String?
    let avatar_url: String?
    let total_duration_sec: Int64
    let workouts_cnt: Int
}

struct SportWinRateLeaderRow: Decodable, Identifiable {
    var id: UUID { user_id }
    let rank: Int
    let user_id: UUID
    let username: String?
    let avatar_url: String?
    let wins: Int64
    let matches_played: Int64
    let win_rate: Decimal
}

struct LikesReceivedLeaderRow: Decodable, Identifiable {
    var id: UUID { user_id }
    let rank: Int
    let user_id: UUID
    let username: String?
    let avatar_url: String?
    let likes_received: Int64
    let published_workouts_cnt: Int
}

struct CommentsReceivedLeaderRow: Decodable, Identifiable {
    var id: UUID { user_id }
    let rank: Int
    let user_id: UUID
    let username: String?
    let avatar_url: String?
    let comments_received: Int64
    let published_workouts_cnt: Int
}

struct GroupSessionsLeaderRow: Decodable, Identifiable {
    var id: UUID { user_id }
    let rank: Int
    let user_id: UUID
    let username: String?
    let avatar_url: String?
    let group_sessions_cnt: Int
    let published_workouts_cnt: Int
}

struct AchievementsLeaderRow: Decodable, Identifiable {
    var id: UUID { user_id }
    let rank: Int
    let user_id: UUID
    let username: String?
    let avatar_url: String?
    let unlocked_cnt: Int64
}

struct ChallengePodiumsLeaderRow: Decodable, Identifiable {
    var id: UUID { user_id }
    let rank: Int
    let user_id: UUID
    let username: String?
    let avatar_url: String?
    let podium_count: Int64
}

struct HyroxBestTimeLeaderRow: Decodable, Identifiable {
    var id: UUID { user_id }
    let rank: Int
    let user_id: UUID
    let username: String?
    let avatar_url: String?
    let best_official_time_sec: Int
    let hyrox_sessions_cnt: Int
}

struct FootballGoalsLeaderRow: Decodable, Identifiable {
    var id: UUID { user_id }
    let rank: Int
    let user_id: UUID
    let username: String?
    let avatar_url: String?
    let total_goals: Int64
    let sessions_cnt: Int
}

struct SkiDistanceKpiLeaderRow: Decodable, Identifiable {
    var id: UUID { user_id }
    let rank: Int
    let user_id: UUID
    let username: String?
    let avatar_url: String?
    let total_distance_km: Decimal
    let sessions_cnt: Int
}

struct SegmentPopularityLeaderRow: Decodable, Identifiable {
    var id: UUID { segment_id }
    let rank: Int
    let segment_id: UUID
    let name: String
    let efforts_count: Int64
    let buffer_m: Double?
}

enum LBScope: String, CaseIterable, Identifiable {
    case global = "Global", friends = "Friends"
    var id: String { rawValue }
}

enum LBPeriod: String, CaseIterable, Identifiable {
    case day = "Today", week = "This Week", month = "This Month", all = "All-time"
    var id: String { rawValue }
}

enum LBKind: String, CaseIterable, Identifiable {
    case all = "All", strength = "Strength", cardio = "Cardio", sport = "Sport"
    var id: String { rawValue }
}

enum LBMetricSection: String, CaseIterable, Identifiable {
    case general = "General"
    case social = "Social"
    case strength = "Strength"
    case cardio = "Cardio"
    case sport = "Sport"
    case segments = "Segments"
    var id: String { rawValue }
    
    func metrics(for kind: LBKind) -> [LBMetric] {
        let base: [LBMetric]
        switch self {
        case .general:
            base = [.score, .calories, .level, .bestWorkout, .goals, .duels, .challengePodiums]
        case .social:
            base = [.likesReceived, .commentsReceived, .groupSessions, .achievements]
        case .strength:
            base = [.strengthVolume, .strengthReps, .strengthSets, .strengthMaxSetWeight]
        case .cardio:
            base = [.cardioDistance, .cardioElevation, .cardioDuration, .cardioBestPace, .territoryShare, .territoryCells]
        case .sport:
            base = [
                .sportWins, .sportWinRate, .sportDuration,
                .hyroxBestTime, .footballGoals, .skiDistanceKpi
            ]
        case .segments:
            base = [.segmentPopularity]
        }
        return base.filter { $0.isVisible(for: kind) }
    }
}

enum LBMetric: String, CaseIterable, Identifiable {
    case score = "Score"
    case calories = "Calories"
    case level = "Level"
    case bestWorkout = "Top workouts"
    case goals = "Goals"
    case duels = "Duels"
    case challengePodiums = "Challenge podiums"
    case strengthVolume = "Strength vol"
    case strengthReps = "Strength reps"
    case strengthSets = "Strength sets"
    case strengthMaxSetWeight = "Max set (kg)"
    case cardioDistance = "Cardio km"
    case cardioElevation = "Cardio ascent (m)"
    case cardioDuration = "Cardio time"
    case cardioBestPace = "Cardio best pace"
    case territoryShare = "Territory %"
    case territoryCells = "Territory cells"
    case sportWins = "Sport wins"
    case sportWinRate = "Sport win %"
    case sportDuration = "Sport play time"
    case likesReceived = "Likes received"
    case commentsReceived = "Comments received"
    case groupSessions = "Group sessions (2+)"
    case achievements = "Achievements"
    case hyroxBestTime = "Hyrox best time"
    case footballGoals = "Football goals"
    case skiDistanceKpi = "Ski km"
    case segmentPopularity = "Segment efforts"
    var id: String { rawValue }
    
    func isVisible(for kind: LBKind) -> Bool {
        switch self {
        case .strengthVolume, .strengthReps, .strengthSets, .strengthMaxSetWeight:
            return kind == .all || kind == .strength
        case .cardioDistance, .cardioElevation, .cardioDuration, .cardioBestPace, .territoryShare, .territoryCells:
            return kind == .all || kind == .cardio
        case .sportWins, .sportWinRate, .sportDuration, .hyroxBestTime, .footballGoals, .skiDistanceKpi:
            return kind == .all || kind == .sport
        case .likesReceived, .commentsReceived, .groupSessions, .achievements:
            return kind == .all
        case .challengePodiums:
            return kind == .all
        case .segmentPopularity:
            return kind == .all
        default: return true
        }
    }
    
    static func chipCases(for kind: LBKind) -> [LBMetric] {
        LBMetric.allCases.filter { $0.isVisible(for: kind) }
    }
}

enum LBAgeBand: String, CaseIterable, Identifiable {
    case none = "All ages", a18_24="18–24", a25_34="25–34", a35_44="35–44", a45_54="45–54", a55p="55+"
    var id: String { rawValue }
}

private struct Section<Content: View>: View {
    @ViewBuilder var content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            content
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.22), lineWidth: 0.8))
        .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
    }
}

private struct RankingMetricPickerSheet: View {
    @Binding var metric: LBMetric
    let kind: LBKind
    @Binding var searchText: String
    @Environment(\.dismiss) private var dismiss
    
    private func matchesSearch(_ m: LBMetric) -> Bool {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return true }
        return m.rawValue.lowercased().contains(q)
    }
    
    private var metricRowBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.white.opacity(0.14))
    }
    
    var body: some View {
        ZStack {
            GradientBackground()
            NavigationStack {
                List {
                    ForEach(Array(LBMetricSection.allCases), id: \.rawValue) { section in
                        let items = section.metrics(for: kind).filter(matchesSearch)
                        if !items.isEmpty {
                            SwiftUI.Section {
                                ForEach(items, id: \.self) { m in
                                    Button {
                                        metric = m
                                        dismiss()
                                    } label: {
                                        HStack {
                                            Text(m.rawValue)
                                                .foregroundStyle(.primary)
                                            Spacer()
                                            if metric == m {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundStyle(Color.accentColor)
                                            }
                                        }
                                    }
                                    .listRowBackground(
                                        metricRowBackground
                                            .padding(.vertical, 3)
                                            .padding(.horizontal, 2)
                                    )
                                }
                            } header: {
                                Text(section.rawValue)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .textCase(nil)
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .navigationTitle("Metric")
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
                .searchable(text: $searchText, prompt: "Search metrics")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                }
            }
        }
    }
}

@MainActor
final class RankingVM: ObservableObject {
    @Published var rows: [LeaderRow] = []
    @Published var levelRows: [LevelRankRow] = []
    @Published var workoutRows: [WorkoutLeaderRow] = []
    @Published var goalsRows: [GoalsLeaderRow] = []
    @Published var duelsRows: [DuelsLeaderRow] = []
    @Published var kcalRows: [CaloriesLeaderRow] = []
    @Published var strengthVolumeRows: [StrengthVolumeLeaderRow] = []
    @Published var cardioDistanceRows: [CardioDistanceLeaderRow] = []
    @Published var sportWinsRows: [SportWinsLeaderRow] = []
    @Published var cardioElevationRows: [CardioElevationLeaderRow] = []
    @Published var cardioDurationRows: [CardioDurationLeaderRow] = []
    @Published var cardioBestPaceRows: [CardioBestPaceLeaderRow] = []
    @Published var strengthRepsRows: [StrengthRepsLeaderRow] = []
    @Published var strengthSetsRows: [StrengthSetsLeaderRow] = []
    @Published var strengthMaxWeightRows: [StrengthMaxWeightLeaderRow] = []
    @Published var sportDurationRows: [SportDurationLeaderRow] = []
    @Published var sportWinRateRows: [SportWinRateLeaderRow] = []
    @Published var likesReceivedRows: [LikesReceivedLeaderRow] = []
    @Published var commentsReceivedRows: [CommentsReceivedLeaderRow] = []
    @Published var groupSessionsRows: [GroupSessionsLeaderRow] = []
    @Published var achievementsRows: [AchievementsLeaderRow] = []
    @Published var challengePodiumsRows: [ChallengePodiumsLeaderRow] = []
    @Published var hyroxBestTimeRows: [HyroxBestTimeLeaderRow] = []
    @Published var footballGoalsRows: [FootballGoalsLeaderRow] = []
    @Published var skiDistanceKpiRows: [SkiDistanceKpiLeaderRow] = []
    @Published var segmentPopularityRows: [SegmentPopularityLeaderRow] = []
    @Published var territoryShareRows: [TerritoryShareLeaderRow] = []
    @Published var territoryCities: [TerritoryCityRegionRow] = []
    @Published var territoryCityKey: String?
    @Published var loading = false
    @Published var error: String?
    @Published var scope: LBScope = .global
    @Published var period: LBPeriod = .week
    @Published var kind: LBKind = .all
    @Published var metric: LBMetric = .score
    @Published var sexOpt: Sex? = nil
    @Published var age: LBAgeBand = .none
    
    private var task: Task<Void, Never>?
    
    func load() {
        task?.cancel()
        task = Task { await fetch() }
    }
    
    private func mapAge(_ a: LBAgeBand) -> String? {
        switch a {
        case .none: return nil
        case .a18_24: return "18-24"
        case .a25_34: return "25-34"
        case .a35_44: return "35-44"
        case .a45_54: return "45-54"
        case .a55p:   return "55+"
        }
    }
    private func mapKind(_ k: LBKind) -> String { k.rawValue.lowercased() }
    private func mapPeriod(_ p: LBPeriod) -> String {
        switch p { case .day: "day"; case .week: "week"; case .month: "month"; case .all: "all" }
    }
    
    private func ajString(_ s: String?) -> AnyJSON {
        if let s, let j = try? AnyJSON(s) { return j } else { return .null }
    }
    
    private func ajInt(_ n: Int?) -> AnyJSON {
        if let n, let j = try? AnyJSON(n) { return j } else { return .null }
    }
    
    private func ajDouble(_ n: Double) -> AnyJSON {
        if let j = try? AnyJSON(n) { return j } else { return .null }
    }
    
    private func clearAllRowBuffers() {
        rows = []
        kcalRows = []
        levelRows = []
        workoutRows = []
        goalsRows = []
        duelsRows = []
        strengthVolumeRows = []
        cardioDistanceRows = []
        sportWinsRows = []
        cardioElevationRows = []
        cardioDurationRows = []
        cardioBestPaceRows = []
        strengthRepsRows = []
        strengthSetsRows = []
        strengthMaxWeightRows = []
        sportDurationRows = []
        sportWinRateRows = []
        likesReceivedRows = []
        commentsReceivedRows = []
        groupSessionsRows = []
        achievementsRows = []
        challengePodiumsRows = []
        hyroxBestTimeRows = []
        footballGoalsRows = []
        skiDistanceKpiRows = []
        segmentPopularityRows = []
        territoryShareRows = []
    }
    
    private func fetchStrengthVolumeLeaderboard() async {
        do {
            var params: [String: AnyJSON] = [:]
            params["p_scope"] = ajString(scope == .global ? "global" : "friends")
            params["p_period"] = ajString(mapPeriod(period))
            params["p_limit"] = ajInt(100)
            params["p_sex"] = ajString(sexOpt?.rawValue)
            params["p_age_band"] = ajString(mapAge(age))
            params["p_muscle_primary"] = .null
            let res = try await SupabaseManager.shared.client
                .rpc("get_strength_volume_leaderboard_v1", params: params)
                .execute()
            let decoded = try JSONDecoder.supabase().decode([StrengthVolumeLeaderRow].self, from: res.data)
            await MainActor.run { self.strengthVolumeRows = decoded }
        } catch {
            guard !shouldIgnoreLeaderboardFetchError(error) else { return }
            await MainActor.run {
                self.error = error.localizedDescription
                self.strengthVolumeRows = []
            }
        }
    }
    
    private func fetchCardioDistanceLeaderboard() async {
        do {
            var params: [String: AnyJSON] = [:]
            params["p_scope"] = ajString(scope == .global ? "global" : "friends")
            params["p_period"] = ajString(mapPeriod(period))
            params["p_limit"] = ajInt(100)
            params["p_sex"] = ajString(sexOpt?.rawValue)
            params["p_age_band"] = ajString(mapAge(age))
            params["p_activity_code"] = .null
            let res = try await SupabaseManager.shared.client
                .rpc("get_cardio_distance_leaderboard_v1", params: params)
                .execute()
            let decoded = try JSONDecoder.supabase().decode([CardioDistanceLeaderRow].self, from: res.data)
            await MainActor.run { self.cardioDistanceRows = decoded }
        } catch {
            guard !shouldIgnoreLeaderboardFetchError(error) else { return }
            await MainActor.run {
                self.error = error.localizedDescription
                self.cardioDistanceRows = []
            }
        }
    }
    
    private func fetchSportWinsLeaderboard() async {
        do {
            var params: [String: AnyJSON] = [:]
            params["p_scope"] = ajString(scope == .global ? "global" : "friends")
            params["p_period"] = ajString(mapPeriod(period))
            params["p_limit"] = ajInt(100)
            params["p_sex"] = ajString(sexOpt?.rawValue)
            params["p_age_band"] = ajString(mapAge(age))
            params["p_sport"] = .null
            let res = try await SupabaseManager.shared.client
                .rpc("get_sport_match_wins_leaderboard_v1", params: params)
                .execute()
            let decoded = try JSONDecoder.supabase().decode([SportWinsLeaderRow].self, from: res.data)
            await MainActor.run { self.sportWinsRows = decoded }
        } catch {
            guard !shouldIgnoreLeaderboardFetchError(error) else { return }
            await MainActor.run {
                self.error = error.localizedDescription
                self.sportWinsRows = []
            }
        }
    }
    
    private func fetchCardioElevationLeaderboard() async {
        do {
            var params: [String: AnyJSON] = [:]
            params["p_scope"] = ajString(scope == .global ? "global" : "friends")
            params["p_period"] = ajString(mapPeriod(period))
            params["p_limit"] = ajInt(100)
            params["p_sex"] = ajString(sexOpt?.rawValue)
            params["p_age_band"] = ajString(mapAge(age))
            params["p_activity_code"] = .null
            let res = try await SupabaseManager.shared.client
                .rpc("get_cardio_elevation_leaderboard_v1", params: params)
                .execute()
            let decoded = try JSONDecoder.supabase().decode([CardioElevationLeaderRow].self, from: res.data)
            await MainActor.run { self.cardioElevationRows = decoded }
        } catch {
            guard !shouldIgnoreLeaderboardFetchError(error) else { return }
            await MainActor.run {
                self.error = error.localizedDescription
                self.cardioElevationRows = []
            }
        }
    }
    
    private func fetchCardioDurationLeaderboard() async {
        do {
            var params: [String: AnyJSON] = [:]
            params["p_scope"] = ajString(scope == .global ? "global" : "friends")
            params["p_period"] = ajString(mapPeriod(period))
            params["p_limit"] = ajInt(100)
            params["p_sex"] = ajString(sexOpt?.rawValue)
            params["p_age_band"] = ajString(mapAge(age))
            params["p_activity_code"] = .null
            let res = try await SupabaseManager.shared.client
                .rpc("get_cardio_duration_leaderboard_v1", params: params)
                .execute()
            let decoded = try JSONDecoder.supabase().decode([CardioDurationLeaderRow].self, from: res.data)
            await MainActor.run { self.cardioDurationRows = decoded }
        } catch {
            guard !shouldIgnoreLeaderboardFetchError(error) else { return }
            await MainActor.run {
                self.error = error.localizedDescription
                self.cardioDurationRows = []
            }
        }
    }
    
    private func fetchCardioBestPaceLeaderboard() async {
        do {
            var params: [String: AnyJSON] = [:]
            params["p_scope"] = ajString(scope == .global ? "global" : "friends")
            params["p_period"] = ajString(mapPeriod(period))
            params["p_limit"] = ajInt(100)
            params["p_sex"] = ajString(sexOpt?.rawValue)
            params["p_age_band"] = ajString(mapAge(age))
            params["p_activity_code"] = .null
            params["p_min_distance_km"] = ajDouble(1.0)
            let res = try await SupabaseManager.shared.client
                .rpc("get_cardio_best_pace_leaderboard_v1", params: params)
                .execute()
            let decoded = try JSONDecoder.supabase().decode([CardioBestPaceLeaderRow].self, from: res.data)
            await MainActor.run { self.cardioBestPaceRows = decoded }
        } catch {
            guard !shouldIgnoreLeaderboardFetchError(error) else { return }
            await MainActor.run {
                self.error = error.localizedDescription
                self.cardioBestPaceRows = []
            }
        }
    }
    
    private func fetchStrengthRepsLeaderboard() async {
        do {
            var params: [String: AnyJSON] = [:]
            params["p_scope"] = ajString(scope == .global ? "global" : "friends")
            params["p_period"] = ajString(mapPeriod(period))
            params["p_limit"] = ajInt(100)
            params["p_sex"] = ajString(sexOpt?.rawValue)
            params["p_age_band"] = ajString(mapAge(age))
            params["p_muscle_primary"] = .null
            let res = try await SupabaseManager.shared.client
                .rpc("get_strength_total_reps_leaderboard_v1", params: params)
                .execute()
            let decoded = try JSONDecoder.supabase().decode([StrengthRepsLeaderRow].self, from: res.data)
            await MainActor.run { self.strengthRepsRows = decoded }
        } catch {
            guard !shouldIgnoreLeaderboardFetchError(error) else { return }
            await MainActor.run {
                self.error = error.localizedDescription
                self.strengthRepsRows = []
            }
        }
    }
    
    private func fetchStrengthSetsLeaderboard() async {
        do {
            var params: [String: AnyJSON] = [:]
            params["p_scope"] = ajString(scope == .global ? "global" : "friends")
            params["p_period"] = ajString(mapPeriod(period))
            params["p_limit"] = ajInt(100)
            params["p_sex"] = ajString(sexOpt?.rawValue)
            params["p_age_band"] = ajString(mapAge(age))
            params["p_muscle_primary"] = .null
            let res = try await SupabaseManager.shared.client
                .rpc("get_strength_total_sets_leaderboard_v1", params: params)
                .execute()
            let decoded = try JSONDecoder.supabase().decode([StrengthSetsLeaderRow].self, from: res.data)
            await MainActor.run { self.strengthSetsRows = decoded }
        } catch {
            guard !shouldIgnoreLeaderboardFetchError(error) else { return }
            await MainActor.run {
                self.error = error.localizedDescription
                self.strengthSetsRows = []
            }
        }
    }
    
    private func fetchStrengthMaxWeightLeaderboard() async {
        do {
            var params: [String: AnyJSON] = [:]
            params["p_scope"] = ajString(scope == .global ? "global" : "friends")
            params["p_period"] = ajString(mapPeriod(period))
            params["p_limit"] = ajInt(100)
            params["p_sex"] = ajString(sexOpt?.rawValue)
            params["p_age_band"] = ajString(mapAge(age))
            params["p_muscle_primary"] = .null
            let res = try await SupabaseManager.shared.client
                .rpc("get_strength_max_set_weight_leaderboard_v1", params: params)
                .execute()
            let decoded = try JSONDecoder.supabase().decode([StrengthMaxWeightLeaderRow].self, from: res.data)
            await MainActor.run { self.strengthMaxWeightRows = decoded }
        } catch {
            guard !shouldIgnoreLeaderboardFetchError(error) else { return }
            await MainActor.run {
                self.error = error.localizedDescription
                self.strengthMaxWeightRows = []
            }
        }
    }
    
    private func fetchSportDurationLeaderboard() async {
        do {
            var params: [String: AnyJSON] = [:]
            params["p_scope"] = ajString(scope == .global ? "global" : "friends")
            params["p_period"] = ajString(mapPeriod(period))
            params["p_limit"] = ajInt(100)
            params["p_sex"] = ajString(sexOpt?.rawValue)
            params["p_age_band"] = ajString(mapAge(age))
            params["p_sport"] = .null
            let res = try await SupabaseManager.shared.client
                .rpc("get_sport_duration_leaderboard_v1", params: params)
                .execute()
            let decoded = try JSONDecoder.supabase().decode([SportDurationLeaderRow].self, from: res.data)
            await MainActor.run { self.sportDurationRows = decoded }
        } catch {
            guard !shouldIgnoreLeaderboardFetchError(error) else { return }
            await MainActor.run {
                self.error = error.localizedDescription
                self.sportDurationRows = []
            }
        }
    }
    
    private func fetchSportWinRateLeaderboard() async {
        do {
            var params: [String: AnyJSON] = [:]
            params["p_scope"] = ajString(scope == .global ? "global" : "friends")
            params["p_period"] = ajString(mapPeriod(period))
            params["p_limit"] = ajInt(100)
            params["p_sex"] = ajString(sexOpt?.rawValue)
            params["p_age_band"] = ajString(mapAge(age))
            params["p_sport"] = .null
            params["p_min_matches"] = ajInt(3)
            let res = try await SupabaseManager.shared.client
                .rpc("get_sport_win_rate_leaderboard_v1", params: params)
                .execute()
            let decoded = try JSONDecoder.supabase().decode([SportWinRateLeaderRow].self, from: res.data)
            await MainActor.run { self.sportWinRateRows = decoded }
        } catch {
            guard !shouldIgnoreLeaderboardFetchError(error) else { return }
            await MainActor.run {
                self.error = error.localizedDescription
                self.sportWinRateRows = []
            }
        }
    }
    
    private func fetchLikesReceivedLeaderboard() async {
        do {
            var params: [String: AnyJSON] = [:]
            params["p_scope"] = ajString(scope == .global ? "global" : "friends")
            params["p_period"] = ajString(mapPeriod(period))
            params["p_limit"] = ajInt(100)
            params["p_sex"] = ajString(sexOpt?.rawValue)
            params["p_age_band"] = ajString(mapAge(age))
            let res = try await SupabaseManager.shared.client
                .rpc("get_workout_likes_received_leaderboard_v1", params: params)
                .execute()
            let decoded = try JSONDecoder.supabase().decode([LikesReceivedLeaderRow].self, from: res.data)
            await MainActor.run { self.likesReceivedRows = decoded }
        } catch {
            guard !shouldIgnoreLeaderboardFetchError(error) else { return }
            await MainActor.run {
                self.error = error.localizedDescription
                self.likesReceivedRows = []
            }
        }
    }
    
    private func fetchCommentsReceivedLeaderboard() async {
        do {
            var params: [String: AnyJSON] = [:]
            params["p_scope"] = ajString(scope == .global ? "global" : "friends")
            params["p_period"] = ajString(mapPeriod(period))
            params["p_limit"] = ajInt(100)
            params["p_sex"] = ajString(sexOpt?.rawValue)
            params["p_age_band"] = ajString(mapAge(age))
            let res = try await SupabaseManager.shared.client
                .rpc("get_workout_comments_received_leaderboard_v1", params: params)
                .execute()
            let decoded = try JSONDecoder.supabase().decode([CommentsReceivedLeaderRow].self, from: res.data)
            await MainActor.run { self.commentsReceivedRows = decoded }
        } catch {
            guard !shouldIgnoreLeaderboardFetchError(error) else { return }
            await MainActor.run {
                self.error = error.localizedDescription
                self.commentsReceivedRows = []
            }
        }
    }
    
    private func fetchGroupSessionsLeaderboard() async {
        do {
            var params: [String: AnyJSON] = [:]
            params["p_scope"] = ajString(scope == .global ? "global" : "friends")
            params["p_period"] = ajString(mapPeriod(period))
            params["p_limit"] = ajInt(100)
            params["p_sex"] = ajString(sexOpt?.rawValue)
            params["p_age_band"] = ajString(mapAge(age))
            let res = try await SupabaseManager.shared.client
                .rpc("get_group_workout_sessions_leaderboard_v1", params: params)
                .execute()
            let decoded = try JSONDecoder.supabase().decode([GroupSessionsLeaderRow].self, from: res.data)
            await MainActor.run { self.groupSessionsRows = decoded }
        } catch {
            guard !shouldIgnoreLeaderboardFetchError(error) else { return }
            await MainActor.run {
                self.error = error.localizedDescription
                self.groupSessionsRows = []
            }
        }
    }
    
    private func fetchAchievementsLeaderboard() async {
        do {
            var params: [String: AnyJSON] = [:]
            params["p_scope"] = ajString(scope == .global ? "global" : "friends")
            params["p_period"] = ajString(mapPeriod(period))
            params["p_limit"] = ajInt(100)
            params["p_sex"] = ajString(sexOpt?.rawValue)
            params["p_age_band"] = ajString(mapAge(age))
            let res = try await SupabaseManager.shared.client
                .rpc("get_achievements_unlocked_period_leaderboard_v1", params: params)
                .execute()
            let decoded = try JSONDecoder.supabase().decode([AchievementsLeaderRow].self, from: res.data)
            await MainActor.run { self.achievementsRows = decoded }
        } catch {
            guard !shouldIgnoreLeaderboardFetchError(error) else { return }
            await MainActor.run {
                self.error = error.localizedDescription
                self.achievementsRows = []
            }
        }
    }

    private func fetchChallengePodiumsLeaderboard() async {
        do {
            var params: [String: AnyJSON] = [:]
            params["p_scope"] = ajString(scope == .global ? "global" : "friends")
            params["p_period"] = ajString(mapPeriod(period))
            params["p_limit"] = ajInt(100)
            params["p_sex"] = ajString(sexOpt?.rawValue)
            params["p_age_band"] = ajString(mapAge(age))
            let res = try await SupabaseManager.shared.client
                .rpc("get_challenge_podiums_period_leaderboard_v1", params: params)
                .execute()
            let decoded = try JSONDecoder.supabase().decode([ChallengePodiumsLeaderRow].self, from: res.data)
            await MainActor.run { self.challengePodiumsRows = decoded }
        } catch {
            guard !shouldIgnoreLeaderboardFetchError(error) else { return }
            await MainActor.run {
                self.error = error.localizedDescription
                self.challengePodiumsRows = []
            }
        }
    }
    
    private func fetchHyroxBestTimeLeaderboard() async {
        do {
            var params: [String: AnyJSON] = [:]
            params["p_scope"] = ajString(scope == .global ? "global" : "friends")
            params["p_period"] = ajString(mapPeriod(period))
            params["p_limit"] = ajInt(100)
            params["p_sex"] = ajString(sexOpt?.rawValue)
            params["p_age_band"] = ajString(mapAge(age))
            let res = try await SupabaseManager.shared.client
                .rpc("get_hyrox_best_official_time_leaderboard_v1", params: params)
                .execute()
            let decoded = try JSONDecoder.supabase().decode([HyroxBestTimeLeaderRow].self, from: res.data)
            await MainActor.run { self.hyroxBestTimeRows = decoded }
        } catch {
            guard !shouldIgnoreLeaderboardFetchError(error) else { return }
            await MainActor.run {
                self.error = error.localizedDescription
                self.hyroxBestTimeRows = []
            }
        }
    }
    
    private func fetchFootballGoalsLeaderboard() async {
        do {
            var params: [String: AnyJSON] = [:]
            params["p_scope"] = ajString(scope == .global ? "global" : "friends")
            params["p_period"] = ajString(mapPeriod(period))
            params["p_limit"] = ajInt(100)
            params["p_sex"] = ajString(sexOpt?.rawValue)
            params["p_age_band"] = ajString(mapAge(age))
            let res = try await SupabaseManager.shared.client
                .rpc("get_football_goals_leaderboard_v1", params: params)
                .execute()
            let decoded = try JSONDecoder.supabase().decode([FootballGoalsLeaderRow].self, from: res.data)
            await MainActor.run { self.footballGoalsRows = decoded }
        } catch {
            guard !shouldIgnoreLeaderboardFetchError(error) else { return }
            await MainActor.run {
                self.error = error.localizedDescription
                self.footballGoalsRows = []
            }
        }
    }
    
    private func fetchSkiDistanceKpiLeaderboard() async {
        do {
            var params: [String: AnyJSON] = [:]
            params["p_scope"] = ajString(scope == .global ? "global" : "friends")
            params["p_period"] = ajString(mapPeriod(period))
            params["p_limit"] = ajInt(100)
            params["p_sex"] = ajString(sexOpt?.rawValue)
            params["p_age_band"] = ajString(mapAge(age))
            let res = try await SupabaseManager.shared.client
                .rpc("get_ski_distance_leaderboard_v1", params: params)
                .execute()
            let decoded = try JSONDecoder.supabase().decode([SkiDistanceKpiLeaderRow].self, from: res.data)
            await MainActor.run { self.skiDistanceKpiRows = decoded }
        } catch {
            guard !shouldIgnoreLeaderboardFetchError(error) else { return }
            await MainActor.run {
                self.error = error.localizedDescription
                self.skiDistanceKpiRows = []
            }
        }
    }

    private func fetchSegmentPopularityLeaderboard() async {
        do {
            var params: [String: AnyJSON] = [:]
            params["p_period"] = ajString(mapPeriod(period))
            params["p_limit"] = ajInt(100)
            let res = try await SupabaseManager.shared.client
                .rpc("list_segments_popularity_leaderboard_v1", params: params)
                .execute()
            let decoded = try JSONDecoder.supabase().decode([SegmentPopularityLeaderRow].self, from: res.data)
            await MainActor.run { self.segmentPopularityRows = decoded }
        } catch {
            guard !shouldIgnoreLeaderboardFetchError(error) else { return }
            await MainActor.run {
                self.error = error.localizedDescription
                self.segmentPopularityRows = []
            }
        }
    }

    private func fetchTerritoryShareLeaderboard() async {
        let started = Date()
        let cities = await TerritoryCaptureClient.fetchTerritoryCityRegions()
        let pendingCount = cities.filter { TerritoryCaptureClient.isPendingTerritoryCityKey($0.city_key) }.count
        TerritoryCaptureClient.logTerritoryShare("ranking cities count=\(cities.count) pending=\(pendingCount) elapsedMs=\(Int(Date().timeIntervalSince(started) * 1000))")
        let cityKey = await MainActor.run { () -> String? in
            territoryCities = cities
            if let selectedKey = territoryCityKey,
               cities.contains(where: { $0.city_key == selectedKey }) {
                return selectedKey
            }
            let reference = AppState.shared.territoryReferenceCoordinate
            let preferred = TerritoryCaptureClient.preferredCityKey(
                latitude: reference?.latitude,
                longitude: reference?.longitude,
                from: cities
            )
            territoryCityKey = preferred
            return preferred
        }
        guard let cityKey, !cityKey.isEmpty else {
            TerritoryCaptureClient.logTerritoryShare("ranking leaderboard skipped missing cityKey")
            await MainActor.run { territoryShareRows = [] }
            return
        }
        let scopeValue = scope == .global ? "global" : "friends"
        let leaderboardStarted = Date()
        let decoded = await TerritoryCaptureClient.fetchTerritoryCityShareLeaderboard(
            cityKey: cityKey,
            scope: scopeValue
        )
        TerritoryCaptureClient.logTerritoryShare("ranking leaderboard cityKey=\(cityKey) scope=\(scopeValue) rows=\(decoded.count) elapsedMs=\(Int(Date().timeIntervalSince(leaderboardStarted) * 1000))")
        await MainActor.run { self.territoryShareRows = decoded }
        if pendingCount > 0 {
            TerritoryCaptureClient.refreshPendingTerritoryCityRegionsInBackground { updated in
                let remainingPending = updated.filter { TerritoryCaptureClient.isPendingTerritoryCityKey($0.city_key) }.count
                TerritoryCaptureClient.logTerritoryShare("ranking background cities count=\(updated.count) pending=\(remainingPending)")
                self.territoryCities = updated
            }
        }
    }

    private func fetchTerritoryTotalCellsLeaderboard() async {
        let scopeValue = scope == .global ? "global" : "friends"
        let decoded = await TerritoryCaptureClient.fetchTerritoryTotalCellsLeaderboard(
            scope: scopeValue
        )
        await MainActor.run {
            territoryCities = []
            territoryCityKey = nil
            territoryShareRows = decoded
        }
    }

    private func fetchLevelLeaderboard() async {
        do {
            var params: [String: AnyJSON] = [:]
            params["p_scope"]     = ajString(scope == .global ? "global" : "friends")
            params["p_limit"]     = ajInt(100)
            params["p_sex"]       = ajString(sexOpt?.rawValue)
            params["p_age_band"]  = ajString(mapAge(age))
            
            let res = try await SupabaseManager.shared.client
                .rpc("get_level_leaderboard_v1", params: params)
                .execute()
            
            let decoded = try JSONDecoder.supabase().decode([LevelRankRow].self, from: res.data)
            await MainActor.run {
                self.levelRows = decoded
                self.rows = []
                self.kcalRows = []
                self.workoutRows = []
                self.goalsRows = []
                self.duelsRows = []
            }
        } catch {
            guard !shouldIgnoreLeaderboardFetchError(error) else { return }
            await MainActor.run {
                self.error = error.localizedDescription
                self.levelRows = []
            }
        }
    }
    
    private func fetchBestWorkoutsLeaderboard() async {
        do {
            var params: [String: AnyJSON] = [:]
            params["p_scope"]     = ajString(scope == .global ? "global" : "friends")
            params["p_period"]    = ajString(mapPeriod(period))
            params["p_kind"]      = ajString(mapKind(kind))
            params["p_limit"]     = ajInt(100)
            params["p_sex"]       = ajString(sexOpt?.rawValue)
            params["p_age_band"]  = ajString(mapAge(age))

            let res = try await SupabaseManager.shared.client
                .rpc("get_best_workouts_leaderboard_v1", params: params)
                .execute()

            let decoded = try JSONDecoder.supabase().decode([WorkoutLeaderRow].self, from: res.data)
            await MainActor.run {
                self.workoutRows = decoded
                self.rows = []
                self.levelRows = []
                self.goalsRows = []
                self.duelsRows = []
            }
        } catch {
            guard !shouldIgnoreLeaderboardFetchError(error) else { return }
            await MainActor.run {
                self.error = error.localizedDescription
                self.workoutRows = []
            }
        }
    }
    
    private func fetchCaloriesLeaderboard() async {
        do {
            var params: [String: AnyJSON] = [:]
            params["p_scope"]     = ajString(scope == .global ? "global" : "friends")
            params["p_period"]    = ajString(mapPeriod(period))
            params["p_kind"]      = ajString(mapKind(kind))
            params["p_limit"]     = ajInt(100)
            params["p_sex"]       = ajString(sexOpt?.rawValue)
            params["p_age_band"]  = ajString(mapAge(age))

            let res = try await SupabaseManager.shared.client
                .rpc("get_calories_leaderboard_v1", params: params)
                .execute()

            let decoded = try JSONDecoder.supabase().decode([CaloriesLeaderRow].self, from: res.data)
            await MainActor.run {
                self.kcalRows = decoded
                self.rows = []
                self.levelRows = []
                self.workoutRows = []
                self.goalsRows = []
                self.duelsRows = []
            }
        } catch {
            guard !shouldIgnoreLeaderboardFetchError(error) else { return }
            await MainActor.run {
                self.error = error.localizedDescription
                self.kcalRows = []
            }
        }
    }
    
    private func fetchGoalsCompletedLeaderboard() async {
        do {
            var params: [String: AnyJSON] = [:]
            params["p_scope"]     = ajString(scope == .global ? "global" : "friends")
            params["p_limit"]     = ajInt(100)
            params["p_sex"]       = ajString(sexOpt?.rawValue)
            params["p_age_band"]  = ajString(mapAge(age))
            
            let res = try await SupabaseManager.shared.client
                .rpc("get_goals_completed_leaderboard_v1", params: params)
                .execute()
            
            let decoded = try JSONDecoder.supabase().decode([GoalsLeaderRow].self, from: res.data)
            await MainActor.run {
                self.goalsRows = decoded
                self.rows = []
                self.kcalRows = []
                self.levelRows = []
                self.workoutRows = []
                self.duelsRows = []
            }
        } catch {
            guard !shouldIgnoreLeaderboardFetchError(error) else { return }
            await MainActor.run {
                self.error = error.localizedDescription
                self.goalsRows = []
            }
        }
    }
    
    private func fetchDuelsWonLeaderboard() async {
        do {
            var params: [String: AnyJSON] = [:]
            params["p_scope"]     = ajString(scope == .global ? "global" : "friends")
            params["p_limit"]     = ajInt(100)
            params["p_sex"]       = ajString(sexOpt?.rawValue)
            params["p_age_band"]  = ajString(mapAge(age))
            
            let res = try await SupabaseManager.shared.client
                .rpc("get_duels_won_leaderboard_v1", params: params)
                .execute()
            
            let decoded = try JSONDecoder.supabase().decode([DuelsLeaderRow].self, from: res.data)
            await MainActor.run {
                self.duelsRows = decoded
                self.rows = []
                self.kcalRows = []
                self.levelRows = []
                self.workoutRows = []
                self.goalsRows = []
            }
        } catch {
            guard !shouldIgnoreLeaderboardFetchError(error) else { return }
            await MainActor.run {
                self.error = error.localizedDescription
                self.duelsRows = []
            }
        }
    }
    
    private func fetch() async {
        loading = true
        error = nil
        clearAllRowBuffers()
        defer { loading = false }
        
        if metric == .level {
            await fetchLevelLeaderboard()
            return
        }
        if metric == .calories {
            await fetchCaloriesLeaderboard()
            return
        }
        if metric == .bestWorkout {
            await fetchBestWorkoutsLeaderboard()
            return
        }
        if metric == .goals {
            await fetchGoalsCompletedLeaderboard()
            return
        }
        if metric == .duels {
            await fetchDuelsWonLeaderboard()
            return
        }
        if metric == .strengthVolume {
            await fetchStrengthVolumeLeaderboard()
            return
        }
        if metric == .cardioDistance {
            await fetchCardioDistanceLeaderboard()
            return
        }
        if metric == .sportWins {
            await fetchSportWinsLeaderboard()
            return
        }
        if metric == .cardioElevation {
            await fetchCardioElevationLeaderboard()
            return
        }
        if metric == .cardioDuration {
            await fetchCardioDurationLeaderboard()
            return
        }
        if metric == .cardioBestPace {
            await fetchCardioBestPaceLeaderboard()
            return
        }
        if metric == .strengthReps {
            await fetchStrengthRepsLeaderboard()
            return
        }
        if metric == .strengthSets {
            await fetchStrengthSetsLeaderboard()
            return
        }
        if metric == .strengthMaxSetWeight {
            await fetchStrengthMaxWeightLeaderboard()
            return
        }
        if metric == .sportDuration {
            await fetchSportDurationLeaderboard()
            return
        }
        if metric == .sportWinRate {
            await fetchSportWinRateLeaderboard()
            return
        }
        if metric == .likesReceived {
            await fetchLikesReceivedLeaderboard()
            return
        }
        if metric == .commentsReceived {
            await fetchCommentsReceivedLeaderboard()
            return
        }
        if metric == .groupSessions {
            await fetchGroupSessionsLeaderboard()
            return
        }
        if metric == .achievements {
            await fetchAchievementsLeaderboard()
            return
        }
        if metric == .challengePodiums {
            await fetchChallengePodiumsLeaderboard()
            return
        }
        if metric == .hyroxBestTime {
            await fetchHyroxBestTimeLeaderboard()
            return
        }
        if metric == .footballGoals {
            await fetchFootballGoalsLeaderboard()
            return
        }
        if metric == .skiDistanceKpi {
            await fetchSkiDistanceKpiLeaderboard()
            return
        }
        if metric == .segmentPopularity {
            await fetchSegmentPopularityLeaderboard()
            return
        }
        if metric == .territoryShare {
            await fetchTerritoryShareLeaderboard()
            return
        }
        if metric == .territoryCells {
            await fetchTerritoryTotalCellsLeaderboard()
            return
        }
        
        do {
            var params: [String: AnyJSON] = [:]
            params["p_scope"]     = ajString(scope == .global ? "global" : "friends")
            params["p_period"]    = ajString(mapPeriod(period))
            params["p_kind"]      = ajString(mapKind(kind))
            params["p_algorithm"] = .null
            params["p_limit"]     = ajInt(100)
            params["p_sex"]       = ajString(sexOpt?.rawValue)
            params["p_age_band"]  = ajString(mapAge(age))
            
            let res = try await SupabaseManager.shared.client
                .rpc("get_leaderboard_v1", params: params)
                .execute()
            
            let decoded = try JSONDecoder.supabase().decode([LeaderRow].self, from: res.data)
            self.rows = decoded
            self.kcalRows = []
            self.levelRows = []
            self.workoutRows = []
            self.goalsRows = []
            self.duelsRows = []
        } catch {
            guard !shouldIgnoreLeaderboardFetchError(error) else { return }
            self.error = error.localizedDescription
            self.rows = []
            self.kcalRows = []
        }
    }
}

struct RankingView: View {
    var presetMetric: LBMetric? = nil
    var presetScope: LBScope? = nil

    @EnvironmentObject private var app: AppState
    @StateObject private var vm = RankingVM()
    @StateObject private var weeklyChallengesLoader = WeeklyChallengesLoader()
    @State private var challengesHubPresented = false
    @State private var didApplyRankingPreset = false
    @State private var metricPickerOpen = false
    @State private var metricSearchText = ""
    @State private var territoryCityPickerOpen = false
    @State private var showTerritoryMap = false
    var body: some View {
        GradientBackground {
            ZStack(alignment: .bottomTrailing) {
                VStack(spacing: 12) {
                    headerBars
                    listContent
                    if !app.isPremium {
                        BannerAdView(adUnitID: "ca-app-pub-7676731162362384/7781347704")
                            .frame(height: 50)
                            .padding(.horizontal)
                            .padding(.bottom, 8)
                    }
                }
                .padding(.horizontal, 12)

                Button {
                    challengesHubPresented = true
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "flag.checkered")
                            .font(.title2)
                            .foregroundStyle(.primary)
                            .frame(width: 52, height: 52)
                            .background(.ultraThinMaterial, in: Circle())
                            .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 0.8))
                        if weeklyChallengesLoader.loading == false, !weeklyChallengesLoader.items.isEmpty {
                            Text("\(weeklyChallengesLoader.items.count)")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(5)
                                .background(Color.red.opacity(0.9), in: Circle())
                                .offset(x: 6, y: -6)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Challenges")
                .padding(.trailing, 4)
                .padding(.bottom, app.isPremium ? 12 : 64)
            }
        }
        .sheet(isPresented: $challengesHubPresented) {
            NavigationStack {
                WeeklyChallengesHubView(loader: weeklyChallengesLoader) {
                    challengesHubPresented = false
                }
                .gradientBG()
            }
        }
        .onAppear {
            if !didApplyRankingPreset {
                if let m = presetMetric, m.isVisible(for: vm.kind) { vm.metric = m }
                if let s = presetScope { vm.scope = s }
                didApplyRankingPreset = true
            }
            vm.load()
            Task { await weeklyChallengesLoader.refresh() }
        }
        .onChange(of: vm.scope)  { _, _ in vm.load() }
        .onChange(of: vm.period) { _, _ in vm.load() }
        .onChange(of: vm.kind) { _, newKind in
            if !vm.metric.isVisible(for: newKind) {
                vm.metric = .score
            }
            vm.load()
        }
        .onChange(of: vm.sexOpt) { _, _ in vm.load() }
        .onChange(of: vm.age)    { _, _ in vm.load() }
        .onChange(of: vm.metric) { _, newMetric in
            if newMetric == .groupSessions, vm.period != .all {
                vm.period = .all
                return
            }
            vm.load()
        }
        .sheet(isPresented: $metricPickerOpen) {
            RankingMetricPickerSheet(metric: $vm.metric, kind: vm.kind, searchText: $metricSearchText)
                .presentationDetents([.medium, .large])
                .presentationBackground(.clear)
        }
        .sheet(isPresented: $territoryCityPickerOpen) {
            TerritoryCitySearchSheet(
                selectedCityKey: $vm.territoryCityKey,
                referenceLatitude: AppState.shared.territoryReferenceCoordinate?.latitude,
                referenceLongitude: AppState.shared.territoryReferenceCoordinate?.longitude
            ) { city in
                vm.territoryCityKey = city.city_key
                vm.load()
            }
            .presentationDetents([.medium, .large])
        }
        .fullScreenCover(isPresented: $showTerritoryMap) {
            NavigationStack {
                TerritoryMapView(
                    initialLatitude: TerritoryCaptureClient.selectedTerritoryCity(
                        from: vm.territoryCities,
                        preferredKey: vm.territoryCityKey,
                        referenceLatitude: AppState.shared.territoryReferenceCoordinate?.latitude,
                        referenceLongitude: AppState.shared.territoryReferenceCoordinate?.longitude
                    )?.center_lat,
                    initialLongitude: TerritoryCaptureClient.selectedTerritoryCity(
                        from: vm.territoryCities,
                        preferredKey: vm.territoryCityKey,
                        referenceLatitude: AppState.shared.territoryReferenceCoordinate?.latitude,
                        referenceLongitude: AppState.shared.territoryReferenceCoordinate?.longitude
                    )?.center_lon
                )
                .environmentObject(AppState.shared)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Close") { showTerritoryMap = false }
                    }
                }
            }
        }
    }
    
    private var headerBars: some View {
        VStack(spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    if vm.metric != .segmentPopularity {
                        Picker("Scope", selection: $vm.scope) {
                            ForEach(LBScope.allCases) {
                                Text($0.rawValue).lineLimit(1).minimumScaleFactor(0.85).tag($0)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    
                    if !metricSkipsPeriod(vm.metric) {
                        Picker("Period", selection: $vm.period) {
                            ForEach(LBPeriod.allCases) {
                                Text($0.rawValue).lineLimit(1).minimumScaleFactor(0.85).tag($0)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }
                VStack(spacing: 8) {
                    if vm.metric != .segmentPopularity {
                        Picker("Scope", selection: $vm.scope) {
                            ForEach(LBScope.allCases) {
                                Text($0.rawValue).lineLimit(1).minimumScaleFactor(0.85).tag($0)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    
                    if !metricSkipsPeriod(vm.metric) {
                        Picker("Period", selection: $vm.period) {
                            ForEach(LBPeriod.allCases) {
                                Text($0.rawValue).lineLimit(1).minimumScaleFactor(0.85).tag($0)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }
            }
            
            Button {
                metricSearchText = ""
                metricPickerOpen = true
            } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Metric")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(vm.metric.rawValue)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.18), lineWidth: 0.8)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Choose ranking metric")
            
            if vm.metric == .territoryShare {
                if vm.territoryCities.count > 1 {
                    TerritoryCityPickerButton(
                        selectedCity: TerritoryCaptureClient.selectedTerritoryCity(
                            from: vm.territoryCities,
                            preferredKey: vm.territoryCityKey,
                            referenceLatitude: AppState.shared.territoryReferenceCoordinate?.latitude,
                            referenceLongitude: AppState.shared.territoryReferenceCoordinate?.longitude
                        )
                    ) {
                        territoryCityPickerOpen = true
                    }
                } else if let city = vm.territoryCities.first {
                    Text(TerritoryCaptureClient.citySummaryLabel(for: city))
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if vm.metric == .territoryShare,
               let cityKey = vm.territoryCityKey,
               !TerritoryCaptureClient.isPendingTerritoryCityKey(cityKey) {
                Button("View on map") {
                    showTerritoryMap = true
                }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            HStack(spacing: 10) {
                if !metricSkipsKind(vm.metric) {
                    Menu {
                        Picker("Type", selection: $vm.kind) {
                            ForEach(LBKind.allCases) {
                                Text($0.rawValue).lineLimit(1).minimumScaleFactor(0.85).tag($0)
                            }
                        }
                    } label: {
                        Label(vm.kind.rawValue, systemImage: "trophy")
                    }
                }
                
                if vm.metric != .segmentPopularity {
                    Menu {
                        Picker("Sex", selection: Binding<Sex?>(
                            get: { vm.sexOpt },
                            set: { vm.sexOpt = $0 }
                        )) {
                            Text("All sexes").tag(Sex?.none)
                            ForEach(Sex.allCases, id: \.self) { Text($0.label).tag(Optional($0)) }
                        }
                    } label: {
                        Text(vm.sexOpt.map(\.label) ?? "All sexes")
                    }
                    
                    Menu {
                        Picker("Age", selection: $vm.age) {
                            ForEach(LBAgeBand.allCases) { Text($0.rawValue).tag($0) }
                        }
                    } label: {
                        Text(vm.age.rawValue)
                    }
                }
            }
            .font(.subheadline)
        }
    }
    
    private func metricSkipsPeriod(_ m: LBMetric) -> Bool {
        switch m {
        case .level, .goals, .duels, .territoryShare, .territoryCells: return true
        default: return false
        }
    }
    
    private func metricSkipsKind(_ m: LBMetric) -> Bool {
        switch m {
        case .level, .goals, .duels, .challengePodiums, .segmentPopularity, .territoryShare, .territoryCells: return true
        default: return false
        }
    }
    
    private var listContent: some View {
        Group {
            if vm.metric == .score {
                List(vm.rows) { row in
                    Section {
                        HStack(spacing: 12) {
                            Text("\(row.rank).")
                                .font(.headline)
                                .frame(width: 30, alignment: .trailing)
                            
                            AvatarView(urlString: row.avatar_url)
                                .frame(width: 36, height: 36)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                NavigationLink {
                                    ProfileView(userId: row.user_id).gradientBG()
                                } label: {
                                    Text(row.username ?? "user")
                                        .font(.subheadline.weight(.semibold))
                                        .lineLimit(1)
                                }
                                .buttonStyle(.plain)

                                Text("\(row.workouts_cnt) workouts")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(scoreString(row.total_score))
                                .font(.headline)
                                .monospacedDigit()
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                }
                .listStyle(.plain)
                .listRowSeparator(.hidden)
                .scrollContentBackground(.hidden)
                .scrollIndicators(.never)
                
            } else if vm.metric == .calories {
                List(vm.kcalRows) { row in
                    Section {
                        HStack(spacing: 12) {
                            Text("\(row.rank).")
                                .font(.headline)
                                .frame(width: 30, alignment: .trailing)
                            
                            AvatarView(urlString: row.avatar_url)
                                .frame(width: 36, height: 36)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                NavigationLink {
                                    ProfileView(userId: row.user_id).gradientBG()
                                } label: {
                                    Text(row.username ?? "user")
                                        .font(.subheadline.weight(.semibold))
                                        .lineLimit(1)
                                }
                                .buttonStyle(.plain)
                                
                                Text("\(row.workouts_cnt) workouts")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                            
                            Text(kcalString(row.total_kcal))
                                .font(.headline)
                                .monospacedDigit()
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                }
                .listStyle(.plain)
                .listRowSeparator(.hidden)
                .scrollContentBackground(.hidden)
                .scrollIndicators(.never)
            } else if vm.metric == .goals {
                List(vm.goalsRows) { row in
                    Section {
                        HStack(spacing: 12) {
                            Text("\(row.rank).")
                                .font(.headline)
                                .frame(width: 30, alignment: .trailing)
                            
                            AvatarView(urlString: row.avatar_url)
                                .frame(width: 36, height: 36)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                NavigationLink {
                                    ProfileView(userId: row.user_id).gradientBG()
                                } label: {
                                    Text(row.username ?? "user")
                                        .font(.subheadline.weight(.semibold))
                                        .lineLimit(1)
                                }
                                .buttonStyle(.plain)

                                Text("\(row.goal_weeks) weeks with completed goals")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(row.completed_goals) completed")
                                .font(.headline)
                                .monospacedDigit()
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                }
                .listStyle(.plain)
                .listRowSeparator(.hidden)
                .scrollContentBackground(.hidden)
                .scrollIndicators(.never)
            } else if vm.metric == .duels {
                List(vm.duelsRows) { row in
                    Section {
                        HStack(spacing: 12) {
                            Text("\(row.rank).")
                                .font(.headline)
                                .frame(width: 30, alignment: .trailing)
                            
                            AvatarView(urlString: row.avatar_url)
                                .frame(width: 36, height: 36)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                NavigationLink {
                                    ProfileView(userId: row.user_id).gradientBG()
                                } label: {
                                    Text(row.username ?? "user")
                                        .font(.subheadline.weight(.semibold))
                                        .lineLimit(1)
                                }
                                .buttonStyle(.plain)

                                Text("\(row.duels_finished) duels finished")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(row.wins) wins")
                                .font(.headline)
                                .monospacedDigit()
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                }
                .listStyle(.plain)
                .listRowSeparator(.hidden)
                .scrollContentBackground(.hidden)
                .scrollIndicators(.never)
            } else if vm.metric == .level {
                List(vm.levelRows) { row in
                    Section {
                        HStack(spacing: 12) {
                            Text("\(row.rank).")
                                .font(.headline)
                                .frame(width: 30, alignment: .trailing)
                            
                            AvatarView(urlString: row.avatar_url)
                                .frame(width: 36, height: 36)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                NavigationLink {
                                    ProfileView(userId: row.user_id).gradientBG()
                                } label: {
                                    Text(row.username ?? "user")
                                        .font(.subheadline.weight(.semibold))
                                        .lineLimit(1)
                                }
                                .buttonStyle(.plain)

                                Text("Level \(row.level)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(row.xp) XP")
                                .font(.headline)
                                .monospacedDigit()
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                }
                .listStyle(.plain)
                .listRowSeparator(.hidden)
                .scrollContentBackground(.hidden)
                .scrollIndicators(.never)

            } else if vm.metric == .bestWorkout {
                List(vm.workoutRows) { row in
                    Section {
                        HStack(spacing: 12) {
                            Text("\(row.rank).")
                                .font(.headline)
                                .frame(width: 30, alignment: .trailing)
                            
                            AvatarView(urlString: row.avatar_url)
                                .frame(width: 36, height: 36)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                NavigationLink {
                                    WorkoutDetailView(workoutId: Int(row.workout_id), ownerId: row.user_id)
                                        .gradientBG()
                                } label: {
                                    Text(row.username ?? "user")
                                        .font(.subheadline.weight(.semibold))
                                        .lineLimit(1)
                                }
                                .buttonStyle(.plain)

                                Text(row.title?.isEmpty == false ? row.title! : row.kind.capitalized)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                Text(dateFormatted(row.started_at))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary.opacity(0.7))
                            }
                            
                            Spacer()
                            
                            Text(scoreString(row.score))
                                .font(.headline)
                                .monospacedDigit()
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                }
                .listStyle(.plain)
                .listRowSeparator(.hidden)
                .scrollContentBackground(.hidden)
                .scrollIndicators(.never)
            } else if vm.metric == .strengthVolume {
                List(vm.strengthVolumeRows) { row in
                    Section {
                        HStack(spacing: 12) {
                            Text("\(row.rank).")
                                .font(.headline)
                                .frame(width: 30, alignment: .trailing)
                            AvatarView(urlString: row.avatar_url)
                                .frame(width: 36, height: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                NavigationLink {
                                    ProfileView(userId: row.user_id).gradientBG()
                                } label: {
                                    Text(row.username ?? "user")
                                        .font(.subheadline.weight(.semibold))
                                        .lineLimit(1)
                                }
                                .buttonStyle(.plain)
                                Text("\(row.workouts_cnt) workouts")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(volumeString(row.total_volume_kg))
                                .font(.headline)
                                .monospacedDigit()
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                }
                .listStyle(.plain)
                .listRowSeparator(.hidden)
                .scrollContentBackground(.hidden)
                .scrollIndicators(.never)
            } else if vm.metric == .cardioDistance {
                List(vm.cardioDistanceRows) { row in
                    Section {
                        HStack(spacing: 12) {
                            Text("\(row.rank).")
                                .font(.headline)
                                .frame(width: 30, alignment: .trailing)
                            AvatarView(urlString: row.avatar_url)
                                .frame(width: 36, height: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                NavigationLink {
                                    ProfileView(userId: row.user_id).gradientBG()
                                } label: {
                                    Text(row.username ?? "user")
                                        .font(.subheadline.weight(.semibold))
                                        .lineLimit(1)
                                }
                                .buttonStyle(.plain)
                                Text("\(row.workouts_cnt) workouts")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(distanceString(row.total_distance_km))
                                .font(.headline)
                                .monospacedDigit()
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                }
                .listStyle(.plain)
                .listRowSeparator(.hidden)
                .scrollContentBackground(.hidden)
                .scrollIndicators(.never)
            } else if vm.metric == .sportWins {
                List(vm.sportWinsRows) { row in
                    Section {
                        HStack(spacing: 12) {
                            Text("\(row.rank).")
                                .font(.headline)
                                .frame(width: 30, alignment: .trailing)
                            AvatarView(urlString: row.avatar_url)
                                .frame(width: 36, height: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                NavigationLink {
                                    ProfileView(userId: row.user_id).gradientBG()
                                } label: {
                                    Text(row.username ?? "user")
                                        .font(.subheadline.weight(.semibold))
                                        .lineLimit(1)
                                }
                                .buttonStyle(.plain)
                                Text("\(row.matches_played) matches logged")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(row.wins) wins")
                                .font(.headline)
                                .monospacedDigit()
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                }
                .listStyle(.plain)
                .listRowSeparator(.hidden)
                .scrollContentBackground(.hidden)
                .scrollIndicators(.never)
            } else if vm.metric == .cardioElevation {
                List(vm.cardioElevationRows) { row in
                    Section {
                        HStack(spacing: 12) {
                            Text("\(row.rank).")
                                .font(.headline)
                                .frame(width: 30, alignment: .trailing)
                            AvatarView(urlString: row.avatar_url)
                                .frame(width: 36, height: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                NavigationLink {
                                    ProfileView(userId: row.user_id).gradientBG()
                                } label: {
                                    Text(row.username ?? "user")
                                        .font(.subheadline.weight(.semibold))
                                        .lineLimit(1)
                                }
                                .buttonStyle(.plain)
                                Text("\(row.workouts_cnt) workouts")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(elevationString(row.total_elevation_m))
                                .font(.headline)
                                .monospacedDigit()
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                }
                .listStyle(.plain)
                .listRowSeparator(.hidden)
                .scrollContentBackground(.hidden)
                .scrollIndicators(.never)
            } else if vm.metric == .cardioDuration {
                List(vm.cardioDurationRows) { row in
                    Section {
                        HStack(spacing: 12) {
                            Text("\(row.rank).")
                                .font(.headline)
                                .frame(width: 30, alignment: .trailing)
                            AvatarView(urlString: row.avatar_url)
                                .frame(width: 36, height: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                NavigationLink {
                                    ProfileView(userId: row.user_id).gradientBG()
                                } label: {
                                    Text(row.username ?? "user")
                                        .font(.subheadline.weight(.semibold))
                                        .lineLimit(1)
                                }
                                .buttonStyle(.plain)
                                Text("\(row.workouts_cnt) workouts")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(durationStringFromSeconds(row.total_duration_sec))
                                .font(.headline)
                                .monospacedDigit()
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                }
                .listStyle(.plain)
                .listRowSeparator(.hidden)
                .scrollContentBackground(.hidden)
                .scrollIndicators(.never)
            } else if vm.metric == .cardioBestPace {
                List(vm.cardioBestPaceRows) { row in
                    Section {
                        HStack(spacing: 12) {
                            Text("\(row.rank).")
                                .font(.headline)
                                .frame(width: 30, alignment: .trailing)
                            AvatarView(urlString: row.avatar_url)
                                .frame(width: 36, height: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                NavigationLink {
                                    ProfileView(userId: row.user_id).gradientBG()
                                } label: {
                                    Text(row.username ?? "user")
                                        .font(.subheadline.weight(.semibold))
                                        .lineLimit(1)
                                }
                                .buttonStyle(.plain)
                                Text("\(row.qualifying_workouts_cnt) sessions ≥1 km")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(pacePerKmString(row.best_pace_sec_per_km))
                                .font(.headline)
                                .monospacedDigit()
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                }
                .listStyle(.plain)
                .listRowSeparator(.hidden)
                .scrollContentBackground(.hidden)
                .scrollIndicators(.never)
            } else if vm.metric == .strengthReps {
                List(vm.strengthRepsRows) { row in
                    Section {
                        HStack(spacing: 12) {
                            Text("\(row.rank).")
                                .font(.headline)
                                .frame(width: 30, alignment: .trailing)
                            AvatarView(urlString: row.avatar_url)
                                .frame(width: 36, height: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                NavigationLink {
                                    ProfileView(userId: row.user_id).gradientBG()
                                } label: {
                                    Text(row.username ?? "user")
                                        .font(.subheadline.weight(.semibold))
                                        .lineLimit(1)
                                }
                                .buttonStyle(.plain)
                                Text("\(row.workouts_cnt) workouts")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(row.total_reps) reps")
                                .font(.headline)
                                .monospacedDigit()
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                }
                .listStyle(.plain)
                .listRowSeparator(.hidden)
                .scrollContentBackground(.hidden)
                .scrollIndicators(.never)
            } else if vm.metric == .strengthSets {
                List(vm.strengthSetsRows) { row in
                    Section {
                        HStack(spacing: 12) {
                            Text("\(row.rank).")
                                .font(.headline)
                                .frame(width: 30, alignment: .trailing)
                            AvatarView(urlString: row.avatar_url)
                                .frame(width: 36, height: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                NavigationLink {
                                    ProfileView(userId: row.user_id).gradientBG()
                                } label: {
                                    Text(row.username ?? "user")
                                        .font(.subheadline.weight(.semibold))
                                        .lineLimit(1)
                                }
                                .buttonStyle(.plain)
                                Text("\(row.workouts_cnt) workouts")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(row.total_sets) sets")
                                .font(.headline)
                                .monospacedDigit()
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                }
                .listStyle(.plain)
                .listRowSeparator(.hidden)
                .scrollContentBackground(.hidden)
                .scrollIndicators(.never)
            } else if vm.metric == .strengthMaxSetWeight {
                List(vm.strengthMaxWeightRows) { row in
                    Section {
                        HStack(spacing: 12) {
                            Text("\(row.rank).")
                                .font(.headline)
                                .frame(width: 30, alignment: .trailing)
                            AvatarView(urlString: row.avatar_url)
                                .frame(width: 36, height: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                NavigationLink {
                                    ProfileView(userId: row.user_id).gradientBG()
                                } label: {
                                    Text(row.username ?? "user")
                                        .font(.subheadline.weight(.semibold))
                                        .lineLimit(1)
                                }
                                .buttonStyle(.plain)
                                Text("\(row.workouts_cnt) workouts")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(maxWeightString(row.max_weight_kg))
                                .font(.headline)
                                .monospacedDigit()
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                }
                .listStyle(.plain)
                .listRowSeparator(.hidden)
                .scrollContentBackground(.hidden)
                .scrollIndicators(.never)
            } else if vm.metric == .sportDuration {
                List(vm.sportDurationRows) { row in
                    Section {
                        HStack(spacing: 12) {
                            Text("\(row.rank).")
                                .font(.headline)
                                .frame(width: 30, alignment: .trailing)
                            AvatarView(urlString: row.avatar_url)
                                .frame(width: 36, height: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                NavigationLink {
                                    ProfileView(userId: row.user_id).gradientBG()
                                } label: {
                                    Text(row.username ?? "user")
                                        .font(.subheadline.weight(.semibold))
                                        .lineLimit(1)
                                }
                                .buttonStyle(.plain)
                                Text("\(row.workouts_cnt) workouts")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(durationStringFromSeconds(row.total_duration_sec))
                                .font(.headline)
                                .monospacedDigit()
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                }
                .listStyle(.plain)
                .listRowSeparator(.hidden)
                .scrollContentBackground(.hidden)
                .scrollIndicators(.never)
            } else if vm.metric == .sportWinRate {
                List(vm.sportWinRateRows) { row in
                    Section {
                        HStack(spacing: 12) {
                            Text("\(row.rank).")
                                .font(.headline)
                                .frame(width: 30, alignment: .trailing)
                            AvatarView(urlString: row.avatar_url)
                                .frame(width: 36, height: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                NavigationLink {
                                    ProfileView(userId: row.user_id).gradientBG()
                                } label: {
                                    Text(row.username ?? "user")
                                        .font(.subheadline.weight(.semibold))
                                        .lineLimit(1)
                                }
                                .buttonStyle(.plain)
                                Text("\(row.wins)W / \(row.matches_played)M (min 3)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(winRateString(row.win_rate))
                                .font(.headline)
                                .monospacedDigit()
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                }
                .listStyle(.plain)
                .listRowSeparator(.hidden)
                .scrollContentBackground(.hidden)
                .scrollIndicators(.never)
            } else if vm.metric == .likesReceived {
                List(vm.likesReceivedRows) { row in
                    Section {
                        HStack(spacing: 12) {
                            Text("\(row.rank).")
                                .font(.headline)
                                .frame(width: 30, alignment: .trailing)
                            AvatarView(urlString: row.avatar_url)
                                .frame(width: 36, height: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                NavigationLink {
                                    ProfileView(userId: row.user_id).gradientBG()
                                } label: {
                                    Text(row.username ?? "user")
                                        .font(.subheadline.weight(.semibold))
                                        .lineLimit(1)
                                }
                                .buttonStyle(.plain)
                                Text("\(row.published_workouts_cnt) published")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(row.likes_received)")
                                .font(.headline)
                                .monospacedDigit()
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                }
                .listStyle(.plain)
                .listRowSeparator(.hidden)
                .scrollContentBackground(.hidden)
                .scrollIndicators(.never)
            } else if vm.metric == .commentsReceived {
                List(vm.commentsReceivedRows) { row in
                    Section {
                        HStack(spacing: 12) {
                            Text("\(row.rank).")
                                .font(.headline)
                                .frame(width: 30, alignment: .trailing)
                            AvatarView(urlString: row.avatar_url)
                                .frame(width: 36, height: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                NavigationLink {
                                    ProfileView(userId: row.user_id).gradientBG()
                                } label: {
                                    Text(row.username ?? "user")
                                        .font(.subheadline.weight(.semibold))
                                        .lineLimit(1)
                                }
                                .buttonStyle(.plain)
                                Text("\(row.published_workouts_cnt) published")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(row.comments_received)")
                                .font(.headline)
                                .monospacedDigit()
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                }
                .listStyle(.plain)
                .listRowSeparator(.hidden)
                .scrollContentBackground(.hidden)
                .scrollIndicators(.never)
            } else if vm.metric == .groupSessions {
                List(vm.groupSessionsRows) { row in
                    Section {
                        HStack(spacing: 12) {
                            Text("\(row.rank).")
                                .font(.headline)
                                .frame(width: 30, alignment: .trailing)
                            AvatarView(urlString: row.avatar_url)
                                .frame(width: 36, height: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                NavigationLink {
                                    ProfileView(userId: row.user_id).gradientBG()
                                } label: {
                                    Text(row.username ?? "user")
                                        .font(.subheadline.weight(.semibold))
                                        .lineLimit(1)
                                }
                                .buttonStyle(.plain)
                                Text("of \(row.published_workouts_cnt) published in period")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(row.group_sessions_cnt)")
                                .font(.headline)
                                .monospacedDigit()
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                }
                .listStyle(.plain)
                .listRowSeparator(.hidden)
                .scrollContentBackground(.hidden)
                .scrollIndicators(.never)
            } else if vm.metric == .achievements {
                List(vm.achievementsRows) { row in
                    Section {
                        HStack(spacing: 12) {
                            Text("\(row.rank).")
                                .font(.headline)
                                .frame(width: 30, alignment: .trailing)
                            AvatarView(urlString: row.avatar_url)
                                .frame(width: 36, height: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                NavigationLink {
                                    ProfileView(userId: row.user_id).gradientBG()
                                } label: {
                                    Text(row.username ?? "user")
                                        .font(.subheadline.weight(.semibold))
                                        .lineLimit(1)
                                }
                                .buttonStyle(.plain)
                                Text("Unlocked \(periodLabel(vm.period))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(row.unlocked_cnt)")
                                .font(.headline)
                                .monospacedDigit()
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                }
                .listStyle(.plain)
                .listRowSeparator(.hidden)
                .scrollContentBackground(.hidden)
                .scrollIndicators(.never)
            } else if vm.metric == .challengePodiums {
                List(vm.challengePodiumsRows) { row in
                    Section {
                        HStack(spacing: 12) {
                            Text("\(row.rank).")
                                .font(.headline)
                                .frame(width: 30, alignment: .trailing)
                            AvatarView(urlString: row.avatar_url)
                                .frame(width: 36, height: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                NavigationLink {
                                    ProfileView(userId: row.user_id).gradientBG()
                                } label: {
                                    Text(row.username ?? "user")
                                        .font(.subheadline.weight(.semibold))
                                        .lineLimit(1)
                                }
                                .buttonStyle(.plain)
                                Text("Podium finishes \(periodLabel(vm.period))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(row.podium_count)")
                                .font(.headline)
                                .monospacedDigit()
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                }
                .listStyle(.plain)
                .listRowSeparator(.hidden)
                .scrollContentBackground(.hidden)
                .scrollIndicators(.never)
            } else if vm.metric == .hyroxBestTime {
                List(vm.hyroxBestTimeRows) { row in
                    Section {
                        HStack(spacing: 12) {
                            Text("\(row.rank).")
                                .font(.headline)
                                .frame(width: 30, alignment: .trailing)
                            AvatarView(urlString: row.avatar_url)
                                .frame(width: 36, height: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                NavigationLink {
                                    ProfileView(userId: row.user_id).gradientBG()
                                } label: {
                                    Text(row.username ?? "user")
                                        .font(.subheadline.weight(.semibold))
                                        .lineLimit(1)
                                }
                                .buttonStyle(.plain)
                                Text("\(row.hyrox_sessions_cnt) sessions")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(durationStringFromSeconds(Int64(row.best_official_time_sec)))
                                .font(.headline)
                                .monospacedDigit()
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                }
                .listStyle(.plain)
                .listRowSeparator(.hidden)
                .scrollContentBackground(.hidden)
                .scrollIndicators(.never)
            } else if vm.metric == .footballGoals {
                List(vm.footballGoalsRows) { row in
                    Section {
                        HStack(spacing: 12) {
                            Text("\(row.rank).")
                                .font(.headline)
                                .frame(width: 30, alignment: .trailing)
                            AvatarView(urlString: row.avatar_url)
                                .frame(width: 36, height: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                NavigationLink {
                                    ProfileView(userId: row.user_id).gradientBG()
                                } label: {
                                    Text(row.username ?? "user")
                                        .font(.subheadline.weight(.semibold))
                                        .lineLimit(1)
                                }
                                .buttonStyle(.plain)
                                Text("\(row.sessions_cnt) sessions")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(row.total_goals)")
                                .font(.headline)
                                .monospacedDigit()
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                }
                .listStyle(.plain)
                .listRowSeparator(.hidden)
                .scrollContentBackground(.hidden)
                .scrollIndicators(.never)
            } else if vm.metric == .skiDistanceKpi {
                List(vm.skiDistanceKpiRows) { row in
                    Section {
                        HStack(spacing: 12) {
                            Text("\(row.rank).")
                                .font(.headline)
                                .frame(width: 30, alignment: .trailing)
                            AvatarView(urlString: row.avatar_url)
                                .frame(width: 36, height: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                NavigationLink {
                                    ProfileView(userId: row.user_id).gradientBG()
                                } label: {
                                    Text(row.username ?? "user")
                                        .font(.subheadline.weight(.semibold))
                                        .lineLimit(1)
                                }
                                .buttonStyle(.plain)
                                Text("\(row.sessions_cnt) sessions")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(distanceString(row.total_distance_km))
                                .font(.headline)
                                .monospacedDigit()
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                }
                .listStyle(.plain)
                .listRowSeparator(.hidden)
                .scrollContentBackground(.hidden)
                .scrollIndicators(.never)
            } else if vm.metric == .territoryShare {
                List(vm.territoryShareRows) { row in
                    Section {
                        HStack(spacing: 12) {
                            Text("\(row.rank).")
                                .font(.headline)
                                .frame(width: 30, alignment: .trailing)
                            AvatarView(urlString: row.avatar_url)
                                .frame(width: 36, height: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                NavigationLink {
                                    ProfileView(userId: row.user_id).gradientBG()
                                } label: {
                                    Text(row.username ?? "user")
                                        .font(.subheadline.weight(.semibold))
                                        .lineLimit(1)
                                }
                                .buttonStyle(.plain)
                                Text("\(row.owned_cells ?? 0) cells")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(String(format: "%.2f%%", row.territory_share_pct ?? 0))
                                .font(.headline)
                                .monospacedDigit()
                        }
                    }
                    .listRowBackground(row.user_id == AppState.shared.userId ? Color.white.opacity(0.12) : Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                }
                .listStyle(.plain)
                .listRowSeparator(.hidden)
                .scrollContentBackground(.hidden)
                .scrollIndicators(.never)
            } else if vm.metric == .territoryCells {
                List(vm.territoryShareRows) { row in
                    Section {
                        HStack(spacing: 12) {
                            Text("\(row.rank).")
                                .font(.headline)
                                .frame(width: 30, alignment: .trailing)
                            AvatarView(urlString: row.avatar_url)
                                .frame(width: 36, height: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                NavigationLink {
                                    ProfileView(userId: row.user_id).gradientBG()
                                } label: {
                                    Text(row.username ?? "user")
                                        .font(.subheadline.weight(.semibold))
                                        .lineLimit(1)
                                }
                                .buttonStyle(.plain)
                                Text(String(format: "%.2f%% global share", row.territory_share_pct ?? 0))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(row.owned_cells ?? 0)")
                                .font(.headline)
                                .monospacedDigit()
                        }
                    }
                    .listRowBackground(row.user_id == AppState.shared.userId ? Color.white.opacity(0.12) : Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                }
                .listStyle(.plain)
                .listRowSeparator(.hidden)
                .scrollContentBackground(.hidden)
                .scrollIndicators(.never)
            } else if vm.metric == .segmentPopularity {
                List(vm.segmentPopularityRows) { row in
                    Section {
                        HStack(spacing: 12) {
                            Text("\(row.rank).")
                                .font(.headline)
                                .frame(width: 30, alignment: .trailing)
                            VStack(alignment: .leading, spacing: 2) {
                                NavigationLink {
                                    SegmentDetailView(segmentId: row.segment_id, onClose: nil)
                                } label: {
                                    Text(row.name)
                                        .font(.subheadline.weight(.semibold))
                                        .lineLimit(2)
                                }
                                .buttonStyle(.plain)
                                Text("Matched efforts in period")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(row.efforts_count)")
                                .font(.headline)
                                .monospacedDigit()
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                }
                .listStyle(.plain)
                .listRowSeparator(.hidden)
                .scrollContentBackground(.hidden)
                .scrollIndicators(.never)
            }
        }
        .overlay {
            if vm.loading {
                ProgressView("Loading…")
                    .padding()
            } else if let e = vm.error {
                Text(e)
                    .foregroundStyle(.red)
                    .padding(.vertical, 24)
            } else if rankingListIsEmpty(vm)
            {
                VStack(spacing: 8) {
                    Image(systemName: "person.3.sequence")
                        .font(.largeTitle)
                        .opacity(0.6)
                    Text("No results")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 24)
            }
        }
    }
    
    private func dateFormatted(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: d)
    }
    
    private func scoreString(_ d: Decimal) -> String {
        let n = NSDecimalNumber(decimal: d).doubleValue
        return String(format: "%.0f", n)
    }
    
    private func kcalString(_ d: Decimal) -> String {
        let n = NSDecimalNumber(decimal: d).doubleValue
        return "\(Int(n.rounded())) kcal"
    }
    
    private func volumeString(_ d: Decimal) -> String {
        let n = NSDecimalNumber(decimal: d).doubleValue
        if n >= 1000 {
            return String(format: "%.1fk kg", n / 1000.0)
        }
        return String(format: "%.0f kg", n)
    }
    
    private func distanceString(_ d: Decimal) -> String {
        let n = NSDecimalNumber(decimal: d).doubleValue
        if n >= 100 {
            return String(format: "%.0f km", n)
        }
        return String(format: "%.1f km", n)
    }
    
    private func elevationString(_ m: Int64) -> String {
        let n = Int(m)
        if n >= 1000 {
            return String(format: "%.1fk m", Double(n) / 1000.0)
        }
        return "\(n) m"
    }
    
    private func durationStringFromSeconds(_ sec: Int64) -> String {
        let s = Int(sec)
        if s < 3600 {
            let m = s / 60
            return "\(m)m"
        }
        let h = s / 3600
        let m = (s % 3600) / 60
        return "\(h)h \(m)m"
    }
    
    private func pacePerKmString(_ secPerKm: Int) -> String {
        let s = max(0, secPerKm)
        let m = s / 60
        let r = s % 60
        return String(format: "%d:%02d /km", m, r)
    }
    
    private func maxWeightString(_ kg: Decimal) -> String {
        let n = NSDecimalNumber(decimal: kg).doubleValue
        if n >= 1000 {
            return String(format: "%.1f t", n / 1000.0)
        }
        return String(format: "%.1f kg", n)
    }
    
    private func winRateString(_ rate: Decimal) -> String {
        let n = NSDecimalNumber(decimal: rate).doubleValue * 100.0
        return String(format: "%.0f%%", n)
    }
    
    private func rankingListIsEmpty(_ vm: RankingVM) -> Bool {
        switch vm.metric {
        case .score: return vm.rows.isEmpty
        case .calories: return vm.kcalRows.isEmpty
        case .level: return vm.levelRows.isEmpty
        case .bestWorkout: return vm.workoutRows.isEmpty
        case .goals: return vm.goalsRows.isEmpty
        case .duels: return vm.duelsRows.isEmpty
        case .strengthVolume: return vm.strengthVolumeRows.isEmpty
        case .cardioDistance: return vm.cardioDistanceRows.isEmpty
        case .sportWins: return vm.sportWinsRows.isEmpty
        case .cardioElevation: return vm.cardioElevationRows.isEmpty
        case .cardioDuration: return vm.cardioDurationRows.isEmpty
        case .cardioBestPace: return vm.cardioBestPaceRows.isEmpty
        case .strengthReps: return vm.strengthRepsRows.isEmpty
        case .strengthSets: return vm.strengthSetsRows.isEmpty
        case .strengthMaxSetWeight: return vm.strengthMaxWeightRows.isEmpty
        case .sportDuration: return vm.sportDurationRows.isEmpty
        case .sportWinRate: return vm.sportWinRateRows.isEmpty
        case .likesReceived: return vm.likesReceivedRows.isEmpty
        case .commentsReceived: return vm.commentsReceivedRows.isEmpty
        case .groupSessions: return vm.groupSessionsRows.isEmpty
        case .achievements: return vm.achievementsRows.isEmpty
        case .challengePodiums: return vm.challengePodiumsRows.isEmpty
        case .hyroxBestTime: return vm.hyroxBestTimeRows.isEmpty
        case .footballGoals: return vm.footballGoalsRows.isEmpty
        case .skiDistanceKpi: return vm.skiDistanceKpiRows.isEmpty
        case .segmentPopularity: return vm.segmentPopularityRows.isEmpty
        case .territoryShare, .territoryCells: return vm.territoryShareRows.isEmpty
        }
    }
    
    private func periodLabel(_ p: LBPeriod) -> String {
        switch p {
        case .day:   return "today"
        case .week:  return "this week"
        case .month: return "this month"
        case .all:   return "all-time"
        }
    }
}
