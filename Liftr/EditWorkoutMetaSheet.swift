import SwiftUI
import Supabase

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
      var notes: String
      var sets: [SEditableSet]
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
          content.labelsHidden()
        } label: {
          if let title { Text(title) }
        }
        .padding(.vertical, 10)
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
              }

              Divider().padding(.vertical, 6)

              FieldRowPlain("Finished") {
                Toggle("", isOn: $endedAtEnabled)
              }

              if endedAtEnabled {
                Divider().padding(.vertical, 6)
                FieldRowPlain("Ended") {
                  DatePicker("", selection: $endedAt, in: startedAt..., displayedComponents: [.date, .hourAndMinute])
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
      .sheet(isPresented: $showExercisePicker) {
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
    }
  }

  private var cardioSection: some View {
    Section {
      TextField("Modality", text: $c_modality)
        HStack(spacing: 12) {
          TextField("Distance (km)", text: $c_distanceKm)
            .keyboardType(.decimalPad)

          VStack(alignment: .leading, spacing: 6) {
            Text("Duration").font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 6) {
              TextField("h", text: $c_durH).keyboardType(.numberPad).frame(width: 36)
              Text(":")
              TextField("m", text: $c_durM).keyboardType(.numberPad).frame(width: 36)
              Text(":")
              TextField("s", text: $c_durS).keyboardType(.numberPad).frame(width: 36)
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
    } header: { Text("CARDIO") }
  }

    private var sportSection: some View {
      Section {
        Picker("Sport", selection: $s_sport) {
          ForEach(SportType.allCases) { Text($0.label).tag($0) }
        }
        TextField("Duration (min)", text: $s_durationMin).keyboardType(.numberPad)

        if sportUsesNumericScore(s_sport) {
          HStack {
            TextField("Score for", text: $s_scoreFor).keyboardType(.numberPad)
            TextField("Score against", text: $s_scoreAgainst).keyboardType(.numberPad)
          }
        }

        if sportUsesSetText(s_sport) {
          TextField("Sets / score text (optional)", text: $s_matchScoreText)
        }

        Picker("Match result", selection: $s_matchResult) {
          ForEach(MatchResult.allCases) { Text($0.label).tag($0) }
        }
        TextField("Location (optional)", text: $s_location)
        TextField("Session notes", text: $s_sessionNotes, axis: .vertical)
      } header: { Text("SPORT") }
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
            .select("*")
            .eq("workout_id", value: workoutId)
            .single()
            .execute()
            struct Row: Decodable {
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
            s_scoreFor = r.score_for.map(String.init) ?? ""
            s_scoreAgainst = r.score_against.map(String.init) ?? ""
            s_matchResult = MatchResult(rawValue: r.match_result ?? "") ?? .unfinished
            s_matchScoreText = r.match_score_text ?? ""
            s_location = r.location ?? ""
            s_sessionNotes = r.notes ?? ""

        case "strength":
          let exQ = try await SupabaseManager.shared.client
            .from("workout_exercises")
            .select("id, exercise_id, order_index, notes, exercises(name)")
            .eq("workout_id", value: workoutId)
            .order("order_index", ascending: true)
            .execute()

          struct ExWire: Decodable {
            let id: Int
            let exercise_id: Int
            let order_index: Int
            let notes: String?
            let exercises: ExName?
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
        _ = try await SupabaseManager.shared.client
          .from("workouts")
          .update(common)
          .eq("id", value: workoutId)
          .execute()

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
            let sport: String
            let duration_sec: Int?
            let score_for: Int?
            let score_against: Int?
            let match_result: String?
            let match_score_text: String?
            let location: String?
            let notes: String?
          }
          let payload = SportPayload(
            sport: s_sport.rawValue,
            duration_sec: parseInt(s_durationMin).map { $0 * 60 },
            score_for: parseInt(s_scoreFor),
            score_against: parseInt(s_scoreAgainst),
            match_result: s_matchResult.rawValue,
            match_score_text: s_matchScoreText.trimmedOrNil,
            location: s_location.trimmedOrNil,
            notes: s_sessionNotes.trimmedOrNil
          )
          _ = try await SupabaseManager.shared.client
            .from("sport_sessions")
            .update(payload)
            .eq("workout_id", value: workoutId)
            .execute()

        case "strength":
          for ex in s_items {
            struct ExPayload: Encodable { let exercise_id: Int; let notes: String? }
            _ = try await SupabaseManager.shared.client
              .from("workout_exercises")
              .update(ExPayload(exercise_id: ex.exerciseId, notes: ex.notes.trimmedOrNil))
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
            "notes": nil
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
    
    // helpers to decide which sport fields to show
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
    
  private func parseInt(_ s: String) -> Int? {
    let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
    return t.isEmpty ? nil : Int(t)
  }
  private func parseDouble(_ s: String) -> Double? {
    let t = s.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespacesAndNewlines)
    return t.isEmpty ? nil : Double(t)
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
