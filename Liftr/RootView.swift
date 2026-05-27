import SwiftUI

enum Tab: Hashable { case home, search, add, nutrition, profile }

struct RootView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.openURL) private var openURL
    @State private var showAuthAlert = false
    @State private var updatePrompt: AppUpdatePrompt?
    @State private var didRunUpdateCheck = false
    @State private var territoryBackfillStartedForUserId: UUID?
    
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
            
            NavigationStack { NutritionView().gradientBG() }
                .tag(Tab.nutrition)
                .tabItem { Label("", systemImage: "fork.knife") }
            
            NavigationStack { ProfileGate().gradientBG() }
                .tag(Tab.profile)
                .tabItem {
                    if let tabImg = app.tabBarProfileAvatar {
                        Image(uiImage: tabImg)
                            .renderingMode(.original)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 26, height: 26)
                            .clipShape(Circle())
                    } else {
                        Label("", systemImage: "person.crop.circle")
                    }
                }
                .badge(app.unreadNotificationsCount)
        }
        .task(id: app.userId) {
            guard let userId = app.userId else { return }
            guard territoryBackfillStartedForUserId != userId else { return }
            territoryBackfillStartedForUserId = userId
            Task.detached(priority: .utility) {
                try? await Task.sleep(nanoseconds: 12_000_000_000)
                await TerritoryCaptureClient.backfillHistoricalCaptures(
                    batchSize: 5,
                    maxBatchesPerVisit: 12
                )
            }
        }
        .overlay(alignment: .top) {
            if let message = app.territoryCaptureToast {
                Text(message)
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.top, 8)
                    .padding(.horizontal, 16)
                    .onAppear {
                        Task {
                            try? await Task.sleep(nanoseconds: 4_000_000_000)
                            await MainActor.run { app.territoryCaptureToast = nil }
                        }
                    }
            }
        }
        .onAppear {
            if !didRunUpdateCheck {
                didRunUpdateCheck = true
                Task {
                    let prompt = await AppUpdateChecker.shared.checkForRecommendedUpdate()
                    await MainActor.run { updatePrompt = prompt }
                }
            }

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
            Task {
                await HealthKitBodyWeightSyncService.shared.handleAppForegroundIfNeeded()
                await HealthKitCardioSyncService.shared.handleAppForegroundIfNeeded()
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
            case .segmentDetail:
                app.selectedTab = .search
            case .achievements:
                app.selectedTab = .profile
            case .goals:
                app.selectedTab = .profile
            case .challengeWeekly:
                break

            case .competitionsHub, .competitionDetail, .competitionReviews:
                app.selectedTab = .home

            case .directMessage:
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

            case .segmentDetail(let segmentId):
                NavigationStack {
                    SegmentDetailView(segmentId: segmentId, onClose: {
                        app.notificationDestination = .none
                    })
                    .environmentObject(app)
                }

            case .challengeWeekly(let instanceId):
                NavigationStack {
                    WeeklyChallengeDetailView(instanceId: instanceId, onClose: {
                        app.notificationDestination = .none
                    })
                    .environmentObject(app)
                    .gradientBG()
                }
                
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

            case .directMessage(let conversationId, let senderUserId):
                NavigationStack {
                    DeepLinkedChatThread(conversationId: conversationId, senderId: senderUserId)
                        .environmentObject(app)
                }
                .gradientBG()
            }
        }
        .alert("You need to log in", isPresented: $showAuthAlert) {
            Button("Go to Profile") { app.selectedTab = .profile }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Sign up or login to register your workouts.")
        }
        .overlay(alignment: .top) {
            if let prompt = updatePrompt {
                updateBanner(prompt)
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(99)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: updatePrompt != nil)
        .fullScreenCover(isPresented: $app.passwordRecoveryPending) {
            NavigationStack {
                ResetPasswordView()
            }
            .interactiveDismissDisabled(true)
        }
        .onChange(of: app.passwordRecoveryPending) { _, pending in
            if pending {
                AuthCallbackLogger.log("RootView presenting password recovery fullScreenCover", source: "RootView")
            }
        }
    }

    @ViewBuilder
    private func updateBanner(_ prompt: AppUpdatePrompt) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.blue)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Update available")
                        .font(.subheadline.weight(.semibold))
                    Text("Version \(prompt.latestVersion) is available on the App Store.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                Button("Later") {
                    updatePrompt = nil
                }
                .buttonStyle(.bordered)

                Button("Update") {
                    openURL(prompt.storeURL)
                    updatePrompt = nil
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.2))
        )
        .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 4)
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
