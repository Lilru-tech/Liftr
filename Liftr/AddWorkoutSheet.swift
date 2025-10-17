import SwiftUI
import Supabase

// MARK: - Exercise catalog model
private struct Exercise: Identifiable, Decodable {
  let id: Int64
  let name: String
  let category: String?
  let modality: String?
  let muscle_primary: String?
  let equipment: String?
}

private enum WorkoutIntensity: String, CaseIterable, Identifiable {
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

// MARK: - Sheet to pick an exercise
private struct ExercisePickerSheet: View {
  let all: [Exercise]
  @Binding var selected: Exercise?
  @Environment(\.dismiss) private var dismiss

  @State private var query = ""

  var filtered: [Exercise] {
    let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !q.isEmpty else { return all }
    return all.filter { $0.name.lowercased().contains(q) }
  }

  var body: some View {
    NavigationStack {
      List {
        ForEach(filtered) { ex in
          Button {
            selected = ex
            dismiss()
          } label: {
            VStack(alignment: .leading, spacing: 2) {
              Text(ex.name)
              Text([ex.category, ex.muscle_primary, ex.equipment].compactMap { $0 }.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }
        }
      }
      .searchable(text: $query)
      .navigationTitle("Choose exercise")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
      }
    }
  }
}

// Wrapper para .sheet(item:)
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

struct AddWorkoutSheet: View {
  @Environment(\.dismiss) private var dismiss

  @State private var kind: WorkoutKind = .strength
  @State private var title: String = ""
  @State private var note: String = ""
  @State private var startedAt: Date = .now
  @State private var endedAtEnabled: Bool = false
  @State private var endedAt: Date = .now

  // Strength
  @State private var items: [EditableExercise] = [EditableExercise()]

  // Cardio / Sport
  @State private var cardio = CardioForm()
  @State private var sport = SportForm()

  // Catalog
  @State private var catalog: [Exercise] = []
  @State private var loadingCatalog = false
  @State private var pickerHandle: PickerHandle? = nil   // 👈 antes era UUID?

  @State private var loading = false
  @State private var error: String?
  @State private var perceived: WorkoutIntensity = .moderate


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
            .listRowBackground(Color.clear)   // <- deja que se vea la tarjeta

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
        .listRowBackground(Color.clear)      // ← QUITA el fondo de tarjeta de la sección
        .listSectionSpacing(-10)
    }
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
      }
      // exercise picker sheet
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

  // MARK: Sections

    // Botón con el mismo look & feel que Register
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
    
    // MARK: - EXERCISES
    private var strengthSection: some View {
      Section {
        SectionCard {
          // Lista de ejercicios
          ForEach(items.indices, id: \.self) { i in
            if i != items.startIndex { Divider().padding(.vertical, 6) }

            // Exercise picker
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

            // Alias
            FieldRowPlain("Alias") {
              TextField("Exercise name (optional)", text: $items[i].exerciseName)
                .textFieldStyle(.plain)
            }

            Divider()

            // Notas del ejercicio
            FieldRowPlain("Notes") {
              TextField("Notes (exercise)", text: $items[i].notes)
                .textFieldStyle(.plain)
            }

            // Sets
            ForEach(items[i].sets.indices, id: \.self) { s in
              Divider()
              LabeledContent {
                HStack(spacing: 2) {
                    Stepper("", value: $items[i].sets[s].setNumber, in: 1...99)
                      .labelsHidden()
                      .controlSize(.mini)
                      .scaleEffect(0.70, anchor: .leading)
                      .frame(width: 70)
                      .offset(x: -15)

                  TextField("Reps", value: $items[i].sets[s].reps, format: .number)
                    .keyboardType(.numberPad)
                    .frame(width: 50)

                  TextField("Weight kg", text: $items[i].sets[s].weightKg)
                    .keyboardType(.decimalPad)
                    .frame(width: 78)

                  TextField("RPE", text: $items[i].sets[s].rpe)
                    .keyboardType(.decimalPad)
                    .frame(width: 44)

                  if items[i].sets.count > 1 {
                    Button(role: .destructive) {
                      items[i].sets.remove(at: s)
                    } label: {
                      Image(systemName: "minus.circle.fill")
                    }
                    .buttonStyle(.borderless)
                  }
                }
              } label: {
                Text("Set \(items[i].sets[s].setNumber)")
                  .lineLimit(1)
                  .layoutPriority(1)
              }
              .font(.subheadline)
            }

            // Acciones del ejercicio
            Divider().padding(.vertical, 4)
            HStack {
                Button {
                  items[i].sets.append(EditableSet(setNumber: 1)) // ← siempre Set 1
                } label: { Label("Add set", systemImage: "plus.circle") }
                .buttonStyle(.borderless)

              Spacer()

              if items.count > 1 {
                Button(role: .destructive) {
                  items.remove(at: i)
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

          // Botón "Add exercise"
          Divider().padding(.vertical, 6)
          Button {
            let nextOrder = (items.last?.orderIndex ?? 0) + 1
            items.append(EditableExercise(orderIndex: nextOrder))
          } label: {
            Label("Add exercise", systemImage: "plus")
          }
          .buttonStyle(.borderless)
          .padding(.top, 2)
        }

        // Botón Save pegado al final de la sección
        saveButton
          .padding(.top, 8)
      } header: {
        Text("EXERCISES").foregroundStyle(.secondary)
      }
      .listRowBackground(Color.clear) // deja ver la tarjeta
    }
    
    // MARK: - CARDIO
    private var cardioSection: some View {
      Section {
        SectionCard {
          // Modality
          FieldRowPlain {
            TextField("Modality (e.g. Run, Bike…)", text: $cardio.modality)
              .textFieldStyle(.plain)
          }

          Divider()

          // Distance / Duration
          HStack {
            TextField("Distance (km)", text: $cardio.distanceKm).keyboardType(.decimalPad)
            TextField("Duration (sec)", text: $cardio.durationSec).keyboardType(.numberPad)
          }

          Divider()

          // HR
          HStack {
            TextField("Avg HR", text: $cardio.avgHR).keyboardType(.numberPad)
            TextField("Max HR", text: $cardio.maxHR).keyboardType(.numberPad)
          }

          Divider()

          // Pace / Elevation
          HStack {
            TextField("Avg pace (s/km)", text: $cardio.avgPaceSecPerKm).keyboardType(.numberPad)
            TextField("Elevation gain (m)", text: $cardio.elevationGainM).keyboardType(.numberPad)
          }
        }

        saveButton
          .padding(.top, 8)
      } header: {
        Text("CARDIO").foregroundStyle(.secondary)
      }
      .listRowBackground(Color.clear)
    }
    
    // MARK: - SPORT
    private var sportSection: some View {
      Section {
        SectionCard {
          FieldRowPlain {
            TextField("Sport (e.g. Football, Tennis…)", text: $sport.sport)
              .textFieldStyle(.plain)
          }

          Divider()

          FieldRowPlain {
            TextField("Duration (min)", text: $sport.durationMin)
              .keyboardType(.numberPad)
              .textFieldStyle(.plain)
          }

          Divider()

          FieldRowPlain {
            TextField("Match result (optional)", text: $sport.matchResult)
              .textFieldStyle(.plain)
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

  // MARK: Save rules

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
      return !sport.sport.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
  }

  private var durationMinutes: Int? {
    guard endedAtEnabled else { return nil }
    let secs = Int(endedAt.timeIntervalSince(startedAt))
    return secs > 0 ? secs / 60 : 0
  }

  // MARK: Save

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
            p_perceived_intensity: perceived.rawValue   // si lo dejaste no-opcional; si opcional, usa ?.rawValue
          )
        _ = try await client.rpc("create_strength_workout", params: params).execute()

      case .cardio:
          let params = RPCCardioParams(
            p_user_id: userId,
            p_modality: cardio.modality,
            p_title: title.isEmpty ? nil : title,
            p_started_at: iso.string(from: startedAt),
            p_ended_at: endedAtEnabled ? iso.string(from: endedAt) : nil,
            p_notes: note.isEmpty ? nil : note,
            p_distance_km: parseDouble(cardio.distanceKm),
            p_duration_sec: parseInt(cardio.durationSec),
            p_avg_hr: parseInt(cardio.avgHR),
            p_max_hr: parseInt(cardio.maxHR),
            p_avg_pace_sec_per_km: parseInt(cardio.avgPaceSecPerKm),
            p_elevation_gain_m: parseInt(cardio.elevationGainM),
            p_perceived_intensity: perceived.rawValue   // 👈 NUEVO (o ?.rawValue si opcional)
          )
        _ = try await client.rpc("create_cardio_workout", params: params).execute()

      case .sport:
        let minutes = parseInt(sport.durationMin) ?? durationMinutes

        let payload = RPCSportParams(
          p_user_id: userId,
          p_sport: sport.sport,
          p_title: title.isEmpty ? nil : title,
          p_started_at: iso.string(from: startedAt),
          p_ended_at: endedAtEnabled ? iso.string(from: endedAt) : nil,
          p_notes: note.isEmpty ? nil : note,
          p_duration_min: minutes,
          p_match_result: sport.matchResult.isEmpty ? nil : sport.matchResult,
          p_session_notes: sport.sessionNotes.isEmpty ? nil : sport.sessionNotes,
          p_perceived_intensity: perceived.rawValue   // si lo quieres opcional usa: perceivedOptional?.rawValue
        )

        _ = try await client
          .rpc("create_sport_workout_v1", params: RPCSportWrapper(p: payload))
          .execute()
      }

      dismiss()
    } catch {
      self.error = error.localizedDescription
    }
  }

  // MARK: Helpers

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
        .eq("is_public", value: true)           // 👈 firma correcta
        .eq("modality", value: "strength")      // 👈 firma correcta
        .order("name", ascending: true)
        .execute()

      catalog = try JSONDecoder().decode([Exercise].self, from: res.data)
    } catch {
      // silencio para no bloquear UI
    }
  }
}

// MARK: - UI Models

private enum WorkoutKind: String, CaseIterable, Identifiable {
  case strength, cardio, sport
  var id: String { rawValue }
}

private struct EditableExercise: Identifiable {
  let id = UUID()
  var exerciseId: Int64? = nil         // seleccionado desde catálogo
  var exerciseName: String = ""        // alias opcional
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

private struct EditableSet: Identifiable {
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

private struct CardioForm {
  var modality: String = "Run"
  var distanceKm: String = ""
  var durationSec: String = ""
  var avgHR: String = ""
  var maxHR: String = ""
  var avgPaceSecPerKm: String = ""
  var elevationGainM: String = ""
}

private struct SportForm {
  var sport: String = "Football"
  var durationMin: String = ""
  var matchResult: String = ""
  var sessionNotes: String = ""
}

// MARK: - RPC payloads

private struct RPCStrengthParams: Encodable {
  let p_user_id: UUID
  let p_items: [StrengthItem]
  let p_title: String?
  let p_started_at: String?
  let p_ended_at: String?
  let p_notes: String?
  let p_perceived_intensity: String?


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

private struct RPCCardioParams: Encodable {
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
  let p_perceived_intensity: String?   // 👈 NUEVO
}

private struct RPCSportParams: Encodable {
  let p_user_id: UUID
  let p_sport: String
  let p_title: String?
  let p_started_at: String
  let p_ended_at: String?
  let p_notes: String?
  let p_duration_min: Int?
  let p_match_result: String?
  let p_session_notes: String?
  let p_perceived_intensity: String?   // "easy|moderate|hard|max"
}

private struct RPCSportWrapper: Encodable {
  let p: RPCSportParams
}
