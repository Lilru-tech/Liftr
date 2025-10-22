import SwiftUI
import Supabase

extension Notification.Name {
  static let workoutDidChange = Notification.Name("workoutDidChange")
}

struct HomeView: View {
  @EnvironmentObject var app: AppState

  enum KindFilter: String, CaseIterable { case all = "All", strength = "Strength", cardio = "Cardio", sport = "Sport" }
  @State private var filter: KindFilter = .all

  struct WorkoutRow: Decodable, Identifiable {
    let id: Int
    let user_id: UUID
    let kind: String
    let title: String?
    let started_at: Date?
    let ended_at: Date?
  }
  private struct FollowRow: Decodable { let followee_id: UUID }
  struct ProfileRow: Decodable { let user_id: UUID; let username: String; let avatar_url: String? }
  private struct WorkoutScoreRow: Decodable { let workout_id: Int; let score: Decimal }

  struct PRRow: Decodable, Identifiable {
    let kind: String
    let user_id: UUID
    let label: String
    let metric: String
    let value: Double
    let achieved_at: Date
    var id: String { "\(user_id.uuidString)|\(label)|\(metric)|\(achieved_at.timeIntervalSince1970)" }
  }

    struct FeedItem: Identifiable, Hashable, Equatable {
      let id: Int
      let workout: WorkoutRow
      let username: String
      let avatarURL: String?
      let score: Double?

      func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(workout.kind)
        hasher.combine(workout.title ?? "")
        hasher.combine(workout.started_at?.timeIntervalSince1970 ?? 0)
        hasher.combine(workout.ended_at?.timeIntervalSince1970 ?? 0)
        hasher.combine(username)
        hasher.combine(avatarURL ?? "")
        hasher.combine(score ?? -1)
      }

      static func == (lhs: FeedItem, rhs: FeedItem) -> Bool {
        lhs.id == rhs.id &&
        lhs.workout.kind == rhs.workout.kind &&
        (lhs.workout.title ?? "") == (rhs.workout.title ?? "") &&
        (lhs.workout.started_at?.timeIntervalSince1970 ?? 0) == (rhs.workout.started_at?.timeIntervalSince1970 ?? 0) &&
        (lhs.workout.ended_at?.timeIntervalSince1970 ?? 0) == (rhs.workout.ended_at?.timeIntervalSince1970 ?? 0) &&
        lhs.username == rhs.username &&
        (lhs.avatarURL ?? "") == (rhs.avatarURL ?? "") &&
        (lhs.score ?? -1) == (rhs.score ?? -1)
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
  @State private var streakDays = 0
  @State private var weekWorkouts = 0
  @State private var weekPoints = 0
  @State private var recentPRs: [PRRow] = []
  @State private var weeklyTop: [(user: ProfileRow, points: Int)] = []

  private let highlightsInsertIndex = 5

  var body: some View {
    VStack(spacing: 8) {
      Picker("", selection: $filter) {
        ForEach(KindFilter.allCases, id: \.self) { k in Text(k.rawValue).tag(k) }
      }
      .pickerStyle(.segmented)
      .padding(.horizontal)

      VStack(spacing: 8) {
        TodaySummaryCard(count: todayCount, minutes: todayMinutes, points: todayPoints)
        StreakWeekCard(streak: streakDays, weekWorkouts: weekWorkouts, weekPoints: weekPoints)
      }
      .padding(.horizontal)

      List {
        if initialLoading && feed.isEmpty {
          ProgressView().frame(maxWidth: .infinity)
        }

          ForEach(Array(feed.enumerated()), id: \.element.id) { i, item in
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

            if i == highlightsInsertIndex, !recentPRs.isEmpty || !weeklyTop.isEmpty {
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
        .onDisappear {
          print("[Home.navDest.onDisappear] leaving WorkoutDetailView id=\(it.id) main=\(Thread.isMainThread)")
          selectedItem = nil
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
        print("[Home.onReceive workoutUpdated] ui.title=\(String(describing: ui["title"])) ui.kind=\(String(describing: ui["kind"])) ui.started_at=\(String(describing: ui["started_at"])) ui.ended_at=\(String(describing: ui["ended_at"])) ui.score=\(String(describing: ui["score"]))")
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
            started_at: startedAt ?? old.workout.started_at,
            ended_at: endedAt ?? old.workout.ended_at
          )

          Task { await MainActor.run {
            feed[idx] = FeedItem(
              id: old.id,
              workout: patched,
              username: old.username,
              avatarURL: old.avatarURL,
              score: newScore ?? old.score
            )
              feed.sort { ($0.workout.started_at ?? .distantPast) > ($1.workout.started_at ?? .distantPast) }
              print("[Home.onReceive workoutUpdated] patched OK (title=\(title ?? "nil"), score=\(String(describing: newScore)))")
            }}
            Task { await recalcHomeSummaries() }
            return
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
        _ = await (t, w, s, r)

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

        var q: PostgrestFilterBuilder = SupabaseManager.shared.client
          .from("workouts")
          .select("id, user_id, kind, title, started_at, ended_at")
          .in("user_id", values: allIds.map { $0.uuidString })

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

        let items: [FeedItem] = workouts.map { w in
          let prof = profiles[w.user_id]
          return FeedItem(
            id: w.id,
            workout: w,
            username: prof?.username ?? (w.user_id == me ? "You" : "—"),
            avatarURL: prof?.avatar_url,
            score: scoresDict[w.id]
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
          .select("id, user_id, kind, title, started_at, ended_at")
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

        let updated = FeedItem(
          id: w.id,
          workout: w,
          username: prof?.username ?? (w.user_id == me ? "You" : "—"),
          avatarURL: prof?.avatar_url,
          score: score
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
          .select("id, user_id, kind, title, started_at, ended_at")
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
        for w in rows {
          if let s = w.started_at, let e = w.ended_at {
            minutes += max(Int(e.timeIntervalSince(s))/60, 0)
          }
          if let sc = scoresDict[w.id] { points += Int(sc.rounded()) }
        }

        await MainActor.run {
          self.todayCount = rows.count
          self.todayMinutes = minutes
          self.todayPoints = points
        }
      } catch { }
    }
    
    private func recalcHomeSummaries() async {
      async let t: Void = loadTodaySummary()
      async let w: Void = loadWeekSummaryAndLeaderboard()
      async let s: Void = loadStreak()
      async let r: Void = loadRecentPRs()
      _ = await (t, w, s, r)
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
          .select("id, user_id, started_at, ended_at, kind, title")
          .in("user_id", values: allIds.map { $0.uuidString })
          .gte("started_at", value: iso.string(from: weekStart))
          .lt("started_at", value: iso.string(from: now))
          .order("started_at", ascending: false)
          .execute()
        let rowsAll = try JSONDecoder.supabase().decode([WorkoutRow].self, from: allRes.data)

        let meRes = try await SupabaseManager.shared.client
          .from("workouts")
          .select("id, user_id, started_at, ended_at, kind, title")
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
        for w in rowsMe { myWeekPts += Int((scoresDict[w.id] ?? 0).rounded()) }

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
          self.weeklyTop    = top
        }
      } catch { /* ignore */ }
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
}


private struct TodaySummaryCard: View {
  let count: Int; let minutes: Int; let points: Int
  var body: some View {
    HStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 2) {
        Text("Today").font(.headline)
        Text("\(count) workouts • \(minutes) min • \(points) pts")
          .font(.subheadline).foregroundStyle(.secondary)
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
  var body: some View {
    HStack {
      Label("\(streak)-day streak", systemImage: "flame.fill")
      Spacer()
      Text("\(weekWorkouts) this week • \(weekPoints) pts")
    }
    .font(.subheadline.weight(.semibold))
    .padding(12)
    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.18)))
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


private struct HomeFeedCard: View {
  let item: HomeView.FeedItem

  var body: some View {
    ZStack {
      WorkoutCardBackground(kind: item.workout.kind)
      HStack(alignment: .top, spacing: 12) {
        AvatarView(urlString: item.avatarURL)
          .frame(width: 42, height: 42)
          .clipShape(RoundedRectangle(cornerRadius: 10))

        VStack(alignment: .leading, spacing: 4) {
          HStack(spacing: 6) {
            Text(item.username).font(.subheadline.weight(.semibold))
          }
          Text(item.workout.title ?? item.workout.kind.capitalized)
            .font(.body).lineLimit(1)
          if let d = item.workout.started_at {
            Text(relative(d)).font(.caption2).foregroundStyle(.secondary)
          }

          Text(item.workout.kind.capitalized)
            .font(.caption2.weight(.semibold))
            .padding(.vertical, 3)
            .padding(.horizontal, 6)
            .background(Capsule().fill(workoutTint(for: item.workout.kind).opacity(0.18)))
            .overlay(Capsule().stroke(Color.white.opacity(0.12)))
        }

        Spacer()

        if let sc = item.score {
          scorePill(score: sc, kind: item.workout.kind)
        }
      }
      .padding(14)
    }
  }

  private func relative(_ d: Date) -> String {
    let f = RelativeDateTimeFormatter(); f.unitsStyle = .short
    return f.localizedString(for: d, relativeTo: Date())
  }
}
