import SwiftUI
import Supabase
import Charts
import UIKit

extension Notification.Name {
    static let workoutDidChange = Notification.Name("workoutDidChange")
}

private struct ShareItem: Identifiable {
    let id = UUID()
    let image: UIImage
}

struct HomeView: View {
    @EnvironmentObject var app: AppState
    @AppStorage("isPremium") private var isPremium = false
    
    enum KindFilter: String, CaseIterable { case all = "All", strength = "Strength", cardio = "Cardio", sport = "Sport" }
    @State private var filter: KindFilter = .all
    
    struct WorkoutRow: Decodable, Identifiable {
        let id: Int
        let user_id: UUID
        let kind: String
        let title: String?
        let state: String
        let started_at: Date?
        let ended_at: Date?
        let calories_kcal: Decimal?
        let sport_sessions: [SportSessionRow]?
        let cardio_sessions: [CardioSessionRow]?
        
        struct SportSessionRow: Decodable {
            let sport: String
        }
        
        struct CardioSessionRow: Decodable {
            let activity_code: String?
        }
        
        var sport: String? { sport_sessions?.first?.sport }
        var cardioActivity: String? { cardio_sessions?.first?.activity_code }
    }
    
    private struct FollowRow: Decodable { let followee_id: UUID }
    struct ProfileRow: Decodable { let user_id: UUID; let username: String; let avatar_url: String? }
    private struct WorkoutScoreRow: Decodable { let workout_id: Int; let score: Decimal }
    private struct LikeRow: Decodable { let workout_id: Int; let user_id: UUID }
    private struct ParticipantRow: Decodable { let workout_id: Int; let user_id: UUID }
    
    struct PRRow: Decodable, Identifiable {
        let kind: String
        let user_id: UUID
        let label: String
        let metric: String
        let value: Double
        let achieved_at: Date
        var id: String { "\(user_id.uuidString)|\(label)|\(metric)|\(achieved_at.timeIntervalSince1970)" }
    }
    
    struct MonthPoint: Identifiable {
        let id = UUID()
        let date: Date
        let label: String
        let value: Double
    }
    
    struct MonthSummary {
        let year: Int
        let month: Int
        let workouts: Int
        let totalScore: Int
        let deltaPercent: Double
        let series: [MonthPoint]
    }
    
    struct FeedItem: Identifiable, Hashable, Equatable {
        let id: Int
        let workout: WorkoutRow
        let username: String
        let avatarURL: String?
        let score: Double?
        let caloriesKcal: Double?
        let likeCount: Int
        let isLiked: Bool
        let participantIds: [UUID]
        let coUserAvatarURLs: [String]
        
        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
            hasher.combine(workout.kind)
            hasher.combine(workout.title ?? "")
            hasher.combine(workout.started_at?.timeIntervalSince1970 ?? 0)
            hasher.combine(workout.ended_at?.timeIntervalSince1970 ?? 0)
            hasher.combine(workout.state)
            hasher.combine(username)
            hasher.combine(avatarURL ?? "")
            hasher.combine(score ?? -1)
            hasher.combine(caloriesKcal ?? -1)
            hasher.combine(likeCount)
            hasher.combine(isLiked)
            hasher.combine(participantIds.count)
            hasher.combine(coUserAvatarURLs.joined(separator: ","))
        }
        
        static func == (lhs: FeedItem, rhs: FeedItem) -> Bool {
            lhs.id == rhs.id &&
            lhs.workout.kind == rhs.workout.kind &&
            (lhs.workout.title ?? "") == (rhs.workout.title ?? "") &&
            (lhs.workout.started_at?.timeIntervalSince1970 ?? 0) == (rhs.workout.started_at?.timeIntervalSince1970 ?? 0) &&
            (lhs.workout.ended_at?.timeIntervalSince1970 ?? 0) == (rhs.workout.ended_at?.timeIntervalSince1970 ?? 0) &&
            lhs.workout.state == rhs.workout.state &&
            lhs.username == rhs.username &&
            (lhs.avatarURL ?? "") == (rhs.avatarURL ?? "") &&
            (lhs.score ?? -1) == (rhs.score ?? -1) &&
            (lhs.caloriesKcal ?? -1) == (rhs.caloriesKcal ?? -1) &&
            lhs.likeCount == rhs.likeCount &&
            lhs.isLiked == rhs.isLiked &&
            lhs.participantIds.count == rhs.participantIds.count &&
            lhs.coUserAvatarURLs.prefix(3) == rhs.coUserAvatarURLs.prefix(3)
        }
    }
    
    @State private var feed: [FeedItem] = []
    @State private var profiles: [UUID: ProfileRow] = [:]
    @State private var followees: [UUID] = []
    @State private var page = 0
    private let pageSize = 30
    @State private var canLoadMore = true
    @State private var isLoadingPage = false
    @State private var selectedItem: FeedItem?
    @State private var _selToken = UUID()
    @State private var initialLoading = false
    @State private var error: String?
    @State private var todayCount = 0
    @State private var todayMinutes = 0
    @State private var todayPoints = 0
    @State private var todayKcal = 0
    @State private var streakDays = 0
    @State private var weekWorkouts = 0
    @State private var weekPoints = 0
    @State private var weekKcal = 0
    @State private var recentPRs: [PRRow] = []
    @State private var weeklyTop: [(user: ProfileRow, points: Int)] = []
    @State private var monthSummary: MonthSummary?
    @State private var strongestWeekPtsMTD = 0
    @State private var strongestWeekKcalMTD = 0
    @State private var bestSportScore = 0
    @State private var showGoals = false
    @State private var showCompetitions = false
    @State private var bestSportLabel = ""
    @State private var shareItem: ShareItem?
    @AppStorage("homeCollapseData") private var collapseData = false
    @AppStorage("homeCollapseModules") private var collapseModules = false
    @AppStorage("homeCollapseToday") private var collapseToday = false
    @AppStorage("homeCollapseStreak") private var collapseStreak = false
    @AppStorage("homeCollapseInsights") private var collapseInsights = false
    @AppStorage("homeCollapseGoals") private var collapseGoals = false
    @AppStorage("homeCollapseMonthly") private var collapseMonthly = false
    
    private let highlightsInsertIndex = 5
    
    private func metricChip(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.18)))
    }
    
    private var hasAnyModule: Bool {
        todayCount > 0
        || weekWorkouts > 0
        || (strongestWeekPtsMTD > 0 || bestSportScore > 0)
    }
    
    private var collapsedModulesPill: some View {
        Button {
            withAnimation(.easeInOut) { setAllCollapsed(false) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "chart.bar.fill")
                    .foregroundStyle(.secondary)

                Text("Data")
                    .font(.subheadline.weight(.semibold))

                Spacer()
                
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.18)))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var expandedModulesPanel: some View {
        if hasAnyModule {
            VStack(spacing: 10) {

                if todayCount > 0 {
                    TodaySummaryCard(
                        count: todayCount,
                        minutes: todayMinutes,
                        points: todayPoints,
                        kcal: todayKcal
                    )
                }

                if weekWorkouts > 0 {
                    StreakWeekCard(
                        streak: streakDays,
                        weekWorkouts: weekWorkouts,
                        weekPoints: weekPoints,
                        weekKcal: weekKcal
                    )
                }

                if strongestWeekPtsMTD > 0 || bestSportScore > 0 {
                    InsightsRow(
                        strongestWeekPts: strongestWeekPtsMTD,
                        strongestWeekKcal: strongestWeekKcalMTD,
                        bestSportScore: bestSportScore,
                        bestSportLabel: bestSportLabel
                    )
                }
            }
            .padding(.trailing, 44)
            .overlay(alignment: .topTrailing) {
                Button {
                    withAnimation(.easeInOut) { setAllCollapsed(true) }
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(6)
            }
        } else {
            EmptyView()
        }
    }
    
    private func setAllCollapsed(_ collapsed: Bool) {
        collapseModules  = collapsed
        collapseData     = collapsed
        collapseToday    = collapsed
        collapseStreak   = collapsed
        collapseInsights = collapsed
        collapseGoals    = collapsed
        collapseMonthly  = collapsed
    }
    
    var body: some View {
        VStack(spacing: 8) {
            VStack(spacing: 8) {
                Picker("", selection: $filter) {
                    ForEach(KindFilter.allCases, id: \.self) { k in Text(k.rawValue).tag(k) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                
                VStack(spacing: 6) {
                    if hasAnyModule {
                        CollapsibleCard(
                            isCollapsed: collapseModules,
                            onToggle: {
                                withAnimation(.easeInOut) {
                                    setAllCollapsed(!collapseModules)
                                }
                            },
                            collapsed: { collapsedModulesPill },
                            expanded: { expandedModulesPanel }
                        )
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 2)
                
                List {
                    if initialLoading && feed.isEmpty {
                        ProgressView().frame(maxWidth: .infinity)
                    }
                    
                    if !collapseModules {
                    if let summary = monthSummary, summary.workouts > 0 {
                        if collapseMonthly {
                            Button {
                                withAnimation(.easeInOut) { collapseMonthly = false }
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "calendar")
                                        .foregroundStyle(.secondary)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("\(DateFormatter().monthSymbols[(max(1, summary.month)-1) % 12]) \(summary.year) summary")
                                            .font(.subheadline.weight(.semibold))
                                        Text("\(summary.totalScore) pts")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(14)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.18)))
                            }
                            .buttonStyle(.plain)
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            .listRowBackground(Color.clear)
                        } else {
                            MonthlySummaryCard(
                                summary: summary,
                                onShare: { image in
                                    self.shareItem = ShareItem(image: image)
                                }
                            )
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            .listRowBackground(Color.clear)
                        }
                    }
                }
                    
                    HStack(spacing: 10) {

                        weeklyGoalsModule
                            .frame(maxWidth: .infinity, alignment: .leading)

                        competitionsModule
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowBackground(Color.clear)
                    
                    ForEach(feed.indices, id: \.self) { i in
                        let item = feed[i]
                        if i == 0 || !sameDay(feed[i-1].workout.started_at, item.workout.started_at) {
                            Text(dateLabel(item.workout.started_at))
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 16).padding(.top, 6)
                                .listRowBackground(Color.clear)
                        }
                        
                        HomeFeedCard(item: item)
                            .contentShape(Rectangle())
                            .onTapGesture { selectedItem = item }
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            .listRowBackground(Color.clear)
                            .onAppear {
                                if i == feed.count - 1 {
                                    print("[Home.cell.onAppear] last cell reached → loadPage(reset:false)")
                                    Task { await loadPage(reset: false) }
                                }
                            }
                        
                        if i == highlightsInsertIndex && (!recentPRs.isEmpty || !weeklyTop.isEmpty) {
                            HighlightsCard(
                                prs: recentPRs,
                                weeklyTop: weeklyTop,
                                profileFor: { uid in profiles[uid] }
                            )
                            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 6, trailing: 16))
                            .listRowBackground(Color.clear)
                        }
                    }
                    
                    if !initialLoading && feed.isEmpty {
                        Text("Sin entrenos recientes").foregroundStyle(.secondary)
                    }
                    
                    if isLoadingPage && !feed.isEmpty {
                        HStack { Spacer(); ProgressView(); Spacer() }
                            .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .refreshable { await reloadAll() }
            }
            if !isPremium {
                BannerAdView(adUnitID: "ca-app-pub-7676731162362384/7781347704")
                    .frame(height: 50)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }
        }
        .onChange(of: selectedItem) { old, new in
            print("[Home.selectedItem] \(old?.id.description ?? "nil") → \(new?.id.description ?? "nil") main=\(Thread.isMainThread)")
        }
        .background(.clear)
        .task { await reloadAll() }
        .navigationDestination(item: $selectedItem) { it in
            WorkoutDetailView(workoutId: it.id, ownerId: it.workout.user_id)
                .onAppear {
                    print("[Home.navDest.onAppear] showing WorkoutDetailView id=\(it.id) main=\(Thread.isMainThread)")
                }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .workoutUpdated).receive(on: RunLoop.main)
        ) { note in
            let idAny = note.object
            print("[Home.onReceive workoutUpdated] recv note object=\(String(describing: idAny)) threadMain=\(Thread.isMainThread)")
            
            guard let id = idAny as? Int else {
                print("[Home.onReceive workoutUpdated] object nil o no Int → reloadAll()")
                Task { await reloadAll() }
                return
            }
            
            if let ui = note.userInfo {
                let keys = Array(ui.keys).map { "\($0)" }.joined(separator: ", ")
                print("[Home.onReceive workoutUpdated] id=\(id) userInfo.keys=[\(keys)]")
                print("[Home.onReceive workoutUpdated] ui.title=\(String(describing: ui["title"])) ui.kind=\(String(describing: ui["kind"])) ui.state=\(String(describing: ui["state"])) ui.started_at=\(String(describing: ui["started_at"])) ui.ended_at=\(String(describing: ui["ended_at"])) ui.score=\(String(describing: ui["score"]))")
            } else {
                print("[Home.onReceive workoutUpdated] id=\(id) userInfo=nil")
            }
            
            if let ui = note.userInfo,
               let kind = ui["kind"] as? String {
                
                let title     = ui["title"] as? String
                let startedAt = ui["started_at"] as? Date
                let endedAt   = ui["ended_at"] as? Date
                
                var newScore: Double? = nil
                if let raw = ui["score"], !(raw is NSNull) {
                    newScore = raw as? Double
                }
                
                if let idx = feed.firstIndex(where: { $0.id == id }) {
                    print("[Home.onReceive workoutUpdated] parcheando feed idx=\(idx) id=\(id)")
                    let old = feed[idx]
                    let patched = WorkoutRow(
                        id: old.workout.id,
                        user_id: old.workout.user_id,
                        kind: kind,
                        title: title,
                        state: (ui["state"] as? String) ?? old.workout.state,
                        started_at: startedAt ?? old.workout.started_at,
                        ended_at: endedAt ?? old.workout.ended_at,
                        calories_kcal: old.workout.calories_kcal,
                        sport_sessions: old.workout.sport_sessions,
                        cardio_sessions: old.workout.cardio_sessions
                    )
                    
                    Task { await MainActor.run {
                        feed[idx] = FeedItem(
                            id: old.id,
                            workout: patched,
                            username: old.username,
                            avatarURL: old.avatarURL,
                            score: newScore ?? old.score,
                            caloriesKcal: old.caloriesKcal,
                            likeCount: old.likeCount,
                            isLiked: old.isLiked,
                            participantIds: old.participantIds,
                            coUserAvatarURLs: old.coUserAvatarURLs
                        )
                        feed.sort { ($0.workout.started_at ?? .distantPast) > ($1.workout.started_at ?? .distantPast) }
                        print("[Home.onReceive workoutUpdated] patched OK (title=\(title ?? "nil"), score=\(String(describing: newScore)))")
                    }}
                    if ui["state"] == nil { Task { await refreshOne(id: id) } }
                    Task { await recalcHomeSummaries() }
                    if (ui["state"] as? String) != nil { return }
                } else {
                    print("[Home.onReceive workoutUpdated] id=\(id) no estaba en feed visible → refreshOne()")
                }
            } else {
                print("[Home.onReceive workoutUpdated] no hay ‘kind’ en userInfo → refreshOne()")
            }
            
            Task {
                print("[Home.onReceive workoutUpdated] calling refreshOne(\(id))…")
                await refreshOne(id: id)
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .workoutDidChange).receive(on: RunLoop.main)
        ) { note in
            let idAny = note.object
            print("[Home.onReceive workoutDidChange] recv object=\(String(describing: idAny)) threadMain=\(Thread.isMainThread)")
            if let id = idAny as? Int {
                Task {
                    print("[Home.onReceive workoutDidChange] refreshOne(\(id))…")
                    await refreshOne(id: id)
                }
            } else {
                print("[Home.onReceive workoutDidChange] reloadAll()…")
                Task { await reloadAll() }
            }
        }
        .onChange(of: filter) { _, _ in Task { await reloadAll() } }
        .sheet(item: $shareItem) { item in
            ShareSheet(items: [item.image])
        }
        .navigationDestination(isPresented: $showGoals) {
            GoalsView(userId: app.userId, viewedUsername: "You")
                .gradientBG()
        }
        .navigationDestination(isPresented: $showCompetitions) {
            CompetitionsHubView()
                .gradientBG()
        }
    }
    
    private func reloadAll() async {
        print("[Home.reloadAll] start filter=\(filter.rawValue)")
        if let session = try? await SupabaseManager.shared.client.auth.session {
            if app.userId != session.user.id {
                await MainActor.run { app.userId = session.user.id }
            }
        }
        
        guard let me = app.userId else { return }
        
        await MainActor.run {
            initialLoading = true
            error = nil
            page = 0
            canLoadMore = true
            isLoadingPage = false
            feed.removeAll()
        }
        
        do {
            let fRes = try await SupabaseManager.shared.client
                .from("follows")
                .select("followee_id")
                .eq("follower_id", value: me.uuidString)
                .limit(500)
                .execute()
            let fRows = try JSONDecoder.supabase().decode([FollowRow].self, from: fRes.data)
            let ids = fRows.map { $0.followee_id }
            await MainActor.run { self.followees = ids }
            await loadPage(reset: true)
            try await ensureProfilesAvailable(for: ([me] + ids))
            async let t: Void = loadTodaySummary()
            async let w: Void = loadWeekSummaryAndLeaderboard()
            async let s: Void = loadStreak()
            async let r: Void = loadRecentPRs()
            async let m: Void = loadMonthlySummary()
            async let i: Void = loadInsights()
            _ = await (t, w, s, r, m, i)
            
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
                self.feed = []
            }
        }
        
        await MainActor.run { initialLoading = false }
    }
    
    private func loadPage(reset: Bool) async {
        guard let me = app.userId else { return }
        
        if reset {
            await MainActor.run {
                page = 0
                canLoadMore = true
                feed.removeAll()
            }
        }
        
        guard canLoadMore, !isLoadingPage else { return }
        
        await MainActor.run {
            isLoadingPage = true
            print("[Home.loadPage] isLoadingPage=true reset=\(reset) page=\(page) canLoadMore=\(canLoadMore)")
        }
        
        defer {
            Task { await MainActor.run {
                isLoadingPage = false
                print("[Home.loadPage] isLoadingPage=false")
            }}
        }
        
        do {
            let allIds = [me] + followees
            print("[Home.loadPage] fetching page=\(page) pageSize=\(pageSize) userIds=\(allIds.count)")
            
            let idsCSV = allIds.map { $0.uuidString }.joined(separator: ",")
            var q: PostgrestFilterBuilder = SupabaseManager.shared.client
                .from("workouts")
                .select("id, user_id, kind, title, started_at, ended_at, state, calories_kcal, sport_sessions!sport_sessions_workout_id_fk(sport), cardio_sessions(activity_code)")
                .or("user_id.eq.\(me.uuidString),and(user_id.in.(\(idsCSV)),state.neq.planned)")
            
            if filter != .all {
                q = q.eq("kind", value: filter.rawValue.lowercased())
                print("[Home.loadPage] filter=\(filter.rawValue.lowercased())")
            }
            
            let from = page * pageSize
            let to   = from + pageSize - 1
            
            let wRes = try await q
                .order("started_at", ascending: false)
                .range(from: from, to: to)
                .execute()
            
            let workouts = try JSONDecoder.supabase().decode([WorkoutRow].self, from: wRes.data)
            print("[Home.loadPage] fetched workouts=\(workouts.count) from=\(from) to=\(to)")
            
            let ids = workouts.map { $0.id }
            let uniqueUserIds = Array(Set(workouts.map { $0.user_id }))
            try await ensureProfilesAvailable(for: uniqueUserIds)
            
            var scoresDict: [Int: Double] = [:]
            if !ids.isEmpty {
                let sRes = try await SupabaseManager.shared.client
                    .from("workout_scores")
                    .select("workout_id, score")
                    .in("workout_id", values: ids)
                    .execute()
                
                let sRows = try JSONDecoder.supabase().decode([WorkoutScoreRow].self, from: sRes.data)
                print("[Home.loadPage] fetched scores rows=\(sRows.count)")
                var tmp: [Int: Double] = [:]
                for row in sRows {
                    let value = NSDecimalNumber(decimal: row.score).doubleValue
                    tmp[row.workout_id, default: 0] += value
                }
                scoresDict = tmp
            }
            
            var likeCountByWorkout: [Int: Int] = [:]
            var likedByMe: Set<Int> = []
            if !ids.isEmpty {
                let lRes = try await SupabaseManager.shared.client
                    .from("workout_likes")
                    .select("workout_id,user_id")
                    .in("workout_id", values: ids)
                    .execute()
                let lRows = try JSONDecoder.supabase().decode([LikeRow].self, from: lRes.data)
                for row in lRows {
                    likeCountByWorkout[row.workout_id, default: 0] += 1
                    if row.user_id == me { likedByMe.insert(row.workout_id) }
                }
            }
            
            var participantIdsByWorkout: [Int: [UUID]] = [:]
            if !ids.isEmpty {
                let pRes = try await SupabaseManager.shared.client
                    .from("workout_participants")
                    .select("workout_id,user_id")
                    .in("workout_id", values: ids)
                    .execute()
                let pRows = try JSONDecoder.supabase().decode([ParticipantRow].self, from: pRes.data)
                for p in pRows {
                    participantIdsByWorkout[p.workout_id, default: []].append(p.user_id)
                }
                let allParticipantUids = Array(Set(pRows.map { $0.user_id }))
                try await ensureProfilesAvailable(for: allParticipantUids)
            }
            
            let items: [FeedItem] = workouts.map { w in
                let ownerProf = profiles[w.user_id]
                let pIds = participantIdsByWorkout[w.id] ?? []
                
                return FeedItem(
                    id: w.id,
                    workout: w,
                    username: ownerProf?.username ?? (w.user_id == me ? "You" : "—"),
                    avatarURL: ownerProf?.avatar_url,
                    score: scoresDict[w.id],
                    caloriesKcal: w.calories_kcal.map { NSDecimalNumber(decimal: $0).doubleValue },
                    likeCount: likeCountByWorkout[w.id] ?? 0,
                    isLiked: likedByMe.contains(w.id),
                    participantIds: pIds,
                    coUserAvatarURLs: pIds
                        .filter { $0 != w.user_id }
                        .compactMap { profiles[$0]?.avatar_url }
                )
            }
            
            await MainActor.run {
                self.feed.append(contentsOf: items)
                self.feed.sort { ($0.workout.started_at ?? .distantPast) > ($1.workout.started_at ?? .distantPast) }
                self.canLoadMore = workouts.count == pageSize
                if canLoadMore { page += 1 }
                print("[Home.loadPage] appended items=\(items.count) newFeedCount=\(feed.count) canLoadMore=\(canLoadMore) nextPage=\(page)")
            }
        } catch {
            await MainActor.run {
                self.canLoadMore = false
                print("[Home.loadPage] error=\(error) → canLoadMore=false")
            }
        }
    }
    
    private func refreshOne(id: Int) async {
        guard let me = app.userId else { return }
        
        print("[Home.refreshOne] id=\(id) start")
        
        do {
            let wRes = try await SupabaseManager.shared.client
                .from("workouts")
                .select("id, user_id, kind, title, started_at, ended_at, state, calories_kcal, sport_sessions!sport_sessions_workout_id_fk(sport), cardio_sessions(activity_code)")
                .eq("id", value: id)
                .single()
                .execute()
            let w = try JSONDecoder.supabase().decode(WorkoutRow.self, from: wRes.data)
            print("[Home.refreshOne] got workout kind=\(w.kind) title=\(String(describing: w.title)) started_at=\(String(describing: w.started_at)) ended_at=\(String(describing: w.ended_at))")
            
            try await ensureProfilesAvailable(for: [w.user_id])
            let prof = profiles[w.user_id]
            print("[Home.refreshOne] profile username=\(String(describing: prof?.username)) avatar=\(String(describing: prof?.avatar_url))")
            
            let sRes = try await SupabaseManager.shared.client
                .from("workout_scores")
                .select("workout_id, score")
                .eq("workout_id", value: id)
                .execute()
            let sRows = try JSONDecoder.supabase().decode([WorkoutScoreRow].self, from: sRes.data)
            let scTotal = sRows.reduce(0.0) { $0 + NSDecimalNumber(decimal: $1.score).doubleValue }
            let score: Double? = sRows.isEmpty ? nil : scTotal
            print("[Home.refreshOne] scores rows=\(sRows.count) total=\(String(describing: score))")
            
            var likeCount = 0
            var isLiked = false
            do {
                let lRes = try await SupabaseManager.shared.client
                    .from("workout_likes")
                    .select("workout_id,user_id")
                    .eq("workout_id", value: id)
                    .limit(2000)
                    .execute()
                let lRows = try JSONDecoder.supabase().decode([LikeRow].self, from: lRes.data)
                likeCount = lRows.count
                if let me = app.userId { isLiked = lRows.contains(where: { $0.user_id == me }) }
            } catch { }
            var pIds: [UUID] = []
            do {
                let pRes = try await SupabaseManager.shared.client
                    .from("workout_participants")
                    .select("workout_id,user_id")
                    .eq("workout_id", value: id)
                    .limit(100)
                    .execute()
                let pRows = try JSONDecoder.supabase().decode([ParticipantRow].self, from: pRes.data)
                pIds = pRows.map { $0.user_id }
                try await ensureProfilesAvailable(for: pIds)
            } catch { }
            
            
            let updated = FeedItem(
                id: w.id,
                workout: w,
                username: prof?.username ?? (w.user_id == me ? "You" : "—"),
                avatarURL: prof?.avatar_url,
                score: score,
                caloriesKcal: w.calories_kcal.map { NSDecimalNumber(decimal: $0).doubleValue },
                likeCount: likeCount,
                isLiked: isLiked,
                participantIds: pIds,
                coUserAvatarURLs: pIds
                    .filter { $0 != w.user_id }
                    .compactMap { profiles[$0]?.avatar_url }
            )
            print("[Home.refreshOne] will update feed on main…")
            
            await MainActor.run {
                if let idx = feed.firstIndex(where: { $0.id == id }) {
                    print("[Home.refreshOne] replacing item at idx=\(idx)")
                    feed[idx] = updated
                    feed.sort { ($0.workout.started_at ?? .distantPast) > ($1.workout.started_at ?? .distantPast) }
                } else {
                    print("[Home.refreshOne] item id=\(id) no estaba en feed (no inserto)")
                }
            }
            await recalcHomeSummaries()
            print("[Home.refreshOne] done id=\(id)")
        } catch {
            print("[Home.refreshOne] error=\(error) → fallback reloadAll()")
            await reloadAll()
        }
    }
    
    private func ensureProfilesAvailable(for userIds: [UUID]) async throws {
        let missing = userIds.filter { profiles[$0] == nil }
        if !missing.isEmpty {
            print("[Home.ensureProfiles] missing=\(missing.count) (will fetch)")
        } else {
            print("[Home.ensureProfiles] all profiles cached (\(userIds.count))")
        }
        
        guard !missing.isEmpty else { return }
        let pRes = try await SupabaseManager.shared.client
            .from("profiles")
            .select("user_id, username, avatar_url")
            .in("user_id", values: missing.map { $0.uuidString })
            .execute()
        
        let pRows = try JSONDecoder.supabase().decode([ProfileRow].self, from: pRes.data)
        print("[Home.ensureProfiles] fetched=\(pRows.count)")
        
        await MainActor.run {
            for p in pRows { profiles[p.user_id] = p }
        }
    }
    
    
    private func loadTodaySummary() async {
        guard let me = app.userId else { return }
        do {
            var cal = Calendar.current; cal.timeZone = .current
            let start = cal.startOfDay(for: .now)
            let end = cal.date(byAdding: .day, value: 1, to: start)!
            
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            iso.timeZone = .current
            
            let wRes = try await SupabaseManager.shared.client
                .from("workouts")
                .select("id, user_id, kind, title, started_at, ended_at, state, calories_kcal")
                .eq("user_id", value: me.uuidString)
                .gte("started_at", value: iso.string(from: start))
                .lt("started_at", value: iso.string(from: end))
                .order("started_at", ascending: false)
                .execute()
            
            let rows = try JSONDecoder.supabase().decode([WorkoutRow].self, from: wRes.data)
            
            var scoresDict: [Int: Double] = [:]
            let ids = rows.map { $0.id }
            if !ids.isEmpty {
                let sRes = try await SupabaseManager.shared.client
                    .from("workout_scores")
                    .select("workout_id, score")
                    .in("workout_id", values: ids)
                    .execute()
                
                let sRows = try JSONDecoder.supabase().decode([WorkoutScoreRow].self, from: sRes.data)
                
                var tmp: [Int: Double] = [:]
                for row in sRows {
                    let value = NSDecimalNumber(decimal: row.score).doubleValue
                    tmp[row.workout_id, default: 0] += value
                }
                scoresDict = tmp
            }
            
            var minutes = 0
            var points = 0
            var kcalTotal = 0
            for w in rows {
                if let s = w.started_at, let e = w.ended_at {
                    minutes += max(Int(e.timeIntervalSince(s))/60, 0)
                }
                if let sc = scoresDict[w.id] { points += Int(sc.rounded()) }

                if let kcal = w.calories_kcal {
                    kcalTotal += Int(NSDecimalNumber(decimal: kcal).doubleValue.rounded())
                }
            }
            
            await MainActor.run {
                self.todayCount = rows.count
                self.todayMinutes = minutes
                self.todayPoints = points
                self.todayKcal = kcalTotal
            }
        } catch { }
    }
    
    private func recalcHomeSummaries() async {
        async let t: Void = loadTodaySummary()
        async let w: Void = loadWeekSummaryAndLeaderboard()
        async let s: Void = loadStreak()
        async let r: Void = loadRecentPRs()
        async let m: Void = loadMonthlySummary()
        async let i: Void = loadInsights()
        _ = await (t, w, s, r, m, i)
    }
    
    private func loadWeekSummaryAndLeaderboard() async {
        guard let me = app.userId else { return }
        do {
            let (weekStart, now) = weekRange()
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            iso.timeZone = .current
            
            let allIds = [me] + followees
            let allRes = try await SupabaseManager.shared.client
                .from("workouts")
                .select("id, user_id, started_at, ended_at, kind, title, state, calories_kcal")
                .in("user_id", values: allIds.map { $0.uuidString })
                .gte("started_at", value: iso.string(from: weekStart))
                .lt("started_at", value: iso.string(from: now))
                .order("started_at", ascending: false)
                .execute()
            let rowsAll = try JSONDecoder.supabase().decode([WorkoutRow].self, from: allRes.data)
            
            let meRes = try await SupabaseManager.shared.client
                .from("workouts")
                .select("id, user_id, started_at, ended_at, kind, title, state, calories_kcal")
                .eq("user_id", value: me.uuidString)
                .gte("started_at", value: iso.string(from: weekStart))
                .lt("started_at", value: iso.string(from: now))
                .order("started_at", ascending: false)
                .execute()
            let rowsMe = try JSONDecoder.supabase().decode([WorkoutRow].self, from: meRes.data)
            
            let allIdsForScores = Array(Set(rowsAll.map { $0.id } + rowsMe.map { $0.id }))
            var scoresDict: [Int: Double] = [:]
            if !allIdsForScores.isEmpty {
                let sRes = try await SupabaseManager.shared.client
                    .from("workout_scores")
                    .select("workout_id, score")
                    .in("workout_id", values: allIdsForScores)
                    .execute()
                
                let sRows = try JSONDecoder.supabase().decode([WorkoutScoreRow].self, from: sRes.data)
                
                var tmp: [Int: Double] = [:]
                for row in sRows {
                    let value = NSDecimalNumber(decimal: row.score).doubleValue
                    tmp[row.workout_id, default: 0] += value
                }
                scoresDict = tmp
            }
            
            var myWeekPts = 0
            var myWeekKcal = 0

            for w in rowsMe {
                myWeekPts += Int((scoresDict[w.id] ?? 0).rounded())
                if let kcal = w.calories_kcal {
                    myWeekKcal += Int(NSDecimalNumber(decimal: kcal).doubleValue.rounded())
                }
            }
            
            var ptsByUser: [UUID: Int] = [:]
            for w in rowsAll { ptsByUser[w.user_id, default: 0] += Int((scoresDict[w.id] ?? 0).rounded()) }
            
            let sortedTop = ptsByUser.sorted { $0.value > $1.value }.prefix(3)
            var top: [(user: ProfileRow, points: Int)] = []
            for (uid, pts) in sortedTop {
                try await ensureProfilesAvailable(for: [uid])
                if let prof = profiles[uid] { top.append((prof, pts)) }
            }
            
            await MainActor.run {
                self.weekWorkouts = rowsMe.count
                self.weekPoints   = myWeekPts
                self.weekKcal     = myWeekKcal
                self.weeklyTop    = top
            }
        } catch { }
    }
    
    private func loadStreak() async {
        guard let me = app.userId else { return }
        do {
            let now = Date()
            let start = Calendar.current.date(byAdding: .day, value: -60, to: now)!
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            iso.timeZone = .current
            
            let res = try await SupabaseManager.shared.client
                .from("workouts")
                .select("started_at")
                .eq("user_id", value: me.uuidString)
                .gte("started_at", value: iso.string(from: start))
                .lt("started_at", value: iso.string(from: now))
                .execute()
            
            struct OnlyDate: Decodable { let started_at: Date? }
            let rows = try JSONDecoder.supabase().decode([OnlyDate].self, from: res.data)
            let dates = rows.compactMap { $0.started_at }
            let streak = computeStreak(from: dates)
            await MainActor.run { self.streakDays = streak }
        } catch {
        }
    }
    
    private func loadRecentPRs() async {
        guard let me = app.userId else { return }
        do {
            let allIds = [me] + followees
            let since = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            iso.timeZone = .current
            let prRes = try await SupabaseManager.shared.client
                .from("vw_user_prs")
                .select("*")
                .in("user_id", values: allIds.map { $0.uuidString })
                .gte("achieved_at", value: iso.string(from: since))
                .order("achieved_at", ascending: false)
                .limit(10)
                .execute()
            let prs = try JSONDecoder.supabase().decode([PRRow].self, from: prRes.data)
            let owners = Array(Set(prs.map { $0.user_id }))
            try await ensureProfilesAvailable(for: owners)
            
            await MainActor.run { self.recentPRs = prs }
        } catch {
        }
    }
    
    private func loadMonthlySummary() async {
        guard let me = app.userId else { return }
        
        var cal = Calendar.current
        cal.timeZone = .current
        
        let now = Date()
        guard let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: now)) else { return }
        let monthEnd = now
        
        guard let prevStart = cal.date(byAdding: .month, value: -1, to: monthStart) else { return }
        let prevEnd = monthStart
        
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        iso.timeZone = .current
        
        struct W: Decodable {
            let id: Int
            let started_at: Date?
            let calories_kcal: Decimal?
        }
        
        do {
            let wRes = try await SupabaseManager.shared.client
                .from("workouts")
                .select("id,started_at,calories_kcal")
                .eq("user_id", value: me.uuidString)
                .gte("started_at", value: iso.string(from: monthStart))
                .lt("started_at", value: iso.string(from: monthEnd))
                .execute()
            let rows = try JSONDecoder.supabase().decode([W].self, from: wRes.data)
            let ids = rows.map { $0.id }
            
            var scoreByWorkout: [Int: Double] = [:]
            if !ids.isEmpty {
                let sRes = try await SupabaseManager.shared.client
                    .from("workout_scores")
                    .select("workout_id,score")
                    .in("workout_id", values: ids)
                    .execute()
                struct S: Decodable { let workout_id: Int; let score: Decimal }
                let sRows = try JSONDecoder.supabase().decode([S].self, from: sRes.data)
                for s in sRows {
                    scoreByWorkout[s.workout_id, default: 0] += NSDecimalNumber(decimal: s.score).doubleValue
                }
            }
            var seriesMap: [Date: Double] = [:]
            var cursor = monthStart
            while cursor < monthEnd {
                let key = cal.startOfDay(for: cursor)
                seriesMap[key] = 0
                cursor = cal.date(byAdding: .day, value: 1, to: cursor)!
            }
            
            for w in rows {
                guard let d = w.started_at else { continue }
                let key = cal.startOfDay(for: d)
                seriesMap[key, default: 0] += (scoreByWorkout[w.id] ?? 0)
            }
            
            let orderedDays = seriesMap.keys.sorted()
            let points: [MonthPoint] = orderedDays.map { d in
                let dayNum = cal.component(.day, from: d)
                return MonthPoint(date: d, label: "\(dayNum)", value: seriesMap[d] ?? 0)
            }
            
            let totalScore = Int(points.reduce(0) { $0 + $1.value }.rounded())
            let workoutsCount = rows.count
            let pwRes = try await SupabaseManager.shared.client
                .from("workouts")
                .select("id")
                .eq("user_id", value: me.uuidString)
                .gte("started_at", value: iso.string(from: prevStart))
                .lt("started_at", value: iso.string(from: prevEnd))
                .execute()
            struct WID: Decodable { let id: Int }
            let prowIds = try JSONDecoder.supabase().decode([WID].self, from: pwRes.data).map { $0.id }
            
            var prevTotalScore = 0.0
            if !prowIds.isEmpty {
                let psRes = try await SupabaseManager.shared.client
                    .from("workout_scores")
                    .select("workout_id,score")
                    .in("workout_id", values: prowIds)
                    .execute()
                struct PS: Decodable { let workout_id: Int; let score: Decimal }
                let psRows = try JSONDecoder.supabase().decode([PS].self, from: psRes.data)
                for s in psRows { prevTotalScore += NSDecimalNumber(decimal: s.score).doubleValue }
            }
            
            let delta: Double
            if prevTotalScore <= 0 {
                delta = totalScore > 0 ? 100.0 : 0.0
            } else {
                delta = ((Double(totalScore) - prevTotalScore) / prevTotalScore) * 100.0
            }
            
            let comp = cal.dateComponents([.year, .month], from: monthStart)
            let summary = MonthSummary(
                year: comp.year ?? 0,
                month: comp.month ?? 0,
                workouts: workoutsCount,
                totalScore: totalScore,
                deltaPercent: delta,
                series: points
            )
            
            await MainActor.run { self.monthSummary = summary }
        } catch {
        }
    }
    
    private func loadInsights() async {
        async let a: Void = loadStrongestWeekMTD()
        async let b: Void = loadBestSportMatch()
        _ = await (a, b)
    }
    
    private func loadStrongestWeekMTD() async {
        guard let me = app.userId else { return }
        var cal = Calendar.current; cal.timeZone = .current
        let now = Date()
        guard let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: now)) else { return }
        let monthEnd = now
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        iso.timeZone = .current
        
        struct W: Decodable {
            let id: Int
            let started_at: Date?
            let calories_kcal: Decimal?
        }
        
        do {
            let wRes = try await SupabaseManager.shared.client
                .from("workouts")
                .select("id,started_at,calories_kcal")
                .eq("user_id", value: me.uuidString)
                .gte("started_at", value: iso.string(from: monthStart))
                .lt("started_at", value: iso.string(from: monthEnd))
                .order("started_at", ascending: false)
                .execute()
            let rows = try JSONDecoder.supabase().decode([W].self, from: wRes.data)
            let ids = rows.map { $0.id }
            
            var scoreByWorkout: [Int: Double] = [:]
            if !ids.isEmpty {
                let sRes = try await SupabaseManager.shared.client
                    .from("workout_scores")
                    .select("workout_id,score")
                    .in("workout_id", values: ids)
                    .execute()
                struct S: Decodable { let workout_id: Int; let score: Decimal }
                let sRows = try JSONDecoder.supabase().decode([S].self, from: sRes.data)
                for s in sRows {
                    scoreByWorkout[s.workout_id, default: 0] += NSDecimalNumber(decimal: s.score).doubleValue
                }
            }
            
            var byWeekPts: [String: Double] = [:]
            var byWeekKcal: [String: Double] = [:]

            for w in rows {
                guard let d = w.started_at else { continue }
                let comp = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: d)
                let key = "\(comp.yearForWeekOfYear ?? 0)-W\(comp.weekOfYear ?? 0)"

                byWeekPts[key, default: 0] += (scoreByWorkout[w.id] ?? 0)

                if let kcal = w.calories_kcal {
                    byWeekKcal[key, default: 0] += NSDecimalNumber(decimal: kcal).doubleValue
                }
            }

            let bestPts  = Int(byWeekPts.values.max()?.rounded() ?? 0)
            let bestKcal = Int(byWeekKcal.values.max()?.rounded() ?? 0)

            await MainActor.run {
                self.strongestWeekPtsMTD = bestPts
                self.strongestWeekKcalMTD = bestKcal
            }
        } catch { }
    }
    
    private func loadBestSportMatch() async {
        guard let me = app.userId else { return }
        let wRes = try? await SupabaseManager.shared.client
            .from("workouts")
            .select("id")
            .eq("user_id", value: me.uuidString)
            .eq("kind", value: "sport")
            .order("started_at", ascending: false)
            .limit(800)
            .execute()
        struct WID: Decodable { let id: Int }
        let wIds = (try? JSONDecoder.supabase().decode([WID].self, from: wRes?.data ?? Data()))?.map { $0.id } ?? []
        
        guard !wIds.isEmpty else {
            await MainActor.run {
                self.bestSportScore = 0
                self.bestSportLabel = ""
            }
            return
        }
        
        let sRes = try? await SupabaseManager.shared.client
            .from("sport_sessions")
            .select("workout_id,sport")
            .in("workout_id", values: wIds)
            .execute()
        struct SS: Decodable { let workout_id: Int; let sport: String }
        let sessions = (try? JSONDecoder.supabase().decode([SS].self, from: sRes?.data ?? Data())) ?? []
        let scRes = try? await SupabaseManager.shared.client
            .from("workout_scores")
            .select("workout_id,score")
            .in("workout_id", values: wIds)
            .execute()
        struct SRow: Decodable { let workout_id: Int; let score: Decimal }
        let scores = (try? JSONDecoder.supabase().decode([SRow].self, from: scRes?.data ?? Data())) ?? []
        
        var totalByWorkout: [Int: Double] = [:]
        for s in scores {
            totalByWorkout[s.workout_id, default: 0] += NSDecimalNumber(decimal: s.score).doubleValue
        }
        var bestScore = 0
        var bestLabel = ""
        for ss in sessions {
            let sc = Int((totalByWorkout[ss.workout_id] ?? 0).rounded())
            if sc > bestScore {
                bestScore = sc
                bestLabel = ss.sport.capitalized
            }
        }
        
        await MainActor.run {
            self.bestSportScore = bestScore
            self.bestSportLabel = bestLabel
        }
    }
    
    private func sameDay(_ a: Date?, _ b: Date?) -> Bool {
        guard let a, let b else { return false }
        return Calendar.current.isDate(a, inSameDayAs: b)
    }
    
    private func dateLabel(_ d: Date?) -> String {
        guard let d else { return "—" }
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "Today" }
        if cal.isDateInYesterday(d) { return "Yesterday" }
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .none
        return f.string(from: d)
    }
    
    private func computeStreak(from dates: [Date]) -> Int {
        let cal = Calendar.current
        let days = Set(dates.map { cal.startOfDay(for: $0) })
        var s = 0
        var cursor = cal.startOfDay(for: Date())
        while days.contains(cursor) {
            s += 1
            cursor = cal.date(byAdding: .day, value: -1, to: cursor)!
        }
        return s
    }
    
    private func weekRange() -> (Date, Date) {
        var cal = Calendar.current
        cal.firstWeekday = 2
        let now = Date()
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
        let start = cal.date(from: comps)!
        return (start, now)
    }
    
    private var weeklyGoalsModule: some View {
        CollapsibleCard(
            isCollapsed: collapseGoals,
            onToggle: {
                withAnimation(.easeInOut) {
                    collapseGoals.toggle()
                    if !collapseGoals {
                        collapseMonthly = true
                        collapseToday = true
                        collapseStreak = true
                        collapseInsights = true
                    }
                }
            },
            collapsed: {
                HStack(spacing: 8) {
                    Image(systemName: "target")
                        .foregroundStyle(.secondary)
                    Text("Weekly goals")
                        .font(.subheadline.weight(.semibold))
                    Spacer(minLength: 0)
                }
                .padding(12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.18)))
            },
            expanded: {
                Button {
                    showGoals = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "target")
                            .font(.headline.weight(.semibold))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Weekly goals")
                                .font(.subheadline.weight(.semibold))
                            Text("Track your objectives")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.18)))
                }
                .buttonStyle(.plain)
            }
        )
    }
    
    private var competitionsModule: some View {
        Button {
            showCompetitions = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "trophy")
                    .font(.headline.weight(.semibold))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Competitions")
                        .font(.subheadline.weight(.semibold))
                    Text("Active & pending")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.18)))
        }
        .buttonStyle(.plain)
    }
}


private struct TodaySummaryCard: View {
    let count: Int
    let minutes: Int
    let points: Int
    let kcal: Int
    
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Today").font(.headline)
                Text(kcal > 0
                     ? "\(count) workouts • \(minutes) min • \(points) pts • \(kcal) kcal"
                     : "\(count) workouts • \(minutes) min • \(points) pts")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.18)))
    }
}

private struct StreakWeekCard: View {
    let streak: Int
    let weekWorkouts: Int
    let weekPoints: Int
    let weekKcal: Int
    var body: some View {
        HStack {
            if streak > 0 {
                Label("\(streak)-day streak", systemImage: "flame.fill")
            } else {
                Label("Start streak", systemImage: "flame")
            }
            Spacer()
            Text(weekKcal > 0
                 ? "\(weekWorkouts) this week • \(weekPoints) pts • \(weekKcal) kcal"
                 : "\(weekWorkouts) this week • \(weekPoints) pts")
        }
        .font(.subheadline.weight(.semibold))
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.18)))
    }
}

private struct MonthlySummaryCard: View {
    let summary: HomeView.MonthSummary
    let onShare: (UIImage) -> Void
    @State private var expanded = false
    @State private var cachedShareImage: UIImage? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(titleText)
                    .font(.headline)
                Spacer()
                medalView
            }
            
            Text(lineText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Button(expanded ? "Show less" : "Show more") {
                withAnimation(.easeInOut) { expanded.toggle() }
            }
            .font(.caption.weight(.semibold))
            .buttonStyle(.plain)
            
            if expanded {
                Chart(summary.series) { p in
                    LineMark(
                        x: .value("Day", p.label),
                        y: .value("Score", p.value)
                    )
                    .interpolationMethod(.catmullRom)
                    
                    AreaMark(
                        x: .value("Day", p.label),
                        y: .value("Score", p.value)
                    )
                    .opacity(0.15)
                }
                .chartPlotStyle { plotArea in
                    plotArea
                        .background(Color.gray.opacity(0.18))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .frame(height: 140)
                .onAppear {
                    if cachedShareImage == nil {
                        cachedShareImage = renderCard()
                    }
                }
                HStack {
                    Spacer()
                    Button {
                        if let img = cachedShareImage ?? renderCard() {
                            onShare(img)
                        }
                    } label: {
                        Label("Share your progress", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.18)))
    }
    
    private var titleText: String {
        let m = summary.month
        let y = summary.year
        let monthName = DateFormatter().monthSymbols[(max(1,m)-1) % 12]
        return "\(monthName) \(y) summary"
    }
    
    private var lineText: String {
        let delta = String(format: "%@%.0f%%", summary.deltaPercent >= 0 ? "+" : "", summary.deltaPercent)
        return "Workouts: \(summary.workouts)  •  Total score: \(summary.totalScore)  •  Improvement: \(delta)"
    }
    
    @ViewBuilder
    private var medalView: some View {
        if summary.workouts >= 20 || summary.deltaPercent >= 10 {
            Image(systemName: "medal.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(.yellow, .orange)
        } else {
            Image(systemName: "star.circle.fill")
                .foregroundStyle(.secondary)
        }
    }
    private func renderCard() -> UIImage? {
        let renderer = ImageRenderer(content:
                                        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(titleText).font(.headline)
                Spacer()
                medalView
            }
            Text(lineText).font(.subheadline).foregroundStyle(.secondary)
            Chart(summary.series) { p in
                LineMark(x: .value("Day", p.label), y: .value("Score", p.value))
                    .lineStyle(.init(lineWidth: 2))
                    .interpolationMethod(.catmullRom)
                AreaMark(x: .value("Day", p.label), y: .value("Score", p.value)).opacity(0.15)
            }
            .chartPlotStyle { plotArea in
                plotArea
                    .background(Color.gray.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .frame(height: 140)
        }
            .padding(14)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.black.opacity(0.06))
            )
                .background(Color.white)
                .environment(\.colorScheme, .light)
                .frame(width: 360)
        )
        renderer.scale = UIScreen.main.scale
        renderer.isOpaque = true
        return renderer.uiImage
    }
}

private struct HighlightsCard: View {
    let prs: [HomeView.PRRow]
    let weeklyTop: [(user: HomeView.ProfileRow, points: Int)]
    let profileFor: (UUID) -> HomeView.ProfileRow?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            
            if !prs.isEmpty {
                Text("Recent PRs").font(.subheadline.weight(.semibold))
                
                ForEach(prs.prefix(5)) { pr in
                    let owner = profileFor(pr.user_id)
                    
                    HStack(spacing: 10) {
                        AvatarView(urlString: owner?.avatar_url)
                            .frame(width: 28, height: 28)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(owner.map { "@\($0.username)" } ?? "@user")
                                    .font(.subheadline.weight(.semibold))
                                Text("• \(prettyMetric(pr.metric))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Text("\(pr.label): \(formatValue(pr))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        
                        Spacer()
                        
                        Text(relative(pr.achieved_at))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            if !weeklyTop.isEmpty {
                if !prs.isEmpty { Divider() }
                Text("Top this week").font(.subheadline.weight(.semibold))
                ForEach(weeklyTop.indices, id: \.self) { i in
                    let row = weeklyTop[i]
                    HStack(spacing: 10) {
                        Text("#\(i+1)").font(.caption).foregroundStyle(.secondary).frame(width: 22)
                        AvatarView(urlString: row.user.avatar_url).frame(width: 28, height: 28)
                        Text("@\(row.user.username)").font(.subheadline)
                        Spacer()
                        Text("\(row.points) pts").font(.subheadline.weight(.semibold))
                    }
                }
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.18)))
    }
    
    private func prettyMetric(_ m: String) -> String {
        switch m.lowercased() {
        case "max_hr": return "Max HR"
        case "longest_duration_sec": return "Longest duration"
        case "longest_distance_km": return "Longest distance"
        case "fastest_pace_sec_per_km": return "Fastest pace"
        case "max_elevation_m": return "Max elevation"
        case "est_1rm_kg": return "Estimated 1RM"
        case "max_weight_kg": return "Max weight"
        case "best_set_volume_kg": return "Best set volume"
        case "max_reps": return "Max reps"
        default: return m.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
    private func formatValue(_ pr: HomeView.PRRow) -> String {
        let m = pr.metric.lowercased(), v = pr.value
        if m.hasSuffix("_kg") || m == "est_1rm_kg" || m == "max_weight_kg" || m == "best_set_volume_kg" {
            return String(format: "%.1f kg", v)
        }
        if m.contains("reps") { return "\(Int(v.rounded())) reps" }
        if m == "max_hr" { return "\(Int(v.rounded())) bpm" }
        if m == "longest_distance_km" { return String(format: "%.1f km", v) }
        if m == "max_elevation_m" { return "\(Int(v.rounded())) m" }
        if m == "fastest_pace_sec_per_km" { return paceString(v) }
        if m.hasSuffix("_sec") || m.contains("duration") { return durationString(v) }
        return String(format: "%.2f", v)
    }
    private func durationString(_ secondsDouble: Double) -> String {
        let s = max(0, Int(secondsDouble.rounded()))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, sec) }
        return String(format: "%d:%02d", m, sec)
    }
    private func paceString(_ secondsDouble: Double) -> String {
        let s = max(1, Int(secondsDouble.rounded()))
        let m = s / 60, sec = s % 60
        return String(format: "%d:%02d /km", m, sec)
    }
    private func relative(_ d: Date) -> String {
        let f = RelativeDateTimeFormatter(); f.unitsStyle = .short
        return f.localizedString(for: d, relativeTo: Date())
    }
}

private struct InsightsRow: View {
    let strongestWeekPts: Int
    let strongestWeekKcal: Int
    let bestSportScore: Int
    let bestSportLabel: String
    
    var body: some View {
        HStack(spacing: 8) {
            if strongestWeekPts > 0 {
                if strongestWeekKcal > 0 {
                    InsightPill(text: "💪 Strongest week: \(strongestWeekPts) pts • \(strongestWeekKcal) kcal")
                } else {
                    InsightPill(text: "💪 Strongest week: \(strongestWeekPts) pts")
                }
            }
            if bestSportScore > 0 {
                Spacer(minLength: 8)
                InsightPill(text: "⚽ Best sport: \(bestSportScore) (\(bestSportLabel))")
            }
        }
        .frame(maxWidth: .infinity)
    }
    
    private struct InsightPill: View {
        let text: String
        var body: some View {
            Text(text)
                .font(.caption.weight(.semibold))
                .padding(.vertical, 6).padding(.horizontal, 10)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.18)))
        }
    }
}


private struct HomeFeedCard: View {
    private func sportIcon(for sport: String?) -> String {
        switch sport {
        case "padel", "tennis", "squash", "badminton", "table_tennis":
            return "🎾"
        case "football":
            return "⚽️"
        case "basketball":
            return "🏀"
        case "volleyball":
            return "🏐"
        case "running":
            return "🏃‍♂️"
        case "cycling":
            return "🚴‍♂️"
        case "rugby":
            return "🏉"
        case "hockey", "field_hockey":
            return "🏑"
        case "ice_hockey":
            return "🏒"
        case "handball":
            return "🤾‍♂️"
        case "hyrox":
            return "🔥"
        default:
            return ""
        }
    }
    
    private func cardioIcon(for activity: String?) -> String {
        switch (activity ?? "").lowercased() {
        case "run", "outdoor_run", "trail_run": return "🏃‍♂️"
        case "treadmill":                       return "🏃‍♀️"
        case "walk", "hike":                    return "🚶‍♂️"
        case "cycling", "road_cycling":         return "🚴‍♂️"
        case "indoor_cycling", "spinning":      return "🚲"
        case "rowerg", "rowing":                return "🚣‍♂️"
        case "ski_erg":                         return "⛷️"
        case "elliptical":                      return "🌀"
        case "stairs", "stairmaster":           return "🪜"
        case "swim_pool":                       return "🏊‍♂️"
        case "swim_open_water":                 return "🌊"
        default:                                return "❤️‍🔥"
        }
    }
    let item: HomeView.FeedItem
    
    var body: some View {
        ZStack {
            WorkoutCardBackground(kind: item.workout.kind)
            
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 12) {
                    ZStack(alignment: .bottomTrailing) {
                        AvatarView(urlString: item.avatarURL)
                            .frame(width: 42, height: 42)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        
                        if !item.coUserAvatarURLs.isEmpty {
                            HStack(spacing: -8) {
                                ForEach(Array(item.coUserAvatarURLs.prefix(3)), id: \.self) { url in
                                    AvatarView(urlString: url)
                                        .frame(width: 18, height: 18)
                                        .clipShape(Circle())
                                        .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))
                                }
                                if item.coUserAvatarURLs.count > 3 {
                                    Text("+\(item.coUserAvatarURLs.count - 3)")
                                        .font(.caption2.weight(.bold))
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(Capsule().fill(Color(.systemBackground)))
                                        .overlay(Capsule().stroke(Color.black.opacity(0.1)))
                                }
                            }
                            .offset(x: 2, y: 2)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(item.username)
                                .font(.subheadline.weight(.semibold))
                        }
                        
                        if item.workout.state == "planned" {
                            Text(item.workout.title ?? item.workout.kind.capitalized)
                                .font(.body)
                                .italic()
                                .lineLimit(1)
                        } else {
                            Text(item.workout.title ?? item.workout.kind.capitalized)
                                .font(.body)
                                .lineLimit(1)
                        }
                        
                        if let d = item.workout.started_at {
                            Text(relative(d))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 6) {
                        HStack(spacing: 8) {
                            if let kcal = item.caloriesKcal, kcal > 0 {
                                caloriesPill(kcal: kcal)
                            }
                            if let sc = item.score {
                                scorePill(score: sc, kind: item.workout.kind)
                            }
                        }
                    }
                }
                HStack {
                    HStack(spacing: 4) {
                        Text(item.workout.kind.capitalized)
                        switch item.workout.kind {
                        case "sport":
                            if let sport = item.workout.sport {
                                Text(sportIcon(for: sport))
                            }
                        case "cardio":
                            Text(cardioIcon(for: item.workout.cardioActivity))
                        case "strength":
                            Text("🏋️‍♂️")
                        default:
                            EmptyView()
                        }
                    }
                    .font(.caption2.weight(.semibold))
                    .padding(.vertical, 3)
                    .padding(.horizontal, 6)
                    .background(Capsule().fill(workoutTint(for: item.workout.kind).opacity(0.18)))
                    .overlay(Capsule().stroke(Color.white.opacity(0.12)))
                    
                    Spacer()
                    
                    likesPill()
                    
                    if item.workout.state == "planned" {
                        HStack(spacing: 4) {
                            Image(systemName: "pencil")
                            Text("Draft")
                        }
                        .font(.caption2.weight(.semibold))
                        .padding(.vertical, 3)
                        .padding(.horizontal, 6)
                        .background(Capsule().fill(Color.yellow.opacity(0.22)))
                        .overlay(Capsule().stroke(Color.white.opacity(0.12)))
                    }
                }
            }
            .opacity(item.workout.state == "planned" ? 0.72 : 1.0)
            .padding(14)
        }
    }
    
    private func caloriesPill(kcal: Double) -> some View {
        let value = Int(kcal.rounded())
        return Text("\(value) 🔥")
            .font(.subheadline.weight(.semibold))
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.18)))
    }
    
    private func likesPill() -> some View {
        HStack(spacing: 6) {
            Image(systemName: item.isLiked ? "heart.fill" : "heart")
                .symbolRenderingMode(.palette)
                .foregroundStyle(item.isLiked ? .red : .secondary)
            Text("\(item.likeCount)")
                .font(.subheadline.weight(.semibold))
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.18)))
    }
    
    private func relative(_ d: Date) -> String {
        let f = RelativeDateTimeFormatter(); f.unitsStyle = .short
        return f.localizedString(for: d, relativeTo: Date())
    }
}

private struct CollapsibleCard<Expanded: View, Collapsed: View>: View {
    let isCollapsed: Bool
    let onToggle: () -> Void
    let collapsed: () -> Collapsed
    let expanded: () -> Expanded
    
    var body: some View {
        Group {
            if isCollapsed {
                Button(action: onToggle) {
                    collapsed()
                }
                .buttonStyle(.plain)
            } else {
                expanded()
            }
        }
    }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) { }
}
