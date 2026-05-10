import SwiftUI
import Supabase
import UIKit

enum WorkoutIntensity: String, CaseIterable, Identifiable {
    case easy, moderate, hard, max
    var id: String { rawValue }
    var label: String {
        switch self {
        case .easy:     return "Easy"
        case .moderate: return "Moderate"
        case .hard:     return "Hard"
        case .max:      return "Max"
        }
    }
}

enum SportType: String, CaseIterable, Identifiable {
    case padel, tennis, football, basketball, badminton, squash, table_tennis, volleyball, handball, hockey, rugby, hyrox, ski
    var id: String { rawValue }
    var label: String {
        switch self {
        case .padel:         return "Padel"
        case .tennis:        return "Tennis"
        case .football:      return "Football"
        case .basketball:    return "Basketball"
        case .badminton:     return "Badminton"
        case .squash:        return "Squash"
        case .table_tennis:  return "Table Tennis"
        case .volleyball:    return "Volleyball"
        case .handball:      return "Handball"
        case .hockey:        return "Hockey"
        case .rugby:         return "Rugby"
        case .hyrox:         return "Hyrox"
        case .ski:          return "Ski"
        }
    }
}

enum MatchResult: String, CaseIterable, Identifiable {
    case win, loss, draw, unfinished, forfeit
    var id: String { rawValue }
    var label: String {
        switch self {
        case .win:        return "Win"
        case .loss:       return "Loss"
        case .draw:       return "Draw"
        case .unfinished: return "Unfinished"
        case .forfeit:    return "Forfeit"
        }
    }
}

enum PublishMode: String, CaseIterable, Identifiable {
    case add, plan
    var id: String { rawValue }
    var label: String { self == .add ? "Add" : "Plan" }
    var stateParam: String { self == .add ? "published" : "planned" }
}

enum PlannedGroupStrengthProgramming: String, CaseIterable, Identifiable, Hashable {
    case sharedSessionTemplate
    case individualPlans

    var id: String { rawValue }

    var segmentedLabel: String {
        switch self {
        case .sharedSessionTemplate: return "Same workout"
        case .individualPlans: return "Per person"
        }
    }

    var detail: String {
        switch self {
        case .sharedSessionTemplate:
            return "One strength workout for the group — same exercises and sets — whether you save as Plan or Add."
        case .individualPlans:
            return "Each person gets their own strength workout (exercises, weights, reps). Use the person switch above the editor. Works for Plan or Add."
        }
    }
}

enum RacketMode: String, CaseIterable, Identifiable {
    case singles, doubles, mixedDoubles
    var id: String { rawValue }
    var label: String {
        switch self {
        case .singles:       return "Singles"
        case .doubles:       return "Doubles"
        case .mixedDoubles:  return "Mixed doubles"
        }
    }
    var dbValue: String {
        switch self {
        case .singles:       return "singles"
        case .doubles:       return "doubles"
        case .mixedDoubles:  return "mixed_doubles"
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
        case .goalkeeper: return "goalkeeper"
        case .defender:   return "defender"
        case .midfielder: return "midfielder"
        case .forward:    return "forward"
        }
    }
}

struct LightweightProfile: Identifiable, Decodable, Hashable {
    let user_id: UUID
    let username: String?
    let avatar_url: String?
    var id: UUID { user_id }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.user_id == rhs.user_id }
    func hash(into hasher: inout Hasher) { hasher.combine(user_id) }
}
struct AddParticipantParams: Encodable {
    let p_workout_id: Int64
    let p_user_id: UUID
}

struct ExerciseUsage: Decodable {
    let id: Int64
    let name: String
    let times_used: Int
    let last_used_at: Date?
}

struct SectionCard<Content: View>: View {
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

struct AddWorkoutDraft {
    var kind: WorkoutKind
    var title: String = ""
    var note: String = ""
    var participants: [LightweightProfile] = []
    var startedAt: Date = .now
    var endedAt: Date? = nil
    var perceived: WorkoutIntensity = .moderate
    var strengthItems: [EditableExercise] = []
    var plannedStrengthPerPerson: Bool = false
    var strengthLaneItems: [[EditableExercise]]? = nil
    var cardio: CardioForm? = nil
    var sport: SportForm? = nil
}

struct AddWorkoutSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var app: AppState
    @AppStorage("exerciseLanguage") private var exerciseLanguageRaw: String = ExerciseLanguage.spanish.rawValue
    
    private var exerciseLanguage: ExerciseLanguage {
        ExerciseLanguage(rawValue: exerciseLanguageRaw) ?? .spanish
    }
    
    @State private var kind: WorkoutKind = .strength
    @State private var title: String = ""
    @State private var note: String = ""
    @State private var startedAt: Date = .now
    @State private var endedAtEnabled: Bool = false
    @State private var endedAt: Date = .now
    @State private var items: [EditableExercise] = [EditableExercise()]
    @State private var cardio = CardioForm()
    @State private var sport = SportForm()
    @State private var skipNextSportScoreReset = false
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
    @State private var confirmRemoveStrengthExercise: (lane: Int, index: Int)? = nil
    @State private var showClearAllStrengthExercisesConfirm = false
    @State private var showClearAllHyroxExercisesConfirm = false
    @State private var publishMode: PublishMode = .add
    @State private var groupProgrammingMode: PlannedGroupStrengthProgramming = .sharedSessionTemplate
    @State private var strengthLaneItems: [[EditableExercise]] = [[EditableExercise()]]
    @State private var strengthProgramPage: Int = 0
    @State private var strengthRecommendTargetLane: Int?
    @State private var durationLabelMin: Int? = nil
    @State private var didApplyDraft = false
    @State private var isApplyingDraft = false
    @State private var showHelp = false
    @State private var hyroxStatsExpanded = false
    @State private var showWorkoutRecommend = false
    @State private var recommendKind: WorkoutKind = .strength
    @State private var hyroxCustomDisplayNameSuggestionsFromDB: [String] = []
    @State private var didLoadHyroxCustomDisplayNameSuggestions = false
    @FocusState private var hyroxExerciseNameFocusedId: UUID?
    @State private var saveNewStrengthRoutine = false
    @State private var newStrengthRoutineName = ""
    @State private var newStrengthRoutineFolderId: Int64? = nil
    @State private var strengthFoldersForPicker: [StrengthRoutineFolderRow] = []
    @State private var showStrengthRoutinesSheet = false
    @FocusState private var focusNewRoutineNameField: Bool
    @State private var showReplaceRoutineConfirm = false
    @State private var replaceRoutinePendingId: Int64?
    @State private var replacePendingIsRoutineOnly = false
    @State private var loadingRoutineOnly = false
    @State private var saveNewHyroxRoutine = false
    @State private var newHyroxRoutineName = ""
    @State private var newHyroxRoutineFolderId: Int64? = nil
    @State private var hyroxFoldersForPicker: [StrengthRoutineFolderRow] = []
    @State private var showHyroxRoutinesSheet = false
    @FocusState private var focusNewHyroxRoutineNameField: Bool
    @State private var showReplaceHyroxRoutineConfirm = false
    @State private var replaceHyroxRoutinePendingId: Int64?
    @State private var replaceHyroxPendingIsRoutineOnly = false
    @State private var loadingHyroxRoutineOnly = false
    @State private var strengthRoutineOverwritePrompt: StrengthRoutineOverwritePrompt?
    @State private var pendingStrengthRoutineOverwriteExercises: [EditableExercise] = []

    var body: some View { addWorkoutRoot }

    @ViewBuilder
    private var addWorkoutGeneralFormSection: some View {
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
                        onKindChangedFromTypePicker(new)
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
                            onStartedAtChangedForDurationSync()
                        }
                }
                Divider()
                FieldRowPlain("Finished") {
                    Toggle("", isOn: $endedAtEnabled)
                        .onChange(of: endedAtEnabled) { _, isOn in
                            onEndedAtEnabledChangedForDurationSync(isOn: isOn)
                        }
                }

                if endedAtEnabled {
                    Divider()
                    FieldRowPlain("Ended at") {
                        DatePicker("", selection: $endedAt, in: startedAt..., displayedComponents: [.date, .hourAndMinute])
                            .onChange(of: endedAt) { _, _ in
                                resetDurationEditFlagsAndSyncSchedule()
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
                FieldRowNotes(
                    "Notes",
                    text: $note,
                    placeholder: "Notes",
                    lineRange: 2...18
                )
                Divider()
                FieldRowPlain("Intensity") {
                    Picker("", selection: $perceived) {
                        ForEach(WorkoutIntensity.allCases) { Text($0.label).tag($0) }
                    }.pickerStyle(.menu)
                }
            }
        } header: {
            HStack {
                Text("GENERAL")
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    showHelp = true
                } label: {
                    Image(systemName: "info.circle")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
                .contentShape(Rectangle())
                .padding(.vertical, 2)
                .accessibilityLabel("How to start strength workout")
            }
        }
        .listRowBackground(Color.clear)
    }

    private var addWorkoutRoot: some View {
        NavigationStack {
            GradientBackground {
                Form {
                    addWorkoutGeneralFormSection

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

                            if kind == .strength, !participants.isEmpty {
                                Divider().padding(.vertical, 6)
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Group programming")
                                        .font(.subheadline.weight(.semibold))

                                    Text("Same strength session for everyone, or a separate workout per person (different lifts, weights, reps). Applies to Plan and Add.")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .padding(.top, 2)

                                    Picker("", selection: $groupProgrammingMode) {
                                        ForEach(PlannedGroupStrengthProgramming.allCases) { mode in
                                            Text(mode.segmentedLabel).tag(mode)
                                        }
                                    }
                                    .pickerStyle(.segmented)
                                    .padding(.vertical, 6)

                                    Text(groupProgrammingMode.detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .padding(.top, 2)
                                }
                                .padding(.top, 4)
                                .padding(.bottom, 2)
                            }
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
                .listSectionSpacing(8)
                .contentMargins(.bottom, 72, for: .scrollContent)
                .sheet(item: $pickerHandle) { handle in
                    strengthExercisePickerSheet(for: handle)
                }
                .sheet(isPresented: $showHelp) {
                    WorkoutHelpSheet()
                        .presentationDetents([.medium, .large])
                        .presentationBackground(.clear)
                }
                .navigationDestination(isPresented: $showWorkoutRecommend) {
                    WorkoutRecommendationFlowView(
                        workoutKind: recommendKind,
                        catalog: catalog,
                        exerciseLanguage: exerciseLanguage,
                        onApply: { payload in
                            switch payload {
                            case .strength(let rows): applyStrengthRecommendation(rows)
                            case .cardio(let r): applyCardioRecommendation(r)
                            case .sport(let r): applySportRecommendation(r)
                            }
                        }
                    )
                    .environmentObject(app)
                }
                .toolbar {
                    if kind == .strength {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                showStrengthRoutinesSheet = true
                            } label: {
                                Image(systemName: "rectangle.stack")
                            }
                            .accessibilityLabel("Routines")
                        }
                    } else if kind == .sport, sport.sport == .hyrox {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                showHyroxRoutinesSheet = true
                            } label: {
                                Image(systemName: "rectangle.stack")
                            }
                            .accessibilityLabel("Hyrox routines")
                        }
                    }
                }
            }
        }
        .task {
            if !didApplyDraft, let d = app.addDraft {
                isApplyingDraft = true
                await MainActor.run {
                    applyDraft(d)
                    didApplyDraft = true
                    isApplyingDraft = false
                }
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
        .sheet(isPresented: $showStrengthRoutinesSheet) {
            StrengthRoutinesPickerSheet(
                exerciseDisplayName: { exerciseId in
                    catalog.first(where: { $0.id == exerciseId })?.localizedName(for: exerciseLanguage) ?? ""
                },
                catalog: catalog,
                loadingCatalog: loadingCatalog,
                exerciseLanguage: exerciseLanguage,
                onApply: { loaded in
                    applyLoadedStrengthRoutine(loaded)
                }
            )
            .environmentObject(app)
            .gradientBG()
            .presentationDetents([.large])
            .presentationBackground(.clear)
        }
        .onChange(of: showStrengthRoutinesSheet) { _, isPresented in
            if !isPresented, kind == .strength {
                Task { await loadStrengthFoldersForPicker() }
            }
        }
        .sheet(isPresented: $showHyroxRoutinesSheet) {
            HyroxRoutinesPickerSheet(
                onApply: { payload in
                    sport.applyHyroxRoutineTemplate(payload)
                }
            )
            .environmentObject(app)
            .gradientBG()
            .presentationDetents([.large])
            .presentationBackground(.clear)
        }
        .onChange(of: showHyroxRoutinesSheet) { _, isPresented in
            if !isPresented, kind == .sport, sport.sport == .hyrox {
                Task { await loadHyroxFoldersForPicker() }
            }
        }
        .confirmationDialog(
            "Replace existing routine?",
            isPresented: $showReplaceRoutineConfirm,
            titleVisibility: .visible
        ) {
            Button("Replace") {
                let id = replaceRoutinePendingId
                let routineOnly = replacePendingIsRoutineOnly
                replaceRoutinePendingId = nil
                replacePendingIsRoutineOnly = false
                if routineOnly {
                    Task { await saveStrengthRoutineOnlyWithReplace(replacingRoutineId: id) }
                } else {
                    Task { await saveWithReplaceConfirm(replacingRoutineId: id) }
                }
            }
            Button("Cancel", role: .cancel) {
                replaceRoutinePendingId = nil
                replacePendingIsRoutineOnly = false
            }
        } message: {
            Text("A routine with this name already exists in this folder. Replacing removes the old template and saves the program you have in the editor now.")
        }
        .sheet(item: $strengthRoutineOverwritePrompt) { prompt in
            StrengthRoutineOverwriteConfirmSheet(
                prompt: prompt,
                onUpdate: {
                    let p = prompt
                    strengthRoutineOverwritePrompt = nil
                    Task { await saveAfterStrengthRoutineOverwriteDecision(prompt: p, updateRoutine: true) }
                },
                onNotNow: {
                    let p = prompt
                    strengthRoutineOverwritePrompt = nil
                    Task { await saveAfterStrengthRoutineOverwriteDecision(prompt: p, updateRoutine: false) }
                }
            )
            .presentationSizing(.fitted)
            .presentationDragIndicator(.visible)
            .presentationBackground(.clear)
            .frame(maxHeight: UIScreen.main.bounds.height * 0.92)
        }
        .confirmationDialog(
            "Replace existing Hyrox routine?",
            isPresented: $showReplaceHyroxRoutineConfirm,
            titleVisibility: .visible
        ) {
            Button("Replace") {
                let id = replaceHyroxRoutinePendingId
                let routineOnly = replaceHyroxPendingIsRoutineOnly
                replaceHyroxRoutinePendingId = nil
                replaceHyroxPendingIsRoutineOnly = false
                if routineOnly {
                    Task { await saveHyroxRoutineOnlyWithReplace(replacingRoutineId: id) }
                } else {
                    Task { await saveWithReplaceHyroxConfirm(replacingRoutineId: id) }
                }
            }
            Button("Cancel", role: .cancel) {
                replaceHyroxRoutinePendingId = nil
                replaceHyroxPendingIsRoutineOnly = false
            }
        } message: {
            Text("A routine with this name already exists in this folder. Replacing removes the old template and saves the Hyrox program you have in the editor now.")
        }
        .onChange(of: app.addDraftKey) { _, _ in
            if let d = app.addDraft {
                isApplyingDraft = true
                applyDraft(d)
                didApplyDraft = true
                isApplyingDraft = false
                pickerHandle = nil
            }
        }
        .onChange(of: participants.map(\.user_id)) { _, _ in
            if participants.isEmpty {
                groupProgrammingMode = .sharedSessionTemplate
            }
            syncStrengthLaneRowsWithParticipants()
        }
        .onChange(of: publishMode) { _, _ in
            if kind == .strength, groupProgrammingMode == .individualPlans {
                syncStrengthLaneRowsWithParticipants()
            }
        }
        .onChange(of: kind) { _, new in
            if new == .strength {
                Task { await loadStrengthFoldersForPicker() }
            }
            if new != .strength {
                groupProgrammingMode = .sharedSessionTemplate
                strengthLaneItems = [[EditableExercise()]]
                saveNewStrengthRoutine = false
                newStrengthRoutineName = ""
                newStrengthRoutineFolderId = nil
                focusNewRoutineNameField = false
            }
            if new != .sport {
                saveNewHyroxRoutine = false
                newHyroxRoutineName = ""
                newHyroxRoutineFolderId = nil
                focusNewHyroxRoutineNameField = false
            }
        }
        .onChange(of: sport.sport) { _, new in
            if new != .hyrox {
                saveNewHyroxRoutine = false
                newHyroxRoutineName = ""
                newHyroxRoutineFolderId = nil
                focusNewHyroxRoutineNameField = false
            }
        }
        .onChange(of: saveNewStrengthRoutine) { _, isOn in
            if isOn {
                Task { await loadStrengthFoldersForPicker() }
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 220_000_000)
                    focusNewRoutineNameField = true
                }
            } else {
                newStrengthRoutineName = ""
                newStrengthRoutineFolderId = nil
                focusNewRoutineNameField = false
            }
        }
        .onChange(of: saveNewHyroxRoutine) { _, isOn in
            if isOn {
                Task { await loadHyroxFoldersForPicker() }
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 220_000_000)
                    focusNewHyroxRoutineNameField = true
                }
            } else {
                newHyroxRoutineName = ""
                newHyroxRoutineFolderId = nil
                focusNewHyroxRoutineNameField = false
            }
        }
        .onChange(of: groupProgrammingMode) { _, new in
            if new == .individualPlans, kind == .strength, !participants.isEmpty {
                syncStrengthLaneRowsWithParticipants()
            } else if new == .sharedSessionTemplate {
                if let first = strengthLaneItems.first {
                    items = first
                }
            }
        }
        .banner($banner)
        .alert(
            "Are you sure you want to remove the exercise?",
            isPresented: removeStrengthExerciseAlertBinding
        ) {
            Button("Remove", role: .destructive) {
                if let req = confirmRemoveStrengthExercise {
                    if usePerPersonStrengthEditor,
                       req.lane >= 0, req.lane < strengthLaneItems.count,
                       strengthLaneItems[req.lane].indices.contains(req.index) {
                        strengthLaneItems[req.lane].remove(at: req.index)
                    } else if items.indices.contains(req.index) {
                        items.remove(at: req.index)
                    }
                }
                confirmRemoveStrengthExercise = nil
            }
            Button("Cancel", role: .cancel) {
                confirmRemoveStrengthExercise = nil
            }
        }
        .alert("Clear all exercises?", isPresented: $showClearAllStrengthExercisesConfirm) {
            Button("Clear all", role: .destructive) {
                if usePerPersonStrengthEditor,
                   strengthProgramPage >= 0, strengthProgramPage < strengthLaneItems.count {
                    strengthLaneItems[strengthProgramPage] = [EditableExercise()]
                } else {
                    items = [EditableExercise()]
                }
                confirmRemoveStrengthExercise = nil
                recentlyAddedExerciseId = nil
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes every exercise in this list and leaves one empty row.")
        }
    }

    private var removeStrengthExerciseAlertBinding: Binding<Bool> {
        Binding(
            get: { confirmRemoveStrengthExercise != nil },
            set: { newVal in
                if !newVal { confirmRemoveStrengthExercise = nil }
            }
        )
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
            .background((!loading && !loadingRoutineOnly && canSave) ? Color.blue : Color.gray.opacity(0.5),
                        in: RoundedRectangle(cornerRadius: 14))
            .foregroundStyle(.white)
        }
        .disabled(loading || loadingRoutineOnly || loadingHyroxRoutineOnly || !canSave)
    }

    private var saveRoutineOnlyButton: some View {
        Button {
            Task { await saveStrengthRoutineOnly() }
        } label: {
            HStack {
                if loadingRoutineOnly { ProgressView().tint(.white) }
                Text(loadingRoutineOnly ? "Saving…" : "Save without logging a workout")
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.9)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                (!loading && !loadingRoutineOnly && canSaveRoutineOnly)
                    ? Color.cyan
                    : Color.gray.opacity(0.5),
                in: RoundedRectangle(cornerRadius: 14)
            )
            .foregroundStyle(.white)
        }
        .disabled(loading || loadingRoutineOnly || !canSaveRoutineOnly)
    }

    private var saveHyroxRoutineOnlyButton: some View {
        Button {
            Task { await saveHyroxRoutineOnly() }
        } label: {
            HStack {
                if loadingHyroxRoutineOnly { ProgressView().tint(.white) }
                Text(loadingHyroxRoutineOnly ? "Saving…" : "Save without logging a workout")
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.9)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                (!loading && !loadingHyroxRoutineOnly && canSaveHyroxRoutineOnly)
                    ? Color.cyan
                    : Color.gray.opacity(0.5),
                in: RoundedRectangle(cornerRadius: 14)
            )
            .foregroundStyle(.white)
        }
        .disabled(loading || loadingHyroxRoutineOnly || !canSaveHyroxRoutineOnly)
    }

    private var usePerPersonStrengthEditor: Bool {
        kind == .strength && !participants.isEmpty && groupProgrammingMode == .individualPlans
    }

    private func strengthItemsBinding(lane: Int) -> Binding<[EditableExercise]> {
        Binding(
            get: {
                guard lane >= 0, lane < strengthLaneItems.count else { return [EditableExercise()] }
                return strengthLaneItems[lane]
            },
            set: { newVal in
                guard lane >= 0, lane < strengthLaneItems.count else { return }
                strengthLaneItems[lane] = newVal
            }
        )
    }

    private func strengthLaneHeaderTitle(lane: Int) -> String {
        guard lane >= 0, lane < strengthLaneItems.count else { return "Exercises" }
        if lane == 0 { return "Exercises — You" }
        let pi = lane - 1
        guard participants.indices.contains(pi) else { return "Exercises" }
        let p = participants[pi]
        let name = (p.username?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
        return "Exercises — \(name ?? p.user_id.uuidString)"
    }

    private func strengthLanePickerShortLabel(lane: Int) -> String {
        guard lane >= 0, lane < strengthLaneItems.count else { return "—" }
        if lane == 0 { return "You" }
        let pi = lane - 1
        guard participants.indices.contains(pi) else { return "—" }
        let p = participants[pi]
        let name = (p.username?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
        let base = name ?? String(p.user_id.uuidString.prefix(8))
        if base.count <= 14 { return base }
        return String(base.prefix(13)) + "…"
    }

    private func syncStrengthLaneRowsWithParticipants() {
        guard usePerPersonStrengthEditor else { return }
        let needed = 1 + participants.count
        let seedHost: [EditableExercise] = {
            if strengthLaneItems.count == 1,
               strengthLaneItems[0].count == 1,
               strengthLaneItems[0][0].exerciseId == nil {
                return items.map { $0.deepCopied() }
            }
            if let first = strengthLaneItems.first, first.contains(where: { exerciseSelected($0) }) {
                return first.map { $0.deepCopied() }
            }
            return items.map { $0.deepCopied() }
        }()
        if strengthLaneItems.count != needed {
            strengthLaneItems = (0..<needed).map { _ in seedHost.map { $0.deepCopied() } }
        }
        strengthProgramPage = min(max(0, strengthProgramPage), max(0, strengthLaneItems.count - 1))
    }

    @ViewBuilder
    private func strengthExercisePickerSheet(for handle: PickerHandle) -> some View {
        let lane = handle.strengthLaneIndex
        let source: [EditableExercise] = {
            if usePerPersonStrengthEditor, lane >= 0, lane < strengthLaneItems.count {
                return strengthLaneItems[lane]
            }
            return items
        }()
        if let idx = source.firstIndex(where: { $0.id == handle.id }) {
            ExercisePickerSheet(
                all: catalog,
                selected: Binding(
                    get: {
                        let row: [EditableExercise] = {
                            if usePerPersonStrengthEditor, lane >= 0, lane < strengthLaneItems.count {
                                return strengthLaneItems[lane]
                            }
                            return items
                        }()
                        guard idx < row.count else { return nil }
                        guard let exid = row[idx].exerciseId else { return nil }
                        return catalog.first(where: { $0.id == exid })
                    },
                    set: { picked in
                        if usePerPersonStrengthEditor, lane >= 0, lane < strengthLaneItems.count {
                            guard idx < strengthLaneItems[lane].count else { return }
                            strengthLaneItems[lane][idx].exerciseId = picked?.id
                            if let ex = picked {
                                strengthLaneItems[lane][idx].exerciseName = ex.localizedName(for: exerciseLanguageFromGlobalStorage())
                            } else {
                                strengthLaneItems[lane][idx].exerciseName = ""
                            }
                        } else {
                            guard idx < items.count else { return }
                            items[idx].exerciseId = picked?.id
                            if let ex = picked {
                                items[idx].exerciseName = ex.localizedName(for: exerciseLanguageFromGlobalStorage())
                            } else {
                                items[idx].exerciseName = ""
                            }
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

    private var strengthSection: some View {
        Section {
            if usePerPersonStrengthEditor {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Person")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Picker("Person", selection: $strengthProgramPage) {
                        ForEach(0..<strengthLaneItems.count, id: \.self) { lane in
                            Text(strengthLanePickerShortLabel(lane: lane)).tag(lane)
                        }
                    }
                    .pickerStyle(.segmented)

                    StrengthRoutineExercisesEditorBlock(
                        exercises: strengthItemsBinding(lane: strengthProgramPage),
                        laneIndex: strengthProgramPage,
                        headerTitle: strengthLaneHeaderTitle(lane: strengthProgramPage),
                        pickerHandle: $pickerHandle,
                        confirmRemoveStrengthExercise: $confirmRemoveStrengthExercise,
                        recentlyAddedExerciseId: $recentlyAddedExerciseId,
                        catalog: catalog,
                        loadingCatalog: loadingCatalog,
                        exerciseLabel: { exerciseLabel(for: $0) },
                        exerciseSelected: { exerciseSelected($0) },
                        onRequestClearAll: { showClearAllStrengthExercisesConfirm = true },
                        onSuggest: {
                            recommendKind = .strength
                            strengthRecommendTargetLane = strengthProgramPage
                            showWorkoutRecommend = true
                        },
                        showSuggestQuickAction: true
                    )
                }
            } else {
                StrengthRoutineExercisesEditorBlock(
                    exercises: $items,
                    laneIndex: 0,
                    headerTitle: nil,
                    pickerHandle: $pickerHandle,
                    confirmRemoveStrengthExercise: $confirmRemoveStrengthExercise,
                    recentlyAddedExerciseId: $recentlyAddedExerciseId,
                    catalog: catalog,
                    loadingCatalog: loadingCatalog,
                    exerciseLabel: { exerciseLabel(for: $0) },
                    exerciseSelected: { exerciseSelected($0) },
                    onRequestClearAll: { showClearAllStrengthExercisesConfirm = true },
                    onSuggest: {
                        recommendKind = .strength
                        strengthRecommendTargetLane = nil
                        showWorkoutRecommend = true
                    },
                    showSuggestQuickAction: true
                )
            }

            SectionCard {
                Text("ROUTINE TEMPLATE")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                FieldRowPlain("Create routine") {
                    Toggle("", isOn: $saveNewStrengthRoutine)
                        .labelsHidden()
                        .accessibilityLabel("Create routine")
                }
                if saveNewStrengthRoutine {
                    Group {
                        Divider()
                        FieldRowPlain("Routine name") {
                            TextField("Routine name", text: $newStrengthRoutineName)
                                .textFieldStyle(.plain)
                                .focused($focusNewRoutineNameField)
                        }
                        if !strengthFoldersForPicker.isEmpty {
                            Divider()
                            FieldRowPlain("Folder (optional)") {
                                Picker("Folder (optional)", selection: $newStrengthRoutineFolderId) {
                                    Text("None").tag(Int64?.none)
                                    ForEach(strengthFoldersForPicker) { f in
                                        Text(f.name).tag(Int64?.some(f.id))
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                            }
                        }
                        Divider()
                        saveRoutineOnlyButton
                    }
                }
                if usePerPersonStrengthEditor {
                    Divider()
                    Text("Routines use only the program for the person selected above (You / partner).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 4)
                }
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
                Button {
                    recommendKind = .cardio
                    showWorkoutRecommend = true
                } label: {
                    Label("Suggest next session", systemImage: "sparkles")
                }
                .buttonStyle(.borderless)
                
                Divider().padding(.vertical, 6)
                
                FieldRowPlain("Activity") {
                    Picker("", selection: $cardio.activity) {
                        ForEach(CardioActivityType.allCases) { a in
                            Text(a.label).tag(a)
                        }
                    }
                    .pickerStyle(.menu)
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

                    if cardio.activity.showsElevation {
                        TextField("Elevation gain (m)", text: $cardio.elevationGainM)
                            .keyboardType(.numberPad)
                    }
                }

                if cardio.activity.showsKmPaceSplits {
                    Divider()
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Per-km pace (optional)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("e.g. 5:30, 5:25, 5:20", text: $cardio.kmSplitsPaceText)
                            .font(.subheadline)
                    }
                }

                if cardio.activity.showsIncline {
                    Divider()
                    FieldRowPlain {
                        TextField("Incline (%)", text: $cardio.inclinePercent)
                            .keyboardType(.decimalPad)
                    }
                }

                if cardio.activity.showsCadenceRpm {
                    Divider()
                    FieldRowPlain {
                        HStack {
                            TextField("Cadence (rpm/spm)", text: $cardio.cadenceRpm).keyboardType(.numberPad)
                            if cardio.activity.showsWatts {
                                TextField("Avg watts", text: $cardio.wattsAvg).keyboardType(.numberPad)
                            }
                        }
                    }
                }

                if cardio.activity.showsSplit500m {
                    Divider()
                    FieldRowPlain {
                        TextField("Split (sec/500m)", text: $cardio.splitSecPer500m).keyboardType(.numberPad)
                    }
                }

                if cardio.activity.showsSwimFields {
                    Divider()
                    FieldRowPlain {
                        HStack {
                            TextField("Laps", text: $cardio.swimLaps).keyboardType(.numberPad)
                            TextField("Pool length (m)", text: $cardio.poolLengthM).keyboardType(.numberPad)
                        }
                    }
                    Divider()
                    FieldRowPlain {
                        TextField("Swim style", text: $cardio.swimStyle).textFieldStyle(.plain)
                    }
                }
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
                Button {
                    recommendKind = .sport
                    showWorkoutRecommend = true
                } label: {
                    Label("Suggest next session", systemImage: "sparkles")
                }
                .buttonStyle(.borderless)
                
                Divider().padding(.vertical, 6)
                
                FieldRowPlain {
                    Picker("", selection: $sport.sport) {
                        ForEach(SportType.allCases) { s in
                            Text(s.label).tag(s)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: sport.sport) { _, new in
                        if skipNextSportScoreReset {
                            skipNextSportScoreReset = false
                            return
                        }
                        if sportUsesNumericScore(new) {
                            sport.matchScoreText = ""
                        } else if sportUsesSetText(new) {
                            sport.scoreFor = ""; sport.scoreAgainst = ""
                        }

                        if new == .ski {
                            sport.matchResult = .unfinished
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
                
                if sport.sport != .ski {
                    Divider()

                    FieldRowPlain {
                        Picker("", selection: $sport.matchResult) {
                            ForEach(MatchResult.allCases) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.menu)
                    }
                }
                
                sportSpecificFields()
                
                Divider()
                
                FieldRowNotes(
                    "Session notes (optional)",
                    text: $sport.sessionNotes,
                    placeholder: "Add session notes…",
                    lineRange: 2...14
                )
            }

            if sport.sport == .hyrox {
                hyroxRoutineTemplateSectionCard
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
            let programs: [[EditableExercise]] = usePerPersonStrengthEditor ? strengthLaneItems : [items]
            for lane in programs {
                guard lane.contains(where: { exerciseSelected($0) }) else { return false }
                for ex in lane where exerciseSelected(ex) {
                    let hasValidSet = ex.cleanSets().contains { $0.reps != nil }
                    if !hasValidSet { return false }
                }
            }
            if saveNewStrengthRoutine {
                let t = newStrengthRoutineName.trimmingCharacters(in: .whitespacesAndNewlines)
                if t.isEmpty { return false }
            }
            return true
        case .cardio:
            return true
        case .sport:
            if sport.sport == .hyrox {
                if sport.hyExercises.isEmpty { return false }
                if saveNewHyroxRoutine {
                    let t = newHyroxRoutineName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if t.isEmpty { return false }
                }
                return true
            }
            return true
        }
    }

    private var canSaveHyroxRoutineOnly: Bool {
        guard kind == .sport, sport.sport == .hyrox, saveNewHyroxRoutine else { return false }
        guard !sport.hyExercises.isEmpty else { return false }
        let t = newHyroxRoutineName.trimmingCharacters(in: .whitespacesAndNewlines)
        return !t.isEmpty
    }

    private var canSaveRoutineOnly: Bool {
        guard kind == .strength, saveNewStrengthRoutine else { return false }
        let programs: [[EditableExercise]] = usePerPersonStrengthEditor ? strengthLaneItems : [items]
        for lane in programs {
            guard lane.contains(where: { exerciseSelected($0) }) else { return false }
            for ex in lane where exerciseSelected(ex) {
                let hasValidSet = ex.cleanSets().contains { $0.reps != nil }
                if !hasValidSet { return false }
            }
        }
        let t = newStrengthRoutineName.trimmingCharacters(in: .whitespacesAndNewlines)
        return !t.isEmpty
    }

    private func hyroxExercisePickerBinding(index: Int) -> Binding<String> {
        Binding(
            get: { HyroxExerciseFormatting.pickerTag(for: sport.hyExercises[index].exerciseCode) },
            set: { newTag in
                let prev = sport.hyExercises[index].exerciseCode
                if newTag != HyroxExerciseFormatting.customExerciseCode {
                    sport.hyExercises[index].exerciseCode = newTag
                    sport.hyExercises[index].customDisplayName = ""
                    return
                }
                if HyroxExerciseCode(rawValue: prev) != nil {
                    sport.hyExercises[index].exerciseCode = HyroxExerciseFormatting.customExerciseCode
                    sport.hyExercises[index].customDisplayName = ""
                } else if prev != HyroxExerciseFormatting.customExerciseCode {
                    sport.hyExercises[index].exerciseCode = HyroxExerciseFormatting.customExerciseCode
                    let existing = sport.hyExercises[index].customDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if existing.isEmpty {
                        sport.hyExercises[index].customDisplayName = HyroxExerciseFormatting.label(code: prev, displayName: nil)
                    }
                }
            }
        )
    }

    private func loadHyroxCustomDisplayNameSuggestionsFromServer() async {
        await MainActor.run {
            guard !didLoadHyroxCustomDisplayNameSuggestions else { return }
            didLoadHyroxCustomDisplayNameSuggestions = true
        }
        do {
            let res = try await SupabaseManager.shared.client
                .from("hyrox_session_exercises")
                .select("exercise_display_name")
                .eq("exercise_code", value: HyroxExerciseFormatting.customExerciseCode)
                .limit(800)
                .execute()
            struct Row: Decodable { let exercise_display_name: String? }
            let rows = try JSONDecoder().decode([Row].self, from: res.data)
            let raw = rows
                .compactMap { $0.exercise_display_name?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let deduped = Self.canonicalSortedHyroxDisplayNames(from: raw)
            await MainActor.run { hyroxCustomDisplayNameSuggestionsFromDB = deduped }
        } catch {
            await MainActor.run { didLoadHyroxCustomDisplayNameSuggestions = false }
        }
    }

    private static func normalizedHyroxDisplayNameKey(_ s: String) -> String {
        s.folding(options: .diacriticInsensitive, locale: .current).lowercased()
    }

    private static func canonicalSortedHyroxDisplayNames(from raw: [String]) -> [String] {
        var bestByNorm: [String: String] = [:]
        for r in raw {
            let t = r.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { continue }
            let k = normalizedHyroxDisplayNameKey(t)
            if let existing = bestByNorm[k] {
                if t.count > existing.count { bestByNorm[k] = t }
            } else {
                bestByNorm[k] = t
            }
        }
        return bestByNorm.values.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func hyroxFilteredExerciseNameSuggestions(exerciseIndex i: Int) -> [String] {
        guard sport.hyExercises.indices.contains(i) else { return [] }
        var raw: [String] = hyroxCustomDisplayNameSuggestionsFromDB
        for (idx, ex) in sport.hyExercises.enumerated() where idx != i {
            let t = ex.customDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty, HyroxExerciseCode(rawValue: ex.exerciseCode) == nil else { continue }
            raw.append(t)
        }
        let deduped = Self.canonicalSortedHyroxDisplayNames(from: raw)
        let q = sport.hyExercises[i].customDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty {
            return Array(deduped.prefix(8))
        }
        let qn = Self.normalizedHyroxDisplayNameKey(q)
        let filtered = deduped.filter {
            Self.normalizedHyroxDisplayNameKey($0).contains(qn) || $0.localizedStandardContains(q)
        }
        return Array(filtered.prefix(8))
    }

    @ViewBuilder
    private func hyroxExerciseNameSuggestionsList(exerciseIndex i: Int) -> some View {
        let rows = hyroxFilteredExerciseNameSuggestions(exerciseIndex: i)
        if rows.isEmpty {
            EmptyView()
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(rows, id: \.self) { name in
                        Button {
                            sport.hyExercises[i].customDisplayName = name
                            hyroxExerciseNameFocusedId = nil
                        } label: {
                            Text(name)
                                .font(.subheadline)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 8)
                                .padding(.horizontal, 10)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Divider()
                    }
                }
            }
            .frame(maxHeight: 160)
            .fixedSize(horizontal: false, vertical: true)
            .scrollClipDisabled()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(.secondary.opacity(0.22), lineWidth: 0.8)
            )
        }
    }

    @ViewBuilder
    private func hyroxExerciseNameFieldWithSuggestions(index i: Int) -> some View {
        let exId = sport.hyExercises[i].id
        VStack(alignment: .leading, spacing: 6) {
            TextField("Exercise name", text: $sport.hyExercises[i].customDisplayName)
                .textFieldStyle(.roundedBorder)
                .focused($hyroxExerciseNameFocusedId, equals: exId)
            if hyroxExerciseNameFocusedId == exId {
                hyroxExerciseNameSuggestionsList(exerciseIndex: i)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var hyroxOptionalStatsDisclosureBlock: some View {
        Group {
            Divider()
            DisclosureGroup(isExpanded: $hyroxStatsExpanded) {
                FieldRowPlain {
                    HStack {
                        TextField("Division (Open/Pro…)", text: $sport.hyDivision)
                            .textFieldStyle(.plain)
                        TextField("Category (Men/Women…)", text: $sport.hyCategory)
                            .textFieldStyle(.plain)
                    }
                }
                Divider()
                FieldRowPlain {
                    TextField("Age group (e.g. 30–34)", text: $sport.hyAgeGroup)
                        .textFieldStyle(.plain)
                }
                Divider()
                FieldRowPlain {
                    HStack {
                        TextField("Official time (sec)", text: $sport.hyOfficialTimeSec).keyboardType(.numberPad)
                        TextField("Penalty time (sec)", text: $sport.hyPenaltyTimeSec).keyboardType(.numberPad)
                    }
                }
                Divider()
                FieldRowPlain {
                    HStack {
                        TextField("No reps", text: $sport.hyNoReps).keyboardType(.numberPad)
                        TextField("Rank overall", text: $sport.hyRankOverall).keyboardType(.numberPad)
                        TextField("Rank category", text: $sport.hyRankCategory).keyboardType(.numberPad)
                    }
                }
                Divider()
                FieldRowPlain {
                    HStack {
                        TextField("Avg HR", text: $sport.hyAvgHR).keyboardType(.numberPad)
                        TextField("Max HR", text: $sport.hyMaxHR).keyboardType(.numberPad)
                    }
                }
            } label: {
                Text("Stats (optional)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Divider()
        }
    }

    private var hyroxExerciseProgramEditorStack: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Exercises")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("Use the arrows on each exercise to change order.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, sport.hyExercises.count > 1 ? 2 : 4)

            if sport.hyExercises.count > 1 {
                HStack {
                    Spacer(minLength: 0)
                    Button("Clear all", role: .destructive) {
                        showClearAllHyroxExercisesConfirm = true
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Clear all Hyrox stations")
                }
                .padding(.bottom, 2)
            }

            if sport.hyExercises.isEmpty {
                Text("No Hyrox exercises added")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            ForEach(sport.hyExercises.indices, id: \.self) { i in
                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Exercise \(i + 1)")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }

                    Picker("", selection: hyroxExercisePickerBinding(index: i)) {
                        ForEach(HyroxExerciseCode.allCases) { ex in
                            Text(ex.label).tag(ex.rawValue)
                        }
                        Text("Other").tag(HyroxExerciseFormatting.customExerciseCode)
                    }
                    .pickerStyle(.menu)

                    if HyroxExerciseCode(rawValue: sport.hyExercises[i].exerciseCode) == nil {
                        hyroxExerciseNameFieldWithSuggestions(index: i)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .top, spacing: 6) {
                            StrengthStyleMetricField(title: "Distance (m)") {
                                TextField("—", text: $sport.hyExercises[i].distanceM)
                                    .keyboardType(.numberPad)
                            }
                            StrengthStyleMetricField(title: "Reps") {
                                TextField("—", text: $sport.hyExercises[i].reps)
                                    .keyboardType(.numberPad)
                            }
                            StrengthStyleMetricField(title: "kg") {
                                TextField("—", text: $sport.hyExercises[i].weightKg)
                                    .keyboardType(.decimalPad)
                            }
                        }
                        HStack(alignment: .top, spacing: 6) {
                            StrengthStyleMetricField(title: "Duration (s)") {
                                TextField("—", text: $sport.hyExercises[i].durationSec)
                                    .keyboardType(.numberPad)
                            }
                            StrengthStyleMetricField(title: "Height (cm)") {
                                TextField("—", text: $sport.hyExercises[i].heightCm)
                                    .keyboardType(.numberPad)
                            }
                            StrengthStyleMetricField(title: "Implements") {
                                TextField("—", text: $sport.hyExercises[i].implementCount)
                                    .keyboardType(.numberPad)
                            }
                        }
                    }

                    FieldRowNotes(
                        "Notes",
                        text: $sport.hyExercises[i].notes,
                        placeholder: "Notes",
                        lineRange: 2...8
                    )
                    .padding(.top, 2)

                    HStack {
                        Spacer(minLength: 0)

                        if sport.hyExercises.count > 1 {
                            HStack(spacing: 2) {
                                Button {
                                    moveHyroxExercise(from: i, direction: -1)
                                } label: {
                                    Image(systemName: "chevron.up")
                                        .font(.subheadline.weight(.semibold))
                                        .frame(width: 36, height: 32)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .disabled(i == 0)
                                .opacity(i == 0 ? 0.35 : 1)

                                Button {
                                    moveHyroxExercise(from: i, direction: 1)
                                } label: {
                                    Image(systemName: "chevron.down")
                                        .font(.subheadline.weight(.semibold))
                                        .frame(width: 36, height: 32)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .disabled(i == sport.hyExercises.count - 1)
                                .opacity(i == sport.hyExercises.count - 1 ? 0.35 : 1)
                            }
                            .foregroundStyle(.secondary)
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("Reorder exercise")
                        }

                        if sport.hyExercises.count > 1 {
                            Button(role: .destructive) {
                                sport.hyExercises.remove(at: i)
                                for idx in sport.hyExercises.indices {
                                    sport.hyExercises[idx].exerciseOrder = idx + 1
                                }
                            } label: {
                                Image(systemName: "trash")
                                    .font(.body)
                                    .frame(width: 40, height: 36)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Remove exercise")
                        }
                    }
                }
            }

            Divider().padding(.vertical, 6)
            Button {
                sport.hyExercises.append(
                    HyroxExerciseForm(
                        exerciseCode: HyroxExerciseCode.run.rawValue,
                        exerciseOrder: sport.hyExercises.count + 1
                    )
                )
            } label: {
                Label("Add exercise", systemImage: "plus")
            }
            .buttonStyle(.borderless)
            .padding(.top, 2)
        }
        .task(id: "\(kind.rawValue)-\(sport.sport.rawValue)") {
            guard kind == .sport, sport.sport == .hyrox else { return }
            await loadHyroxCustomDisplayNameSuggestionsFromServer()
            await loadHyroxFoldersForPicker()
        }
        .alert("Clear all Hyrox stations?", isPresented: $showClearAllHyroxExercisesConfirm) {
            Button("Clear all", role: .destructive) {
                sport.hyExercises = []
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes every station from your Hyrox program.")
        }
    }

    private var hyroxRoutineTemplateSectionCard: some View {
        SectionCard {
            Text("ROUTINE TEMPLATE")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            FieldRowPlain("Create routine") {
                Toggle("", isOn: $saveNewHyroxRoutine)
                    .labelsHidden()
                    .accessibilityLabel("Create Hyrox routine")
            }
            if saveNewHyroxRoutine {
                Group {
                    Divider()
                    FieldRowPlain("Routine name") {
                        TextField("Routine name", text: $newHyroxRoutineName)
                            .textFieldStyle(.plain)
                            .focused($focusNewHyroxRoutineNameField)
                    }
                    if !hyroxFoldersForPicker.isEmpty {
                        Divider()
                        FieldRowPlain("Folder (optional)") {
                            Picker("Folder (optional)", selection: $newHyroxRoutineFolderId) {
                                Text("None").tag(Int64?.none)
                                ForEach(hyroxFoldersForPicker) { f in
                                    Text(f.name).tag(Int64?.some(f.id))
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }
                    }
                    Divider()
                    saveHyroxRoutineOnlyButton
                }
            }
        }
    }

    @ViewBuilder
    private var hyroxSportFieldsContent: some View {
        hyroxOptionalStatsDisclosureBlock
        hyroxExerciseProgramEditorStack
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

        case .handball:
            Divider()
            FieldRowPlain {
                TextField("Position (optional)", text: $sport.hbPosition)
                    .textFieldStyle(.plain)
            }
            Divider()
            FieldRowPlain {
                HStack {
                    TextField("Goals", text: $sport.hbGoals).keyboardType(.numberPad)
                    TextField("Shots", text: $sport.hbShots).keyboardType(.numberPad)
                    TextField("Shots on target", text: $sport.hbShotsOnTarget).keyboardType(.numberPad)
                }
            }
            Divider()
            FieldRowPlain {
                HStack {
                    TextField("Assists", text: $sport.hbAssists).keyboardType(.numberPad)
                    TextField("Steals", text: $sport.hbSteals).keyboardType(.numberPad)
                    TextField("Blocks", text: $sport.hbBlocks).keyboardType(.numberPad)
                }
            }
            Divider()
            FieldRowPlain {
                HStack {
                    TextField("Turnovers lost", text: $sport.hbTurnoversLost).keyboardType(.numberPad)
                    TextField("7m goals", text: $sport.hbSevenMGoals).keyboardType(.numberPad)
                    TextField("7m attempts", text: $sport.hbSevenMAttempts).keyboardType(.numberPad)
                }
            }
            Divider()
            FieldRowPlain {
                HStack {
                    TextField("Saves (GK)", text: $sport.hbSaves).keyboardType(.numberPad)
                    TextField("Yellow cards", text: $sport.hbYellow).keyboardType(.numberPad)
                    TextField("2-min susp.", text: $sport.hbTwoMin).keyboardType(.numberPad)
                    TextField("Red cards", text: $sport.hbRed).keyboardType(.numberPad)
                }
            }

        case .hockey:
            Divider()
            FieldRowPlain {
                TextField("Position (optional)", text: $sport.hkPosition)
                    .textFieldStyle(.plain)
            }
            Divider()
            FieldRowPlain {
                HStack {
                    TextField("Goals", text: $sport.hkGoals).keyboardType(.numberPad)
                    TextField("Assists", text: $sport.hkAssists).keyboardType(.numberPad)
                    TextField("Shots on goal", text: $sport.hkShotsOnGoal).keyboardType(.numberPad)
                }
            }
            Divider()
            FieldRowPlain {
                HStack {
                    TextField("+/-", text: $sport.hkPlusMinus).keyboardType(.numberPad)
                    TextField("Hits", text: $sport.hkHits).keyboardType(.numberPad)
                    TextField("Blocks", text: $sport.hkBlocks).keyboardType(.numberPad)
                }
            }
            Divider()
            FieldRowPlain {
                HStack {
                    TextField("Faceoffs won", text: $sport.hkFaceoffsWon).keyboardType(.numberPad)
                    TextField("Faceoffs total", text: $sport.hkFaceoffsTotal).keyboardType(.numberPad)
                }
            }
            Divider()
            FieldRowPlain {
                HStack {
                    TextField("Saves (GK)", text: $sport.hkSaves).keyboardType(.numberPad)
                    TextField("Penalty minutes", text: $sport.hkPenaltyMinutes).keyboardType(.numberPad)
                }
            }

        case .rugby:
            Divider()
            FieldRowPlain {
                TextField("Position (optional)", text: $sport.rgPosition)
                    .textFieldStyle(.plain)
            }
            Divider()
            FieldRowPlain {
                HStack {
                    TextField("Tries", text: $sport.rgTries).keyboardType(.numberPad)
                    TextField("Conv. made", text: $sport.rgConversionsMade).keyboardType(.numberPad)
                    TextField("Conv. att.", text: $sport.rgConversionsAttempted).keyboardType(.numberPad)
                }
            }
            Divider()
            FieldRowPlain {
                HStack {
                    TextField("Pen. goals made", text: $sport.rgPenaltyGoalsMade).keyboardType(.numberPad)
                    TextField("Pen. goals att.", text: $sport.rgPenaltyGoalsAttempted).keyboardType(.numberPad)
                }
            }
            Divider()
            FieldRowPlain {
                HStack {
                    TextField("Runs", text: $sport.rgRuns).keyboardType(.numberPad)
                    TextField("Meters gained", text: $sport.rgMetersGained).keyboardType(.numberPad)
                    TextField("Offloads", text: $sport.rgOffloads).keyboardType(.numberPad)
                }
            }
            Divider()
            FieldRowPlain {
                HStack {
                    TextField("Tackles made", text: $sport.rgTacklesMade).keyboardType(.numberPad)
                    TextField("Tackles missed", text: $sport.rgTacklesMissed).keyboardType(.numberPad)
                    TextField("Turnovers won", text: $sport.rgTurnoversWon).keyboardType(.numberPad)
                }
            }
            Divider()
            FieldRowPlain {
                HStack {
                    TextField("Yellow cards", text: $sport.rgYellow).keyboardType(.numberPad)
                    TextField("Red cards", text: $sport.rgRed).keyboardType(.numberPad)
                }
            }

        case .hyrox:
            hyroxSportFieldsContent

        case .ski:
            Divider()
            FieldRowPlain {
                HStack {
                    TextField("Total distance (km)", text: $sport.skiTotalDistanceKm)
                        .keyboardType(.decimalPad)
                    TextField("Runs", text: $sport.skiRunsCount)
                        .keyboardType(.numberPad)
                }
            }

            Divider()
            FieldRowPlain {
                HStack {
                    TextField("Max speed (km/h)", text: $sport.skiMaxSpeedKmh)
                        .keyboardType(.decimalPad)
                    TextField("Avg speed (km/h)", text: $sport.skiAvgSpeedKmh)
                        .keyboardType(.decimalPad)
                }
            }

            Divider()
            FieldRowPlain {
                HStack {
                    TextField("Vertical drop (m)", text: $sport.skiVerticalDropM)
                        .keyboardType(.numberPad)
                    TextField("Moving time (sec)", text: $sport.skiMovingTimeSec)
                        .keyboardType(.numberPad)
                    TextField("Paused time (sec)", text: $sport.skiPausedTimeSec)
                        .keyboardType(.numberPad)
                }
            }

            Divider()
            FieldRowPlain {
                TextField("Resort name", text: $sport.skiResortName)
                    .textFieldStyle(.plain)
            }

            Divider()
            FieldRowPlain {
                TextField("Snow condition", text: $sport.skiSnowCondition)
                    .textFieldStyle(.plain)
            }

            Divider()
            FieldRowPlain {
                TextField("Weather", text: $sport.skiWeather)
                    .textFieldStyle(.plain)
            }
        }
    }
    
    private func moveHyroxExercise(from index: Int, direction: Int) {
        var list = sport.hyExercises
        let j = index + direction
        guard list.indices.contains(index), list.indices.contains(j) else { return }
        list.swapAt(index, j)
        for idx in list.indices {
            list[idx].exerciseOrder = idx + 1
        }
        sport.hyExercises = list
    }

    private func patchHyroxExerciseDisplayNames(
        client: SupabaseClient,
        workoutId: Int,
        exercises: [HyroxExerciseForm]
    ) async throws {
        let rows: [HyroxExerciseFormatting.HyroxExerciseRowInput] = exercises.enumerated().map { idx, ex in
            HyroxExerciseFormatting.HyroxExerciseRowInput(
                exerciseOrder: idx + 1,
                exerciseCode: ex.exerciseCode,
                customDisplayName: ex.customDisplayName,
                notes: ex.notes
            )
        }
        let updates = HyroxExerciseFormatting.hyroxDisplayNameColumnUpdates(rows: rows)
        guard !updates.isEmpty else { return }

        let sessionRes = try await client
            .from("sport_sessions")
            .select("id")
            .eq("workout_id", value: workoutId)
            .single()
            .execute()
        struct SessionRow: Decodable { let id: Int }
        let sessionId = try JSONDecoder().decode(SessionRow.self, from: sessionRes.data).id

        struct Patch: Encodable { let exercise_display_name: String }
        for u in updates {
            _ = try await client
                .from("hyrox_session_exercises")
                .update(Patch(exercise_display_name: u.displayName))
                .eq("session_id", value: sessionId)
                .eq("exercise_order", value: u.exerciseOrder)
                .execute()
        }
    }

    private func recomputeDurationLabel() {
        guard endedAtEnabled else { durationLabelMin = nil; return }
        let secs = Int(endedAt.timeIntervalSince(startedAt))
        durationLabelMin = secs > 0 ? secs / 60 : 0
    }
    
    private func loadStrengthFoldersForPicker() async {
        do {
            let client = SupabaseManager.shared.client
            let res = try await client
                .from("strength_routine_folders")
                .select("id,name,updated_at,sort_order")
                .order("sort_order", ascending: true)
                .order("name", ascending: true)
                .execute()
            let rows = try JSONDecoder.supabase().decode([StrengthRoutineFolderRow].self, from: res.data)
            await MainActor.run { strengthFoldersForPicker = rows }
        } catch {
            await MainActor.run { strengthFoldersForPicker = [] }
        }
    }

    private func loadHyroxFoldersForPicker() async {
        do {
            let client = SupabaseManager.shared.client
            let res = try await client
                .from("hyrox_routine_folders")
                .select("id,name,updated_at,sort_order")
                .order("sort_order", ascending: true)
                .order("name", ascending: true)
                .execute()
            let rows = try JSONDecoder.supabase().decode([StrengthRoutineFolderRow].self, from: res.data)
            await MainActor.run { hyroxFoldersForPicker = rows }
        } catch {
            await MainActor.run { hyroxFoldersForPicker = [] }
        }
    }
    
    private func save() async {
        error = nil
        loading = true
        defer { loading = false }
        
        do {
            let client = SupabaseManager.shared.client
            let session = try await client.auth.session
            let userId = session.user.id
            var _: Int64? = nil
            
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

            if kind == .strength, usePerPersonStrengthEditor, participants.count > 2 {
                error = "Per-person planning supports at most two partners (three people total)."
                return
            }

            if kind == .strength, saveNewStrengthRoutine {
                let routineTitle = newStrengthRoutineName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !routineTitle.isEmpty {
                    if let existingId = try await StrengthRoutineNameValidator.existingRoutineIdForName(
                        client: client,
                        userId: userId,
                        trimmedName: routineTitle,
                        excludingRoutineId: nil,
                        folderId: newStrengthRoutineFolderId
                    ) {
                        await MainActor.run {
                            replacePendingIsRoutineOnly = false
                            replaceRoutinePendingId = existingId
                            showReplaceRoutineConfirm = true
                        }
                        return
                    }
                }
            }

            if kind == .sport, sport.sport == .hyrox, saveNewHyroxRoutine {
                let routineTitle = newHyroxRoutineName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !routineTitle.isEmpty {
                    if let existingId = try await HyroxRoutineNameValidator.existingRoutineIdForName(
                        client: client,
                        userId: userId,
                        trimmedName: routineTitle,
                        excludingRoutineId: nil,
                        folderId: newHyroxRoutineFolderId
                    ) {
                        await MainActor.run {
                            replaceHyroxPendingIsRoutineOnly = false
                            replaceHyroxRoutinePendingId = existingId
                            showReplaceHyroxRoutineConfirm = true
                        }
                        return
                    }
                }
            }

            if kind == .strength, !usePerPersonStrengthEditor {
                let tpl = strengthExercisesForRoutineTemplate()
                let items = strengthProgramItems(from: tpl)
                if !items.isEmpty {
                    let candidate = (
                        try? await fetchStrengthRoutineOverwriteCandidate(
                            client: client,
                            userId: userId,
                            proposed: items,
                            exerciseDisplayName: { eid in
                                catalog.first(where: { $0.id == eid })?.localizedName(for: exerciseLanguage) ?? ""
                            }
                        )
                    ) ?? .none
                    if case .prompt(let pr) = candidate {
                        let copied = tpl.map { $0.deepCopied() }
                        await MainActor.run {
                            pendingStrengthRoutineOverwriteExercises = copied
                            strengthRoutineOverwritePrompt = pr
                        }
                        return
                    }
                }
            }

            try await performSaveWorkoutAndRoutine(replacingStrengthRoutineId: nil, replacingHyroxRoutineId: nil)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func saveWithReplaceConfirm(replacingRoutineId: Int64?) async {
        guard let rid = replacingRoutineId else { return }
        error = nil
        loading = true
        defer { loading = false }
        do {
            try await performSaveWorkoutAndRoutine(
                replacingStrengthRoutineId: rid,
                replacingHyroxRoutineId: nil,
                strengthRoutinePrescriptionOverwrite: nil
            )
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func saveWithReplaceHyroxConfirm(replacingRoutineId: Int64?) async {
        guard let rid = replacingRoutineId else { return }
        error = nil
        loading = true
        defer { loading = false }
        do {
            try await performSaveWorkoutAndRoutine(
                replacingStrengthRoutineId: nil,
                replacingHyroxRoutineId: rid,
                strengthRoutinePrescriptionOverwrite: nil
            )
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func saveAfterStrengthRoutineOverwriteDecision(
        prompt: StrengthRoutineOverwritePrompt,
        updateRoutine: Bool
    ) async {
        let exercisesCopy = pendingStrengthRoutineOverwriteExercises
        await MainActor.run { pendingStrengthRoutineOverwriteExercises = [] }
        guard !exercisesCopy.isEmpty else { return }
        error = nil
        loading = true
        defer { loading = false }
        do {
            let overwrite: (routineId: Int64, exercises: [EditableExercise])? = updateRoutine
                ? (prompt.routineId, exercisesCopy)
                : nil
            try await performSaveWorkoutAndRoutine(
                replacingStrengthRoutineId: nil,
                replacingHyroxRoutineId: nil,
                strengthRoutinePrescriptionOverwrite: overwrite
            )
        } catch {
            await MainActor.run { self.error = error.localizedDescription }
        }
    }

    private func saveStrengthRoutineOnly() async {
        error = nil
        guard kind == .strength, canSaveRoutineOnly else { return }
        loadingRoutineOnly = true
        defer { loadingRoutineOnly = false }
        do {
            let client = SupabaseManager.shared.client
            let session = try await client.auth.session
            let userId = session.user.id
            let routineTitle = newStrengthRoutineName.trimmingCharacters(in: .whitespacesAndNewlines)
            if let existingId = try await StrengthRoutineNameValidator.existingRoutineIdForName(
                client: client,
                userId: userId,
                trimmedName: routineTitle,
                excludingRoutineId: nil,
                folderId: newStrengthRoutineFolderId
            ) {
                await MainActor.run {
                    replacePendingIsRoutineOnly = true
                    replaceRoutinePendingId = existingId
                    showReplaceRoutineConfirm = true
                }
                return
            }
            try await performSaveStrengthRoutineOnly(replacingRoutineId: nil)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func saveStrengthRoutineOnlyWithReplace(replacingRoutineId: Int64?) async {
        guard let rid = replacingRoutineId else { return }
        error = nil
        loadingRoutineOnly = true
        defer { loadingRoutineOnly = false }
        do {
            try await performSaveStrengthRoutineOnly(replacingRoutineId: rid)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func performSaveStrengthRoutineOnly(replacingRoutineId: Int64?) async throws {
        let client = SupabaseManager.shared.client
        let session = try await client.auth.session
        let userId = session.user.id
        let routineTitle = newStrengthRoutineName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !routineTitle.isEmpty else { return }
        let templateExercises = strengthExercisesForRoutineTemplate()
        let outcome = try await persistStrengthRoutineTemplate(
            client: client,
            userId: userId,
            name: routineTitle,
            folderId: newStrengthRoutineFolderId,
            exercises: templateExercises,
            replaceRoutineId: replacingRoutineId
        )
        var message = "Routine saved."
        if outcome.alsoHasAnotherRoutineWithSameProgram {
            message += " You already have another saved routine with the same exercises in this folder."
        }
        await MainActor.run {
            banner = Banner(message: message, type: .success)
            newStrengthRoutineName = ""
            newStrengthRoutineFolderId = nil
            saveNewStrengthRoutine = false
            focusNewRoutineNameField = false
        }
    }

    private func saveHyroxRoutineOnly() async {
        error = nil
        guard kind == .sport, sport.sport == .hyrox, canSaveHyroxRoutineOnly else { return }
        loadingHyroxRoutineOnly = true
        defer { loadingHyroxRoutineOnly = false }
        do {
            let client = SupabaseManager.shared.client
            let session = try await client.auth.session
            let userId = session.user.id
            let routineTitle = newHyroxRoutineName.trimmingCharacters(in: .whitespacesAndNewlines)
            if let existingId = try await HyroxRoutineNameValidator.existingRoutineIdForName(
                client: client,
                userId: userId,
                trimmedName: routineTitle,
                excludingRoutineId: nil,
                folderId: newHyroxRoutineFolderId
            ) {
                await MainActor.run {
                    replaceHyroxPendingIsRoutineOnly = true
                    replaceHyroxRoutinePendingId = existingId
                    showReplaceHyroxRoutineConfirm = true
                }
                return
            }
            try await performSaveHyroxRoutineOnly(replacingRoutineId: nil)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func saveHyroxRoutineOnlyWithReplace(replacingRoutineId: Int64?) async {
        guard let rid = replacingRoutineId else { return }
        error = nil
        loadingHyroxRoutineOnly = true
        defer { loadingHyroxRoutineOnly = false }
        do {
            try await performSaveHyroxRoutineOnly(replacingRoutineId: rid)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func performSaveHyroxRoutineOnly(replacingRoutineId: Int64?) async throws {
        let client = SupabaseManager.shared.client
        let session = try await client.auth.session
        let userId = session.user.id
        let routineTitle = newHyroxRoutineName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !routineTitle.isEmpty else { return }
        let outcome = try await insertHyroxRoutineTemplate(
            client: client,
            userId: userId,
            name: routineTitle,
            folderId: newHyroxRoutineFolderId,
            sport: sport,
            replaceRoutineId: replacingRoutineId
        )
        var message = "Hyrox routine saved."
        if outcome.alsoHasAnotherRoutineWithSameProgram {
            message += " You already have another saved routine with the same program in this folder."
        }
        await MainActor.run {
            banner = Banner(message: message, type: .success)
            newHyroxRoutineName = ""
            newHyroxRoutineFolderId = nil
            saveNewHyroxRoutine = false
            focusNewHyroxRoutineNameField = false
        }
    }

    private func performSaveWorkoutAndRoutine(
        replacingStrengthRoutineId: Int64?,
        replacingHyroxRoutineId: Int64? = nil,
        strengthRoutinePrescriptionOverwrite: (routineId: Int64, exercises: [EditableExercise])? = nil
    ) async throws {
        let client = SupabaseManager.shared.client
        let session = try await client.auth.session
        let userId = session.user.id
        var newWorkoutId: Int64? = nil

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        if kind == .strength, usePerPersonStrengthEditor, participants.count > 2 {
            throw NSError(
                domain: "AddWorkout",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: "Per-person planning supports at most two partners (three people total)."]
            )
        }

        switch kind {
            case .strength:
                if usePerPersonStrengthEditor {
                    var rows: [PlanStrengthSquadProgramRow] = []
                    guard let me = app.userId else { throw NSError(domain: "AddWorkout", code: 1, userInfo: [NSLocalizedDescriptionKey: "Not signed in"]) }
                    let hostItems = strengthLaneItems[0].compactMap { $0.toStrengthItem() }
                    guard !hostItems.isEmpty else { throw NSError(domain: "AddWorkout", code: 2, userInfo: [NSLocalizedDescriptionKey: "Host program is empty"]) }
                    rows.append(.init(owner_user_id: me, items: hostItems))
                    for (i, p) in participants.enumerated() {
                        let lane = i + 1
                        guard strengthLaneItems.indices.contains(lane) else { continue }
                        let theirs = strengthLaneItems[lane].compactMap { $0.toStrengthItem() }
                        guard !theirs.isEmpty else {
                            throw NSError(domain: "AddWorkout", code: 3, userInfo: [NSLocalizedDescriptionKey: "Each person needs at least one valid exercise."])
                        }
                        rows.append(.init(owner_user_id: p.user_id, items: theirs))
                    }
                    let squadParams = PlanStrengthSquadProgramsRPC(
                        p_programs: rows,
                        p_title: title,
                        p_notes: note,
                        p_started_at: iso.string(from: startedAt),
                        p_perceived_intensity: perceived.rawValue,
                        p_state: publishMode.stateParam,
                        p_ended_at: endedAtEnabled ? iso.string(from: endedAt) : ""
                    )
                    let res = try await client.rpc("plan_strength_squad_programs", params: squadParams).execute()
                    let created = try JSONDecoder().decode([Int64].self, from: res.data)
                    newWorkoutId = created.first
                } else {
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
                }
                
            case .cardio:
                let durSecHMS = hmsToSeconds(cardio.durH, cardio.durM, cardio.durS)
                let paceAuto  = autoPaceSec(distanceKmText: cardio.distanceKm,
                                            durH: cardio.durH, durM: cardio.durM, durS: cardio.durS)
                let statsJSON = try buildCardioStatsJSON(from: cardio)

                let params = RPCCardioV2Params(
                    p_user_id: userId,
                    p_activity_code: cardio.activity.rawValue,
                    p_title: title.isEmpty ? nil : title,
                    p_started_at: iso.string(from: startedAt),
                    p_ended_at: endedAtEnabled ? iso.string(from: endedAt) : nil,
                    p_notes: note.isEmpty ? nil : note,
                    p_distance_km: parseDouble(cardio.distanceKm),
                    p_duration_sec: durSecHMS ?? parseInt(cardio.durationSec),
                    p_avg_hr: parseInt(cardio.avgHR),
                    p_max_hr: parseInt(cardio.maxHR),
                    p_avg_pace_sec_per_km: paceAuto ?? parseInt(cardio.avgPaceSecPerKm),
                    p_elevation_gain_m: cardio.activity.showsElevation ? parseInt(cardio.elevationGainM) : nil,
                    p_perceived_intensity: perceived.rawValue,
                    p_state: publishMode.stateParam,
                    p_stats: statsJSON,
                    p_healthkit_uuid: nil,
                    p_route_geojson: nil
                )

                let res = try await client
                    .rpc("create_cardio_workout_v2", params: RPCCardioV2Wrapper(p: params))
                    .execute()
                if let created = try? JSONDecoder().decode(Int.self, from: res.data) {
                    newWorkoutId = Int64(created)
                }
                
            case .sport:
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
                var pDict: [String: AnyJSON] = [:]
                pDict["p_user_id"] = try .init(userId.uuidString)
                pDict["p_sport"] = try .init(sport.sport.rawValue)
                if let t = title.trimmedOrNil { pDict["p_title"] = try .init(t) }
                pDict["p_started_at"] = try .init(iso.string(from: startedAt))
                if endedAtEnabled { pDict["p_ended_at"] = try .init(iso.string(from: endedAt)) }
                if let n = note.trimmedOrNil { pDict["p_notes"] = try .init(n) }
                if let dm = durationMin { pDict["p_duration_min"] = try .init(dm) }
                if let sf = scoreFor { pDict["p_score_for"] = try .init(sf) }
                if let sa = scoreAgainst { pDict["p_score_against"] = try .init(sa) }

                if sport.sport != .ski {
                    pDict["p_match_result"] = try .init(sport.matchResult.rawValue)
                }

                if let ms = matchScoreTxt { pDict["p_match_score_text"] = try .init(ms) }
                if let loc = sport.location.trimmedOrNil { pDict["p_location"] = try .init(loc) }
                if let sn = sport.sessionNotes.trimmedOrNil { pDict["p_session_notes"] = try .init(sn) }

                pDict["p_perceived_intensity"] = try .init(perceived.rawValue)
                pDict["p_state"] = try .init(publishMode.stateParam)

                let pJSON = try AnyJSON(pDict)
                let statsJSON = try buildSportStatsJSON(from: sport)

                let res = try await client
                    .rpc("create_sport_workout_v2", params: RPCSportV2Wrapper(p: pJSON, p_stats: statsJSON))
                    .execute()
                
                if let created = try? JSONDecoder().decode(Int.self, from: res.data) {
                    newWorkoutId = Int64(created)
                }
                if sport.sport == .hyrox, let wid = newWorkoutId {
                    try await patchHyroxExerciseDisplayNames(
                        client: client,
                        workoutId: Int(wid),
                        exercises: sport.hyExercises
                    )
                }
            }
            if let wid = newWorkoutId, !(kind == .strength && usePerPersonStrengthEditor) {
                await addParticipants(to: wid)
            }
            if let wid = newWorkoutId,
               let activeCompetitionId = await CompetitionService.shared.fetchMyActiveCompetitionId() {
                try? await CompetitionService.shared.submitWorkoutToCompetition(
                    competitionId: activeCompetitionId,
                    workoutId: Int(wid)
                )
            }
            let successMessage: String = {
                if kind == .strength, usePerPersonStrengthEditor {
                    return publishMode == .add
                        ? "Everyone’s workout is saved! 💪"
                        : "Everyone’s plan is saved! 🗓️"
                }
                return publishMode == .add ? "Workout published! 💪" : "Workout planned! 🗓️"
            }()
            var routineSaveSuffix = ""
            if kind == .strength, saveNewStrengthRoutine {
                let routineTitle = newStrengthRoutineName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !routineTitle.isEmpty {
                    do {
                        let templateExercises = strengthExercisesForRoutineTemplate()
                        let outcome = try await persistStrengthRoutineTemplate(
                            client: client,
                            userId: userId,
                            name: routineTitle,
                            folderId: newStrengthRoutineFolderId,
                            exercises: templateExercises,
                            replaceRoutineId: replacingStrengthRoutineId
                        )
                        routineSaveSuffix = " Routine saved."
                        if outcome.alsoHasAnotherRoutineWithSameProgram {
                            routineSaveSuffix += " You already have another saved routine with the same exercises in this folder."
                        }
                    } catch {
                        routineSaveSuffix = " " + strengthRoutineUserFacingSaveError(error)
                        print("[StrengthRoutine][SAVE]", error.localizedDescription)
                    }
                }
            }
            if kind == .sport, sport.sport == .hyrox, saveNewHyroxRoutine {
                let routineTitle = newHyroxRoutineName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !routineTitle.isEmpty {
                    do {
                        let outcome = try await insertHyroxRoutineTemplate(
                            client: client,
                            userId: userId,
                            name: routineTitle,
                            folderId: newHyroxRoutineFolderId,
                            sport: sport,
                            replaceRoutineId: replacingHyroxRoutineId
                        )
                        routineSaveSuffix += " Hyrox routine saved."
                        if outcome.alsoHasAnotherRoutineWithSameProgram {
                            routineSaveSuffix += " You already have another saved routine with the same program in this folder."
                        }
                    } catch {
                        routineSaveSuffix += " " + hyroxRoutineUserFacingSaveError(error)
                        print("[HyroxRoutine][SAVE]", error.localizedDescription)
                    }
                }
            }
            if let o = strengthRoutinePrescriptionOverwrite {
                do {
                    try await applyStrengthRoutinePrescriptionUpdate(
                        client: client,
                        userId: userId,
                        routineId: o.routineId,
                        exercises: o.exercises
                    )
                    routineSaveSuffix += " Routine template updated."
                } catch {
                    routineSaveSuffix += " Could not update routine template: \(error.localizedDescription)"
                    print("[StrengthRoutine][OVERWRITE]", error.localizedDescription)
                }
            }
            await showSuccessAndGoHome(successMessage + routineSaveSuffix)
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
        groupProgrammingMode = .sharedSessionTemplate
        strengthLaneItems = [[EditableExercise()]]
        strengthProgramPage = 0
        strengthRecommendTargetLane = nil
        saveNewStrengthRoutine = false
        newStrengthRoutineName = ""
        newStrengthRoutineFolderId = nil
        focusNewRoutineNameField = false
        replaceRoutinePendingId = nil
        showReplaceRoutineConfirm = false
        replacePendingIsRoutineOnly = false
        saveNewHyroxRoutine = false
        newHyroxRoutineName = ""
        newHyroxRoutineFolderId = nil
        focusNewHyroxRoutineNameField = false
        replaceHyroxRoutinePendingId = nil
        showReplaceHyroxRoutineConfirm = false
        replaceHyroxPendingIsRoutineOnly = false
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

    private func strengthExercisesForRoutineTemplate() -> [EditableExercise] {
        if usePerPersonStrengthEditor, strengthLaneItems.indices.contains(strengthProgramPage) {
            return strengthLaneItems[strengthProgramPage]
        }
        return items
    }

    private func applyLoadedStrengthRoutine(_ exercises: [EditableExercise]) {
        guard !exercises.isEmpty else { return }
        let normalized = exercises.enumerated().map { idx, ex -> EditableExercise in
            var c = ex.deepCopied()
            c.orderIndex = idx + 1
            return c
        }
        if usePerPersonStrengthEditor, strengthLaneItems.indices.contains(strengthProgramPage) {
            strengthLaneItems[strengthProgramPage] = normalized
        } else {
            items = normalized
        }
    }

    private func persistStrengthRoutineTemplate(
        client: SupabaseClient,
        userId: UUID,
        name: String,
        folderId: Int64?,
        exercises: [EditableExercise],
        replaceRoutineId: Int64? = nil
    ) async throws -> StrengthRoutinePersistOutcome {
        try await StrengthRoutineRemotePersistence.insertStrengthRoutineTemplate(
            client: client,
            userId: userId,
            name: name,
            folderId: folderId,
            exercises: exercises,
            replaceRoutineId: replaceRoutineId
        )
    }
    
    private func strengthRoutineUserFacingSaveError(_ error: Error) -> String {
        let ns = error as NSError
        if ns.domain == "StrengthRoutine",
           let msg = ns.userInfo[NSLocalizedDescriptionKey] as? String, !msg.isEmpty {
            return msg
        }
        if let pe = error as? PostgrestError {
            if pe.code == "23505" {
                return "A routine with this name already exists in this folder. Choose another name."
            }
            let parts = [pe.message, pe.detail, pe.hint].compactMap { $0 }.filter { !$0.isEmpty }
            if !parts.isEmpty { return parts.joined(separator: " ") }
        }
        return "Routine was not saved."
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
            if let mins = parseInt(f.durationMin) {
                out["minutes_played"] = try .init(mins)
            }

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
            if let v = parseInt(f.rkAces)             { out["aces"]              = try .init(v) }
            if let v = parseInt(f.rkDoubleFaults)     { out["double_faults"]     = try .init(v) }
            if let v = parseInt(f.rkWinners)          { out["winners"]           = try .init(v) }
            if let v = parseInt(f.rkUnforcedErrors)   { out["unforced_errors"]   = try .init(v) }
            if let v = parseInt(f.rkSetsWon)          { out["sets_won"]          = try .init(v) }
            if let v = parseInt(f.rkSetsLost)         { out["sets_lost"]         = try .init(v) }
            if let v = parseInt(f.rkGamesWon)         { out["games_won"]         = try .init(v) }
            if let v = parseInt(f.rkGamesLost)        { out["games_lost"]        = try .init(v) }
            if let v = parseInt(f.rkBreakPointsWon)   { out["break_points_won"]  = try .init(v) }
            if let v = parseInt(f.rkBreakPointsTotal) { out["break_points_total"] = try .init(v) }
            if let v = parseInt(f.rkNetPointsWon)     { out["net_points_won"]    = try .init(v) }
            if let v = parseInt(f.rkNetPointsTotal)   { out["net_points_total"]  = try .init(v) }
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

        case .handball:
            var out: [String: AnyJSON] = [:]
            if let s = strOrNil(f.hbPosition)        { out["position"]            = try .init(s) }
            if let mins = parseInt(f.durationMin)    { out["minutes_played"]      = try .init(mins) }
            if let v = parseInt(f.hbGoals)           { out["goals"]               = try .init(v) }
            if let v = parseInt(f.hbShots)           { out["shots"]               = try .init(v) }
            if let v = parseInt(f.hbShotsOnTarget)   { out["shots_on_target"]     = try .init(v) }
            if let v = parseInt(f.hbAssists)         { out["assists"]             = try .init(v) }
            if let v = parseInt(f.hbSteals)          { out["steals"]              = try .init(v) }
            if let v = parseInt(f.hbBlocks)          { out["blocks"]              = try .init(v) }
            if let v = parseInt(f.hbTurnoversLost)   { out["turnovers_lost"]      = try .init(v) }
            if let v = parseInt(f.hbSevenMGoals)     { out["seven_m_goals"]       = try .init(v) }
            if let v = parseInt(f.hbSevenMAttempts)  { out["seven_m_attempts"]    = try .init(v) }
            if let v = parseInt(f.hbSaves)           { out["saves"]               = try .init(v) }
            if let v = parseInt(f.hbYellow)          { out["yellow_cards"]        = try .init(v) }
            if let v = parseInt(f.hbTwoMin)          { out["two_min_suspensions"] = try .init(v) }
            if let v = parseInt(f.hbRed)             { out["red_cards"]           = try .init(v) }
            return try AnyJSON(out)

        case .hockey:
            var out: [String: AnyJSON] = [:]
            if let s = strOrNil(f.hkPosition)        { out["position"]        = try .init(s) }
            if let mins = parseInt(f.durationMin)    { out["minutes_played"]  = try .init(mins) }
            if let v = parseInt(f.hkGoals)           { out["goals"]           = try .init(v) }
            if let v = parseInt(f.hkAssists)         { out["assists"]         = try .init(v) }
            if let v = parseInt(f.hkShotsOnGoal)     { out["shots_on_goal"]   = try .init(v) }
            if let v = parseInt(f.hkPlusMinus)       { out["plus_minus"]      = try .init(v) }
            if let v = parseInt(f.hkHits)            { out["hits"]            = try .init(v) }
            if let v = parseInt(f.hkBlocks)          { out["blocks"]          = try .init(v) }
            if let v = parseInt(f.hkFaceoffsWon)     { out["faceoffs_won"]    = try .init(v) }
            if let v = parseInt(f.hkFaceoffsTotal)   { out["faceoffs_total"]  = try .init(v) }
            if let v = parseInt(f.hkSaves)           { out["saves"]           = try .init(v) }
            if let v = parseInt(f.hkPenaltyMinutes)  { out["penalty_minutes"] = try .init(v) }
            return try AnyJSON(out)

        case .rugby:
            var out: [String: AnyJSON] = [:]
            if let s = strOrNil(f.rgPosition)             { out["position"]                = try .init(s) }
            if let mins = parseInt(f.durationMin)         { out["minutes_played"]          = try .init(mins) }
            if let v = parseInt(f.rgTries)               { out["tries"]                   = try .init(v) }
            if let v = parseInt(f.rgConversionsMade)     { out["conversions_made"]        = try .init(v) }
            if let v = parseInt(f.rgConversionsAttempted){ out["conversions_attempted"]   = try .init(v) }
            if let v = parseInt(f.rgPenaltyGoalsMade)    { out["penalty_goals_made"]      = try .init(v) }
            if let v = parseInt(f.rgPenaltyGoalsAttempted){ out["penalty_goals_attempted"] = try .init(v) }
            if let v = parseInt(f.rgRuns)                { out["runs"]                    = try .init(v) }
            if let v = parseInt(f.rgMetersGained)        { out["meters_gained"]           = try .init(v) }
            if let v = parseInt(f.rgOffloads)            { out["offloads"]                = try .init(v) }
            if let v = parseInt(f.rgTacklesMade)         { out["tackles_made"]            = try .init(v) }
            if let v = parseInt(f.rgTacklesMissed)       { out["tackles_missed"]          = try .init(v) }
            if let v = parseInt(f.rgTurnoversWon)        { out["turnovers_won"]           = try .init(v) }
            if let v = parseInt(f.rgYellow)              { out["yellow_cards"]            = try .init(v) }
            if let v = parseInt(f.rgRed)                 { out["red_cards"]               = try .init(v) }
            return try AnyJSON(out)

        case .hyrox:
            var out: [String: AnyJSON] = [:]
            if let s = strOrNil(f.hyDivision)        { out["division"]          = try .init(s) }
            if let s = strOrNil(f.hyCategory)        { out["category"]          = try .init(s) }
            if let s = strOrNil(f.hyAgeGroup)        { out["age_group"]         = try .init(s) }
            if let v = parseInt(f.hyOfficialTimeSec) { out["official_time_sec"] = try .init(v) }
            if let v = parseInt(f.hyRankOverall)     { out["rank_overall"]      = try .init(v) }
            if let v = parseInt(f.hyRankCategory)    { out["rank_category"]     = try .init(v) }
            if let v = parseInt(f.hyNoReps)          { out["no_reps"]           = try .init(v) }
            if let v = parseInt(f.hyPenaltyTimeSec)  { out["penalty_time_sec"]  = try .init(v) }
            if let v = parseInt(f.hyAvgHR)           { out["avg_hr"]            = try .init(v) }
            if let v = parseInt(f.hyMaxHR)           { out["max_hr"]            = try .init(v) }

            let exercises: [AnyJSON] = try f.hyExercises.enumerated().map { index, ex in
                var item: [String: AnyJSON] = [:]
                let persisted = HyroxExerciseFormatting.persistedPayload(
                    exerciseCode: ex.exerciseCode,
                    customDisplayName: ex.customDisplayName,
                    notes: ex.notes
                )
                item["exercise_code"] = try .init(persisted.code)
                if let d = persisted.displayName {
                    item["exercise_display_name"] = try .init(d)
                }
                item["exercise_order"] = try .init(index + 1)

                if let v = parseInt(ex.distanceM)      { item["distance_m"] = try .init(v) }
                if let v = parseInt(ex.reps)           { item["reps"] = try .init(v) }
                if let v = parseDouble(ex.weightKg)    { item["weight_kg"] = try .init(v) }
                if let v = parseInt(ex.durationSec)    { item["duration_sec"] = try .init(v) }
                if let v = parseInt(ex.heightCm)       { item["height_cm"] = try .init(v) }
                if let v = parseInt(ex.implementCount) { item["implement_count"] = try .init(v) }
                if let s = strOrNil(ex.notes)          { item["notes"] = try .init(s) }

                return try AnyJSON(item)
            }

            out["exercises"] = try .init(exercises)
            return try AnyJSON(out)
            
        case .ski:
            var out: [String: AnyJSON] = [:]
            if let v = parseDouble(f.skiTotalDistanceKm) { out["total_distance_km"] = try .init(v) }
            if let v = parseDouble(f.skiMaxSpeedKmh)     { out["max_speed_kmh"]     = try .init(v) }
            if let v = parseDouble(f.skiAvgSpeedKmh)     { out["avg_speed_kmh"]     = try .init(v) }
            if let v = parseInt(f.skiRunsCount)     { out["runs_count"]      = try .init(v) }
            if let v = parseInt(f.skiVerticalDropM){ out["vertical_drop_m"] = try .init(v) }
            if let v = parseInt(f.skiMovingTimeSec){ out["moving_time_sec"] = try .init(v) }
            if let v = parseInt(f.skiPausedTimeSec){ out["paused_time_sec"] = try .init(v) }
            if let s = strOrNil(f.skiResortName)    { out["resort_name"]    = try .init(s) }
            if let s = strOrNil(f.skiSnowCondition){ out["snow_condition"] = try .init(s) }
            if let s = strOrNil(f.skiWeather)      { out["weather"]        = try .init(s) }
            return try AnyJSON(out)
        }
    }
    
    private func buildCardioStatsJSON(from f: CardioForm) throws -> AnyJSON {
        var out: [String: AnyJSON] = [:]
        if f.cadenceRpm.trimmedOrNil != nil, let v = Int(f.cadenceRpm) { out["cadence_rpm"] = try .init(v) }
        if f.wattsAvg.trimmedOrNil != nil, let v = Int(f.wattsAvg)     { out["watts_avg"]   = try .init(v) }
        if f.inclinePercent.trimmedOrNil != nil, let v = Double(f.inclinePercent.replacingOccurrences(of: ",", with: ".")) { out["incline_pct"] = try .init(v) }
        if f.swimLaps.trimmedOrNil != nil, let v = Int(f.swimLaps)     { out["swim_laps"]   = try .init(v) }
        if f.poolLengthM.trimmedOrNil != nil, let v = Int(f.poolLengthM) { out["pool_length_m"] = try .init(v) }
        if let style = f.swimStyle.trimmedOrNil { out["swim_style"] = try .init(style) }
        if f.splitSecPer500m.trimmedOrNil != nil, let v = Int(f.splitSecPer500m) { out["split_sec_per_500m"] = try .init(v) }
        if f.activity.showsKmPaceSplits {
            let splits = CardioKmPaceSplits.parseFieldText(f.kmSplitsPaceText)
            if !splits.isEmpty {
                out[CardioKmPaceSplits.jsonKey] = try AnyJSON(splits.map { try AnyJSON($0) })
            }
        }
        return try AnyJSON(out)
    }
    
    private func applyStrengthRecommendation(_ rec: [StrengthRecommendationExercise]) {
        let newItems: [EditableExercise] = rec.enumerated().map { idx, ex in
            var e = EditableExercise()
            e.exerciseId = ex.exerciseId
            e.exerciseName = ex.displayName
            e.orderIndex = idx + 1
            e.notes = ""
            e.sets = collapsedEditableSetsFromRecommendation(ex.sets)
            return e
        }
        let lane = strengthRecommendTargetLane ?? (usePerPersonStrengthEditor ? strengthProgramPage : 0)
        strengthRecommendTargetLane = nil
        if usePerPersonStrengthEditor, strengthLaneItems.indices.contains(lane) {
            strengthLaneItems[lane] = newItems
        } else {
            items = newItems
        }
    }
    
    private func collapsedEditableSetsFromRecommendation(_ sets: [StrengthRecommendationSet]) -> [EditableSet] {
        let sorted = sets.sorted { $0.setNumber < $1.setNumber }
        guard !sorted.isEmpty else { return [EditableSet(setNumber: 1)] }
        var blocks: [(count: Int, template: StrengthRecommendationSet)] = []
        for s in sorted {
            if let li = blocks.indices.last,
               blocks[li].template.reps == s.reps,
               abs(blocks[li].template.weightKg - s.weightKg) < 0.02,
               optionalDoubleEqual(blocks[li].template.rpe, s.rpe),
               blocks[li].template.restSec == s.restSec {
                blocks[li].count += 1
            } else {
                blocks.append((1, s))
            }
        }
        return blocks.map { b in
            EditableSet(
                setNumber: b.count,
                reps: b.template.reps,
                weightKg: stringFromRecommendationKg(b.template.weightKg),
                rpe: b.template.rpe.map { stringFromRecommendationRpe($0) } ?? "",
                restSec: b.template.restSec,
                notes: ""
            )
        }
    }
    
    private func optionalDoubleEqual(_ a: Double?, _ b: Double?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case let (x?, y?): return abs(x - y) < 0.02
        default: return false
        }
    }
    
    private func stringFromRecommendationKg(_ x: Double) -> String {
        if x == floor(x) { return String(Int(x)) }
        return String(format: "%.1f", x)
    }
    
    private func stringFromRecommendationRpe(_ x: Double) -> String {
        if x == floor(x) { return String(Int(x)) }
        return String(format: "%.1f", x)
    }
    
    private func applyCardioRecommendation(_ r: CardioRecommendation) {
        cardio.activity = r.activity
        let sec = r.durationSec
        cardio.durH = String(sec / 3600)
        cardio.durM = String((sec % 3600) / 60)
        cardio.durS = String(sec % 60)
        didEditCardioDuration = true
        cardio.distanceKm = r.distanceKm.map { String(format: "%.2f", $0) } ?? ""
        cardio.elevationGainM = r.elevationGainM.map(String.init) ?? ""
        cardio.avgHR = r.avgHr.map(String.init) ?? ""
        cardio.maxHR = r.maxHr.map(String.init) ?? ""
        cardio.inclinePercent = r.inclinePercent.map { String(format: "%.1f", $0) } ?? ""
        cardio.cadenceRpm = r.cadenceRpm.map(String.init) ?? ""
        cardio.wattsAvg = r.wattsAvg.map(String.init) ?? ""
        cardio.splitSecPer500m = r.splitSecPer500m.map(String.init) ?? ""
        cardio.swimLaps = r.swimLaps.map(String.init) ?? ""
        cardio.poolLengthM = r.poolLengthM.map(String.init) ?? ""
        cardio.swimStyle = r.swimStyle ?? ""
        cardio.kmSplitsPaceText = ""
        updateAutoPaceIfNeeded()
    }
    
    private func applySportRecommendation(_ r: SportRecommendation) {
        switch r {
        case .durationOnly(let durationMin, _):
            sport.durationMin = String(durationMin)
            didEditSportDuration = true
        case .hyrox(let durationMin, let exercises, _):
            sport.sport = .hyrox
            sport.durationMin = String(durationMin)
            didEditSportDuration = true
            sport.hyExercises = exercises.map { ex in
                HyroxExerciseForm(
                    exerciseCode: ex.exerciseCode,
                    customDisplayName: ex.customDisplayName,
                    exerciseOrder: ex.exerciseOrder,
                    distanceM: ex.distanceM.map(String.init) ?? "",
                    reps: ex.reps.map(String.init) ?? "",
                    weightKg: ex.weightKg.map { $0 == floor($0) ? String(Int($0)) : String(format: "%.1f", $0) } ?? "",
                    durationSec: ex.durationSec.map(String.init) ?? "",
                    heightCm: ex.heightCm.map(String.init) ?? "",
                    implementCount: ex.implementCount.map(String.init) ?? "",
                    notes: ex.notes ?? ""
                )
            }
        }
    }
    
    private func exerciseSelected(_ ex: EditableExercise) -> Bool {
        ex.exerciseId != nil
    }
    
    private func exerciseLabel(for ex: EditableExercise) -> String {
        if let exid = ex.exerciseId,
           let found = catalog.first(where: { $0.id == exid }) {
            return found.localizedName(for: exerciseLanguage)
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

    private func resetDurationEditFlagsAndSyncSchedule() {
        didEditCardioDuration = false
        didEditSportDuration = false
        recomputeDurationLabel()
        syncDurationFromDates()
    }

    private func onKindChangedFromTypePicker(_ new: WorkoutKind) {
        if new == .strength {
            Task { await loadCatalogIfNeeded() }
        }
        resetDurationEditFlagsAndSyncSchedule()
    }

    private func onStartedAtChangedForDurationSync() {
        if endedAtEnabled, endedAt < startedAt {
            endedAt = startedAt
        }
        resetDurationEditFlagsAndSyncSchedule()
    }

    private func onEndedAtEnabledChangedForDurationSync(isOn: Bool) {
        if isOn {
            endedAt = max(endedAt, startedAt)
        }
        resetDurationEditFlagsAndSyncSchedule()
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
 
        switch d.kind {
        case .strength:
            if d.plannedStrengthPerPerson, let lanes = d.strengthLaneItems, !lanes.isEmpty {
                groupProgrammingMode = .individualPlans
                strengthLaneItems = lanes
                if let first = lanes.first {
                    items = first
                }
            } else {
                groupProgrammingMode = .sharedSessionTemplate
                items = d.strengthItems.isEmpty ? [EditableExercise()] : d.strengthItems
                strengthLaneItems = [items.map { $0.deepCopied() }]
            }

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
            skipNextSportScoreReset = true
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
        case .football, .basketball, .handball, .hockey, .rugby: return true
        default: return false
        }
    }
    private func sportUsesSetText(_ s: SportType) -> Bool {
        switch s {
        case .padel, .tennis, .badminton, .squash, .table_tennis, .volleyball:
            return true
        default:
            return false
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

extension EditableExercise {
    func deepCopied() -> EditableExercise {
        var copy = EditableExercise()
        copy.exerciseId = exerciseId
        copy.exerciseName = exerciseName
        copy.orderIndex = orderIndex
        copy.notes = notes
        copy.sets = sets.map {
            EditableSet(
                setNumber: $0.setNumber,
                reps: $0.reps,
                weightKg: $0.weightKg,
                rpe: $0.rpe,
                restSec: $0.restSec,
                notes: $0.notes
            )
        }
        return copy
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
    var activity: CardioActivityType = .run
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
    var cadenceRpm: String = ""
    var wattsAvg: String = ""
    var inclinePercent: String = ""
    var swimLaps: String = ""
    var poolLengthM: String = ""
    var swimStyle: String = ""
    var splitSecPer500m: String = ""
    var kmSplitsPaceText: String = ""
}

struct HyroxExerciseForm: Identifiable, Hashable {
    let id = UUID()
    var exerciseCode: String = HyroxExerciseCode.run.rawValue
    var customDisplayName: String = ""
    var exerciseOrder: Int = 1
    var distanceM: String = ""
    var reps: String = ""
    var weightKg: String = ""
    var durationSec: String = ""
    var heightCm: String = ""
    var implementCount: String = ""
    var notes: String = ""
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
    var hbPosition: String = ""
    var hbGoals: String = ""
    var hbShots: String = ""
    var hbShotsOnTarget: String = ""
    var hbAssists: String = ""
    var hbSteals: String = ""
    var hbBlocks: String = ""
    var hbTurnoversLost: String = ""
    var hbSevenMGoals: String = ""
    var hbSevenMAttempts: String = ""
    var hbSaves: String = ""
    var hbYellow: String = ""
    var hbTwoMin: String = ""
    var hbRed: String = ""
    var hkPosition: String = ""
    var hkGoals: String = ""
    var hkAssists: String = ""
    var hkShotsOnGoal: String = ""
    var hkPlusMinus: String = ""
    var hkHits: String = ""
    var hkBlocks: String = ""
    var hkFaceoffsWon: String = ""
    var hkFaceoffsTotal: String = ""
    var hkSaves: String = ""
    var hkPenaltyMinutes: String = ""
    var rgPosition: String = ""
    var rgTries: String = ""
    var rgConversionsMade: String = ""
    var rgConversionsAttempted: String = ""
    var rgPenaltyGoalsMade: String = ""
    var rgPenaltyGoalsAttempted: String = ""
    var rgRuns: String = ""
    var rgMetersGained: String = ""
    var rgOffloads: String = ""
    var rgTacklesMade: String = ""
    var rgTacklesMissed: String = ""
    var rgTurnoversWon: String = ""
    var rgYellow: String = ""
    var rgRed: String = ""
    var hyDivision: String = ""
    var hyCategory: String = ""
    var hyAgeGroup: String = ""
    var hyOfficialTimeSec: String = ""
    var hyRankOverall: String = ""
    var hyRankCategory: String = ""
    var hyNoReps: String = ""
    var hyPenaltyTimeSec: String = ""
    var hyAvgHR: String = ""
    var hyMaxHR: String = ""
    var hyExercises: [HyroxExerciseForm] = []
    var skiTotalDistanceKm: String = ""
    var skiRunsCount: String = ""
    var skiMaxSpeedKmh: String = ""
    var skiAvgSpeedKmh: String = ""
    var skiVerticalDropM: String = ""
    var skiMovingTimeSec: String = ""
    var skiPausedTimeSec: String = ""
    var skiResortName: String = ""
    var skiSnowCondition: String = ""
    var skiWeather: String = ""
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

private struct PlanStrengthSquadProgramRow: Encodable {
    let owner_user_id: UUID
    let items: [RPCStrengthParams.StrengthItem]
}

private struct PlanStrengthSquadProgramsRPC: Encodable {
    let p_programs: [PlanStrengthSquadProgramRow]
    let p_title: String
    let p_notes: String
    let p_started_at: String
    let p_perceived_intensity: String
    let p_state: String
    let p_ended_at: String
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
    let p_activity_type: String?
    let p_details: AnyJSON?
}

struct RPCCardioWrapper: Encodable {
    let p: RPCCardioParams
}

struct RPCCardioV2Params: Encodable {
    let p_user_id: UUID
    let p_activity_code: String
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
    let p_stats: AnyJSON
    let p_healthkit_uuid: String?
    let p_route_geojson: String?
}
struct RPCCardioV2Wrapper: Encodable {
    let p: RPCCardioV2Params
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
    let p: AnyJSON
    let p_stats: AnyJSON?
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

private struct StrengthRoutineFolderRow: Identifiable, Hashable, Decodable {
    let id: Int64
    let name: String
    let updated_at: Date?
    let sort_order: Int?
}

private struct StrengthRoutineListRow: Identifiable, Decodable {
    let id: Int64
    let name: String
    let updated_at: Date?
    let folder_id: Int64?
    let sort_order: Int?
}

enum StrengthRoutineNameValidator {
    static func isRoutineNameTaken(
        client: SupabaseClient,
        userId: UUID,
        trimmedName: String,
        excludingRoutineId: Int64?,
        folderId: Int64? = nil
    ) async throws -> Bool {
        if let _ = try await existingRoutineIdForName(
            client: client,
            userId: userId,
            trimmedName: trimmedName,
            excludingRoutineId: excludingRoutineId,
            folderId: folderId
        ) {
            return true
        }
        return false
    }

    static func existingRoutineIdForName(
        client: SupabaseClient,
        userId: UUID,
        trimmedName: String,
        excludingRoutineId: Int64?,
        folderId: Int64? = nil
    ) async throws -> Int64? {
        let t = trimmedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        struct R: Decodable { let id: Int64 }
        let rows: [R]
        if let fid = folderId {
            let res = try await client
                .from("strength_routines")
                .select("id")
                .eq("user_id", value: userId)
                .eq("name", value: t)
                .eq("folder_id", value: Int(fid))
                .limit(1)
                .execute()
            rows = try JSONDecoder.supabase().decode([R].self, from: res.data)
        } else {
            let res = try await client
                .from("strength_routines")
                .select("id")
                .eq("user_id", value: userId)
                .eq("name", value: t)
                .is("folder_id", value: nil)
                .limit(1)
                .execute()
            rows = try JSONDecoder.supabase().decode([R].self, from: res.data)
        }
        guard let row = rows.first else { return nil }
        if let ex = excludingRoutineId, row.id == ex { return nil }
        return row.id
    }
}

private func nextFolderSortOrderForInsert(client: SupabaseClient, userId: UUID) async throws -> Int {
    struct R: Decodable { let sort_order: Int? }
    let res = try await client
        .from("strength_routine_folders")
        .select("sort_order")
        .eq("user_id", value: userId)
        .order("sort_order", ascending: false)
        .limit(1)
        .execute()
    let rows = try JSONDecoder.supabase().decode([R].self, from: res.data)
    return (rows.first?.sort_order ?? 0) + 1
}

private struct StrengthRoutinesPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var app: AppState
    let exerciseDisplayName: (Int64) -> String
    let catalog: [Exercise]
    let loadingCatalog: Bool
    let exerciseLanguage: ExerciseLanguage
    let onApply: ([EditableExercise]) -> Void

    @State private var routines: [StrengthRoutineListRow] = []
    @State private var folders: [StrengthRoutineFolderRow] = []
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var showRenameSheet = false
    @State private var renameRoutineId: Int64?
    @State private var renameRoutineFolderId: Int64?
    @State private var renameDraft = ""
    @State private var renameError: String?
    @State private var routineIdPendingDelete: Int64?
    @State private var showNewFolderSheet = false
    @State private var newFolderName = ""
    @State private var newFolderError: String?
    @State private var showRenameFolderSheet = false
    @State private var renameFolderId: Int64?
    @State private var renameFolderDraft = ""
    @State private var renameFolderError: String?
    @State private var folderIdPendingDelete: Int64?
    @State private var collapsedFolderIds: Set<Int64> = []
    @State private var isUnfiledSectionCollapsed: Bool = false
    @AppStorage("strengthRoutinesSheet.collapsedFolderIdsCSV") private var collapsedFolderIdsCSV: String = ""
    @AppStorage("strengthRoutinesSheet.unfiledSectionCollapsed") private var storedUnfiledCollapsed: Bool = false
    @State private var routineSearchText: String = ""
    @State private var showDuplicateSheet = false
    @State private var duplicateSourceRoutine: StrengthRoutineListRow?
    @State private var duplicateNameDraft: String = ""
    @State private var duplicateTargetFolderId: Int64? = nil
    @State private var duplicateError: String?
    @State private var routinePendingEdit: StrengthRoutineListRow?
    @State private var shareRoutineChatToken: ShareRoutineChatToken?
    @State private var shareRoutineBuildError: String?
    @State private var routinePreviewToken: RoutinePreviewToken?
    @State private var previewBuildError: String?

    private struct ShareRoutineChatToken: Identifiable {
        let id = UUID()
        let snapshot: RoutineShareSnapshot
    }

    private struct RoutinePreviewToken: Identifiable {
        let id = UUID()
        let row: StrengthRoutineListRow
        let snapshot: RoutineShareSnapshot
    }

    private var sortedFolders: [StrengthRoutineFolderRow] {
        folders.sorted { a, b in
            let ao = Int64(a.sort_order ?? 0)
            let bo = Int64(b.sort_order ?? 0)
            if ao != bo { return ao < bo }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    private var displayRoutines: [StrengthRoutineListRow] {
        let q = routineSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return routines }
        return routines.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    private var displayFolders: [StrengthRoutineFolderRow] {
        let q = routineSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return sortedFolders }
        return sortedFolders.filter { f in
            f.name.localizedCaseInsensitiveContains(q)
                || displayRoutines.contains(where: { $0.folder_id == f.id })
        }
    }

    private func routinesUnfiled() -> [StrengthRoutineListRow] {
        displayRoutines
            .filter { $0.folder_id == nil }
            .sorted { a, b in
                let ao = Int64(a.sort_order ?? 0)
                let bo = Int64(b.sort_order ?? 0)
                if ao != bo { return ao < bo }
                return (a.updated_at ?? .distantPast) > (b.updated_at ?? .distantPast)
            }
    }

    private func routines(inFolderId fid: Int64) -> [StrengthRoutineListRow] {
        displayRoutines
            .filter { $0.folder_id == fid }
            .sorted { a, b in
                let ao = Int64(a.sort_order ?? 0)
                let bo = Int64(b.sort_order ?? 0)
                if ao != bo { return ao < bo }
                return (a.updated_at ?? .distantPast) > (b.updated_at ?? .distantPast)
            }
    }

    private func applyCollapsedPersistence() {
        if !collapsedFolderIdsCSV.isEmpty {
            collapsedFolderIds = Set(collapsedFolderIdsCSV.split(separator: ",").compactMap { Int64(String($0)) })
        }
        isUnfiledSectionCollapsed = storedUnfiledCollapsed
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let errorMessage {
                        SectionCard {
                            Text(errorMessage)
                                .foregroundStyle(.red)
                                .font(.footnote)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    SectionCard {
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(.secondary)
                            TextField("Search routines", text: $routineSearchText)
                                .textFieldStyle(.plain)
                        }
                    }
                    if loading, routines.isEmpty, folders.isEmpty {
                        SectionCard {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                    } else if routines.isEmpty, folders.isEmpty {
                        SectionCard {
                            Text("No saved routines yet. Save one when you publish a strength workout.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else if !routineSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, displayRoutines.isEmpty {
                        SectionCard {
                            Text("No matching routines.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        if !routinesUnfiled().isEmpty {
                            collapsibleUnfiledSection()
                        }
                        ForEach(displayFolders) { folder in
                            folderSection(folder)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.visible)
            .navigationTitle("Routines")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    HStack {
                        Menu {
                            Button("Expand all") {
                                withAnimation(.snappy) {
                                    collapsedFolderIds = []
                                    isUnfiledSectionCollapsed = false
                                }
                            }
                            Button("Collapse all") {
                                withAnimation(.snappy) {
                                    collapsedFolderIds = Set(sortedFolders.map(\.id))
                                    isUnfiledSectionCollapsed = routines.contains { $0.folder_id == nil }
                                }
                            }
                        } label: {
                            Image(systemName: "chevron.up.chevron.down")
                        }
                        Button {
                            newFolderName = ""
                            newFolderError = nil
                            showNewFolderSheet = true
                        } label: {
                            Image(systemName: "folder.badge.plus")
                        }
                        Button {
                            Task { await loadRoutines() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .disabled(loading)
                    }
                }
            }
        }
        .task {
            await loadRoutines()
            applyCollapsedPersistence()
        }
        .onChange(of: collapsedFolderIds) { _, new in
            collapsedFolderIdsCSV = new.sorted().map { String($0) }.joined(separator: ",")
        }
        .onChange(of: isUnfiledSectionCollapsed) { _, v in
            storedUnfiledCollapsed = v
        }
        .sheet(isPresented: $showRenameSheet) {
            NavigationStack {
                ScrollView {
                    SectionCard {
                        if let renameError {
                            Text(renameError)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        FieldRowPlain("Routine name") {
                            TextField("Routine name", text: $renameDraft)
                                .textFieldStyle(.plain)
                        }
                    }
                    .padding(16)
                }
                .scrollIndicators(.hidden)
                .navigationTitle("Rename routine")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            showRenameSheet = false
                            renameRoutineId = nil
                            renameRoutineFolderId = nil
                            renameError = nil
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            Task { await saveRename() }
                        }
                        .disabled(renameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showNewFolderSheet) {
            NavigationStack {
                ScrollView {
                    SectionCard {
                        if let newFolderError {
                            Text(newFolderError)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        FieldRowPlain("Folder name") {
                            TextField("Folder name", text: $newFolderName)
                                .textFieldStyle(.plain)
                        }
                    }
                    .padding(16)
                }
                .scrollIndicators(.hidden)
                .navigationTitle("New folder")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            showNewFolderSheet = false
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Create") {
                            Task { await createFolder() }
                        }
                        .disabled(newFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showRenameFolderSheet) {
            NavigationStack {
                ScrollView {
                    SectionCard {
                        if let renameFolderError {
                            Text(renameFolderError)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        FieldRowPlain("Folder name") {
                            TextField("Folder name", text: $renameFolderDraft)
                                .textFieldStyle(.plain)
                        }
                    }
                    .padding(16)
                }
                .scrollIndicators(.hidden)
                .navigationTitle("Rename folder")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            showRenameFolderSheet = false
                            renameFolderId = nil
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            Task { await saveRenameFolder() }
                        }
                        .disabled(renameFolderDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showDuplicateSheet) {
            NavigationStack {
                ScrollView {
                    SectionCard {
                        if let duplicateError {
                            Text(duplicateError)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        FieldRowPlain("Routine name") {
                            TextField("Routine name", text: $duplicateNameDraft)
                                .textFieldStyle(.plain)
                        }
                        if !sortedFolders.isEmpty {
                            Divider()
                            FieldRowPlain("Folder") {
                                Picker("", selection: $duplicateTargetFolderId) {
                                    Text("No folder").tag(Int64?.none)
                                    ForEach(sortedFolders) { f in
                                        Text(f.name).tag(Int64?.some(f.id))
                                    }
                                }
                                .labelsHidden()
                            }
                        }
                    }
                    .padding(16)
                }
                .scrollIndicators(.hidden)
                .navigationTitle("Duplicate routine")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            showDuplicateSheet = false
                            duplicateSourceRoutine = nil
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            Task { await saveDuplicateRoutine() }
                        }
                        .disabled(duplicateNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .sheet(item: $routinePreviewToken) { token in
            NavigationStack {
                SharedRoutineFromChatView(snapshot: token.snapshot)
                    .environmentObject(app)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(String(localized: "Close")) {
                                routinePreviewToken = nil
                            }
                        }
                        ToolbarItemGroup(placement: .primaryAction) {
                            Menu {
                                Button(String(localized: "Edit")) {
                                    let row = token.row
                                    routinePreviewToken = nil
                                    DispatchQueue.main.async {
                                        routinePendingEdit = row
                                    }
                                }
                                Button(String(localized: "Rename")) {
                                    let row = token.row
                                    routinePreviewToken = nil
                                    DispatchQueue.main.async {
                                        renameRoutineId = row.id
                                        renameRoutineFolderId = row.folder_id
                                        renameDraft = row.name
                                        renameError = nil
                                        showRenameSheet = true
                                    }
                                }
                                Button(String(localized: "Duplicate")) {
                                    let row = token.row
                                    routinePreviewToken = nil
                                    DispatchQueue.main.async {
                                        duplicateSourceRoutine = row
                                        duplicateNameDraft = "Copy of \(row.name)"
                                        duplicateTargetFolderId = row.folder_id
                                        duplicateError = nil
                                        showDuplicateSheet = true
                                    }
                                }
                                if routineSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                                   let neigh = routineNeighborInfo(token.row) {
                                    if neigh.index > 0 {
                                        Button(String(localized: "Move up")) {
                                            Task { await swapRoutineSortOrder(token.row, withOffset: -1) }
                                        }
                                    }
                                    if neigh.index < neigh.list.count - 1 {
                                        Button(String(localized: "Move down")) {
                                            Task { await swapRoutineSortOrder(token.row, withOffset: 1) }
                                        }
                                    }
                                }
                                Menu(String(localized: "Move to")) {
                                    Button(String(localized: "No folder")) {
                                        Task { await moveRoutine(token.row, to: nil) }
                                    }
                                    ForEach(sortedFolders) { f in
                                        Button(f.name) {
                                            Task { await moveRoutine(token.row, to: f.id) }
                                        }
                                    }
                                }
                                Button(String(localized: "Delete"), role: .destructive) {
                                    let id = token.row.id
                                    routinePreviewToken = nil
                                    DispatchQueue.main.async {
                                        routineIdPendingDelete = id
                                    }
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                            }

                            Button {
                                let row = token.row
                                Task {
                                    shareRoutineBuildError = nil
                                    do {
                                        let snap = try await buildStrengthRoutineShareSnapshot(row: row)
                                        await MainActor.run { routinePreviewToken = nil }
                                        let tokenSnap = ShareRoutineChatToken(snapshot: snap)
                                        DispatchQueue.main.async {
                                            shareRoutineChatToken = tokenSnap
                                        }
                                    } catch {
                                        await MainActor.run { shareRoutineBuildError = error.localizedDescription }
                                    }
                                }
                            } label: {
                                Image(systemName: "paperplane")
                            }

                            Button {
                                Task {
                                    await applyRoutine(id: token.row.id, dismissRoutinesPicker: true)
                                }
                            } label: {
                                Text(String(localized: "Apply"))
                            }
                        }
                    }
                    .gradientBG()
            }
        }
        .sheet(item: $shareRoutineChatToken) { token in
            ShareRoutineToChatSheet(snapshot: token.snapshot, onSent: {})
                .environmentObject(app)
                .gradientBG()
        }
        .sheet(item: $routinePendingEdit) { row in
            EditSavedStrengthRoutineSheet(
                routineId: row.id,
                routineName: row.name,
                catalog: catalog,
                loadingCatalog: loadingCatalog,
                exerciseLanguage: exerciseLanguage,
                exerciseDisplayName: exerciseDisplayName,
                onClose: { routinePendingEdit = nil },
                onSaved: {
                    routinePendingEdit = nil
                    Task { await loadRoutines() }
                }
            )
            .presentationDetents([.large])
            .presentationBackground(.clear)
        }
        .alert(
            String(localized: "Couldn't share routine"),
            isPresented: Binding(
                get: { shareRoutineBuildError != nil },
                set: { if !$0 { shareRoutineBuildError = nil } }
            )
        ) {
            Button(String(localized: "OK"), role: .cancel) { shareRoutineBuildError = nil }
        } message: {
            Text(shareRoutineBuildError ?? "")
        }
        .alert(
            String(localized: "Couldn't open routine"),
            isPresented: Binding(
                get: { previewBuildError != nil },
                set: { if !$0 { previewBuildError = nil } }
            )
        ) {
            Button(String(localized: "OK"), role: .cancel) { previewBuildError = nil }
        } message: {
            Text(previewBuildError ?? "")
        }
        .confirmationDialog(
            "Delete this routine?",
            isPresented: Binding(
                get: { routineIdPendingDelete != nil },
                set: { if !$0 { routineIdPendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let id = routineIdPendingDelete {
                    Task { await deleteRoutine(id: id) }
                }
                routineIdPendingDelete = nil
            }
            Button("Cancel", role: .cancel) {
                routineIdPendingDelete = nil
            }
        }
        .confirmationDialog(
            "Delete this folder?",
            isPresented: Binding(
                get: { folderIdPendingDelete != nil },
                set: { if !$0 { folderIdPendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let id = folderIdPendingDelete {
                    Task { await deleteFolder(id: id) }
                }
                folderIdPendingDelete = nil
            }
            Button("Cancel", role: .cancel) {
                folderIdPendingDelete = nil
            }
        }
    }

    @ViewBuilder
    private func collapsibleUnfiledSection() -> some View {
        let rows = routinesUnfiled()
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 6) {
                Button {
                    withAnimation(.snappy) { isUnfiledSectionCollapsed.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isUnfiledSectionCollapsed ? 0 : 90))
                        Text("No folder")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isUnfiledSectionCollapsed ? "Expand No folder" : "Collapse No folder")
                Spacer()
            }
            .padding(.horizontal, 2)

            if !isUnfiledSectionCollapsed {
                ForEach(rows) { row in
                    routineCard(row)
                }
            }
        }
    }

    @ViewBuilder
    private func folderSection(_ folder: StrengthRoutineFolderRow) -> some View {
        let inFolder = routines(inFolderId: folder.id)
        let isCollapsed = collapsedFolderIds.contains(folder.id)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 6) {
                Button {
                    withAnimation(.snappy) {
                        if isCollapsed { collapsedFolderIds.remove(folder.id) } else { collapsedFolderIds.insert(folder.id) }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                        Text(folder.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isCollapsed ? "Expand folder \(folder.name)" : "Collapse folder \(folder.name)")
                Spacer()
                Menu {
                    Button("Rename folder") {
                        renameFolderId = folder.id
                        renameFolderDraft = folder.name
                        renameFolderError = nil
                        showRenameFolderSheet = true
                    }
                    if routineSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                       let idx = sortedFolders.firstIndex(where: { $0.id == folder.id }) {
                        if idx > 0 {
                            Button("Move folder up") {
                                Task { await swapFolderSortOrder(at: idx, with: idx - 1) }
                            }
                        }
                        if idx < sortedFolders.count - 1 {
                            Button("Move folder down") {
                                Task { await swapFolderSortOrder(at: idx, with: idx + 1) }
                            }
                        }
                    }
                    Button("Delete folder", role: .destructive) {
                        folderIdPendingDelete = folder.id
                    }
                } label: {
                    Image(systemName: "folder.badge.gearshape")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 2)
            .padding(.top, routinesUnfiled().isEmpty && folder.id == sortedFolders.first?.id ? 0 : 6)

            if !isCollapsed {
                if inFolder.isEmpty {
                    SectionCard {
                        Text("No routines in this folder")
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    ForEach(inFolder) { row in
                        routineCard(row)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func routineCard(_ row: StrengthRoutineListRow) -> some View {
        SectionCard {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(row.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    if let u = row.updated_at {
                        Text(u, format: .dateTime.day().month().year().hour().minute())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(String(localized: "Tap to preview"))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    if loading { return }
                    Task {
                        previewBuildError = nil
                        do {
                            let snap = try await buildStrengthRoutineShareSnapshot(row: row)
                            await MainActor.run { routinePreviewToken = RoutinePreviewToken(row: row, snapshot: snap) }
                        } catch {
                            await MainActor.run { previewBuildError = error.localizedDescription }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Menu {
                    Button("Edit") {
                        routinePendingEdit = row
                    }
                    Button("Rename") {
                        renameRoutineId = row.id
                        renameRoutineFolderId = row.folder_id
                        renameDraft = row.name
                        renameError = nil
                        showRenameSheet = true
                    }
                    Button("Duplicate") {
                        duplicateSourceRoutine = row
                        duplicateNameDraft = "Copy of \(row.name)"
                        duplicateTargetFolderId = row.folder_id
                        duplicateError = nil
                        showDuplicateSheet = true
                    }
                    if routineSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                       let neigh = routineNeighborInfo(row) {
                        if neigh.index > 0 {
                            Button("Move up") {
                                Task { await swapRoutineSortOrder(row, withOffset: -1) }
                            }
                        }
                        if neigh.index < neigh.list.count - 1 {
                            Button("Move down") {
                                Task { await swapRoutineSortOrder(row, withOffset: 1) }
                            }
                        }
                    }
                    Menu("Move to") {
                        Button("No folder") {
                            Task { await moveRoutine(row, to: nil) }
                        }
                        ForEach(sortedFolders) { f in
                            Button(f.name) {
                                Task { await moveRoutine(row, to: f.id) }
                            }
                        }
                    }
                    Button("Delete", role: .destructive) {
                        routineIdPendingDelete = row.id
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }

                Button {
                    Task {
                        shareRoutineBuildError = nil
                        do {
                            let snap = try await buildStrengthRoutineShareSnapshot(row: row)
                            await MainActor.run { shareRoutineChatToken = ShareRoutineChatToken(snapshot: snap) }
                        } catch {
                            await MainActor.run { shareRoutineBuildError = error.localizedDescription }
                        }
                    }
                } label: {
                    Image(systemName: "paperplane")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    Task { await applyRoutine(id: row.id, dismissRoutinesPicker: true) }
                } label: {
                    Text("Apply")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .foregroundStyle(.white)
                        .background(Color.blue, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func orderedRoutinesInGroup(_ row: StrengthRoutineListRow) -> [StrengthRoutineListRow] {
        routines
            .filter { $0.folder_id == row.folder_id }
            .sorted { a, b in
                let ao = Int64(a.sort_order ?? 0)
                let bo = Int64(b.sort_order ?? 0)
                if ao != bo { return ao < bo }
                return a.id < b.id
            }
    }

    private func routineNeighborInfo(_ row: StrengthRoutineListRow) -> (list: [StrengthRoutineListRow], index: Int)? {
        let list = orderedRoutinesInGroup(row)
        guard let i = list.firstIndex(where: { $0.id == row.id }) else { return nil }
        return (list, i)
    }

    private func swapRoutineSortOrder(_ row: StrengthRoutineListRow, withOffset: Int) async {
        guard let info = routineNeighborInfo(row) else { return }
        let j = info.index + withOffset
        guard info.list.indices.contains(j) else { return }
        let a = info.list[info.index]
        let b = info.list[j]
        let ao = Int(a.sort_order ?? 0)
        let bo = Int(b.sort_order ?? 0)
        await MainActor.run { errorMessage = nil }
        do {
            let client = SupabaseManager.shared.client
            struct P: Encodable { let sort_order: Int }
            _ = try await client
                .from("strength_routines")
                .update(P(sort_order: bo))
                .eq("id", value: Int(a.id))
                .execute()
            _ = try await client
                .from("strength_routines")
                .update(P(sort_order: ao))
                .eq("id", value: Int(b.id))
                .execute()
            await loadRoutines()
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
        }
    }

    private func swapFolderSortOrder(at i: Int, with j: Int) async {
        let list = sortedFolders
        guard list.indices.contains(i), list.indices.contains(j) else { return }
        let a = list[i]
        let b = list[j]
        let ao = a.sort_order ?? 0
        let bo = b.sort_order ?? 0
        await MainActor.run { errorMessage = nil }
        do {
            let client = SupabaseManager.shared.client
            struct P: Encodable { let sort_order: Int }
            _ = try await client
                .from("strength_routine_folders")
                .update(P(sort_order: bo))
                .eq("id", value: Int(a.id))
                .execute()
            _ = try await client
                .from("strength_routine_folders")
                .update(P(sort_order: ao))
                .eq("id", value: Int(b.id))
                .execute()
            await loadRoutines()
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
        }
    }

    private func saveDuplicateRoutine() async {
        guard let src = duplicateSourceRoutine else { return }
        let name = duplicateNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            await MainActor.run { duplicateError = "Enter a routine name." }
            return
        }
        await MainActor.run { duplicateError = nil }
        do {
            let client = SupabaseManager.shared.client
            let session = try await client.auth.session
            let taken = try await StrengthRoutineNameValidator.isRoutineNameTaken(
                client: client,
                userId: session.user.id,
                trimmedName: name,
                excludingRoutineId: nil,
                folderId: duplicateTargetFolderId
            )
            if taken {
                await MainActor.run {
                    duplicateError = "A routine with this name already exists in this folder."
                }
                return
            }
            let res = try await client
                .from("strength_routines")
                .select(strengthTemplateDetailSelect())
                .eq("id", value: Int(src.id))
                .single()
                .execute()
            let detail = try JSONDecoder.supabase().decode(StrengthTemplateDetailWire.self, from: res.data)
            let built = editableExercisesFromStrengthTemplateDetail(detail, exerciseDisplayName: exerciseDisplayName)
            guard !built.isEmpty else {
                await MainActor.run { duplicateError = "This routine has no exercises to copy." }
                return
            }
            _ = try await StrengthRoutineRemotePersistence.insertStrengthRoutineTemplate(
                client: client,
                userId: session.user.id,
                name: name,
                folderId: duplicateTargetFolderId,
                exercises: built,
                replaceRoutineId: nil
            )
            await MainActor.run {
                showDuplicateSheet = false
                duplicateSourceRoutine = nil
            }
            await loadRoutines()
        } catch {
            await MainActor.run { duplicateError = error.localizedDescription }
        }
    }

    private func loadRoutines() async {
        await MainActor.run {
            loading = true
            errorMessage = nil
        }
        defer { Task { await MainActor.run { loading = false } } }
        do {
            let client = SupabaseManager.shared.client
            let rRes = try await client
                .from("strength_routines")
                .select("id,name,updated_at,folder_id,sort_order")
                .order("sort_order", ascending: true)
                .order("name", ascending: true)
                .execute()
            let fRes = try await client
                .from("strength_routine_folders")
                .select("id,name,updated_at,sort_order")
                .order("sort_order", ascending: true)
                .order("name", ascending: true)
                .execute()
            let rRows = try JSONDecoder.supabase().decode([StrengthRoutineListRow].self, from: rRes.data)
            let fRows = try JSONDecoder.supabase().decode([StrengthRoutineFolderRow].self, from: fRes.data)
            await MainActor.run {
                routines = rRows
                folders = fRows
            }
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
        }
    }

    private func buildStrengthRoutineShareSnapshot(row: StrengthRoutineListRow) async throws -> RoutineShareSnapshot {
        let client = SupabaseManager.shared.client
        let session = try await client.auth.session
        struct ProfileLite: Decodable {
            let username: String
            let avatar_url: String?
        }
        let pRes = try await client
            .from("profiles")
            .select("username,avatar_url")
            .eq("user_id", value: session.user.id.uuidString)
            .single()
            .execute()
        let prof = try JSONDecoder.supabase().decode(ProfileLite.self, from: pRes.data)
        let res = try await client
            .from("strength_routines")
            .select(strengthTemplateDetailSelect())
            .eq("id", value: Int(row.id))
            .single()
            .execute()
        let json = String(decoding: res.data, as: UTF8.self)
        let detail = try JSONDecoder.supabase().decode(StrengthTemplateDetailWire.self, from: res.data)
        let exs = (detail.strength_routine_exercises ?? []).sorted { $0.order_index < $1.order_index }
        let exerciseCount = exs.count
        var totalSets = 0
        var previewExerciseName: String?
        for (idx, ex) in exs.enumerated() {
            let n = (ex.strength_routine_sets ?? []).count
            totalSets += n == 0 ? 1 : n
            if idx == 0 {
                let cn = ex.custom_name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                previewExerciseName = cn.isEmpty ? "Exercise \(ex.exercise_id)" : cn
            }
        }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let updated = row.updated_at.map { iso.string(from: $0) }
        return RoutineShareSnapshot(
            v: 1,
            type: "routine_share",
            routine_kind: "strength",
            name: row.name,
            routine_id: row.id,
            updated_at: updated,
            owner_user_id: session.user.id,
            owner_username: prof.username,
            owner_avatar_url: prof.avatar_url,
            share_nonce: UUID().uuidString,
            detail_json: json,
            exercise_count: exerciseCount > 0 ? exerciseCount : nil,
            total_sets: totalSets > 0 ? totalSets : nil,
            preview_exercise_name: previewExerciseName
        )
    }

    private func applyRoutine(id: Int64, dismissRoutinesPicker: Bool = true) async {
        await MainActor.run { errorMessage = nil }
        do {
            let client = SupabaseManager.shared.client
            let res = try await client
                .from("strength_routines")
                .select(strengthTemplateDetailSelect())
                .eq("id", value: Int(id))
                .single()
                .execute()
            let detail = try JSONDecoder.supabase().decode(StrengthTemplateDetailWire.self, from: res.data)
            let built = editableExercisesFromStrengthTemplateDetail(detail, exerciseDisplayName: exerciseDisplayName)
            guard !built.isEmpty else {
                await MainActor.run { errorMessage = "This routine has no exercises." }
                return
            }
            await MainActor.run {
                onApply(built)
                if dismissRoutinesPicker {
                    dismiss()
                }
            }
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
        }
    }

    private func deleteRoutine(id: Int64) async {
        await MainActor.run { errorMessage = nil }
        do {
            let client = SupabaseManager.shared.client
            _ = try await client
                .from("strength_routines")
                .delete()
                .eq("id", value: Int(id))
                .execute()
            await loadRoutines()
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
        }
    }

    private func moveRoutine(_ row: StrengthRoutineListRow, to folderId: Int64?) async {
        await MainActor.run { errorMessage = nil }
        if row.folder_id == folderId { return }
        do {
            let client = SupabaseManager.shared.client
            let session = try await client.auth.session
            let taken = try await StrengthRoutineNameValidator.isRoutineNameTaken(
                client: client,
                userId: session.user.id,
                trimmedName: row.name,
                excludingRoutineId: row.id,
                folderId: folderId
            )
            if taken {
                await MainActor.run {
                    errorMessage = "A routine with this name already exists in that folder."
                }
                return
            }
            let nextOrder = try await StrengthRoutineRemotePersistence.nextSortOrderForInsert(
                client: client,
                userId: session.user.id,
                folderId: folderId
            )
            struct Patch: Encodable { let folder_id: Int64?; let sort_order: Int }
            _ = try await client
                .from("strength_routines")
                .update(Patch(folder_id: folderId, sort_order: nextOrder))
                .eq("id", value: Int(row.id))
                .execute()
            await loadRoutines()
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
        }
    }

    private func createFolder() async {
        let trimmed = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        await MainActor.run { newFolderError = nil }
        do {
            let client = SupabaseManager.shared.client
            let session = try await client.auth.session
            let next = try await nextFolderSortOrderForInsert(client: client, userId: session.user.id)
            struct Ins: Encodable { let user_id: UUID; let name: String; let sort_order: Int }
            _ = try await client
                .from("strength_routine_folders")
                .insert(Ins(user_id: session.user.id, name: trimmed, sort_order: next))
                .execute()
            await MainActor.run {
                showNewFolderSheet = false
                newFolderName = ""
            }
            await loadRoutines()
        } catch {
            await MainActor.run {
                if let pe = error as? PostgrestError, pe.code == "23505" {
                    newFolderError = "A folder with this name already exists."
                } else {
                    newFolderError = error.localizedDescription
                }
            }
        }
    }

    private func saveRenameFolder() async {
        let trimmed = renameFolderDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let fid = renameFolderId else { return }
        await MainActor.run { renameFolderError = nil }
        do {
            let client = SupabaseManager.shared.client
            let session = try await client.auth.session
            let existing = try await client
                .from("strength_routine_folders")
                .select("id")
                .eq("user_id", value: session.user.id)
                .eq("name", value: trimmed)
                .limit(1)
                .execute()
            struct Fid: Decodable { let id: Int64 }
            let found = try JSONDecoder.supabase().decode([Fid].self, from: existing.data)
            if let other = found.first, other.id != fid {
                await MainActor.run {
                    renameFolderError = "A folder with this name already exists."
                }
                return
            }
            struct NamePatch: Encodable { let name: String }
            _ = try await client
                .from("strength_routine_folders")
                .update(NamePatch(name: trimmed))
                .eq("id", value: Int(fid))
                .execute()
            await MainActor.run {
                showRenameFolderSheet = false
                renameFolderId = nil
            }
            await loadRoutines()
        } catch {
            if let pe = error as? PostgrestError, pe.code == "23505" {
                await MainActor.run { renameFolderError = "A folder with this name already exists." }
            } else {
                await MainActor.run { renameFolderError = error.localizedDescription }
            }
        }
    }

    private func deleteFolder(id: Int64) async {
        await MainActor.run { errorMessage = nil }
        do {
            let client = SupabaseManager.shared.client
            _ = try await client
                .from("strength_routine_folders")
                .delete()
                .eq("id", value: Int(id))
                .execute()
            await loadRoutines()
        } catch {
            let text = (error as? PostgrestError).map { e in
                e.message + (e.detail.map { " \($0)" } ?? "")
            } ?? error.localizedDescription
            let lower = text.lowercased()
            await MainActor.run {
                if lower.contains("foreign key") || lower.contains("strength_routines") || lower.contains("violat") {
                    errorMessage = "This folder still has routines. Move or remove them first."
                } else {
                    errorMessage = text
                }
            }
        }
    }

    private func saveRename() async {
        let trimmed = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let rid = renameRoutineId else { return }
        await MainActor.run {
            errorMessage = nil
            renameError = nil
        }
        do {
            let client = SupabaseManager.shared.client
            let session = try await client.auth.session
            let taken = try await StrengthRoutineNameValidator.isRoutineNameTaken(
                client: client,
                userId: session.user.id,
                trimmedName: trimmed,
                excludingRoutineId: rid,
                folderId: renameRoutineFolderId
            )
            if taken {
                await MainActor.run {
                    renameError = "A routine with this name already exists in this folder. Choose another name."
                }
                return
            }
            struct NamePatch: Encodable { let name: String }
            _ = try await client
                .from("strength_routines")
                .update(NamePatch(name: trimmed))
                .eq("id", value: Int(rid))
                .execute()
            await MainActor.run {
                showRenameSheet = false
                renameRoutineId = nil
                renameRoutineFolderId = nil
                renameError = nil
            }
            await loadRoutines()
        } catch {
            await MainActor.run { renameError = error.localizedDescription }
        }
    }
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
