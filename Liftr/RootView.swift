import SwiftUI

enum Tab: Hashable { case home, search, add, ranking, profile }

struct RootView: View {
    @EnvironmentObject var app: AppState
    @State private var showAuthAlert = false
    
    var body: some View {
        TabView(selection: $app.selectedTab) {
            NavigationStack { HomeView().gradientBG() }
                .tag(Tab.home)
                .tabItem { Label("", systemImage: "house.fill") }
            
            NavigationStack { SearchView().gradientBG() }
                .tag(Tab.search)
                .tabItem { Label("", systemImage: "magnifyingglass") }
            
            NavigationStack {
                AddWorkoutSheet()
                    .gradientBG()
                    .id(app.addDraftKey)
            }
            .tag(Tab.add)
            .tabItem { Label("", systemImage: "plus.circle.fill") }
            
            NavigationStack { RankingView().gradientBG() }
                .tag(Tab.ranking)
                .tabItem { Label("", systemImage: "trophy.fill") }
            
            NavigationStack { ProfileGate().gradientBG() }
                .tag(Tab.profile)
                .tabItem { Label("", systemImage: "person.crop.circle") }
        }
        .onAppear {
            if let pending = app.pendingNotification {
                print("🧭 [RootView] onAppear with pendingNotification:", pending)
                Task { @MainActor in
                    app.processNotification(
                        notificationId: pending.id,
                        type: pending.type,
                        data: pending.data
                    )
                    app.pendingNotification = nil
                }
            }
        }
        .onReceive(app.$pendingNotification) { pending in
            guard let pending else { return }
            print("🧭 [RootView] onReceive pendingNotification:", pending)
            Task { @MainActor in
                app.processNotification(
                    notificationId: pending.id,
                    type: pending.type,
                    data: pending.data
                )
                app.pendingNotification = nil
            }
        }
        .onChange(of: app.notificationDestination) { _, dest in
            print("🧭 [RootView] notificationDestination changed:", dest)
            switch dest {
            case .none:
                break
            case .followerProfile:
                app.selectedTab = .search
            case .workout:
                app.selectedTab = .home
            case .achievements:
                app.selectedTab = .profile
            case .goals:
                app.selectedTab = .profile

            case .competitionsHub, .competitionDetail, .competitionReviews:
                app.selectedTab = .home
            }
        }
        .sheet(
            isPresented: Binding(
                get: { app.notificationDestination != .none },
                set: { newValue in
                    if !newValue {
                        app.notificationDestination = .none
                    }
                }
            )
        ) {
            switch app.notificationDestination {
            case .none:
                EmptyView()
                
            case .followerProfile(let userId):
                ProfileView(userId: userId)
                    .gradientBG()
                
            case .workout(let workoutId, let ownerId):
                if let ownerId {
                    WorkoutDetailView(workoutId: workoutId, ownerId: ownerId)
                        .gradientBG()
                        .onAppear {
                            print("🧪 [RootView.sheet] presenting WorkoutDetailView workoutId=\(workoutId) ownerId=\(ownerId)")
                        }
                } else {
                    WorkoutFromNotificationLoaderView(workoutId: workoutId)
                        .gradientBG()
                }
                
            case .achievements:
                if let currentUserId = app.userId {
                    AchievementsFromNotificationView(
                        userId: currentUserId,
                        viewedUsername: "",
                        showsCloseButton: true
                    )
                    .gradientBG()
                } else {
                    Text("Achievements")
                        .padding()
                }
                
            case .goals(let userId):
                GoalsView(userId: userId, viewedUsername: "")
                    .gradientBG()
                
            case .competitionsHub:
                NavigationStack {
                    CompetitionsHubView()
                        .gradientBG()
                }

            case .competitionReviews:
                NavigationStack {
                    CompetitionReviewsView()
                        .gradientBG()
                }

            case .competitionDetail(_):
                NavigationStack {
                    CompetitionsHubView()
                        .gradientBG()
                }
            }
        }
        .alert("You need to log in", isPresented: $showAuthAlert) {
            Button("Go to Profile") { app.selectedTab = .profile }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Sign up or login to register your workouts.")
        }
    }
}

struct WorkoutFromNotificationLoaderView: View {
    @EnvironmentObject var app: AppState
    let workoutId: Int

    @State private var ownerId: UUID?
    @State private var isLoading = false
    @State private var errorText: String?

    var body: some View {
        Group {
            if let ownerId {
                WorkoutDetailView(workoutId: workoutId, ownerId: ownerId)
            } else if let errorText {
                VStack(spacing: 12) {
                    Text("Workout not found")
                        .font(.headline)
                    Text(errorText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding()
            } else {
                VStack(spacing: 12) {
                    ProgressView("Opening workout…")
                }
                .task { await resolve() }
            }
        }
    }

    @MainActor
    private func resolve() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        print("🧪 [WorkoutLoader] resolving owner for workoutId=\(workoutId) currentUser=\(String(describing: app.userId))")

        struct Row: Decodable { let user_id: UUID }

        do {
            let res = try await SupabaseManager.shared.client
                .from("workouts")
                .select("user_id")
                .eq("id", value: workoutId)
                .limit(1)
                .execute()

            if let raw = String(data: res.data, encoding: .utf8) {
                print("🧪 [WorkoutLoader] raw:", raw)
            }

            let rows = try JSONDecoder.supabase().decode([Row].self, from: res.data)

            guard let oid = rows.first?.user_id else {
                errorText = "Workout \(workoutId) returned 0 rows (RLS or deleted)."
                print("❌ [WorkoutLoader] no rows for workoutId=\(workoutId)")
                return
            }

            print("✅ [WorkoutLoader] resolved ownerId=\(oid) workoutId=\(workoutId)")
            ownerId = oid

        } catch {
            errorText = error.localizedDescription
            print("❌ [WorkoutLoader] resolve error:", error)
        }
    }
}
