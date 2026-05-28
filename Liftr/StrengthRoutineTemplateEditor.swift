import Foundation
import Supabase
import SwiftUI

extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}

struct StrengthTemplateDetailWire: Decodable {
    let id: Int64
    let name: String
    let strength_routine_exercises: [StrengthTemplateExerciseWire]?
}

struct StrengthTemplateExerciseWire: Decodable {
    let exercise_id: Int64
    let order_index: Int
    let superset_group_id: UUID?
    let superset_position: Int?
    let notes: String?
    let custom_name: String?
    let strength_routine_sets: [StrengthTemplateSetWire]?
}

struct StrengthTemplateSetWire: Decodable {
    let set_number: Int
    let reps: Int?
    let weight_kg: Double?
    let rpe: Double?
    let rest_sec: Int?
    let notes: String?
    let weight_segments: [StrengthWeightSegWire]?
}

func strengthTemplateDetailSelect() -> String {
    "id,name,strength_routine_exercises(exercise_id,order_index,superset_group_id,superset_position,notes,custom_name,strength_routine_sets(set_number,reps,weight_kg,rpe,rest_sec,notes,weight_segments))"
}

func strengthTemplateDetailSelectLegacy() -> String {
    "id,name,strength_routine_exercises(exercise_id,order_index,notes,custom_name,strength_routine_sets(set_number,reps,weight_kg,rpe,rest_sec,notes,weight_segments))"
}

func strengthRoutineSupersetColumnsUnavailable(_ error: Error) -> Bool {
    let text = error.localizedDescription.lowercased()
    return text.contains("superset_group_id") || text.contains("superset_position")
}

func fetchStrengthRoutineTemplateDetailData(
    client: SupabaseClient,
    routineId: Int64
) async throws -> Data {
    do {
        let res = try await client
            .from("strength_routines")
            .select(strengthTemplateDetailSelect())
            .eq("id", value: Int(routineId))
            .single()
            .execute()
        return res.data
    } catch {
        guard strengthRoutineSupersetColumnsUnavailable(error) else { throw error }
        let res = try await client
            .from("strength_routines")
            .select(strengthTemplateDetailSelectLegacy())
            .eq("id", value: Int(routineId))
            .single()
            .execute()
        return res.data
    }
}

func fetchStrengthRoutineTemplateDetail(
    client: SupabaseClient,
    routineId: Int64
) async throws -> StrengthTemplateDetailWire {
    let data = try await fetchStrengthRoutineTemplateDetailData(client: client, routineId: routineId)
    return try JSONDecoder.supabase().decode(StrengthTemplateDetailWire.self, from: data)
}

func editableExercisesFromStrengthTemplateDetail(
    _ detail: StrengthTemplateDetailWire,
    exerciseDisplayName: (Int64) -> String
) -> [EditableExercise] {
    let exs = (detail.strength_routine_exercises ?? []).sorted { $0.order_index < $1.order_index }
    let mapped = exs.map { ex in
        let setsSorted = (ex.strength_routine_sets ?? []).sorted { $0.set_number < $1.set_number }
        let mappedSets: [EditableSet] = setsSorted.enumerated().map { idx, s in
            let segDraft = (s.weight_segments ?? []).asEditorSegmentsIfDropSet()
            return EditableSet(
                setNumber: s.set_number,
                orderIndex: idx + 1,
                reps: s.reps,
                weightKg: s.weight_kg.map { String($0) } ?? "",
                rpe: s.rpe.map { String($0) } ?? "",
                restSec: s.rest_sec,
                notes: s.notes ?? "",
                segments: segDraft
            )
        }
        let fallbackSets = mappedSets.isEmpty ? [EditableSet(setNumber: 1)] : mappedSets
        let displayName: String = {
            if let cn = ex.custom_name, !cn.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return cn }
            return exerciseDisplayName(ex.exercise_id)
        }()
        return EditableExercise(
            exerciseId: ex.exercise_id,
            exerciseName: displayName,
            orderIndex: ex.order_index,
            supersetGroupId: ex.superset_group_id,
            supersetPosition: ex.superset_position,
            notes: ex.notes ?? "",
            sets: fallbackSets
        )
    }
    return compactSupersetMetadata(mapped)
}

struct StrengthRoutinePreviewBlock: Identifiable {
    let id: String
    let isSuperset: Bool
    let exercises: [EditableExercise]
}

func strengthRoutinePreviewBlocks(from exercises: [EditableExercise]) -> [StrengthRoutinePreviewBlock] {
    var blocks: [StrengthRoutinePreviewBlock] = []
    let ordered = exercises.sorted { $0.orderIndex < $1.orderIndex }
    var idx = 0
    while idx < ordered.count {
        let current = ordered[idx]
        guard let groupId = current.supersetGroupId else {
            blocks.append(StrengthRoutinePreviewBlock(id: "exercise-\(idx)", isSuperset: false, exercises: [current]))
            idx += 1
            continue
        }
        var group: [EditableExercise] = [current]
        var nextIdx = idx + 1
        while nextIdx < ordered.count, ordered[nextIdx].supersetGroupId == groupId {
            group.append(ordered[nextIdx])
            nextIdx += 1
        }
        if group.count > 1 {
            let sortedGroup = group.sorted {
                let lp = $0.supersetPosition ?? Int.max
                let rp = $1.supersetPosition ?? Int.max
                if lp != rp { return lp < rp }
                return $0.orderIndex < $1.orderIndex
            }
            blocks.append(
                StrengthRoutinePreviewBlock(
                    id: "superset-\(groupId.uuidString)",
                    isSuperset: true,
                    exercises: sortedGroup
                )
            )
        } else {
            blocks.append(StrengthRoutinePreviewBlock(id: "exercise-\(idx)", isSuperset: false, exercises: [current]))
        }
        idx = nextIdx
    }
    return blocks
}

private func strengthRoutinePreviewMemberLabel(position: Int, memberCount: Int) -> String {
    String.localizedStringWithFormat(
        String(localized: "strength_preview_exercise_of_format"),
        position,
        memberCount
    )
}

struct StrengthRoutinePreviewExercisesList<SetLine: View>: View {
    let exercises: [EditableExercise]
    @ViewBuilder let setLine: (EditableSet) -> SetLine

    var body: some View {
        let blocks = strengthRoutinePreviewBlocks(from: exercises)
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(blocks.enumerated()), id: \.element.id) { blockIdx, block in
                if block.isSuperset {
                    strengthRoutinePreviewSupersetCard(block)
                } else if let ex = block.exercises.first {
                    strengthRoutinePreviewSingleExercise(ex)
                }
                if blockIdx < blocks.count - 1 {
                    Divider()
                }
            }
        }
    }

    @ViewBuilder
    private func strengthRoutinePreviewSupersetCard(_ block: StrengthRoutinePreviewBlock) -> some View {
        let memberCount = block.exercises.count
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "link")
                    .font(.caption.weight(.semibold))
                Text(String(localized: "Superserie"))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(
                    String.localizedStringWithFormat(
                        String(localized: "strength_preview_exercise_count_format"),
                        memberCount
                    )
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.blue)

            ForEach(Array(block.exercises.enumerated()), id: \.offset) { offset, ex in
                let position = ex.supersetPosition ?? (offset + 1)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(strengthRoutinePreviewMemberLabel(position: position, memberCount: memberCount))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.blue)
                        Text(ex.exerciseName)
                            .font(.subheadline.weight(.semibold))
                        Spacer(minLength: 0)
                    }
                    if !ex.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(ex.notes)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(ex.sets.sorted { $0.setNumber < $1.setNumber }) { s in
                        setLine(s)
                    }
                }
                .padding(10)
                .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.blue.opacity(0.25), lineWidth: 1))
    }

    @ViewBuilder
    private func strengthRoutinePreviewSingleExercise(_ ex: EditableExercise) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(ex.exerciseName)
                .font(.subheadline.weight(.semibold))
            if !ex.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(ex.notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(ex.sets.sorted { $0.setNumber < $1.setNumber }) { s in
                setLine(s)
            }
        }
    }
}

struct StrengthRoutineExercisesEditorBlock: View {
    @Binding var exercises: [EditableExercise]
    let laneIndex: Int
    let headerTitle: String?
    @Binding var pickerHandle: PickerHandle?
    @Binding var confirmRemoveStrengthExercise: (lane: Int, index: Int)?
    @Binding var recentlyAddedExerciseId: UUID?
    let catalog: [Exercise]
    let loadingCatalog: Bool
    let exerciseLabel: (EditableExercise) -> String
    let exerciseSelected: (EditableExercise) -> Bool
    let onRequestClearAll: () -> Void
    let onSuggest: () -> Void
    var showSuggestQuickAction: Bool = true

    var body: some View {
        SectionCard {
            if let headerTitle {
                Text(headerTitle)
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Divider().padding(.vertical, 4)
            }

            if showSuggestQuickAction {
                Text("QUICK ACTIONS")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button(action: onSuggest) {
                    HStack(spacing: 10) {
                        Image(systemName: "sparkles")
                            .imageScale(.medium)
                        Text("Suggest next session")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .foregroundStyle(.blue)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(loadingCatalog)
                .padding(.vertical, 4)

                Divider().padding(.vertical, 6)
            }

            Text("LIFTS")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 2)

            Text("Use the arrows on each exercise to change order.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, exercises.count > 1 ? 2 : 4)

            if exercises.count > 1 {
                HStack {
                    Spacer(minLength: 0)
                    Button("Clear all", role: .destructive) {
                        onRequestClearAll()
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Clear all exercises")
                }
                .padding(.bottom, 2)
            }

            VStack(spacing: 12) {
                ForEach(Array(exercises.enumerated()), id: \.element.id) { i, _ in
                    exerciseEditorBlock(index: i)
                }
            }

            Divider().padding(.vertical, 6)
            Button {
                let nextOrder = (exercises.last?.orderIndex ?? 0) + 1
                var new = EditableExercise()
                new.orderIndex = nextOrder
                exercises.append(new)
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
    }

    @ViewBuilder
    private func exerciseEditorBlock(index i: Int) -> some View {
        VStack(spacing: 0) {
            FieldRowPlain("Exercise") {
                Button {
                    pickerHandle = PickerHandle(id: exercises[i].id, strengthLaneIndex: laneIndex)
                } label: {
                    HStack {
                        Image(systemName: "list.bullet.rectangle.portrait")
                        Text(exerciseLabel(exercises[i]))
                            .foregroundStyle(exerciseSelected(exercises[i]) ? .primary : .secondary)
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
                TextField("Exercise name (optional)", text: nameBinding(i))
                    .textFieldStyle(.plain)
            }

            Divider()

            FieldRowNotes(
                "Notes",
                text: notesBinding(i),
                placeholder: "Notes (exercise)",
                lineRange: 2...8
            )

            ForEach(exercises[i].sets.indices, id: \.self) { s in
                Divider()
                StrengthSetRowEditor(
                    lineOrdinal: s + 1,
                    setNumber: setNumberBinding(i, s),
                    reps: repsBinding(i, s),
                    weightKg: weightBinding(i, s),
                    rpe: rpeBinding(i, s),
                    restSec: restBinding(i, s),
                    segments: segmentsBinding(i, s),
                    showDelete: exercises[i].sets.count > 1,
                    showReorder: exercises[i].sets.count > 1,
                    canMoveUp: s > 0,
                    canMoveDown: s < exercises[i].sets.count - 1,
                    onMoveUp: { moveSet(exerciseIndex: i, setIndex: s, direction: -1) },
                    onMoveDown: { moveSet(exerciseIndex: i, setIndex: s, direction: 1) },
                    onDelete: { removeSet(exerciseIndex: i, setIndex: s) }
                )
            }

            Divider().padding(.vertical, 4)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Button {
                        appendSet(exerciseIndex: i)
                    } label: { Label("Add set", systemImage: "plus.circle") }
                        .buttonStyle(.borderless)

                    Spacer()

                    if exercises.count > 1 {
                        HStack(spacing: 2) {
                            Button {
                                moveExercise(from: i, direction: -1)
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
                                moveExercise(from: i, direction: 1)
                            } label: {
                                Image(systemName: "chevron.down")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(width: 36, height: 32)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(i == exercises.count - 1)
                            .opacity(i == exercises.count - 1 ? 0.35 : 1)
                        }
                        .foregroundStyle(.secondary)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Reorder exercise")
                    }

                    if exercises.count > 1 {
                        Button(role: .destructive) {
                            confirmRemoveStrengthExercise = (laneIndex, i)
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
                if exercises.count > 1 {
                    supersetControls(for: i)
                }
                Text("Next prescription row: #\(exercises[i].sets.count + 1)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.07))
                if exercises[i].id == recentlyAddedExerciseId {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.yellow.opacity(0.2))
                }
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.white.opacity(0.16), lineWidth: 0.8)
        )
        .animation(.easeInOut(duration: 0.6), value: recentlyAddedExerciseId)
    }

    @ViewBuilder
    private func supersetControls(for index: Int) -> some View {
        if let exercise = exercises[safe: index], let groupId = exercise.supersetGroupId {
            HStack(spacing: 8) {
                Text("Superserie")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("Group \(supersetGroupDisplayNumber(groupId, in: exercises)) · \(exercise.supersetPosition ?? 1)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)

                Spacer(minLength: 8)

                if canAddNextToSuperset(groupId: groupId) {
                    Button("Add next") {
                        addNextExerciseToSuperset(groupId: groupId)
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.borderless)
                }

                Button("Remove") {
                    removeExerciseFromSuperset(index)
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.borderless)
                .foregroundStyle(.red)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        } else {
            HStack(spacing: 8) {
                Text("Superserie")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Button {
                    startSuperset(at: index)
                } label: {
                    Label("Superset with next", systemImage: "link.badge.plus")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderless)
                .disabled(!canStartSuperset(at: index))
                .opacity(canStartSuperset(at: index) ? 1 : 0.45)
            }
        }
    }

    private func moveExercise(from index: Int, direction: Int) {
        let newIndex = index + direction
        guard exercises.indices.contains(index), exercises.indices.contains(newIndex) else { return }
        var next = exercises
        next.swapAt(index, newIndex)
        for idx in next.indices {
            next[idx].orderIndex = idx + 1
        }
        exercises = compactSupersetMetadata(next)
    }

    private func startSuperset(at index: Int) {
        guard canStartSuperset(at: index) else { return }
        var next = exercises
        let groupId = next[index].supersetGroupId ?? next[index + 1].supersetGroupId ?? UUID()
        next[index].supersetGroupId = groupId
        next[index + 1].supersetGroupId = groupId
        exercises = compactSupersetMetadata(next)
    }

    private func addNextExerciseToSuperset(groupId: UUID) {
        guard let nextIndex = nextExerciseIndexAfterSuperset(groupId: groupId) else { return }
        var next = exercises
        next[nextIndex].supersetGroupId = groupId
        exercises = compactSupersetMetadata(next)
    }

    private func removeExerciseFromSuperset(_ index: Int) {
        guard exercises.indices.contains(index) else { return }
        var next = exercises
        next[index].supersetGroupId = nil
        next[index].supersetPosition = nil
        exercises = compactSupersetMetadata(next)
    }

    private func canStartSuperset(at index: Int) -> Bool {
        guard exercises.indices.contains(index),
              exercises.indices.contains(index + 1)
        else { return false }
        return exerciseSelected(exercises[index]) && exerciseSelected(exercises[index + 1])
    }

    private func canAddNextToSuperset(groupId: UUID) -> Bool {
        guard let nextIndex = nextExerciseIndexAfterSuperset(groupId: groupId) else { return false }
        return exerciseSelected(exercises[nextIndex])
    }

    private func nextExerciseIndexAfterSuperset(groupId: UUID) -> Int? {
        let groupIndices = exercises.indices.filter { exercises[$0].supersetGroupId == groupId }
        guard let lastGroupIndex = groupIndices.max() else { return nil }
        let nextIndex = lastGroupIndex + 1
        guard exercises.indices.contains(nextIndex),
              exercises[nextIndex].supersetGroupId != groupId
        else { return nil }
        return nextIndex
    }

    private func replaceExercise(_ index: Int, _ mutate: (inout EditableExercise) -> Void) {
        var copy = exercises
        guard copy.indices.contains(index) else { return }
        mutate(&copy[index])
        exercises = copy
    }

    private func nameBinding(_ i: Int) -> Binding<String> {
        Binding(
            get: { exercises[safe: i]?.exerciseName ?? "" },
            set: { nv in replaceExercise(i) { $0.exerciseName = nv } }
        )
    }

    private func notesBinding(_ i: Int) -> Binding<String> {
        Binding(
            get: { exercises[safe: i]?.notes ?? "" },
            set: { nv in replaceExercise(i) { $0.notes = nv } }
        )
    }

    private func setNumberBinding(_ i: Int, _ s: Int) -> Binding<Int> {
        Binding(
            get: { exercises[safe: i]?.sets[safe: s]?.setNumber ?? 1 },
            set: { newVal in
                replaceExercise(i) { ex in
                    guard ex.sets.indices.contains(s) else { return }
                    ex.sets[s].setNumber = newVal
                }
            }
        )
    }

    private func repsBinding(_ i: Int, _ s: Int) -> Binding<Int?> {
        Binding(
            get: { exercises[safe: i]?.sets[safe: s]?.reps },
            set: { newVal in
                replaceExercise(i) { ex in
                    guard ex.sets.indices.contains(s) else { return }
                    ex.sets[s].reps = newVal
                }
            }
        )
    }

    private func weightBinding(_ i: Int, _ s: Int) -> Binding<String> {
        Binding(
            get: { exercises[safe: i]?.sets[safe: s]?.weightKg ?? "" },
            set: { newVal in
                replaceExercise(i) { ex in
                    guard ex.sets.indices.contains(s) else { return }
                    ex.sets[s].weightKg = newVal
                }
            }
        )
    }

    private func rpeBinding(_ i: Int, _ s: Int) -> Binding<String> {
        Binding(
            get: { exercises[safe: i]?.sets[safe: s]?.rpe ?? "" },
            set: { newVal in
                replaceExercise(i) { ex in
                    guard ex.sets.indices.contains(s) else { return }
                    ex.sets[s].rpe = newVal
                }
            }
        )
    }

    private func restBinding(_ i: Int, _ s: Int) -> Binding<Int?> {
        Binding(
            get: { exercises[safe: i]?.sets[safe: s]?.restSec },
            set: { newVal in
                replaceExercise(i) { ex in
                    guard ex.sets.indices.contains(s) else { return }
                    ex.sets[s].restSec = newVal
                }
            }
        )
    }

    private func segmentsBinding(_ i: Int, _ s: Int) -> Binding<[StrengthEditorSegment]> {
        Binding(
            get: { exercises[safe: i]?.sets[safe: s]?.segments ?? [] },
            set: { newVal in
                replaceExercise(i) { ex in
                    guard ex.sets.indices.contains(s) else { return }
                    ex.sets[s].segments = newVal
                }
            }
        )
    }

    private func appendSet(exerciseIndex i: Int) {
        replaceExercise(i) { ex in
            ex.sets.append(EditableSet(setNumber: 1, orderIndex: ex.sets.count + 1))
        }
    }

    private func removeSet(exerciseIndex i: Int, setIndex s: Int) {
        replaceExercise(i) { ex in
            guard ex.sets.indices.contains(s) else { return }
            ex.sets.remove(at: s)
            renumberSetOrder(&ex)
        }
    }

    private func moveSet(exerciseIndex i: Int, setIndex s: Int, direction: Int) {
        replaceExercise(i) { ex in
            let newIndex = s + direction
            guard ex.sets.indices.contains(s), ex.sets.indices.contains(newIndex) else { return }
            ex.sets.swapAt(s, newIndex)
            renumberSetOrder(&ex)
        }
    }

    private func renumberSetOrder(_ ex: inout EditableExercise) {
        for idx in ex.sets.indices {
            ex.sets[idx].orderIndex = idx + 1
        }
    }
}

struct EditSavedStrengthRoutineSheet: View {
    let routineId: Int64
    let routineName: String
    let catalog: [Exercise]
    let loadingCatalog: Bool
    let exerciseLanguage: ExerciseLanguage
    let exerciseDisplayName: (Int64) -> String
    let onClose: () -> Void
    let onSaved: () -> Void

    @State private var exercises: [EditableExercise] = []
    @State private var loading = true
    @State private var saving = false
    @State private var errorMessage: String?
    @State private var pickerHandle: PickerHandle? = nil
    @State private var confirmRemoveStrengthExercise: (lane: Int, index: Int)? = nil
    @State private var showClearAllConfirm = false
    @State private var recentlyAddedExerciseId: UUID? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                Color.clear.gradientBG()
                Group {
                    if loading {
                        ProgressView("Loading routine…")
                    } else if exercises.isEmpty {
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

                                StrengthRoutineExercisesEditorBlock(
                                    exercises: $exercises,
                                    laneIndex: 0,
                                    headerTitle: nil,
                                    pickerHandle: $pickerHandle,
                                    confirmRemoveStrengthExercise: $confirmRemoveStrengthExercise,
                                    recentlyAddedExerciseId: $recentlyAddedExerciseId,
                                    catalog: catalog,
                                    loadingCatalog: loadingCatalog,
                                    exerciseLabel: { labelFor($0) },
                                    exerciseSelected: { $0.exerciseId != nil },
                                    onRequestClearAll: { showClearAllConfirm = true },
                                    onSuggest: {},
                                    showSuggestQuickAction: false
                                )
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        }
                        .scrollIndicators(.visible)
                    }
                }
            }
            .navigationTitle("Edit routine")
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
                    .disabled(saving || loading || exercises.isEmpty)
                }
            }
        }
        .task {
            await loadRoutine()
        }
        .sheet(item: $pickerHandle) { handle in
            routineExercisePickerSheet(for: handle)
        }
        .alert(
            "Are you sure you want to remove the exercise?",
            isPresented: removeExerciseAlertBinding
        ) {
            Button("Remove", role: .destructive) {
                if let req = confirmRemoveStrengthExercise, exercises.indices.contains(req.index) {
                    exercises.remove(at: req.index)
                    exercises = compactSupersetMetadata(exercises)
                }
                confirmRemoveStrengthExercise = nil
            }
            Button("Cancel", role: .cancel) {
                confirmRemoveStrengthExercise = nil
            }
        }
        .alert("Clear all exercises?", isPresented: $showClearAllConfirm) {
            Button("Clear all", role: .destructive) {
                exercises = [EditableExercise()]
                recentlyAddedExerciseId = nil
                confirmRemoveStrengthExercise = nil
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes every exercise in this list and leaves one empty row.")
        }
    }

    private var removeExerciseAlertBinding: Binding<Bool> {
        Binding(
            get: { confirmRemoveStrengthExercise != nil },
            set: { newVal in
                if !newVal { confirmRemoveStrengthExercise = nil }
            }
        )
    }

    private func labelFor(_ ex: EditableExercise) -> String {
        if let exid = ex.exerciseId,
           let found = catalog.first(where: { $0.id == exid }) {
            return found.localizedName(for: exerciseLanguage)
        }
        let trimmed = ex.exerciseName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return catalog.isEmpty ? "Loading exercises…" : "Choose exercise"
    }

    @ViewBuilder
    private func routineExercisePickerSheet(for handle: PickerHandle) -> some View {
        if let idx = exercises.firstIndex(where: { $0.id == handle.id }) {
            ExercisePickerSheet(
                all: catalog,
                selected: Binding(
                    get: {
                        guard idx < exercises.count, let exid = exercises[idx].exerciseId else { return nil }
                        return catalog.first(where: { $0.id == exid })
                    },
                    set: { picked in
                        guard idx < exercises.count else { return }
                        exercises[idx].exerciseId = picked?.id
                        if let ex = picked {
                            exercises[idx].exerciseName = ex.localizedName(for: exerciseLanguage)
                        } else {
                            exercises[idx].exerciseName = ""
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
            let detail = try await fetchStrengthRoutineTemplateDetail(client: client, routineId: routineId)
            let built = editableExercisesFromStrengthTemplateDetail(detail, exerciseDisplayName: exerciseDisplayName)
            guard !built.isEmpty else {
                await MainActor.run { errorMessage = "This routine has no exercises." }
                return
            }
            await MainActor.run {
                exercises = built
                errorMessage = nil
            }
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
        }
    }

    private func saveTemplate() async {
        if exercises.contains(where: { $0.exerciseId == nil }) {
            await MainActor.run { errorMessage = "Choose a movement for each exercise before saving." }
            return
        }
        guard !exercises.isEmpty else {
            await MainActor.run { errorMessage = "Add at least one exercise." }
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
            let toSave = await MainActor.run {
                compactSupersetMetadata(exercises)
            }
            try await applyStrengthRoutinePrescriptionUpdate(
                client: client,
                userId: session.user.id,
                routineId: routineId,
                exercises: toSave
            )
            await MainActor.run {
                onSaved()
            }
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
        }
    }
}
