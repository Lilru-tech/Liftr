import SwiftUI
import Supabase
import MapKit
import CoreLocation

struct WorkoutDetailView: View {
    private enum ActiveStrengthLaunch: Identifiable, Equatable {
        case solo
        case dual(guestWorkoutId: Int, guestAvatarURL: String?, hostAvatarURL: String?)
        case trio(
            guest1WorkoutId: Int,
            guest1AvatarURL: String?,
            guest2WorkoutId: Int,
            guest2AvatarURL: String?,
            hostAvatarURL: String?
        )

        var id: String {
            switch self {
            case .solo:
                return "strength-solo"
            case .dual(let guestWorkoutId, _, _):
                return "strength-dual-\(guestWorkoutId)"
            case .trio(let g1, _, let g2, _, _):
                return "strength-trio-\(g1)-\(g2)"
            }
        }
    }

    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    let workoutId: Int
    let ownerId: UUID
    @State private var showEdit = false
    @State private var showDuplicate = false
    @State private var duplicateDraft: AddWorkoutDraft?
    private var canEdit: Bool { app.userId == ownerId }
    
    private var isParticipant: Bool {
        guard let me = app.userId else { return false }
        return participants.contains { $0.user_id == me }
    }
    
    private var canDuplicate: Bool { canEdit || isParticipant }
    
    private var showStartButton: Bool {
        (canEdit || isParticipant) && (workout?.state == "planned")
    }
    
    struct WorkoutDetailRow: Decodable {
        let id: Int
        let user_id: UUID
        let kind: String
        let title: String?
        let notes: String?
        let started_at: Date?
        let ended_at: Date?
        let duration_min: Int?
        let paused_sec: Int?
        let perceived_intensity: String?
        let state: String
        let calories_kcal: Decimal?
    }
    
    struct ProfileRow: Decodable { let user_id: UUID; let username: String; let avatar_url: String? }
    struct ScoreRow: Decodable { let workout_id: Int; let score: Decimal }
    @State private var workout: WorkoutDetailRow?
    
    struct ParticipantRow: Identifiable, Decodable, Hashable {
        let user_id: UUID
        let username: String?
        let avatar_url: String?
        var id: UUID { user_id }
    }
    
    @State private var profile: ProfileRow?
    @State private var totalScore: Double?
    @State private var loading = false
    @State private var totalCalories: Double?
    @State private var error: String?
    @State private var reloadKey = UUID()
    private struct LikeRow: Decodable { let user_id: UUID }
    @State private var isLiked = false
    @State private var likeCount = 0
    @State private var commentCount = 0
    @State private var likeBusy = false
    @State private var showLikesSheet = false
    @State private var likers: [ProfileRow] = []
    @State private var participants: [ParticipantRow] = []
    @State private var loadLikesRequestId = 0
    @State private var showCommentsSheet = false
    @State private var shareWorkoutChatToken: ShareWorkoutChatToken?
    @State private var showErrorAlert = false
    @State private var alertMessage = ""
    @State private var showStartFailureAlert = false
    @State private var startFailureOffersSolo = false
    private enum PendingStartFailure {
        case dualGuest(UUID, String?)
        case trio(ParticipantRow, ParticipantRow)
    }
    @State private var pendingStartFailure: PendingStartFailure?
    @State private var compareCandidateId: Int? = nil
    @State private var compareCandidates: [CompareCandidate] = []
    @State private var comparePicker = ComparePickerState()
    @State private var compareAverageScope: CompareAverageScope? = nil
    @State private var compareAverageRightLabel: String? = nil
    @State private var showComparePicker = false
    @State private var compareReady = false
    @State private var compareComputing = false
    @State private var showCompare = false
    @State private var showDeleteConfirm = false
    @State private var showActiveCardio = false
    @State private var showActiveSport = false
    @State private var deleteBusy = false
    @State private var showDualStartChoice = false
    @State private var dualSheetSelectedParticipantIds: Set<UUID> = []
    @State private var dualGuestWorkoutIdForActive: Int? = nil
    @State private var dualGuest2WorkoutIdForActive: Int? = nil
    @State private var activeStrengthPresentation: ActiveStrengthLaunch?
    
    @ViewBuilder
    private var editDestination: some View {
        if let w = workout {
            EditWorkoutMetaSheet(
                kind: w.kind,
                workoutId: workoutId,
                initial: .init(
                    title: w.title ?? "",
                    notes: w.notes ?? "",
                    startedAt: w.started_at ?? .now,
                    endedAt: w.ended_at,
                    perceived: w.perceived_intensity ?? "moderate"
                ),
                onSaved: {
                    await load()
                    await loadLikes()
                    reloadKey = UUID()
                }
            )
            .gradientBG()
        } else {
            EmptyView()
        }
    }
        
    var body: some View {
        ScrollView {
            content
        }
        .safeAreaInset(edge: .bottom) {
            if showStartButton {
                startButtonBar
                    .padding(.bottom, 12)
            }
        }
        .task {
            await load()
            await loadParticipants()
            await loadLikes()
            await loadCommentCount()
            await loadLikers()
            await loadCompareCandidates()
        }
        .onReceive(NotificationCenter.default.publisher(for: .workoutDidChange)) { note in
            if let id = note.object as? Int,
               id == workoutId || id == dualGuestWorkoutIdForActive || id == dualGuest2WorkoutIdForActive {
                Task { await load(); await loadParticipants() }
            }
        }
        .onChange(of: app.userId) { _, _ in
            Task {
                await loadLikes()
                await loadCompareCandidates()
            }
        }
        .gradientBG()
        .safeAreaPadding(.top, 2)
        .navigationTitle((workout?.title?.isEmpty == false ? workout!.title! : (workout?.kind.capitalized ?? "Workout")))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar { toolbarContent }
        .alert("Delete workout?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                Task { await deleteWorkout() }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will permanently delete this workout and its sets.")
        }
        .alert("Could not start workout", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage.isEmpty ? "Unknown error" : alertMessage)
        }
        .alert("Could not start workout", isPresented: $showStartFailureAlert) {
            if startFailureOffersSolo {
                Button("Start solo") {
                    Task { await resolveStartFailure(startSolo: true) }
                }
            }
            Button("Retry") {
                Task { await resolveStartFailure(retry: true) }
            }
            Button("Start offline") {
                Task { await resolveStartFailure(startOffline: true) }
            }
            Button("Cancel", role: .cancel) {
                pendingStartFailure = nil
            }
        } message: {
            Text(alertMessage.isEmpty ? "Unknown error" : alertMessage)
        }
        .sheet(isPresented: $showLikesSheet) { LikersSheet(likers: likers)
                .onAppear { Task { await loadLikers() } }
                .presentationDetents(Set([.medium, .large]))
                .presentationBackground(.ultraThinMaterial)
        }
        .sheet(isPresented: $showCommentsSheet) {
            CommentsSheet(
                workoutId: workoutId,
                ownerId: ownerId,
                onDidChange: {
                    await load()
                    await loadCommentCount()
                }
            )
            .environmentObject(app)
            .presentationDetents(Set([.large]))
            .presentationBackground(.ultraThinMaterial)
        }
        .sheet(item: $shareWorkoutChatToken) { token in
            ShareWorkoutToChatSheet(snapshot: token.snapshot) {
                shareWorkoutChatToken = nil
            }
            .environmentObject(app)
            .gradientBG()
        }
        .sheet(isPresented: $showComparePicker) {
            CompareCandidatePicker(picker: comparePicker) { target, rightLabel in
                applyCompareTarget(target, rightLabel: rightLabel)
                showCompare = true
            }
            .gradientBG()
            .presentationDetents([.fraction(0.45), .medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showCompare) {
            if let target = resolvedCompareTarget() {
                CompareWorkoutsView(
                    currentWorkoutId: workoutId,
                    other: target,
                    averageRightLabel: compareAverageRightLabel
                )
                .gradientBG()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
        .sheet(isPresented: $showDualStartChoice) {
            dualStartChoiceSheet
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .gradientBG()
                .presentationDetents([.fraction(0.42), .medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
                .onChange(of: showDualStartChoice) { _, isOpen in
                    if isOpen, let first = dualStartParticipantOptions.first {
                        dualSheetSelectedParticipantIds = [first.user_id]
                    }
                }
                .onChange(of: participants.map(\.user_id)) { _, _ in
                    guard showDualStartChoice else { return }
                    let allowed = Set(dualStartParticipantOptions.map(\.user_id))
                    dualSheetSelectedParticipantIds = Set(
                        dualSheetSelectedParticipantIds.filter { allowed.contains($0) }
                    )
                    if dualSheetSelectedParticipantIds.isEmpty, let first = dualStartParticipantOptions.first {
                        dualSheetSelectedParticipantIds = [first.user_id]
                    }
                }
        }
        .navigationDestination(isPresented: $showEdit) {
            editDestination
        }
        .fullScreenCover(item: $activeStrengthPresentation, onDismiss: {
            dualGuestWorkoutIdForActive = nil
            dualGuest2WorkoutIdForActive = nil
            Task {
                await load()
                await loadParticipants()
                await loadCompareCandidates()
                reloadKey = UUID()
            }
        }) { launch in
            switch launch {
            case .solo:
                ActiveStrengthWorkoutView(
                    workoutId: workoutId,
                    dualGuestWorkoutId: nil,
                    dualGuestAvatarURL: nil,
                    dualGuest2WorkoutId: nil,
                    dualGuest2AvatarURL: nil,
                    dualHostAvatarURL: profile?.avatar_url
                )
                .environmentObject(app)
                .gradientBG()
            case .dual(let guestWid, let guestAvatar, let hostAvatar):
                ActiveStrengthWorkoutView(
                    workoutId: workoutId,
                    dualGuestWorkoutId: guestWid,
                    dualGuestAvatarURL: guestAvatar,
                    dualGuest2WorkoutId: nil,
                    dualGuest2AvatarURL: nil,
                    dualHostAvatarURL: hostAvatar ?? profile?.avatar_url
                )
                .environmentObject(app)
                .gradientBG()
            case .trio(let g1Wid, let g1Av, let g2Wid, let g2Av, let hostAv):
                ActiveStrengthWorkoutView(
                    workoutId: workoutId,
                    dualGuestWorkoutId: g1Wid,
                    dualGuestAvatarURL: g1Av,
                    dualGuest2WorkoutId: g2Wid,
                    dualGuest2AvatarURL: g2Av,
                    dualHostAvatarURL: hostAv ?? profile?.avatar_url
                )
                .environmentObject(app)
                .gradientBG()
            }
        }
        .fullScreenCover(
            isPresented: $showActiveCardio,
            onDismiss: {
                Task {
                    await load()
                    await loadParticipants()
                    await loadCompareCandidates()
                    reloadKey = UUID()
                }
            }
        ) {
            ActiveCardioWorkoutView(workoutId: workoutId)
                .environmentObject(app)
                .gradientBG()
        }
        .fullScreenCover(
            isPresented: $showActiveSport,
            onDismiss: {
                Task {
                    await load()
                    await loadParticipants()
                    await loadCompareCandidates()
                    reloadKey = UUID()
                }
            }
        ) {
            ActiveSportWorkoutView(workoutId: workoutId)
                .environmentObject(app)
                .gradientBG()
        }
    }
    
    @ViewBuilder
    private var content: some View {
        VStack(spacing: 14) {
            if loading && workout == nil {
                DetailSectionCard(title: "Workout") {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                }
            } else if let error, workout == nil {
                DetailSectionCard(title: "Workout") {
                    DetailEmptyState(
                        title: "Could not load workout",
                        message: error,
                        systemImage: "exclamationmark.triangle"
                    )
                }
            } else if let w = workout {
                workoutHeader(w)

                if !participants.isEmpty {
                    participantsBlock
                }
                if let notes = workout?.notes,
                   !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    notesBlock(notes)
                }

                workoutDetail(w.kind)
                feedbackBlock
            } else {
                DetailSectionCard(title: "Workout") {
                    DetailEmptyState(
                        title: "Workout unavailable",
                        message: "This workout could not be found.",
                        systemImage: "figure.run"
                    )
                }
            }
        }
        .padding(16)
    }
    
    @ViewBuilder
    private func workoutHeader(_ w: WorkoutDetailRow) -> some View {
        ZStack {
            WorkoutCardBackground(kind: w.kind)
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    AvatarView(urlString: profile?.avatar_url)
                        .frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 4) {
                        NavigationLink {
                            ProfileView(userId: ownerId).id(ownerId).gradientBG()
                        } label: {
                            Text("@\(profile?.username ?? "user")")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        
                        Text(w.title ?? w.kind.capitalized)
                            .font(.title3.weight(.semibold))
                            .lineLimit(2)
                    }
                    Spacer()

                    HStack(spacing: 8) {
                        if let kcal = totalCalories, kcal > 0 {
                            caloriesPill(kcal: kcal, kind: w.kind)
                        }
                        if let sc = totalScore {
                            scorePill(score: sc, kind: w.kind)
                        }
                    }
                }
                
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(dateRange(w)).font(.footnote).foregroundStyle(.secondary)
                    if let dur = w.duration_min {
                        Text("• \(dur) min")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    if let paused = w.paused_sec, paused > 0 {
                        Text("• Paused \(durationString(Double(paused)))")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    if let pi = w.perceived_intensity, !pi.isEmpty {
                        Text("• \(pi.capitalized)")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    if !participants.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "person.2.fill")
                            Text("\(participants.count)")
                        }
                        .font(.footnote.weight(.semibold))
                        .padding(.vertical, 2)
                        .padding(.horizontal, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                    }
                    Spacer()
                    if w.state == "planned" {
                        draftBadge
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.18)))
    }
    
    private var draftBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "pencil")
            Text("Draft")
        }
        .font(.caption2.weight(.semibold))
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(Capsule().fill(Color.yellow.opacity(0.22)))
        .overlay(Capsule().stroke(Color.white.opacity(0.12)))
    }
        
    @ViewBuilder
    private func notesBlock(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Notes").font(.headline)
            Text(notes)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.18)))
    }
    
    private var participantsBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Participants").font(.headline)
            
            LazyVStack(spacing: 8) {
                ForEach(participants, id: \.id) { p in
                    HStack(spacing: 10) {
                        AvatarView(urlString: p.avatar_url)
                            .frame(width: 28, height: 28)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        NavigationLink {
                            ProfileView(userId: p.user_id).id(p.user_id).gradientBG()
                        } label: {
                            Text("@\(p.username ?? "user")")
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                }
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.18)))
    }
    
    @ViewBuilder
    private func workoutDetail(_ kind: String) -> some View {
        switch kind.lowercased() {
        case "strength":
            StrengthDetailBlock(workoutId: workoutId, reloadKey: reloadKey)
        case "cardio":
            CardioDetailBlock(
                workoutId: workoutId,
                reloadKey: reloadKey,
                canEdit: canEdit,
                workoutState: workout?.state
            )
        case "sport":
            SportDetailBlock(workoutId: workoutId, reloadKey: reloadKey, canEdit: canEdit)
        default:
            EmptyView()
        }
    }
    
    private var feedbackBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Feedback").font(.headline)
            HStack(spacing: 10) {
                likeButtonGroup
                commentButton
                if app.userId != nil {
                    shareToChatButton
                }
                Spacer()
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.18)))
    }
    
    private var shouldOfferDualStrengthStart: Bool {
        effectiveWorkoutKindForDual == "strength" && !dualStartParticipantOptions.isEmpty
    }

    private var dualStartParticipantOptions: [ParticipantRow] {
        guard let me = app.userId else { return participants }
        return participants.filter { $0.user_id != me }
    }

    private var effectiveWorkoutKindForDual: String {
        let raw = (workout?.kind ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if raw == "strength" || raw == "cardio" || raw == "sport" { return raw }
        let title = (workout?.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if title == "strength" { return "strength" }
        return raw
    }

    @ViewBuilder
    private var dualStartChoiceSheet: some View {
        let selectableParticipants = dualStartParticipantOptions
        if selectableParticipants.isEmpty {
            EmptyView()
        } else {
            let multiInviteWorkout = selectableParticipants.count > 1
            let showsAsGroupSession = dualSheetSelectedParticipantIds.count > 1
            let soleSelectedPick: ParticipantRow? = {
                guard dualSheetSelectedParticipantIds.count == 1,
                      let only = dualSheetSelectedParticipantIds.first
                else { return nil }
                return selectableParticipants.first { $0.user_id == only }
            }()
            VStack(spacing: 16) {
                Text(showsAsGroupSession ? "Group workout" : "Dual workout")
                    .font(.title3.weight(.bold))
                if multiInviteWorkout {
                    Text(
                        "Tap to select people. Dual: exactly one selected. Group: pick two (you plus two partners on this phone, three people total). Each lane keeps separate results."
                    )
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(selectableParticipants) { p in
                                dualParticipantSelectRow(
                                    participant: p,
                                    isSelected: dualSheetSelectedParticipantIds.contains(p.user_id)
                                )
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    var next = dualSheetSelectedParticipantIds
                                    if next.contains(p.user_id) {
                                        if next.count > 1 { next.remove(p.user_id) }
                                    } else {
                                        if next.count >= 2 { return }
                                        next.insert(p.user_id)
                                    }
                                    dualSheetSelectedParticipantIds = next
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 240)
                } else if let p = selectableParticipants.first {
                    HStack(spacing: 12) {
                        AvatarView(urlString: p.avatar_url)
                            .frame(width: 56, height: 56)
                        Text("@\(p.username ?? "user")")
                            .font(.title3.weight(.semibold))
                            .lineLimit(1)
                    }
                    Text("Train together on this phone. Each person keeps their own weight, reps, and rest timers, with separate workout results.")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 12) {
                    Button("Just me") {
                        showDualStartChoice = false
                        Task { await startPlannedWorkout(dualParticipantId: nil, dualGuestAvatar: nil) }
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)

                    Button(showsAsGroupSession ? "Group" : "Dual") {
                        showDualStartChoice = false
                        if dualSheetSelectedParticipantIds.count > 1 {
                            let picks = selectableParticipants.filter { dualSheetSelectedParticipantIds.contains($0.user_id) }
                            guard picks.count >= 2 else { return }
                            let pair = Array(picks.prefix(2))
                            guard pair.count == 2 else { return }
                            Task { await startPlannedTrioStrength(guestA: pair[0], guestB: pair[1]) }
                            return
                        }
                        guard let pick = soleSelectedPick else { return }
                        Task { await startPlannedWorkout(dualParticipantId: pick.user_id, dualGuestAvatar: pick.avatar_url) }
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(24)
        }
    }

    private func dualParticipantSelectRow(participant p: ParticipantRow, isSelected: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            AvatarView(urlString: p.avatar_url)
                .frame(width: 44, height: 44)
            Text("@\(p.username ?? "user")")
                .font(.body.weight(.semibold))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.04))
        )
    }

    private struct CreateLinkedStrengthRPC: Encodable {
        let p_source_workout_id: Int64
        let p_target_user_id: UUID
    }

    private func rpcCreateLinkedStrengthCopy(targetUserId: UUID) async throws -> Int64 {
        let client = SupabaseManager.shared.client
        let params = CreateLinkedStrengthRPC(
            p_source_workout_id: Int64(workoutId),
            p_target_user_id: targetUserId
        )
        let res = try await client.rpc("create_linked_strength_workout_copy", params: params).execute()
        let data = res.data
        if let id = try? JSONDecoder().decode(Int64.self, from: data) {
            return id
        }
        if let arr = try? JSONDecoder().decode([Int64].self, from: data), let id = arr.first {
            return id
        }
        throw NSError(
            domain: "DualWorkout",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Could not create the linked workout copy (invalid RPC response)."]
        )
    }

    private func ensureStrengthKindPersistedBeforeLinkedCopy() async throws {
        struct KindPatch: Encodable { let kind: String }
        _ = try await SupabaseManager.shared.client
            .from("workouts")
            .update(KindPatch(kind: "strength"))
            .eq("id", value: workoutId)
            .execute()

        await MainActor.run {
            guard let w = workout else { return }
            self.workout = WorkoutDetailRow(
                id: w.id,
                user_id: w.user_id,
                kind: "strength",
                title: w.title,
                notes: w.notes,
                started_at: w.started_at,
                ended_at: w.ended_at,
                duration_min: w.duration_min,
                paused_sec: w.paused_sec,
                perceived_intensity: w.perceived_intensity,
                state: w.state,
                calories_kcal: w.calories_kcal
            )
        }
        NotificationCenter.default.post(name: .workoutDidChange, object: workoutId)
    }

    private func applyLocalWorkoutStartedNow() {
        let now = Date()
        if let w = workout {
            workout = WorkoutDetailRow(
                id: w.id,
                user_id: w.user_id,
                kind: w.kind,
                title: w.title,
                notes: w.notes,
                started_at: now,
                ended_at: nil,
                duration_min: w.duration_min,
                paused_sec: w.paused_sec,
                perceived_intensity: w.perceived_intensity,
                state: w.state,
                calories_kcal: w.calories_kcal
            )
        }
        NotificationCenter.default.post(name: .workoutDidChange, object: workoutId)
    }

    @MainActor
    private func presentPlannedActive(
        dualParticipantId: UUID?,
        dualGuestAvatar: String?,
        guestWorkoutId: Int? = nil,
        guest2WorkoutId: Int? = nil,
        guest2Avatar: String? = nil
    ) {
        dualGuestWorkoutIdForActive = guestWorkoutId
        dualGuest2WorkoutIdForActive = guest2WorkoutId
        let hostURL = profile?.avatar_url
        switch effectiveWorkoutKindForDual {
        case "strength":
            if let g2 = guest2WorkoutId, let g1 = guestWorkoutId {
                activeStrengthPresentation = .trio(
                    guest1WorkoutId: g1,
                    guest1AvatarURL: dualGuestAvatar,
                    guest2WorkoutId: g2,
                    guest2AvatarURL: guest2Avatar,
                    hostAvatarURL: hostURL
                )
            } else if let gid = guestWorkoutId, dualParticipantId != nil {
                activeStrengthPresentation = .dual(
                    guestWorkoutId: gid,
                    guestAvatarURL: dualGuestAvatar,
                    hostAvatarURL: hostURL
                )
            } else {
                activeStrengthPresentation = .solo
            }
        case "cardio":
            showActiveCardio = true
        case "sport":
            showActiveSport = true
        default:
            break
        }
    }

    private func beginOptimisticServerStart() {
        applyLocalWorkoutStartedNow()
        _ = WorkoutStartSync.enqueueStart(workoutId: workoutId)
    }

    private func rpcCreateLinkedStrengthCopyWithRetries(targetUserId: UUID) async throws -> Int64 {
        try await WorkoutStartSync.withRetries {
            try await rpcCreateLinkedStrengthCopy(targetUserId: targetUserId)
        }
    }

    private func startPlannedWorkout(dualParticipantId: UUID?, dualGuestAvatar: String?) async {
        beginOptimisticServerStart()

        if let pid = dualParticipantId, effectiveWorkoutKindForDual == "strength" {
            do {
                try await ensureStrengthKindPersistedBeforeLinkedCopy()
                let newWid = try await rpcCreateLinkedStrengthCopyWithRetries(targetUserId: pid)
                await MainActor.run {
                    presentPlannedActive(
                        dualParticipantId: pid,
                        dualGuestAvatar: dualGuestAvatar,
                        guestWorkoutId: Int(newWid)
                    )
                }
            } catch {
                let detail = Self.describeSupabaseError(error)
                print("[DualStart][ERROR] workoutId=\(workoutId) :: \(detail)")
                await MainActor.run {
                    pendingStartFailure = .dualGuest(pid, dualGuestAvatar)
                    startFailureOffersSolo = true
                    alertMessage = WorkoutStartSync.userFacingMessage(for: error)
                    showStartFailureAlert = true
                }
            }
            return
        }

        await MainActor.run {
            presentPlannedActive(dualParticipantId: nil, dualGuestAvatar: nil)
        }
    }

    private func startPlannedTrioStrength(guestA: ParticipantRow, guestB: ParticipantRow) async {
        beginOptimisticServerStart()
        do {
            try await ensureStrengthKindPersistedBeforeLinkedCopy()
            let w1 = try await rpcCreateLinkedStrengthCopyWithRetries(targetUserId: guestA.user_id)
            let w2 = try await rpcCreateLinkedStrengthCopyWithRetries(targetUserId: guestB.user_id)
            await MainActor.run {
                presentPlannedActive(
                    dualParticipantId: guestA.user_id,
                    dualGuestAvatar: guestA.avatar_url,
                    guestWorkoutId: Int(w1),
                    guest2WorkoutId: Int(w2),
                    guest2Avatar: guestB.avatar_url
                )
            }
        } catch {
            let detail = Self.describeSupabaseError(error)
            print("[TrioStart][ERROR] workoutId=\(workoutId) :: \(detail)")
            await MainActor.run {
                pendingStartFailure = .trio(guestA, guestB)
                startFailureOffersSolo = true
                alertMessage = WorkoutStartSync.userFacingMessage(for: error)
                showStartFailureAlert = true
            }
        }
    }

    private func resolveStartFailure(
        retry: Bool = false,
        startOffline: Bool = false,
        startSolo: Bool = false
    ) async {
        let failure = pendingStartFailure
        await MainActor.run {
            showStartFailureAlert = false
            pendingStartFailure = nil
            startFailureOffersSolo = false
        }

        if startOffline || startSolo {
            await MainActor.run {
                presentPlannedActive(dualParticipantId: nil, dualGuestAvatar: nil)
            }
            return
        }

        guard retry, let failure else { return }
        switch failure {
        case .dualGuest(let pid, let avatar):
            await startPlannedWorkout(dualParticipantId: pid, dualGuestAvatar: avatar)
        case .trio(let a, let b):
            await startPlannedTrioStrength(guestA: a, guestB: b)
        }
    }

    private static func describeSupabaseError(_ error: Error) -> String {
        if let pe = error as? PostgrestError {
            var parts: [String] = [pe.message]
            if let c = pe.code, !c.isEmpty { parts.append("code=\(c)") }
            if let h = pe.hint, !h.isEmpty { parts.append("hint=\(h)") }
            if let d = pe.detail, !d.isEmpty { parts.append("detail=\(d)") }
            return parts.joined(separator: " | ")
        }
        return "\(error.localizedDescription) [\(String(describing: Swift.type(of: error)))]"
    }

    private var startButtonBar: some View {
        Button {
            if shouldOfferDualStrengthStart {
                showDualStartChoice = true
            } else {
                Task { await startPlannedWorkout(dualParticipantId: nil, dualGuestAvatar: nil) }
            }
        } label: {
            Text("Start")
                .font(.headline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.accentColor)
                )
                .foregroundColor(.white)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
    }
    
    private var likeButtonGroup: some View {
        HStack(spacing: 0) {
            Button {
                Task { await toggleLike() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isLiked ? "heart.fill" : "heart")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(isLiked ? .red : .secondary)
                }
                .frame(height: 28)
                .padding(.vertical, 8)
                .padding(.leading, 12)
                .padding(.trailing, 10)
            }
            .buttonStyle(.plain)
            .disabled(likeBusy)
            .contentShape(Rectangle())
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.4).onEnded { _ in
                    Task { await showLikers() }
                }
            )
            
            Divider()
                .frame(height: 20)
                .padding(.vertical, 6)
                .opacity(0.25)
            
            Button {
                Task { await showLikers() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "person.2.fill")
                    Text("\(likeCount)").font(.subheadline.weight(.semibold))
                }
                .frame(height: 28)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
            }
            .buttonStyle(.plain)
        }
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.12)))
    }
    
    private var commentButton: some View {
        Button { showCommentsSheet = true } label: {
            HStack(spacing: 6) {
                Image(systemName: "bubble.right")
                    .foregroundStyle(.secondary)
                Text("Comments")
                    .font(.subheadline.weight(.semibold))
                Text("\(commentCount)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(.ultraThinMaterial, in: Capsule())
        }
    }

    private var shareToChatButton: some View {
        Button {
            guard let snap = makeWorkoutShareSnapshot() else { return }
            shareWorkoutChatToken = ShareWorkoutChatToken(snapshot: snap)
        } label: {
            Image(systemName: "paperplane")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(.ultraThinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(workout == nil || profile == nil)
    }

    private struct ShareWorkoutChatToken: Identifiable {
        let id = UUID()
        let snapshot: WorkoutShareSnapshot
    }

    private func makeWorkoutShareSnapshot() -> WorkoutShareSnapshot? {
        guard let w = workout, let prof = profile else { return nil }
        let ref = w.started_at ?? w.ended_at ?? Date()
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let performedAt = iso.string(from: ref)
        let scoreInt: Int? = totalScore.map { Int($0.rounded()) }
        let kcalInt: Int? = {
            guard let c = totalCalories, c > 0 else { return nil }
            return Int(c.rounded())
        }()
        return WorkoutShareSnapshot(
            v: 1,
            workout_id: Int64(workoutId),
            title: w.title,
            kind: w.kind,
            score: scoreInt,
            kcal: kcalInt,
            performed_at: performedAt,
            owner_user_id: w.user_id,
            owner_username: prof.username,
            owner_avatar_url: prof.avatar_url
        )
    }
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if canEdit {
            ToolbarItem(placement: .topBarTrailing) {
                if let w = workout, w.state == "planned" {
                    Button("Publish") {
                        Task { await publishWorkout() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        
        if canEdit || canDuplicate || (compareReady && workout?.state != "planned") {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if compareReady, workout?.state != "planned" {
                        if shouldShowComparePicker(comparePicker) {
                            Button("Compare…") { showComparePicker = true }
                        } else if let only = singleCompareTarget(comparePicker) {
                            Button("Compare") {
                                applyCompareTarget(only, rightLabel: nil)
                                showCompare = true
                            }
                        }
                    }
                    if canEdit {
                        Button("Edit") { showEdit = true }
                    }
                    if canDuplicate {
                        Button("Duplicate") {
                            Task {
                                let d = await buildDuplicateDraft()
                                await MainActor.run {
                                    guard let d else { return }
                                    app.addDraft = d
                                    app.addDraftKey = UUID()
                                    app.selectedTab = .add
                                }
                            }
                        }
                    }
                    if canEdit {
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Text("Delete workout")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }
    
    private func load() async {
        loading = true; defer { loading = false }
        do {
            let wRes = try await SupabaseManager.shared.client
                .from("workouts")
                .select("id, user_id, kind, title, notes, started_at, ended_at, duration_min, paused_sec, perceived_intensity, state, calories_kcal")
                .eq("id", value: workoutId)
                .single()
                .execute()
            let w = try JSONDecoder.supabase().decode(WorkoutDetailRow.self, from: wRes.data)
            
            let pRes = try await SupabaseManager.shared.client
                .from("profiles")
                .select("user_id, username, avatar_url")
                .eq("user_id", value: ownerId.uuidString)
                .single()
                .execute()
            let p = try JSONDecoder.supabase().decode(ProfileRow.self, from: pRes.data)
            
            let sRes = try await SupabaseManager.shared.client
                .from("workout_scores")
                .select("workout_id, score")
                .eq("workout_id", value: workoutId)
                .execute()
            let sRows = try JSONDecoder.supabase().decode([ScoreRow].self, from: sRes.data)
            let total = sRows.reduce(0.0) { $0 + NSDecimalNumber(decimal: $1.score).doubleValue }

            await MainActor.run {
                self.workout = w
                self.profile = p
                self.totalScore = sRows.isEmpty ? nil : total
                self.totalCalories = w.calories_kcal.map { NSDecimalNumber(decimal: $0).doubleValue }
                self.error = nil
            }
        } catch {
            await MainActor.run { self.error = error.localizedDescription }
        }
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
    
    private func loadCommentCount() async {
        do {
            let countRes = try await SupabaseManager.shared.client
                .from("workout_comments")
                .select("id", head: true, count: .exact)
                .eq("workout_id", value: workoutId)
                .is("deleted_at", value: nil)
                .execute()
            let total = countRes.count ?? 0
            await MainActor.run { self.commentCount = total }
        } catch {
            print("loadCommentCount error:", error)
        }
    }

    private func loadLikes() async {
        let reqId = loadLikesRequestId + 1
        await MainActor.run { loadLikesRequestId = reqId }
        
        do {
            let countRes = try await SupabaseManager.shared.client
                .from("workout_likes")
                .select("user_id", head: true, count: .exact)
                .eq("workout_id", value: workoutId)
                .execute()
            let total = countRes.count ?? 0
            var mine = false
            if let me = app.userId {
                let myRes = try await SupabaseManager.shared.client
                    .from("workout_likes")
                    .select("user_id")
                    .eq("workout_id", value: workoutId)
                    .eq("user_id", value: me.uuidString)
                    .limit(1)
                    .execute()
                let rows = try JSONDecoder.supabase().decode([LikeRow].self, from: myRes.data)
                mine = !rows.isEmpty
            }
            guard reqId == loadLikesRequestId else { return }
            
            await MainActor.run {
                self.likeCount = total
                self.isLiked = mine
            }
        } catch {
            print("loadLikes error:", error)
        }
    }
    
    private func toggleLike() async {
        guard !likeBusy else { return }
        guard let me = app.userId else { return }
        await MainActor.run { likeBusy = true }
        defer { Task { await MainActor.run { likeBusy = false } } }
        
        do {
            if isLiked {
                _ = try await SupabaseManager.shared.client
                    .from("workout_likes")
                    .delete()
                    .eq("workout_id", value: workoutId)
                    .eq("user_id", value: me.uuidString)
                    .execute()
                await MainActor.run {
                    self.isLiked = false
                    self.likeCount = max(0, self.likeCount - 1)
                }
                Task { await loadLikers(); await loadLikes() }
            } else {
                struct LikeInsert: Encodable { let workout_id: Int; let user_id: UUID }
                _ = try await SupabaseManager.shared.client
                    .from("workout_likes")
                    .insert(LikeInsert(workout_id: workoutId, user_id: me))
                    .execute()
                await MainActor.run {
                    self.isLiked = true
                    self.likeCount += 1
                }
                Task { await loadLikers(); await loadLikes() }
            }
        } catch {
            await loadLikes()
        }
    }
    
    private func showLikers() async {
        await MainActor.run { showLikesSheet = true }
        await loadLikers()
        if self.likers.isEmpty, self.likeCount > 0 {
            try? await Task.sleep(nanoseconds: 300_000_000)
            await loadLikers()
        }
    }
    
    private func loadLikers() async {
        do {
            let res = try await SupabaseManager.shared.client
                .from("workout_likes")
                .select("user_id, created_at, profiles(user_id, username, avatar_url)")
                .eq("workout_id", value: workoutId)
                .order("created_at", ascending: false)
                .limit(200)
                .execute()
            
            struct LikeWire: Decodable {
                let user_id: UUID
                let created_at: Date
                let profiles: ProfileRow?
            }
            let rows = try JSONDecoder.supabase().decode([LikeWire].self, from: res.data)
            var people: [ProfileRow] = rows.compactMap { $0.profiles }
            
            if people.isEmpty, !rows.isEmpty {
                let ids = rows.map { $0.user_id.uuidString }
                let pRes = try await SupabaseManager.shared.client
                    .from("profiles")
                    .select("user_id, username, avatar_url")
                    .in("user_id", values: ids)
                    .execute()
                let fetched = try JSONDecoder.supabase().decode([ProfileRow].self, from: pRes.data)
                people = fetched
            }
            
            await MainActor.run { self.likers = people }
        } catch {
            await MainActor.run { self.likers = [] }
        }
    }
    
    private func loadParticipants() async {
        do {
            let res = try await SupabaseManager.shared.client
                .from("workout_participants")
                .select("user_id, profiles!workout_participants_user_id_fkey(username, avatar_url)")
                .eq("workout_id", value: workoutId)
                .execute()
            
            struct Wire: Decodable {
                let user_id: UUID
                let profiles: Profile?
                struct Profile: Decodable { let username: String?; let avatar_url: String? }
            }
            let rows = try JSONDecoder.supabase().decode([Wire].self, from: res.data)
            let mapped: [ParticipantRow] = rows.map {
                ParticipantRow(user_id: $0.user_id, username: $0.profiles?.username, avatar_url: $0.profiles?.avatar_url)
            }
            await MainActor.run { self.participants = mapped }
        } catch {
            await MainActor.run { self.participants = [] }
        }
    }
    
    private func publishWorkout() async {
        guard let me = app.userId else { return }
        if let w = workout, w.state != "planned" {
            print("[Publish] skipped: state is already '\(w.state)'")
            return
        }
        
        do {
            let newStarted = workout?.started_at ?? Date()
            
            struct WorkoutUpdate: Encodable {
                let state: String
                let started_at: Date
            }
            let payload = WorkoutUpdate(state: "published", started_at: newStarted)
            
            let res = try await SupabaseManager.shared.client
                .from("workouts")
                .update(payload)
                .eq("id", value: workoutId)
                .eq("user_id", value: me.uuidString)
                .select("*")
                .single()
                .execute()
            print("[Publish] status =", res.response.statusCode)
            let bodyStr = String(data: res.data, encoding: .utf8) ?? ""
            print("[Publish] body   =", bodyStr)
            let trimmed = bodyStr.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed == "[]" || trimmed.isEmpty {
                throw NSError(domain: "Publish", code: 0,
                              userInfo: [NSLocalizedDescriptionKey:
                                            "No se actualizó ninguna fila (RLS o user_id no coincide)."])
            }
            
            let updated = try JSONDecoder.supabase().decode(WorkoutDetailRow.self, from: res.data)
            
            await MainActor.run {
                self.workout = updated
                self.error = nil
            }
            if updated.state == "planned" {
                print("[Publish][WARN] UI still shows planned, forcing reload()")
                await load()
            }
            
            var ui: [String: Any] = ["kind": updated.kind, "state": updated.state]
            if let t = updated.title { ui["title"] = t }
            if let s = updated.started_at { ui["started_at"] = s }
            if let e = updated.ended_at { ui["ended_at"] = e }
            
            NotificationCenter.default.post(
                name: .workoutUpdated,
                object: workoutId,
                userInfo: ui
            )
            
            print("[Publish] done. state=\(updated.state)")
            await loadParticipants()
        } catch {
            print("[Publish][ERROR]", error.localizedDescription)
            await MainActor.run {
                self.alertMessage = error.localizedDescription
                self.showErrorAlert = true
                self.error = error.localizedDescription
            }
        }
    }
    
    private struct StartWorkoutRPCParams: Encodable {
        let p_workout_id: Int64
        let p_started_at: String
    }

    private func setWorkoutStartedNow() async throws {
        let now = Date()
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let params = StartWorkoutRPCParams(p_workout_id: Int64(workoutId), p_started_at: iso.string(from: now))

        let res = try await SupabaseManager.shared.client
            .rpc("start_workout_v1", params: params)
            .execute()

        let body = String(data: res.data, encoding: .utf8) ?? ""
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "[]" {
            throw NSError(
                domain: "StartWorkout",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: "No row was updated (RLS/policy or invalid workout id)."]
            )
        }

        await MainActor.run {
            if let w = self.workout {
                self.workout = WorkoutDetailRow(
                    id: w.id,
                    user_id: w.user_id,
                    kind: w.kind,
                    title: w.title,
                    notes: w.notes,
                    started_at: now,
                    ended_at: nil,
                    duration_min: w.duration_min,
                    paused_sec: w.paused_sec,
                    perceived_intensity: w.perceived_intensity,
                    state: w.state,
                    calories_kcal: w.calories_kcal
                )
            }
        }

        NotificationCenter.default.post(name: .workoutDidChange, object: workoutId)
    }
    
    private func deleteWorkout() async {
        guard let me = app.userId else { return }
        if deleteBusy { return }

        await MainActor.run { deleteBusy = true }
        defer {
            Task { await MainActor.run { deleteBusy = false } }
        }

        do {
            let res = try await SupabaseManager.shared.client
                .from("workouts")
                .delete()
                .eq("id", value: workoutId)
                .eq("user_id", value: me.uuidString)
                .select("id")
                .single()
                .execute()

            let bodyStr = String(data: res.data, encoding: .utf8) ?? ""
            let trimmed = bodyStr.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed == "[]" {
                throw NSError(
                    domain: "DeleteWorkout",
                    code: 0,
                    userInfo: [NSLocalizedDescriptionKey:
                                "Workout not found or you don't have permission to delete it."]
                )
            }

            await MainActor.run {
                dismiss()
            }
        } catch {
            print("[DeleteWorkout][ERROR]", error.localizedDescription)
        }
    }
    
    private func dateRange(_ w: WorkoutDetailRow) -> String {
        let f = DateFormatter(); f.timeStyle = .short; f.dateStyle = .medium
        guard let s = w.started_at else { return "—" }
        if let e = w.ended_at { return "\(f.string(from: s)) – \(f.string(from: e))" }
        return f.string(from: s)
    }
    
    private func buildDuplicateDraft() async -> AddWorkoutDraft? {
        guard let base = workout else { return nil }
        
        let me = app.userId

        let dupStartedAt: Date = {
            if let me, base.user_id == me { return Date() }
            return base.started_at ?? Date()
        }()

        let dupEndedAt: Date? = {
            if let me, base.user_id == me { return nil }
            return base.ended_at
        }()

        var draft = AddWorkoutDraft(
            kind: WorkoutKind(rawValue: base.kind) ?? .strength,
            title: base.title ?? "",
            note: base.notes ?? "",
            startedAt: dupStartedAt,
            endedAt: dupEndedAt,
            perceived: WorkoutIntensity(rawValue: base.perceived_intensity ?? "moderate") ?? .moderate
        )
        
        let decoder = JSONDecoder.supabase()
        
        switch base.kind.lowercased() {
        case "strength":
            do {
                let exRes = try await SupabaseManager.shared.client
                    .from("workout_exercises")
                    .select("id, exercise_id, order_index, superset_group_id, superset_position, notes, custom_name, exercises(name)")
                    .eq("workout_id", value: workoutId)
                    .order("order_index", ascending: true)
                    .execute()
                
                struct ExWire: Decodable {
                    let id: Int
                    let exercise_id: Int64
                    let order_index: Int
                    let superset_group_id: UUID?
                    let superset_position: Int?
                    let notes: String?
                    let exercises: ExName?
                    let custom_name: String?
                    struct ExName: Decodable { let name: String? }
                }
                let exs = try decoder.decode([ExWire].self, from: exRes.data)
                
                let exIds = exs.map { $0.id }
                var setsByEx: [Int: [EditableSet]] = [:]
                if !exIds.isEmpty {
                    struct SetWire: Decodable {
                        let id: Int
                        let workout_exercise_id: Int
                        let set_number: Int
                        let order_index: Int?
                        let reps: Int?
                        let weight_kg: Decimal?
                        let rpe: Decimal?
                        let rest_sec: Int?
                        let weight_segments: [StrengthWeightSegWire]?
                    }
                    let setData: Data
                    do {
                        setData = try await SupabaseManager.shared.client
                            .from("exercise_sets")
                            .select("id, workout_exercise_id, set_number, order_index, reps, weight_kg, rpe, rest_sec, weight_segments")
                            .in("workout_exercise_id", values: exIds)
                            .order("order_index", ascending: true)
                            .order("id", ascending: true)
                            .execute()
                            .data
                    } catch {
                        setData = try await SupabaseManager.shared.client
                            .from("exercise_sets")
                            .select("id, workout_exercise_id, set_number, reps, weight_kg, rpe, rest_sec, weight_segments")
                            .in("workout_exercise_id", values: exIds)
                            .order("set_number", ascending: true)
                            .order("id", ascending: true)
                            .execute()
                            .data
                    }
                    let sets = try decoder.decode([SetWire].self, from: setData)
                    for s in sets {
                        let nextOrder = setsByEx[s.workout_exercise_id, default: []].count + 1
                        let segDraft = (s.weight_segments ?? []).asEditorSegmentsIfDropSet()
                        setsByEx[s.workout_exercise_id, default: []].append(
                            EditableSet(
                                setNumber: s.set_number,
                                orderIndex: s.order_index ?? nextOrder,
                                reps: s.reps,
                                weightKg: s.weight_kg.map { String(NSDecimalNumber(decimal: $0).doubleValue) } ?? "",
                                rpe: s.rpe.map { String(NSDecimalNumber(decimal: $0).doubleValue) } ?? "",
                                restSec: s.rest_sec,
                                notes: "",
                                segments: segDraft
                            )
                        )
                    }
                }
                
                draft.strengthItems = exs.map { ex in
                    EditableExercise(
                        exerciseId: ex.exercise_id,
                        exerciseName: (ex.custom_name?.isEmpty == false ? ex.custom_name! : (ex.exercises?.name ?? "")),
                        orderIndex: ex.order_index,
                        supersetGroupId: ex.superset_group_id,
                        supersetPosition: ex.superset_position,
                        notes: ex.notes ?? "",
                        sets: setsByEx[ex.id] ?? [EditableSet(setNumber: 1)]
                    )
                }
            } catch { return nil }
            
        case "cardio":
            do {
                let res = try await SupabaseManager.shared.client
                    .from("cardio_sessions")
                    .select("*")
                    .eq("workout_id", value: workoutId)
                    .single()
                    .execute()
                
                struct Row: Decodable {
                    let id: Int
                    let activity_code: String?
                    let modality: String?
                    let distance_km: Decimal?
                    let duration_sec: Int?
                    let avg_hr: Int?
                    let max_hr: Int?
                    let avg_pace_sec_per_km: Int?
                    let elevation_gain_m: Int?
                    let notes: String?
                }
                let r = try decoder.decode(Row.self, from: res.data)
                
                var cf = CardioForm()
                cf.activity = CardioActivityType(rawValue: r.activity_code ?? r.modality ?? "run") ?? .run
                cf.distanceKm = r.distance_km.map { "\(NSDecimalNumber(decimal: $0).doubleValue)" } ?? ""
                if let s = r.duration_sec, s > 0 {
                    cf.durH = String(s/3600); cf.durM = String((s%3600)/60); cf.durS = String(s%60)
                }
                cf.avgHR = r.avg_hr.map { "\($0)" } ?? ""
                cf.maxHR = r.max_hr.map { "\($0)" } ?? ""
                if let p = r.avg_pace_sec_per_km, p > 0 {
                    cf.paceH = ""; cf.paceM = String(p/60); cf.paceS = String(p%60)
                }
                cf.elevationGainM = r.elevation_gain_m.map { "\($0)" } ?? ""
                do {
                    let statsRes = try await SupabaseManager.shared.client
                        .from("cardio_session_stats")
                        .select("stats")
                        .eq("session_id", value: r.id)
                        .single()
                        .execute()

                    struct StatsWire: Decodable {
                        struct StatsBody: Decodable {
                            let cadence_rpm: Int?
                            let watts_avg: Int?
                            let incline_pct: Double?
                            let swim_laps: Int?
                            let pool_length_m: Int?
                            let swim_style: String?
                            let split_sec_per_500m: Int?
                            let km_split_pace_sec: [Int]?
                        }
                        let stats: StatsBody?
                    }

                    let stats = try JSONDecoder.supabase().decode(StatsWire.self, from: statsRes.data)

                    if let s = stats.stats {
                        if let v = s.cadence_rpm         { cf.cadenceRpm        = String(v) }
                        if let v = s.watts_avg           { cf.wattsAvg          = String(v) }
                        if let v = s.incline_pct         { cf.inclinePercent    = String(v) }
                        if let v = s.swim_laps           { cf.swimLaps          = String(v) }
                        if let v = s.pool_length_m       { cf.poolLengthM       = String(v) }
                        if let v = s.swim_style, !v.isEmpty { cf.swimStyle     = v }
                        if let v = s.split_sec_per_500m  { cf.splitSecPer500m   = String(v) }
                        if let km = s.km_split_pace_sec, !km.isEmpty {
                            cf.kmSplitsPaceText = CardioKmPaceSplits.formatFieldText(secondsPerKm: km)
                        }
                    }
                } catch {
                }
                draft.cardio = cf
            } catch { return nil }
            
        case "sport":
            do {
                let res = try await SupabaseManager.shared.client
                    .from("sport_sessions")
                    .select("*")
                    .eq("workout_id", value: workoutId)
                    .single()
                    .execute()
                
                struct Row: Decodable {
                    let id: Int
                    let sport: String
                    let duration_sec: Int?
                    let match_result: String?
                    let score_for: Int?
                    let score_against: Int?
                    let match_score_text: String?
                    let location: String?
                    let notes: String?
                }
                let r = try decoder.decode(Row.self, from: res.data)
                
                var sf = SportForm()
                sf.sport = SportType(rawValue: r.sport) ?? .football
                print("[DUP][SPORT] session_id=\(r.id), sport=\(r.sport)")
                sf.durationMin = r.duration_sec.map { "\($0/60)" } ?? ""
                sf.scoreFor = r.score_for.map(String.init) ?? ""
                sf.scoreAgainst = r.score_against.map(String.init) ?? ""
                sf.matchResult = MatchResult(rawValue: r.match_result ?? "") ?? .unfinished
                sf.matchScoreText = r.match_score_text ?? ""
                sf.location = r.location ?? ""
                sf.sessionNotes = r.notes ?? ""
                draft.sport = sf
                
                let q = try await SupabaseManager.shared.client
                    .from("vw_sport_session_full")
                    .select("*")
                    .eq("workout_id", value: workoutId)
                    .single()
                    .execute()
                
                struct Full: Decodable {
                    let session_id: Int
                    let sport: String
                    let duration_sec: Int?
                    let match_result: String?
                    let score_for: Int?
                    let score_against: Int?
                    let match_score_text: String?
                    let location: String?
                    let session_notes: String?
                    let rk_mode: String?
                    let rk_format: String?
                    let rk_sets_won: Int?
                    let rk_sets_lost: Int?
                    let rk_games_won: Int?
                    let rk_games_lost: Int?
                    let rk_aces: Int?
                    let rk_double_faults: Int?
                    let rk_winners: Int?
                    let rk_unforced_errors: Int?
                    let rk_break_points_won: Int?
                    let rk_break_points_total: Int?
                    let rk_net_points_won: Int?
                    let rk_net_points_total: Int?
                    let bb_points: Int?
                    let bb_rebounds: Int?
                    let bb_assists: Int?
                    let bb_steals: Int?
                    let bb_blocks: Int?
                    let bb_fg_made: Int?
                    let bb_fg_attempted: Int?
                    let bb_three_made: Int?
                    let bb_three_attempted: Int?
                    let bb_ft_made: Int?
                    let bb_ft_attempted: Int?
                    let bb_turnovers: Int?
                    let bb_fouls: Int?
                    let fb_position: String?
                    let fb_minutes_played: Int?
                    let fb_goals: Int?
                    let fb_assists: Int?
                    let fb_shots_on_target: Int?
                    let fb_passes_completed: Int?
                    let fb_passes_attempted: Int?
                    let fb_tackles: Int?
                    let fb_interceptions: Int?
                    let fb_saves: Int?
                    let fb_yellow_cards: Int?
                    let fb_red_cards: Int?
                    let vb_points: Int?
                    let vb_aces: Int?
                    let vb_blocks: Int?
                    let vb_digs: Int?
                    let hb_position: String?
                    let hb_minutes_played: Int?
                    let hb_goals: Int?
                    let hb_shots: Int?
                    let hb_shots_on_target: Int?
                    let hb_assists: Int?
                    let hb_steals: Int?
                    let hb_blocks: Int?
                    let hb_turnovers_lost: Int?
                    let hb_seven_m_goals: Int?
                    let hb_seven_m_attempts: Int?
                    let hb_saves: Int?
                    let hb_yellow_cards: Int?
                    let hb_two_min_suspensions: Int?
                    let hb_red_cards: Int?
                    let hk_position: String?
                    let hk_minutes_played: Int?
                    let hk_goals: Int?
                    let hk_assists: Int?
                    let hk_shots_on_goal: Int?
                    let hk_plus_minus: Int?
                    let hk_hits: Int?
                    let hk_blocks: Int?
                    let hk_faceoffs_won: Int?
                    let hk_faceoffs_total: Int?
                    let hk_saves: Int?
                    let hk_penalty_minutes: Int?
                    let rg_position: String?
                    let rg_minutes_played: Int?
                    let rg_tries: Int?
                    let rg_conversions_made: Int?
                    let rg_conversions_attempted: Int?
                    let rg_penalty_goals_made: Int?
                    let rg_penalty_goals_attempted: Int?
                    let rg_runs: Int?
                    let rg_meters_gained: Int?
                    let rg_offloads: Int?
                    let rg_tackles_made: Int?
                    let rg_tackles_missed: Int?
                    let rg_turnovers_won: Int?
                    let rg_yellow_cards: Int?
                    let rg_red_cards: Int?
                    let hy_division: String?
                    let hy_category: String?
                    let hy_age_group: String?
                    let hy_official_time_sec: Int?
                    let hy_rank_overall: Int?
                    let hy_rank_category: Int?
                    let hy_no_reps: Int?
                    let hy_penalty_time_sec: Int?
                    let hy_avg_hr: Int?
                    let hy_max_hr: Int?
                }
                
                let full = try JSONDecoder.supabase().decode(Full.self, from: q.data)
                var sf2 = draft.sport ?? SportForm()
                sf2.sport           = SportType(rawValue: full.sport) ?? .football
                sf2.durationMin     = full.duration_sec.map { "\($0/60)" } ?? ""
                sf2.scoreFor        = full.score_for.map(String.init) ?? ""
                sf2.scoreAgainst    = full.score_against.map(String.init) ?? ""
                sf2.matchResult     = MatchResult(rawValue: full.match_result ?? "") ?? .unfinished
                sf2.matchScoreText  = full.match_score_text ?? ""
                sf2.location        = full.location ?? ""
                sf2.sessionNotes    = full.session_notes ?? ""
                
                if ["padel","tennis","badminton","squash","table_tennis"].contains(full.sport) {
                    sf2.racket = RacketStatsForm(
                        mode: full.rk_mode ?? "",
                        format: full.rk_format ?? "",
                        setsWon: (full.rk_sets_won ?? 0).description,
                        setsLost: (full.rk_sets_lost ?? 0).description,
                        gamesWon: (full.rk_games_won ?? 0).description,
                        gamesLost: (full.rk_games_lost ?? 0).description,
                        aces: (full.rk_aces ?? 0).description,
                        doubleFaults: (full.rk_double_faults ?? 0).description,
                        winners: (full.rk_winners ?? 0).description,
                        unforcedErrors: (full.rk_unforced_errors ?? 0).description,
                        breakPointsWon: (full.rk_break_points_won ?? 0).description,
                        breakPointsTotal: (full.rk_break_points_total ?? 0).description,
                        netPointsWon: (full.rk_net_points_won ?? 0).description,
                        netPointsTotal: (full.rk_net_points_total ?? 0).description
                    )
                }
                
                if full.sport == "basketball" {
                    sf2.basketball = BasketballStatsForm(
                        points: (full.bb_points ?? 0).description,
                        rebounds: (full.bb_rebounds ?? 0).description,
                        assists: (full.bb_assists ?? 0).description,
                        steals: (full.bb_steals ?? 0).description,
                        blocks: (full.bb_blocks ?? 0).description,
                        fgMade: (full.bb_fg_made ?? 0).description,
                        fgAttempted: (full.bb_fg_attempted ?? 0).description,
                        threeMade: (full.bb_three_made ?? 0).description,
                        threeAttempted: (full.bb_three_attempted ?? 0).description,
                        ftMade: (full.bb_ft_made ?? 0).description,
                        ftAttempted: (full.bb_ft_attempted ?? 0).description,
                        turnovers: (full.bb_turnovers ?? 0).description,
                        fouls: (full.bb_fouls ?? 0).description
                    )
                }
                
                if full.sport == "football" {
                    sf2.football = FootballStatsForm(
                        position: full.fb_position ?? "",
                        minutesPlayed: (full.fb_minutes_played ?? 0).description,
                        goals: (full.fb_goals ?? 0).description,
                        assists: (full.fb_assists ?? 0).description,
                        shotsOnTarget: (full.fb_shots_on_target ?? 0).description,
                        passesCompleted: (full.fb_passes_completed ?? 0).description,
                        passesAttempted: (full.fb_passes_attempted ?? 0).description,
                        tackles: (full.fb_tackles ?? 0).description,
                        interceptions: (full.fb_interceptions ?? 0).description,
                        saves: (full.fb_saves ?? 0).description,
                        yellowCards: (full.fb_yellow_cards ?? 0).description,
                        redCards: (full.fb_red_cards ?? 0).description
                    )
                }
                
                if full.sport == "volleyball" {
                    sf2.volleyball = VolleyballStatsForm(
                        points: (full.vb_points ?? 0).description,
                        aces: (full.vb_aces ?? 0).description,
                        blocks: (full.vb_blocks ?? 0).description,
                        digs: (full.vb_digs ?? 0).description
                    )
                }
                
                if full.sport == "handball" {
                    sf2.hbPosition       = full.hb_position ?? ""
                    sf2.hbGoals          = (full.hb_goals ?? 0).description
                    sf2.hbShots          = (full.hb_shots ?? 0).description
                    sf2.hbShotsOnTarget  = (full.hb_shots_on_target ?? 0).description
                    sf2.hbAssists        = (full.hb_assists ?? 0).description
                    sf2.hbSteals         = (full.hb_steals ?? 0).description
                    sf2.hbBlocks         = (full.hb_blocks ?? 0).description
                    sf2.hbTurnoversLost  = (full.hb_turnovers_lost ?? 0).description
                    sf2.hbSevenMGoals    = (full.hb_seven_m_goals ?? 0).description
                    sf2.hbSevenMAttempts = (full.hb_seven_m_attempts ?? 0).description
                    sf2.hbSaves          = (full.hb_saves ?? 0).description
                    sf2.hbYellow         = (full.hb_yellow_cards ?? 0).description
                    sf2.hbTwoMin         = (full.hb_two_min_suspensions ?? 0).description
                    sf2.hbRed            = (full.hb_red_cards ?? 0).description
                }
                
                if full.sport == "hockey" {
                    sf2.hkPosition      = full.hk_position ?? ""
                    sf2.hkGoals         = (full.hk_goals ?? 0).description
                    sf2.hkAssists       = (full.hk_assists ?? 0).description
                    sf2.hkShotsOnGoal   = (full.hk_shots_on_goal ?? 0).description
                    sf2.hkPlusMinus     = (full.hk_plus_minus ?? 0).description
                    sf2.hkHits          = (full.hk_hits ?? 0).description
                    sf2.hkBlocks        = (full.hk_blocks ?? 0).description
                    sf2.hkFaceoffsWon   = (full.hk_faceoffs_won ?? 0).description
                    sf2.hkFaceoffsTotal = (full.hk_faceoffs_total ?? 0).description
                    sf2.hkSaves         = (full.hk_saves ?? 0).description
                    sf2.hkPenaltyMinutes = (full.hk_penalty_minutes ?? 0).description
                }
                
                if full.sport == "rugby" {
                    sf2.rgPosition             = full.rg_position ?? ""
                    sf2.rgTries                = (full.rg_tries ?? 0).description
                    sf2.rgConversionsMade      = (full.rg_conversions_made ?? 0).description
                    sf2.rgConversionsAttempted = (full.rg_conversions_attempted ?? 0).description
                    sf2.rgPenaltyGoalsMade     = (full.rg_penalty_goals_made ?? 0).description
                    sf2.rgPenaltyGoalsAttempted = (full.rg_penalty_goals_attempted ?? 0).description
                    sf2.rgRuns                 = (full.rg_runs ?? 0).description
                    sf2.rgMetersGained         = (full.rg_meters_gained ?? 0).description
                    sf2.rgOffloads             = (full.rg_offloads ?? 0).description
                    sf2.rgTacklesMade          = (full.rg_tackles_made ?? 0).description
                    sf2.rgTacklesMissed        = (full.rg_tackles_missed ?? 0).description
                    sf2.rgTurnoversWon         = (full.rg_turnovers_won ?? 0).description
                    sf2.rgYellow               = (full.rg_yellow_cards ?? 0).description
                    sf2.rgRed                  = (full.rg_red_cards ?? 0).description
                }
                
                if full.sport == "hyrox" {
                    sf2.hyDivision        = full.hy_division ?? ""
                    sf2.hyCategory        = full.hy_category ?? ""
                    sf2.hyAgeGroup        = full.hy_age_group ?? ""
                    sf2.hyOfficialTimeSec = full.hy_official_time_sec.map(String.init) ?? ""
                    sf2.hyRankOverall     = full.hy_rank_overall.map(String.init) ?? ""
                    sf2.hyRankCategory    = full.hy_rank_category.map(String.init) ?? ""
                    sf2.hyNoReps          = full.hy_no_reps.map(String.init) ?? ""
                    sf2.hyPenaltyTimeSec  = full.hy_penalty_time_sec.map(String.init) ?? ""
                    sf2.hyAvgHR           = full.hy_avg_hr.map(String.init) ?? ""
                    sf2.hyMaxHR           = full.hy_max_hr.map(String.init) ?? ""

                    do {
                        let hyExRes = try await SupabaseManager.shared.client
                            .from("hyrox_session_exercises")
                            .select("*")
                            .eq("session_id", value: full.session_id)
                            .order("exercise_order", ascending: true)
                            .execute()

                        struct HyExRow: Decodable {
                            let exercise_code: String
                            let exercise_order: Int
                            let zone_order: Int?
                            let distance_m: Int?
                            let reps: Int?
                            let weight_kg: Decimal?
                            let duration_sec: Int?
                            let height_cm: Int?
                            let implement_count: Int?
                            let notes: String?
                            let exercise_display_name: String?
                        }

                        let hyRows = try decoder.decode([HyExRow].self, from: hyExRes.data)

                        sf2.hyExercises = hyRows.map { row in
                            let fields = HyroxExerciseFormatting.formFields(
                                exerciseCode: row.exercise_code,
                                exerciseDisplayName: row.exercise_display_name
                            )
                            return HyroxExerciseForm(
                                exerciseCode: fields.code,
                                customDisplayName: fields.customDisplayName,
                                exerciseOrder: row.exercise_order,
                                zoneOrder: row.zone_order.map { max(1, $0) },
                                distanceM: row.distance_m.map(String.init) ?? "",
                                reps: row.reps.map(String.init) ?? "",
                                weightKg: row.weight_kg.map { "\(NSDecimalNumber(decimal: $0).doubleValue)" } ?? "",
                                durationSec: row.duration_sec.map(String.init) ?? "",
                                heightCm: row.height_cm.map(String.init) ?? "",
                                implementCount: row.implement_count.map(String.init) ?? "",
                                notes: row.notes ?? ""
                            )
                        }
                    } catch {
                        sf2.hyExercises = []
                    }
                }
                
                if full.sport == "ski" {
                    do {
                        let skiRes = try await SupabaseManager.shared.client
                            .from("ski_session_stats")
                            .select("*")
                            .eq("session_id", value: full.session_id)
                            .single()
                            .execute()
                        struct SkiRow: Decodable {
                            let total_distance_km: Decimal?
                            let runs_count: Int?
                            let max_speed_kmh: Decimal?
                            let avg_speed_kmh: Decimal?
                            let vertical_drop_m: Int?
                            let moving_time_sec: Int?
                            let paused_time_sec: Int?
                            let resort_name: String?
                            let snow_condition: String?
                            let weather: String?
                        }
                        let skiRow = try decoder.decode(SkiRow.self, from: skiRes.data)
                        sf2.skiTotalDistanceKm = skiRow.total_distance_km.map { "\(NSDecimalNumber(decimal: $0).doubleValue)" } ?? ""
                        sf2.skiRunsCount = skiRow.runs_count.map(String.init) ?? ""
                        sf2.skiMaxSpeedKmh = skiRow.max_speed_kmh.map { "\(NSDecimalNumber(decimal: $0).doubleValue)" } ?? ""
                        sf2.skiAvgSpeedKmh = skiRow.avg_speed_kmh.map { "\(NSDecimalNumber(decimal: $0).doubleValue)" } ?? ""
                        sf2.skiVerticalDropM = skiRow.vertical_drop_m.map(String.init) ?? ""
                        sf2.skiMovingTimeSec = skiRow.moving_time_sec.map(String.init) ?? ""
                        sf2.skiPausedTimeSec = skiRow.paused_time_sec.map(String.init) ?? ""
                        sf2.skiResortName = skiRow.resort_name ?? ""
                        sf2.skiSnowCondition = skiRow.snow_condition ?? ""
                        sf2.skiWeather = skiRow.weather ?? ""
                    } catch {
                        print("[DUP][SPORT] Ski stats load failed: \(error)")
                    }
                }
                
                draft.sport = sf2
            } catch { return nil }
            
        default: break
        }
        
        do {
            let partRes = try await SupabaseManager.shared.client
                .from("workout_participants")
                .select("user_id, profiles!workout_participants_user_id_fkey(username, avatar_url)")
                .eq("workout_id", value: workoutId)
                .execute()
            
            struct PWire: Decodable {
                let user_id: UUID
                let profiles: Profile?
                struct Profile: Decodable { let username: String?; let avatar_url: String? }
            }
            let rows = try JSONDecoder.supabase().decode([PWire].self, from: partRes.data)
            let mapped = rows.map {
                LightweightProfile(user_id: $0.user_id,
                                   username: $0.profiles?.username,
                                   avatar_url: $0.profiles?.avatar_url)
            }
            let unique = Dictionary(grouping: mapped, by: { $0.user_id }).compactMap { $0.value.first }
            draft.participants = unique
            if let me = app.userId, me != ownerId {
                let amIParticipant = draft.participants.contains { $0.user_id == me }
                if amIParticipant {
                    draft.participants.removeAll { $0.user_id == me }
                    let ownerAsParticipant = LightweightProfile(
                        user_id: ownerId,
                        username: profile?.username,
                        avatar_url: profile?.avatar_url
                    )
                    if !draft.participants.contains(where: { $0.user_id == ownerId }) {
                        draft.participants.append(ownerAsParticipant)
                    }
                }
            }
        } catch {
            draft.participants = []
        }
        return draft
    }
    
    struct CompareCandidate: Decodable, Identifiable {
        let candidate_id: Int
        let title: String?
        let kind: String
        let sport: String?
        let activity: String?
        let started_at: Date
        let owner_username: String?
        var id: Int { candidate_id }

        var displayTitle: String {
            if let t = title, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return t }
            if kind == "sport"  { return (sport ?? "Sport").replacingOccurrences(of: "_", with: " ").capitalized }
            if kind == "cardio" { return (activity ?? "Cardio").replacingOccurrences(of: "_", with: " ").capitalized }
            return "Workout"
        }
        
        func withOwnerUsername(_ name: String?) -> CompareCandidate {
            CompareCandidate(
                candidate_id: candidate_id,
                title: title,
                kind: kind,
                sport: sport,
                activity: activity,
                started_at: started_at,
                owner_username: name ?? owner_username
            )
        }
    }
    
    private struct CanCompareParams: Encodable {
        let p_viewer: UUID
        let p_workout: Int
    }

    private func enrichCompareCandidatesWithOwnerUsernames(_ rows: [CompareCandidate]) async -> [CompareCandidate] {
        guard !rows.isEmpty else { return rows }
        let ids = rows.map(\.candidate_id)
        let decoder = JSONDecoder.supabase()
        do {
            let wRes = try await SupabaseManager.shared.client
                .from("workouts")
                .select("id, user_id")
                .in("id", values: ids)
                .execute()
            struct WO: Decodable { let id: Int; let user_id: UUID }
            let owners = try decoder.decode([WO].self, from: wRes.data)
            let idToUser = Dictionary(uniqueKeysWithValues: owners.map { ($0.id, $0.user_id) })
            let uids = Array(Set(owners.map(\.user_id)))
            guard !uids.isEmpty else { return rows }
            let pRes = try await SupabaseManager.shared.client
                .from("profiles")
                .select("user_id, username")
                .in("user_id", values: uids.map(\.uuidString))
                .execute()
            struct PR: Decodable { let user_id: UUID; let username: String? }
            let profs = try decoder.decode([PR].self, from: pRes.data)
            let uidToName: [UUID: String] = Dictionary(
                uniqueKeysWithValues: profs.compactMap { p in
                    guard let u = p.username, !u.isEmpty else { return nil }
                    return (p.user_id, u)
                }
            )
            return rows.map { r in
                guard let uid = idToUser[r.candidate_id], let un = uidToName[uid] else { return r }
                return r.withOwnerUsername(un)
            }
        } catch {
            return rows
        }
    }
    
    private func loadCompareCandidates() async {
        guard let me = app.userId else {
            await MainActor.run {
                compareCandidates = []
                compareCandidateId = nil
                compareReady = false
            }
            return
        }
        if compareComputing { return }
        await MainActor.run { compareComputing = true }
        defer { Task { await MainActor.run { compareComputing = false } } }

        do {
            struct Params: Encodable { let p_viewer: UUID; let p_workout: Int; let p_limit: Int }
            let res = try await SupabaseManager.shared.client
                .rpc("list_comparable_workouts_v1",
                     params: Params(p_viewer: me, p_workout: workoutId, p_limit: 120))
                .execute()
            var rows = try JSONDecoder.supabase().decode([CompareCandidate].self, from: res.data)
            rows = await enrichCompareCandidatesWithOwnerUsernames(rows)
            rows = await CompareWorkoutCandidateOrdering.sortForPicker(
                rows,
                baselineWorkoutId: workoutId,
                kind: workout?.kind ?? ""
            )
            let typeLabel: String = {
                guard let w = workout else { return "Workout" }
                return CompareAveragePoolLoader.typeLabel(for: w)
            }()
            let (mine, global) = await CompareAveragePoolLoader.loadPickerAverages(
                baselineWorkoutId: workoutId,
                typeLabel: typeLabel
            )
            let picker = ComparePickerState(
                sessions: rows,
                myAverage: mine,
                globalAverage: global
            )
            await MainActor.run {
                compareCandidates = rows
                comparePicker = picker
                compareCandidateId = rows.first?.id
                compareReady = picker.hasAnyOption
            }
        } catch {
            await MainActor.run {
                compareCandidates = []
                compareCandidateId = nil
                compareReady = false
            }
        }
    }
    
    private struct CanCompareRes: Decodable {
        let viewer_can_compare_with_owner: Bool
        let viewer_has_comparable_workout: Bool
        let target_kind: String?
        let target_sport: String?
        let target_activity: String?
        let target_title: String?
        let sample_viewer_match_id: Int?
    }
    
    private func computeCompareCandidate() async {
        guard let me = app.userId else {
            await MainActor.run { compareReady = false; compareCandidateId = nil }
            return
        }
        guard workout != nil else {
            await MainActor.run { compareReady = false; compareCandidateId = nil }
            return
        }
        if compareComputing { return }
        await MainActor.run { compareComputing = true }
        defer { Task { await MainActor.run { compareComputing = false } } }

        do {
            let params = CanCompareParams(p_viewer: me, p_workout: workoutId)
            let res = try await SupabaseManager.shared.client
                .rpc("can_compare_workout_v1", params: params)
                .execute()

            let rows = try JSONDecoder.supabase().decode([CanCompareRes].self, from: res.data)
            let r = rows.first

            let candidate = (r?.sample_viewer_match_id != nil && r?.sample_viewer_match_id != workoutId)
                ? r?.sample_viewer_match_id
                : nil
            let ready = (r?.viewer_can_compare_with_owner == true)
                     && (r?.viewer_has_comparable_workout == true)
                     && (candidate != nil)

            await MainActor.run {
                compareCandidateId = candidate
                compareReady = ready
            }
        } catch {
            await MainActor.run {
                compareCandidateId = nil
                compareReady = false
            }
        }
    }

}

private struct DetailMetric: Identifiable {
    let id = UUID()
    let label: String
    let value: String
    let systemImage: String?

    init(_ label: String, _ value: String, systemImage: String? = nil) {
        self.label = label
        self.value = value
        self.systemImage = systemImage
    }
}

private struct DetailSectionCard<Content: View>: View {
    let title: String
    let subtitle: String?
    let content: Content

    init(title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            content
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.18)))
    }
}

private struct DetailStatRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.subheadline.weight(.semibold))
            Spacer(minLength: 12)
            Text(value)
                .font(.subheadline)
                .multilineTextAlignment(.trailing)
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct DetailMetricGrid: View {
    let metrics: [DetailMetric]

    private var columns: [GridItem] {
        [GridItem(.flexible()), GridItem(.flexible())]
    }

    var body: some View {
        if !metrics.isEmpty {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(metrics) { metric in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            if let systemImage = metric.systemImage {
                                Image(systemName: systemImage)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            Text(metric.label)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        Text(metric.value)
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }
}

private struct DetailEmptyState: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 12)
    }
}

private func detailTrimmed(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

private func detailPositiveInt(_ value: Int?) -> Int? {
    guard let value, value > 0 else { return nil }
    return value
}

private func detailNonZeroInt(_ value: Int?) -> Int? {
    guard let value, value != 0 else { return nil }
    return value
}

private func detailPositiveDecimalDouble(_ value: Decimal?) -> Double? {
    guard let value else { return nil }
    let doubleValue = NSDecimalNumber(decimal: value).doubleValue
    return doubleValue > 0 ? doubleValue : nil
}

private func detailRatio(_ made: Int?, _ total: Int?) -> String? {
    let madeValue = made ?? 0
    let totalValue = total ?? 0
    guard madeValue != 0 || totalValue != 0 else { return nil }
    return "\(madeValue)/\(totalValue)"
}

private func detailPair(_ left: Int?, _ right: Int?, separator: String = "–") -> String? {
    let leftValue = left ?? 0
    let rightValue = right ?? 0
    guard leftValue != 0 || rightValue != 0 else { return nil }
    return "\(leftValue)\(separator)\(rightValue)"
}

private func detailLabel(_ value: String) -> String {
    value.replacingOccurrences(of: "_", with: " ").capitalized
}

private struct StrengthDetailBlock: View {
    let workoutId: Int
    let reloadKey: UUID
    
    private struct ExerciseRow: Decodable, Identifiable {
        let id: Int
        let exercise_id: Int64
        let order_index: Int
        let superset_group_id: UUID?
        let superset_position: Int?
        let notes: String?
        let custom_name: String?
        let exercise_name: String?
    }
    
    private struct SetRow: Decodable, Identifiable {
        let id: Int
        let workout_exercise_id: Int
        let set_number: Int
        let order_index: Int?
        let reps: Int?
        let weight_kg: Decimal?
        let rpe: Decimal?
        let rest_sec: Int?
        let notes: String?
        let weight_segments: [StrengthWeightSegWire]?
    }

    private struct ExerciseDisplayBlock: Identifiable {
        let id: String
        let title: String?
        let exercises: [ExerciseRow]

        var isSuperset: Bool {
            exercises.count > 1
        }
    }
    
    @State private var exercises: [ExerciseRow] = []
    @State private var setsByExercise: [Int: [SetRow]] = [:]
    @State private var totalVolumeKg: Double?
    @State private var loading = false
    @State private var error: String?
    
    var body: some View {
        DetailSectionCard(title: "Strength", subtitle: nil) {
            if loading && exercises.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            } else if let error, exercises.isEmpty {
                DetailEmptyState(
                    title: "Could not load strength details",
                    message: error,
                    systemImage: "exclamationmark.triangle"
                )
            } else if exercises.isEmpty {
                DetailEmptyState(
                    title: "No exercises yet",
                    message: "This workout does not have any exercises attached.",
                    systemImage: "dumbbell"
                )
            } else {
                DetailMetricGrid(metrics: strengthMetrics)

                ForEach(exerciseDisplayBlocks) { block in
                    if block.isSuperset {
                        supersetExerciseCard(block)
                    } else if let ex = block.exercises.first {
                        exerciseCard(ex)
                    }
                }
            }
        }
        .task { await load() }
        .onChange(of: reloadKey) { _, _ in
            Task { await load() }
        }
    }

    private var allSets: [SetRow] {
        setsByExercise.values.flatMap { $0 }
    }

    private var strengthAggregates: StrengthDetailAggregates {
        strengthDetailAggregates(
            setsByExercise: setsByExercise,
            orderIndex: { $0.order_index },
            id: { $0.id },
            setNumber: { $0.set_number },
            reps: { $0.reps },
            rpe: { $0.rpe }
        )
    }

    private var strengthMetrics: [DetailMetric] {
        var metrics: [DetailMetric] = []
        if !exercises.isEmpty {
            metrics.append(DetailMetric("Exercises", "\(exercises.count)", systemImage: "list.bullet"))
        }
        let agg = strengthAggregates
        if agg.totalSets > 0 {
            metrics.append(DetailMetric("Sets", "\(agg.totalSets)", systemImage: "number"))
        }
        if agg.totalReps > 0 {
            metrics.append(DetailMetric("Reps", "\(agg.totalReps)", systemImage: "repeat"))
        }
        if let totalVolumeKg, totalVolumeKg > 0 {
            metrics.append(DetailMetric("Volume", String(format: "%.1f kg", totalVolumeKg), systemImage: "scalemass"))
        }
        let maxWeight = allSets.compactMap { detailPositiveDecimalDouble($0.weight_kg) }.max()
        if let maxWeight {
            metrics.append(DetailMetric("Top weight", String(format: "%.1f kg", maxWeight), systemImage: "arrow.up"))
        }
        if let avgRpe = agg.avgRpe {
            metrics.append(DetailMetric("Avg RPE", String(format: "%.1f", avgRpe), systemImage: "gauge.medium"))
        }
        return metrics
    }

    private var exerciseDisplayBlocks: [ExerciseDisplayBlock] {
        var blocks: [ExerciseDisplayBlock] = []
        let ordered = exercises.sorted { lhs, rhs in
            if lhs.order_index != rhs.order_index { return lhs.order_index < rhs.order_index }
            return lhs.id < rhs.id
        }
        var idx = 0
        while idx < ordered.count {
            let current = ordered[idx]
            guard let groupId = current.superset_group_id else {
                blocks.append(ExerciseDisplayBlock(id: "exercise-\(current.id)", title: nil, exercises: [current]))
                idx += 1
                continue
            }

            var group: [ExerciseRow] = [current]
            var nextIdx = idx + 1
            while nextIdx < ordered.count, ordered[nextIdx].superset_group_id == groupId {
                group.append(ordered[nextIdx])
                nextIdx += 1
            }

            if group.count > 1 {
                let sortedGroup = group.sorted {
                    let lp = $0.superset_position ?? Int.max
                    let rp = $1.superset_position ?? Int.max
                    if lp != rp { return lp < rp }
                    if $0.order_index != $1.order_index { return $0.order_index < $1.order_index }
                    return $0.id < $1.id
                }
                blocks.append(
                    ExerciseDisplayBlock(
                        id: "superset-\(groupId.uuidString)",
                        title: "Superserie",
                        exercises: sortedGroup
                    )
                )
            } else {
                blocks.append(ExerciseDisplayBlock(id: "exercise-\(current.id)", title: nil, exercises: [current]))
            }

            idx = nextIdx
        }
        return blocks
    }

    private func supersetExerciseCard(_ block: ExerciseDisplayBlock) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "link")
                    .font(.caption.weight(.semibold))
                Text(block.title ?? "Superserie")
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }
            .foregroundStyle(.blue)

            ForEach(Array(block.exercises.enumerated()), id: \.element.id) { offset, ex in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(supersetPositionLabel(offset))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.blue)
                        Text(exerciseDisplayName(ex))
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                    }
                    if let exNotes = ex.notes, !exNotes.isEmpty {
                        Text(exNotes).font(.caption).foregroundStyle(.secondary)
                    }
                    exerciseSetsSummary(ex)
                }
                .padding(10)
                .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.blue.opacity(0.25), lineWidth: 1))
    }

    private func exerciseCard(_ ex: ExerciseRow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(exerciseDisplayName(ex))
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }
            if let exNotes = ex.notes, !exNotes.isEmpty {
                Text(exNotes).font(.caption).foregroundStyle(.secondary)
            }
            exerciseSetsSummary(ex)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.12)))
    }

    private func exerciseDisplayName(_ ex: ExerciseRow) -> String {
        ex.custom_name?.isEmpty == false ? ex.custom_name! : (ex.exercise_name ?? "Exercise #\(ex.exercise_id)")
    }

    private func supersetPositionLabel(_ offset: Int) -> String {
        let letter = Character(UnicodeScalar(65 + min(max(offset, 0), 25))!)
        return "\(letter)1"
    }

    private func exerciseSetsSummary(_ ex: ExerciseRow) -> some View {
        let rows = setsByExercise[ex.id] ?? []
        let paired = strengthSetRowsWithMultiplicities(
            rows,
            orderIndex: { $0.order_index },
            id: { $0.id },
            setNumber: { $0.set_number }
        )
        return Group {
            if paired.isEmpty {
                Text("No sets").font(.caption).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(paired.enumerated()), id: \.element.row.id) { offset, item in
                        let s = item.row
                        let mult = item.multiplier
                        let lineOrdinal = s.order_index ?? (offset + 1)
                        let dropSummary: String? = {
                            guard let ws = s.weight_segments, ws.count >= 2 else { return nil }
                            return ws.map { "\($0.reps)×\(String(format: "%.1f", $0.weight_kg))" }.joined(separator: " → ")
                        }()
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 12) {
                                Text("#\(lineOrdinal)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 26, alignment: .leading)
                                if let ds = dropSummary {
                                    Text(strengthSetSummaryText(dropSummary: ds, set: s, multiplier: mult))
                                        .font(.footnote)
                                } else {
                                    let summary = strengthSetSummaryText(dropSummary: nil, set: s, multiplier: mult)
                                    if summary.isEmpty {
                                        Text("No set data")
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    } else {
                                        Text(summary)
                                            .font(.footnote)
                                    }
                                }
                                Spacer()
                            }
                            if let notes = detailTrimmed(s.notes) {
                                Text(notes)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(8)
                        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
    }

    private func strengthSetSummaryText(dropSummary: String?, set s: SetRow, multiplier mult: Int) -> String {
        let body: String
        if let dropSummary {
            body = dropSummary
        } else {
            let parts = setSummaryParts(s)
            guard !parts.isEmpty else { return "" }
            body = parts.joined(separator: " • ")
        }
        if mult > 1 {
            return "\(mult)× · \(body)"
        }
        return body
    }

    private func setSummaryParts(_ s: SetRow) -> [String] {
        var parts: [String] = []
        if let reps = detailPositiveInt(s.reps) {
            parts.append("\(reps) reps")
        }
        if let weight = detailPositiveDecimalDouble(s.weight_kg) {
            parts.append(String(format: "%.1f kg", weight))
        }
        if let rpe = detailPositiveDecimalDouble(s.rpe) {
            parts.append(String(format: "RPE %.1f", rpe))
        }
        if let rest = detailPositiveInt(s.rest_sec) {
            parts.append("Rest \(rest)s")
        }
        return parts
    }
    
    private func load() async {
        loading = true; defer { loading = false }
        do {
            let exQ = try await SupabaseManager.shared.client
                .from("workout_exercises")
                .select("id, exercise_id, order_index, superset_group_id, superset_position, notes, custom_name, exercises(name)")
                .eq("workout_id", value: workoutId)
                .order("order_index", ascending: true)
                .execute()
            
            struct ExWire: Decodable {
                let id: Int
                let exercise_id: Int64
                let order_index: Int
                let superset_group_id: UUID?
                let superset_position: Int?
                let notes: String?
                let custom_name: String?
                let exercises: ExName?
                struct ExName: Decodable { let name: String? }
            }
            let exWire = try JSONDecoder.supabase().decode([ExWire].self, from: exQ.data)
            let exRows: [ExerciseRow] = exWire.map {
                .init(
                    id: $0.id,
                    exercise_id: $0.exercise_id,
                    order_index: $0.order_index,
                    superset_group_id: $0.superset_group_id,
                    superset_position: $0.superset_position,
                    notes: $0.notes,
                    custom_name: $0.custom_name,
                    exercise_name: $0.exercises?.name
                )
            }
            await MainActor.run { exercises = exRows }
            
            let ids = exRows.map { $0.id }
            var byEx: [Int: [SetRow]] = [:]
            if !ids.isEmpty {
                let setData: Data
                do {
                    setData = try await SupabaseManager.shared.client
                        .from("exercise_sets")
                        .select("id, workout_exercise_id, set_number, order_index, reps, weight_kg, rpe, rest_sec, notes, weight_segments")
                        .in("workout_exercise_id", values: ids)
                        .order("order_index", ascending: true)
                        .order("id", ascending: true)
                        .execute()
                        .data
                } catch {
                    setData = try await SupabaseManager.shared.client
                        .from("exercise_sets")
                        .select("id, workout_exercise_id, set_number, reps, weight_kg, rpe, rest_sec, notes, weight_segments")
                        .in("workout_exercise_id", values: ids)
                        .order("set_number", ascending: true)
                        .order("id", ascending: true)
                        .execute()
                        .data
                }
                let sets = try JSONDecoder.supabase().decode([SetRow].self, from: setData)
                for s in sets { byEx[s.workout_exercise_id, default: []].append(s) }
            }
            
            var vol: Double? = nil
            do {
                let vRes = try await SupabaseManager.shared.client
                    .from("vw_workout_volume")
                    .select("total_volume_kg")
                    .eq("workout_id", value: workoutId)
                    .single()
                    .execute()
                struct V: Decodable { let total_volume_kg: Decimal? }
                let v = try JSONDecoder.supabase().decode(V.self, from: vRes.data)
                vol = v.total_volume_kg.map { NSDecimalNumber(decimal: $0).doubleValue }
            } catch {
                vol = nil
            }
            
            let cachedExercises = exRows.map {
                WorkoutProgramCache.CachedExercise(
                    id: $0.id,
                    exercise_id: $0.exercise_id,
                    order_index: $0.order_index,
                    superset_group_id: $0.superset_group_id,
                    superset_position: $0.superset_position,
                    notes: $0.notes,
                    custom_name: $0.custom_name,
                    exercise_name: $0.exercise_name
                )
            }
            let cachedSets = byEx.mapValues { rows in
                rows.map {
                    WorkoutProgramCache.CachedSet(
                        id: $0.id,
                        workout_exercise_id: $0.workout_exercise_id,
                        set_number: $0.set_number,
                        order_index: $0.order_index,
                        reps: $0.reps,
                        weight_kg: $0.weight_kg,
                        rpe: $0.rpe,
                        rest_sec: $0.rest_sec,
                        notes: $0.notes
                    )
                }
            }
            WorkoutProgramCache.store(
                workoutId: workoutId,
                exercises: cachedExercises,
                setsByExerciseId: cachedSets
            )

            await MainActor.run {
                setsByExercise = byEx
                totalVolumeKg = vol
                error = nil
            }
        } catch {
            await MainActor.run { self.error = error.localizedDescription }
        }
    }
    
}

private enum CardioRouteGeoJSONParser {
    private struct LineStringBody: Decodable {
        let type: String
        let coordinates: [[Double]]
    }

    static func coordinates(from json: String?) -> [CLLocationCoordinate2D] {
        guard let json, let data = json.data(using: .utf8) else { return [] }
        guard let obj = try? JSONDecoder().decode(LineStringBody.self, from: data),
              obj.type.lowercased() == "linestring",
              obj.coordinates.count >= 2
        else { return [] }
        return obj.coordinates.compactMap { pair in
            guard pair.count >= 2 else { return nil }
            let lon = pair[0]
            let lat = pair[1]
            guard (-90...90).contains(lat), (-180...180).contains(lon) else { return nil }
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
    }
}

private struct CardioRouteMapMini: View {
    let coordinates: [CLLocationCoordinate2D]
    let territoryFillRings: [[CLLocationCoordinate2D]]
    let territorySampleCells: [TerritoryPreviewCell]
    @State private var position: MapCameraPosition = .automatic
    @State private var showExpanded = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Map(position: $position) {
                ForEach(Array(territoryFillRings.enumerated()), id: \.offset) { _, ring in
                    if ring.count >= 3 {
                        MapPolygon(coordinates: ring)
                            .foregroundStyle(Color.green.opacity(0.22))
                    }
                }
                ForEach(territorySampleCells) { cell in
                    let ring = cell.cell_geojson?.ring ?? []
                    if ring.count >= 3 {
                        MapPolygon(coordinates: ring)
                            .foregroundStyle(Color.green.opacity(0.18))
                    }
                }
                MapPolyline(coordinates: coordinates)
                    .stroke(.blue.opacity(0.88), lineWidth: 4)
            }
            .mapStyle(.standard(elevation: .flat))
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .onAppear { fitCamera() }
            .onChange(of: coordinates.count) { _, _ in fitCamera() }
            Button {
                fitCamera()
                showExpanded = true
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .padding(8)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .padding(8)
            .accessibilityLabel("Expand map")
        }
        .fullScreenCover(isPresented: $showExpanded) {
            NavigationStack {
                ZStack {
                    Map(position: $position) {
                        ForEach(Array(territoryFillRings.enumerated()), id: \.offset) { _, ring in
                            if ring.count >= 3 {
                                MapPolygon(coordinates: ring)
                                    .foregroundStyle(Color.green.opacity(0.22))
                            }
                        }
                        ForEach(territorySampleCells) { cell in
                            let ring = cell.cell_geojson?.ring ?? []
                            if ring.count >= 3 {
                                MapPolygon(coordinates: ring)
                                    .foregroundStyle(Color.green.opacity(0.18))
                            }
                        }
                        MapPolyline(coordinates: coordinates)
                            .stroke(.blue.opacity(0.88), lineWidth: 4)
                    }
                    .mapStyle(.standard(elevation: .flat))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("Route")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { showExpanded = false }
                    }
                }
                .onAppear { fitCamera() }
                .onChange(of: coordinates.count) { _, _ in fitCamera() }
            }
        }
    }

    private func fitCamera() {
        guard coordinates.count >= 2 else { return }
        var minLat = coordinates[0].latitude
        var maxLat = minLat
        var minLon = coordinates[0].longitude
        var maxLon = minLon
        for c in coordinates {
            minLat = min(minLat, c.latitude)
            maxLat = max(maxLat, c.latitude)
            minLon = min(minLon, c.longitude)
            maxLon = max(maxLon, c.longitude)
        }
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max(0.004, (maxLat - minLat) * 1.4),
            longitudeDelta: max(0.004, (maxLon - minLon) * 1.4)
        )
        position = .region(MKCoordinateRegion(center: center, span: span))
    }
}

private struct CardioDetailBlock: View {
    let workoutId: Int
    let reloadKey: UUID
    let canEdit: Bool
    let workoutState: String?

    @State private var showCreateSegment = false
    @State private var segmentNav: SegmentNavSheet?

    private struct SegmentNavSheet: Identifiable {
        let id: UUID
    }

    private struct CardioRow: Decodable {
        let id: Int
        let activity_code: String?
        let modality: String?
        let distance_km: Decimal?
        let duration_sec: Int?
        let avg_hr: Int?
        let max_hr: Int?
        let avg_pace_sec_per_km: Int?
        let elevation_gain_m: Int?
        let notes: String?
        let route_geojson: String?
    }
    
    @State private var row: CardioRow?
    @State private var loading = false
    @State private var error: String?
    private struct CardioExtras: Decodable {
        let cadence_rpm: Int?
        let watts_avg: Int?
        let incline_pct: Double?
        let swim_laps: Int?
        let pool_length_m: Int?
        let swim_style: String?
        let split_sec_per_500m: Int?
        let km_split_pace_sec: [Int]?
    }
    @State private var extras: CardioExtras?
    @State private var kmPaceSplitsExpanded = false
    @State private var captureEvent: TerritoryCaptureEventRow?
    @State private var territoryFillRings: [[CLLocationCoordinate2D]] = []
    @State private var territorySampleCells: [TerritoryPreviewCell] = []
    @State private var workoutTakeovers: [TerritoryWorkoutTakeoverRow] = []
    @State private var showTerritoryTakeoversSheet = false

    private let maxInlineTerritoryTakeovers = 5

    private var routeCoordinates: [CLLocationCoordinate2D] {
        CardioRouteGeoJSONParser.coordinates(from: row?.route_geojson)
    }

    private var territoryDetailValue: String? {
        guard let gained = captureEvent?.cells_gained, gained > 0 else { return nil }
        return TerritoryCapturePresentation.workoutDetailLabel(
            gained: gained,
            taken: captureEvent?.cells_taken ?? 0
        )
    }

    private var inlineTerritoryTakeovers: [TerritoryWorkoutTakeoverRow] {
        guard (captureEvent?.cells_taken ?? 0) > 0, !workoutTakeovers.isEmpty else { return [] }
        return Array(workoutTakeovers.prefix(maxInlineTerritoryTakeovers))
    }

    private var hiddenTerritoryTakeoverCount: Int {
        max(workoutTakeovers.count - maxInlineTerritoryTakeovers, 0)
    }
    
    var body: some View {
        DetailSectionCard(title: row.map(activityLabel) ?? "Cardio", subtitle: cardioSubtitle) {
            if loading && row == nil {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            } else if let error, row == nil {
                DetailEmptyState(
                    title: "Could not load cardio details",
                    message: error,
                    systemImage: "exclamationmark.triangle"
                )
            } else if let r = row {
                DetailMetricGrid(metrics: cardioMetrics(r))

                if let splits = extras?.km_split_pace_sec?.filter({ $0 > 0 }), !splits.isEmpty {
                    perKmPaceSection(splits: splits)
                }
                if let elev = detailPositiveInt(r.elevation_gain_m) {
                    info("Elevation gain", "\(elev) m")
                }
                cardioSpecificRows(r)

                if routeCoordinates.count < 2, let territoryDetailValue {
                    territorySection(summary: territoryDetailValue)
                }
                if routeCoordinates.count >= 2 {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Route")
                            .font(.subheadline.weight(.semibold))
                        CardioRouteMapMini(
                            coordinates: routeCoordinates,
                            territoryFillRings: territoryFillRings,
                            territorySampleCells: territorySampleCells
                        )
                    }
                    if let territoryDetailValue {
                        territorySection(summary: territoryDetailValue)
                    }
                    if canEdit && workoutState == "published" {
                        Button {
                            showCreateSegment = true
                        } label: {
                            Text("Create segment")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 4)
                    }
                }
                if let n = detailTrimmed(r.notes) {
                    info("Notes", n)
                }
            } else {
                DetailEmptyState(
                    title: "No cardio session linked",
                    message: "This workout does not have cardio details attached.",
                    systemImage: "heart.text.square"
                )
            }
        }
        .task { await load() }
        .onChange(of: reloadKey) { _, _ in
            kmPaceSplitsExpanded = false
            captureEvent = nil
            territoryFillRings = []
            territorySampleCells = []
            workoutTakeovers = []
            Task { await load() }
        }
        .sheet(isPresented: $showTerritoryTakeoversSheet) {
            NavigationStack {
                List(workoutTakeovers) { takeover in
                    territoryTakeoverRow(takeover)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .navigationTitle("Territory taken from")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { showTerritoryTakeoversSheet = false }
                    }
                }
            }
            .presentationBackground(.clear)
        }
        .sheet(isPresented: $showCreateSegment) {
            CreateSegmentFromWorkoutSheet(
                workoutId: workoutId,
                initialRouteCoordinates: routeCoordinates,
                onCreated: { id in
                    showCreateSegment = false
                    segmentNav = SegmentNavSheet(id: id)
                },
                onOpenExistingSegment: { id in
                    showCreateSegment = false
                    segmentNav = SegmentNavSheet(id: id)
                },
                onCancel: { showCreateSegment = false }
            )
            .presentationBackground(.clear)
        }
        .sheet(item: $segmentNav) { nav in
            NavigationStack {
                SegmentDetailView(segmentId: nav.id, onClose: { segmentNav = nil })
            }
            .presentationBackground(.clear)
        }
    }

    private var cardioSubtitle: String? {
        guard let row else { return nil }
        if routeCoordinates.count >= 2 {
            return "Route recorded"
        }
        if detailPositiveDecimalDouble(row.distance_km) != nil {
            return "Distance workout"
        }
        return nil
    }

    private func cardioMetrics(_ r: CardioRow) -> [DetailMetric] {
        var metrics: [DetailMetric] = []
        let swimUnits = CardioSwimDisplay.usesSwimUnits(code: r.activity_code)
        if let d = detailPositiveDecimalDouble(r.distance_km) {
            let distLabel = swimUnits
                ? CardioSwimDisplay.formatSwimDistance(km: d)
                : String(format: "%.2f km", d)
            metrics.append(DetailMetric("Distance", distLabel, systemImage: "point.topleft.down.curvedto.point.bottomright.up"))
        }
        if let s = detailPositiveInt(r.duration_sec) {
            metrics.append(DetailMetric("Duration", durationString(Double(s)), systemImage: "clock"))
        }
        if let p = detailPositiveInt(r.avg_pace_sec_per_km) {
            let paceLabel = swimUnits
                ? CardioSwimDisplay.formatSwimPace(secPerKm: p)
                : paceString(Double(p))
            metrics.append(DetailMetric("Avg pace", paceLabel, systemImage: "speedometer"))
        }
        if let ah = detailPositiveInt(r.avg_hr) {
            metrics.append(DetailMetric("Avg HR", "\(ah) bpm", systemImage: "heart"))
        }
        if let mh = detailPositiveInt(r.max_hr) {
            metrics.append(DetailMetric("Max HR", "\(mh) bpm", systemImage: "heart.fill"))
        }
        return metrics
    }

    @ViewBuilder
    private func cardioSpecificRows(_ r: CardioRow) -> some View {
        if showsCadence(for: r.activity_code), let cad = detailPositiveInt(extras?.cadence_rpm) {
            info("Cadence", "\(cad) \((r.activity_code ?? "") == "rowerg" ? "spm" : "rpm")")
        }
        if showsWatts(for: r.activity_code), let w = detailPositiveInt(extras?.watts_avg) {
            info("Avg watts", "\(w) W")
        }
        if showsIncline(for: r.activity_code), let inc = extras?.incline_pct, inc != 0 {
            info("Incline", String(format: "%.1f %%", inc))
        }
        if showsSplit500m(for: r.activity_code), let split = detailPositiveInt(extras?.split_sec_per_500m) {
            info("Split", "\(liftrMMSS(split)) /500m")
        }
        if showsSwimFields(for: r.activity_code) {
            if let laps = detailPositiveInt(extras?.swim_laps) { info("Laps", "\(laps)") }
            if let len = detailPositiveInt(extras?.pool_length_m) { info("Pool length", "\(len) m") }
            if let st = detailTrimmed(extras?.swim_style) { info("Swim style", st.capitalized) }
        }
    }
    
    private func load() async {
        await MainActor.run {
            loading = true
            error = nil
        }
        defer { Task { await MainActor.run { loading = false } } }
        do {
            let res = try await SupabaseManager.shared.client
                .from("cardio_sessions")
                .select("*")
                .eq("workout_id", value: workoutId)
                .single()
                .execute()
            let r = try JSONDecoder.supabase().decode(CardioRow.self, from: res.data)
            await MainActor.run {
                row = r
                error = nil
                kmPaceSplitsExpanded = false
            }
            do {
                let statsRes = try await SupabaseManager.shared.client
                    .from("cardio_session_stats")
                    .select("stats")
                    .eq("session_id", value: r.id)
                    .single()
                    .execute()

                struct Wire: Decodable { let stats: CardioExtras? }
                let w = try JSONDecoder.supabase().decode(Wire.self, from: statsRes.data)
                await MainActor.run { self.extras = w.stats }
            } catch {
                await MainActor.run { self.extras = nil }
            }
            async let capture = TerritoryCaptureClient.fetchCaptureEvent(workoutId: workoutId)
            async let takeovers = TerritoryCaptureClient.fetchWorkoutTakeovers(workoutId: workoutId)
            let captureEvent = await capture
            let takeoverRows = await takeovers
            let territoryDisplay: TerritoryWorkoutDisplay?
            if (captureEvent?.cells_gained ?? 0) > 0 {
                territoryDisplay = await TerritoryCaptureClient.fetchWorkoutTerritoryDisplay(workoutId: workoutId)
            } else {
                territoryDisplay = nil
            }
            await MainActor.run {
                self.captureEvent = captureEvent
                self.workoutTakeovers = takeoverRows
                self.territoryFillRings = territoryDisplay?.fillRings ?? []
                self.territorySampleCells = territoryDisplay?.sampleCells ?? []
            }
        } catch {
            await MainActor.run {
                self.row = nil
                self.captureEvent = nil
                self.workoutTakeovers = []
                self.territoryFillRings = []
                self.territorySampleCells = []
                self.error = error.localizedDescription
            }
        }
    }

    @ViewBuilder
    private func territorySection(summary: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            info("Territory", summary)
            ForEach(inlineTerritoryTakeovers) { takeover in
                territoryTakeoverRow(takeover)
            }
            if hiddenTerritoryTakeoverCount > 0 {
                Button {
                    showTerritoryTakeoversSheet = true
                } label: {
                    HStack {
                        Text("+\(hiddenTerritoryTakeoverCount) more")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func territoryTakeoverRow(_ takeover: TerritoryWorkoutTakeoverRow) -> some View {
        HStack(spacing: 10) {
            AvatarView(urlString: takeover.victim_avatar_url)
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            if let userId = takeover.victim_user_id {
                NavigationLink {
                    ProfileView(userId: userId).id(userId).gradientBG()
                } label: {
                    Text("@\(takeover.victim_username ?? "user")")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .buttonStyle(.plain)
            } else {
                Text("@\(takeover.victim_username ?? "user")")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if let cells = takeover.cells_taken {
                Text(
                    TerritoryCapturePresentation.takeoverRowSubtitle(
                        cells: cells,
                        sharePct: takeover.share_taken_pct ?? 0
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
            }
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
    
    @ViewBuilder private func info(_ label: String, _ value: String) -> some View {
        DetailStatRow(label: label, value: value)
    }

    @ViewBuilder
    private func perKmPaceSection(splits: [Int]) -> some View {
        if splits.count == 1 {
            info("Per-km pace", "Km 1: \(paceString(Double(splits[0])))")
        } else {
            DisclosureGroup(isExpanded: $kmPaceSplitsExpanded) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(splits.enumerated()), id: \.offset) { idx, sec in
                        HStack(alignment: .firstTextBaseline) {
                            Text("Km \(idx + 1)")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 12)
                            Text(paceString(Double(sec)))
                                .font(.subheadline.monospacedDigit())
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
            } label: {
                HStack(alignment: .center) {
                    Text("Per-km pace")
                        .font(.subheadline.weight(.semibold))
                    Spacer(minLength: 12)
                    if kmPaceSplitsExpanded {
                        Text("\(splits.count) km")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Km 1: \(paceString(Double(splits[0])))")
                                .font(.subheadline)
                                .monospacedDigit()
                            Text("+\(splits.count - 1) more")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(10)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func activityLabel(_ r: CardioRow) -> String {
        let code = (r.activity_code ?? r.modality ?? "cardio")
        return code.replacingOccurrences(of: "_", with: " ").capitalized
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
}

private struct SportDetailBlock: View {
    let workoutId: Int
    let reloadKey: UUID
    let canEdit: Bool
    
    private struct SportRow: Decodable {
        let id: Int
        let sport: String
        let duration_sec: Int?
        let match_result: String?
        let score_for: Int?
        let score_against: Int?
        let match_score_text: String?
        let location: String?
        let notes: String?
    }
    
    private struct FootballStats: Decodable {
        let position: String?
        let minutes_played: Int?
        let goals: Int?
        let assists: Int?
        let shots_on_target: Int?
        let passes_completed: Int?
        let passes_attempted: Int?
        let tackles: Int?
        let interceptions: Int?
        let saves: Int?
        let yellow_cards: Int?
        let red_cards: Int?
    }
    
    private struct BasketballStats: Decodable {
        let points: Int?
        let rebounds: Int?
        let assists: Int?
        let steals: Int?
        let blocks: Int?
        let fg_made: Int?
        let fg_attempted: Int?
        let three_made: Int?
        let three_attempted: Int?
        let ft_made: Int?
        let ft_attempted: Int?
        let turnovers: Int?
        let fouls: Int?
    }
    
    private struct RacketStats: Decodable {
        let mode: String?
        let format: String?
        let sets_won: Int?
        let sets_lost: Int?
        let games_won: Int?
        let games_lost: Int?
        let aces: Int?
        let double_faults: Int?
        let winners: Int?
        let unforced_errors: Int?
        let break_points_won: Int?
        let break_points_total: Int?
        let net_points_won: Int?
        let net_points_total: Int?
    }
    
    private struct VolleyballStats: Decodable {
        let points: Int?
        let aces: Int?
        let blocks: Int?
        let digs: Int?
    }
    
    private struct HandballStats: Decodable {
        let position: String?
        let minutes_played: Int?
        let goals: Int?
        let shots: Int?
        let shots_on_target: Int?
        let assists: Int?
        let steals: Int?
        let blocks: Int?
        let turnovers_lost: Int?
        let seven_m_goals: Int?
        let seven_m_attempts: Int?
        let saves: Int?
        let yellow_cards: Int?
        let two_min_suspensions: Int?
        let red_cards: Int?
    }
    
    private struct HockeyStats: Decodable {
        let position: String?
        let minutes_played: Int?
        let goals: Int?
        let assists: Int?
        let shots_on_goal: Int?
        let plus_minus: Int?
        let hits: Int?
        let blocks: Int?
        let faceoffs_won: Int?
        let faceoffs_total: Int?
        let saves: Int?
        let penalty_minutes: Int?
    }
    
    private struct RugbyStats: Decodable {
        let position: String?
        let minutes_played: Int?
        let tries: Int?
        let conversions_made: Int?
        let conversions_attempted: Int?
        let penalty_goals_made: Int?
        let penalty_goals_attempted: Int?
        let runs: Int?
        let meters_gained: Int?
        let offloads: Int?
        let tackles_made: Int?
        let tackles_missed: Int?
        let turnovers_won: Int?
        let yellow_cards: Int?
        let red_cards: Int?
    }
    
    private struct HyroxStats: Decodable {
        let division: String?
        let category: String?
        let age_group: String?
        let official_time_sec: Int?
        let rank_overall: Int?
        let rank_category: Int?
        let no_reps: Int?
        let penalty_time_sec: Int?
        let avg_hr: Int?
        let max_hr: Int?
    }
    
    private struct HyroxExerciseStats: Decodable, Identifiable {
        let id: Int64
        let session_id: Int
        let exercise_code: String
        let exercise_order: Int
        let zone_order: Int?
        let distance_m: Int?
        let reps: Int?
        let weight_kg: Decimal?
        let duration_sec: Int?
        let height_cm: Int?
        let implement_count: Int?
        let notes: String?
        let exercise_display_name: String?
    }
    
    private struct SkiStats: Decodable {
        let session_id: Int
        let total_distance_km: Decimal?
        let runs_count: Int?
        let max_speed_kmh: Decimal?
        let avg_speed_kmh: Decimal?
        let vertical_drop_m: Int?
        let moving_time_sec: Int?
        let paused_time_sec: Int?
        let resort_name: String?
        let snow_condition: String?
        let weather: String?
    }
    
    @State private var row: SportRow?
    @State private var loading = false
    @State private var error: String?
    
    @State private var fb: FootballStats? = nil
    @State private var bb: BasketballStats? = nil
    @State private var rk: RacketStats? = nil
    @State private var vb: VolleyballStats? = nil
    @State private var hb: HandballStats? = nil
    @State private var hk: HockeyStats? = nil
    @State private var rg: RugbyStats? = nil
    @State private var hy: HyroxStats? = nil
    @State private var hyExercises: [HyroxExerciseStats] = []
    @State private var sk: SkiStats? = nil
    
    var body: some View {
        DetailSectionCard(title: sportTitle, subtitle: sportSubtitle) {
            if loading && row == nil {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            } else if let error, row == nil {
                DetailEmptyState(
                    title: "Could not load sport details",
                    message: error,
                    systemImage: "exclamationmark.triangle"
                )
            } else if let r = row {
                DetailMetricGrid(metrics: sportSummaryMetrics(r))
                sportOverviewRows(r)
                sportSpecificSection(r)
            } else {
                DetailEmptyState(
                    title: "No sport session linked",
                    message: "This workout does not have sport details attached.",
                    systemImage: "trophy"
                )
            }
        }
        .task { await load() }
        .onChange(of: reloadKey) { _, _ in
            Task { await load() }
        }
    }

    private var sportTitle: String {
        row.map { detailLabel($0.sport) } ?? "Sport"
    }

    private var sportSubtitle: String? {
        guard let row else { return nil }
        if row.sport == "hyrox", !hyExercises.isEmpty {
            return "\(hyExercises.count) Hyrox exercises"
        }
        if let result = detailTrimmed(row.match_result), row.sport != "ski" {
            return result.capitalized
        }
        return nil
    }

    private func sportSummaryMetrics(_ r: SportRow) -> [DetailMetric] {
        var metrics: [DetailMetric] = [DetailMetric("Sport", detailLabel(r.sport), systemImage: "figure.run")]
        if let s = detailPositiveInt(r.duration_sec) {
            metrics.append(DetailMetric("Duration", durationString(Double(s)), systemImage: "clock"))
        }
        if r.sport != "ski", let res = detailTrimmed(r.match_result) {
            metrics.append(DetailMetric("Result", res.capitalized, systemImage: "flag.checkered"))
        }
        if sportUsesNumericScore(r.sport), let score = detailPair(r.score_for, r.score_against) {
            metrics.append(DetailMetric("Score", score, systemImage: "number"))
        }
        if sportUsesSetText(r.sport), let sets = detailTrimmed(r.match_score_text) {
            metrics.append(DetailMetric("Sets", sets, systemImage: "list.number"))
        }
        if r.sport == "hyrox", !hyExercises.isEmpty {
            metrics.append(DetailMetric("Exercises", "\(hyExercises.count)", systemImage: "square.grid.2x2"))
        }
        return metrics
    }

    @ViewBuilder
    private func sportOverviewRows(_ r: SportRow) -> some View {
        if let loc = detailTrimmed(r.location) {
            info("Location", loc)
        }
        if let n = detailTrimmed(r.notes) {
            info("Session notes", n)
        }
    }

    @ViewBuilder
    private func sportSpecificSection(_ r: SportRow) -> some View {
        switch r.sport {
        case "football":
            if let s = fb, hasFootballStats(s) {
                sportSubsection("Football stats") {
                    if let v = detailTrimmed(s.position) { info("Position", detailLabel(v)) }
                    if let v = detailPositiveInt(s.minutes_played) { info("Minutes played", "\(v)") }
                    if let v = detailPositiveInt(s.goals) { info("Goals", "\(v)") }
                    if let v = detailPositiveInt(s.assists) { info("Assists", "\(v)") }
                    if let v = detailPositiveInt(s.shots_on_target) { info("Shots on target", "\(v)") }
                    if let v = detailRatio(s.passes_completed, s.passes_attempted) { info("Passes", v) }
                    if let v = detailPositiveInt(s.tackles) { info("Tackles", "\(v)") }
                    if let v = detailPositiveInt(s.interceptions) { info("Interceptions", "\(v)") }
                    if let v = detailPositiveInt(s.saves) { info("Saves", "\(v)") }
                    if let v = detailPositiveInt(s.yellow_cards) { info("Yellow cards", "\(v)") }
                    if let v = detailPositiveInt(s.red_cards) { info("Red cards", "\(v)") }
                }
            }
        case "handball":
            if let s = hb, hasHandballStats(s) {
                sportSubsection("Handball stats") {
                    if let v = detailTrimmed(s.position) { info("Position", detailLabel(v)) }
                    if let v = detailPositiveInt(s.minutes_played) { info("Minutes played", "\(v)") }
                    if let v = detailPositiveInt(s.goals) { info("Goals", "\(v)") }
                    if let v = detailPositiveInt(s.shots) { info("Shots", "\(v)") }
                    if let v = detailPositiveInt(s.shots_on_target) { info("Shots on target", "\(v)") }
                    if let v = detailPositiveInt(s.assists) { info("Assists", "\(v)") }
                    if let v = detailPositiveInt(s.steals) { info("Steals", "\(v)") }
                    if let v = detailPositiveInt(s.blocks) { info("Blocks", "\(v)") }
                    if let v = detailPositiveInt(s.turnovers_lost) { info("Turnovers lost", "\(v)") }
                    if let v = detailRatio(s.seven_m_goals, s.seven_m_attempts) { info("7m goals", v) }
                    if let v = detailPositiveInt(s.saves) { info("Saves", "\(v)") }
                    if let v = detailPositiveInt(s.yellow_cards) { info("Yellow cards", "\(v)") }
                    if let v = detailPositiveInt(s.two_min_suspensions) { info("2-min suspensions", "\(v)") }
                    if let v = detailPositiveInt(s.red_cards) { info("Red cards", "\(v)") }
                }
            }
        case "hockey":
            if let s = hk, hasHockeyStats(s) {
                sportSubsection("Hockey stats") {
                    if let v = detailTrimmed(s.position) { info("Position", detailLabel(v)) }
                    if let v = detailPositiveInt(s.minutes_played) { info("Minutes played", "\(v)") }
                    if let v = detailPositiveInt(s.goals) { info("Goals", "\(v)") }
                    if let v = detailPositiveInt(s.assists) { info("Assists", "\(v)") }
                    if let v = detailPositiveInt(s.shots_on_goal) { info("Shots on goal", "\(v)") }
                    if let v = detailNonZeroInt(s.plus_minus) { info("+ / -", "\(v)") }
                    if let v = detailPositiveInt(s.hits) { info("Hits", "\(v)") }
                    if let v = detailPositiveInt(s.blocks) { info("Blocks", "\(v)") }
                    if let v = detailRatio(s.faceoffs_won, s.faceoffs_total) { info("Faceoffs", v) }
                    if let v = detailPositiveInt(s.saves) { info("Saves", "\(v)") }
                    if let v = detailPositiveInt(s.penalty_minutes) { info("Penalty minutes", "\(v)") }
                }
            }
        case "rugby":
            if let s = rg, hasRugbyStats(s) {
                sportSubsection("Rugby stats") {
                    if let v = detailTrimmed(s.position) { info("Position", detailLabel(v)) }
                    if let v = detailPositiveInt(s.minutes_played) { info("Minutes played", "\(v)") }
                    if let v = detailPositiveInt(s.tries) { info("Tries", "\(v)") }
                    if let v = detailRatio(s.conversions_made, s.conversions_attempted) { info("Conversions", v) }
                    if let v = detailRatio(s.penalty_goals_made, s.penalty_goals_attempted) { info("Penalty goals", v) }
                    if let v = detailPositiveInt(s.runs) { info("Runs", "\(v)") }
                    if let v = detailPositiveInt(s.meters_gained) { info("Meters gained", "\(v)") }
                    if let v = detailPositiveInt(s.offloads) { info("Offloads", "\(v)") }
                    if let v = detailPositiveInt(s.tackles_made) { info("Tackles made", "\(v)") }
                    if let v = detailPositiveInt(s.tackles_missed) { info("Tackles missed", "\(v)") }
                    if let v = detailPositiveInt(s.turnovers_won) { info("Turnovers won", "\(v)") }
                    if let v = detailPositiveInt(s.yellow_cards) { info("Yellow cards", "\(v)") }
                    if let v = detailPositiveInt(s.red_cards) { info("Red cards", "\(v)") }
                }
            }
        case "basketball":
            if let s = bb, hasBasketballStats(s) {
                sportSubsection("Basketball stats") {
                    if let v = detailPositiveInt(s.points) { info("Points", "\(v)") }
                    if let v = detailPositiveInt(s.rebounds) { info("Rebounds", "\(v)") }
                    if let v = detailPositiveInt(s.assists) { info("Assists", "\(v)") }
                    if let v = detailPositiveInt(s.steals) { info("Steals", "\(v)") }
                    if let v = detailPositiveInt(s.blocks) { info("Blocks", "\(v)") }
                    if let v = detailRatio(s.fg_made, s.fg_attempted) { info("FG", v) }
                    if let v = detailRatio(s.three_made, s.three_attempted) { info("3PT", v) }
                    if let v = detailRatio(s.ft_made, s.ft_attempted) { info("FT", v) }
                    if let v = detailPositiveInt(s.turnovers) { info("Turnovers", "\(v)") }
                    if let v = detailPositiveInt(s.fouls) { info("Fouls", "\(v)") }
                }
            }
        case "padel", "tennis", "badminton", "squash", "table_tennis":
            if let s = rk, hasRacketStats(s) {
                sportSubsection("Racket stats") {
                    if let v = detailTrimmed(s.mode) { info("Mode", detailLabel(v)) }
                    if let v = detailTrimmed(s.format) { info("Format", detailLabel(v)) }
                    if let v = detailPair(s.sets_won, s.sets_lost) { info("Sets (W-L)", v) }
                    if let v = detailPair(s.games_won, s.games_lost) { info("Games (W-L)", v) }
                    if let v = detailPositiveInt(s.aces) { info("Aces", "\(v)") }
                    if let v = detailPositiveInt(s.double_faults) { info("Double faults", "\(v)") }
                    if let v = detailPositiveInt(s.winners) { info("Winners", "\(v)") }
                    if let v = detailPositiveInt(s.unforced_errors) { info("Unforced errors", "\(v)") }
                    if let v = detailRatio(s.break_points_won, s.break_points_total) { info("Break points", v) }
                    if let v = detailRatio(s.net_points_won, s.net_points_total) { info("Net points", v) }
                }
            }
        case "volleyball":
            if let s = vb, hasVolleyballStats(s) {
                sportSubsection("Volleyball stats") {
                    if let v = detailPositiveInt(s.points) { info("Points", "\(v)") }
                    if let v = detailPositiveInt(s.aces) { info("Aces", "\(v)") }
                    if let v = detailPositiveInt(s.blocks) { info("Blocks", "\(v)") }
                    if let v = detailPositiveInt(s.digs) { info("Digs", "\(v)") }
                }
            }
        case "hyrox":
            hyroxSection()
        case "ski":
            if let s = sk, hasSkiStats(s) {
                sportSubsection("Ski stats") {
                    if let d = detailPositiveDecimalDouble(s.total_distance_km) {
                        info("Total distance", String(format: "%.2f km", d))
                    }
                    if let v = detailPositiveInt(s.runs_count) { info("Runs", "\(v)") }
                    if let v = detailPositiveDecimalDouble(s.max_speed_kmh) {
                        info("Max speed", String(format: "%.1f km/h", v))
                    }
                    if let v = detailPositiveDecimalDouble(s.avg_speed_kmh) {
                        info("Avg speed", String(format: "%.1f km/h", v))
                    }
                    if let v = detailPositiveInt(s.vertical_drop_m) { info("Vertical drop", "\(v) m") }
                    if let t = detailPositiveInt(s.moving_time_sec) { info("Moving time", durationString(Double(t))) }
                    if let t = detailPositiveInt(s.paused_time_sec) { info("Paused time", durationString(Double(t))) }
                    if let v = detailTrimmed(s.resort_name) { info("Resort", v) }
                    if let v = detailTrimmed(s.snow_condition) { info("Snow", v) }
                    if let v = detailTrimmed(s.weather) { info("Weather", v) }
                }
            }
        default:
            EmptyView()
        }
    }

    private func sportSubsection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider().padding(.vertical, 2)
            Text(title)
                .font(.subheadline.weight(.semibold))
            content()
        }
    }

    @ViewBuilder
    private func hyroxSection() -> some View {
        if let s = hy, hasHyroxStats(s) {
            sportSubsection("Hyrox stats") {
                if let v = detailTrimmed(s.division) { info("Division", v) }
                if let v = detailTrimmed(s.category) { info("Category", v) }
                if let v = detailTrimmed(s.age_group) { info("Age group", v) }
                if let t = detailPositiveInt(s.official_time_sec) { info("Official time", durationString(Double(t))) }
                if let v = detailPositiveInt(s.rank_overall) { info("Overall rank", "#\(v)") }
                if let v = detailPositiveInt(s.rank_category) { info("Category rank", "#\(v)") }
                if let v = detailPositiveInt(s.no_reps) { info("No reps", "\(v)") }
                if let t = detailPositiveInt(s.penalty_time_sec) { info("Penalty time", durationString(Double(t))) }
                if let v = detailPositiveInt(s.avg_hr) { info("Avg HR", "\(v) bpm") }
                if let v = detailPositiveInt(s.max_hr) { info("Max HR", "\(v) bpm") }
            }
        }

        if !hyExercises.isEmpty {
            sportSubsection("Hyrox exercises") {
                ForEach(orderedHyroxDetailExercisePairs, id: \.element.id) { pair in
                    if let zoneOrder = pair.element.zone_order {
                        if isFirstHyroxDetailExerciseInZone(position: pair.offset, zoneOrder: zoneOrder) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Zone \(max(1, zoneOrder))")
                                    .font(.subheadline.weight(.bold))
                                ForEach(hyroxDetailZoneExercisePairs(zoneOrder), id: \.element.id) { zonePair in
                                    hyroxDetailExerciseCard(zonePair.element)
                                }
                            }
                            .padding(10)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.accentColor.opacity(0.35), lineWidth: 1))
                        }
                    } else {
                        hyroxDetailExerciseCard(pair.element)
                    }
                }
            }
        }
    }

    private func hasFootballStats(_ s: FootballStats) -> Bool {
        detailTrimmed(s.position) != nil ||
        [
            s.minutes_played, s.goals, s.assists, s.shots_on_target,
            s.passes_completed, s.passes_attempted, s.tackles, s.interceptions,
            s.saves, s.yellow_cards, s.red_cards
        ].contains { detailPositiveInt($0) != nil }
    }

    private func hasBasketballStats(_ s: BasketballStats) -> Bool {
        [
            s.points, s.rebounds, s.assists, s.steals, s.blocks,
            s.fg_made, s.fg_attempted, s.three_made, s.three_attempted,
            s.ft_made, s.ft_attempted, s.turnovers, s.fouls
        ].contains { detailPositiveInt($0) != nil }
    }

    private func hasRacketStats(_ s: RacketStats) -> Bool {
        detailTrimmed(s.mode) != nil ||
        detailTrimmed(s.format) != nil ||
        [
            s.sets_won, s.sets_lost, s.games_won, s.games_lost, s.aces,
            s.double_faults, s.winners, s.unforced_errors, s.break_points_won,
            s.break_points_total, s.net_points_won, s.net_points_total
        ].contains { detailPositiveInt($0) != nil }
    }

    private func hasVolleyballStats(_ s: VolleyballStats) -> Bool {
        [s.points, s.aces, s.blocks, s.digs].contains { detailPositiveInt($0) != nil }
    }

    private func hasHandballStats(_ s: HandballStats) -> Bool {
        detailTrimmed(s.position) != nil ||
        [
            s.minutes_played, s.goals, s.shots, s.shots_on_target, s.assists,
            s.steals, s.blocks, s.turnovers_lost, s.seven_m_goals,
            s.seven_m_attempts, s.saves, s.yellow_cards, s.two_min_suspensions,
            s.red_cards
        ].contains { detailPositiveInt($0) != nil }
    }

    private func hasHockeyStats(_ s: HockeyStats) -> Bool {
        detailTrimmed(s.position) != nil ||
        detailNonZeroInt(s.plus_minus) != nil ||
        [
            s.minutes_played, s.goals, s.assists, s.shots_on_goal, s.hits,
            s.blocks, s.faceoffs_won, s.faceoffs_total, s.saves, s.penalty_minutes
        ].contains { detailPositiveInt($0) != nil }
    }

    private func hasRugbyStats(_ s: RugbyStats) -> Bool {
        detailTrimmed(s.position) != nil ||
        [
            s.minutes_played, s.tries, s.conversions_made, s.conversions_attempted,
            s.penalty_goals_made, s.penalty_goals_attempted, s.runs,
            s.meters_gained, s.offloads, s.tackles_made, s.tackles_missed,
            s.turnovers_won, s.yellow_cards, s.red_cards
        ].contains { detailPositiveInt($0) != nil }
    }

    private func hasHyroxStats(_ s: HyroxStats) -> Bool {
        detailTrimmed(s.division) != nil ||
        detailTrimmed(s.category) != nil ||
        detailTrimmed(s.age_group) != nil ||
        [
            s.official_time_sec, s.rank_overall, s.rank_category,
            s.no_reps, s.penalty_time_sec, s.avg_hr, s.max_hr
        ].contains { detailPositiveInt($0) != nil }
    }

    private func hasSkiStats(_ s: SkiStats) -> Bool {
        detailPositiveDecimalDouble(s.total_distance_km) != nil ||
        detailPositiveDecimalDouble(s.max_speed_kmh) != nil ||
        detailPositiveDecimalDouble(s.avg_speed_kmh) != nil ||
        detailTrimmed(s.resort_name) != nil ||
        detailTrimmed(s.snow_condition) != nil ||
        detailTrimmed(s.weather) != nil ||
        [
            s.runs_count, s.vertical_drop_m, s.moving_time_sec, s.paused_time_sec
        ].contains { detailPositiveInt($0) != nil }
    }

    private var orderedHyroxDetailExercisePairs: [(offset: Int, element: HyroxExerciseStats)] {
        Array(hyExercises.sorted { $0.exercise_order < $1.exercise_order }.enumerated())
    }

    private func hyroxDetailZoneExercisePairs(_ zoneOrder: Int) -> [(offset: Int, element: HyroxExerciseStats)] {
        orderedHyroxDetailExercisePairs.filter { $0.element.zone_order == zoneOrder }
    }

    private func isFirstHyroxDetailExerciseInZone(position: Int, zoneOrder: Int) -> Bool {
        guard orderedHyroxDetailExercisePairs.indices.contains(position) else { return false }
        guard position > 0 else { return true }
        return orderedHyroxDetailExercisePairs[position - 1].element.zone_order != zoneOrder
    }

    @ViewBuilder
    private func hyroxDetailExerciseCard(_ ex: HyroxExerciseStats) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            let exerciseTitle = HyroxExerciseFormatting.label(
                code: ex.exercise_code,
                displayName: ex.exercise_display_name,
                notes: ex.notes
            )
            Text("\(ex.exercise_order). \(exerciseTitle)")
                .font(.subheadline.weight(.semibold))

            DetailMetricGrid(metrics: hyroxExerciseMetrics(ex))

            if let v = ex.notes, !v.isEmpty {
                let trimmedNote = v.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmedNote != exerciseTitle.trimmingCharacters(in: .whitespacesAndNewlines) {
                    info("Notes", v)
                }
            }
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private func hyroxExerciseMetrics(_ ex: HyroxExerciseStats) -> [DetailMetric] {
        var metrics: [DetailMetric] = []
        if let v = detailPositiveInt(ex.distance_m) {
            metrics.append(DetailMetric("Distance", "\(v) m"))
        }
        if let v = detailPositiveInt(ex.reps) {
            metrics.append(DetailMetric("Reps", "\(v)"))
        }
        if let v = detailPositiveDecimalDouble(ex.weight_kg) {
            metrics.append(DetailMetric("Weight", String(format: "%.1f kg", v)))
        }
        if let v = detailPositiveInt(ex.duration_sec) {
            metrics.append(DetailMetric("Duration", durationString(Double(v))))
        }
        if let v = detailPositiveInt(ex.height_cm) {
            metrics.append(DetailMetric("Height", "\(v) cm"))
        }
        if let v = detailPositiveInt(ex.implement_count) {
            metrics.append(DetailMetric("Implements", "\(v)"))
        }
        return metrics
    }
    
    private func load() async {
        await MainActor.run {
            loading = true
            error = nil
        }
        defer { Task { await MainActor.run { loading = false } } }
        do {
            let res = try await SupabaseManager.shared.client
                .from("sport_sessions")
                .select("*")
                .eq("workout_id", value: workoutId)
                .single()
                .execute()
            let r = try JSONDecoder.supabase().decode(SportRow.self, from: res.data)
            await MainActor.run {
                row = r
                error = nil
                fb = nil; bb = nil; rk = nil; vb = nil
                hb = nil; hk = nil; rg = nil; hy = nil
                hyExercises = []
                sk = nil
            }
            await loadStats(for: r)
        } catch {
            await MainActor.run {
                self.row = nil
                self.error = error.localizedDescription
            }
        }
    }
    
    private func loadStats(for r: SportRow) async {
        let client = SupabaseManager.shared.client
        let decoder = JSONDecoder.supabase()
        
        switch r.sport {
        case "football":
            do {
                let q = try await client
                    .from("football_session_stats")
                    .select("*")
                    .eq("session_id", value: r.id)
                    .single()
                    .execute()
                let s = try decoder.decode(FootballStats.self, from: q.data)
                await MainActor.run { fb = s }
            } catch { await MainActor.run { fb = nil } }
            
        case "handball":
            do {
                let q = try await client
                    .from("handball_session_stats")
                    .select("*")
                    .eq("session_id", value: r.id)
                    .single()
                    .execute()
                let s = try decoder.decode(HandballStats.self, from: q.data)
                await MainActor.run { hb = s }
            } catch { await MainActor.run { hb = nil } }
            
        case "hockey":
            do {
                let q = try await client
                    .from("hockey_session_stats")
                    .select("*")
                    .eq("session_id", value: r.id)
                    .single()
                    .execute()
                let s = try decoder.decode(HockeyStats.self, from: q.data)
                await MainActor.run { hk = s }
            } catch { await MainActor.run { hk = nil } }
            
        case "rugby":
            do {
                let q = try await client
                    .from("rugby_session_stats")
                    .select("*")
                    .eq("session_id", value: r.id)
                    .single()
                    .execute()
                let s = try decoder.decode(RugbyStats.self, from: q.data)
                await MainActor.run { rg = s }
            } catch { await MainActor.run { rg = nil } }
            
        case "hyrox":
            do {
                let q = try await client
                    .from("hyrox_session_stats")
                    .select("*")
                    .eq("session_id", value: r.id)
                    .single()
                    .execute()
                let s = try decoder.decode(HyroxStats.self, from: q.data)

                let exQ = try await client
                    .from("hyrox_session_exercises")
                    .select("*")
                    .eq("session_id", value: r.id)
                    .order("exercise_order", ascending: true)
                    .execute()
                let ex = try decoder.decode([HyroxExerciseStats].self, from: exQ.data)

                await MainActor.run {
                    hy = s
                    hyExercises = ex
                }
            } catch {
                await MainActor.run {
                    hy = nil
                    hyExercises = []
                }
            }
            
        case "basketball":
            do {
                let q = try await client
                    .from("basketball_session_stats")
                    .select("*")
                    .eq("session_id", value: r.id)
                    .single()
                    .execute()
                let s = try decoder.decode(BasketballStats.self, from: q.data)
                await MainActor.run { bb = s }
            } catch { await MainActor.run { bb = nil } }
            
        case "padel", "tennis", "badminton", "squash", "table_tennis":
            do {
                let q = try await client
                    .from("racket_session_stats")
                    .select("*")
                    .eq("session_id", value: r.id)
                    .single()
                    .execute()
                let s = try decoder.decode(RacketStats.self, from: q.data)
                await MainActor.run { rk = s }
            } catch { await MainActor.run { rk = nil } }
            
        case "volleyball":
            do {
                let q = try await client
                    .from("volleyball_session_stats")
                    .select("*")
                    .eq("session_id", value: r.id)
                    .single()
                    .execute()
                let s = try decoder.decode(VolleyballStats.self, from: q.data)
                await MainActor.run { vb = s }
            } catch { await MainActor.run { vb = nil } }
            
        case "ski":
            do {
                let q = try await client
                    .from("ski_session_stats")
                    .select("*")
                    .eq("session_id", value: r.id)
                    .single()
                    .execute()
                let s = try decoder.decode(SkiStats.self, from: q.data)
                await MainActor.run { sk = s }
            } catch {
                await MainActor.run { sk = nil }
            }
            
        default:
            break
        }
    }
    
    @ViewBuilder
    private func info(_ label: String, _ value: String) -> some View {
        DetailStatRow(label: label, value: value)
    }
    
    private func durationString(_ secondsDouble: Double) -> String {
        let s = max(0, Int(secondsDouble.rounded()))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, sec) }
        return String(format: "%d:%02d", m, sec)
    }
}

private func sportUsesNumericScore(_ s: String) -> Bool {
    switch s {
    case "football", "basketball", "handball", "hockey": return true
    default: return false
    }
}
private func sportUsesSetText(_ s: String) -> Bool {
    switch s {
    case "padel", "tennis", "badminton", "squash", "table_tennis", "volleyball": return true
    default: return false
    }
}

private struct LikersSheet: View {
    let likers: [WorkoutDetailView.ProfileRow]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Likes").font(.title3.weight(.semibold))
                Spacer()
                HStack(spacing: 6) {
                    Image(systemName: "heart.fill")
                        .symbolRenderingMode(.hierarchical)
                    Text("\(likers.count)")
                        .font(.caption.weight(.semibold))
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 10)
                .background(.ultraThinMaterial, in: Capsule())
            }
            
            Divider().opacity(0.2)
            
            if likers.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "heart")
                        .font(.system(size: 36, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                    
                    Text("No likes yet")
                        .font(.headline)
                    
                    Text("Be the first to like this workout.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 36)
                .padding(.horizontal, 12)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
            } else {
                List(likers, id: \.user_id) { p in
                    HStack(spacing: 12) {
                        AvatarView(urlString: p.avatar_url)
                            .frame(width: 36, height: 36)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        Text("@\(p.username)")
                            .font(.body)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
            }
        }
        .padding(16)
    }
}

private struct CompareCandidatePicker: View {
    let picker: ComparePickerState
    let onPick: (CompareOtherTarget, String?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var filteredSessions: [WorkoutDetailView.CompareCandidate] {
        filterComparePickerSessions(picker, query: searchText)
    }

    private var visibleMyAverage: CompareAverageOption? {
        guard let o = picker.myAverage else { return nil }
        return compareAverageMatchesSearch(o, query: searchText) ? o : nil
    }

    private var visibleGlobalAverage: CompareAverageOption? {
        guard let o = picker.globalAverage else { return nil }
        return compareAverageMatchesSearch(o, query: searchText) ? o : nil
    }

    private var showAverageCTAs: Bool {
        visibleMyAverage != nil || visibleGlobalAverage != nil
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var showEmptySearch: Bool {
        isSearching && !showAverageCTAs && filteredSessions.isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                if showAverageCTAs {
                    CompareAverageCTARow(
                        myAverage: visibleMyAverage,
                        globalAverage: visibleGlobalAverage,
                        onSelect: { option in
                            let target: CompareOtherTarget = .average(
                                scope: option.scope,
                                workoutIds: option.workoutIds,
                                sampleCount: option.sampleCount
                            )
                            onPick(target, compareAverageRightLabel(scope: option.scope, sampleCount: option.sampleCount))
                            dismiss()
                        }
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 12)
                }

                if showEmptySearch {
                    Text("No matches")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 120)
                } else {
                    if !filteredSessions.isEmpty {
                        Text("Past workouts")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 6)
                    }
                    List(filteredSessions) { c in
                        Button {
                            onPick(.workout(c.id), nil)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(c.displayTitle)
                                    .font(.headline)
                                    .lineLimit(1)
                                if let u = c.owner_username, !u.isEmpty {
                                    Text("@\(u)")
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(.secondary)
                                }
                                Text(c.started_at.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .listRowBackground(Color.clear)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .searchable(text: $searchText, prompt: "Search")
            .navigationTitle("Choose workout")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct CompareAverageCTARow: View {
    let myAverage: CompareAverageOption?
    let globalAverage: CompareAverageOption?
    let onSelect: (CompareAverageOption) -> Void

    var body: some View {
        HStack(spacing: 10) {
            if let mine = myAverage {
                CompareAverageCTAButton(option: mine, onTap: { onSelect(mine) })
            }
            if let global = globalAverage {
                CompareAverageCTAButton(option: global, onTap: { onSelect(global) })
            }
        }
    }
}

private struct CompareAverageCTAButton: View {
    let option: CompareAverageOption
    let onTap: () -> Void

    private var title: String { compareAveragePickerTitle(option) }
    private var icon: String {
        option.scope == .mine ? "person.crop.circle.fill" : "globe.americas.fill"
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary.opacity(0.85))
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                Text(option.typeLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text("Last \(option.sampleCount)")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.08), in: Capsule())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

extension WorkoutDetailView {
    fileprivate func applyCompareTarget(_ target: CompareOtherTarget, rightLabel: String?) {
        switch target {
        case .workout(let id):
            compareCandidateId = id
            compareAverageScope = nil
            compareAverageRightLabel = nil
        case .average(let scope, _, _):
            compareCandidateId = nil
            compareAverageScope = scope
            compareAverageRightLabel = rightLabel
        }
    }

    fileprivate func resolvedCompareTarget() -> CompareOtherTarget? {
        if let scope = compareAverageScope {
            let opt: CompareAverageOption? = switch scope {
            case .mine: comparePicker.myAverage
            case .global: comparePicker.globalAverage
            }
            if let o = opt {
                return .average(scope: o.scope, workoutIds: o.workoutIds, sampleCount: o.sampleCount)
            }
            return nil
        }
        if let id = compareCandidateId {
            return .workout(id)
        }
        return nil
    }
}

@inline(__always)
private func liftrMMSS(_ seconds: Int) -> String {
    let m = max(0, seconds) / 60
    let s = max(0, seconds) % 60
    return String(format: "%d:%02d", m, s)
}

private func showsCadence(for code: String?) -> Bool {
    guard let c = code else { return false }
    return ["bike","e_bike","mtb","indoor_cycling","rowerg"].contains(c)
}

private func showsWatts(for code: String?) -> Bool {
    guard let c = code else { return false }
    return ["bike","e_bike","indoor_cycling","rowerg","mtb"].contains(c)
}

private func showsIncline(for code: String?) -> Bool {
    return code == "treadmill"
}

private func showsSplit500m(for code: String?) -> Bool {
    return code == "rowerg"
}

private func showsSwimFields(for code: String?) -> Bool {
    return code == "swim_pool"
}
