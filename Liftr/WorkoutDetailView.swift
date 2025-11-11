import SwiftUI
import Supabase

struct WorkoutDetailView: View {
    @EnvironmentObject var app: AppState
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
    
    struct WorkoutDetailRow: Decodable {
        let id: Int
        let user_id: UUID
        let kind: String
        let title: String?
        let notes: String?
        let started_at: Date?
        let ended_at: Date?
        let duration_min: Int?
        let perceived_intensity: String?
        let state: String
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
    @State private var error: String?
    @State private var reloadKey = UUID()
    private struct LikeRow: Decodable { let user_id: UUID }
    @State private var isLiked = false
    @State private var likeCount = 0
    @State private var likeBusy = false
    @State private var showLikesSheet = false
    @State private var likers: [ProfileRow] = []
    @State private var participants: [ParticipantRow] = []
    @State private var loadLikesRequestId = 0
    @State private var showCommentsSheet = false
    @State private var showErrorAlert = false
    @State private var alertMessage = ""
    @State private var compareCandidateId: Int? = nil
    @State private var compareCandidates: [CompareCandidate] = []
    @State private var showComparePicker = false
    @State private var compareReady = false
    @State private var compareComputing = false
    @State private var showCompare = false
    
    var body: some View {
        ScrollView {
            content
        }
        .task {
            await load()
            await loadParticipants()
            await loadLikes()
            if likeCount > 0 { await loadLikers() }
            await loadCompareCandidates()
        }
        .onReceive(NotificationCenter.default.publisher(for: .workoutDidChange)) { note in
            if let id = note.object as? Int, id == workoutId {
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
        .sheet(isPresented: $showLikesSheet) { LikersSheet(likers: likers)
                .onAppear { Task { await loadLikers() } }
                .presentationDetents(Set([.medium, .large]))
                .presentationBackground(.ultraThinMaterial)
        }
        .sheet(isPresented: $showCommentsSheet) {
            CommentsSheet(
                workoutId: workoutId,
                ownerId: ownerId,
                onDidChange: { await load() }
            )
            .environmentObject(app)
            .presentationDetents(Set([.large]))
            .presentationBackground(.ultraThinMaterial)
        }
        .sheet(isPresented: $showComparePicker) {
            CompareCandidatePicker(items: compareCandidates) { chosen in
                compareCandidateId = chosen
                showCompare = true
            }
            .gradientBG()
            .presentationDetents([.fraction(0.45), .medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showEdit) {
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
                .presentationDetents(Set([.medium, .large]))
            }
        }
        .sheet(isPresented: $showCompare) {
            if let otherId = compareCandidateId {
                CompareWorkoutsView(currentWorkoutId: workoutId, myOtherWorkoutId: otherId)
                    .gradientBG()
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
    }
    
    @ViewBuilder
    private var content: some View {
        VStack(spacing: 14) {
            if let w = workout {
                workoutHeader(w)
            }
            if !participants.isEmpty {
                participantsBlock
            }
            if let notes = workout?.notes,
               !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                notesBlock(notes)
            }
            
            if let kind = workout?.kind {
                workoutDetail(kind)
                feedbackBlock
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
                    if let sc = totalScore {
                        scorePill(score: sc, kind: w.kind)
                    }
                }
                
                HStack(spacing: 10) {
                    Text(dateRange(w)).font(.footnote).foregroundStyle(.secondary)
                    if let dur = w.duration_min {
                        Text("• \(dur) min")
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
            CardioDetailBlock(workoutId: workoutId, reloadKey: reloadKey)
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
                Spacer()
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.18)))
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
                Image(systemName: "bubble.right").foregroundStyle(.secondary)
                Text("Comments").font(.subheadline.weight(.semibold))
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(.ultraThinMaterial, in: Capsule())
        }
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
        
        if canEdit || canDuplicate || compareReady {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if compareReady {
                        if compareCandidates.count > 1 {
                            Button("Compare…") { showComparePicker = true }
                        } else if let only = (compareCandidates.first?.id ?? compareCandidateId) {
                            Button("Compare") {
                                compareCandidateId = only
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
                .select("*")
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
    
    private func dateRange(_ w: WorkoutDetailRow) -> String {
        let f = DateFormatter(); f.timeStyle = .short; f.dateStyle = .medium
        guard let s = w.started_at else { return "—" }
        if let e = w.ended_at { return "\(f.string(from: s)) – \(f.string(from: e))" }
        return f.string(from: s)
    }
    
    private func buildDuplicateDraft() async -> AddWorkoutDraft? {
        guard let base = workout else { return nil }
        
        var draft = AddWorkoutDraft(
            kind: WorkoutKind(rawValue: base.kind) ?? .strength,
            title: base.title ?? "",
            note: base.notes ?? "",
            startedAt: base.started_at ?? Date(),
            endedAt: base.ended_at,
            perceived: WorkoutIntensity(rawValue: base.perceived_intensity ?? "moderate") ?? .moderate
        )
        
        let decoder = JSONDecoder.supabase()
        
        switch base.kind.lowercased() {
        case "strength":
            do {
                let exRes = try await SupabaseManager.shared.client
                    .from("workout_exercises")
                    .select("id, exercise_id, order_index, notes, custom_name, exercises(name)")
                    .eq("workout_id", value: workoutId)
                    .order("order_index", ascending: true)
                    .execute()
                
                struct ExWire: Decodable {
                    let id: Int
                    let exercise_id: Int64
                    let order_index: Int
                    let notes: String?
                    let exercises: ExName?
                    let custom_name: String?
                    struct ExName: Decodable { let name: String? }
                }
                let exs = try decoder.decode([ExWire].self, from: exRes.data)
                
                let exIds = exs.map { $0.id }
                var setsByEx: [Int: [EditableSet]] = [:]
                if !exIds.isEmpty {
                    let setRes = try await SupabaseManager.shared.client
                        .from("exercise_sets")
                        .select("workout_exercise_id, set_number, reps, weight_kg, rpe, rest_sec")
                        .in("workout_exercise_id", values: exIds)
                        .order("set_number", ascending: true)
                        .execute()
                    
                    struct SetWire: Decodable {
                        let workout_exercise_id: Int
                        let set_number: Int
                        let reps: Int?
                        let weight_kg: Decimal?
                        let rpe: Decimal?
                        let rest_sec: Int?
                    }
                    let sets = try decoder.decode([SetWire].self, from: setRes.data)
                    for s in sets {
                        setsByEx[s.workout_exercise_id, default: []].append(
                            EditableSet(
                                setNumber: s.set_number,
                                reps: s.reps,
                                weightKg: s.weight_kg.map { String(NSDecimalNumber(decimal: $0).doubleValue) } ?? "",
                                rpe: s.rpe.map { String(NSDecimalNumber(decimal: $0).doubleValue) } ?? "",
                                restSec: s.rest_sec,
                                notes: ""
                            )
                        )
                    }
                }
                
                draft.strengthItems = exs.map { ex in
                    EditableExercise(
                        exerciseId: ex.exercise_id,
                        exerciseName: (ex.custom_name?.isEmpty == false ? ex.custom_name! : (ex.exercises?.name ?? "")),
                        orderIndex: ex.order_index,
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
                if ["football","handball","hockey","rugby"].contains(full.sport) {
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
        var id: Int { candidate_id }

        var displayTitle: String {
            if let t = title, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return t }
            if kind == "sport"  { return (sport ?? "Sport").replacingOccurrences(of: "_", with: " ").capitalized }
            if kind == "cardio" { return (activity ?? "Cardio").replacingOccurrences(of: "_", with: " ").capitalized }
            return "Workout"
        }
    }
    
    private struct CanCompareParams: Encodable {
        let p_viewer: UUID
        let p_workout: Int
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
                     params: Params(p_viewer: me, p_workout: workoutId, p_limit: 50))
                .execute()
            let rows = try JSONDecoder.supabase().decode([CompareCandidate].self, from: res.data)
            await MainActor.run {
                compareCandidates = rows
                compareCandidateId = rows.first?.id
                compareReady = !rows.isEmpty
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

private struct StrengthDetailBlock: View {
    let workoutId: Int
    let reloadKey: UUID
    
    private struct ExerciseRow: Decodable, Identifiable {
        let id: Int
        let exercise_id: Int64
        let order_index: Int
        let notes: String?
        let custom_name: String?
        let exercise_name: String?
    }
    
    private struct SetRow: Decodable, Identifiable {
        let id: Int
        let workout_exercise_id: Int
        let set_number: Int
        let reps: Int?
        let weight_kg: Decimal?
        let rpe: Decimal?
        let rest_sec: Int?
    }
    
    @State private var exercises: [ExerciseRow] = []
    @State private var setsByExercise: [Int: [SetRow]] = [:]
    @State private var totalVolumeKg: Double?
    @State private var loading = false
    @State private var error: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Exercises").font(.headline)
            
            if loading { ProgressView().padding(.vertical, 8) }
            
            ForEach(exercises.sorted(by: { $0.order_index < $1.order_index })) { ex in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text((ex.custom_name?.isEmpty == false ? ex.custom_name! : (ex.exercise_name ?? "Exercise #\(ex.exercise_id)")))
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                    }
                    if let exNotes = ex.notes, !exNotes.isEmpty {
                        Text(exNotes).font(.caption).foregroundStyle(.secondary)
                    }
                    
                    let rows = setsByExercise[ex.id] ?? []
                    if rows.isEmpty {
                        Text("No sets").font(.caption).foregroundStyle(.secondary)
                    } else {
                        VStack(spacing: 6) {
                            ForEach(rows.sorted(by: { $0.set_number < $1.set_number })) { s in
                                HStack(spacing: 12) {
                                    Text("#\(s.set_number)").font(.caption2).foregroundStyle(.secondary).frame(width: 26, alignment: .leading)
                                    Text("\(s.reps ?? 0) reps").font(.footnote)
                                    Text("• \(weightStr(s.weight_kg))").font(.footnote)
                                    if let rpe = s.rpe {
                                        Text("• RPE \(String(format: "%.1f", NSDecimalNumber(decimal: rpe).doubleValue))").font(.footnote)
                                    }
                                    if let rest = s.rest_sec {
                                        Text("• Rest \(rest)s").font(.footnote)
                                    }
                                    Spacer()
                                }
                            }
                        }
                    }
                }
                .padding(12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.12)))
            }
            
            if let vol = totalVolumeKg {
                Text(String(format: "Total volume: %.1f kg", vol))
                    .font(.footnote).foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.18)))
        .task { await load() }
        .onChange(of: reloadKey) { _, _ in
            Task { await load() }
        }
    }
    
    private func load() async {
        loading = true; defer { loading = false }
        do {
            let exQ = try await SupabaseManager.shared.client
                .from("workout_exercises")
                .select("id, exercise_id, order_index, notes, custom_name, exercises(name)")
                .eq("workout_id", value: workoutId)
                .order("order_index", ascending: true)
                .execute()
            
            struct ExWire: Decodable {
                let id: Int
                let exercise_id: Int64
                let order_index: Int
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
                    notes: $0.notes,
                    custom_name: $0.custom_name,
                    exercise_name: $0.exercises?.name
                )
            }
            await MainActor.run { exercises = exRows }
            
            let ids = exRows.map { $0.id }
            var byEx: [Int: [SetRow]] = [:]
            if !ids.isEmpty {
                let sRes = try await SupabaseManager.shared.client
                    .from("exercise_sets")
                    .select("*")
                    .in("workout_exercise_id", values: ids)
                    .order("set_number", ascending: true)
                    .execute()
                let sets = try JSONDecoder.supabase().decode([SetRow].self, from: sRes.data)
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
            
            await MainActor.run {
                setsByExercise = byEx
                totalVolumeKg = vol
            }
        } catch {
            await MainActor.run { self.error = error.localizedDescription }
        }
    }
    
    private func weightStr(_ w: Decimal?) -> String {
        guard let w else { return "0.0 kg" }
        return String(format: "%.1f kg", NSDecimalNumber(decimal: w).doubleValue)
    }
}

private struct CardioDetailBlock: View {
    let workoutId: Int
    let reloadKey: UUID
    
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
    }
    
    @State private var row: CardioRow?
    @State private var error: String?
    private struct CardioExtras: Decodable {
        let cadence_rpm: Int?
        let watts_avg: Int?
        let incline_pct: Double?
        let swim_laps: Int?
        let pool_length_m: Int?
        let swim_style: String?
        let split_sec_per_500m: Int?
    }
    @State private var extras: CardioExtras?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Cardio").font(.headline)
            
            if let r = row {
                info("Activity", activityLabel(r))
                if let d = r.distance_km { info("Distance", String(format: "%.2f km", NSDecimalNumber(decimal: d).doubleValue)) }
                if let s = r.duration_sec { info("Duration", durationString(Double(s))) }
                if let p = r.avg_pace_sec_per_km { info("Avg pace", paceString(Double(p))) }
                if let ah = r.avg_hr { info("Avg HR", "\(ah) bpm") }
                if let mh = r.max_hr { info("Max HR", "\(mh) bpm") }
                if let elev = r.elevation_gain_m { info("Elevation gain", "\(elev) m") }
                if let n = r.notes, !n.isEmpty { info("Notes", n) }
                if showsCadence(for: r.activity_code), let cad = extras?.cadence_rpm {
                    info("Cadence", "\(cad) \((r.activity_code ?? "") == "rowerg" ? "spm" : "rpm")")
                }
                if showsWatts(for: r.activity_code), let w = extras?.watts_avg {
                    info("Avg watts", "\(w) W")
                }
                if showsIncline(for: r.activity_code), let inc = extras?.incline_pct {
                    info("Incline", String(format: "%.1f %%", inc))
                }
                if showsSplit500m(for: r.activity_code), let split = extras?.split_sec_per_500m {
                    info("Split", "\(liftrMMSS(split)) /500m")
                }
                if showsSwimFields(for: r.activity_code) {
                    if let laps = extras?.swim_laps { info("Laps", "\(laps)") }
                    if let len  = extras?.pool_length_m { info("Pool length", "\(len) m") }
                    if let st   = extras?.swim_style, !st.isEmpty { info("Swim style", st.capitalized) }
                }
            } else {
                Text("No cardio session linked").foregroundStyle(.secondary).font(.caption)
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.18)))
        .task { await load() }
        .onChange(of: reloadKey) { _, _ in
            Task { await load() }
        }
    }
    
    private func load() async {
        do {
            let res = try await SupabaseManager.shared.client
                .from("cardio_sessions")
                .select("*")
                .eq("workout_id", value: workoutId)
                .single()
                .execute()
            let r = try JSONDecoder.supabase().decode(CardioRow.self, from: res.data)
            await MainActor.run { row = r }
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
        } catch {
            await MainActor.run { self.row = nil; self.error = error.localizedDescription }
        }
    }
    
    @ViewBuilder private func info(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.subheadline.weight(.semibold))
            Spacer()
            Text(value).font(.subheadline)
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
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
    
    @State private var row: SportRow?
    @State private var error: String?
    @State private var fb: FootballStats? = nil
    @State private var bb: BasketballStats? = nil
    @State private var rk: RacketStats? = nil
    @State private var vb: VolleyballStats? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sport").font(.headline)
            
            if let r = row {
                info("Sport", r.sport.capitalized)
                if let s = r.duration_sec { info("Duration", durationString(Double(s))) }
                if let res = r.match_result, !res.isEmpty { info("Result", res.capitalized) }
                if let sf = r.score_for, let sa = r.score_against { info("Score", "\(sf) – \(sa)") }
                if sportUsesSetText(r.sport), let mst = r.match_score_text, !mst.isEmpty { info("Sets", mst) }
                if let loc = r.location, !loc.isEmpty { info("Location", loc) }
                if let n = r.notes, !n.isEmpty {
                    info("Session notes", n)
                }
                if let s = fb {
                    Divider().padding(.vertical, 4)
                    Text("Football stats").font(.headline)
                    if let v = s.position, !v.isEmpty { info("Position", v.replacingOccurrences(of: "_", with: " ").capitalized) }
                    if let v = s.minutes_played { info("Minutes played", "\(v)") }
                    if let v = s.goals { info("Goals", "\(v)") }
                    if let v = s.assists { info("Assists", "\(v)") }
                    if let v = s.shots_on_target { info("Shots on target", "\(v)") }
                    if let v = s.passes_completed, let tot = s.passes_attempted {
                        info("Passes", "\(v)/\(tot)")
                    } else if let v = s.passes_completed {
                        info("Passes completed", "\(v)")
                    }
                    if let v = s.tackles { info("Tackles", "\(v)") }
                    if let v = s.interceptions { info("Interceptions", "\(v)") }
                    if let v = s.saves { info("Saves", "\(v)") }
                    if let v = s.yellow_cards { info("Yellow cards", "\(v)") }
                    if let v = s.red_cards { info("Red cards", "\(v)") }
                }
                
                if let s = bb {
                    Divider().padding(.vertical, 4)
                    Text("Basketball stats").font(.headline)
                    if let v = s.points { info("Points", "\(v)") }
                    if let v = s.rebounds { info("Rebounds", "\(v)") }
                    if let v = s.assists { info("Assists", "\(v)") }
                    if let v = s.steals { info("Steals", "\(v)") }
                    if let v = s.blocks { info("Blocks", "\(v)") }
                    if let m = s.fg_made, let a = s.fg_attempted { info("FG", "\(m)/\(a)") }
                    if let m = s.three_made, let a = s.three_attempted { info("3PT", "\(m)/\(a)") }
                    if let m = s.ft_made, let a = s.ft_attempted { info("FT", "\(m)/\(a)") }
                    if let v = s.turnovers { info("Turnovers", "\(v)") }
                    if let v = s.fouls { info("Fouls", "\(v)") }
                }
                
                if let s = rk {
                    Divider().padding(.vertical, 4)
                    Text("Racket stats").font(.headline)
                    if let v = s.mode { info("Mode", v.replacingOccurrences(of: "_", with: " ").capitalized) }
                    if let v = s.format { info("Format", v.replacingOccurrences(of: "_", with: " ").capitalized) }
                    if let w = s.sets_won, let l = s.sets_lost { info("Sets (W–L)", "\(w)–\(l)") }
                    if let w = s.games_won, let l = s.games_lost { info("Games (W–L)", "\(w)–\(l)") }
                    if let v = s.aces { info("Aces", "\(v)") }
                    if let v = s.double_faults { info("Double faults", "\(v)") }
                    if let v = s.winners { info("Winners", "\(v)") }
                    if let v = s.unforced_errors { info("Unforced errors", "\(v)") }
                    if let w = s.break_points_won, let t = s.break_points_total { info("Break points", "\(w)/\(t)") }
                    if let w = s.net_points_won,  let t = s.net_points_total  { info("Net points", "\(w)/\(t)") }
                }
                
                if let s = vb {
                    Divider().padding(.vertical, 4)
                    Text("Volleyball stats").font(.headline)
                    if let v = s.points { info("Points", "\(v)") }
                    if let v = s.aces { info("Aces", "\(v)") }
                    if let v = s.blocks { info("Blocks", "\(v)") }
                    if let v = s.digs { info("Digs", "\(v)") }
                }
            } else {
                Text("No sport session linked").foregroundStyle(.secondary).font(.caption)
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.18)))
        .task { await load() }
        .onChange(of: reloadKey) { _, _ in
            Task { await load() }
        }
    }
    
    private func load() async {
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
                fb = nil; bb = nil; rk = nil; vb = nil
            }
            await loadStats(for: r)
        } catch {
            await MainActor.run { self.row = nil; self.error = error.localizedDescription }
        }
    }
    
    private func loadStats(for r: SportRow) async {
        let client = SupabaseManager.shared.client
        let decoder = JSONDecoder.supabase()
        
        switch r.sport {
        case "football", "handball", "hockey", "rugby":
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
            
        default:
            break
        }
    }
    
    @ViewBuilder private func info(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.subheadline.weight(.semibold))
            Spacer()
            Text(value).font(.subheadline)
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
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
    let items: [WorkoutDetailView.CompareCandidate]
    let onPick: (Int) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(items) { c in
                Button {
                    onPick(c.id)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(c.displayTitle)
                            .font(.headline)
                            .lineLimit(1)
                        Text(c.started_at.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .listRowBackground(Color.clear)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .navigationTitle("Choose workout")
            .navigationBarTitleDisplayMode(.inline)
        }
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
