import SwiftUI
import Supabase

struct SharedRoutineFromChatView: View {
    let snapshot: RoutineShareSnapshot

    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @AppStorage("exerciseLanguage") private var exerciseLanguageRaw: String = ExerciseLanguage.spanish.rawValue

    @State private var catalog: [Exercise] = []
    @State private var loadingCatalog = true
    @State private var strengthFolders: [StrengthFolderPick] = []
    @State private var hyroxFolders: [HyroxFolderPick] = []
    @State private var showSaveSheet = false
    @State private var saveNameDraft = ""
    @State private var saveFolderId: Int64? = nil
    @State private var saveError: String?
    @State private var saveBusy = false
    @State private var decodeError: String?

    private var exerciseLanguage: ExerciseLanguage {
        ExerciseLanguage(rawValue: exerciseLanguageRaw) ?? .spanish
    }

    private var isStrength: Bool { snapshot.routine_kind == "strength" }
    private var isHyrox: Bool { snapshot.routine_kind == "hyrox" }

    private var viewerIsRoutineOwner: Bool {
        guard let owner = snapshot.owner_user_id, let me = app.userId else { return false }
        return owner == me
    }

    var body: some View {
        Group {
            if let decodeError {
                ContentUnavailableView(
                    String(localized: "Routine unavailable"),
                    systemImage: "exclamationmark.triangle",
                    description: Text(decodeError)
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        headerBlock
                        previewBlock
                        if !viewerIsRoutineOwner {
                            Button {
                                saveNameDraft = "Copy of \(snapshot.name)"
                                saveFolderId = nil
                                saveError = nil
                                showSaveSheet = true
                            } label: {
                                Text(String(localized: "Save as yours"))
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(loadingCatalog && isStrength)
                        }
                    }
                    .padding(16)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .gradientBG()
        .navigationTitle(snapshot.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadSideData()
        }
        .sheet(isPresented: $showSaveSheet) {
            NavigationStack {
                ScrollView {
                    SectionCard {
                        if let saveError {
                            Text(saveError)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        FieldRowPlain(String(localized: "Routine name")) {
                            TextField(String(localized: "Routine name"), text: $saveNameDraft)
                                .textFieldStyle(.plain)
                        }
                        if isStrength, !strengthFolders.isEmpty {
                            Divider()
                            FieldRowPlain(String(localized: "Folder")) {
                                Picker("", selection: $saveFolderId) {
                                    Text(String(localized: "No folder")).tag(Int64?.none)
                                    ForEach(strengthFolders) { f in
                                        Text(f.name).tag(Int64?.some(f.id))
                                    }
                                }
                                .labelsHidden()
                            }
                        } else if isHyrox, !hyroxFolders.isEmpty {
                            Divider()
                            FieldRowPlain(String(localized: "Folder")) {
                                Picker("", selection: $saveFolderId) {
                                    Text(String(localized: "No folder")).tag(Int64?.none)
                                    ForEach(hyroxFolders) { f in
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
                .navigationTitle(String(localized: "Save routine"))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(String(localized: "Cancel")) {
                            showSaveSheet = false
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(String(localized: "Save")) {
                            Task { await performSave() }
                        }
                        .disabled(saveBusy || saveNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }

    @ViewBuilder
    private var headerBlock: some View {
        HStack(alignment: .top, spacing: 12) {
            AvatarView(urlString: snapshot.owner_avatar_url)
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                if let u = snapshot.owner_username, !u.isEmpty {
                    Text("@\(u)")
                        .font(.subheadline.weight(.semibold))
                }
                Text(kindLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private var kindLabel: String {
        if isStrength { return String(localized: "Strength routine") }
        if isHyrox { return String(localized: "Hyrox routine") }
        return snapshot.routine_kind
    }

    @ViewBuilder
    private var previewBlock: some View {
        SectionCard {
            if isStrength, let detail = strengthDetail {
                let exName: (Int64) -> String = { id in
                    catalog.first(where: { $0.id == id })?.localizedName(for: exerciseLanguage) ?? "Exercise \(id)"
                }
                let built = editableExercisesFromStrengthTemplateDetail(detail, exerciseDisplayName: exName)
                if built.isEmpty {
                    Text(String(localized: "No exercises in this routine."))
                        .foregroundStyle(.secondary)
                } else {
                    StrengthRoutinePreviewExercisesList(exercises: built) { s in
                        strengthSetSummaryLine(s)
                    }
                }
            } else if isHyrox, let detail = hyroxDetail {
                let rows = (detail.hyrox_routine_exercises ?? []).sorted { $0.exercise_order < $1.exercise_order }
                if rows.isEmpty {
                    Text(String(localized: "No stations in this routine."))
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(rows.enumerated()), id: \.offset) { idx, w in
                            hyroxStationBlock(w)
                            if idx < rows.count - 1 {
                                Divider()
                            }
                        }
                    }
                }
            } else {
                Text(String(localized: "Could not read routine contents."))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func strengthSetSummaryLine(_ s: EditableSet) -> some View {
        let dropSummary: String? = {
            guard s.segments.count >= 2 else { return nil }
            return s.segments.map { seg in
                let r = seg.reps.map { String($0) } ?? "—"
                let w = seg.weightKg.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "—" : seg.weightKg
                return "\(r)×\(w)"
            }.joined(separator: " → ")
        }()
        let repsStr = s.reps.map { String($0) } ?? "—"
        let kgStr = s.weightKg.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "—" : s.weightKg
        let rpeStr = s.rpe.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "—" : s.rpe
        let restStr = s.restSec.map { "\($0) s" } ?? "—"
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Set \(s.setNumber)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .leading)
            Text(
                dropSummary
                    ?? "\(repsStr) \(String(localized: "reps")) · \(kgStr) \(String(localized: "kg")) · \(String(localized: "RPE")) \(rpeStr) · \(String(localized: "Rest")) \(restStr)"
            )
                .font(.caption)
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
        if !s.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Text(s.notes)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.leading, 52)
        }
    }

    @ViewBuilder
    private func hyroxStationBlock(_ w: HyroxRoutineExerciseWire) -> some View {
        let title = HyroxExerciseFormatting.label(
            code: w.exercise_code,
            displayName: w.exercise_display_name,
            notes: w.notes
        )
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            let lines = hyroxStationDetailLines(w)
            if lines.isEmpty {
                Text(String(localized: "No parameters"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func hyroxStationDetailLines(_ w: HyroxRoutineExerciseWire) -> [String] {
        var out: [String] = []
        if let d = w.distance_m, d > 0 {
            out.append(
                String.localizedStringWithFormat(
                    String(localized: "hyrox_station_distance_m_format"),
                    d
                )
            )
        }
        if let r = w.reps, r > 0 {
            out.append(
                String.localizedStringWithFormat(
                    String(localized: "hyrox_station_reps_format"),
                    r
                )
            )
        }
        if let kg = w.weight_kg, kg > 0 {
            let s = kg == floor(kg) ? "\(Int(kg))" : String(format: "%.1f", kg)
            out.append(
                String.localizedStringWithFormat(
                    String(localized: "hyrox_station_weight_kg_format"),
                    s
                )
            )
        }
        if let sec = w.duration_sec, sec > 0 {
            out.append(
                String.localizedStringWithFormat(
                    String(localized: "hyrox_station_duration_sec_format"),
                    sec
                )
            )
        }
        if let h = w.height_cm, h > 0 {
            out.append(
                String.localizedStringWithFormat(
                    String(localized: "hyrox_station_height_cm_format"),
                    h
                )
            )
        }
        if let imp = w.implement_count, imp > 0 {
            out.append(
                String.localizedStringWithFormat(
                    String(localized: "hyrox_station_implements_format"),
                    imp
                )
            )
        }
        if let n = w.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty {
            out.append(
                String.localizedStringWithFormat(
                    String(localized: "hyrox_station_notes_format"),
                    n
                )
            )
        }
        return out
    }

    private var strengthDetail: StrengthTemplateDetailWire? {
        guard isStrength,
              let data = snapshot.detail_json.data(using: .utf8) else { return nil }
        return try? JSONDecoder.supabase().decode(StrengthTemplateDetailWire.self, from: data)
    }

    private var hyroxDetail: HyroxRoutineDetailWire? {
        guard isHyrox,
              let data = snapshot.detail_json.data(using: .utf8) else { return nil }
        return try? JSONDecoder.supabase().decode(HyroxRoutineDetailWire.self, from: data)
    }

    private func loadSideData() async {
        guard decodeError == nil else { return }
        if isStrength {
            guard strengthDetail != nil else {
                await MainActor.run {
                    decodeError = String(localized: "Could not read routine contents.")
                    loadingCatalog = false
                }
                return
            }
            let ids = (strengthDetail?.strength_routine_exercises ?? []).map(\.exercise_id)
            await loadCatalog(exerciseIds: ids)
            await loadStrengthFolders()
        } else if isHyrox {
            guard hyroxDetail != nil else {
                await MainActor.run {
                    decodeError = String(localized: "Could not read routine contents.")
                    loadingCatalog = false
                }
                return
            }
            await MainActor.run { loadingCatalog = false }
            await loadHyroxFolders()
        } else {
            await MainActor.run {
                decodeError = String(localized: "Unknown routine type.")
                loadingCatalog = false
            }
        }
    }

    private func loadCatalog(exerciseIds: [Int64]) async {
        let unique = Array(Set(exerciseIds))
        guard !unique.isEmpty else {
            await MainActor.run { loadingCatalog = false }
            return
        }
        do {
            let client = SupabaseManager.shared.client
            let res = try await client
                .from("exercises")
                .select("id,name,name_es,name_en,category,modality,muscle_primary,equipment")
                .in("id", values: unique.map { Int($0) })
                .limit(unique.count + 1)
                .execute()
            let rows = try JSONDecoder.supabase().decode([Exercise].self, from: res.data)
            await MainActor.run {
                catalog = rows
                loadingCatalog = false
            }
        } catch {
            await MainActor.run { loadingCatalog = false }
        }
    }

    private func loadStrengthFolders() async {
        do {
            let client = SupabaseManager.shared.client
            let session = try await client.auth.session
            let res = try await client
                .from("strength_routine_folders")
                .select("id,name,sort_order")
                .eq("user_id", value: session.user.id)
                .order("sort_order", ascending: true)
                .order("name", ascending: true)
                .execute()
            let rows = try JSONDecoder.supabase().decode([StrengthFolderPick].self, from: res.data)
            await MainActor.run { strengthFolders = rows }
        } catch {
            await MainActor.run { strengthFolders = [] }
        }
    }

    private func loadHyroxFolders() async {
        do {
            let client = SupabaseManager.shared.client
            let session = try await client.auth.session
            let res = try await client
                .from("hyrox_routine_folders")
                .select("id,name,sort_order")
                .eq("user_id", value: session.user.id)
                .order("sort_order", ascending: true)
                .order("name", ascending: true)
                .execute()
            let rows = try JSONDecoder.supabase().decode([HyroxFolderPick].self, from: res.data)
            await MainActor.run { hyroxFolders = rows }
        } catch {
            await MainActor.run { hyroxFolders = [] }
        }
    }

    private func performSave() async {
        let name = saveNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            await MainActor.run { saveError = String(localized: "Enter a routine name.") }
            return
        }
        await MainActor.run {
            saveBusy = true
            saveError = nil
        }
        defer { Task { await MainActor.run { saveBusy = false } } }
        do {
            let client = SupabaseManager.shared.client
            let session = try await client.auth.session
            if isStrength, let detail = strengthDetail {
                let taken = try await StrengthRoutineNameValidator.isRoutineNameTaken(
                    client: client,
                    userId: session.user.id,
                    trimmedName: name,
                    excludingRoutineId: nil,
                    folderId: saveFolderId
                )
                if taken {
                    await MainActor.run {
                        saveError = String(localized: "A routine with this name already exists in this folder.")
                    }
                    return
                }
                let exName: (Int64) -> String = { id in
                    catalog.first(where: { $0.id == id })?.localizedName(for: exerciseLanguage) ?? "Exercise \(id)"
                }
                let built = editableExercisesFromStrengthTemplateDetail(detail, exerciseDisplayName: exName)
                guard !built.isEmpty else {
                    await MainActor.run {
                        saveError = String(localized: "This routine has no exercises to copy.")
                    }
                    return
                }
                _ = try await StrengthRoutineRemotePersistence.insertStrengthRoutineTemplate(
                    client: client,
                    userId: session.user.id,
                    name: name,
                    folderId: saveFolderId,
                    exercises: built,
                    replaceRoutineId: nil
                )
            } else if isHyrox, let detail = hyroxDetail {
                let taken = try await HyroxRoutineNameValidator.isRoutineNameTaken(
                    client: client,
                    userId: session.user.id,
                    trimmedName: name,
                    excludingRoutineId: nil,
                    folderId: saveFolderId
                )
                if taken {
                    await MainActor.run {
                        saveError = String(localized: "A routine with this name already exists in this folder.")
                    }
                    return
                }
                let payload = hyroxApplyPayloadFromDetail(detail)
                guard !payload.exercises.isEmpty else {
                    await MainActor.run {
                        saveError = String(localized: "This routine has no exercises to copy.")
                    }
                    return
                }
                var sport = SportForm()
                sport.applyHyroxRoutineTemplate(payload)
                _ = try await insertHyroxRoutineTemplate(
                    client: client,
                    userId: session.user.id,
                    name: name,
                    folderId: saveFolderId,
                    sport: sport,
                    replaceRoutineId: nil
                )
            } else {
                await MainActor.run {
                    saveError = String(localized: "Could not read routine contents.")
                }
                return
            }
            await MainActor.run {
                showSaveSheet = false
                dismiss()
            }
        } catch {
            await MainActor.run { saveError = error.localizedDescription }
        }
    }
}

private struct StrengthFolderPick: Identifiable, Decodable {
    let id: Int64
    let name: String
    let sort_order: Int?
}

private struct HyroxFolderPick: Identifiable, Decodable {
    let id: Int64
    let name: String
    let sort_order: Int?
}
