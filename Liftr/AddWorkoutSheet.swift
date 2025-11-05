import SwiftUI
import Supabase

struct Exercise: Identifiable, Decodable {
    let id: Int64
    let name: String
    let category: String?
    let modality: String?
    let muscle_primary: String?
    let equipment: String?
}

enum WorkoutIntensity: String, CaseIterable, Identifiable {
    case easy, moderate, hard, max
    var id: String { rawValue }
    var label: String {
        switch self {
        case .easy: "Easy"
        case .moderate: "Moderate"
        case .hard: "Hard"
        case .max: "Max"
        }
    }
}

enum SortMode: String, CaseIterable, Identifiable {
    case alphabetic = "Alphabetic"
    case mostUsed   = "Most used"
    case favorites  = "Favorites"
    case recent     = "Recently used"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .alphabetic: "A–Z"
        case .mostUsed:   "Más usados"
        case .favorites:  "Favoritos"
        case .recent:     "Últimos usados"
        }
    }
}

enum SportType: String, CaseIterable, Identifiable {
    case padel, tennis, football, basketball, badminton, squash, table_tennis, volleyball, handball, hockey, rugby
    var id: String { rawValue }
    var label: String {
        switch self {
        case .padel: "Padel"
        case .tennis: "Tennis"
        case .football: "Football"
        case .basketball: "Basketball"
        case .badminton: "Badminton"
        case .squash: "Squash"
        case .table_tennis: "Table Tennis"
        case .volleyball: "Volleyball"
        case .handball: "Handball"
        case .hockey: "Hockey"
        case .rugby: "Rugby"
        }
    }
}

enum MatchResult: String, CaseIterable, Identifiable {
    case win, loss, draw, unfinished, forfeit
    var id: String { rawValue }
    var label: String {
        switch self {
        case .win: "Win"
        case .loss: "Loss"
        case .draw: "Draw"
        case .unfinished: "Unfinished"
        case .forfeit: "Forfeit"
        }
    }
}

enum PublishMode: String, CaseIterable, Identifiable {
    case add, plan
    var id: String { rawValue }
    var label: String { self == .add ? "Add" : "Plan" }
    var stateParam: String { self == .add ? "published" : "planned" }
}

enum RacketMode: String, CaseIterable, Identifiable {
    case singles, doubles, mixedDoubles
    var id: String { rawValue }
    var label: String {
        switch self {
        case .singles: "Singles"
        case .doubles: "Doubles"
        case .mixedDoubles: "Mixed doubles"
        }
    }
    var dbValue: String {
        switch self {
        case .singles: "singles"
        case .doubles: "doubles"
        case .mixedDoubles: "mixed_doubles"
        }
    }
}

enum RacketFormat: String, CaseIterable, Identifiable {
    case bestOfThree, bestOfFive
    var id: String { rawValue }
    var label: String { self == .bestOfThree ? "Best of 3" : "Best of 5" }
    var dbValue: String { self == .bestOfThree ? "best_of_3" : "best_of_5" }
}

enum FootballPosition: String, CaseIterable, Identifiable {
    case goalkeeper, defender, midfielder, forward
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var dbValue: String {
        switch self {
        case .goalkeeper: "goalkeeper"
        case .defender:   "defender"
        case .midfielder: "midfielder"
        case .forward:    "forward"
        }
    }
}

struct LightweightProfile: Identifiable, Decodable, Hashable {
    let user_id: UUID
    let username: String?
    let avatar_url: String?
    var id: UUID { user_id }
}
struct AddParticipantParams: Encodable {
    let p_workout_id: Int64
    let p_user_id: UUID
}

struct ExercisePickerSheet: View {
    let all: [Exercise]
    @Binding var selected: Exercise?
    @Environment(\.dismiss) private var dismiss
    
    @State private var query = ""
    @State private var sortMode: SortMode = .alphabetic
    @State private var loading = false
    @State private var exercises: [Exercise] = []
    @State private var favorites = Set<Int64>()
    
    var filtered: [Exercise] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return exercises }
        return exercises.filter { $0.name.lowercased().contains(q) }
    }
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    SectionCard {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(filtered.enumerated()), id: \.element.id) { idx, ex in
                                HStack(alignment: .center, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(ex.name)
                                        Text(
                                            [ex.category, ex.muscle_primary, ex.equipment]
                                                .compactMap { $0 }
                                                .filter { $0.lowercased() != "strength" }
                                                .joined(separator: " · ")
                                        )
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    Button {
                                        Task { await toggleFavorite(ex.id) }
                                    } label: {
                                        Image(systemName: favorites.contains(ex.id) ? "star.fill" : "star")
                                            .font(.subheadline)
                                            .foregroundStyle(favorites.contains(ex.id) ? .yellow : .secondary)
                                            .opacity(0.9)
                                            .frame(width: 32, height: 32)
                                            .contentShape(Rectangle())
                                            .accessibilityLabel(favorites.contains(ex.id) ? "Unfavorite" : "Favorite")
                                            .accessibilityAddTraits(.isButton)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.vertical, 10)
                                .padding(.horizontal, 8)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selected = ex
                                    dismiss()
                                }
                                if idx < filtered.count - 1 {
                                    Divider()
                                        .padding(.leading, 8)
                                        .opacity(0.75)
                                }
                            }
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listSectionSeparator(.hidden, edges: .top)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .searchable(text: $query)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        ForEach(SortMode.allCases) { mode in
                            Button(mode.label) {
                                sortMode = mode
                                Task { await loadExercises() }
                            }
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                    .accessibilityLabel("Filter")
                }
            }
            .scrollContentBackground(.hidden)
            .listRowBackground(Color.clear)
            .toolbarBackground(.hidden, for: .navigationBar)
            .overlay {
                if loading {
                    ProgressView("Loading…")
                        .padding()
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .task { await loadExercises() }
        }
    }
    
    private func loadExercises() async {
        loading = true
        defer { loading = false }
        do {
            await loadFavorites()
            
            switch sortMode {
            case .alphabetic:
                let res = try await SupabaseManager.shared.client
                    .from("exercises")
                    .select("*")
                    .eq("is_public", value: true)
                    .eq("modality", value: "strength")
                    .order("name", ascending: true)
                    .execute()
                exercises = try JSONDecoder().decode([Exercise].self, from: res.data)
                
            case .mostUsed:
                let params: [String: AnyJSON] = [
                    "p_modality": try .init("strength"),
                    "p_search":   try .init(AnyJSON.null),
                    "p_limit":    try .init(200)
                ]
                let res = try await SupabaseManager.shared.client
                    .rpc("get_exercises_usage", params: params)
                    .execute()
                let used = try JSONDecoder.supabaseCustom().decode([ExerciseUsage].self, from: res.data)
                exercises = used.map { Exercise(id: $0.id, name: $0.name, category: nil, modality: "strength", muscle_primary: nil, equipment: nil) }
                
            case .favorites:
                if favorites.isEmpty {
                    exercises = []
                } else {
                    let ids = favorites.map(Int.init)
                    let res = try await SupabaseManager.shared.client
                        .from("exercises")
                        .select("*")
                        .eq("is_public", value: true)
                        .eq("modality", value: "strength")
                        .in("id", values: ids)
                        .order("name", ascending: true)
                        .execute()
                    exercises = try JSONDecoder().decode([Exercise].self, from: res.data)
                }
            case .recent:
                let params: [String: AnyJSON] = [
                    "p_modality": try .init("strength"),
                    "p_search":   try .init(AnyJSON.null),
                    "p_limit":    try .init(200)
                ]
                let res = try await SupabaseManager.shared.client
                    .rpc("get_exercises_usage", params: params)
                    .execute()
                
                let used = try JSONDecoder.supabaseCustom().decode([ExerciseUsage].self, from: res.data)
                
                let sorted = used
                    .filter { $0.last_used_at != nil && $0.times_used > 0 }
                    .sorted { (a, b) in
                        (a.last_used_at ?? .distantPast) > (b.last_used_at ?? .distantPast)
                    }
                
                exercises = sorted.map {
                    Exercise(
                        id: $0.id,
                        name: $0.name,
                        category: nil,
                        modality: "strength",
                        muscle_primary: nil,
                        equipment: nil
                    )
                }
            }
        } catch {
            print("Error loading exercises:", error)
        }
    }
    
    private func loadFavorites() async {
        do {
            let res = try await SupabaseManager.shared.client
                .from("user_favorite_exercises")
                .select("exercise_id")
                .execute()
            
            struct Row: Decodable { let exercise_id: Int64 }
            let rows = try JSONDecoder().decode([Row].self, from: res.data)
            
            await MainActor.run {
                favorites = Set(rows.map { $0.exercise_id })
            }
        } catch {
            print("Error loading favorites:", error)
        }
    }
    
    private struct FavoriteRow: Encodable {
        let user_id: UUID
        let exercise_id: Int64
    }
    
    private func toggleFavorite(_ exerciseId: Int64) async {
        let client = SupabaseManager.shared.client
        
        if favorites.contains(exerciseId) {
            await MainActor.run {
                _ = favorites.remove(exerciseId)
                if sortMode == .favorites {
                    exercises.removeAll { $0.id == exerciseId }
                }
            }
            
            do {
                let session = try await client.auth.session
                _ = try await client
                    .from("user_favorite_exercises")
                    .delete()
                    .eq("user_id", value: session.user.id)
                    .eq("exercise_id", value: Int(exerciseId))
                    .execute()
            } catch {
                await MainActor.run { _ = favorites.insert(exerciseId) }
                print("Error unfavorite:", error)
            }
        } else {
            await MainActor.run { _ = favorites.insert(exerciseId) }
            
            do {
                let session = try await client.auth.session
                struct FavInsert: Encodable { let user_id: UUID; let exercise_id: Int }
                let row = FavInsert(user_id: session.user.id, exercise_id: Int(exerciseId))
                
                _ = try await client
                    .from("user_favorite_exercises")
                    .upsert([row], onConflict: "user_id,exercise_id", returning: .minimal)
                    .execute()
            } catch let err as PostgrestError {
                if err.code != "23505" {
                    await MainActor.run { _ = favorites.remove(exerciseId) }
                    print("Error favorite:", err)
                }
            } catch {
                await MainActor.run { _ = favorites.remove(exerciseId) }
                print("Error favorite:", error)
            }
        }
    }
}

struct ExerciseUsage: Decodable {
    let id: Int64
    let name: String
    let times_used: Int
    let last_used_at: Date?
}

private struct PickerHandle: Identifiable {
    let id: UUID
}

private struct SectionCard<Content: View>: View {
    @ViewBuilder var content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    
    var body: some View {
        VStack(spacing: 0) { content }
            .padding(12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.22), lineWidth: 0.8))
            .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
    }
}

private struct FieldRowPlain<Content: View>: View {
    let title: String?
    @ViewBuilder var content: Content
    init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title; self.content = content()
    }
    
    var body: some View {
        LabeledContent {
            content
                .labelsHidden()
        } label: {
            if let title { Text(title) }
        }
        .padding(.vertical, 10)
    }
}

struct AddWorkoutDraft {
    var kind: WorkoutKind
    var title: String = ""
    var note: String = ""
    var participants: [LightweightProfile] = []
    var startedAt: Date = .now
    var endedAt: Date? = nil
    var perceived: WorkoutIntensity = .moderate
    var strengthItems: [EditableExercise] = []
    var cardio: CardioForm? = nil
    var sport: SportForm? = nil
}

struct AddWorkoutSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var app: AppState
    
    @State private var kind: WorkoutKind = .strength
    @State private var title: String = ""
    @State private var note: String = ""
    @State private var startedAt: Date = .now
    @State private var endedAtEnabled: Bool = false
    @State private var endedAt: Date = .now
    @State private var items: [EditableExercise] = [EditableExercise()]
    @State private var cardio = CardioForm()
    @State private var sport = SportForm()
    @State private var catalog: [Exercise] = []
    @State private var loadingCatalog = false
    @State private var pickerHandle: PickerHandle? = nil
    @State private var loading = false
    @State private var error: String?
    @State private var perceived: WorkoutIntensity = .moderate
    @State private var banner: Banner?
    @State private var recentlyAddedExerciseId: UUID? = nil
    @State private var participants: [LightweightProfile] = []
    @State private var needsInitialSync = false
    @State private var didEditCardioDuration = false
    @State private var didEditSportDuration  = false
    @State private var showParticipantsPicker = false
    @State private var confirmRemoveIndex: Int? = nil
    @State private var publishMode: PublishMode = .add
    @State private var durationLabelMin: Int? = nil
    @State private var didApplyDraft = false
    @State private var isApplyingDraft = false
    
    var body: some View {
        NavigationStack {
            GradientBackground {
                Form {
                    Section {
                        SectionCard {
                            FieldRowPlain("Type") {
                                Picker("", selection: $kind) {
                                    Text("Strength").tag(WorkoutKind.strength)
                                    Text("Cardio").tag(WorkoutKind.cardio)
                                    Text("Sport").tag(WorkoutKind.sport)
                                }
                                .pickerStyle(.menu)
                                .onChange(of: kind) { _, new in
                                    if new == .strength { Task { await loadCatalogIfNeeded() } }
                                    didEditCardioDuration = false
                                    didEditSportDuration  = false
                                    recomputeDurationLabel()
                                    syncDurationFromDates()
                                }
                            }
                            Divider()
                            FieldRowPlain("Mode") {
                                Picker("", selection: $publishMode) {
                                    ForEach(PublishMode.allCases) { Text($0.label).tag($0) }
                                }.pickerStyle(.segmented)
                            }
                            Divider()
                            FieldRowPlain("Title") { TextField("Title (optional)", text: $title).textFieldStyle(.plain) }
                            Divider()
                            FieldRowPlain("Started at") {
                                DatePicker("", selection: $startedAt, displayedComponents: [.date, .hourAndMinute])
                                    .onChange(of: startedAt) { _, _ in
                                        if endedAtEnabled, endedAt < startedAt { endedAt = startedAt }
                                        didEditCardioDuration = false
                                        didEditSportDuration  = false
                                        recomputeDurationLabel()
                                        syncDurationFromDates()
                                    }
                            }
                            Divider()
                            FieldRowPlain("Finished") {
                                Toggle("", isOn: $endedAtEnabled)
                                    .onChange(of: endedAtEnabled) { _, isOn in
                                        if isOn { endedAt = max(endedAt, startedAt) }
                                        didEditCardioDuration = false
                                        didEditSportDuration  = false
                                        recomputeDurationLabel()
                                        syncDurationFromDates()
                                    }
                            }
                            
                            if endedAtEnabled {
                                Divider()
                                FieldRowPlain("Ended at") {
                                    DatePicker("", selection: $endedAt, in: startedAt..., displayedComponents: [.date, .hourAndMinute])
                                        .onChange(of: endedAt) { _, _ in
                                            didEditCardioDuration = false
                                            didEditSportDuration  = false
                                            recomputeDurationLabel()
                                            syncDurationFromDates()
                                        }
                                }
                                if let dur = durationLabelMin {
                                    Divider()
                                    Text("Duration: \(dur) min")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                        .padding(.vertical, 6)
                                }
                            }
                            
                            Divider()
                            FieldRowPlain("Notes") { TextField("Notes", text: $note, axis: .vertical).textFieldStyle(.plain) }
                            Divider()
                            FieldRowPlain("Intensity") {
                                Picker("", selection: $perceived) {
                                    ForEach(WorkoutIntensity.allCases) { Text($0.label).tag($0) }
                                }.pickerStyle(.menu)
                            }
                        }
                    } header: {
                        Text("GENERAL").foregroundStyle(.secondary)
                    }
                    .listRowBackground(Color.clear)
                    
                    Section {
                        SectionCard {
                            if participants.isEmpty {
                                Text("No participants added")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 4)
                            } else {
                                ForEach(participants, id: \.id) { p in
                                    HStack {
                                        Text(p.username ?? p.user_id.uuidString)
                                            .lineLimit(1)
                                            .truncationMode(.tail)
                                        Spacer()
                                        Button(role: .destructive) {
                                            participants.removeAll { $0.id == p.id }
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                        }
                                        .buttonStyle(.borderless)
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                            
                            Divider().padding(.vertical, 6)
                            
                            Button {
                                showParticipantsPicker = true
                            } label: {
                                Label("Add participants", systemImage: "person.crop.circle.badge.plus")
                            }
                            .buttonStyle(.borderless)
                        }
                    } header: {
                        Text("PARTICIPANTS").foregroundStyle(.secondary)
                    }
                    .listRowBackground(Color.clear)
                    
                    switch kind {
                    case .strength:
                        strengthSection
                            .task { await loadCatalogIfNeeded() }
                    case .cardio:
                        cardioSection
                    case .sport:
                        sportSection
                    }
                    
                    if let error {
                        Section { Text(error).foregroundStyle(.red) }
                    }
                }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
                .listRowBackground(Color.clear)
                .listSectionSpacing(-10)
                .sheet(item: $pickerHandle) { handle in
                    if let idx = items.firstIndex(where: { $0.id == handle.id }) {
                        ExercisePickerSheet(
                            all: catalog,
                            selected: Binding(
                                get: {
                                    guard let exid = items[idx].exerciseId else { return nil }
                                    return catalog.first(where: { $0.id == exid })
                                },
                                set: { picked in
                                    items[idx].exerciseId = picked?.id
                                    if items[idx].exerciseName.isEmpty {
                                        items[idx].exerciseName = picked?.name ?? ""
                                    }
                                }
                            )
                        )
                        .gradientBG()
                        .presentationDetents([.large])
                        .presentationBackground(.clear)
                    } else {
                        ExercisePickerSheet(all: catalog, selected: .constant(nil))
                            .gradientBG()
                            .presentationDetents([.large])
                            .presentationBackground(.clear)
                    }
                }
            }
        }
        .onAppear {
            if !didApplyDraft, let d = app.addDraft {
                isApplyingDraft = true
                applyDraft(d)
                didApplyDraft = true
                isApplyingDraft = false
            }
            if needsInitialSync {
                needsInitialSync = false
                recomputeDurationLabel()
                syncDurationFromDates()
            }
        }
        .sheet(isPresented: $showParticipantsPicker) {
            ParticipantsPickerSheet(
                alreadySelected: Set(participants),
                onPick: { picked in
                    let set = Set(participants).union(picked)
                    participants = Array(set)
                }
            )
            .gradientBG()
            .presentationDetents([.large])
            .presentationBackground(.clear)
        }
        .onChange(of: app.addDraftKey) { _, _ in
            if let d = app.addDraft {
                isApplyingDraft = true
                applyDraft(d)
                didApplyDraft = true
                isApplyingDraft = false
            }
        }
        .banner($banner)
        .alert(
            "Are you sure you want to remove the exercise?",
            isPresented: Binding(
                get: { confirmRemoveIndex != nil },
                set: { if !$0 { confirmRemoveIndex = nil } }
            )
        ) {
            Button("Remove", role: .destructive) {
                if let idx = confirmRemoveIndex {
                    items.remove(at: idx)
                }
                confirmRemoveIndex = nil
            }
            Button("Cancel", role: .cancel) {
                confirmRemoveIndex = nil
            }
        }
    }
    
    private var saveButton: some View {
        Button {
            Task { await save() }
        } label: {
            HStack {
                if loading { ProgressView().tint(.white) }
                Text(loading ? "Saving…" : "Save")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background((!loading && canSave) ? Color.blue : Color.gray.opacity(0.5),
                        in: RoundedRectangle(cornerRadius: 14))
            .foregroundStyle(.white)
        }
        .disabled(loading || !canSave)
    }
    
    private var strengthSection: some View {
        Section {
            SectionCard {
                ForEach(items.indices, id: \.self) { i in
                    if i != items.startIndex { Divider().padding(.vertical, 6) }
                    
                    VStack(spacing: 0) {
                        
                        FieldRowPlain("Exercise") {
                            Button {
                                pickerHandle = .init(id: items[i].id)
                            } label: {
                                HStack {
                                    Image(systemName: "list.bullet.rectangle.portrait")
                                    Text(exerciseLabel(for: items[i]))
                                        .foregroundStyle(exerciseSelected(items[i]) ? .primary : .secondary)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                    Spacer()
                                    if loadingCatalog { ProgressView() }
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(loadingCatalog || catalog.isEmpty)
                        }
                        
                        Divider()
                        
                        FieldRowPlain("Alias") {
                            TextField("Exercise name (optional)", text: $items[i].exerciseName)
                                .textFieldStyle(.plain)
                        }
                        
                        Divider()
                        
                        FieldRowPlain("Notes") {
                            TextField("Notes (exercise)", text: $items[i].notes)
                                .textFieldStyle(.plain)
                        }
                        
                        ForEach(items[i].sets.indices, id: \.self) { s in
                            Divider()
                            HStack(spacing: 6) {
                                Text("Set \(items[i].sets[s].setNumber)")
                                    .font(.subheadline)
                                    .frame(width: 46, alignment: .leading)
                                
                                Stepper("", value: $items[i].sets[s].setNumber, in: 1...99)
                                    .labelsHidden()
                                    .controlSize(.mini)
                                    .scaleEffect(0.74, anchor: .leading)
                                    .frame(width: 64)
                                
                                TextField("Reps", value: $items[i].sets[s].reps, format: .number)
                                    .keyboardType(.numberPad)
                                    .frame(width: 44)
                                
                                TextField("Weight kg", text: $items[i].sets[s].weightKg)
                                    .keyboardType(.decimalPad)
                                    .frame(width: 70)
                                
                                TextField("RPE", text: $items[i].sets[s].rpe)
                                    .keyboardType(.decimalPad)
                                    .frame(width: 38)
                                
                                TextField("Rest s", value: $items[i].sets[s].restSec, format: .number)
                                    .keyboardType(.numberPad)
                                    .frame(width: 54)
                                
                                if items[i].sets.count > 1 {
                                    Button(role: .destructive) {
                                        items[i].sets.remove(at: s)
                                    } label: { Image(systemName: "minus.circle.fill") }
                                        .buttonStyle(.borderless)
                                }
                            }
                        }
                        
                        Divider().padding(.vertical, 4)
                        HStack {
                            Button {
                                items[i].sets.append(EditableSet(setNumber: 1))
                            } label: { Label("Add set", systemImage: "plus.circle") }
                                .buttonStyle(.borderless)
                            
                            Spacer()
                            
                            if items.count > 1 {
                                Button(role: .destructive) {
                                    confirmRemoveIndex = i
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "trash")
                                        Text("Remove exercise")
                                    }
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                        
                    }
                    .padding(6)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.yellow.opacity(items[i].id == recentlyAddedExerciseId ? 0.18 : 0))
                    )
                    .animation(.easeInOut(duration: 0.6), value: recentlyAddedExerciseId)
                }
                
                Divider().padding(.vertical, 6)
                Button {
                    let nextOrder = (items.last?.orderIndex ?? 0) + 1
                    let new = EditableExercise(orderIndex: nextOrder)
                    items.append(new)
                    recentlyAddedExerciseId = new.id
                    Task {
                        try? await Task.sleep(nanoseconds: 1_200_000_000)
                        await MainActor.run {
                            if recentlyAddedExerciseId == new.id { recentlyAddedExerciseId = nil }
                        }
                    }
                } label: {
                    Label("Add exercise", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                .padding(.top, 2)
            }
            
            saveButton
                .padding(.top, 8)
        } header: {
            Text("EXERCISES").foregroundStyle(.secondary)
        }
        .listRowBackground(Color.clear)
    }
    
    private var cardioSection: some View {
        Section {
            SectionCard {
                FieldRowPlain {
                    TextField("Modality (e.g. Run, Bike…)", text: $cardio.modality)
                        .textFieldStyle(.plain)
                }
                
                Divider()
                
                HStack(spacing: 12) {
                    TextField("Distance (km)", text: $cardio.distanceKm)
                        .keyboardType(.decimalPad)
                        .onChange(of: cardio.distanceKm) { _, _ in
                            updateAutoPaceIfNeeded()
                        }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Duration").font(.caption).foregroundStyle(.secondary)
                        HStack(spacing: 6) {
                            TextField("h", text: $cardio.durH)
                                .keyboardType(.numberPad)
                                .frame(width: 36)
                                .onChange(of: cardio.durH) { _, _ in
                                    didEditCardioDuration = true
                                    updateAutoPaceIfNeeded()
                                }
                            
                            Text(":")
                            
                            TextField("m", text: $cardio.durM)
                                .keyboardType(.numberPad)
                                .frame(width: 36)
                                .onChange(of: cardio.durM) { _, _ in updateAutoPaceIfNeeded() }
                            
                            Text(":")
                            
                            TextField("s", text: $cardio.durS)
                                .keyboardType(.numberPad)
                                .frame(width: 36)
                                .onChange(of: cardio.durS) { _, _ in updateAutoPaceIfNeeded() }
                        }
                        .font(.subheadline)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                Divider()
                
                HStack {
                    TextField("Avg HR", text: $cardio.avgHR).keyboardType(.numberPad)
                    TextField("Max HR", text: $cardio.maxHR).keyboardType(.numberPad)
                }
                
                Divider()
                
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Avg pace (/km)").font(.caption).foregroundStyle(.secondary)
                        if let p = autoPaceSec(distanceKmText: cardio.distanceKm,
                                               durH: cardio.durH, durM: cardio.durM, durS: cardio.durS) {
                            Text(String(format: "%d:%02d /km", p/60, p%60))
                                .font(.subheadline.weight(.semibold))
                        } else {
                            Text("—").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    TextField("Elevation gain (m)", text: $cardio.elevationGainM)
                        .keyboardType(.numberPad)
                }
                Divider()
            }
            
            saveButton
                .padding(.top, 8)
        } header: {
            Text("CARDIO").foregroundStyle(.secondary)
        }
        .listRowBackground(Color.clear)
    }
    
    private var sportSection: some View {
        Section {
            SectionCard {
                FieldRowPlain {
                    Picker("", selection: $sport.sport) {
                        ForEach(SportType.allCases.filter { $0 != .hockey && $0 != .handball && $0 != .rugby }) { s in
                            Text(s.label).tag(s)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: sport.sport) { _, new in
                        if sportUsesNumericScore(new) {
                            sport.matchScoreText = ""
                        } else if sportUsesSetText(new) {
                            sport.scoreFor = ""; sport.scoreAgainst = ""
                        }
                    }
                }
                
                Divider()
                
                FieldRowPlain {
                    TextField("Duration (min)", text: $sport.durationMin)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.plain)
                        .onChange(of: sport.durationMin) { _, _ in
                            didEditSportDuration = true
                        }
                }
                
                if sportUsesNumericScore(sport.sport) {
                    Divider()
                    FieldRowPlain {
                        HStack {
                            TextField("Score for", text: $sport.scoreFor).keyboardType(.numberPad)
                            TextField("Score against", text: $sport.scoreAgainst).keyboardType(.numberPad)
                        }
                    }
                }
                
                if sportUsesSetText(sport.sport) {
                    Divider()
                    FieldRowPlain {
                        TextField("Match score text (e.g. 6/3 6/4 6/4)", text: $sport.matchScoreText)
                            .textFieldStyle(.plain)
                    }
                }
                
                Divider()
                FieldRowPlain {
                    TextField("Location (optional)", text: $sport.location)
                        .textFieldStyle(.plain)
                }
                Divider()
                
                Divider()

                FieldRowPlain {
                    Picker("", selection: $sport.matchResult) {
                        ForEach(MatchResult.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.menu)
                }
                
                sportSpecificFields()
                
                Divider()
                
                FieldRowPlain {
                    TextField("Session notes (optional)", text: $sport.sessionNotes, axis: .vertical)
                        .textFieldStyle(.plain)
                }
            }
            
            saveButton
                .padding(.top, 8)
        } header: {
            Text("SPORT").foregroundStyle(.secondary)
        }
        .listRowBackground(Color.clear)
    }
    
    private var canSave: Bool {
        switch kind {
        case .strength:
            guard items.contains(where: { exerciseSelected($0) }) else { return false }
            for ex in items where exerciseSelected(ex) {
                let hasValidSet = ex.cleanSets().contains { $0.reps != nil }
                if !hasValidSet { return false }
            }
            return true
        case .cardio:
            return !cardio.modality.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .sport:
            return true
        }
    }
    
    @ViewBuilder
    private func sportSpecificFields() -> some View {
        switch sport.sport {
        case .football:
            Divider()
            FieldRowPlain {
                Picker("", selection: $sport.fbPosition) {
                    ForEach(FootballPosition.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.menu)
            }
            Divider()
            FieldRowPlain {
                HStack {
                    TextField("Assists", text: $sport.fbAssists).keyboardType(.numberPad)
                    TextField("Shots on target", text: $sport.fbShotsOnTarget).keyboardType(.numberPad)
                }
            }
            Divider()
            FieldRowPlain {
                HStack {
                    TextField("Passes completed", text: $sport.fbPassesCompleted).keyboardType(.numberPad)
                    TextField("Tackles", text: $sport.fbTackles).keyboardType(.numberPad)
                }
            }
            Divider()
            FieldRowPlain {
                HStack {
                    TextField("Saves (GK)", text: $sport.fbSaves).keyboardType(.numberPad)
                    TextField("Yellow cards", text: $sport.fbYellow).keyboardType(.numberPad)
                    TextField("Red cards", text: $sport.fbRed).keyboardType(.numberPad)
                }
            }
            
        case .basketball:
            Divider()
            FieldRowPlain {
                HStack {
                    TextField("Points", text: $sport.bbPoints).keyboardType(.numberPad)
                    TextField("Rebounds", text: $sport.bbRebounds).keyboardType(.numberPad)
                    TextField("Assists", text: $sport.bbAssists).keyboardType(.numberPad)
                }
            }
            Divider()
            FieldRowPlain {
                HStack {
                    TextField("Steals", text: $sport.bbSteals).keyboardType(.numberPad)
                    TextField("Blocks", text: $sport.bbBlocks).keyboardType(.numberPad)
                    TextField("Turnovers", text: $sport.bbTurnovers).keyboardType(.numberPad)
                }
            }
            Divider()
            FieldRowPlain {
                TextField("Fouls", text: $sport.bbFouls).keyboardType(.numberPad)
            }
            
        case .padel, .tennis, .badminton, .squash, .table_tennis:
            Divider()
            FieldRowPlain {
                Picker("", selection: $sport.racketMode) {
                    ForEach(RacketMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.menu)
            }
            Divider()
            FieldRowPlain {
                Picker("", selection: $sport.racketFormat) {
                    ForEach(RacketFormat.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            Divider()
            FieldRowPlain {
                HStack {
                    TextField("Aces",            text: $sport.rkAces).keyboardType(.numberPad)
                    TextField("Double faults",   text: $sport.rkDoubleFaults).keyboardType(.numberPad)
                    TextField("Winners",         text: $sport.rkWinners).keyboardType(.numberPad)
                }
            }
            
            Divider()
            FieldRowPlain {
                TextField("Unforced errors", text: $sport.rkUnforcedErrors).keyboardType(.numberPad)
            }
            Divider()
            FieldRowPlain {
                HStack {
                    TextField("Sets won",  text: $sport.rkSetsWon).keyboardType(.numberPad)
                    TextField("Sets lost", text: $sport.rkSetsLost).keyboardType(.numberPad)
                }
            }

            Divider()
            FieldRowPlain {
                HStack {
                    TextField("Games won",  text: $sport.rkGamesWon).keyboardType(.numberPad)
                    TextField("Games lost", text: $sport.rkGamesLost).keyboardType(.numberPad)
                }
            }

            Divider()
            FieldRowPlain {
                HStack {
                    TextField("Break pts won",   text: $sport.rkBreakPointsWon).keyboardType(.numberPad)
                    TextField("Break pts total", text: $sport.rkBreakPointsTotal).keyboardType(.numberPad)
                }
            }

            Divider()
            FieldRowPlain {
                HStack {
                    TextField("Net pts won",   text: $sport.rkNetPointsWon).keyboardType(.numberPad)
                    TextField("Net pts total", text: $sport.rkNetPointsTotal).keyboardType(.numberPad)
                }
            }
            
        case .volleyball:
            Divider()
            FieldRowPlain {
                HStack {
                    TextField("Points", text: $sport.vbPoints).keyboardType(.numberPad)
                    TextField("Aces", text: $sport.vbAces).keyboardType(.numberPad)
                }
            }
            
        case .handball, .hockey, .rugby:
            Divider()
            FieldRowPlain {
                HStack {
                    Text("Use 'Score for/against' arriba y notes si necesitas más detalles.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
    
    private func recomputeDurationLabel() {
        guard endedAtEnabled else { durationLabelMin = nil; return }
        let secs = Int(endedAt.timeIntervalSince(startedAt))
        durationLabelMin = secs > 0 ? secs / 60 : 0
    }
    
    private func save() async {
        error = nil
        loading = true
        defer { loading = false }
        
        do {
            let client = SupabaseManager.shared.client
            let session = try await client.auth.session
            let userId = session.user.id
            var newWorkoutId: Int64? = nil
            
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            
            switch kind {
            case .strength:
                let strengthItems = items.compactMap { $0.toStrengthItem() }
                let params = RPCStrengthParams(
                    p_user_id: userId,
                    p_items: strengthItems,
                    p_title: title.isEmpty ? nil : title,
                    p_started_at: iso.string(from: startedAt),
                    p_ended_at: endedAtEnabled ? iso.string(from: endedAt) : nil,
                    p_notes: note.isEmpty ? nil : note,
                    p_perceived_intensity: perceived.rawValue,
                    p_state: publishMode.stateParam
                )
                _ = try await client.rpc("create_strength_workout", params: params).execute()
                if newWorkoutId == nil {
                    newWorkoutId = try await fetchLastWorkoutId(for: userId, kind: .strength)
                }
                
            case .cardio:
                let durSecHMS = hmsToSeconds(cardio.durH, cardio.durM, cardio.durS)
                let paceAuto  = autoPaceSec(distanceKmText: cardio.distanceKm,
                                            durH: cardio.durH, durM: cardio.durM, durS: cardio.durS)
                
                let params = RPCCardioParams(
                    p_user_id: userId,
                    p_modality: cardio.modality,
                    p_title: title.isEmpty ? nil : title,
                    p_started_at: iso.string(from: startedAt),
                    p_ended_at: endedAtEnabled ? iso.string(from: endedAt) : nil,
                    p_notes: note.isEmpty ? nil : note,
                    p_distance_km: parseDouble(cardio.distanceKm),
                    p_duration_sec: durSecHMS ?? parseInt(cardio.durationSec),
                    p_avg_hr: parseInt(cardio.avgHR),
                    p_max_hr: parseInt(cardio.maxHR),
                    p_avg_pace_sec_per_km: paceAuto ?? parseInt(cardio.avgPaceSecPerKm),
                    p_elevation_gain_m: parseInt(cardio.elevationGainM),
                    p_perceived_intensity: perceived.rawValue,
                    p_state: publishMode.stateParam
                )
                
                let res = try await client
                    .rpc("create_cardio_workout_v1", params: RPCCardioWrapper(p: params))
                    .execute()
                if let created = try? JSONDecoder().decode(Int.self, from: res.data) {
                    newWorkoutId = Int64(created)
                }
                
            case .sport:
                if sport.sport == .hockey || sport.sport == .handball || sport.sport == .rugby {
                    self.error = "El deporte \(sport.sport.label) aún no está soportado."
                    return
                }
                let minutes: Int?
                if let typed = parseInt(sport.durationMin) {
                    minutes = typed
                } else if let fromLabel = durationLabelMin {
                    minutes = fromLabel
                } else if endedAtEnabled {
                    minutes = max(1, Int(endedAt.timeIntervalSince(startedAt)) / 60)
                } else {
                    minutes = nil
                }
                let durationMin = minutes
                let scoreFor      = sportUsesNumericScore(sport.sport) ? parseInt(sport.scoreFor) : nil
                let scoreAgainst  = sportUsesNumericScore(sport.sport) ? parseInt(sport.scoreAgainst) : nil
                let matchScoreTxt = sportUsesSetText(sport.sport) ? sport.matchScoreText.trimmedOrNil : nil
                let payload = RPCSportParams(
                    p_user_id: userId,
                    p_sport: sport.sport.rawValue,
                    p_title: title.isEmpty ? nil : title,
                    p_started_at: iso.string(from: startedAt),
                    p_ended_at: endedAtEnabled ? iso.string(from: endedAt) : nil,
                    p_notes: note.isEmpty ? nil : note,
                    p_duration_min: durationMin,
                    p_duration_sec: nil,
                    p_score_for: scoreFor,
                    p_score_against: scoreAgainst,
                    p_match_result: sport.matchResult.rawValue,
                    p_match_score_text: matchScoreTxt,
                    p_location: sport.location.trimmedOrNil,
                    p_session_notes: sport.sessionNotes.trimmedOrNil,
                    p_perceived_intensity: perceived.rawValue,
                    p_state: publishMode.stateParam
                )
                
                let statsJSON = try buildSportStatsJSON(from: sport)
                
                let res = try await client
                    .rpc("create_sport_workout_v2", params: RPCSportV2Wrapper(p: payload, p_stats: statsJSON))
                    .execute()
                
                if let created = try? JSONDecoder().decode(Int.self, from: res.data) {
                    newWorkoutId = Int64(created)
                }
            }
            if let wid = newWorkoutId {
                await addParticipants(to: wid)
            }
            await showSuccessAndGoHome(publishMode == .add ? "Workout published! 💪" : "Workout planned! 🗓️")
        } catch {
            self.error = error.localizedDescription
        }
    }
    
    @MainActor
    private func resetForm() {
        kind = .strength
        title = ""
        note = ""
        startedAt = .now
        endedAtEnabled = false
        endedAt = .now
        items = [EditableExercise()]
        cardio = CardioForm()
        sport = SportForm()
        perceived = .moderate
    }
    
    @MainActor
    private func showSuccessAndGoHome(_ message: String) async {
        banner = Banner(message: message, type: .success)
        try? await Task.sleep(nanoseconds: 1_600_000_000)
        resetForm()
        app.selectedTab = .home
    }
    
    private func fetchLastWorkoutId(for userId: UUID, kind: WorkoutKind) async throws -> Int64? {
        let client = SupabaseManager.shared.client
        struct Row: Decodable { let id: Int64 }
        let res = try await client
            .from("workouts")
            .select("id")
            .eq("user_id", value: userId)
            .eq("kind", value: kind.rawValue)
            .order("id", ascending: false)
            .limit(1)
            .execute()
        let rows = try JSONDecoder().decode([Row].self, from: res.data)
        return rows.first?.id
    }
    
    private func addParticipants(to workoutId: Int64) async {
        guard !participants.isEmpty else { return }
        let client = SupabaseManager.shared.client
        for p in participants {
            do {
                let params = AddParticipantParams(p_workout_id: workoutId, p_user_id: p.user_id)
                _ = try await client.rpc("add_workout_participant", params: params).execute()
            } catch {
                print("Error adding participant \(p.user_id):", error)
            }
        }
    }
    
    private func parseInt(_ s: String) -> Int? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : Int(t)
    }
    
    private func parseDouble(_ s: String) -> Double? {
        let t = s.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : Double(t)
    }
    
    private func buildSportStatsJSON(from f: SportForm) throws -> AnyJSON {
        func strOrNil(_ s: String) -> String? {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }
        switch f.sport {
        case .football:
            var out: [String: AnyJSON] = [:]
            out["position"] = try .init(f.fbPosition.dbValue)
            if let v = parseInt(f.fbAssists)         { out["assists"]          = try .init(v) }
            if let v = parseInt(f.fbShotsOnTarget)   { out["shots_on_target"]  = try .init(v) }
            if let v = parseInt(f.fbPassesCompleted) { out["passes_completed"] = try .init(v) }
            if let v = parseInt(f.fbTackles)         { out["tackles"]          = try .init(v) }
            if let v = parseInt(f.fbSaves)           { out["saves"]            = try .init(v) }
            if let v = parseInt(f.fbYellow)          { out["yellow_cards"]     = try .init(v) }
            if let v = parseInt(f.fbRed)             { out["red_cards"]        = try .init(v) }
            return try AnyJSON(out)
            
        case .basketball:
            var out: [String: AnyJSON] = [:]
            if let v = parseInt(f.bbPoints)    { out["points"]    = try .init(v) }
            if let v = parseInt(f.bbRebounds)  { out["rebounds"]  = try .init(v) }
            if let v = parseInt(f.bbAssists)   { out["assists"]   = try .init(v) }
            if let v = parseInt(f.bbSteals)    { out["steals"]    = try .init(v) }
            if let v = parseInt(f.bbBlocks)    { out["blocks"]    = try .init(v) }
            if let v = parseInt(f.bbTurnovers) { out["turnovers"] = try .init(v) }
            if let v = parseInt(f.bbFouls)     { out["fouls"]     = try .init(v) }
            return try AnyJSON(out)
            
        case .padel, .tennis, .badminton, .squash, .table_tennis:
            var out: [String: AnyJSON] = [:]
            if let v = parseInt(f.rkAces)           { out["aces"]              = try .init(v) }
            if let v = parseInt(f.rkDoubleFaults)   { out["double_faults"]     = try .init(v) }
            if let v = parseInt(f.rkWinners)        { out["winners"]           = try .init(v) }
            if let v = parseInt(f.rkUnforcedErrors) { out["unforced_errors"]   = try .init(v) }
            if let v = parseInt(f.rkSetsWon)        { out["sets_won"]          = try .init(v) }
            if let v = parseInt(f.rkSetsLost)       { out["sets_lost"]         = try .init(v) }
            if let v = parseInt(f.rkGamesWon)       { out["games_won"]         = try .init(v) }
            if let v = parseInt(f.rkGamesLost)      { out["games_lost"]        = try .init(v) }
            if let v = parseInt(f.rkBreakPointsWon)   { out["break_points_won"]   = try .init(v) }
            if let v = parseInt(f.rkBreakPointsTotal) { out["break_points_total"] = try .init(v) }
            if let v = parseInt(f.rkNetPointsWon)     { out["net_points_won"]     = try .init(v) }
            if let v = parseInt(f.rkNetPointsTotal)   { out["net_points_total"]   = try .init(v) }
            out["racket_mode"]   = try .init(f.racketMode.dbValue)
            out["racket_format"] = try .init(f.racketFormat.dbValue)
            return try AnyJSON(out)
            
        case .volleyball:
            var out: [String: AnyJSON] = [:]
            if let v = parseInt(f.vbPoints)  { out["points"] = try .init(v) }
            if let v = parseInt(f.vbAces)    { out["aces"]   = try .init(v) }
            if let v = parseInt(f.vbBlocks)  { out["blocks"] = try .init(v) }
            if let v = parseInt(f.vbDigs)    { out["digs"]   = try .init(v) }
            return try AnyJSON(out)
            
        case .handball, .hockey, .rugby:
            let out: [String: AnyJSON] = [:]
            return try AnyJSON(out)
        }
    }
    
    private func exerciseSelected(_ ex: EditableExercise) -> Bool {
        ex.exerciseId != nil
    }
    
    private func exerciseLabel(for ex: EditableExercise) -> String {
        if let exid = ex.exerciseId,
           let found = catalog.first(where: { $0.id == exid }) {
            return found.name
        }
        return catalog.isEmpty ? "Loading exercises…" : "Choose exercise"
    }
    
    private func loadCatalogIfNeeded() async {
        guard catalog.isEmpty && !loadingCatalog else { return }
        loadingCatalog = true
        defer { loadingCatalog = false }
        do {
            let res = try await SupabaseManager.shared.client
                .from("exercises")
                .select("*")
                .eq("is_public", value: true)
                .eq("modality", value: "strength")
                .order("name", ascending: true)
                .execute()
            
            catalog = try JSONDecoder().decode([Exercise].self, from: res.data)
        } catch {
        }
    }
    
    private func autoPaceSec(distanceKmText: String, durH: String, durM: String, durS: String) -> Int? {
        guard let dist = parseDouble(distanceKmText), dist > 0,
              let dur = hmsToSeconds(durH, durM, durS) else { return nil }
        return Int((Double(dur) / dist).rounded())
    }
    
    private func secondsToHMS(_ sec: Int) -> (h: Int, m: Int, s: Int) {
        let h = sec / 3600
        let m = (sec % 3600) / 60
        let s = sec % 60
        return (h, m, s)
    }
    
    private func updateAutoPaceIfNeeded() {
        guard let p = autoPaceSec(distanceKmText: cardio.distanceKm,
                                  durH: cardio.durH, durM: cardio.durM, durS: cardio.durS)
        else { return }
        let (h,m,s) = secondsToHMS(p)
        cardio.paceH = h == 0 ? "" : String(h)
        cardio.paceM = String(m)
        cardio.paceS = String(s)
    }
    
    private func syncDurationFromDates() {
        guard endedAtEnabled, endedAt >= startedAt else { return }
        let totalSec = Int(endedAt.timeIntervalSince(startedAt))
        guard totalSec > 0 else { return }
        
        switch kind {
        case .cardio:
            guard !didEditCardioDuration else { return }
            let h = totalSec / 3600
            let m = (totalSec % 3600) / 60
            let s = totalSec % 60
            cardio.durH = h == 0 ? "" : String(h)
            cardio.durM = String(m)
            cardio.durS = String(s)
            updateAutoPaceIfNeeded()
            
        case .sport:
            guard !didEditSportDuration else { return }
            let minutes = max(1, totalSec / 60)
            sport.durationMin = String(minutes)
            
        case .strength:
            break
        }
        recomputeDurationLabel()
    }
    
    private func applyDraft(_ d: AddWorkoutDraft) {
        kind      = d.kind
        title     = d.title
        note      = d.note
        startedAt = d.startedAt
        if let end = d.endedAt {
            endedAtEnabled = true
            endedAt = max(end, startedAt)
        } else {
            endedAtEnabled = false
            endedAt = startedAt
        }
        perceived   = d.perceived
        participants = d.participants
        
        // Contenido por tipo
        switch d.kind {
        case .strength:
            items = d.strengthItems.isEmpty ? [EditableExercise()] : d.strengthItems
            
        case .cardio:
            cardio = d.cardio ?? CardioForm()
            
        case .sport:
            var s = d.sport ?? SportForm()
            if let vb = s.volleyball {
                s.vbPoints = vb.points
                s.vbAces   = vb.aces
                s.vbBlocks = vb.blocks
                s.vbDigs   = vb.digs
            }
            if let bb = s.basketball {
                s.bbPoints    = bb.points
                s.bbRebounds  = bb.rebounds
                s.bbAssists   = bb.assists
                s.bbSteals    = bb.steals
                s.bbBlocks    = bb.blocks
                s.bbTurnovers = bb.turnovers
                s.bbFouls     = bb.fouls
            }
            if let fb = s.football {
                if let pos = FootballPosition(rawValue: fb.position) {
                    s.fbPosition = pos
                }
                s.fbAssists         = fb.assists
                s.fbShotsOnTarget   = fb.shotsOnTarget
                s.fbPassesCompleted = fb.passesCompleted
                s.fbTackles         = fb.tackles
                s.fbSaves           = fb.saves
                s.fbYellow          = fb.yellowCards
                s.fbRed             = fb.redCards
            }
            if let rk = s.racket {
                let modeNorm   = rk.mode.lowercased().replacingOccurrences(of: " ", with: "_")
                let formatNorm = rk.format.lowercased().replacingOccurrences(of: " ", with: "_")
                switch modeNorm {
                case "singles":       s.racketMode = .singles
                case "doubles":       s.racketMode = .doubles
                case "mixed_doubles": s.racketMode = .mixedDoubles
                default: break
                }
                switch formatNorm {
                case "best_of_3": s.racketFormat = .bestOfThree
                case "best_of_5": s.racketFormat = .bestOfFive
                default: break
                }
                s.rkAces             = rk.aces
                s.rkDoubleFaults     = rk.doubleFaults
                s.rkWinners          = rk.winners
                s.rkUnforcedErrors   = rk.unforcedErrors
                s.rkSetsWon          = rk.setsWon
                s.rkSetsLost         = rk.setsLost
                s.rkGamesWon         = rk.gamesWon
                s.rkGamesLost        = rk.gamesLost
                s.rkBreakPointsWon   = rk.breakPointsWon
                s.rkBreakPointsTotal = rk.breakPointsTotal
                s.rkNetPointsWon     = rk.netPointsWon
                s.rkNetPointsTotal   = rk.netPointsTotal
            }
            
            s.scoreFor     = (d.sport?.scoreFor.isEmpty == false)     ? (d.sport?.scoreFor ?? s.scoreFor)         : s.scoreFor
            s.scoreAgainst = (d.sport?.scoreAgainst.isEmpty == false) ? (d.sport?.scoreAgainst ?? s.scoreAgainst) : s.scoreAgainst
            
            if sportUsesNumericScore(s.sport) { s.matchScoreText = "" }
            sport = s
            print("[DUP][INIT][SPORT] type=\(s.sport.rawValue) scoreFor=\(s.scoreFor) scoreAgainst=\(s.scoreAgainst) matchScoreText=\(s.matchScoreText)")
            print("[DUP][INIT][RACKET] mode=\(s.racketMode.dbValue) format=\(s.racketFormat.dbValue)")
            print("[DUP][INIT][RACKET] aces=\(s.rkAces) dblFaults=\(s.rkDoubleFaults) winners=\(s.rkWinners) unforced=\(s.rkUnforcedErrors)")
            print("[DUP][INIT][RACKET] setsWon=\(s.rkSetsWon) setsLost=\(s.rkSetsLost) gamesWon=\(s.rkGamesWon) gamesLost=\(s.rkGamesLost)")
            print("[DUP][INIT][RACKET] bpWon=\(s.rkBreakPointsWon)/\(s.rkBreakPointsTotal) netWon=\(s.rkNetPointsWon)/\(s.rkNetPointsTotal)")
        }
        recomputeDurationLabel()
        syncDurationFromDates()
    }
    
    private func sportUsesNumericScore(_ s: SportType) -> Bool {
        switch s {
        case .football, .basketball, .handball, .hockey: return true
        default: return false
        }
    }
    private func sportUsesSetText(_ s: SportType) -> Bool {
        switch s {
        case .padel, .tennis, .badminton, .squash, .table_tennis, .volleyball: return true
        default: return false
        }
    }
}

enum WorkoutKind: String, CaseIterable, Identifiable {
    case strength, cardio, sport
    var id: String { rawValue }
}

struct EditableExercise: Identifiable {
    let id = UUID()
    var exerciseId: Int64? = nil
    var exerciseName: String = ""
    var orderIndex: Int = 1
    var notes: String = ""
    var sets: [EditableSet] = [EditableSet(setNumber: 1)]
    
    func cleanSets() -> [EditableSet] {
        sets.filter { $0.reps != nil || !$0.weightKg.isEmpty || !$0.rpe.isEmpty }
    }
    
    func toStrengthItem() -> RPCStrengthParams.StrengthItem? {
        guard let exerciseId else { return nil }
        let cleaned = cleanSets()
        guard !cleaned.isEmpty else { return nil }
        return .init(
            exercise_id: exerciseId,
            order_index: orderIndex,
            notes: notes.isEmpty ? nil : notes,
            sets: cleaned.map { $0.toStrengthSet() },
            custom_name: exerciseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : exerciseName
        )
    }
}

struct EditableSet: Identifiable {
    let id = UUID()
    var setNumber: Int
    var reps: Int? = nil
    var weightKg: String = ""
    var rpe: String = ""
    var restSec: Int? = nil
    var notes: String = ""
    
    func toStrengthSet() -> RPCStrengthParams.StrengthItem.StrengthSet {
        .init(
            set_number: setNumber,
            reps: reps,
            weight_kg: parseDouble(weightKg),
            rpe: parseDouble(rpe),
            rest_sec: restSec,
            notes: notes.isEmpty ? nil : notes
        )
    }
    
    private func parseDouble(_ s: String) -> Double? {
        let t = s.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : Double(t)
    }
}

struct CardioForm {
    var modality: String = "Run"
    var distanceKm: String = ""
    var durH: String = ""
    var durM: String = ""
    var durS: String = ""
    var avgHR: String = ""
    var maxHR: String = ""
    var paceH: String = ""
    var paceM: String = ""
    var paceS: String = ""
    var elevationGainM: String = ""
    var durationSec: String = ""
    var avgPaceSecPerKm: String = ""
}

struct SportForm {
    var sport: SportType = .padel
    var durationMin: String = ""
    var scoreFor: String = ""
    var scoreAgainst: String = ""
    var matchResult: MatchResult = .unfinished
    var matchScoreText: String = ""
    var location: String = ""
    var sessionNotes: String = ""
    var football: FootballStatsForm? = nil
    var basketball: BasketballStatsForm? = nil
    var racket: RacketStatsForm? = nil
    var volleyball: VolleyballStatsForm? = nil
    var fbPosition: FootballPosition = .forward
    var fbAssists: String = ""
    var fbShotsOnTarget: String = ""
    var fbPassesCompleted: String = ""
    var fbTackles: String = ""
    var fbSaves: String = ""
    var fbYellow: String = ""
    var fbRed: String = ""
    var bbPoints: String = ""
    var bbRebounds: String = ""
    var bbAssists: String = ""
    var bbSteals: String = ""
    var bbBlocks: String = ""
    var bbTurnovers: String = ""
    var bbFouls: String = ""
    var rkAces: String = ""
    var rkDoubleFaults: String = ""
    var rkWinners: String = ""
    var racketMode: RacketMode = .singles
    var racketFormat: RacketFormat = .bestOfThree
    var rkSetsWon: String = ""
    var rkSetsLost: String = ""
    var rkGamesWon: String = ""
    var rkGamesLost: String = ""
    var rkBreakPointsWon: String = ""
    var rkBreakPointsTotal: String = ""
    var rkNetPointsWon: String = ""
    var rkNetPointsTotal: String = ""
    var rkUnforcedErrors: String = ""
    var vbPoints: String = ""
    var vbAces: String = ""
    var vbBlocks: String = ""
    var vbDigs: String = ""
}

struct RPCStrengthParams: Encodable {
    let p_user_id: UUID
    let p_items: [StrengthItem]
    let p_title: String?
    let p_started_at: String?
    let p_ended_at: String?
    let p_notes: String?
    let p_perceived_intensity: String?
    let p_state: String
    
    
    struct StrengthItem: Encodable {
        let exercise_id: Int64
        let order_index: Int
        let notes: String?
        let sets: [StrengthSet]
        let custom_name: String?
        
        struct StrengthSet: Encodable {
            let set_number: Int
            let reps: Int?
            let weight_kg: Double?
            let rpe: Double?
            let rest_sec: Int?
            let notes: String?
        }
    }
}

struct FootballStatsForm: Codable {
    var position: String
    var minutesPlayed: String
    var goals: String
    var assists: String
    var shotsOnTarget: String
    var passesCompleted: String
    var passesAttempted: String
    var tackles: String
    var interceptions: String
    var saves: String
    var yellowCards: String
    var redCards: String
}

struct BasketballStatsForm: Codable {
    var points: String
    var rebounds: String
    var assists: String
    var steals: String
    var blocks: String
    var fgMade: String
    var fgAttempted: String
    var threeMade: String
    var threeAttempted: String
    var ftMade: String
    var ftAttempted: String
    var turnovers: String
    var fouls: String
}

struct RacketStatsForm: Codable {
    var mode: String
    var format: String
    var setsWon: String
    var setsLost: String
    var gamesWon: String
    var gamesLost: String
    var aces: String
    var doubleFaults: String
    var winners: String
    var unforcedErrors: String
    var breakPointsWon: String
    var breakPointsTotal: String
    var netPointsWon: String
    var netPointsTotal: String
}

struct VolleyballStatsForm: Codable {
    var points: String
    var aces: String
    var blocks: String
    var digs: String
}

struct RPCCardioParams: Encodable {
    let p_user_id: UUID
    let p_modality: String
    let p_title: String?
    let p_started_at: String?
    let p_ended_at: String?
    let p_notes: String?
    let p_distance_km: Double?
    let p_duration_sec: Int?
    let p_avg_hr: Int?
    let p_max_hr: Int?
    let p_avg_pace_sec_per_km: Int?
    let p_elevation_gain_m: Int?
    let p_perceived_intensity: String?
    let p_state: String
}

struct RPCCardioWrapper: Encodable {
    let p: RPCCardioParams
}

struct RPCSportParams: Encodable {
    let p_user_id: UUID
    let p_sport: String
    let p_title: String?
    let p_started_at: String
    let p_ended_at: String?
    let p_notes: String?
    let p_duration_min: Int?
    let p_duration_sec: Int?
    let p_score_for: Int?
    let p_score_against: Int?
    let p_match_result: String?
    let p_match_score_text: String?
    let p_location: String?
    let p_session_notes: String?
    let p_perceived_intensity: String?
    let p_state: String
}

struct RPCSportWrapper: Encodable {
    let p: RPCSportParams
}

struct RPCSportV2Wrapper: Encodable {
    let p: RPCSportParams
    let p_stats: AnyJSON
}

private func hmsToSeconds(_ h: String, _ m: String, _ s: String) -> Int? {
    let H = Int(h.trimmingCharacters(in: .whitespaces)) ?? 0
    let M = Int(m.trimmingCharacters(in: .whitespaces)) ?? 0
    let S = Int(s.trimmingCharacters(in: .whitespaces)) ?? 0
    guard (0...59).contains(M), (0...59).contains(S), H >= 0 else { return nil }
    let total = H*3600 + M*60 + S
    return total > 0 ? total : nil
}

private func msToSeconds(_ h: String, _ m: String, _ s: String) -> Int? {
    let H = Int(h.trimmingCharacters(in: .whitespaces)) ?? 0
    let M = Int(m.trimmingCharacters(in: .whitespaces)) ?? 0
    let S = Int(s.trimmingCharacters(in: .whitespaces)) ?? 0
    guard (0...59).contains(M), (0...59).contains(S), H >= 0 else { return nil }
    let total = H*3600 + M*60 + S
    return total > 0 ? total : nil
}

private struct ParticipantsPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var loading = false
    @State private var results: [LightweightProfile] = []
    @State private var followees: [LightweightProfile] = []
    let alreadySelected: Set<LightweightProfile>
    let onPick: ([LightweightProfile]) -> Void
    
    @State private var tempSelected: Set<LightweightProfile> = []
    
    var body: some View {
        NavigationStack {
            List {
                if results.isEmpty && !query.isEmpty && !loading {
                    Text("No users found")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(results, id: \.id) { p in
                        let isOn = Binding<Bool>(
                            get: { tempSelected.contains(p) || alreadySelected.contains(p) },
                            set: { newVal in
                                if newVal { tempSelected.insert(p) } else { tempSelected.remove(p) }
                            }
                        )
                        HStack(spacing: 10) {
                            AvatarView(urlString: p.avatar_url)
                                .frame(width: 36, height: 36)
                            
                            Text(p.username ?? "Unknown")
                                .lineLimit(1)
                                .truncationMode(.tail)
                            
                            Spacer()
                            Toggle("", isOn: isOn).labelsHidden()
                        }
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onPick(Array(tempSelected))
                        dismiss()
                    }
                    .disabled(tempSelected.isEmpty)
                }
            }
            .overlay {
                if loading {
                    ProgressView("Searching…")
                        .padding()
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .scrollContentBackground(.hidden)
            .listRowBackground(Color.clear)
            .task { await loadFolloweesAndPrime() }
            .onChange(of: query) { _, new in
                Task { await searchUsers(new) }
            }
        }
    }
    
    private func loadFolloweesAndPrime() async {
        await MainActor.run { loading = true }
        defer { Task { await MainActor.run { loading = false } } }
        do {
            let client = SupabaseManager.shared.client
            let session = try await client.auth.session
            let fRes = try await client
                .from("follows")
                .select("followee_id")
                .eq("follower_id", value: session.user.id)
                .execute()
            
            struct FRow: Decodable { let followee_id: UUID }
            let fRows = try JSONDecoder().decode([FRow].self, from: fRes.data)
            let ids = fRows
                .map { $0.followee_id }
                .filter { $0 != session.user.id }
            
            guard !ids.isEmpty else {
                await MainActor.run { self.followees = []; self.results = [] }
                return
            }
            
            let pRes = try await client
                .from("profiles")
                .select("user_id,username,avatar_url")
                .in("user_id", values: ids)
                .order("username", ascending: true)
                .limit(50)
                .execute()
            
            let rows = try JSONDecoder().decode([LightweightProfile].self, from: pRes.data)
            
            await MainActor.run {
                self.followees = rows
                if self.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    self.results = rows
                }
            }
        } catch {
            await MainActor.run {
                self.followees = []
                self.results = []
            }
        }
    }
    
    private func searchUsers(_ q: String) async {
        let trimmed = q.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            await MainActor.run { results = followees; loading = false }
            return
        }
        await MainActor.run { loading = true }
        defer { Task { await MainActor.run { loading = false } } }
        
        let filtered = followees.filter {
            ($0.username ?? "").localizedCaseInsensitiveContains(trimmed)
        }
        await MainActor.run { results = filtered }
    }
}
