import SwiftUI
import Supabase

struct HyroxRoutineTemplateProgramEditor: View {
    @Binding var sport: SportForm
    @Binding var statsExpanded: Bool
    @Binding var showClearAllConfirm: Bool
    @FocusState private var hyroxExerciseNameFocusedId: UUID?
    @State private var didLoadHyroxCustomDisplayNameSuggestions = false
    @State private var hyroxCustomDisplayNameSuggestionsFromDB: [String] = []

    var body: some View {
        Group {
            hyroxOptionalStatsDisclosureBlock
            hyroxExerciseProgramEditorStack
        }
    }

    private var hyroxOptionalStatsDisclosureBlock: some View {
        Group {
            Divider()
            DisclosureGroup(isExpanded: $statsExpanded) {
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
                        showClearAllConfirm = true
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
        .task(id: sport.sport.rawValue) {
            guard sport.sport == .hyrox else { return }
            await loadHyroxCustomDisplayNameSuggestionsFromServer()
        }
        .alert("Clear all Hyrox stations?", isPresented: $showClearAllConfirm) {
            Button("Clear all", role: .destructive) {
                sport.hyExercises = []
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes every station from your Hyrox program.")
        }
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
}

struct EditSavedHyroxRoutineSheet: View {
    let routineId: Int64
    let routineName: String
    let onClose: () -> Void
    let onSaved: () -> Void

    @State private var sport = SportForm()
    @State private var hyroxStatsExpanded = false
    @State private var showClearAllHyroxExercisesConfirm = false
    @State private var loading = true
    @State private var saving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.clear.gradientBG()
                Group {
                    if loading {
                        ProgressView("Loading routine…")
                    } else if sport.hyExercises.isEmpty {
                        VStack(spacing: 12) {
                            Text(errorMessage ?? "Unable to load this routine.")
                                .foregroundStyle(.red)
                                .font(.footnote)
                                .multilineTextAlignment(.center)
                            Button("Close") { onClose() }
                        }
                        .padding()
                    } else {
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
                                Text("Changes update the saved template only. Use Apply on the list to load it into your workout.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)

                                HyroxRoutineTemplateProgramEditor(
                                    sport: $sport,
                                    statsExpanded: $hyroxStatsExpanded,
                                    showClearAllConfirm: $showClearAllHyroxExercisesConfirm
                                )
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        }
                        .scrollIndicators(.visible)
                    }
                }
            }
            .navigationTitle(routineName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onClose() }
                        .disabled(saving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await saveTemplate() }
                    }
                    .fontWeight(.semibold)
                    .disabled(saving || loading || sport.hyExercises.isEmpty)
                }
            }
        }
        .task {
            await loadRoutine()
        }
    }

    private func loadRoutine() async {
        await MainActor.run {
            loading = true
            errorMessage = nil
        }
        defer {
            Task { await MainActor.run { loading = false } }
        }
        do {
            let client = SupabaseManager.shared.client
            let res = try await client
                .from("hyrox_routines")
                .select(hyroxRoutineDetailSelect())
                .eq("id", value: Int(routineId))
                .single()
                .execute()
            let detail = try JSONDecoder.supabase().decode(HyroxRoutineDetailWire.self, from: res.data)
            let payload = hyroxApplyPayloadFromDetail(detail)
            guard !payload.exercises.isEmpty else {
                await MainActor.run { errorMessage = "This routine has no exercises." }
                return
            }
            await MainActor.run {
                var next = SportForm()
                next.applyHyroxRoutineTemplate(payload)
                sport = next
                errorMessage = nil
            }
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
        }
    }

    private func saveTemplate() async {
        guard !sport.hyExercises.isEmpty else {
            await MainActor.run { errorMessage = "Add at least one station before saving." }
            return
        }
        await MainActor.run {
            saving = true
            errorMessage = nil
        }
        defer {
            Task { await MainActor.run { saving = false } }
        }
        do {
            let client = SupabaseManager.shared.client
            let session = try await client.auth.session
            var toSave = await MainActor.run { sport }
            for idx in toSave.hyExercises.indices {
                toSave.hyExercises[idx].exerciseOrder = idx + 1
            }
            _ = try await updateHyroxRoutineTemplateInPlace(
                client: client,
                userId: session.user.id,
                routineId: routineId,
                sport: toSave
            )
            await MainActor.run {
                onSaved()
            }
        } catch {
            await MainActor.run { errorMessage = hyroxRoutineUserFacingSaveError(error) }
        }
    }
}
