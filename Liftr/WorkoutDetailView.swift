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
  }
  struct ProfileRow: Decodable { let user_id: UUID; let username: String; let avatar_url: String? }
  struct ScoreRow: Decodable { let workout_id: Int; let score: Decimal }

  @State private var workout: WorkoutDetailRow?
  @State private var profile: ProfileRow?
  @State private var totalScore: Double?
  @State private var loading = false
  @State private var error: String?
  @State private var reloadKey = UUID()

  var body: some View {
    ScrollView {
      VStack(spacing: 14) {
        if let w = workout {
          ZStack {
            WorkoutCardBackground(kind: w.kind)
            VStack(alignment: .leading, spacing: 10) {
              HStack(alignment: .top, spacing: 10) {
                AvatarView(urlString: profile?.avatar_url)
                  .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 4) {
                  Text(profile.map { "@\($0.username)" } ?? "@user")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
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
                Spacer()
                Text(w.kind.capitalized)
                  .font(.caption2.weight(.semibold))
                  .padding(.vertical, 4).padding(.horizontal, 8)
                  .background(Capsule().fill(workoutTint(for: w.kind).opacity(0.15)))
                  .overlay(Capsule().stroke(Color.white.opacity(0.12)))
              }
            }
            .padding(16)
          }
          .clipShape(RoundedRectangle(cornerRadius: 16))
          .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.18)))
        }
        if let notes = workout?.notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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

          if let kind = workout?.kind {
            switch kind.lowercased() {
            case "strength":
              StrengthDetailBlock(workoutId: workoutId, reloadKey: reloadKey)
            case "cardio":
              CardioDetailBlock(workoutId: workoutId, reloadKey: reloadKey)
            case "sport":
              SportDetailBlock(workoutId: workoutId, reloadKey: reloadKey)
          default:
            EmptyView()
          }
        }
      }
      .padding(16)
    }
    .task { await load() }
    .onReceive(NotificationCenter.default.publisher(for: .workoutDidChange)) { note in
      if let id = note.object as? Int, id == workoutId {
        Task { await load() }
      }
    }
    .gradientBG()
    .safeAreaPadding(.top, 2)
    .navigationTitle(workout?.title ?? workout?.kind.capitalized ?? "Workout")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar(.visible, for: .navigationBar)
    .toolbarBackground(.visible, for: .navigationBar)
    .toolbar {
      if canEdit {
        ToolbarItem(placement: .topBarTrailing) {
          Menu {
            Button("Edit") { showEdit = true }
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
          } label: {
            Image(systemName: "ellipsis.circle")
          }
        }
      }
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
              reloadKey = UUID()
          }
        )
        .gradientBG()
        .presentationDetents(Set([.medium, .large]))
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
        startedAt: Date(),
        endedAt: nil,
        perceived: WorkoutIntensity(rawValue: base.perceived_intensity ?? "moderate") ?? .moderate
      )

      let decoder = JSONDecoder.supabase()

      switch base.kind.lowercased() {
      case "strength":
        do {
          let exRes = try await SupabaseManager.shared.client
            .from("workout_exercises")
            .select("id, exercise_id, order_index, notes, exercises(name)")
            .eq("workout_id", value: workoutId)
            .order("order_index", ascending: true)
            .execute()

          struct ExWire: Decodable {
            let id: Int
            let exercise_id: Int64
            let order_index: Int
            let notes: String?
            let exercises: ExName?
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
              exerciseName: ex.exercises?.name ?? "",
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

          var cf = CardioForm()
          cf.modality = r.modality
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
            sf.durationMin = r.duration_sec.map { "\($0/60)" } ?? ""
            sf.scoreFor = r.score_for.map(String.init) ?? ""
            sf.scoreAgainst = r.score_against.map(String.init) ?? ""
            sf.matchResult = MatchResult(rawValue: r.match_result ?? "") ?? .unfinished
            sf.matchScoreText = r.match_score_text ?? ""
            sf.location = r.location ?? ""
            sf.sessionNotes = r.notes ?? ""
            draft.sport = sf
        } catch { return nil }

      default: break
      }

      return draft
    }
}

private struct StrengthDetailBlock: View {
  let workoutId: Int
  let reloadKey: UUID

  private struct ExerciseRow: Decodable, Identifiable {
    let id: Int
    let exercise_id: Int
    let order_index: Int
    let notes: String?
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
            Text(ex.exercise_name ?? "Exercise #\(ex.exercise_id)")
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
      let exWire = try JSONDecoder.supabase().decode([ExWire].self, from: exQ.data)
      let exRows: [ExerciseRow] = exWire.map {
        .init(id: $0.id, exercise_id: $0.exercise_id, order_index: $0.order_index, notes: $0.notes, exercise_name: $0.exercises?.name)
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
    let modality: String
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

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Cardio").font(.headline)

      if let r = row {
        info("Modality", r.modality)
        if let d = r.distance_km { info("Distance", String(format: "%.2f km", NSDecimalNumber(decimal: d).doubleValue)) }
        if let s = r.duration_sec { info("Duration", durationString(Double(s))) }
        if let p = r.avg_pace_sec_per_km { info("Avg pace", paceString(Double(p))) }
        if let ah = r.avg_hr { info("Avg HR", "\(ah) bpm") }
        if let mh = r.max_hr { info("Max HR", "\(mh) bpm") }
        if let elev = r.elevation_gain_m { info("Elevation gain", "\(elev) m") }
        if let n = r.notes, !n.isEmpty { info("Notes", n) }
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
    
    private struct SportRow: Decodable {
      let sport: String
      let duration_sec: Int?
      let match_result: String?
      let score_for: Int?
      let score_against: Int?
      let match_score_text: String?
      let location: String?
      let notes: String?
    }

  @State private var row: SportRow?
  @State private var error: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Sport").font(.headline)

        if let r = row {
          info("Sport", r.sport.capitalized)
          if let s = r.duration_sec { info("Duration", durationString(Double(s))) }
          if let res = r.match_result, !res.isEmpty { info("Result", res.capitalized) }
          if let sf = r.score_for, let sa = r.score_against { info("Score", "\(sf) – \(sa)") }
          if let mst = r.match_score_text, !mst.isEmpty { info("Sets", mst) }
          if let loc = r.location, !loc.isEmpty { info("Location", loc) }
          if let n = r.notes, !n.isEmpty { info("Notes", n) }
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
      await MainActor.run { row = r }
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

  private func durationString(_ secondsDouble: Double) -> String {
    let s = max(0, Int(secondsDouble.rounded()))
    let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
    if h > 0 { return String(format: "%d:%02d:%02d", h, m, sec) }
    return String(format: "%d:%02d", m, sec)
  }
}
