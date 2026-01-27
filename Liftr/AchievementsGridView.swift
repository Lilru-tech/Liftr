import SwiftUI
import Supabase

@inline(__always)
func symbolForAchievement(code: String, category: String) -> String {
    let c = code.lowercased()
    let k = category.lowercased()

    switch true {
    case c.hasPrefix("max_weight_"),
         c.hasPrefix("est_1rm_"),
         c.hasPrefix("total_volume_"),
         c.hasPrefix("total_reps_"),
         c.hasPrefix("strength_workouts_"),
         c.hasPrefix("strength_pr_"),
         c.hasPrefix("strength_session_streak_"),
         c.hasPrefix("strength_"):
        return "dumbbell.fill"

    case c.hasPrefix("run_"), c.hasPrefix("pace_"):
        return "figure.run"
        
    case c.hasPrefix("bike_"),
         c.hasPrefix("ebike_"),
         c.hasPrefix("mtb_"),
         c.hasPrefix("indoor_cycling_"),
         c.hasPrefix("treadmill_"):
        return "bicycle"

    case c.hasPrefix("rowerg_"):
        return "water.waves"

    case c.hasPrefix("swim_pool_"),
         c.hasPrefix("swim_ow_"):
        return "water.waves"

    case c.hasPrefix("walk_"):
        return "figure.walk"
    case c.hasPrefix("hike_"):
        return "figure.hiking"

    case c.hasPrefix("hyrox_"):
        return "stopwatch"

    case c.hasPrefix("cardio_"),
         c.hasPrefix("duration_"),
        c.hasPrefix("elev_gain_"):
        return "heart.circle.fill"

    case c.hasPrefix("padel_"),
         c.hasPrefix("tennis_"),
         c.hasPrefix("table_tennis_"),
         c.hasPrefix("squash_"):
        return "sportscourt.fill"
    case c.hasPrefix("football_"):
        return "soccerball"
    case c.hasPrefix("basketball_"):
        return "basketball"
    case c.hasPrefix("volleyball_"):
        return "volleyball"
    case c.hasPrefix("badminton_"):
        return "sportscourt.fill"

    case c.hasPrefix("likes_given_"),
         c.hasPrefix("likes_received_"),
         c.hasPrefix("followers_"),
         c.hasPrefix("first_follow"),
         c.hasPrefix("first_comment"),
         c.hasPrefix("comments_"),
         c.hasPrefix("follows_"):
        return "person.2.fill"

    case c.hasPrefix("ranking_"):
        return "trophy.fill"

    case c.hasPrefix("streak_"),
         c.hasPrefix("multi_streak_"):
        return "flame.fill"

    case c.hasPrefix("first_workout"),
         c.hasPrefix("workouts_"),
         c.hasPrefix("achievements_"),
         c.hasPrefix("first_fail"),
         c.hasPrefix("night_workout"),
         c.hasPrefix("morning_workout"),
         c.hasPrefix("double_session"),
         c.hasPrefix("zero_day"):
        return "star.circle.fill"

    default:
        break
    }

    switch k {
    case "strength": return "dumbbell.fill"
    case "cardio":   return "figure.run"
    case "sport":    return "sportscourt.fill"
    case "streak":   return "flame.fill"
    case "ranking":  return "trophy.fill"
    case "social":   return "person.2.fill"
    default:         return "star.circle.fill"
    }
}

@inline(__always)
func prettySubtype(from code: String, fallbackCategory: String) -> String {
    let c = code.lowercased()
    switch true {
    case c.hasPrefix("run_"), c.hasPrefix("pace_"): return "Running"
    case c.hasPrefix("bike_"): return "Cycling"
    case c.hasPrefix("ebike_"): return "E-Bike"
    case c.hasPrefix("mtb_"): return "MTB"
    case c.hasPrefix("indoor_cycling_"): return "Indoor Cycling"
    case c.hasPrefix("rowerg_"): return "RowErg"
    case c.hasPrefix("swim_pool_"): return "Pool Swim"
    case c.hasPrefix("swim_ow_"): return "Open-Water Swim"
    case c.hasPrefix("walk_"): return "Walking"
    case c.hasPrefix("hike_"): return "Hiking"
    case c.hasPrefix("treadmill_"): return "Treadmill"
    case c.hasPrefix("hyrox_"): return "HYROX"
    case c.hasPrefix("padel_"): return "Padel"
    case c.hasPrefix("tennis_"): return "Tennis"
    case c.hasPrefix("table_tennis_"): return "Table Tennis"
    case c.hasPrefix("squash_"): return "Squash"
    case c.hasPrefix("football_"): return "Football"
    case c.hasPrefix("basketball_"): return "Basketball"
    case c.hasPrefix("volleyball_"): return "Volleyball"
    case c.hasPrefix("badminton_"): return "Badminton"
    default:
        return fallbackCategory.capitalized
    }
}

struct AchievementsGridView: View {
    let userId: UUID?
    let viewedUsername: String
    var externalReloadToken: UUID? = nil
    
    enum LockFilter: String, CaseIterable, Identifiable {
        case all = "All", unlocked = "Unlocked", locked = "Locked"
        var id: String { rawValue }
    }
    enum CategoryFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case general = "General"
        case strength = "Strength", cardio = "Cardio", sport = "Sport"
        case social = "Social", streak = "Streak", ranking = "Ranking"
        var id: String { rawValue }
    }
    
    @State private var lockFilter: LockFilter = .all
    @State private var category: CategoryFilter = .all
    @State private var search = ""
    @State private var showSearch = false
    @FocusState private var searchFocused: Bool
    @State private var items: [AchievementRow] = []
    @State private var loading = false
    @State private var error: String?
    @State private var selected: AchievementRow?
    
    var body: some View {
        VStack(spacing: 10) {
            header
            
            if loading {
                ProgressView().padding(.top, 16)
            } else if let err = error {
                Text(err).foregroundStyle(.red).padding(.horizontal)
            } else {
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                        ForEach(filtered(items)) { it in
                            AchievementTile(item: it)
                                .onTapGesture { selected = it }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 6)
                    .padding(.bottom, 24)
                }
            }
        }
        .safeAreaInset(edge: .top) {
            Color.clear.frame(height: 8)
        }
        .sheet(item: $selected) { row in
            AchievementDetailSheet(row: row)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .task { await load() }
        .onChange(of: externalReloadToken) { _, _ in
            guard externalReloadToken != nil else { return }
            Task { await recomputeAndReload() }
        }
        .refreshable { await recomputeAndReload() }
        .onChange(of: lockFilter) { _, _ in }
        .onChange(of: category) { _, _ in }
    }
    
    private var header: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Picker("", selection: $lockFilter) {
                    ForEach(LockFilter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            .padding(.horizontal)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(CategoryFilter.allCases) { cat in
                        Button {
                            category = cat
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: iconFor(cat))
                                Text(cat.rawValue)
                            }
                            .font(.caption.weight(.semibold))
                            .padding(.vertical, 6)
                            .padding(.horizontal, 10)
                            .background(
                                Capsule().fill(
                                    category == cat ? Color.primary.opacity(0.15)
                                    : Color.white.opacity(0.12)
                                )
                            )
                            .overlay(
                                Capsule().stroke(
                                    Color.white.opacity(category == cat ? 0.28 : 0.12),
                                    lineWidth: 1
                                )
                            )
                            .foregroundStyle(category == cat ? .primary : .secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
            Group {
                if showSearch {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)

                        TextField("Search", text: $search)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($searchFocused)

                        if !search.isEmpty {
                            Button {
                                search = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }

                        Button("Cancel") {
                            withAnimation(.snappy) { showSearch = false }
                            searchFocused = false
                        }
                        .font(.callout)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(.primary.opacity(0.08), lineWidth: 1))
                    .padding(.horizontal)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { searchFocused = true }
                    }
                } else {
                    HStack {
                        Spacer()
                        Button {
                            withAnimation(.snappy) { showSearch = true }
                        } label: {
                            Image(systemName: "magnifyingglass")
                                .font(.headline)
                                .padding(10)
                                .background(Capsule().fill(.white.opacity(0.12)))
                                .overlay(Capsule().stroke(.white.opacity(0.2), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
        }
    }
    
    private func filtered(_ src: [AchievementRow]) -> [AchievementRow] {
        src.filter { it in
            switch lockFilter {
            case .all: true
            case .unlocked: it.is_unlocked
            case .locked: !it.is_unlocked
            }
        }
        .filter { it in
            category == .all ? true : it.category.caseInsensitiveCompare(category.rawValue) == .orderedSame
        }
        .filter { it in
            let q = search.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !q.isEmpty else { return true }
            return it.title.localizedCaseInsensitiveContains(q)
            || (it.description ?? "").localizedCaseInsensitiveContains(q)
            || it.code.localizedCaseInsensitiveContains(q)
        }
        .sorted { a, b in
            if a.is_unlocked != b.is_unlocked { return a.is_unlocked && !b.is_unlocked }
            if a.category != b.category { return a.category < b.category }
            return a.title < b.title
        }
    }
    
    private func load() async {
        guard let uid = userId else { return }
        loading = true; defer { loading = false }
        
        do {
            let res = try await SupabaseManager.shared.client
                .rpc("get_user_achievements", params: ["p_user_id": uid.uuidString])
                .execute()
            
            let rows = try JSONDecoder.supabase().decode([AchievementRow].self, from: res.data)
            await MainActor.run {
                self.items = rows
                self.error = nil
            }
        } catch {
            await MainActor.run { self.error = error.localizedDescription }
        }
    }
    
    private func recomputeAndReload() async {
        guard let uid = userId else { return }
        do {
            _ = try await SupabaseManager.shared.client
                .rpc("check_and_unlock_achievements_for", params: ["p_user_id": uid.uuidString])
                .execute()
        } catch { }
        
        await load()
    }
    
    private func iconFor(_ cat: CategoryFilter) -> String {
        switch cat {
        case .all:      return "line.3.horizontal.decrease.circle"
        case .strength: return "dumbbell.fill"
        case .general:  return "star.circle.fill"
        case .cardio:   return "figure.run"
        case .sport:    return "sportscourt.fill"
        case .social:   return "person.2.fill"
        case .streak:   return "flame.fill"
        case .ranking:  return "trophy.fill"
        }
    }
}

struct AchievementRow: Decodable, Identifiable {
    let achievement_id: Int
    let code: String
    let title: String
    let description: String?
    let category: String
    let icon_url: String?
    let user_id: UUID?
    let unlocked_at: Date?
    let is_unlocked: Bool
    var id: String { "\(achievement_id)|\(code)" }
}

private struct AchievementTile: View {
    let item: AchievementRow
    
    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial)
                    .frame(height: 64)
                
                Group {
                    if let urlStr = item.icon_url, let url = URL(string: urlStr) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .empty: ProgressView()
                            case .success(let img): img.resizable().scaledToFit().padding(10)
                            case .failure: Image(systemName: symbolForAchievement(code: item.code, category: item.category))
                                    .resizable().scaledToFit().padding(12)
                            @unknown default: EmptyView()
                            }
                        }
                    } else {
                        Image(systemName: symbolForAchievement(code: item.code, category: item.category))
                            .resizable().scaledToFit().padding(12)
                    }
                }
                .opacity(item.is_unlocked ? 1.0 : 0.35)
                
                if !item.is_unlocked {
                    Image(systemName: "lock.fill")
                        .font(.caption.weight(.bold))
                        .padding(6)
                        .background(.thinMaterial, in: Circle())
                        .offset(x: 20, y: 20)
                        .opacity(0.9)
                }
            }
            
            Text(item.title)
                .font(.caption2.weight(.semibold))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .opacity(item.is_unlocked ? 1 : 0.6)
        }
    }

}

private struct AchievementDetailSheet: View {
    let row: AchievementRow
    
    var body: some View {
        VStack(spacing: 14) {
            Capsule().fill(.secondary.opacity(0.25)).frame(width: 40, height: 5).padding(.top, 8)
            
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial).frame(width: 64, height: 64)
                    Image(systemName: symbolForAchievement(code: row.code, category: row.category))
                        .font(.system(size: 28, weight: .regular))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.title).font(.headline)
                    HStack(spacing: 6) {
                        Text(prettySubtype(from: row.code, fallbackCategory: row.category))
                            .font(.caption2.weight(.semibold))
                            .padding(.vertical, 3).padding(.horizontal, 6)
                            .background(Capsule().fill(Color.black.opacity(0.08)))
                        if row.is_unlocked, let d = row.unlocked_at {
                            Text("Unlocked \(dateOnly(d))").font(.caption2).foregroundStyle(.secondary)
                        } else {
                            Text("Locked").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer()
            }
            .padding(.horizontal)
            
            ScrollView {
                Text((row.description ?? "").isEmpty ? "No description." : (row.description ?? ""))
                    .font(.body)
                    .padding(.horizontal)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            Spacer(minLength: 10)
        }
    }
    
    private func dateOnly(_ d: Date) -> String {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .none
        return f.string(from: d)
    }
}
