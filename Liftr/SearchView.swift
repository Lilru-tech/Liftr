import SwiftUI
import Supabase

struct SearchView: View {
    @EnvironmentObject var app: AppState
    @AppStorage("isPremium") private var isPremium: Bool = false

    private enum SearchTab: String, CaseIterable, Identifiable {
        case users
        case workouts
        case segments
        var id: String { rawValue }
        var label: String {
            switch self {
            case .users: "Users"
            case .workouts: "Workouts"
            case .segments: "Segments"
            }
        }
        var rpcScope: String {
            switch self {
            case .users: "users"
            case .workouts: "workouts"
            case .segments: "segments"
            }
        }
    }

    @State private var tab: SearchTab = .users
    @State private var query = ""
    @State private var userResults: [UserRow] = []
    @State private var workoutResults: [WorkoutSearchRow] = []
    @State private var segmentResults: [SegmentSearchRow] = []
    @State private var usernamesByUserId: [UUID: String] = [:]
    @State private var loading = false
    @State private var searchTask: Task<Void, Never>? = nil

    @State private var trending: [TrendingRow] = []
    @State private var recents: [RecentRow] = []
    @State private var suggestionsLoading = false
    @State private var showClearRecentsConfirm = false

    private struct RecordSearchParams: Encodable {
        let p_query: String
        let p_scope: String
    }

    private struct TrendingRow: Decodable, Identifiable {
        let normalized_query: String
        let search_count: Int
        var id: String { normalized_query }
    }

    private struct RecentRow: Decodable, Identifiable {
        let normalized_query: String
        let scope: String
        let searched_at: Date
        var id: String { "\(normalized_query)|\(scope)|\(searched_at.timeIntervalSince1970)" }
    }

    private struct UserRow: Decodable, Identifiable {
        let user_id: UUID
        let username: String
        let avatar_url: String?
        var id: UUID { user_id }
    }

    private struct WorkoutSearchRow: Decodable, Identifiable {
        let id: Int
        let user_id: UUID
        let kind: String
        let title: String?
        let started_at: Date?
    }

    private struct SegmentSearchRow: Decodable, Identifiable {
        let id: UUID
        let name: String
        let buffer_m: Double?
    }

    private struct WorkoutOwnerRow: Decodable {
        let user_id: UUID
        let username: String
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(spacing: 8) {
            Picker("", selection: $tab) {
                ForEach(SearchTab.allCases) { t in
                    Text(t.label).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                TextField(
                    tab == .users ? "Search users…" : (tab == .workouts ? "Search workouts…" : "Search segments…"),
                    text: $query
                )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            .padding(12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)

            List {
                if trimmedQuery.isEmpty {
                    suggestionsSections
                } else {
                    resultsSections
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .listRowSeparator(.hidden)
            .refreshable { await loadSuggestions() }

            if !isPremium {
                BannerAdView(adUnitID: "ca-app-pub-7676731162362384/7781347704")
                    .frame(height: 50)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }
        }
        .onAppear { Task { await loadSuggestions() } }
        .onChange(of: query) { _, newValue in
            searchTask?.cancel()
            searchTask = Task {
                try? await Task.sleep(nanoseconds: 250_000_000)
                if Task.isCancelled { return }
                await runSearch(q: newValue)
            }
        }
        .onChange(of: tab) { _, _ in
            searchTask?.cancel()
            searchTask = Task {
                try? await Task.sleep(nanoseconds: 250_000_000)
                if Task.isCancelled { return }
                await runSearch(q: query)
            }
        }
        .onDisappear { searchTask?.cancel() }
        .alert("Clear all recent searches?", isPresented: $showClearRecentsConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) {
                Task { await clearRecents() }
            }
        }
    }

    @ViewBuilder
    private var suggestionsSections: some View {
        if suggestionsLoading && trending.isEmpty && recents.isEmpty {
            Section {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            }
        }

        if !trending.isEmpty {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Trending (24h)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(trending) { row in
                                trendingQueryPill(text: row.normalized_query) {
                                    let q = row.normalized_query
                                    Task {
                                        await MainActor.run { query = q }
                                        await runSearch(q: q)
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listRowBackground(Color.clear)
            }
        }

        if !recents.isEmpty {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Recent")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            showClearRecentsConfirm = true
                        } label: {
                            Image(systemName: "trash")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(recents) { row in
                                recentQueryPill(row: row) {
                                    let q = row.normalized_query
                                    Task {
                                        await MainActor.run {
                                            if row.scope == "workouts" { tab = .workouts }
                                            else if row.scope == "users" { tab = .users }
                                            else if row.scope == "segments" { tab = .segments }
                                            query = q
                                        }
                                        await runSearch(q: q)
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listRowBackground(Color.clear)
            }
        }
    }

    private func trendingQueryPill(text: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func recentQueryPill(row: RecentRow, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.normalized_query)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                Text(
                    row.scope == "workouts" ? "Workouts" : (row.scope == "segments" ? "Segments" : "Users")
                )
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(red: 0.47, green: 0.36, blue: 0.88).opacity(0.26))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color(red: 0.47, green: 0.36, blue: 0.88).opacity(0.42), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var resultsSections: some View {
        Section {
            if loading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            }

            if tab == .segments {
                ForEach(segmentResults) { row in
                    NavigationLink {
                        SegmentDetailView(segmentId: row.id, onClose: nil)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(row.name)
                                .font(.body.weight(.medium))
                            if let b = row.buffer_m {
                                Text("Buffer \(Int(b)) m")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .listRowBackground(Color.clear)
                }
                if !loading && segmentResults.isEmpty {
                    Text("No segments found")
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                }
            } else if tab == .users {
                ForEach(userResults, id: \.user_id) { row in
                    NavigationLink {
                        ProfileView(userId: row.user_id)
                            .gradientBG()
                    } label: {
                        HStack(spacing: 12) {
                            AvatarView(urlString: row.avatar_url)
                                .frame(width: 40, height: 40)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            Text("@\(row.username)")
                        }
                    }
                    .listRowBackground(Color.clear)
                }
                if !loading && userResults.isEmpty {
                    Text("No users found")
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                }
            } else {
                ForEach(workoutResults) { row in
                    NavigationLink {
                        WorkoutDetailView(workoutId: row.id, ownerId: row.user_id)
                            .gradientBG()
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text((row.title.flatMap { $0.isEmpty ? nil : $0 }) ?? "Untitled")
                                .font(.body.weight(.medium))
                            HStack(spacing: 6) {
                                if let username = usernamesByUserId[row.user_id], !username.isEmpty {
                                    Text("@\(username)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text("·")
                                        .foregroundStyle(.tertiary)
                                }
                                Text(row.kind.capitalized)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if let d = row.started_at {
                                    Text("·")
                                        .foregroundStyle(.tertiary)
                                    Text(d, style: .date)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .listRowBackground(Color.clear)
                }
                if !loading && workoutResults.isEmpty {
                    Text("No workouts found")
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                }
            }
        }
    }

    private func loadSuggestions() async {
        guard app.userId != nil else {
            await MainActor.run {
                trending = []
                recents = []
            }
            return
        }

        await MainActor.run { suggestionsLoading = true }
        defer {
            Task { await MainActor.run { suggestionsLoading = false } }
        }

        async let t: Void = loadTrending()
        async let r: Void = loadRecents()
        _ = await (t, r)
    }

    private func loadTrending() async {
        do {
            let res = try await SupabaseManager.shared.client
                .rpc("trending_search_queries_24h")
                .execute()
            let rows = try JSONDecoder.supabase().decode([TrendingRow].self, from: res.data)
            await MainActor.run { self.trending = rows }
        } catch {
            await MainActor.run { self.trending = [] }
        }
    }

    private func loadRecents() async {
        do {
            let res = try await SupabaseManager.shared.client
                .rpc("user_search_recent_list")
                .execute()
            let rows = try JSONDecoder.supabase().decode([RecentRow].self, from: res.data)
            await MainActor.run { self.recents = rows }
        } catch {
            await MainActor.run { self.recents = [] }
        }
    }

    private func clearRecents() async {
        guard app.userId != nil else { return }
        do {
            _ = try await SupabaseManager.shared.client
                .rpc("clear_user_search_recent")
                .execute()
            await MainActor.run { recents = [] }
        } catch {
            await loadRecents()
        }
    }

    private func recordSearch(term: String, scope: String) async {
        guard app.userId != nil else { return }
        let params = RecordSearchParams(p_query: term, p_scope: scope)
        do {
            _ = try await SupabaseManager.shared.client
                .rpc("record_search", params: params)
                .execute()
            await loadRecents()
        } catch {
        }
    }

    private func runSearch(q: String) async {
        let term = q.trimmingCharacters(in: .whitespacesAndNewlines)
        guard term.count >= 2 else {
            await MainActor.run {
                userResults = []
                workoutResults = []
                segmentResults = []
                usernamesByUserId = [:]
                loading = false
            }
            return
        }

        let (scopeTab, recordScope) = await MainActor.run { (tab, tab.rpcScope) }

        await MainActor.run { loading = true }

        if scopeTab == .users {
            await searchUsers(term: term, recordScope: recordScope)
        } else if scopeTab == .segments {
            await searchSegments(term: term)
        } else {
            await searchWorkouts(term: term, recordScope: recordScope)
        }

        await MainActor.run { loading = false }
    }

    private struct SearchSegmentsParams: Encodable {
        let p_query: String
        let p_limit: Int
    }

    private func searchSegments(term: String) async {
        do {
            let params = SearchSegmentsParams(p_query: term, p_limit: 50)
            let res = try await SupabaseManager.shared.client
                .rpc("search_segments_v1", params: params)
                .execute()
            let rows = try JSONDecoder.supabase().decode([SegmentSearchRow].self, from: res.data)
            await MainActor.run { self.segmentResults = rows }
        } catch {
            await MainActor.run { self.segmentResults = [] }
        }
    }

    private func searchUsers(term: String, recordScope: String) async {
        do {
            let res = try await SupabaseManager.shared.client
                .from("profiles")
                .select("user_id, username, avatar_url")
                .ilike("username", pattern: "%\(term)%")
                .order("username", ascending: true)
                .limit(50)
                .execute()

            var rows = try JSONDecoder.supabase().decode([UserRow].self, from: res.data)

            if let myId = app.userId {
                rows.removeAll { $0.user_id == myId }
            }

            await MainActor.run { self.userResults = rows }
            await recordSearch(term: term, scope: recordScope)
        } catch {
            await MainActor.run { self.userResults = [] }
        }
    }

    private func workoutSearchOrFilter(term: String) -> String {
        let safe = term.replacingOccurrences(of: ",", with: " ")
        let pattern = "%\(safe)%"
        return "title.ilike.\(pattern),notes.ilike.\(pattern)"
    }

    private func searchWorkouts(term: String, recordScope: String) async {
        do {
            let res = try await SupabaseManager.shared.client
                .from("workouts")
                .select("id, user_id, kind, title, started_at")
                .eq("state", value: "published")
                .or(workoutSearchOrFilter(term: term))
                .order("started_at", ascending: false)
                .limit(50)
                .execute()

            let rows = try JSONDecoder.supabase().decode([WorkoutSearchRow].self, from: res.data)
            let ownerIds = Array(Set(rows.map(\.user_id)))
            var ownerMap: [UUID: String] = [:]

            if !ownerIds.isEmpty {
                let ownerRes = try await SupabaseManager.shared.client
                    .from("profiles")
                    .select("user_id, username")
                    .in("user_id", values: ownerIds.map(\.uuidString))
                    .execute()
                let ownerRows = try JSONDecoder.supabase().decode([WorkoutOwnerRow].self, from: ownerRes.data)
                ownerMap = Dictionary(uniqueKeysWithValues: ownerRows.map { ($0.user_id, $0.username) })
            }

            await MainActor.run {
                self.workoutResults = rows
                self.usernamesByUserId = ownerMap
            }
            await recordSearch(term: term, scope: recordScope)
        } catch {
            await MainActor.run {
                self.workoutResults = []
                self.usernamesByUserId = [:]
            }
        }
    }
}
