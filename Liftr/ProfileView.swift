import SwiftUI
import Supabase
import PhotosUI
import UIKit
import Charts
import StoreKit

private struct ProfileCounts: Decodable, Identifiable {
    let user_id: UUID
    let followers: Int
    let following: Int
    var id: UUID { user_id }
}

private struct ProfileRow: Decodable {
    let user_id: UUID
    let username: String
    let avatar_url: String?
    let bio: String?
    let height_cm: Int?
    let weight_kg: Double?
    let birth_date: Date?
}

private struct DayActivity: Decodable, Identifiable {
    let day: String
    let workouts_count: Int
    var id: String { day }
}

private struct WorkoutRow: Decodable, Identifiable {
    let id: Int
    let user_id: UUID
    let kind: String
    let title: String?
    let started_at: Date?
    let ended_at: Date?
    let state: String?
}

private struct WorkoutScoreRow: Decodable {
    let workout_id: Int
    let score: Decimal
}

private struct OnlyStartedAt: Decodable {
    let started_at: Date?
    let state: String?
}

private struct GetMonthActivityParams: Encodable {
    let p_user_id: UUID
    let p_year: Int
    let p_month: Int
}

private struct FollowRow: Decodable { let follower_id: UUID }

extension JSONDecoder {
    static func supabase() -> JSONDecoder {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .custom { decoder in
            let s = try decoder.singleValueContainer().decode(String.self)
            
            do {
                let f = ISO8601DateFormatter()
                f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let d = f.date(from: s) { return d }
            }
            
            do {
                let f = ISO8601DateFormatter()
                f.formatOptions = [.withInternetDateTime]
                if let d = f.date(from: s) { return d }
            }
            
            do {
                let f = DateFormatter()
                f.locale = Locale(identifier: "en_US_POSIX")
                f.timeZone = TimeZone(secondsFromGMT: 0)
                f.dateFormat = "yyyy-MM-dd HH:mm:ssXXXXX"
                if let d = f.date(from: s) { return d }
            }
            
            do {
                let f = DateFormatter()
                f.locale = Locale(identifier: "en_US_POSIX")
                f.timeZone = TimeZone(secondsFromGMT: 0)
                f.dateFormat = "yyyy-MM-dd"
                if let d = f.date(from: s) { return d }
            }
            
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath,
                      debugDescription: "Invalid ISO/RFC3339 date: \(s)")
            )
        }
        return dec
    }
}

struct ProfileView: View {
    @EnvironmentObject var app: AppState
    @AppStorage("isPremium") private var isPremium: Bool = false
    @AppStorage("backgroundTheme") private var backgroundTheme: String = "mintBlue"
    let userId: UUID?
    private var viewingUserId: UUID? { userId ?? app.userId }
    private var isOwnProfile: Bool { viewingUserId != nil && viewingUserId == app.userId }
    init(userId: UUID? = nil) {
        self.userId = userId
    }
    @State private var counts: ProfileCounts?
    @State private var username: String = ""
    @State private var avatarURL: String?
    @State private var loading = false
    @State private var error: String?
    @State private var banner: Banner?
    @State private var hasUnreadNotifications = false
    @State private var pickedItem: PhotosPickerItem?
    @State private var uploadingAvatar = false
    @State private var monthDate = Date()
    @State private var monthDays: [Date?] = []
    @State private var activity: [Date: Int] = [:]
    @State private var ownActivity: [Date: Int] = [:]
    @State private var participantActivity: [Date: Int] = [:]
    @State private var draftActivity: [Date: Bool] = [:]
    @State private var selectedDay: Date?
    @State private var bio: String? = nil
    @State private var showEditProfile = false
    @State private var bioExpanded = false
    @State private var isFollowing: Bool? = nil
    @State private var mutatingFollow = false
    @State private var progressRange: ProgressRange = .week
    @State private var progressMetric: ProgressMetric = .workouts
    @State private var progressPoints: [ProgressPoint] = []
    @State private var progressLoading = false
    @State private var progressError: String?
    @State private var myLevel: Int = 1
    @State private var myXP: Int64 = 0
    @State private var nextLevelXP: Int64 = 120
    private enum ProgressSubtab: CaseIterable { case activity, intensity, consistency }
    @State private var progressSubtab: ProgressSubtab = .activity
    @State private var kindDistribution: [KindSlice] = []
    @State private var totalDurationMin: Int = 0
    @State private var email: String? = nil
    @State private var editingProfile = false
    @State private var heightCm: String = ""
    @State private var weightKg: String = ""
    @State private var birthDate: Date = Date()
    @State private var hasBirthDate: Bool = false
    @State private var showAvatarPreview = false
    @State private var showDeleteConfirm = false
    @State private var deletingAccount = false
    @State private var premiumProduct: Product?
    @State private var isPurchasingPremium = false
    @State private var premiumError: String?
    private let premiumProductID = "com.liftr.premium.monthly"
    private let privacyPolicyURL = URL(string: "https://lilru-tech.github.io/liftr-legal/privacy.html")!
    private let termsOfUseURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    
    enum Tab: String { case calendar = "Calendar", prs = "PRs", progress = "Progress", settings = "Settings" }
    @State private var tab: Tab = .calendar
    
    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 12) {
                headerCard
                
                Picker("", selection: $tab) {
                    Text("Calendar").tag(Tab.calendar)
                    Text("PRs").tag(Tab.prs)
                    Text("Progress").tag(Tab.progress)
                    if isOwnProfile {
                        Text("Settings").tag(Tab.settings)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                
                switch tab {
                case .calendar: calendarView
                case .prs: prsView
                case .progress: progressView
                case .settings: settingsView
                }
            }
            
            if !isPremium {
                BannerAdView(adUnitID: "ca-app-pub-7676731162362384/7781347704")
                    .frame(height: 50)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }
        }
        .foregroundStyle(.primary)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .banner($banner)
        .task {
            let session = try? await SupabaseManager.shared.client.auth.session
            print("[Auth] user.id:", session?.user.id.uuidString ?? "nil")
            await loadProfileHeader()
            await refreshFollowState()
            await loadProgress()
            await loadUserLevel()
            await loadUnreadNotifications()
            if isOwnProfile {
                await loadPremiumProduct()
            }
        }
        .onChange(of: app.userId) { _, _ in
            Task {
                await loadProfileHeader()
                await refreshFollowState()
                await loadProgress()
                await loadUnreadNotifications()
                if isOwnProfile {
                    await loadPremiumProduct()
                }
            }
        }
        .onChange(of: monthDate) { _, newDate in
            monthDays = monthDaysGrid(for: newDate)
            selectedDay = nil
            Task { await loadMonthActivity() }
        }
        .onChange(of: progressRange) { _, _ in Task { await loadProgress() } }
        .onChange(of: progressMetric) { _, _ in Task { await loadProgress() } }
        .onChange(of: progressSubtab) { _, _ in Task { await loadProgress() } }
        .sheet(isPresented: $showEditProfile) {
            if isOwnProfile {
                EditBioSheet(
                    initialBio: bio ?? "",
                    onSaved: { newBio in
                        self.bio = newBio.isEmpty ? nil : newBio
                    }
                )
                .gradientBG()
                .presentationDetents([.fraction(0.30)])
                .presentationDragIndicator(.visible)
            }
        }
        .fullScreenCover(isPresented: $showAvatarPreview) {
            if !isOwnProfile {
                AvatarZoomPreview(urlString: avatarURL)
            }
        }
    }
    
    private var prsView: some View {
        PRsListView(
            userId: viewingUserId,
            viewedUsername: username,
            enableCompareWithMe: !isOwnProfile
        )
    }
    
    private var progressView: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Picker("Range", selection: $progressRange) {
                    Text("Week").tag(ProgressRange.week)
                    Text("Month").tag(ProgressRange.month)
                    Text("Year").tag(ProgressRange.year)
                }
                .pickerStyle(.segmented)
                
                Picker("View", selection: $progressSubtab) {
                    Text("Activity").tag(ProgressSubtab.activity)
                    Text("Intensity").tag(ProgressSubtab.intensity)
                    Text("Consistency").tag(ProgressSubtab.consistency)
                }
                .pickerStyle(.segmented)
            }
            .padding(.horizontal)
            if progressSubtab == .activity {
                HStack {
                    Picker("Metric", selection: $progressMetric) {
                        Text("Workouts").tag(ProgressMetric.workouts)
                        Text("Score").tag(ProgressMetric.score)
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.horizontal)
            }
            
            if progressLoading {
                ProgressView().padding()
            } else if let err = progressError {
                Text(err).foregroundStyle(.red).padding(.horizontal)
            } else if progressSubtab == .consistency {
                if kindDistribution.isEmpty && totalDurationMin == 0 {
                    Text("No data for this period").foregroundStyle(.secondary).padding(.horizontal)
                } else {
                    VStack(spacing: 12) {
                        if #available(iOS 17.0, *) {
                            Chart(kindDistribution) { s in
                                SectorMark(
                                    angle: .value("Count", s.count),
                                    innerRadius: .ratio(0.55),
                                    angularInset: 1.5
                                )
                                .foregroundStyle(by: .value("Kind", s.kind.capitalized))
                            }
                            .frame(height: 220)
                            .padding(.horizontal)
                            .chartLegend(.visible)
                            .chartPlotStyle { plotArea in
                                plotArea
                                    .background(Color.gray.opacity(0.18))
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                        } else {
                            Chart(kindDistribution) { s in
                                BarMark(
                                    x: .value("Kind", s.kind.capitalized),
                                    y: .value("Workouts", s.count)
                                )
                            }
                            .frame(height: 220)
                            .padding(.horizontal)
                            .chartPlotStyle { plotArea in
                                plotArea
                                    .background(Color.gray.opacity(0.18))
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                        }
                        
                        Text("Total duration: \(formatMinutes(totalDurationMin))")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                    }
                }
                
            } else if progressPoints.isEmpty {
                Text("No data for this period").foregroundStyle(.secondary).padding(.horizontal)
                
            } else {
                let maxY = progressPoints.map { $0.value }.max() ?? 0
                let yUpper = max(1, maxY * 1.15)
                let yLower = -yUpper * 0.05
                
                Chart(progressPoints) { p in
                    LineMark(
                        x: .value("Period", p.label),
                        y: .value("Value", p.value)
                    )
                    .interpolationMethod(.catmullRom)
                    
                    PointMark(
                        x: .value("Period", p.label),
                        y: .value("Value", p.value)
                    )
                }
                .chartPlotStyle { plotArea in
                    plotArea
                        .background(Color.gray.opacity(0.18))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .chartYAxisLabel(
                    progressSubtab == .activity
                    ? (progressMetric == .workouts ? "Workouts" : "Score")
                    : "Avg score"
                )
                .chartYScale(domain: yLower...yUpper)
                .frame(height: 240)
                .padding(.horizontal)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
    
    
    private enum ProgressRange: CaseIterable { case week, month, year }
    
    private enum ProgressMetric: CaseIterable { case workouts, score }
    
    private struct ProgressPoint: Identifiable {
        let id = UUID()
        let date: Date
        let label: String
        let value: Double
    }
    
    private struct KindSlice: Identifiable {
        let id = UUID()
        let kind: String
        let count: Int
    }
    
    private var headerCard: some View {
        HStack(alignment: .top, spacing: 16) {
            if isOwnProfile {
                PhotosPicker(selection: $pickedItem, matching: .images) {
                    ZStack {
                        AvatarView(urlString: avatarURL)
                            .frame(width: 64, height: 64)
                            .overlay(
                                Group { if uploadingAvatar { ProgressView().scaleEffect(0.8) } },
                                alignment: .bottomTrailing
                            )
                    }
                }
                .onChange(of: pickedItem) { _, newItem in
                    Task { await handlePickedItem(newItem) }
                }
            } else {
                AvatarView(urlString: avatarURL)
                    .frame(width: 64, height: 64)
                    .contentShape(Rectangle())
                    .onTapGesture { if avatarURL != nil { showAvatarPreview = true } }
                    .accessibilityHint("Tap to preview")
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text("@\(username.isEmpty ? "user" : username)")
                    .font(.title3).fontWeight(.semibold)
                HStack(spacing: 8) {
                    NavigationLink {
                        if let uid = viewingUserId {
                            FollowersListView(userId: uid, mode: .followers).gradientBG()
                        }
                    } label: {
                        Label("\(counts?.followers ?? 0)", systemImage: "person.2.fill")
                            .labelStyle(.titleAndIcon)
                            .font(.caption.weight(.semibold))
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                            .background(Capsule().fill(Color.white.opacity(0.12)))
                            .overlay(Capsule().stroke(Color.white.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                    
                    NavigationLink {
                        if let uid = viewingUserId {
                            FollowersListView(userId: uid, mode: .following).gradientBG()
                        }
                    } label: {
                        Label("\(counts?.following ?? 0)", systemImage: "arrowshape.turn.up.right.fill")
                            .labelStyle(.titleAndIcon)
                            .font(.caption.weight(.semibold))
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                            .background(Capsule().fill(Color.white.opacity(0.12)))
                            .overlay(Capsule().stroke(Color.white.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                }
                .foregroundStyle(.secondary)
                
                HStack(spacing: 8) {
                    Text("LV \(myLevel)")
                        .font(.caption.weight(.black))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .layoutPriority(2)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(Capsule().fill(Color.yellow.opacity(0.25)))
                        .overlay(Capsule().stroke(Color.white.opacity(0.18)))
                    
                    Text("\(formatXP(myXP)) XP")
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .layoutPriority(1)
                        .foregroundStyle(.secondary)
                    
                    Spacer(minLength: 8)
                    
                    NavigationLink {
                        RankingView()
                            .navigationTitle("Level Ranking")
                    } label: {
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 6) {
                                Image(systemName: "trophy")
                                Text("Ranking")
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                            Image(systemName: "trophy")
                        }
                        .font(.caption.weight(.semibold))
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(Capsule().fill(Color.white.opacity(0.12)))
                        .overlay(Capsule().stroke(Color.white.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                }
                
                GeometryReader { geo in
                    let total = max(1, Double(self.nextLevelXP))
                    let ratio = Double(self.myXP) / total
                    let prog = min(1.0, max(0.0, ratio))
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.12))
                        Capsule().fill(Color.green.opacity(0.35))
                            .frame(width: geo.size.width * prog)
                            .animation(.easeInOut(duration: 0.35), value: prog)
                    }
                }
                .frame(height: 6)
                .clipped()
                
                if let bio, !bio.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(bio)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(bioExpanded ? nil : 2)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                            .animation(.easeInOut, value: bioExpanded)
                        
                        HStack(spacing: 14) {
                            Button(bioExpanded ? "Show less" : "Read more") {
                                bioExpanded.toggle()
                            }
                            .font(.caption)
                            .buttonStyle(.plain)
                            
                            if isOwnProfile {
                                Button {
                                    showEditProfile = true
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                        .labelStyle(.titleAndIcon)
                                        .font(.caption)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Edit bio")
                            }
                        }
                        .foregroundStyle(.secondary)
                    }
                } else {
                    if isOwnProfile {
                        Button {
                            showEditProfile = true
                        } label: {
                            Label("Add bio", systemImage: "pencil")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 8) {
                HStack(spacing: 8) {
                    NavigationLink {
                        NotificationsListView()
                            .gradientBG()
                    } label: {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "bell.fill")
                                .font(.subheadline.weight(.bold))
                                .padding(8)
                                .background(.thinMaterial, in: Circle())
                            
                            if hasUnreadNotifications {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 10, height: 10)
                                    .offset(x: 4, y: -4)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    
                    NavigationLink {
                        AchievementsGridView(userId: viewingUserId, viewedUsername: username)
                            .gradientBG()
                    } label: {
                        Image(systemName: "trophy.fill")
                            .font(.subheadline.weight(.bold))
                            .padding(8)
                            .background(.thinMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                }
                
                if !isOwnProfile {
                    followButton
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.18), lineWidth: 0.8)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .compositingGroup()
        .padding(.horizontal)
    }
    
    private var calendarView: some View {
        VStack(spacing: 12) {
            HStack {
                Button {
                    monthDate = Calendar.current.date(byAdding: .month, value: -1, to: monthDate)!
                } label: { Image(systemName: "chevron.left") }
                
                Spacer()
                Text(monthTitle(for: monthDate)).font(.headline)
                Spacer()
                
                Button {
                    monthDate = Calendar.current.date(byAdding: .month, value: 1, to: monthDate)!
                } label: { Image(systemName: "chevron.right") }
            }
            .padding(.horizontal)
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                ForEach(weekdays(), id: \.self) { w in
                    Text(w).font(.caption2).foregroundStyle(.secondary)
                }
                ForEach(monthDays.indices, id: \.self) { idx in
                    let day = monthDays[idx]
                    
                    Button {
                        if let day { selectedDay = day }
                    } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill({
                                    if let day {
                                        let key = day.startOfDay
                                        let own = ownActivity[key] ?? 0
                                        let part = participantActivity[key] ?? 0
                                        let total = (activity[key] ?? (own + part))

                                        if total > 0 {
                                            if draftActivity[key] == true {
                                                return Color(red: 0.6, green: 0.1, blue: 0.2)
                                                    .opacity(min(0.20 + Double(total) * 0.05, 0.45))
                                            }

                                            if own > 0 {
                                                return Color.green
                                                    .opacity(min(0.15 + Double(total) * 0.1, 0.35))
                                            }

                                            return Color.yellow
                                                .opacity(min(0.15 + Double(total) * 0.1, 0.35))
                                        }
                                    }
                                    return Color.clear
                                }())
                            
                            if let day {
                                Text("\(Calendar.current.component(.day, from: day))").font(.footnote)
                            } else {
                                Text("")
                            }
                        }
                        .frame(height: 36)
                    }
                    .buttonStyle(.plain)
                    .disabled(day == nil)
                }
            }
            .padding(.horizontal)
            
            if let selectedDay, let uid = viewingUserId {
                DayWorkoutsList(userId: uid, selectedDay: selectedDay)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                Text("Select a day to see your workouts")
                    .font(.subheadline).foregroundStyle(.secondary).padding(.top, 6)
            }
        }
        .task { await prepareMonthAndLoad() }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
    
    private struct PRRow: Decodable, Identifiable {
        let kind: String
        let user_id: UUID
        let label: String
        let metric: String
        let value: Double
        let achieved_at: Date
        
        var id: String { "\(kind)|\(label)|\(metric)|\(achieved_at.timeIntervalSince1970)" }
    }
    
    private struct PRsListView: View {
        @EnvironmentObject var app: AppState
        let userId: UUID?
        let viewedUsername: String
        let enableCompareWithMe: Bool
        
        enum KindFilter: String, CaseIterable { case all = "All", strength = "Strength", cardio = "Cardio", sport = "Sport" }
        @State private var filter: KindFilter = .all
        @State private var search: String = ""
        @State private var showSearch = false
        @State private var prs: [PRRow] = []
        @State private var loading = false
        @State private var error: String?
        
        private var sections: [(title: String, items: [PRRow])] {
            grouped(by: Self.sectionTitle)
        }
        
        var body: some View {
            VStack(spacing: 10) {
                HStack {
                    Picker("Kind", selection: $filter) {
                        ForEach(KindFilter.allCases, id: \.self) { kind in
                            Text(kind.rawValue).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.horizontal)

                if showSearch {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                        TextField("Search PRs", text: $search)
                            .textFieldStyle(.roundedBorder)
                        if !search.isEmpty {
                            Button { search = "" } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                
                List {
                    if loading { ProgressView().frame(maxWidth: .infinity) }
                    
                    ForEach(Array(sections.enumerated()), id: \.element.title) { index, section in
                        HStack {
                            Text(section.title)
                                .font(.headline)
                                .textCase(nil)
                            Spacer()
                            if index == 0 {
                                Button {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.88)) {
                                        showSearch.toggle()
                                    }
                                } label: {
                                    Image(systemName: showSearch ? "magnifyingglass.circle.fill" : "magnifyingglass")
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Toggle search")
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .listRowInsets(EdgeInsets(top: 18, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color.clear)
                        
                        ForEach(section.items, id: \.id) { pr in
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(pr.label).font(.body.weight(.semibold))
                                    Text(prettyMetricName(pr.metric, kind: pr.kind))
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(formatValue(pr))
                                        .font(.title3.weight(.bold))
                                        .monospacedDigit()
                                    Text(dateOnly(pr.achieved_at))
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 10)
                            .padding(.horizontal, 12)
                            .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.12)))
                            .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                            .listRowBackground(Color.clear)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listSectionSeparator(.hidden)
                .background(Color.clear)
            }
            .toolbar {
                if enableCompareWithMe, let myId = app.userId, let otherId = userId {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink {
                            ComparePRsView(myUserId: myId, otherUserId: otherId, otherUsername: viewedUsername)
                        } label: {
                            Label("Compare", systemImage: "arrow.left.and.right.circle")
                        }
                    }
                }
            }
            .task { await load() }
            .onChange(of: filter) { _, _ in Task { await load() } }
            .onAppear { UITableView.appearance().backgroundColor = .clear }
            .onDisappear { UITableView.appearance().backgroundColor = nil }
        }
        
        private func load() async {
            let effective = userId ?? app.userId
            guard let uid = effective else { return }
            loading = true; defer { loading = false }
            
            do {
                var query: PostgrestFilterBuilder = SupabaseManager.shared.client
                    .from("vw_user_prs")
                    .select("*")
                    .eq("user_id", value: uid.uuidString)
                
                if filter != .all {
                    query = query.eq("kind", value: filter.rawValue.lowercased())
                }
                
                let res = try await query
                    .order("achieved_at", ascending: false)
                    .execute()
                let rows = try JSONDecoder.supabase().decode([PRRow].self, from: res.data)
                await MainActor.run { prs = rows }
            } catch {
                await MainActor.run { self.error = error.localizedDescription }
            }
        }
        
        private static func sectionTitle(_ pr: PRRow) -> String {
            let kind = pr.kind.capitalized
            let label = pr.label.capitalized
            return "\(kind) · \(label)"
        }
        
        private func grouped(by key: (PRRow) -> String) -> [(title: String, items: [PRRow])] {
            let dict = Dictionary(grouping: filtered(prs), by: key)
            func orderTuple(_ title: String) -> (Int, String) {
                let lower = title.lowercased()
                if lower.hasPrefix("strength") { return (0, lower) }
                if lower.hasPrefix("cardio")   { return (1, lower) }
                if lower.hasPrefix("sport")    { return (2, lower) }
                return (3, lower)
            }

            let sortedKeys = dict.keys.sorted { a, b in
                let oa = orderTuple(a), ob = orderTuple(b)
                return oa.0 == ob.0 ? oa.1 < ob.1 : oa.0 < ob.0
            }
            return sortedKeys.map { key in
                let items = (dict[key] ?? []).sorted { $0.achieved_at > $1.achieved_at }
                return (title: key, items: items)
            }
        }
        
        private func filtered(_ items: [PRRow]) -> [PRRow] {
            guard !search.isEmpty else { return items }
            return items.filter { $0.label.localizedCaseInsensitiveContains(search) || $0.metric.localizedCaseInsensitiveContains(search) }
        }
        
        private func prettyMetricName(_ metric: String, kind: String) -> String {
            let m = metric.lowercased()
            if m == "max_hr" { return "Max HR" }
            if m == "longest_duration_sec" { return "Longest duration" }
            if m == "longest_distance_km" { return "Longest distance" }
            if m == "fastest_pace_sec_per_km" { return "Fastest pace" }
            if m == "max_elevation_m" { return "Max elevation" }
            if m == "est_1rm_kg" { return "Estimated 1RM" }
            if m == "max_weight_kg" { return "Max weight" }
            if m == "best_set_volume_kg" { return "Best set volume" }
            if m == "max_reps" { return "Max reps" }
            return snakeToTitle(m)
        }
        
        private func formatValue(_ pr: PRRow) -> String {
            let m = pr.metric.lowercased()
            let v = pr.value
            
            if m.hasSuffix("_kg") || m == "est_1rm_kg" || m == "max_weight_kg" || m == "best_set_volume_kg" {
                return String(format: "%.1f kg", v)
            }
            if m.contains("reps") {
                return "\(Int(v.rounded())) reps"
            }
            if m == "max_hr" {
                return "\(Int(v.rounded())) bpm"
            }
            if m == "longest_distance_km" {
                return String(format: "%.1f km", v)
            }
            if m == "max_elevation_m" {
                return "\(Int(v.rounded())) m"
            }
            if m == "fastest_pace_sec_per_km" {
                return paceString(fromSeconds: v)
            }
            if m.hasSuffix("_sec") || m.contains("duration") {
                return durationString(fromSeconds: v)
            }
            return String(format: "%.2f", v)
        }
        
        private func durationString(fromSeconds secondsDouble: Double) -> String {
            let s = max(0, Int(secondsDouble.rounded()))
            let h = s / 3600
            let m = (s % 3600) / 60
            let sec = s % 60
            if h > 0 { return String(format: "%d:%02d:%02d", h, m, sec) }
            return String(format: "%d:%02d", m, sec)
        }
        
        private func paceString(fromSeconds secondsDouble: Double) -> String {
            let s = max(1, Int(secondsDouble.rounded()))
            let m = s / 60
            let sec = s % 60
            return String(format: "%d:%02d /km", m, sec)
        }
        
        private func snakeToTitle(_ s: String) -> String {
            s.replacingOccurrences(of: "_", with: " ")
                .capitalized
        }
        
        private func dateOnly(_ d: Date) -> String {
            let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .none
            return f.string(from: d)
        }
    }
    @Environment(\.openURL) private var openURL
    private var settingsView: some View {
        List {
            Section("Premium") {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(.white.opacity(0.18))
                        )
                    
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            Image(systemName: "star.circle.fill")
                            Text(isPremium ? "You are Premium" : "Remove ads")
                                .font(.body.weight(.semibold))
                            Spacer()
                        }
                        
                        if let product = premiumProduct, !isPremium {
                            Text("Subscribe for \(product.displayPrice) per month to remove ads.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else if isPremium {
                            Text("Ads are disabled on this account.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        
                        if !isPremium {
                            Button {
                                Task { await purchasePremium() }
                            } label: {
                                HStack {
                                    if isPurchasingPremium {
                                        ProgressView()
                                            .controlSize(.small)
                                    }
                                    Text("Continue")
                                        .font(.body.weight(.semibold))
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isPurchasingPremium || premiumProduct == nil)
                            
                            Button {
                                Task { await restorePremium() }
                            } label: {
                                Text("Restore purchases")
                                    .font(.footnote.weight(.semibold))
                            }
                            .buttonStyle(.plain)
                        }
                        
                        Divider().opacity(0.15)

                        VStack(alignment: .leading, spacing: 8) {
                            if let product = premiumProduct {
                                Text("Subscription: \(product.displayName) (\(product.displayPrice) / month). Auto-renewable. Cancel anytime in your Apple ID settings.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Subscription is auto-renewable. Cancel anytime in your Apple ID settings.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            VStack(alignment: .leading, spacing: 10) {
                                Button {
                                    openURL(privacyPolicyURL)
                                } label: {
                                    Text("Privacy Policy")
                                        .font(.caption.weight(.semibold))
                                }
                                .buttonStyle(.plain)

                                Button {
                                    openURL(termsOfUseURL)
                                } label: {
                                    Text("OPEN APPLE EULA")
                                        .font(.caption.weight(.semibold))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        
                        if let msg = premiumError {
                            Text(msg)
                                .font(.footnote)
                                .foregroundColor(.red)
                        }
                    }
                    .padding(12)
                }
                .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                .listRowBackground(Color.clear)
            }
            Section("Account") {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(.white.opacity(0.18))
                        )
                    
                    HStack(spacing: 10) {
                        Text("Email")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(email ?? "–")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .padding(12)
                }
                .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                .listRowBackground(Color.clear)
            }
            Section("Appearance") {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(.white.opacity(0.18))
                        )
                    
                    HStack(spacing: 10) {
                        Text("Background")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Picker("", selection: $backgroundTheme) {
                            Text("Default").tag("mintBlue")
                            Text("Sunset").tag("sunset")
                            Text("Forest").tag("forest")
                            Text("Midnight").tag("midnight")
                        }
                        .pickerStyle(.menu)
                        .font(.footnote)
                    }
                    .padding(12)
                }
                .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                .listRowBackground(Color.clear)
            }
            Section("Support") {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(.white.opacity(0.18))
                        )

                    NavigationLink {
                        ContactSupportForm()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "envelope")
                            Text("Contact support")
                                .font(.body.weight(.semibold))
                            Spacer()
                        }
                        .padding(12)
                    }
                    .buttonStyle(.plain)
                }
                .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                .listRowBackground(Color.clear)
            }
            Section("Feedback") {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(.white.opacity(0.18))
                        )

                    NavigationLink {
                        FeatureRequestsListView()
                            .gradientBG()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "lightbulb")
                            Text("Feature requests")
                                .font(.body.weight(.semibold))
                            Spacer()
                        }
                        .padding(12)
                    }
                    .buttonStyle(.plain)
                }
                .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                .listRowBackground(Color.clear)
            }
            Section("FAQs") {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(.white.opacity(0.18))
                        )

                    NavigationLink {
                        FAQsView()
                            .gradientBG()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "questionmark.circle")
                            Text("See frequently asked questions")
                                .font(.body.weight(.semibold))
                            Spacer()
                        }
                        .padding(12)
                    }
                    .buttonStyle(.plain)
                }
                .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                .listRowBackground(Color.clear)
            }
            Section("Personal information") {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(.white.opacity(0.18))
                        )
                    
                    VStack(spacing: 10) {
                        HStack {
                            Spacer()
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) { editingProfile.toggle() }
                            } label: {
                                Image(systemName: editingProfile ? "checkmark.circle.fill" : "pencil")
                                    .font(.subheadline.weight(.semibold))
                                    .padding(6)
                                    .background(.thinMaterial, in: Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(editingProfile ? "Done" : "Edit")
                        }
                        
                        Divider().opacity(0.15)
                        HStack {
                            Text("Height (cm)")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            if editingProfile {
                                TextField("—", text: $heightCm)
                                    .keyboardType(.numberPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(maxWidth: 120)
                            } else {
                                Text(heightCm.isEmpty ? "–" : "\(heightCm) cm")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        Divider().opacity(0.15)
                        HStack {
                            Text("Weight (kg)")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            if editingProfile {
                                TextField("—", text: $weightKg)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(maxWidth: 120)
                            } else {
                                Text(weightKg.isEmpty ? "–" : "\(weightKg)")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        Divider().opacity(0.15)
                        if editingProfile {
                            HStack {
                                Text("Birth date")
                                Spacer()
                                DatePicker("", selection: $birthDate, displayedComponents: .date)
                                    .labelsHidden()
                            }
                        }
                        
                        HStack {
                            Text("Age")
                            Spacer()
                            Text(ageYears.map(String.init) ?? "—")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        if editingProfile {
                            Divider().opacity(0.15)
                            Button {
                                Task { await saveProfileMetrics() }
                            } label: {
                                HStack {
                                    Spacer()
                                    Text("Save changes").font(.body.weight(.semibold))
                                    Spacer()
                                }
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    .padding(12)
                }
                .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                .listRowBackground(Color.clear)
            }
            
            Section {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(.white.opacity(0.18))
                        )

                    Button(role: .destructive) { showDeleteConfirm = true } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "trash")
                            Text(deletingAccount ? "Deleting…" : "Delete account")
                                .font(.body.weight(.semibold))
                            Spacer()
                        }
                        .padding(12)
                        .foregroundColor(deletingAccount ? .secondary : .red)                    }
                    .disabled(deletingAccount)
                    .buttonStyle(.plain)
                }
                .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                .listRowBackground(Color.clear)
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(.white.opacity(0.18))
                        )
                    
                    Button(role: .destructive) { app.signOut() } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                            Text("Sign out")
                                .font(.body.weight(.semibold))
                            Spacer()
                        }
                        .padding(12)
                    }
                    .buttonStyle(.plain)
                }
                .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .listRowSeparator(.hidden)
        .listSectionSeparator(.hidden)
        .background(Color.clear)
        .alert("Delete account?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                showDeleteConfirm = false
                Task { await performDeleteAccount() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete your account and data. This action cannot be undone.")
        }
    }
    
    private var ageYears: Int? {
        guard hasBirthDate else { return nil }
        let cal = Calendar.current
        let now = Date()
        return cal.dateComponents([.year], from: birthDate, to: now).year
    }
    
    private func saveProfileMetrics() async {
        guard let uid = app.userId else { return }
        struct ProfileMetricsUpdate: Encodable {
            let height_cm: Int?
            let weight_kg: Double?
            let date_of_birth: String?
        }
        do {
            let hText = heightCm.trimmingCharacters(in: .whitespacesAndNewlines)
            let height = Int(hText).flatMap { $0 > 0 ? $0 : nil }

            let wText = weightKg
                .replacingOccurrences(of: ",", with: ".")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let weight = Double(wText).flatMap { $0 > 0 ? $0 : nil }
            
            let df = DateFormatter()
            df.timeZone = .current
            df.dateFormat = "yyyy-MM-dd"
            let birth = df.string(from: birthDate)
            
            let update = ProfileMetricsUpdate(height_cm: height, weight_kg: weight, date_of_birth: birth)
            guard update.height_cm != nil || update.weight_kg != nil || update.date_of_birth != nil else { return }
            
            _ = try await SupabaseManager.shared.client
                .from("profiles")
                .update(update)
                .eq("user_id", value: uid.uuidString)
                .execute()
            await loadProfileHeader()
            await MainActor.run { editingProfile = false }
            BannerAction.showSuccess("Profile updated! ✅", banner: $banner)
        } catch {
            await MainActor.run { self.error = error.localizedDescription }
        }
    }
    
    private func performDeleteAccount() async {
        guard !deletingAccount else { return }
        await MainActor.run { deletingAccount = true; error = nil }
        defer { Task { await MainActor.run { deletingAccount = false } } }
        do {
            _ = try await SupabaseManager.shared.client
                .rpc("delete_my_account")
                .execute()
        } catch {
            print("[Delete] public RPC error:", error.localizedDescription)
        }

        do {
            _ = try await SupabaseManager.shared.client.functions
                .invoke("delete-auth-user")
            await MainActor.run {
                BannerAction.showSuccess("Account deleted. Goodbye 👋", banner: $banner)
                app.signOut()
            }
        } catch {
            await MainActor.run {
                self.error = "We removed your app data, but couldn't remove the Auth user. Contact support."
                app.signOut()
            }
        }
    }
    
    private func loadUnreadNotifications() async {
        if !isOwnProfile {
            await MainActor.run { hasUnreadNotifications = false }
            return
        }
        guard let uid = app.userId else {
            await MainActor.run { hasUnreadNotifications = false }
            return
        }
        
        struct NId: Decodable { let id: Int }
        
        do {
            let res = try await SupabaseManager.shared.client
                .from("notifications")
                .select("id")
                .eq("user_id", value: uid.uuidString)
                .eq("is_read", value: false)
                .limit(1)
                .execute()
            
            let rows = try JSONDecoder.supabase().decode([NId].self, from: res.data)
            await MainActor.run {
                self.hasUnreadNotifications = !rows.isEmpty
            }
        } catch {
            await MainActor.run {
                self.hasUnreadNotifications = false
            }
        }
    }
    
    private func loadProfileHeader() async {
        guard let uid = viewingUserId else { return }
        loading = true; defer { loading = false }
        
        do {
            let res1 = try await SupabaseManager.shared.client
                .from("profiles")
                .select("user_id,username,avatar_url,bio,height_cm,weight_kg,birth_date:date_of_birth")
                .eq("user_id", value: uid)
                .single()
                .execute()
            
            let profile = try JSONDecoder.supabase().decode(ProfileRow.self, from: res1.data)
            username = profile.username
            avatarURL = profile.avatar_url
            bio = profile.bio
            
            if let session = try? await SupabaseManager.shared.client.auth.session {
                self.email = session.user.email
            }
            self.heightCm = profile.height_cm.map { "\($0)" } ?? ""
            self.weightKg = profile.weight_kg.map { String(format: "%.1f", $0) } ?? ""
            self.hasBirthDate = profile.birth_date != nil
            self.birthDate = profile.birth_date ?? Date()
            let res2 = try await SupabaseManager.shared.client
                .from("vw_profile_counts")
                .select()
                .eq("user_id", value: uid.uuidString)
                .execute()
            
            let rows = try JSONDecoder.supabase().decode([ProfileCounts].self, from: res2.data)
            counts = rows.first ?? ProfileCounts(user_id: uid, followers: 0, following: 0)
        } catch {
            self.error = error.localizedDescription
        }
    }
    
    private func prepareMonthAndLoad() async {
        monthDays = monthDaysGrid(for: monthDate)
        await loadMonthActivity()
    }
    
    private func loadMonthActivity() async {
        guard let uid = viewingUserId else { return }
        let cal = Calendar.current
        let year = cal.component(.year, from: monthDate)
        let month = cal.component(.month, from: monthDate)
        
        do {
            var cal = Calendar.current
            cal.timeZone = .current
            let monthStart = cal.date(from: DateComponents(year: year, month: month, day: 1))!
            let monthEnd = cal.date(byAdding: .month, value: 1, to: monthStart)!
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            iso.timeZone = .current
            let resOwn = try await SupabaseManager.shared.client
                .from("workouts")
                .select("started_at,state")
                .eq("user_id", value: uid.uuidString)
                .gte("started_at", value: iso.string(from: monthStart))
                .lt("started_at", value: iso.string(from: monthEnd))
                .execute()
            
            let rowsOwn = try JSONDecoder.supabase().decode([OnlyStartedAt].self, from: resOwn.data)
            var dictOwn: [Date: Int] = [:]
            var dictDraft: [Date: Bool] = [:]

            for r in rowsOwn {
                if let d = r.started_at {
                    let key = cal.startOfDay(for: d)
                    dictOwn[key, default: 0] += 1
                    if (r.state ?? "published") == "planned" {
                        dictDraft[key] = true
                    }
                }
            }
            
            let pres = try await SupabaseManager.shared.client
                .from("workout_participants")
                .select("workout_id")
                .eq("user_id", value: uid.uuidString)
                .execute()
            
            struct PId: Decodable { let workout_id: Int }
            let pIds = try JSONDecoder.supabase().decode([PId].self, from: pres.data).map { $0.workout_id }
            
            var dictPart: [Date: Int] = [:]
            if !pIds.isEmpty {
                let resPartW = try await SupabaseManager.shared.client
                    .from("workouts")
                    .select("started_at,state")
                    .in("id", values: pIds)
                    .gte("started_at", value: iso.string(from: monthStart))
                    .lt("started_at", value: iso.string(from: monthEnd))
                    .execute()
                
                let rowsPart = try JSONDecoder.supabase().decode([OnlyStartedAt].self, from: resPartW.data)
                for r in rowsPart {
                    if let d = r.started_at {
                        let key = cal.startOfDay(for: d)
                        dictPart[key, default: 0] += 1
                        if (r.state ?? "published") == "planned" {
                            dictDraft[key] = true
                        }
                    }
                }
            }
            
            var dictTotal: [Date: Int] = dictOwn
            for (k, v) in dictPart { dictTotal[k, default: 0] += v }
            
            await MainActor.run {
                self.ownActivity = dictOwn
                self.participantActivity = dictPart
                self.activity = dictTotal
                self.draftActivity = dictDraft
            }
        } catch {
            await MainActor.run { self.error = error.localizedDescription }
        }
    }
    
    private func loadProgress() async {
        guard let uid = viewingUserId else { return }
        await MainActor.run { progressLoading = true; progressError = nil }
        defer { Task { await MainActor.run { progressLoading = false } } }
        var cal = Calendar.current
        cal.timeZone = .current
        let now = Date()
        let start: Date
        let step: Calendar.Component
        let bucketCount: Int
        
        switch progressRange {
        case .week:
            start = cal.date(byAdding: .day, value: -6, to: now.startOfDay) ?? now.startOfDay
            step = .day
            bucketCount = 7
        case .month:
            start = cal.date(byAdding: .day, value: -29, to: now.startOfDay) ?? now.startOfDay
            step = .day
            bucketCount = 30
        case .year:
            let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now
            start = cal.date(byAdding: .month, value: -11, to: monthStart) ?? monthStart
            step = .month
            bucketCount = 12
        }
        var bucketsCount: [Date: Int] = [:]
        var bucketsScore: [Date: Double] = [:]
        var labels: [Date: String] = [:]
        var cursor = start
        for _ in 0..<bucketCount {
            let key: Date
            let label: String
            switch step {
            case .day:
                key = cal.startOfDay(for: cursor)
                label = DateFormatter.shortDay(cursor)
            case .month:
                key = cal.date(from: cal.dateComponents([.year,.month], from: cursor)) ?? cursor
                label = DateFormatter.shortMonth(cursor)
            default:
                key = cal.startOfDay(for: cursor)
                label = DateFormatter.shortDay(cursor)
            }
            bucketsCount[key] = 0
            bucketsScore[key] = 0
            labels[key] = label
            cursor = cal.date(byAdding: step, value: 1, to: cursor) ?? cursor
        }
        let end: Date
        switch step {
        case .day:
            end = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) ?? now
        case .month:
            end = cal.date(byAdding: .month, value: 1, to: cal.date(from: cal.dateComponents([.year,.month], from: now)) ?? now) ?? now
        default:
            end = now
        }
        
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        iso.timeZone = .current
        
        do {
            let res = try await SupabaseManager.shared.client
                .from("workouts")
                .select("id,started_at,kind,duration_min")
                .eq("user_id", value: uid.uuidString)
                .gte("started_at", value: iso.string(from: start))
                .lt("started_at", value: iso.string(from: end))
                .execute()
            
            struct W: Decodable { let id: Int; let started_at: Date?; let kind: String; let duration_min: Int? }
            let workouts = try JSONDecoder.supabase().decode([W].self, from: res.data)
            let ids = workouts.map { $0.id }
            var scoresByWorkout: [Int: Double] = [:]
            if !ids.isEmpty {
                let sres = try await SupabaseManager.shared.client
                    .from("workout_scores")
                    .select("workout_id,score")
                    .in("workout_id", values: ids)
                    .execute()
                
                struct S: Decodable { let workout_id: Int; let score: Decimal }
                let srows = try JSONDecoder.supabase().decode([S].self, from: sres.data)
                for r in srows {
                    scoresByWorkout[r.workout_id, default: 0] += NSDecimalNumber(decimal: r.score).doubleValue
                }
            }
            var durationMinByWorkout: [Int: Int] = [:]
            for w in workouts {
                if let dm = w.duration_min {
                    durationMinByWorkout[w.id] = max(dm, 0)
                }
            }
            if !ids.isEmpty {
                let cres = try await SupabaseManager.shared.client
                    .from("cardio_sessions")
                    .select("workout_id,duration_sec")
                    .in("workout_id", values: ids)
                    .execute()
                struct CRow: Decodable { let workout_id: Int; let duration_sec: Int? }
                let crows = try JSONDecoder.supabase().decode([CRow].self, from: cres.data)
                for r in crows {
                    if let s = r.duration_sec, durationMinByWorkout[r.workout_id] == nil {
                        durationMinByWorkout[r.workout_id] = max(Int(round(Double(s)/60.0)), 0)
                    }
                }
                let sres2 = try await SupabaseManager.shared.client
                    .from("sport_sessions")
                    .select("workout_id,duration_sec")
                    .in("workout_id", values: ids)
                    .execute()
                struct SRow2: Decodable { let workout_id: Int; let duration_sec: Int? }
                let srows2 = try JSONDecoder.supabase().decode([SRow2].self, from: sres2.data)
                for r in srows2 {
                    if let s = r.duration_sec, durationMinByWorkout[r.workout_id] == nil {
                        durationMinByWorkout[r.workout_id] = max(Int(round(Double(s)/60.0)), 0)
                    }
                }
            }
            var kindCount: [String: Int] = [:]
            var totalMinutes = 0
            
            for w in workouts {
                guard let d = w.started_at else { continue }
                let key: Date
                switch step {
                case .day:
                    key = cal.startOfDay(for: d)
                case .month:
                    key = cal.date(from: cal.dateComponents([.year,.month], from: d)) ?? d
                default:
                    key = cal.startOfDay(for: d)
                }
                guard bucketsCount[key] != nil else { continue }
                bucketsCount[key]! += 1
                bucketsScore[key]! += scoresByWorkout[w.id] ?? 0
                kindCount[w.kind, default: 0] += 1
                totalMinutes += (durationMinByWorkout[w.id] ?? 0)
            }
            if progressSubtab == .activity {
                let ordered = bucketsCount.keys.sorted()
                let points: [ProgressPoint] = ordered.map { k in
                    let val = (progressMetric == .workouts) ? Double(bucketsCount[k] ?? 0) : (bucketsScore[k] ?? 0)
                    return ProgressPoint(date: k, label: labels[k] ?? "", value: val)
                }
                await MainActor.run { self.progressPoints = points }
            }
            if progressSubtab == .intensity {
                let ordered = bucketsCount.keys.sorted()
                let points: [ProgressPoint] = ordered.map { k in
                    let count = max(1, bucketsCount[k] ?? 0)
                    let avg = (bucketsScore[k] ?? 0) / Double(count)
                    return ProgressPoint(date: k, label: labels[k] ?? "", value: avg)
                }
                await MainActor.run { self.progressPoints = points }
            }
            if progressSubtab == .consistency {
                let slices = ["strength","cardio","sport"]
                    .map { KindSlice(kind: $0, count: kindCount[$0] ?? 0) }
                    .filter { $0.count > 0 }
                await MainActor.run {
                    self.kindDistribution = slices
                    self.totalDurationMin = totalMinutes
                    self.progressPoints = []
                }
            }
            
        } catch {
            await MainActor.run { self.progressError = error.localizedDescription }
        }
    }
    
    private func handlePickedItem(_ item: PhotosPickerItem?) async {
        guard isOwnProfile, let item, let uid = app.userId else { return }
        await MainActor.run { uploadingAvatar = true }
        
        func log(_ m: String) { print("[Avatar]", m) }
        
        do {
            log("start")
            
            let data = try await item.loadTransferable(type: Data.self) ?? Data()
            guard let uiImage = UIImage(data: data) else {
                throw NSError(domain: "image", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid image data"])
            }
            
            guard let jpeg = resizedJPEG(from: uiImage, maxSide: 1024, quality: 0.85) else {
                throw NSError(domain: "jpeg", code: -2, userInfo: [NSLocalizedDescriptionKey: "JPEG encode failed"])
            }
            log("jpeg size: \(kbString(jpeg))")
            
            let fileName = "\(uid.uuidString)-\(Int(Date().timeIntervalSince1970)).jpg"
            log("upload → \(fileName)")
            try await SupabaseManager.shared.client.storage
                .from("avatars")
                .upload(fileName, data: jpeg, options: FileOptions(contentType: "image/jpeg", upsert: true))
            
            log("upload ok")
            
            let publicURL = try SupabaseManager.shared.client.storage
                .from("avatars")
                .getPublicURL(path: fileName)
            log("publicURL: \(publicURL.absoluteString)")
            
            let payload: [String: String] = ["avatar_url": publicURL.absoluteString]
            log("update profiles")
            _ = try await SupabaseManager.shared.client
                .from("profiles")
                .update(payload)
                .eq("user_id", value: uid.uuidString)
                .execute()
            log("update ok")
            
            let check = try await SupabaseManager.shared.client
                .from("profiles")
                .select("avatar_url")
                .eq("user_id", value: uid.uuidString)
                .single()
                .execute()
            log("db row: " + (String(data: check.data, encoding: .utf8) ?? "—"))
            
            await MainActor.run {
                self.avatarURL = publicURL.absoluteString
            }
        } catch {
            await MainActor.run { self.error = error.localizedDescription }
            print("[Avatar][ERROR]", error.localizedDescription)
        }
        
        await MainActor.run { uploadingAvatar = false }
    }
    
    private func monthTitle(for date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "LLLL yyyy"; return f.string(from: date).capitalized
    }
    private let WEEK_START = 2
    
    private func weekdays() -> [String] {
        let fmt = DateFormatter()
        fmt.locale = .current
        let symbols = fmt.shortWeekdaySymbols ?? ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"]
        let startIndex = (WEEK_START - 1 + symbols.count) % symbols.count
        let head = Array(symbols[startIndex...])
        let tail = Array(symbols[..<startIndex])
        return head + tail
    }
    
    private func monthDaysGrid(for date: Date) -> [Date?] {
        var cal = Calendar.current
        cal.firstWeekday = WEEK_START
        let range = cal.range(of: .day, in: .month, for: date)!
        let first = cal.date(from: cal.dateComponents([.year, .month], from: date))!
        let weekday = cal.component(.weekday, from: first)
        let leading = ((weekday - WEEK_START) + 7) % 7
        let monthDates: [Date] = range.compactMap { day -> Date? in
            cal.date(byAdding: .day, value: day - 1, to: first)
        }
        
        var grid: [Date?] = Array(repeating: nil, count: leading) + monthDates.map { Optional($0) }
        while grid.count % 7 != 0 { grid.append(nil) }
        return grid
    }
    
    private var followButton: some View {
        Group {
            if isFollowing == nil {
                ProgressView().controlSize(.small)
            } else if isFollowing == true {
                Button {
                    Task { await unfollow() }
                } label: {
                    Text("Unfollow")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else {
                Button {
                    Task { await follow() }
                } label: {
                    Text("Follow")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
    }
    
    private func refreshFollowState() async {
        guard
            let me = app.userId,
            let other = viewingUserId,
            me != other
        else {
            await MainActor.run { isFollowing = nil }
            return
        }
        
        do {
            let res = try await SupabaseManager.shared.client
                .from("follows")
                .select("follower_id")
                .eq("follower_id", value: me.uuidString)
                .eq("followee_id", value: other.uuidString)
                .limit(1)
                .execute()
            
            let rows = try JSONDecoder.supabase().decode([FollowRow].self, from: res.data)
            await MainActor.run { isFollowing = !rows.isEmpty }
        } catch {
            await MainActor.run { isFollowing = false }
        }
    }
    
    private func follow() async {
        guard !mutatingFollow,
              let me = app.userId,
              let other = viewingUserId,
              me != other else { return }

        await MainActor.run { mutatingFollow = true; error = nil }
        defer { Task { await MainActor.run { mutatingFollow = false } } }

        do {
            let payload: [String: String] = [
                "follower_id": me.uuidString,
                "followee_id": other.uuidString
            ]
            _ = try await SupabaseManager.shared.client
                .from("follows")
                .upsert(payload, onConflict: "follower_id,followee_id")
                .execute()

            await refreshFollowState()
            await loadProfileHeader()
        } catch {
            await MainActor.run { self.error = "Follow failed: \(error.localizedDescription)" }
            print("[Follow][ERROR]", error.localizedDescription)
        }
    }
    
    private func unfollow() async {
        guard !mutatingFollow,
              let me = app.userId,
              let other = viewingUserId else { return }

        await MainActor.run { mutatingFollow = true; error = nil }
        defer { Task { await MainActor.run { mutatingFollow = false } } }

        do {
            _ = try await SupabaseManager.shared.client
                .from("follows")
                .delete()
                .eq("follower_id", value: me.uuidString)
                .eq("followee_id", value: other.uuidString)
                .execute()

            await refreshFollowState()
            await loadProfileHeader()
        } catch {
            await MainActor.run { self.error = "Unfollow failed: \(error.localizedDescription)" }
            print("[Unfollow][ERROR]", error.localizedDescription)
        }
    }
    
    private func loadPremiumProduct() async {
        guard premiumProduct == nil else { return }
        await MainActor.run {
            premiumError = nil
        }
        do {
            let bundleID = Bundle.main.bundleIdentifier ?? "nil"
            print("[StoreKit] Requesting product for id:", premiumProductID, "bundle:", bundleID)

            let products = try await Product.products(for: [premiumProductID])

            print("[StoreKit] Received products count:", products.count)
            for p in products {
                print("[StoreKit] Product id:", p.id, "price:", p.displayPrice)
            }

            await MainActor.run {
                self.premiumProduct = products.first
            }
        } catch {
            print("[StoreKit] error:", error)
            await MainActor.run {
                self.premiumError = error.localizedDescription
            }
        }
    }
    
    private func purchasePremium() async {
        guard let product = premiumProduct else { return }
        await MainActor.run {
            isPurchasingPremium = true
            premiumError = nil
        }
        defer {
            Task { await MainActor.run { isPurchasingPremium = false } }
        }
        
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if let transaction = verifiedTransaction(from: verification) {
                    await MainActor.run {
                        self.isPremium = true
                    }
                    await transaction.finish()
                } else {
                    await MainActor.run {
                        self.premiumError = "Purchase verification failed."
                    }
                }
            case .pending:
                break
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            await MainActor.run {
                self.premiumError = error.localizedDescription
            }
        }
    }
    
    private func restorePremium() async {
        await MainActor.run {
            isPurchasingPremium = true
            premiumError = nil
        }
        defer {
            Task { await MainActor.run { isPurchasingPremium = false } }
        }

        var found = false
        for await result in StoreKit.Transaction.currentEntitlements {
            if let transaction = verifiedTransaction(from: result),
               transaction.productID == premiumProductID {
                found = true
                await MainActor.run {
                    self.isPremium = true
                }
                break
            }
        }

        if !found {
            await MainActor.run {
                self.premiumError = "No active subscription found for this Apple ID."
            }
        }
    }
    
    private func verifiedTransaction(from result: StoreKit.VerificationResult<StoreKit.Transaction>) -> StoreKit.Transaction? {
        switch result {
        case .unverified:
            return nil
        case .verified(let transaction):
            return transaction
        }
    }
}

struct AvatarView: View {
    let urlString: String?
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12).fill(.thinMaterial)
            if let urlString, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty: ProgressView()
                    case .success(let img): img.resizable().scaledToFill()
                    case .failure: Image(systemName: "person.fill").resizable().scaledToFit().padding(12)
                    @unknown default: EmptyView()
                    }
                }
            } else {
                Image(systemName: "person.fill").resizable().scaledToFit().padding(12)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct AvatarZoomPreview: View {
    let urlString: String?
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastScale: CGFloat = 1
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            Group {
                if let urlString, let url = URL(string: urlString) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .empty:
                            ProgressView()
                        case .success(let img):
                            img
                                .resizable()
                                .scaledToFit()
                                .scaleEffect(scale)
                                .offset(offset)
                                .gesture(
                                    MagnificationGesture()
                                        .onChanged { value in
                                            scale = clamp(lastScale * value, min: 1, max: 4)
                                        }
                                        .onEnded { _ in
                                            lastScale = scale
                                            if scale <= 1 {
                                                withAnimation(.spring) {
                                                    offset = .zero
                                                    lastOffset = .zero
                                                }
                                            }
                                        }
                                )
                                .simultaneousGesture(
                                    DragGesture()
                                        .onChanged { g in
                                            guard scale > 1 else { return }
                                            offset = CGSize(width: lastOffset.width + g.translation.width,
                                                            height: lastOffset.height + g.translation.height)
                                        }
                                        .onEnded { _ in
                                            lastOffset = offset
                                        }
                                )
                                .onTapGesture(count: 2) {
                                    withAnimation(.spring) {
                                        if scale > 1 {
                                            scale = 1
                                            lastScale = 1
                                            offset = .zero
                                            lastOffset = .zero
                                        } else {
                                            scale = 2
                                            lastScale = 2
                                        }
                                    }
                                }
                        case .failure:
                            Image(systemName: "person.fill")
                                .resizable()
                                .scaledToFit()
                                .foregroundColor(.white.opacity(0.6))
                                .padding(40)
                        @unknown default:
                            EmptyView()
                        }
                    }
                } else {
                    Image(systemName: "person.fill")
                        .resizable()
                        .scaledToFit()
                        .foregroundColor(.white.opacity(0.6))
                        .padding(40)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            .safeAreaInset(edge: .top) {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .padding(12)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
            }
        }
    }

    private func clamp(_ v: CGFloat, min: CGFloat, max: CGFloat) -> CGFloat {
        Swift.min(Swift.max(v, min), max)
    }
}

private struct DayWorkoutsList: View {
    let userId: UUID
    let selectedDay: Date
    @EnvironmentObject var app: AppState
    @State private var workouts: [WorkoutRow] = []
    @State private var scores: [Int: Double] = [:]
    @State private var error: String?
    @State private var participated: [WorkoutRow] = []
    @State private var owners: [UUID: ProfileRow] = [:]
    @State private var workoutParticipants: [Int: [UUID]] = [:]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(dateTitle(selectedDay))
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
            
            if workouts.isEmpty && participated.isEmpty {
                Text("No workouts this day")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            } else {
                GeometryReader { _ in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(workouts) { w in
                                NavigationLink {
                                    WorkoutDetailView(workoutId: w.id, ownerId: w.user_id)
                                } label: {
                                    ZStack {
                                        WorkoutCardBackground(kind: w.kind)
                                            .opacity((w.state ?? "published") == "planned" ? 0.55 : 1.0)

                                        if (w.state ?? "published") == "planned" {
                                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                                .stroke(Color.yellow.opacity(0.7), lineWidth: 2)
                                        }

                                        HStack(alignment: .top, spacing: 12) {
                                            avatarStack(for: w)
                                            
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(w.title ?? w.kind.capitalized)
                                                    .font(.body.weight(.semibold))
                                                    .lineLimit(1)
                                                
                                                if let username = owners[w.user_id]?.username {
                                                    Text(username)
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                }
                                                
                                                Text(timeRange(w))
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                                
                                                HStack(spacing: 6) {
                                                    Text(w.kind.capitalized)
                                                        .font(.caption2.weight(.semibold))
                                                        .padding(.vertical, 3)
                                                        .padding(.horizontal, 6)
                                                        .background(
                                                            Capsule().fill(workoutTint(for: w.kind).opacity(0.12))
                                                        )
                                                        .overlay(
                                                            Capsule().stroke(Color.white.opacity(0.12))
                                                        )
                                                    
                                                    if (w.state ?? "published") == "planned" {
                                                        Text("Draft")
                                                            .font(.caption2.weight(.semibold))
                                                            .padding(.vertical, 3)
                                                            .padding(.horizontal, 6)
                                                            .background(
                                                                Capsule().fill(Color.yellow.opacity(0.20))
                                                            )
                                                            .overlay(
                                                                Capsule().stroke(Color.white.opacity(0.12))
                                                            )
                                                    }
                                                }
                                            }
                                            
                                            Spacer()
                                            
                                            if let sc = scores[w.id] {
                                                scorePill(score: sc, kind: w.kind)
                                                    .accessibilityLabel("Score \(scoreString(sc))")
                                            }
                                        }
                                        .padding(14)
                                    }
                                    .padding(.horizontal)
                                }
                            }
                            if !participated.isEmpty {
                                Divider().opacity(0.15)
                                ForEach(participated) { w in
                                    NavigationLink {
                                        WorkoutDetailView(workoutId: w.id, ownerId: w.user_id)
                                    } label: {
                                        ZStack {
                                            WorkoutCardBackground(kind: w.kind)
                                                .opacity((w.state ?? "published") == "planned" ? 0.55 : 1.0)

                                            if (w.state ?? "published") == "planned" {
                                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                                    .stroke(Color.yellow.opacity(0.7), lineWidth: 2)
                                            }

                                            HStack(alignment: .top, spacing: 12) {
                                                avatarStack(for: w)
                                                
                                                VStack(alignment: .leading, spacing: 4) {
                                                    Text(w.title ?? w.kind.capitalized)
                                                        .font(.body.weight(.semibold))
                                                        .lineLimit(1)
                                                    
                                                    Text(timeRange(w))
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                    
                                                    HStack(spacing: 6) {
                                                        Text(w.kind.capitalized)
                                                            .font(.caption2.weight(.semibold))
                                                            .padding(.vertical, 3)
                                                            .padding(.horizontal, 6)
                                                            .background(
                                                                Capsule().fill(workoutTint(for: w.kind).opacity(0.12))
                                                            )
                                                            .overlay(
                                                                Capsule().stroke(Color.white.opacity(0.12))
                                                            )
                                                        
                                                        Text("Participated")
                                                            .font(.caption2.weight(.semibold))
                                                            .padding(.vertical, 3)
                                                            .padding(.horizontal, 6)
                                                            .background(
                                                                Capsule().fill(Color.yellow.opacity(0.20))
                                                            )
                                                            .overlay(
                                                                Capsule().stroke(Color.white.opacity(0.12))
                                                            )
                                                        
                                                        if (w.state ?? "published") == "planned" {
                                                            Text("Draft")
                                                                .font(.caption2.weight(.semibold))
                                                                .padding(.vertical, 3)
                                                                .padding(.horizontal, 6)
                                                                .background(
                                                                    Capsule().fill(Color.yellow.opacity(0.20))
                                                                )
                                                                .overlay(
                                                                    Capsule().stroke(Color.white.opacity(0.12))
                                                                )
                                                        }
                                                    }
                                                }
                                                
                                                Spacer()
                                                
                                                if let sc = scores[w.id] {
                                                    scorePill(score: sc, kind: w.kind)
                                                        .accessibilityLabel("Score \(scoreString(sc))")
                                                }
                                            }
                                            .padding(14)
                                        }
                                        .padding(.horizontal)
                                    }
                                }
                            }
                        }
                        Color.clear.frame(height: 8)
                    }
                }
            }
        }
        .task(id: selectedDay) { await load() }
        .onChange(of: selectedDay) { _, _ in
            workouts = []
            scores = [:]
            participated = []
        }
    }
    
    private func load() async {
        let uid = userId
        
        var cal = Calendar.current
        cal.timeZone = .current
        let start = cal.startOfDay(for: selectedDay)
        let end = cal.date(byAdding: .day, value: 1, to: start)!
        
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        iso.timeZone = .current
        
        do {
            let resOwn = try await SupabaseManager.shared.client
                .from("workouts")
                .select("*")
                .eq("user_id", value: uid.uuidString)
                .gte("started_at", value: iso.string(from: start))
                .lt("started_at", value: iso.string(from: end))
                .order("started_at", ascending: false)
                .execute()
            let rowsOwn = try JSONDecoder.supabase().decode([WorkoutRow].self, from: resOwn.data)
            let pres = try await SupabaseManager.shared.client
                .from("workout_participants")
                .select("workout_id")
                .eq("user_id", value: uid.uuidString)
                .execute()
            struct PId: Decodable { let workout_id: Int }
            let partIdsAll = try JSONDecoder.supabase().decode([PId].self, from: pres.data).map { $0.workout_id }
            var rowsPart: [WorkoutRow] = []
            if !partIdsAll.isEmpty {
                let resPart = try await SupabaseManager.shared.client
                    .from("workouts")
                    .select("*")
                    .in("id", values: partIdsAll)
                    .gte("started_at", value: iso.string(from: start))
                    .lt("started_at", value: iso.string(from: end))
                    .order("started_at", ascending: false)
                    .execute()
                rowsPart = try JSONDecoder.supabase().decode([WorkoutRow].self, from: resPart.data)
            }
            let allIds = rowsOwn.map { $0.id } + rowsPart.map { $0.id }
            
            var participantsByWorkout: [Int: [UUID]] = [:]
            if !allIds.isEmpty {
                let presAll = try await SupabaseManager.shared.client
                    .from("workout_participants")
                    .select("workout_id,user_id")
                    .in("workout_id", values: allIds)
                    .execute()
                
                struct PRow: Decodable { let workout_id: Int; let user_id: UUID }
                let pRowsAll = try JSONDecoder.supabase().decode([PRow].self, from: presAll.data)
                for row in pRowsAll {
                    participantsByWorkout[row.workout_id, default: []].append(row.user_id)
                }
            }
            
            var scoresDict: [Int: Double] = [:]
            if !allIds.isEmpty {
                let scoreRes = try await SupabaseManager.shared.client
                    .from("workout_scores")
                    .select("workout_id, score")
                    .in("workout_id", values: allIds)
                    .execute()
                
                let scoreRows = try JSONDecoder.supabase().decode([WorkoutScoreRow].self, from: scoreRes.data)
                
                var tmp: [Int: Double] = [:]
                for row in scoreRows {
                    let value = NSDecimalNumber(decimal: row.score).doubleValue
                    tmp[row.workout_id, default: 0] += value
                }
                scoresDict = tmp
            }
            
            let participantUserIds = Set(participantsByWorkout.values.flatMap { $0 })
            var allUsers = Set(rowsOwn.map { $0.user_id } + rowsPart.map { $0.user_id })
            for u in participantUserIds {
                allUsers.insert(u)
            }
            
            var ownerDict: [UUID: ProfileRow] = [:]

            if !allUsers.isEmpty {
                let resProfiles = try await SupabaseManager.shared.client
                    .from("profiles")
                    .select("user_id,username,avatar_url")
                    .in("user_id", values: allUsers.map { $0.uuidString })
                    .execute()
                
                let profRows = try JSONDecoder.supabase().decode([ProfileRow].self, from: resProfiles.data)
                for p in profRows {
                    ownerDict[p.user_id] = p
                }
            }
            
            await MainActor.run {
                workouts = rowsOwn
                participated = rowsPart
                scores = scoresDict
                owners = ownerDict
                workoutParticipants = participantsByWorkout
            }
        } catch {
            await MainActor.run { self.error = error.localizedDescription }
        }
    }
    
    private func avatarURLs(for workout: WorkoutRow) -> (String?, String?) {
        let ownerAvatar = owners[workout.user_id]?.avatar_url
        let participants = workoutParticipants[workout.id] ?? []
        
        guard let meId = app.userId else {
            return (ownerAvatar, nil)
        }
        
        if workout.user_id == meId {
            if let otherId = participants.first(where: { $0 != meId }),
               let otherAvatar = owners[otherId]?.avatar_url {
                return (ownerAvatar, otherAvatar)
            } else {
                return (ownerAvatar, nil)
            }
        } else {
            if participants.contains(meId),
               let myAvatar = owners[meId]?.avatar_url {
                return (ownerAvatar, myAvatar)
            } else if let first = participants.first,
                      let firstAvatar = owners[first]?.avatar_url {
                return (ownerAvatar, firstAvatar)
            } else {
                return (ownerAvatar, nil)
            }
        }
    }
    
    @ViewBuilder
    private func avatarStack(for workout: WorkoutRow) -> some View {
        let (primary, secondary) = avatarURLs(for: workout)
        ZStack(alignment: .bottomTrailing) {
            AvatarView(urlString: primary)
                .frame(width: 42, height: 42)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            
            if let secondary {
                AvatarView(urlString: secondary)
                    .frame(width: 18, height: 18)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))
                    .offset(x: 2, y: 2)
            }
        }
    }
    
    private func dateTitle(_ d: Date) -> String {
        let f = DateFormatter(); f.dateStyle = .full; return f.string(from: d)
    }
    
    private func timeRange(_ w: WorkoutRow) -> String {
        let f = DateFormatter(); f.timeStyle = .short; f.dateStyle = .none
        guard let started = w.started_at else { return "—" }
        let s = f.string(from: started)
        if let ended = w.ended_at { return "\(s) – \(f.string(from: ended))" }
        return s
    }
    
    private func scoreString(_ s: Double) -> String {
        String(format: "%.0f", s)
    }
    
    @ViewBuilder
    private func kindBadge(_ kind: String) -> some View {
        Text(kind.capitalized)
            .font(.caption2.weight(.semibold))
            .padding(.vertical, 3)
            .padding(.horizontal, 6)
            .background(Capsule().fill(Color.black.opacity(0.06)))
            .overlay(Capsule().stroke(.white.opacity(0.12)))
    }
}

private extension Date {
    var startOfDay: Date { Calendar.current.startOfDay(for: self) }
}

extension ProfileView {
    private func backgroundFor(kind: String) -> AnyShapeStyle {
        switch kind.lowercased() {
        case "strength": return AnyShapeStyle(Color.green.opacity(0.10).gradient)
        case "cardio":   return AnyShapeStyle(Color.blue.opacity(0.10).gradient)
        case "sport":    return AnyShapeStyle(Color.orange.opacity(0.10).gradient)
        default:         return AnyShapeStyle(.ultraThinMaterial)
        }
    }
    
    private func loadUserLevel() async {
        guard let uid = self.viewingUserId else { return }
        
        struct GetUserLevelParams: Encodable { let p_user: UUID }
        
        do {
            let res = try await SupabaseManager.shared.client
                .rpc("get_user_level", params: GetUserLevelParams(p_user: uid))
                .execute()
            
            struct UL: Decodable { let level: Int; let xp: Int64; let last_activity_at: String? }
            let rows = try JSONDecoder.supabase().decode([UL].self, from: res.data)
            let row = rows.first
            let level = row?.level ?? 1
            let xp = row?.xp ?? 0
            
            let thr = try await SupabaseManager.shared.client
                .from("level_thresholds")
                .select("level,xp_required")
                .in("level", values: [level, level + 1])
                .execute()
            
            struct Thr: Decodable { let level: Int; let xp_required: Int64 }
            let thrs = try JSONDecoder.supabase().decode([Thr].self, from: thr.data)
            
            let next = thrs.first(where: { $0.level == level + 1 })?.xp_required
            ?? thrs.first(where: { $0.level == level })?.xp_required
            ?? 120
            
            await MainActor.run {
                self.myLevel = level
                self.myXP = xp
                self.nextLevelXP = next
            }
        } catch {
        }
    }
}

private extension DateFormatter {
    static func shortDay(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "dd/MM"
        return f.string(from: d)
    }
    static func shortMonth(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM yy"
        return f.string(from: d).capitalized
    }
}

private func resizedJPEG(from image: UIImage, maxSide: CGFloat = 1024, quality: CGFloat = 0.85) -> Data? {
    let size = image.size
    let scale = min(maxSide / max(size.width, size.height), 1)
    let newSize = CGSize(width: size.width * scale, height: size.height * scale)
    
    UIGraphicsBeginImageContextWithOptions(newSize, true, 1.0)
    image.draw(in: CGRect(origin: .zero, size: newSize))
    let resized = UIGraphicsGetImageFromCurrentImageContext()
    UIGraphicsEndImageContext()
    
    return resized?.jpegData(compressionQuality: quality)
}

private func kbString(_ data: Data) -> String {
    String(format: "%.1f KB", Double(data.count)/1024.0)
}

private func formatMinutes(_ minutes: Int) -> String {
    let m = max(0, minutes)
    let h = m / 60
    let r = m % 60
    if h > 0 { return "\(h)h \(r)m" }
    return "\(r)m"
}

private func formatXP(_ xp: Int64) -> String {
    if xp >= 1_000_000 { return String(format: "%.1fM", Double(xp) / 1_000_000) }
    if xp >= 1_000     { return String(format: "%.1fk", Double(xp) / 1_000) }
    return "\(xp)"
}
