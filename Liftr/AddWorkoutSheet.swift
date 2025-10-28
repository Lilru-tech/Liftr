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
          ForEach(filtered) { ex in
            HStack {
              VStack(alignment: .leading, spacing: 2) {
                Text(ex.name)
                Text([ex.category, ex.muscle_primary, ex.equipment].compactMap { $0 }.joined(separator: " · "))
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
            .contentShape(Rectangle())
            .onTapGesture {
              selected = ex
              dismiss()
            }
          }
      }
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
  @State private var confirmRemoveIndex: Int? = nil
  @State private var publishMode: PublishMode = .add
    
    init(draft: AddWorkoutDraft? = nil) {
      if let d = draft {
        _kind      = State(initialValue: d.kind)
        _title     = State(initialValue: d.title)
        _note      = State(initialValue: d.note)
        _startedAt = State(initialValue: d.startedAt)
        _endedAtEnabled = State(initialValue: d.endedAt != nil)
        _endedAt   = State(initialValue: d.endedAt ?? d.startedAt)
        _perceived = State(initialValue: d.perceived)

        switch d.kind {
        case .strength:
          _items  = State(initialValue: d.strengthItems.isEmpty ? [EditableExercise()] : d.strengthItems)
        case .cardio:
          _cardio = State(initialValue: d.cardio ?? CardioForm())
        case .sport:
          _sport  = State(initialValue: d.sport ?? SportForm())
        }
      }
    }

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
                        }
                        Divider()
                        FieldRowPlain("Finished") { Toggle("", isOn: $endedAtEnabled) }
                        
                        if endedAtEnabled {
                            Divider()
                            FieldRowPlain("Ended at") {
                                DatePicker("", selection: $endedAt, in: startedAt..., displayedComponents: [.date, .hourAndMinute])
                            }
                            if let dur = durationMinutes {
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
                } else {
                    ExercisePickerSheet(all: catalog, selected: .constant(nil))
                }
            }
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
                    .onChange(of: cardio.durH) { _, _ in updateAutoPaceIfNeeded() }

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
                ForEach(SportType.allCases) { s in
                  Text(s.label).tag(s)
                }
              }
              .pickerStyle(.menu)
            }

          Divider()

          FieldRowPlain {
            TextField("Duration (min)", text: $sport.durationMin)
              .keyboardType(.numberPad)
              .textFieldStyle(.plain)
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

            FieldRowPlain {
              Picker("", selection: $sport.matchResult) {
                ForEach(MatchResult.allCases) { r in
                  Text(r.label).tag(r)
                }
              }
              .pickerStyle(.menu)
            }

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

  private var durationMinutes: Int? {
    guard endedAtEnabled else { return nil }
    let secs = Int(endedAt.timeIntervalSince(startedAt))
    return secs > 0 ? secs / 60 : 0
  }

  private func save() async {
    error = nil
    loading = true
    defer { loading = false }

    do {
      let client = SupabaseManager.shared.client
      let session = try await client.auth.session
      let userId = session.user.id

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

          _ = try await client
            .rpc("create_cardio_workout_v1", params: RPCCardioWrapper(p: params))
            .execute()

      case .sport:
          let minutes = parseInt(sport.durationMin) ?? durationMinutes
          let durationMin = minutes
          let payload = RPCSportParams(
            p_user_id: userId,
            p_sport: sport.sport.rawValue,
            p_title: title.isEmpty ? nil : title,
            p_started_at: iso.string(from: startedAt),
            p_ended_at: endedAtEnabled ? iso.string(from: endedAt) : nil,
            p_notes: note.isEmpty ? nil : note,
            p_duration_min: durationMin,
            p_duration_sec: nil,
            p_score_for: parseInt(sport.scoreFor),
            p_score_against: parseInt(sport.scoreAgainst),
            p_match_result: sport.matchResult.rawValue,
            p_match_score_text: sport.matchScoreText.trimmedOrNil,
            p_location: sport.location.trimmedOrNil,
            p_session_notes: sport.sessionNotes.trimmedOrNil,
            p_perceived_intensity: perceived.rawValue,
            p_state: publishMode.stateParam
          )

          _ = try await client
            .rpc("create_sport_workout_v1", params: RPCSportWrapper(p: payload))
            .execute()
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

  private func parseInt(_ s: String) -> Int? {
    let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
    return t.isEmpty ? nil : Int(t)
  }

  private func parseDouble(_ s: String) -> Double? {
    let t = s.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespacesAndNewlines)
    return t.isEmpty ? nil : Double(t)
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

    private func sportUsesNumericScore(_ s: SportType) -> Bool {
      switch s {
        case .football, .basketball, .handball, .hockey, .rugby: return true
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
      sets: cleaned.map { $0.toStrengthSet() }
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
  var sport: SportType = .football
  var durationMin: String = ""
  var scoreFor: String = ""
  var scoreAgainst: String = ""
  var matchResult: MatchResult = .unfinished
  var matchScoreText: String = ""
  var location: String = ""
  var sessionNotes: String = ""
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
