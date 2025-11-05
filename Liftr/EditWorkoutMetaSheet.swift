import SwiftUI
import Supabase

private enum JV: Encodable {
    case s(String), i(Int)
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .s(let v): try c.encode(v)
        case .i(let n): try c.encode(n)
        }
    }
}

private struct JStats: Encodable {
    let values: [String: JV]
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicCodingKey.self)
        for (k, v) in values {
            try container.encode(v, forKey: DynamicCodingKey(stringValue: k)!)
        }
    }
}

private struct DynamicCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
    init(_ s: String) { self.stringValue = s }
}

private struct IntOrString: Decodable {
    let value: Int?
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let i = try? c.decode(Int.self) {
            value = i
        } else if let s = try? c.decode(String.self), let i = Int(s.trimmingCharacters(in: .whitespacesAndNewlines)) {
            value = i
        } else {
            value = nil
        }
    }
}

struct EditWorkoutMetaSheet: View {
    struct Initial {
        var title: String
        var notes: String
        var startedAt: Date
        var endedAt: Date?
        var perceived: String
    }
    
    let kind: String
    let workoutId: Int
    let initial: Initial
    let onSaved: () async -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    @State private var title: String
    @State private var notes: String
    @State private var startedAt: Date
    @State private var endedAtEnabled: Bool
    @State private var endedAt: Date
    @State private var perceived: WorkoutIntensity
    @State private var c_modality = ""
    @State private var c_distanceKm = ""
    @State private var c_durH = ""
    @State private var c_durM = ""
    @State private var c_durS = ""
    @State private var c_durationSec = ""
    @State private var c_avgHR = ""
    @State private var c_maxHR = ""
    @State private var c_avgPace = ""
    @State private var c_elevGain = ""
    @State private var c_notes = ""
    @State private var s_sport: SportType = .football
    @State private var s_durationMin = ""
    @State private var s_scoreFor = ""
    @State private var s_scoreAgainst = ""
    @State private var s_matchResult: MatchResult = .unfinished
    @State private var s_matchScoreText = ""
    @State private var s_location = ""
    @State private var s_sessionNotes = ""
    @State private var participants: [LightweightProfile] = []
    @State private var fbPosition: FootballPosition = .forward
    @State private var fbAssists = ""
    @State private var fbShotsOnTarget = ""
    @State private var fbPassesCompleted = ""
    @State private var fbTackles = ""
    @State private var fbSaves = ""
    @State private var fbYellow = ""
    @State private var fbRed = ""
    @State private var bbPoints = ""
    @State private var bbRebounds = ""
    @State private var bbAssists = ""
    @State private var bbSteals = ""
    @State private var bbBlocks = ""
    @State private var bbTurnovers = ""
    @State private var bbFouls = ""
    @State private var racketMode: RacketMode = .singles
    @State private var racketFormat: RacketFormat = .bestOfThree
    @State private var rkAces = ""
    @State private var rkDoubleFaults = ""
    @State private var rkWinners = ""
    @State private var rkUnforcedErrors = ""
    @State private var rkSetsWon = ""
    @State private var rkSetsLost = ""
    @State private var rkGamesWon = ""
    @State private var rkGamesLost = ""
    @State private var rkBreakPointsWon = ""
    @State private var rkBreakPointsTotal = ""
    @State private var rkNetPointsWon = ""
    @State private var rkNetPointsTotal = ""
    @State private var vbPoints = ""
    @State private var vbAces = ""
    @State private var vbBlocks = ""
    @State private var vbDigs = ""
    @State private var showParticipantsPicker = false
    @State private var initialParticipants = Set<UUID>()
    @State private var didEditCardioDuration = false
    @State private var didEditSportDuration  = false
    
    struct SEditableSet: Identifiable, Hashable {
        let id = UUID()
        var setId: Int?
        var setNumber: Int
        var reps: Int?
        var weightKg: String = ""
        var rpe: String = ""
        var restSec: Int?
    }
    
    struct SEditableExercise: Identifiable {
        let id = UUID()
        let workoutExerciseId: Int
        var exerciseId: Int
        var name: String
        var alias: String
        var notes: String
        var sets: [SEditableSet]
    }
    
    private struct SectionCard<Content: View>: View {
        @ViewBuilder var content: Content
        init(@ViewBuilder content: () -> Content) { self.content = content() }
        var body: some View {
            VStack(spacing: 12) { content }
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
                content.labelsHidden()
            } label: {
                if let title { Text(title) }
            }
            .padding(.vertical, 12)
        }
    }
    
    @State private var s_items: [SEditableExercise] = []
    @State private var showExercisePicker = false
    @State private var selectedExerciseForAdd: Exercise? = nil
    @State private var catalog: [Exercise] = []
    @State private var loadingCatalog = false
    @State private var loading = false
    @State private var exerciseIndexToRename: Int? = nil
    @State private var saving = false
    @State private var error: String?
    
    init(kind: String, workoutId: Int, initial: Initial, onSaved: @escaping () async -> Void) {
        self.kind = kind
        self.workoutId = workoutId
        self.initial = initial
        self.onSaved = onSaved
        _title = State(wrappedValue: initial.title)
        _notes = State(wrappedValue: initial.notes)
        _startedAt = State(wrappedValue: initial.startedAt)
        _endedAtEnabled = State(wrappedValue: initial.endedAt != nil)
        _endedAt = State(wrappedValue: initial.endedAt ?? initial.startedAt)
        _perceived = State(wrappedValue: WorkoutIntensity(rawValue: initial.perceived) ?? .moderate)
    }
    
    var body: some View {
        NavigationStack {
            GradientBackground {
                Form {
                    Section {
                        SectionCard {
                            FieldRowPlain("Title") {
                                TextField("Title", text: $title)
                                    .textFieldStyle(.plain)
                                    .layoutPriority(1)
                            }
                            
                            Divider().padding(.vertical, 6)
                            
                            FieldRowPlain("Notes") {
                                TextField("Notes", text: $notes, axis: .vertical)
                                    .textFieldStyle(.plain)
                                    .lineLimit(3, reservesSpace: true)
                                    .layoutPriority(1)
                            }
                            
                            Divider().padding(.vertical, 6)
                            
                            FieldRowPlain("Started") {
                                DatePicker("", selection: $startedAt, displayedComponents: [.date, .hourAndMinute])
                                    .onChange(of: startedAt) { _, _ in
                                        if endedAtEnabled, endedAt < startedAt { endedAt = startedAt }
                                        didEditCardioDuration = false
                                        didEditSportDuration  = false
                                        syncDurationFromDates()
                                    }
                            }
                            
                            Divider().padding(.vertical, 6)
                            
                            FieldRowPlain("Finished") {
                                Toggle("", isOn: $endedAtEnabled)
                                    .onChange(of: endedAtEnabled) { _, isOn in
                                        if isOn { endedAt = max(endedAt, startedAt) }
                                        didEditCardioDuration = false
                                        didEditSportDuration  = false
                                        syncDurationFromDates()
                                    }
                            }
                            
                            if endedAtEnabled {
                                Divider().padding(.vertical, 6)
                                FieldRowPlain("Ended") {
                                    DatePicker("", selection: $endedAt, in: startedAt..., displayedComponents: [.date, .hourAndMinute])
                                        .onChange(of: endedAt) { _, _ in
                                            didEditCardioDuration = false
                                            didEditSportDuration  = false
                                            syncDurationFromDates()
                                        }
                                }
                            }
                            
                            Divider().padding(.vertical, 6)
                            
                            FieldRowPlain("Intensity") {
                                Picker("", selection: $perceived) {
                                    ForEach(WorkoutIntensity.allCases) { Text($0.label).tag($0) }
                                }
                            }
                        }
                    } header: { Text("GENERAL") }
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
                                    HStack(spacing: 10) {
                                        AvatarView(urlString: p.avatar_url)
                                            .frame(width: 28, height: 28)
                                            .clipShape(RoundedRectangle(cornerRadius: 6))
                                        Text(p.username ?? "user")
                                            .font(.subheadline.weight(.semibold))
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
                        Text("PARTICIPANTS")
                    }
                    .listRowBackground(Color.clear)
                    
                    switch kind.lowercased() {
                    case "cardio":  cardioSection
                    case "sport":   sportSection
                    case "strength": strengthSection
                    default: EmptyView()
                    }
                    
                    if let error { Text(error).foregroundStyle(.red) }
                }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
                .listSectionSpacing(18)
                .listRowBackground(Color.clear)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button { Task { await saveAll() } } label: {
                            if saving { ProgressView() } else { Text("Save") }
                        }
                        .disabled(saving || loading)
                    }
                }
                .task { await loadSpecificIfNeeded() }
                .onAppear { syncDurationFromDates() }
                .sheet(isPresented: $showExercisePicker) {
                    NavigationStack {
                        ExercisePickerSheet(
                            all: catalog,
                            selected: Binding(
                                get: { selectedExerciseForAdd },
                                set: { picked in
                                    selectedExerciseForAdd = picked
                                    defer {
                                        showExercisePicker = false
                                        exerciseIndexToRename = nil
                                    }
                                    guard let ex = picked else { return }
                                    if let idx = exerciseIndexToRename {
                                        s_items[idx].exerciseId = Int(ex.id)
                                        s_items[idx].name = ex.name
                                    } else {
                                        Task { await insertExercise(ex) }
                                    }
                                }
                            )
                        )
                    }
                    .onAppear {
                        UITableView.appearance().backgroundColor = .clear
                    }
                    .onDisappear {
                        UITableView.appearance().backgroundColor = nil
                    }
                    .gradientBG()
                }
                .sheet(isPresented: $showParticipantsPicker) {
                    ParticipantsPickerSheet(
                        alreadySelected: Set(participants),
                        onPick: { picked in
                            let set = Set(participants).union(picked)
                            participants = Array(set)
                        }
                    )
                }
            }
        }
        .gradientBG()
    }
    
    private var cardioSection: some View {
        Section {
            SectionCard {
                TextField("Modality", text: $c_modality)
                
                HStack(spacing: 12) {
                    TextField("Distance (km)", text: $c_distanceKm)
                        .keyboardType(.decimalPad)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Duration").font(.caption).foregroundStyle(.secondary)
                        HStack(spacing: 6) {
                            TextField("h", text: $c_durH).keyboardType(.numberPad).frame(width: 36)
                                .onChange(of: c_durH) { _, _ in didEditCardioDuration = true }
                            Text(":")
                            TextField("m", text: $c_durM).keyboardType(.numberPad).frame(width: 36)
                                .onChange(of: c_durM) { _, _ in didEditCardioDuration = true }
                            Text(":")
                            TextField("s", text: $c_durS).keyboardType(.numberPad).frame(width: 36)
                                .onChange(of: c_durS) { _, _ in didEditCardioDuration = true }
                        }
                        .font(.subheadline)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                HStack {
                    TextField("Avg HR", text: $c_avgHR).keyboardType(.numberPad)
                    TextField("Max HR", text: $c_maxHR).keyboardType(.numberPad)
                }
                
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Avg pace (/km)").font(.caption).foregroundStyle(.secondary)
                        Text(autoPaceLabel())
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    TextField("Elevation gain (m)", text: $c_elevGain)
                        .keyboardType(.numberPad)
                }
                
                TextField("Cardio notes", text: $c_notes, axis: .vertical)
            }
        } header: { Text("CARDIO") }
            .listRowBackground(Color.clear)
    }
    
    private var sportSection: some View {
        Section {
            SectionCard {
                FieldRowPlain("Sport") {
                    Picker("", selection: $s_sport) {
                        ForEach(SportType.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.menu)
                }
                .onChange(of: s_sport) { _, new in
                    if sportUsesNumericScore(new) { s_matchScoreText = "" }
                    if sportUsesSetText(new) { s_scoreFor = ""; s_scoreAgainst = "" }
                }
                
                Divider().padding(.vertical, 6)
                
                FieldRowPlain("Duration (min)") {
                    TextField("0", text: $s_durationMin)
                        .keyboardType(.numberPad)
                        .onChange(of: s_durationMin) { _, _ in didEditSportDuration = true }
                }
                
                if sportUsesNumericScore(s_sport) {
                    Divider().padding(.vertical, 6)
                    FieldRowPlain("Score") {
                        HStack {
                            TextField("For",     text: $s_scoreFor).keyboardType(.numberPad)
                            TextField("Against", text: $s_scoreAgainst).keyboardType(.numberPad)
                        }
                    }
                }
                
                if sportUsesSetText(s_sport) {
                    Divider().padding(.vertical, 6)
                    FieldRowPlain("Sets / score") {
                        TextField("e.g. 6-4, 4-6, 7-5", text: $s_matchScoreText)
                    }
                }
                
                Divider().padding(.vertical, 6)
                
                FieldRowPlain("Match result") {
                    Picker("", selection: $s_matchResult) {
                        ForEach(MatchResult.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.menu)
                }
                
                Divider().padding(.vertical, 6)
                
                FieldRowPlain("Location") {
                    TextField("Optional", text: $s_location)
                }
                
                Divider().padding(.vertical, 6)
                
                FieldRowPlain("Session Notes") {
                    TextField("Optional", text: $s_sessionNotes, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(3, reservesSpace: true)
                        .layoutPriority(1)
                }
                
                Divider().padding(.vertical, 6)
                
                Text("\(s_sport == .volleyball ? "Volleyball stats" : "Stats")")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 2)
                
                sportSpecificFields_Edit()
            }
        } header: { Text("SPORT") }
            .listRowBackground(Color.clear)
    }
    
    private var strengthSection: some View {
        Section {
            SectionCard {
                if s_items.isEmpty && !loading {
                    Text("No exercises found").foregroundStyle(.secondary)
                } else {
                    ForEach(s_items.indices, id: \.self) { i in
                        if i != s_items.startIndex { Divider().padding(.vertical, 6) }
                        FieldRowPlain(nil) {
                            Button {
                                Task { await loadCatalogIfNeeded() }
                                exerciseIndexToRename = i
                                showExercisePicker = true
                            } label: {
                                HStack(spacing: 6) {
                                    Text(s_items[i].name)
                                        .font(.subheadline.weight(.semibold))
                                    Image(systemName: "chevron.down")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                        }
                        
                        Divider()
                        
                        FieldRowPlain("Alias") {
                            TextField("Exercise name (optional)", text: $s_items[i].alias)
                                .textFieldStyle(.plain)
                        }
                        
                        Divider()
                        
                        FieldRowPlain("Notes") {
                            TextField("Notes (exercise)", text: $s_items[i].notes)
                                .textFieldStyle(.plain)
                        }
                        
                        ForEach(s_items[i].sets.indices, id: \.self) { s in
                            Divider()
                            HStack(spacing: 6) {
                                Text("Set \(s_items[i].sets[s].setNumber)")
                                    .font(.subheadline)
                                    .frame(width: 46, alignment: .leading)
                                
                                Stepper("", value: $s_items[i].sets[s].setNumber, in: 1...99)
                                    .labelsHidden()
                                    .controlSize(.mini)
                                    .scaleEffect(0.74, anchor: .leading)
                                    .frame(width: 64)
                                
                                TextField("Reps", value: $s_items[i].sets[s].reps, format: .number)
                                    .keyboardType(.numberPad).frame(width: 44)
                                
                                TextField("Weight kg", text: $s_items[i].sets[s].weightKg)
                                    .keyboardType(.decimalPad).frame(width: 70)
                                
                                TextField("RPE", text: $s_items[i].sets[s].rpe)
                                    .keyboardType(.decimalPad).frame(width: 38)
                                
                                TextField("Rest s", value: $s_items[i].sets[s].restSec, format: .number)
                                    .keyboardType(.numberPad).frame(width: 54)
                                
                                if s_items[i].sets.count > 1 {
                                    Button(role: .destructive) {
                                        s_items[i].sets.remove(at: s)
                                    } label: { Image(systemName: "minus.circle.fill") }
                                        .buttonStyle(.borderless)
                                }
                            }
                        }
                        
                        Divider().padding(.vertical, 4)
                        HStack {
                            Button {
                                s_items[i].sets.append(
                                    SEditableSet(setId: nil, setNumber: 1, reps: nil, weightKg: "", rpe: "", restSec: nil)
                                )
                            } label: { Label("Add set", systemImage: "plus.circle") }
                                .buttonStyle(.borderless)
                            
                            Spacer()
                            
                            if s_items.count > 1 {
                                Button(role: .destructive) {
                                    Task {
                                        await deleteExercise(s_items[i].workoutExerciseId)
                                        s_items.remove(at: i)
                                    }
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
                    Divider().padding(.vertical, 6)
                    Button {
                        Task {
                            await loadCatalogIfNeeded()
                            showExercisePicker = true
                        }
                    } label: {
                        Label("Add exercise", systemImage: "plus")
                    }
                    .buttonStyle(.borderless)
                    .opacity(0.9)
                }
            }
        } header: {
            Text("STRENGTH").foregroundStyle(.secondary)
        }
        .listRowBackground(Color.clear)
    }
    
    private func loadSpecificIfNeeded() async {
        loading = true; defer { loading = false }
        do {
            let decoder = JSONDecoder.supabaseCustom()
            
            switch kind.lowercased() {
            case "cardio":
                let res = try await SupabaseManager.shared.client
                    .from("cardio_sessions")
                    .select("*")
                    .eq("workout_id", value: workoutId)
                    .single()
                    .execute()
                struct Row: Decodable {
                    let modality: String
                    let distance_km: Decimal?
                    let duration_sec: Int?
                    let avg_hr: Int?
                    let max_hr: Int?
                    let avg_pace_sec_per_km: Int?
                    let elevation_gain_m: Int?
                    let notes: String?
                }
                let r = try decoder.decode(Row.self, from: res.data)
                c_modality   = r.modality
                c_distanceKm = r.distance_km.map { "\($0)" } ?? ""
                c_durationSec = r.duration_sec.map { "\($0)" } ?? ""
                c_avgHR      = r.avg_hr.map { "\($0)" } ?? ""
                c_maxHR      = r.max_hr.map { "\($0)" } ?? ""
                c_avgPace    = r.avg_pace_sec_per_km.map { "\($0)" } ?? ""
                c_elevGain   = r.elevation_gain_m.map { "\($0)" } ?? ""
                c_notes      = r.notes ?? ""
                if let sec = r.duration_sec, sec > 0 {
                    let h = sec / 3600
                    let m = (sec % 3600) / 60
                    let s = sec % 60
                    c_durH = h == 0 ? "" : String(h)
                    c_durM = String(m)
                    c_durS = String(s)
                } else {
                    c_durH = ""; c_durM = ""; c_durS = ""
                }
                
            case "sport":
                let res = try await SupabaseManager.shared.client
                    .from("sport_sessions")
                    .select("id, sport, duration_sec, match_result, score_for, score_against, match_score_text, location, notes")
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
                s_sport = SportType(rawValue: r.sport) ?? .football
                s_durationMin = r.duration_sec.map { "\($0/60)" } ?? ""
                print("SPORT_SESSION_ROW:", String(data: res.data, encoding: .utf8) ?? "<non-utf8>")
                s_scoreFor = r.score_for.map(String.init) ?? ""
                s_scoreAgainst = r.score_against.map(String.init) ?? ""
                s_matchResult = MatchResult(rawValue: r.match_result ?? "") ?? .unfinished
                s_matchScoreText = r.match_score_text ?? ""
                s_location = r.location ?? ""
                s_sessionNotes = r.notes ?? ""

                let client = SupabaseManager.shared.client
                
                switch s_sport {
                case .football, .handball, .hockey, .rugby:
                    do {
                        let q = try await client
                            .from("football_session_stats")
                            .select("*")
                            .eq("session_id", value: r.id)
                            .single()
                            .execute()
                        struct FB: Decodable {
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
                        let s = try decoder.decode(FB.self, from: q.data)
                        
                        if let pos = s.position, let mapped = FootballPosition(rawValue: pos) {
                            fbPosition = mapped
                        }
                        fbAssists         = s.assists.map(String.init) ?? ""
                        fbShotsOnTarget   = s.shots_on_target.map(String.init) ?? ""
                        fbPassesCompleted = s.passes_completed.map(String.init) ?? ""
                        fbTackles         = s.tackles.map(String.init) ?? ""
                        fbSaves           = s.saves.map(String.init) ?? ""
                        fbYellow          = s.yellow_cards.map(String.init) ?? ""
                        fbRed             = s.red_cards.map(String.init) ?? ""
                    } catch {
                        fbAssists = ""; fbShotsOnTarget = ""; fbPassesCompleted = ""
                        fbTackles = ""; fbSaves = ""; fbYellow = ""; fbRed = ""
                    }
                    
                case .basketball:
                    do {
                        let q = try await client
                            .from("basketball_session_stats")
                            .select("*")
                            .eq("session_id", value: r.id)
                            .single()
                            .execute()
                        struct BB: Decodable {
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
                        let s = try decoder.decode(BB.self, from: q.data)
                        bbPoints    = s.points.map(String.init) ?? ""
                        bbRebounds  = s.rebounds.map(String.init) ?? ""
                        bbAssists   = s.assists.map(String.init) ?? ""
                        bbSteals    = s.steals.map(String.init) ?? ""
                        bbBlocks    = s.blocks.map(String.init) ?? ""
                        bbTurnovers = s.turnovers.map(String.init) ?? ""
                        bbFouls     = s.fouls.map(String.init) ?? ""
                    } catch {
                        bbPoints = ""; bbRebounds = ""; bbAssists = ""
                        bbSteals = ""; bbBlocks = ""; bbTurnovers = ""; bbFouls = ""
                    }
                    
                case .padel, .tennis, .badminton, .squash, .table_tennis:
                    do {
                        let q = try await client
                            .from("racket_session_stats")
                            .select("*")
                            .eq("session_id", value: r.id)
                            .single()
                            .execute()
                        struct RK: Decodable {
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
                        let s = try decoder.decode(RK.self, from: q.data)

                        switch (s.mode ?? "").lowercased().replacingOccurrences(of: " ", with: "_") {
                        case "singles":       racketMode = .singles
                        case "doubles":       racketMode = .doubles
                        case "mixed_doubles": racketMode = .mixedDoubles
                        default: break
                        }
                        switch (s.format ?? "").lowercased().replacingOccurrences(of: " ", with: "_") {
                        case "best_of_3": racketFormat = .bestOfThree
                        case "best_of_5": racketFormat = .bestOfFive
                        default: break
                        }

                        rkAces             = s.aces.map(String.init) ?? ""
                        rkDoubleFaults     = s.double_faults.map(String.init) ?? ""
                        rkWinners          = s.winners.map(String.init) ?? ""
                        rkUnforcedErrors   = s.unforced_errors.map(String.init) ?? ""
                        rkSetsWon          = s.sets_won.map(String.init) ?? ""
                        rkSetsLost         = s.sets_lost.map(String.init) ?? ""
                        rkGamesWon         = s.games_won.map(String.init) ?? ""
                        rkGamesLost        = s.games_lost.map(String.init) ?? ""
                        rkBreakPointsWon   = s.break_points_won.map(String.init) ?? ""
                        rkBreakPointsTotal = s.break_points_total.map(String.init) ?? ""
                        rkNetPointsWon     = s.net_points_won.map(String.init) ?? ""
                        rkNetPointsTotal   = s.net_points_total.map(String.init) ?? ""
                    } catch {
                        rkAces = ""; rkDoubleFaults = ""; rkWinners = ""; rkUnforcedErrors = ""
                        rkSetsWon = ""; rkSetsLost = ""; rkGamesWon = ""; rkGamesLost = ""
                        rkBreakPointsWon = ""; rkBreakPointsTotal = ""; rkNetPointsWon = ""; rkNetPointsTotal = ""
                    }
                    
                case .volleyball:
                    do {
                        let q = try await client
                            .from("volleyball_session_stats")
                            .select("session_id, points, aces, blocks, digs")
                            .eq("session_id", value: r.id)
                            .single()
                            .execute()
                        struct VB: Decodable {
                            let points: Int?
                            let aces: Int?
                            let blocks: Int?
                            let digs: Int?
                        }
                        let s = try decoder.decode(VB.self, from: q.data)
                        vbPoints = s.points.map(String.init) ?? ""
                        vbAces   = s.aces.map(String.init) ?? ""
                        vbBlocks = s.blocks.map(String.init) ?? ""
                        vbDigs   = s.digs.map(String.init) ?? ""
                    } catch {
                        vbPoints = ""; vbAces = ""; vbBlocks = ""; vbDigs = ""
                    }
                }
                
            case "strength":
                let exQ = try await SupabaseManager.shared.client
                    .from("workout_exercises")
                    .select("id, exercise_id, order_index, notes, custom_name, exercises(name)")
                    .eq("workout_id", value: workoutId)
                    .order("order_index", ascending: true)
                    .execute()
                
                struct ExWire: Decodable {
                    let id: Int
                    let exercise_id: Int
                    let order_index: Int
                    let notes: String?
                    let exercises: ExName?
                    let custom_name: String?
                    struct ExName: Decodable { let name: String? }
                }
                let exWire = try decoder.decode([ExWire].self, from: exQ.data)
                
                let exIds = exWire.map { $0.id }
                var setsByEx: [Int: [SEditableSet]] = [:]
                if !exIds.isEmpty {
                    let sRes = try await SupabaseManager.shared.client
                        .from("exercise_sets")
                        .select("id, workout_exercise_id, set_number, reps, weight_kg, rpe, rest_sec")
                        .in("workout_exercise_id", values: exIds)
                        .order("set_number", ascending: true)
                        .execute()
                    
                    struct SetWire: Decodable {
                        let id: Int
                        let workout_exercise_id: Int
                        let set_number: Int
                        let reps: Int?
                        let weight_kg: Decimal?
                        let rpe: Decimal?
                        let rest_sec: Int?
                    }
                    let sWire = try decoder.decode([SetWire].self, from: sRes.data)
                    for s in sWire {
                        let editable = SEditableSet(
                            setId: s.id,
                            setNumber: s.set_number,
                            reps: s.reps,
                            weightKg: s.weight_kg.map { String(NSDecimalNumber(decimal: $0).doubleValue) } ?? "",
                            rpe: s.rpe.map { String(NSDecimalNumber(decimal: $0).doubleValue) } ?? "",
                            restSec: s.rest_sec
                        )
                        setsByEx[s.workout_exercise_id, default: []].append(editable)
                    }
                }
                
                let mapped: [SEditableExercise] = exWire.map { ex in
                    SEditableExercise(
                        workoutExerciseId: ex.id,
                        exerciseId: ex.exercise_id,
                        name: ex.exercises?.name ?? "Exercise",
                        alias: ex.custom_name ?? "",
                        notes: ex.notes ?? "",
                        sets: setsByEx[ex.id, default: [SEditableSet(setId: nil, setNumber: 1, reps: nil, weightKg: "", rpe: "", restSec: nil)]]
                    )
                }
                await MainActor.run { s_items = mapped }
                
            default:
                break
            }
        } catch {
            self.error = error.localizedDescription
        }
        await loadParticipants()
    }
    
    private func saveAll() async {
        error = nil; saving = true; defer { saving = false }
        do {
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let decoder = JSONDecoder.supabaseCustom()
            
            struct CommonPayload: Encodable {
                let title: String?
                let notes: String?
                let started_at: String?
                let ended_at: String?
                let perceived_intensity: String?
            }
            let common = CommonPayload(
                title: title.trimmedOrNil,
                notes: notes.trimmedOrNil,
                started_at: iso.string(from: startedAt),
                ended_at: endedAtEnabled ? iso.string(from: endedAt) : nil,
                perceived_intensity: perceived.rawValue
            )
            if kind.lowercased() != "sport" {
                _ = try await SupabaseManager.shared.client
                    .from("workouts")
                    .update(common)
                    .eq("id", value: workoutId)
                    .execute()
            }
            
            switch kind.lowercased() {
            case "cardio":
                struct CardioPayload: Encodable {
                    let modality: String
                    let distance_km: Double?
                    let duration_sec: Int?
                    let avg_hr: Int?
                    let max_hr: Int?
                    let avg_pace_sec_per_km: Int?
                    let elevation_gain_m: Int?
                    let notes: String?
                }
                let payload = CardioPayload(
                    modality: c_modality,
                    distance_km: parseDouble(c_distanceKm),
                    duration_sec: hmsToSeconds(c_durH, c_durM, c_durS) ?? parseInt(c_durationSec),
                    avg_hr: parseInt(c_avgHR),
                    max_hr: parseInt(c_maxHR),
                    avg_pace_sec_per_km: autoPaceSec(distanceKmText: c_distanceKm, durH: c_durH, durM: c_durM, durS: c_durS) ?? parseInt(c_avgPace),
                    elevation_gain_m: parseInt(c_elevGain),
                    notes: c_notes.trimmedOrNil
                )
                _ = try await SupabaseManager.shared.client
                    .from("cardio_sessions")
                    .update(payload)
                    .eq("workout_id", value: workoutId)
                    .execute()
                
            case "sport":
                struct SportPayload: Encodable {
                    let p_title: String?
                    let p_notes: String?
                    let p_started_at: String?
                    let p_ended_at: String?
                    let p_perceived_intensity: String?
                    let p_sport: String
                    let p_duration_min: Int?
                    let p_score_for: Int?
                    let p_score_against: Int?
                    let p_match_result: String?
                    let p_match_score_text: String?
                    let p_location: String?
                    let p_session_notes: String?
                }
                
                let payload = SportPayload(
                    p_title: title.trimmedOrNil,
                    p_notes: notes.trimmedOrNil,
                    p_started_at: iso.string(from: startedAt),
                    p_ended_at: endedAtEnabled ? iso.string(from: endedAt) : nil,
                    p_perceived_intensity: perceived.rawValue,
                    p_sport: s_sport.rawValue,
                    p_duration_min: parseInt(s_durationMin),
                    p_score_for: parseInt(s_scoreFor),
                    p_score_against: parseInt(s_scoreAgainst),
                    p_match_result: s_matchResult.rawValue,
                    p_match_score_text: s_matchScoreText.trimmedOrNil,
                    p_location: s_location.trimmedOrNil,
                    p_session_notes: s_sessionNotes.trimmedOrNil
                )
                
                let stats = try buildSportStatsJSON_Edit()
                struct RPCSportV2UpdateWrapper: Encodable {
                    let p_workout_id: Int
                    let p: SportPayload
                    let p_stats: JStats
                }
                
                _ = try await SupabaseManager.shared.client
                    .rpc("update_sport_workout_v2",
                         params: RPCSportV2UpdateWrapper(
                            p_workout_id: workoutId,
                            p: payload,
                            p_stats: JStats(values: stats)
                         )
                    )
                    .execute()
                
            case "strength":
                for ex in s_items {
                    struct ExPayload: Encodable { let exercise_id: Int; let notes: String?; let custom_name: String? }
                    _ = try await SupabaseManager.shared.client
                        .from("workout_exercises")
                        .update(ExPayload(
                            exercise_id: ex.exerciseId,
                            notes: ex.notes.trimmedOrNil,
                            custom_name: ex.alias.trimmedOrNil
                        ))
                        .eq("id", value: ex.workoutExerciseId)
                        .execute()
                }
                
                let exIds = s_items.map { $0.workoutExerciseId }
                if !exIds.isEmpty {
                    _ = try await SupabaseManager.shared.client
                        .from("exercise_sets")
                        .delete()
                        .in("workout_exercise_id", values: exIds)
                        .execute()
                }
                
                struct InsertSet: Encodable {
                    let workout_exercise_id: Int
                    let set_number: Int
                    let reps: Int?
                    let weight_kg: Double?
                    let rpe: Double?
                    let rest_sec: Int?
                }
                let payload: [InsertSet] = s_items.flatMap { ex in
                    ex.sets
                        .filter { s in
                            s.reps != nil ||
                            !s.weightKg.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                            !s.rpe.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                            s.restSec != nil
                        }
                        .map { s in
                            InsertSet(
                                workout_exercise_id: ex.workoutExerciseId,
                                set_number: max(1, s.setNumber),
                                reps: s.reps,
                                weight_kg: s.weightKg.asDouble,
                                rpe: s.rpe.asDouble,
                                rest_sec: s.restSec
                            )
                        }
                }
                if !payload.isEmpty {
                    _ = try await SupabaseManager.shared.client
                        .from("exercise_sets")
                        .insert(payload)
                        .execute()
                }
                
            default: break
            }
            
            NotificationCenter.default.post(name: .workoutDidChange, object: workoutId)
            
            let freshRes = try await SupabaseManager.shared.client
                .from("workouts")
                .select("id, user_id, kind, title, started_at, ended_at")
                .eq("id", value: workoutId)
                .single()
                .execute()
            
            struct Fresh: Decodable {
                let id: Int
                let user_id: UUID
                let kind: String
                let title: String?
                let started_at: Date?
                let ended_at: Date?
            }
            let fresh = try decoder.decode(Fresh.self, from: freshRes.data)
            
            struct ScoreWire: Decodable { let workout_id: Int; let score: Decimal }
            let scoreRes = try await SupabaseManager.shared.client
                .from("workout_scores")
                .select("workout_id, score")
                .eq("workout_id", value: workoutId)
                .execute()
            let sRows = try decoder.decode([ScoreWire].self, from: scoreRes.data)
            let totalScore = sRows.reduce(0.0) { $0 + NSDecimalNumber(decimal: $1.score).doubleValue }
            let scorePayload: Any = sRows.isEmpty ? NSNull() : totalScore
            
            NotificationCenter.default.post(
                name: .workoutUpdated,
                object: workoutId,
                userInfo: [
                    "id": fresh.id,
                    "user_id": fresh.user_id,
                    "kind": fresh.kind,
                    "title": fresh.title as Any,
                    "started_at": fresh.started_at ?? NSNull(),
                    "ended_at":   fresh.ended_at   ?? NSNull(),
                    "score":      scorePayload
                ]
            )
            try await applyParticipantsChanges()
            await onSaved()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
    
    private func loadCatalogIfNeeded() async {
        guard catalog.isEmpty && !loadingCatalog else { return }
        loadingCatalog = true; defer { loadingCatalog = false }
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
    
    private func insertExercise(_ ex: Exercise) async {
        do {
            let nextOrder = (s_items.count) + 1
            
            let res = try await SupabaseManager.shared.client
                .from("workout_exercises")
                .insert([
                    "workout_id": workoutId,
                    "exercise_id": Int(ex.id),
                    "order_index": nextOrder,
                    "notes": nil,
                    "custom_name": nil
                ])
                .select("id")
                .single()
                .execute()
            
            struct InsertedId: Decodable { let id: Int }
            let inserted = try JSONDecoder().decode(InsertedId.self, from: res.data)
            
            await MainActor.run {
                s_items.append(
                    SEditableExercise(
                        workoutExerciseId: inserted.id,
                        exerciseId: Int(ex.id),
                        name: ex.name,
                        alias: "",
                        notes: "",
                        sets: [SEditableSet(setId: nil, setNumber: 1, reps: nil, weightKg: "", rpe: "", restSec: nil)]
                    )
                )
            }
        } catch {
            await MainActor.run { self.error = error.localizedDescription }
        }
    }
    
    private func deleteExercise(_ workoutExerciseId: Int) async {
        do {
            _ = try await SupabaseManager.shared.client
                .from("exercise_sets")
                .delete()
                .eq("workout_exercise_id", value: workoutExerciseId)
                .execute()
            
            _ = try await SupabaseManager.shared.client
                .from("workout_exercises")
                .delete()
                .eq("id", value: workoutExerciseId)
                .execute()
        } catch {
            await MainActor.run { self.error = error.localizedDescription }
        }
    }
    
    private func loadParticipants() async {
        do {
            let decoder = JSONDecoder.supabaseCustom()
            let res = try await SupabaseManager.shared.client
                .from("workout_participants")
                .select("user_id, profiles!workout_participants_user_id_fkey(username, avatar_url)")
                .eq("workout_id", value: workoutId)
                .execute()
            
            struct Wire: Decodable {
                let user_id: UUID
                let profiles: Profile?
                struct Profile: Decodable {
                    let username: String?
                    let avatar_url: String?
                }
            }
            let rows = try decoder.decode([Wire].self, from: res.data)
            let mapped = rows.map { LightweightProfile(user_id: $0.user_id, username: $0.profiles?.username, avatar_url: $0.profiles?.avatar_url) }
            
            await MainActor.run {
                participants = mapped
                initialParticipants = Set(mapped.map { $0.user_id })
            }
        } catch {
        }
    }
    
    private func applyParticipantsChanges() async throws {
        let client = SupabaseManager.shared.client
        let current = Set(participants.map { $0.user_id })
        let toAdd    = current.subtracting(initialParticipants)
        let toRemove = initialParticipants.subtracting(current)
        for uid in toAdd {
            let params = AddParticipantParams(p_workout_id: Int64(workoutId), p_user_id: uid)
            _ = try await client.rpc("add_workout_participant", params: params).execute()
        }
        
        for uid in toRemove {
            _ = try await client
                .from("workout_participants")
                .delete()
                .eq("workout_id", value: workoutId)
                .eq("user_id", value: uid)
                .execute()
        }
        initialParticipants = current
    }
    
    private func hmsToSeconds(_ h: String, _ m: String, _ s: String) -> Int? {
        let H = Int(h.trimmingCharacters(in: .whitespaces)) ?? 0
        let M = Int(m.trimmingCharacters(in: .whitespaces)) ?? 0
        let S = Int(s.trimmingCharacters(in: .whitespaces)) ?? 0
        guard (0...59).contains(M), (0...59).contains(S), H >= 0 else { return nil }
        let total = H*3600 + M*60 + S
        return total > 0 ? total : nil
    }
    
    private func autoPaceSec(distanceKmText: String, durH: String, durM: String, durS: String) -> Int? {
        guard let dist = parseDouble(distanceKmText), dist > 0,
              let dur = hmsToSeconds(durH, durM, durS) else { return nil }
        return Int((Double(dur) / dist).rounded())
    }
    
    private func autoPaceLabel() -> String {
        guard let p = autoPaceSec(distanceKmText: c_distanceKm, durH: c_durH, durM: c_durM, durS: c_durS)
        else { return "—" }
        let mm = p / 60
        let ss = p % 60
        return String(format: "%d:%02d /km", mm, ss)
    }
    
    private func syncDurationFromDates() {
        guard endedAtEnabled, endedAt >= startedAt else { return }
        let totalSec = Int(endedAt.timeIntervalSince(startedAt))
        guard totalSec > 0 else { return }
        
        switch kind.lowercased() {
        case "cardio":
            guard !didEditCardioDuration else { return }
            let h = totalSec / 3600
            let m = (totalSec % 3600) / 60
            let s = totalSec % 60
            c_durH = h == 0 ? "" : String(h)
            c_durM = String(m)
            c_durS = String(s)
            
        case "sport":
            guard !didEditSportDuration else { return }
            let minutes = max(1, totalSec / 60)
            s_durationMin = String(minutes)
            
        default:
            break
        }
    }
    
    private func sportUsesNumericScore(_ s: SportType) -> Bool {
        switch s {
        case .football, .basketball, .handball, .hockey, .rugby: return true
        default: return false
        }
    }
    private func sportUsesSetText(_ s: SportType) -> Bool {
        switch s {
        case .padel, .tennis, .badminton, .squash, .table_tennis: return true
        default: return false
        }
    }
    
    @ViewBuilder
    private func sportSpecificFields_Edit() -> some View {
        switch s_sport {
        case .football:
            FieldRowPlain("Position") {
                Picker("", selection: $fbPosition) {
                    ForEach(FootballPosition.allCases) { Text($0.label).tag($0) }
                }.pickerStyle(.menu)
            }
            Divider()
            FieldRowPlain {
                HStack {
                    TextField("Assists", text: $fbAssists).keyboardType(.numberPad)
                    TextField("Shots on target", text: $fbShotsOnTarget).keyboardType(.numberPad)
                }
            }
            Divider()
            FieldRowPlain {
                HStack {
                    TextField("Passes completed", text: $fbPassesCompleted).keyboardType(.numberPad)
                    TextField("Tackles", text: $fbTackles).keyboardType(.numberPad)
                }
            }
            Divider()
            FieldRowPlain {
                HStack {
                    TextField("Saves (GK)", text: $fbSaves).keyboardType(.numberPad)
                    TextField("Yellow", text: $fbYellow).keyboardType(.numberPad)
                    TextField("Red", text: $fbRed).keyboardType(.numberPad)
                }
            }
            
        case .basketball:
            Divider()
            FieldRowPlain {
                HStack {
                    TextField("Points", text: $bbPoints).keyboardType(.numberPad)
                    TextField("Rebounds", text: $bbRebounds).keyboardType(.numberPad)
                    TextField("Assists", text: $bbAssists).keyboardType(.numberPad)
                }
            }
            Divider()
            FieldRowPlain {
                HStack {
                    TextField("Steals", text: $bbSteals).keyboardType(.numberPad)
                    TextField("Blocks", text: $bbBlocks).keyboardType(.numberPad)
                    TextField("Turnovers", text: $bbTurnovers).keyboardType(.numberPad)
                }
            }
            Divider()
            FieldRowPlain {
                TextField("Fouls", text: $bbFouls).keyboardType(.numberPad)
            }
            
        case .padel, .tennis, .badminton, .squash, .table_tennis:
            Divider()
            FieldRowPlain("Mode") {
                Picker("", selection: $racketMode) {
                    ForEach(RacketMode.allCases) { Text($0.label).tag($0) }
                }.pickerStyle(.menu)
            }
            Divider()
            FieldRowPlain("Format") {
                Picker("", selection: $racketFormat) {
                    ForEach(RacketFormat.allCases) { Text($0.label).tag($0) }
                }.pickerStyle(.segmented)
            }
            Divider()
            FieldRowPlain {
                HStack {
                    TextField("Aces", text: $rkAces).keyboardType(.numberPad)
                    TextField("Double faults", text: $rkDoubleFaults).keyboardType(.numberPad)
                    TextField("Winners", text: $rkWinners).keyboardType(.numberPad)
                }
            }
            Divider()
            FieldRowPlain {
                TextField("Unforced errors", text: $rkUnforcedErrors).keyboardType(.numberPad)
            }
            Divider()
            FieldRowPlain {
                HStack {
                    TextField("Sets won", text: $rkSetsWon).keyboardType(.numberPad)
                    TextField("Sets lost", text: $rkSetsLost).keyboardType(.numberPad)
                }
            }
            
            Divider()
            FieldRowPlain {
                HStack {
                    TextField("Games won", text: $rkGamesWon).keyboardType(.numberPad)
                    TextField("Games lost", text: $rkGamesLost).keyboardType(.numberPad)
                }
            }
            
            Divider()
            FieldRowPlain {
                HStack {
                    TextField("Break pts won", text: $rkBreakPointsWon).keyboardType(.numberPad)
                    TextField("Break pts total", text: $rkBreakPointsTotal).keyboardType(.numberPad)
                }
            }
            
            Divider()
            FieldRowPlain {
                HStack {
                    TextField("Net pts won", text: $rkNetPointsWon).keyboardType(.numberPad)
                    TextField("Net pts total", text: $rkNetPointsTotal).keyboardType(.numberPad)
                }
            }
            
        case .volleyball:
            Divider()
            FieldRowPlain {
                HStack {
                    TextField("Points", text: $vbPoints)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.plain)
                    TextField("Aces", text: $vbAces)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.plain)
                }
            }
            Divider()
            FieldRowPlain {
                HStack {
                    TextField("Blocks", text: $vbBlocks)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.plain)
                    TextField("Digs", text: $vbDigs)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.plain)
                }
            }
            
        case .handball, .hockey, .rugby:
            Divider()
            FieldRowPlain {
                Text("Usa 'Score for/against' y notes si necesitas más detalles.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
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
    
    private func buildSportStatsJSON_Edit() throws -> [String: JV] {
        switch s_sport {
        case .football:
            var out: [String: JV] = [:]
            out["position"] = .s(fbPosition.dbValue)
            if let v = parseInt(fbAssists)         { out["assists"]          = .i(v) }
            if let v = parseInt(fbShotsOnTarget)   { out["shots_on_target"]  = .i(v) }
            if let v = parseInt(fbPassesCompleted) { out["passes_completed"] = .i(v) }
            if let v = parseInt(fbTackles)         { out["tackles"]          = .i(v) }
            if let v = parseInt(fbSaves)           { out["saves"]            = .i(v) }
            if let v = parseInt(fbYellow)          { out["yellow_cards"]     = .i(v) }
            if let v = parseInt(fbRed)             { out["red_cards"]        = .i(v) }
            return out
            
        case .basketball:
            var out: [String: JV] = [:]
            if let v = parseInt(bbPoints)    { out["points"]    = .i(v) }
            if let v = parseInt(bbRebounds)  { out["rebounds"]  = .i(v) }
            if let v = parseInt(bbAssists)   { out["assists"]   = .i(v) }
            if let v = parseInt(bbSteals)    { out["steals"]    = .i(v) }
            if let v = parseInt(bbBlocks)    { out["blocks"]    = .i(v) }
            if let v = parseInt(bbTurnovers) { out["turnovers"] = .i(v) }
            if let v = parseInt(bbFouls)     { out["fouls"]     = .i(v) }
            return out
            
        case .padel, .tennis, .badminton, .squash, .table_tennis:
            var out: [String: JV] = [:]
            out["racket_mode"]   = {
                switch racketMode {
                case .singles:       .s("singles")
                case .doubles:       .s("doubles")
                case .mixedDoubles:  .s("mixed_doubles")
                }
            }()
            out["racket_format"] = (racketFormat == .bestOfThree) ? .s("best_of_3") : .s("best_of_5")
            if let v = parseInt(rkAces)           { out["aces"]            = .i(v) }
            if let v = parseInt(rkDoubleFaults)   { out["double_faults"]   = .i(v) }
            if let v = parseInt(rkWinners)        { out["winners"]         = .i(v) }
            if let v = parseInt(rkUnforcedErrors) { out["unforced_errors"] = .i(v) }
            if let v = parseInt(rkSetsWon)          { out["sets_won"]          = .i(v) }
            if let v = parseInt(rkSetsLost)         { out["sets_lost"]         = .i(v) }
            if let v = parseInt(rkGamesWon)         { out["games_won"]         = .i(v) }
            if let v = parseInt(rkGamesLost)        { out["games_lost"]        = .i(v) }
            if let v = parseInt(rkBreakPointsWon)   { out["break_points_won"]  = .i(v) }
            if let v = parseInt(rkBreakPointsTotal) { out["break_points_total"] = .i(v) }
            if let v = parseInt(rkNetPointsWon)     { out["net_points_won"]    = .i(v) }
            if let v = parseInt(rkNetPointsTotal)   { out["net_points_total"]  = .i(v) }
            return out
            
        case .volleyball:
            var out: [String: JV] = [:]
            if let v = parseInt(vbPoints) { out["points"] = .i(v) }
            if let v = parseInt(vbAces)   { out["aces"]   = .i(v) }
            if let v = parseInt(vbBlocks) { out["blocks"] = .i(v) }
            if let v = parseInt(vbDigs)   { out["digs"]   = .i(v) }
            return out
            
        case .handball, .hockey, .rugby:
            return [:]
        }
    }
}

extension String {
    var trimmedOrNil: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
    var asDouble: Double? {
        let t = replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : Double(t)
    }
}

extension Notification.Name {
    static let workoutUpdated = Notification.Name("workoutUpdated")
}

private struct ParticipantsPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var loading = false
    @State private var results: [LightweightProfile] = []
    let alreadySelected: Set<LightweightProfile>
    let onPick: ([LightweightProfile]) -> Void
    @State private var tempSelected: Set<LightweightProfile> = []
    @State private var followees: [LightweightProfile] = []
    
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
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            Text(p.username ?? "user")
                                .font(.body)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Spacer()
                            Toggle("", isOn: isOn).labelsHidden()
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 12)
                        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
                        .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                        .listRowBackground(Color.clear)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .listStyle(.plain)
            .listRowSeparator(.hidden)
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
            .task { await loadFollowees() }
            .gradientBG()
            .overlay {
                if loading {
                    ProgressView("Searching…")
                        .padding()
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .onAppear { UITableView.appearance().backgroundColor = .clear }
            .onDisappear { UITableView.appearance().backgroundColor = nil }
            .onChange(of: query) { _, new in
                Task { await searchUsers(new) }
            }
        }
    }
    
    private func searchUsers(_ q: String) async {
        let trimmed = q.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            await MainActor.run { results = followees; loading = false }
            return
        }
        
        await MainActor.run { loading = true }
        defer { Task { await MainActor.run { loading = false } } }
        
        do {
            let client = SupabaseManager.shared.client
            let res = try await client
                .from("profiles")
                .select("user_id,username,avatar_url")
                .ilike("username", pattern: "%\(trimmed)%")
                .limit(25)
                .execute()
            let me: UUID? = try? await SupabaseManager.shared.client.auth.session.user.id
            
            let rows = try JSONDecoder().decode([LightweightProfile].self, from: res.data)
            let filtered = rows.filter { prof in
                guard let me else { return true }
                return prof.user_id != me
            }
            let unique = Dictionary(grouping: filtered, by: { $0.user_id }).compactMap { $0.value.first }
            await MainActor.run { results = unique }
        } catch {
        }
    }
    
    private func loadFollowees() async {
        do {
            let client = SupabaseManager.shared.client
            guard let me: UUID = try? await client.auth.session.user.id else { return }
            
            let res = try await client
                .from("follows")
                .select("followee_id, profiles!follows_followee_id_fkey(user_id,username,avatar_url)")
                .eq("follower_id", value: me)
                .limit(200)
                .execute()
            
            struct Row: Decodable {
                let followee_id: UUID
                let profiles: LightweightProfile?
            }
            
            let rows = try JSONDecoder().decode([Row].self, from: res.data)
            let profs = rows
                .compactMap { $0.profiles }
                .filter { $0.user_id != me }
            
            let unique = Dictionary(grouping: profs, by: { $0.user_id }).compactMap { $0.value.first }
            
            await MainActor.run {
                self.followees = unique
                if self.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    self.results = unique
                }
            }
        } catch {
        }
    }
}
