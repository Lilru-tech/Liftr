import SwiftUI
import Supabase

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

enum LBMetric: String, CaseIterable, Identifiable {
    case score = "Score"
    case calories = "Calories"
    case level = "Level"
    case bestWorkout = "Top workouts"
    var id: String { rawValue }
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

@MainActor
final class RankingVM: ObservableObject {
    @Published var rows: [LeaderRow] = []
    @Published var levelRows: [LevelRankRow] = []
    @Published var workoutRows: [WorkoutLeaderRow] = []
    @Published var kcalRows: [CaloriesLeaderRow] = []
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
                self.workoutRows = []
            }
        } catch {
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
            }
        } catch {
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
            }
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
                self.kcalRows = []
            }
        }
    }
    
    private func fetch() async {
        loading = true; error = nil
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
        } catch {
            self.error = error.localizedDescription
            self.rows = []
            self.kcalRows = []
        }
    }
}

struct RankingView: View {
    @StateObject private var vm = RankingVM()
    @AppStorage("isPremium") private var isPremium: Bool = false

    var body: some View {
        GradientBackground {
            VStack(spacing: 12) {
                headerBars
                listContent
                if !isPremium {
                    BannerAdView(adUnitID: "ca-app-pub-7676731162362384/7781347704")
                        .frame(height: 50)
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                }
            }
            .padding(.horizontal, 12)
        }
        .onAppear { vm.load() }
        .onChange(of: vm.scope)  { _, _ in vm.load() }
        .onChange(of: vm.period) { _, _ in vm.load() }
        .onChange(of: vm.kind)   { _, _ in vm.load() }
        .onChange(of: vm.sexOpt) { _, _ in vm.load() }
        .onChange(of: vm.age)    { _, _ in vm.load() }
        .onChange(of: vm.metric) { _, _ in vm.load() }
    }
    
    private var headerBars: some View {
        VStack(spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    Picker("Scope", selection: $vm.scope) {
                        ForEach(LBScope.allCases) {
                            Text($0.rawValue).lineLimit(1).minimumScaleFactor(0.85).tag($0)
                        }
                    }
                    .pickerStyle(.segmented)
                    
                    if vm.metric != .level {
                        Picker("Period", selection: $vm.period) {
                            ForEach(LBPeriod.allCases) {
                                Text($0.rawValue).lineLimit(1).minimumScaleFactor(0.85).tag($0)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }
                VStack(spacing: 8) {
                    Picker("Scope", selection: $vm.scope) {
                        ForEach(LBScope.allCases) {
                            Text($0.rawValue).lineLimit(1).minimumScaleFactor(0.85).tag($0)
                        }
                    }
                    .pickerStyle(.segmented)
                    
                    if vm.metric != .level {
                        Picker("Period", selection: $vm.period) {
                            ForEach(LBPeriod.allCases) {
                                Text($0.rawValue).lineLimit(1).minimumScaleFactor(0.85).tag($0)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }
            }
            
            HStack {
                Picker("Metric", selection: $vm.metric) {
                    ForEach(LBMetric.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            
            HStack(spacing: 10) {
                if vm.metric != .level {
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
            .font(.subheadline)
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

            } else {
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
                                    ProfileView(userId: row.user_id).gradientBG()
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
            } else if
                (vm.metric == .score && vm.rows.isEmpty) ||
                (vm.metric == .calories && vm.kcalRows.isEmpty) ||
                (vm.metric == .level && vm.levelRows.isEmpty) ||
                (vm.metric == .bestWorkout && vm.workoutRows.isEmpty)
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
    
    private func periodLabel(_ p: LBPeriod) -> String {
        switch p {
        case .day:   return "today"
        case .week:  return "this week"
        case .month: return "this month"
        case .all:   return "all-time"
        }
    }
}
