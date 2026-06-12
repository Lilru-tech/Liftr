import CryptoKit
import Foundation
import Supabase
import SwiftUI

struct StrengthWeightSegment: Equatable {
    let reps: Int
    let weightKg: Double
}

struct StrengthProgramItem: Equatable {
    var exerciseId: Int64
    var orderIndex: Int
    var notes: String?
    var customName: String?
    var supersetGroupId: UUID?
    var supersetPosition: Int?
    var sets: [StrengthProgramSet]

    init(
        exerciseId: Int64,
        orderIndex: Int,
        notes: String?,
        customName: String?,
        supersetGroupId: UUID? = nil,
        supersetPosition: Int? = nil,
        sets: [StrengthProgramSet]
    ) {
        self.exerciseId = exerciseId
        self.orderIndex = orderIndex
        self.notes = notes
        self.customName = customName
        self.supersetGroupId = supersetGroupId
        self.supersetPosition = supersetPosition
        self.sets = sets
    }

    init?(from editable: EditableExercise) {
        guard let item = editable.toStrengthItem() else { return nil }
        self.init(
            exerciseId: item.exercise_id,
            orderIndex: item.order_index,
            notes: item.notes,
            customName: item.custom_name,
            supersetGroupId: editable.supersetGroupId,
            supersetPosition: editable.supersetPosition,
            sets: item.sets.map { StrengthProgramSet(from: $0) }
        )
    }
}

struct StrengthProgramSet: Equatable {
    var setNumber: Int
    var rowOrder: Int
    var reps: Int?
    var weightKg: Double?
    var rpe: Double?
    var restSec: Int?
    var notes: String?
    var weightSegments: [StrengthWeightSegment]?

    init(
        setNumber: Int,
        rowOrder: Int? = nil,
        reps: Int?,
        weightKg: Double?,
        rpe: Double?,
        restSec: Int?,
        notes: String?,
        weightSegments: [StrengthWeightSegment]? = nil
    ) {
        self.setNumber = setNumber
        self.rowOrder = rowOrder ?? setNumber
        self.reps = reps
        self.weightKg = weightKg
        self.rpe = rpe
        self.restSec = restSec
        self.notes = notes
        self.weightSegments = weightSegments
    }

    fileprivate init(from s: RPCStrengthParams.StrengthItem.StrengthSet) {
        setNumber = s.set_number
        rowOrder = s.order_index ?? s.set_number
        reps = s.reps
        weightKg = s.weight_kg
        rpe = s.rpe
        restSec = s.rest_sec
        notes = s.notes
        if let ws = s.weight_segments, ws.count >= 2 {
            weightSegments = ws.map { StrengthWeightSegment(reps: $0.reps, weightKg: $0.weight_kg) }
        } else {
            weightSegments = nil
        }
    }
}

func strengthRoutineContentFingerprint(from exercises: [EditableExercise]) -> String {
    let items = strengthProgramItems(from: exercises)
    return strengthRoutineContentFingerprint(from: items)
}

func strengthRoutineContentFingerprint(from items: [StrengthProgramItem]) -> String {
    let sorted = expandedStrengthProgramItemsForCompare(items).sorted { $0.orderIndex < $1.orderIndex }
    var lines: [String] = []
    for item in sorted {
        let setParts = item.sets.sorted { $0.setNumber < $1.setNumber }.map { s in
            let w = s.weightKg.map { String($0) } ?? ""
            let r = s.rpe.map { String($0) } ?? ""
            let rest = s.restSec.map { String($0) } ?? ""
            let rep = s.reps.map { String($0) } ?? ""
            let n = s.notes ?? ""
            let seg = (s.weightSegments ?? []).map { "\($0.reps)x\($0.weightKg)" }.joined(separator: "→")
            return "\(s.setNumber)|\(rep)|\(w)|\(r)|\(rest)|\(n)|\(seg)"
        }
        let cn = item.customName ?? ""
        let note = item.notes ?? ""
        let sg = item.supersetGroupId?.uuidString ?? ""
        let sp = item.supersetPosition.map(String.init) ?? ""
        lines.append("\(item.exerciseId)|\(item.orderIndex)|\(cn)|\(note)|\(sg)|\(sp)|" + setParts.joined(separator: ";"))
    }
    let joined = lines.joined(separator: "\n")
    let digest = SHA256.hash(data: Data(joined.utf8))
    return digest.map { String(format: "%02x", $0) }.joined()
}

func strengthRoutineStructureFingerprint(from items: [StrengthProgramItem]) -> String {
    let sorted = items.sorted { $0.orderIndex < $1.orderIndex }
    let joined = sorted.map { String($0.exerciseId) }.joined(separator: "\n")
    let digest = SHA256.hash(data: Data(joined.utf8))
    return digest.map { String(format: "%02x", $0) }.joined()
}

private func normalizedProgramItemsForCompare(_ items: [StrengthProgramItem]) -> [StrengthProgramItem] {
    items
        .sorted { $0.orderIndex < $1.orderIndex }
        .enumerated()
        .map { idx, item in
            StrengthProgramItem(
                exerciseId: item.exerciseId,
                orderIndex: idx + 1,
                notes: item.notes,
                customName: item.customName,
                supersetGroupId: item.supersetGroupId,
                supersetPosition: item.supersetPosition,
                sets: item.sets
            )
        }
}

func strengthProgramItems(from exercises: [EditableExercise]) -> [StrengthProgramItem] {
    exercises.compactMap { StrengthProgramItem(from: $0) }.sorted { $0.orderIndex < $1.orderIndex }
}

func expandedStrengthProgramSetsForCompare(_ sets: [StrengthProgramSet]) -> [StrengthProgramSet] {
    let sorted = sets.sorted {
        if $0.rowOrder != $1.rowOrder { return $0.rowOrder < $1.rowOrder }
        return $0.setNumber < $1.setNumber
    }
    guard !sorted.isEmpty else { return [] }
    let mults = strengthSetMultiplicities(sortedSetNumbers: sorted.map(\.setNumber))
    var out: [StrengthProgramSet] = []
    var seq = 1
    for (row, mult) in zip(sorted, mults) {
        for _ in 0..<mult {
            out.append(
                StrengthProgramSet(
                    setNumber: seq,
                    rowOrder: seq,
                    reps: row.reps,
                    weightKg: row.weightKg,
                    rpe: row.rpe,
                    restSec: row.restSec,
                    notes: row.notes,
                    weightSegments: row.weightSegments
                )
            )
            seq += 1
        }
    }
    return out
}

private let blankStrengthProgramSetForDiff = StrengthProgramSet(
    setNumber: 0,
    rowOrder: 0,
    reps: nil,
    weightKg: nil,
    rpe: nil,
    restSec: nil,
    notes: nil,
    weightSegments: nil
)

func expandedStrengthProgramItemsForCompare(_ items: [StrengthProgramItem]) -> [StrengthProgramItem] {
    items.map { item in
        StrengthProgramItem(
            exerciseId: item.exerciseId,
            orderIndex: item.orderIndex,
            notes: item.notes,
            customName: item.customName,
            supersetGroupId: item.supersetGroupId,
            supersetPosition: item.supersetPosition,
            sets: expandedStrengthProgramSetsForCompare(item.sets)
        )
    }
}

struct StrengthRoutineOverwriteDiffLine: Identifiable, Equatable {
    let id: String
    let exerciseContext: String
    let exerciseTitle: String
    let setNumber: Int
    let exerciseOrderIndex: Int
    let fieldTitle: String
    let oldValue: String
    let newValue: String
}

struct StrengthRoutineOverwritePrompt: Equatable, Identifiable {
    let routineId: Int64
    let routineName: String
    let diffLines: [StrengthRoutineOverwriteDiffLine]
    let routineBaselineItems: [StrengthProgramItem]

    var id: Int64 { routineId }
}

func actionableOverwriteDiffLineIds(from lines: [StrengthRoutineOverwriteDiffLine]) -> Set<String> {
    Set(lines.filter { $0.fieldTitle != "Sets" }.map(\.id))
}

private func deepCopyProgramSet(_ s: StrengthProgramSet) -> StrengthProgramSet {
    StrengthProgramSet(
        setNumber: s.setNumber,
        rowOrder: s.rowOrder,
        reps: s.reps,
        weightKg: s.weightKg,
        rpe: s.rpe,
        restSec: s.restSec,
        notes: s.notes,
        weightSegments: s.weightSegments?.map { StrengthWeightSegment(reps: $0.reps, weightKg: $0.weightKg) }
    )
}

private func deepCopyProgramItem(_ item: StrengthProgramItem) -> StrengthProgramItem {
    StrengthProgramItem(
        exerciseId: item.exerciseId,
        orderIndex: item.orderIndex,
        notes: item.notes,
        customName: item.customName,
        supersetGroupId: item.supersetGroupId,
        supersetPosition: item.supersetPosition,
        sets: item.sets.map(deepCopyProgramSet)
    )
}

private func renumberExpandedSets(_ sets: [StrengthProgramSet]) -> [StrengthProgramSet] {
    sets.sorted { $0.setNumber < $1.setNumber }.enumerated().map { idx, s in
        StrengthProgramSet(
            setNumber: idx + 1,
            rowOrder: idx + 1,
            reps: s.reps,
            weightKg: s.weightKg,
            rpe: s.rpe,
            restSec: s.restSec,
            notes: s.notes,
            weightSegments: s.weightSegments?.map { StrengthWeightSegment(reps: $0.reps, weightKg: $0.weightKg) }
        )
    }
}

func collapseStrengthProgramSetsForStorage(_ sets: [StrengthProgramSet]) -> [StrengthProgramSet] {
    let sorted = sets.sorted { $0.setNumber < $1.setNumber }
    guard !sorted.isEmpty else { return [] }
    var out: [StrengthProgramSet] = []
    var i = 0
    while i < sorted.count {
        var count = 1
        while i + count < sorted.count,
              !strengthProgramSetPrescriptionDiffers(proposed: sorted[i], routine: sorted[i + count]) {
            count += 1
        }
        let template = sorted[i]
        out.append(
            StrengthProgramSet(
                setNumber: count,
                rowOrder: out.count + 1,
                reps: template.reps,
                weightKg: template.weightKg,
                rpe: template.rpe,
                restSec: template.restSec,
                notes: template.notes,
                weightSegments: template.weightSegments?.map { StrengthWeightSegment(reps: $0.reps, weightKg: $0.weightKg) }
            )
        )
        i += count
    }
    return out
}

func collapseStrengthProgramItemsForStorage(_ items: [StrengthProgramItem]) -> [StrengthProgramItem] {
    items.sorted { $0.orderIndex < $1.orderIndex }.map { item in
        StrengthProgramItem(
            exerciseId: item.exerciseId,
            orderIndex: item.orderIndex,
            notes: item.notes,
            customName: item.customName,
            supersetGroupId: item.supersetGroupId,
            supersetPosition: item.supersetPosition,
            sets: collapseStrengthProgramSetsForStorage(item.sets)
        )
    }
}

private func overwriteDiffLineApplicationRank(_ fieldTitle: String) -> Int {
    switch fieldTitle {
    case "Removed exercise": return 0
    case "Added exercise": return 1
    case "Exercise": return 2
    case "Removed set": return 3
    case "Added set": return 4
    case "Reps": return 10
    case "Weight": return 11
    case "RPE": return 12
    case "Rest": return 13
    case "Drop steps": return 14
    case "Set notes": return 15
    case "Prescription": return 100
    default: return 50
    }
}

private func exerciseIndexInMerged(_ merged: [StrengthProgramItem], orderIndex: Int) -> Int? {
    merged.firstIndex { $0.orderIndex == orderIndex }
}

private func sortedSetsForMerge(_ sets: [StrengthProgramSet]) -> [StrengthProgramSet] {
    sets.sorted { $0.setNumber < $1.setNumber }
}

private func applyOverwriteDiffLine(
    _ line: StrengthRoutineOverwriteDiffLine,
    merged: inout [StrengthProgramItem],
    proposedExpanded: [StrengthProgramItem]
) {
    switch line.fieldTitle {
    case "Prescription":
        return
    case "Removed exercise":
        guard let idx = exerciseIndexInMerged(merged, orderIndex: line.exerciseOrderIndex) else { return }
        merged.remove(at: idx)
        merged = merged.enumerated().map { offset, item in
            var copy = deepCopyProgramItem(item)
            copy.orderIndex = offset + 1
            return copy
        }
    case "Added exercise":
        guard let src = proposedExpanded.first(where: { $0.orderIndex == line.exerciseOrderIndex }) else { return }
        merged.append(deepCopyProgramItem(src))
        merged.sort { $0.orderIndex < $1.orderIndex }
    case "Exercise":
        guard let idx = exerciseIndexInMerged(merged, orderIndex: line.exerciseOrderIndex),
              let src = proposedExpanded.first(where: { $0.orderIndex == line.exerciseOrderIndex }) else { return }
        merged[idx] = deepCopyProgramItem(src)
    case "Removed set":
        guard let exIdx = exerciseIndexInMerged(merged, orderIndex: line.exerciseOrderIndex),
              line.setNumber > 0 else { return }
        var sets = sortedSetsForMerge(merged[exIdx].sets)
        guard line.setNumber <= sets.count else { return }
        sets.remove(at: line.setNumber - 1)
        merged[exIdx].sets = renumberExpandedSets(sets)
    case "Added set":
        guard let exIdx = exerciseIndexInMerged(merged, orderIndex: line.exerciseOrderIndex),
              let propEx = proposedExpanded.first(where: { $0.orderIndex == line.exerciseOrderIndex }),
              line.setNumber > 0 else { return }
        let propSets = sortedSetsForMerge(propEx.sets)
        guard line.setNumber <= propSets.count else { return }
        let newSet = deepCopyProgramSet(propSets[line.setNumber - 1])
        var sets = sortedSetsForMerge(merged[exIdx].sets)
        if line.setNumber - 1 == sets.count {
            sets.append(newSet)
        } else if line.setNumber - 1 < sets.count {
            sets.insert(newSet, at: line.setNumber - 1)
        } else {
            return
        }
        merged[exIdx].sets = renumberExpandedSets(sets)
    case "Reps", "Weight", "RPE", "Rest", "Set notes", "Drop steps":
        guard let exIdx = exerciseIndexInMerged(merged, orderIndex: line.exerciseOrderIndex),
              let propEx = proposedExpanded.first(where: { $0.orderIndex == line.exerciseOrderIndex }),
              line.setNumber > 0 else { return }
        let propSets = sortedSetsForMerge(propEx.sets)
        guard line.setNumber <= propSets.count else { return }
        let propSet = propSets[line.setNumber - 1]
        var sets = sortedSetsForMerge(merged[exIdx].sets)
        guard line.setNumber <= sets.count else { return }
        var target = sets[line.setNumber - 1]
        switch line.fieldTitle {
        case "Reps": target.reps = propSet.reps
        case "Weight": target.weightKg = propSet.weightKg
        case "RPE": target.rpe = propSet.rpe
        case "Rest": target.restSec = propSet.restSec
        case "Set notes": target.notes = propSet.notes
        case "Drop steps":
            target.weightSegments = propSet.weightSegments?.map { StrengthWeightSegment(reps: $0.reps, weightKg: $0.weightKg) }
        default: break
        }
        sets[line.setNumber - 1] = target
        merged[exIdx].sets = sets
    default:
        break
    }
}

func mergeStrengthRoutineWithSelectedChanges(
    routine: [StrengthProgramItem],
    proposed: [StrengthProgramItem],
    selectedLineIds: Set<String>
) -> [StrengthProgramItem] {
    if selectedLineIds.contains("prescription-fallback") {
        return collapseStrengthProgramItemsForStorage(
            expandedStrengthProgramItemsForCompare(normalizedProgramItemsForCompare(proposed))
        )
    }
    var merged = expandedStrengthProgramItemsForCompare(
        normalizedProgramItemsForCompare(routine)
    ).map(deepCopyProgramItem)
    let proposedExpanded = expandedStrengthProgramItemsForCompare(
        normalizedProgramItemsForCompare(proposed)
    )
    let diffLines = buildStrengthRoutineOverwriteDiffLines(
        proposed: proposed,
        routine: routine,
        exerciseDisplayName: { _ in "" }
    )
    let sorted = diffLines
        .filter { $0.fieldTitle != "Sets" && selectedLineIds.contains($0.id) }
        .sorted {
            let r0 = overwriteDiffLineApplicationRank($0.fieldTitle)
            let r1 = overwriteDiffLineApplicationRank($1.fieldTitle)
            if r0 != r1 { return r0 < r1 }
            if $0.exerciseOrderIndex != $1.exerciseOrderIndex { return $0.exerciseOrderIndex < $1.exerciseOrderIndex }
            if $0.setNumber != $1.setNumber { return $0.setNumber < $1.setNumber }
            return $0.id < $1.id
        }
    for line in sorted {
        applyOverwriteDiffLine(line, merged: &merged, proposedExpanded: proposedExpanded)
    }
    merged = merged.enumerated().map { offset, item in
        var copy = deepCopyProgramItem(item)
        copy.orderIndex = offset + 1
        return copy
    }
    return collapseStrengthProgramItemsForStorage(merged)
}

func mergedStrengthRoutineProgramItemsForOverwrite(
    prompt: StrengthRoutineOverwritePrompt,
    proposed: [StrengthProgramItem],
    selectedLineIds: Set<String>
) -> [StrengthProgramItem] {
    mergeStrengthRoutineWithSelectedChanges(
        routine: prompt.routineBaselineItems,
        proposed: proposed,
        selectedLineIds: selectedLineIds
    )
}

enum StrengthRoutineOverwriteCandidate {
    case none
    case prompt(StrengthRoutineOverwritePrompt)
}

struct StrengthRoutineOverwriteConfirmSheet: View {
    let prompt: StrengthRoutineOverwritePrompt
    let onApply: (Set<String>) -> Void
    let onNotNow: () -> Void

    @State private var selectedLineIds: Set<String>

    init(
        prompt: StrengthRoutineOverwritePrompt,
        onApply: @escaping (Set<String>) -> Void,
        onNotNow: @escaping () -> Void
    ) {
        self.prompt = prompt
        self.onApply = onApply
        self.onNotNow = onNotNow
        _selectedLineIds = State(initialValue: actionableOverwriteDiffLineIds(from: prompt.diffLines))
    }

    private var groupedDiff: [ExerciseDiffGroup] {
        StrengthRoutineOverwriteConfirmSheet.buildGroups(from: prompt.diffLines)
    }

    private var actionableLineIds: Set<String> {
        actionableOverwriteDiffLineIds(from: prompt.diffLines)
    }

    private var selectedCount: Int {
        selectedLineIds.intersection(actionableLineIds).count
    }

    private var actionableCount: Int { actionableLineIds.count }
    private var affectedExerciseCount: Int {
        Set(prompt.diffLines.map(\.exerciseOrderIndex)).count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Review changes")
                            .font(.title2.weight(.bold))
                            .fixedSize(horizontal: false, vertical: true)

                        Text(prompt.routineName)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)

                        summaryChip

                        (Text("This updates your ") + Text("saved routine template").fontWeight(.semibold) + Text(". Your completed workout is still saved as usual."))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Text("Changes")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .tracking(0.6)

                    ForEach(groupedDiff) { exGroup in
                        SectionCard {
                            VStack(alignment: .leading, spacing: 14) {
                                Text(exGroup.exerciseTitle)
                                    .font(.headline)
                                    .fixedSize(horizontal: false, vertical: true)

                                ForEach(Array(exGroup.setGroups.enumerated()), id: \.element.id) { idx, setGroup in
                                    VStack(alignment: .leading, spacing: 10) {
                                        Text("Set \(setGroup.setNumber)")
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.secondary)

                                        ForEach(setGroup.lines) { line in
                                            diffRow(line, isSelectable: line.fieldTitle != "Sets")
                                        }
                                    }
                                    if idx + 1 < exGroup.setGroups.count {
                                        Divider()
                                            .opacity(0.35)
                                    }
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.top)
                .padding(.bottom, 8)
            }
            .scrollBounceBehavior(.basedOnSize)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                actionFooter
            }
        }
        .gradientBG()
    }

    private var summaryChip: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.triangle.merge")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(summaryChipText)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.2), lineWidth: 0.5))
        .accessibilityElement(children: .combine)
    }

    private var summaryChipText: String {
        let ex = affectedExerciseCount
        let selected = selectedCount
        let total = actionableCount
        let changePart: String
        if selected == total {
            changePart = total == 1 ? "1 change" : "\(total) changes"
        } else {
            changePart = "\(selected) of \(total) changes"
        }
        if ex == 1 {
            return "\(changePart) · 1 exercise"
        }
        return "\(changePart) · \(ex) exercises"
    }

    private var actionFooter: some View {
        VStack(spacing: 12) {
            Button {
                onApply(selectedLineIds.intersection(actionableLineIds))
            } label: {
                Text(selectedCount == 1 ? "Apply 1 change" : "Apply \(selectedCount) changes")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(selectedCount == 0)

            Button("Not now", action: onNotNow)
                .font(.body.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .buttonStyle(.bordered)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Divider()
                .opacity(0.4)
        }
    }

    @ViewBuilder
    private func diffRow(_ line: StrengthRoutineOverwriteDiffLine, isSelectable: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            if isSelectable {
                Button {
                    if selectedLineIds.contains(line.id) {
                        selectedLineIds.remove(line.id)
                    } else {
                        selectedLineIds.insert(line.id)
                    }
                } label: {
                    Image(systemName: selectedLineIds.contains(line.id) ? "checkmark.square.fill" : "square")
                        .font(.title3)
                        .foregroundStyle(selectedLineIds.contains(line.id) ? Color.accentColor : .secondary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    selectedLineIds.contains(line.id)
                        ? "Selected, \(line.fieldTitle)"
                        : "Not selected, \(line.fieldTitle)"
                )
            } else {
                Color.clear
                    .frame(width: 28, height: 28)
                    .accessibilityHidden(true)
            }

            Image(systemName: Self.iconName(for: line.fieldTitle))
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 26, alignment: .center)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text(line.fieldTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(line.oldValue)
                        .font(.subheadline)
                        .strikethrough()
                        .foregroundStyle(.tertiary)
                    Image(systemName: "arrow.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.quaternary)
                    Text(line.newValue)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(line.fieldTitle), was \(line.oldValue), now \(line.newValue), \(line.exerciseContext)"
        )
    }

    private static func iconName(for fieldTitle: String) -> String {
        switch fieldTitle {
        case "Reps": return "repeat"
        case "Weight": return "scalemass.fill"
        case "RPE": return "gauge.with.dots.needle.67percent"
        case "Rest": return "timer"
        case "Set notes": return "text.alignleft"
        default: return "slider.horizontal.3"
        }
    }

    private struct ExerciseDiffGroup: Identifiable {
        let exerciseOrderIndex: Int
        let exerciseTitle: String
        var setGroups: [SetDiffGroup]
        var id: Int { exerciseOrderIndex }
    }

    private struct SetDiffGroup: Identifiable {
        let setNumber: Int
        let lines: [StrengthRoutineOverwriteDiffLine]
        var id: Int { setNumber }
    }

    private static func buildGroups(from lines: [StrengthRoutineOverwriteDiffLine]) -> [ExerciseDiffGroup] {
        let fieldRank: [String: Int] = [
            "Reps": 0, "Weight": 1, "RPE": 2, "Rest": 3, "Drop steps": 4,
            "Sets": 5, "Added set": 6, "Removed set": 7, "Set notes": 8, "Prescription": 9
        ]
        let byExercise = Dictionary(grouping: lines) { $0.exerciseOrderIndex }
        return byExercise.keys.sorted().compactMap { order in
            let exLines = byExercise[order] ?? []
            guard let title = exLines.first?.exerciseTitle else { return nil }
            let bySet = Dictionary(grouping: exLines) { $0.setNumber }
            let setGroups: [SetDiffGroup] = bySet.keys.sorted().map { setNum in
                let sl = (bySet[setNum] ?? []).sorted {
                    (fieldRank[$0.fieldTitle] ?? 99) < (fieldRank[$1.fieldTitle] ?? 99)
                }
                return SetDiffGroup(setNumber: setNum, lines: sl)
            }
            return ExerciseDiffGroup(exerciseOrderIndex: order, exerciseTitle: title, setGroups: setGroups)
        }
    }
}

private struct StrengthRoutineFullRow: Decodable {
    let id: Int64
    let name: String
    let updated_at: Date?
    let strength_routine_exercises: [StrengthRoutineExerciseWire]?

    enum CodingKeys: String, CodingKey {
        case id, name, updated_at, strength_routine_exercises
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int64.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        strength_routine_exercises = try c.decodeIfPresent([StrengthRoutineExerciseWire].self, forKey: .strength_routine_exercises)
        updated_at = Self.decodeUpdatedAt(from: c)
    }

    private static func decodeUpdatedAt(from c: KeyedDecodingContainer<CodingKeys>) -> Date? {
        if (try? c.decodeNil(forKey: .updated_at)) == true { return nil }
        if let s = try? c.decode(String.self, forKey: .updated_at) {
            return parseUpdatedAtString(s)
        }
        if let d = try? c.decode(Date.self, forKey: .updated_at) {
            return d
        }
        return nil
    }

    private static func parseUpdatedAtString(_ s: String) -> Date? {
        let isoFrac = ISO8601DateFormatter()
        isoFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = isoFrac.date(from: s) { return d }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: s) { return d }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd HH:mm:ssXXXXX"
        if let d = f.date(from: s) { return d }
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: s)
    }
}

private struct StrengthRoutineExerciseWire: Decodable {
    let exercise_id: Int64
    let order_index: Int
    let superset_group_id: UUID?
    let superset_position: Int?
    let notes: String?
    let custom_name: String?
    let strength_routine_sets: [StrengthRoutineSetWire]?

    enum CodingKeys: String, CodingKey {
        case exercise_id, order_index, superset_group_id, superset_position, notes, custom_name, strength_routine_sets
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        exercise_id = try c.decode(Int64.self, forKey: .exercise_id)
        order_index = try c.decode(Int.self, forKey: .order_index)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        custom_name = try c.decodeIfPresent(String.self, forKey: .custom_name)
        superset_position = try c.decodeIfPresent(Int.self, forKey: .superset_position)
        strength_routine_sets = try c.decodeIfPresent([StrengthRoutineSetWire].self, forKey: .strength_routine_sets)
        if let uuid = try? c.decodeIfPresent(UUID.self, forKey: .superset_group_id) {
            superset_group_id = uuid
        } else if let raw = try? c.decodeIfPresent(String.self, forKey: .superset_group_id) {
            superset_group_id = UUID(uuidString: raw)
        } else {
            superset_group_id = nil
        }
    }
}

private struct StrengthRoutineSetWire: Decodable {
    let set_number: Int
    let reps: Int?
    let weight_kg: Double?
    let rpe: Double?
    let rest_sec: Int?
    let notes: String?
    let weight_segments: [StrengthWeightSegWire]?

    enum CodingKeys: String, CodingKey {
        case set_number, reps, weight_kg, rpe, rest_sec, notes, weight_segments
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        set_number = try c.decode(Int.self, forKey: .set_number)
        reps = try c.decodeIfPresent(Int.self, forKey: .reps)
        weight_kg = try c.decodeIfPresent(Double.self, forKey: .weight_kg)
        rpe = try c.decodeIfPresent(Double.self, forKey: .rpe)
        rest_sec = try c.decodeIfPresent(Int.self, forKey: .rest_sec)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        weight_segments = try? c.decodeIfPresent([StrengthWeightSegWire].self, forKey: .weight_segments)
    }
}

private func strengthRoutineFullDetailSelect() -> String {
    "id,name,updated_at,strength_routine_exercises(exercise_id,order_index,superset_group_id,superset_position,notes,custom_name,strength_routine_sets(set_number,reps,weight_kg,rpe,rest_sec,notes,weight_segments))"
}

private func strengthRoutineFullDetailSelectLegacy() -> String {
    "id,name,updated_at,strength_routine_exercises(exercise_id,order_index,notes,custom_name,strength_routine_sets(set_number,reps,weight_kg,rpe,rest_sec,notes,weight_segments))"
}

private func fetchStrengthRoutineFullRows(
    client: SupabaseClient,
    userId: UUID,
    routineId: Int64? = nil
) async throws -> [StrengthRoutineFullRow] {
    do {
        let res: PostgrestResponse<Data>
        if let routineId {
            res = try await client
                .from("strength_routines")
                .select(strengthRoutineFullDetailSelect())
                .eq("user_id", value: userId)
                .eq("id", value: Int(routineId))
                .execute()
        } else {
            res = try await client
                .from("strength_routines")
                .select(strengthRoutineFullDetailSelect())
                .eq("user_id", value: userId)
                .execute()
        }
        return try decodeStrengthRoutineFullRows(from: res.data)
    } catch {
        guard strengthRoutineSupersetColumnsUnavailable(error) else { throw error }
        let res: PostgrestResponse<Data>
        if let routineId {
            res = try await client
                .from("strength_routines")
                .select(strengthRoutineFullDetailSelectLegacy())
                .eq("user_id", value: userId)
                .eq("id", value: Int(routineId))
                .execute()
        } else {
            res = try await client
                .from("strength_routines")
                .select(strengthRoutineFullDetailSelectLegacy())
                .eq("user_id", value: userId)
                .execute()
        }
        return try decodeStrengthRoutineFullRows(from: res.data)
    }
}

private func decodeStrengthRoutineFullRows(from data: Data) throws -> [StrengthRoutineFullRow] {
    let decoder = JSONDecoder.supabase()
    if let rows = try? decoder.decode([StrengthRoutineFullRow].self, from: data), !rows.isEmpty {
        return rows
    }
    if let row = try? decoder.decode(StrengthRoutineFullRow.self, from: data) {
        return [row]
    }
    return try decoder.decode([StrengthRoutineFullRow].self, from: data)
}

private func fetchAllStrengthRoutineFullRows(
    client: SupabaseClient,
    userId: UUID
) async throws -> [StrengthRoutineFullRow] {
    try await fetchStrengthRoutineFullRows(client: client, userId: userId, routineId: nil)
}

private func programItemsFromTemplateDetail(_ detail: StrengthTemplateDetailWire) -> [StrengthProgramItem] {
    let exs = (detail.strength_routine_exercises ?? []).sorted { $0.order_index < $1.order_index }
    return exs.map { ex in
        let setsInOrder = ex.strength_routine_sets ?? []
        let mapped: [StrengthProgramSet] = setsInOrder.enumerated().map { idx, s in
            let segs: [StrengthWeightSegment]? = {
                guard let arr = s.weight_segments, arr.count >= 2 else { return nil }
                return arr.map { StrengthWeightSegment(reps: $0.reps, weightKg: $0.weight_kg) }
            }()
            return StrengthProgramSet(
                setNumber: s.set_number,
                rowOrder: idx + 1,
                reps: s.reps,
                weightKg: s.weight_kg,
                rpe: s.rpe,
                restSec: s.rest_sec,
                notes: s.notes,
                weightSegments: segs
            )
        }
        return StrengthProgramItem(
            exerciseId: ex.exercise_id,
            orderIndex: ex.order_index,
            notes: ex.notes,
            customName: ex.custom_name,
            supersetGroupId: ex.superset_group_id,
            supersetPosition: ex.superset_position,
            sets: mapped
        )
    }
}

private func programItemsFromRoutineRow(_ row: StrengthRoutineFullRow) -> [StrengthProgramItem] {
    let exs = (row.strength_routine_exercises ?? []).sorted { $0.order_index < $1.order_index }
    return exs.map { ex in
        let setsInOrder = ex.strength_routine_sets ?? []
        let mapped: [StrengthProgramSet] = setsInOrder.enumerated().map { idx, s in
            let segs: [StrengthWeightSegment]? = {
                guard let arr = s.weight_segments, arr.count >= 2 else { return nil }
                return arr.map { StrengthWeightSegment(reps: $0.reps, weightKg: $0.weight_kg) }
            }()
            return StrengthProgramSet(
                setNumber: s.set_number,
                rowOrder: idx + 1,
                reps: s.reps,
                weightKg: s.weight_kg,
                rpe: s.rpe,
                restSec: s.rest_sec,
                notes: s.notes,
                weightSegments: segs
            )
        }
        return StrengthProgramItem(
            exerciseId: ex.exercise_id,
            orderIndex: ex.order_index,
            notes: ex.notes,
            customName: ex.custom_name,
            supersetGroupId: ex.superset_group_id,
            supersetPosition: ex.superset_position,
            sets: mapped
        )
    }
}

private enum StrengthPrescriptionCompare {
    static let weightEpsilon = 0.0001
    static let rpeEpsilon = 0.001

    static func repsChanged(_ proposed: Int?, _ routine: Int?) -> Bool {
        proposed != routine
    }

    static func optionalDoubleChanged(_ proposed: Double?, _ routine: Double?, epsilon: Double) -> Bool {
        switch (proposed, routine) {
        case (nil, nil): return false
        case (nil, _), (_, nil): return true
        case let (p?, r?): return abs(p - r) > epsilon
        }
    }

    static func restChanged(_ proposed: Int?, _ routine: Int?) -> Bool {
        proposed != routine
    }
}

func exerciseStructureMatch(_ a: [StrengthProgramItem], _ b: [StrengthProgramItem]) -> Bool {
    strengthRoutineStructureFingerprint(from: a) == strengthRoutineStructureFingerprint(from: b)
}

private func structuresMatch(_ a: [StrengthProgramItem], _ b: [StrengthProgramItem]) -> Bool {
    exerciseStructureMatch(a, b)
}

private func displayNameForDiff(exerciseName: String, item: StrengthProgramItem) -> String {
    let cn = (item.customName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    if !cn.isEmpty { return cn }
    let trimmed = exerciseName.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmed.isEmpty { return trimmed }
    return "Exercise \(item.exerciseId)"
}

private func formatWeight(_ d: Double?) -> String {
    guard let d else { return "—" }
    if d == floor(d) { return String(Int(d)) }
    return String(d)
}

private func formatRpe(_ d: Double?) -> String {
    guard let d else { return "—" }
    if abs(d * 10 - floor(d * 10 + 0.0001)) < 0.0001 {
        return String(format: "%.1f", d)
    }
    return String(d)
}

func buildStrengthRoutineOverwriteDiffLines(
    proposed: [StrengthProgramItem],
    routine: [StrengthProgramItem],
    exerciseDisplayName: (Int64) -> String
) -> [StrengthRoutineOverwriteDiffLine] {
    var lines: [StrengthRoutineOverwriteDiffLine] = []
    let prop = expandedStrengthProgramItemsForCompare(normalizedProgramItemsForCompare(proposed))
    let rout = expandedStrengthProgramItemsForCompare(normalizedProgramItemsForCompare(routine))
    let maxExercises = max(prop.count, rout.count)
    for i in 0..<maxExercises {
        let pEx = i < prop.count ? prop[i] : nil
        let rEx = i < rout.count ? rout[i] : nil
        if pEx == nil, let rEx {
            let exLabel = displayNameForDiff(exerciseName: exerciseDisplayName(rEx.exerciseId), item: rEx)
            lines.append(StrengthRoutineOverwriteDiffLine(
                id: "\(rEx.exerciseId)-removed-exercise",
                exerciseContext: exLabel,
                exerciseTitle: exLabel,
                setNumber: 0,
                exerciseOrderIndex: rEx.orderIndex,
                fieldTitle: "Removed exercise",
                oldValue: exLabel,
                newValue: "—"
            ))
            continue
        }
        if rEx == nil, let pEx {
            let exLabel = displayNameForDiff(exerciseName: exerciseDisplayName(pEx.exerciseId), item: pEx)
            lines.append(StrengthRoutineOverwriteDiffLine(
                id: "\(pEx.exerciseId)-added-exercise",
                exerciseContext: exLabel,
                exerciseTitle: exLabel,
                setNumber: 0,
                exerciseOrderIndex: pEx.orderIndex,
                fieldTitle: "Added exercise",
                oldValue: "—",
                newValue: exLabel
            ))
            continue
        }
        guard let pEx, let rEx else { continue }
        if pEx.exerciseId != rEx.exerciseId {
            let pLabel = displayNameForDiff(exerciseName: exerciseDisplayName(pEx.exerciseId), item: pEx)
            let rLabel = displayNameForDiff(exerciseName: exerciseDisplayName(rEx.exerciseId), item: rEx)
            lines.append(StrengthRoutineOverwriteDiffLine(
                id: "\(pEx.exerciseId)-\(rEx.exerciseId)-exercise-swap",
                exerciseContext: pLabel,
                exerciseTitle: pLabel,
                setNumber: 0,
                exerciseOrderIndex: pEx.orderIndex,
                fieldTitle: "Exercise",
                oldValue: rLabel,
                newValue: pLabel
            ))
            continue
        }
        let exLabel = displayNameForDiff(exerciseName: exerciseDisplayName(pEx.exerciseId), item: pEx)
        let setsP = pEx.sets.sorted { $0.setNumber < $1.setNumber }
        let setsR = rEx.sets.sorted { $0.setNumber < $1.setNumber }
        if setsP.count != setsR.count {
            lines.append(StrengthRoutineOverwriteDiffLine(
                id: "\(pEx.exerciseId)-sets-count",
                exerciseContext: exLabel,
                exerciseTitle: exLabel,
                setNumber: 0,
                exerciseOrderIndex: pEx.orderIndex,
                fieldTitle: "Sets",
                oldValue: "\(setsR.count)",
                newValue: "\(setsP.count)"
            ))
        }
        let prefixMatches = zip(setsP.prefix(setsR.count), setsR.prefix(setsP.count)).allSatisfy { ps, rs in
            !strengthProgramSetPrescriptionDiffers(proposed: ps, routine: rs)
        }
        let isAppendOnly = setsP.count > setsR.count && prefixMatches
        let maxCount = max(setsP.count, setsR.count)
        for idx in 0..<maxCount {
            let setNum = idx + 1
            let ps = idx < setsP.count ? setsP[idx] : nil
            let rs = idx < setsR.count ? setsR[idx] : nil
            let setLabel = "\(exLabel) · Set \(setNum)"
            let baseId = "\(pEx.exerciseId)-\(setNum)"
            if ps == nil, rs != nil {
                if isAppendOnly { continue }
                lines.append(StrengthRoutineOverwriteDiffLine(
                    id: "\(baseId)-removed",
                    exerciseContext: setLabel,
                    exerciseTitle: exLabel,
                    setNumber: setNum,
                    exerciseOrderIndex: pEx.orderIndex,
                    fieldTitle: "Removed set",
                    oldValue: "Set \(setNum)",
                    newValue: "—"
                ))
                continue
            }
            if ps != nil, rs == nil {
                lines.append(StrengthRoutineOverwriteDiffLine(
                    id: "\(baseId)-added",
                    exerciseContext: setLabel,
                    exerciseTitle: exLabel,
                    setNumber: setNum,
                    exerciseOrderIndex: pEx.orderIndex,
                    fieldTitle: "Added set",
                    oldValue: "—",
                    newValue: "Set \(setNum)"
                ))
                let routineBaseline = setsR.last
                let isDuplicateAppend = isAppendOnly
                    && routineBaseline != nil
                    && !strengthProgramSetPrescriptionDiffers(proposed: ps!, routine: routineBaseline!)
                if !isDuplicateAppend {
                    appendPrescriptionDiffLines(
                        lines: &lines,
                        proposed: ps!,
                        routine: blankStrengthProgramSetForDiff,
                        exLabel: exLabel,
                        pEx: pEx,
                        setNum: setNum,
                        baseId: baseId,
                        setLabel: setLabel
                    )
                }
                continue
            }
            guard let ps, let rs else { continue }
            appendPrescriptionDiffLines(
                lines: &lines,
                proposed: ps,
                routine: rs,
                exLabel: exLabel,
                pEx: pEx,
                setNum: setNum,
                baseId: baseId,
                setLabel: setLabel
            )
        }
    }
    return lines
}

private func strengthProgramSetPrescriptionDiffers(proposed ps: StrengthProgramSet, routine rs: StrengthProgramSet) -> Bool {
    if StrengthPrescriptionCompare.repsChanged(ps.reps, rs.reps) { return true }
    if StrengthPrescriptionCompare.optionalDoubleChanged(ps.weightKg, rs.weightKg, epsilon: StrengthPrescriptionCompare.weightEpsilon) { return true }
    if StrengthPrescriptionCompare.optionalDoubleChanged(ps.rpe, rs.rpe, epsilon: StrengthPrescriptionCompare.rpeEpsilon) { return true }
    if StrengthPrescriptionCompare.restChanged(ps.restSec, rs.restSec) { return true }
    let pn = (ps.notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let rn = (rs.notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    if pn != rn { return true }
    let psSeg = (ps.weightSegments ?? []).map { "\($0.reps)×\(formatWeight($0.weightKg))" }.joined(separator: " → ")
    let rsSeg = (rs.weightSegments ?? []).map { "\($0.reps)×\(formatWeight($0.weightKg))" }.joined(separator: " → ")
    return psSeg != rsSeg
}

private func appendPrescriptionDiffLines(
    lines: inout [StrengthRoutineOverwriteDiffLine],
    proposed ps: StrengthProgramSet,
    routine rs: StrengthProgramSet,
    exLabel: String,
    pEx: StrengthProgramItem,
    setNum: Int,
    baseId: String,
    setLabel: String
) {
    if StrengthPrescriptionCompare.repsChanged(ps.reps, rs.reps) {
        lines.append(StrengthRoutineOverwriteDiffLine(
            id: "\(baseId)-reps",
            exerciseContext: setLabel,
            exerciseTitle: exLabel,
            setNumber: setNum,
            exerciseOrderIndex: pEx.orderIndex,
            fieldTitle: "Reps",
            oldValue: rs.reps.map(String.init) ?? "—",
            newValue: ps.reps.map(String.init) ?? "—"
        ))
    }
    if StrengthPrescriptionCompare.optionalDoubleChanged(ps.weightKg, rs.weightKg, epsilon: StrengthPrescriptionCompare.weightEpsilon) {
        lines.append(StrengthRoutineOverwriteDiffLine(
            id: "\(baseId)-kg",
            exerciseContext: setLabel,
            exerciseTitle: exLabel,
            setNumber: setNum,
            exerciseOrderIndex: pEx.orderIndex,
            fieldTitle: "Weight",
            oldValue: formatWeight(rs.weightKg) + " kg",
            newValue: formatWeight(ps.weightKg) + " kg"
        ))
    }
    if StrengthPrescriptionCompare.optionalDoubleChanged(ps.rpe, rs.rpe, epsilon: StrengthPrescriptionCompare.rpeEpsilon) {
        lines.append(StrengthRoutineOverwriteDiffLine(
            id: "\(baseId)-rpe",
            exerciseContext: setLabel,
            exerciseTitle: exLabel,
            setNumber: setNum,
            exerciseOrderIndex: pEx.orderIndex,
            fieldTitle: "RPE",
            oldValue: formatRpe(rs.rpe),
            newValue: formatRpe(ps.rpe)
        ))
    }
    if StrengthPrescriptionCompare.restChanged(ps.restSec, rs.restSec) {
        lines.append(StrengthRoutineOverwriteDiffLine(
            id: "\(baseId)-rest",
            exerciseContext: setLabel,
            exerciseTitle: exLabel,
            setNumber: setNum,
            exerciseOrderIndex: pEx.orderIndex,
            fieldTitle: "Rest",
            oldValue: rs.restSec.map { "\($0) s" } ?? "—",
            newValue: ps.restSec.map { "\($0) s" } ?? "—"
        ))
    }
    let pn = (ps.notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let rn = (rs.notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    if pn != rn {
        lines.append(StrengthRoutineOverwriteDiffLine(
            id: "\(baseId)-notes",
            exerciseContext: setLabel,
            exerciseTitle: exLabel,
            setNumber: setNum,
            exerciseOrderIndex: pEx.orderIndex,
            fieldTitle: "Set notes",
            oldValue: rn.isEmpty ? "—" : rn,
            newValue: pn.isEmpty ? "—" : pn
        ))
    }
    let psSeg = (ps.weightSegments ?? []).map { "\($0.reps)×\(formatWeight($0.weightKg))" }.joined(separator: " → ")
    let rsSeg = (rs.weightSegments ?? []).map { "\($0.reps)×\(formatWeight($0.weightKg))" }.joined(separator: " → ")
    if psSeg != rsSeg {
        lines.append(StrengthRoutineOverwriteDiffLine(
            id: "\(baseId)-drop",
            exerciseContext: setLabel,
            exerciseTitle: exLabel,
            setNumber: setNum,
            exerciseOrderIndex: pEx.orderIndex,
            fieldTitle: "Drop steps",
            oldValue: rsSeg.isEmpty ? "—" : rsSeg,
            newValue: psSeg.isEmpty ? "—" : psSeg
        ))
    }
}

private func strengthRoutineOverwritePromptIfContentDiffers(
    routineId: Int64,
    routineName: String,
    routineItems: [StrengthProgramItem],
    proposed: [StrengthProgramItem],
    proposedContent: String,
    exerciseDisplayName: (Int64) -> String
) -> StrengthRoutineOverwriteCandidate {
    let normalizedRoutine = normalizedProgramItemsForCompare(routineItems)
    guard !normalizedRoutine.isEmpty else { return .none }
    let routineContent = strengthRoutineContentFingerprint(from: normalizedRoutine)
    if routineContent == proposedContent { return .none }
    var diff = buildStrengthRoutineOverwriteDiffLines(
        proposed: proposed,
        routine: normalizedRoutine,
        exerciseDisplayName: exerciseDisplayName
    )
    if diff.isEmpty {
        diff = [
            StrengthRoutineOverwriteDiffLine(
                id: "prescription-fallback",
                exerciseContext: routineName,
                exerciseTitle: routineName,
                setNumber: 0,
                exerciseOrderIndex: 0,
                fieldTitle: "Prescription",
                oldValue: "Saved template",
                newValue: "Updated workout"
            )
        ]
    }
    guard !diff.isEmpty else { return .none }
    return .prompt(StrengthRoutineOverwritePrompt(
        routineId: routineId,
        routineName: routineName,
        diffLines: diff,
        routineBaselineItems: normalizedRoutine
    ))
}

func fetchStrengthRoutineOverwriteCandidate(
    client: SupabaseClient,
    userId: UUID,
    proposed: [StrengthProgramItem],
    exerciseDisplayName: @escaping (Int64) -> String,
    preferredRoutineId: Int64? = nil
) async throws -> StrengthRoutineOverwriteCandidate {
    guard !proposed.isEmpty else { return .none }
    let proposedNormalized = normalizedProgramItemsForCompare(proposed)
    let proposedContent = strengthRoutineContentFingerprint(from: proposedNormalized)

    if let preferredRoutineId {
        let detail = try await fetchStrengthRoutineTemplateDetail(client: client, routineId: preferredRoutineId)
        let items = programItemsFromTemplateDetail(detail)
        return strengthRoutineOverwritePromptIfContentDiffers(
            routineId: detail.id,
            routineName: detail.name,
            routineItems: items,
            proposed: proposedNormalized,
            proposedContent: proposedContent,
            exerciseDisplayName: exerciseDisplayName
        )
    }

    let rows = try await fetchStrengthRoutineFullRows(
        client: client,
        userId: userId,
        routineId: nil
    )
    guard !rows.isEmpty else { return .none }

    var matches: [(row: StrengthRoutineFullRow, items: [StrengthProgramItem], contentHash: String)] = []
    for row in rows {
        let items = normalizedProgramItemsForCompare(programItemsFromRoutineRow(row))
        guard !items.isEmpty, structuresMatch(proposedNormalized, items) else { continue }
        let ch = strengthRoutineContentFingerprint(from: items)
        if ch == proposedContent { continue }
        matches.append((row, items, ch))
    }
    guard !matches.isEmpty else { return .none }

    let best = matches.max { a, b in
        let da = a.row.updated_at ?? .distantPast
        let db = b.row.updated_at ?? .distantPast
        if da != db { return da < db }
        return a.row.id < b.row.id
    }!
    return strengthRoutineOverwritePromptIfContentDiffers(
        routineId: best.row.id,
        routineName: best.row.name,
        routineItems: best.items,
        proposed: proposedNormalized,
        proposedContent: proposedContent,
        exerciseDisplayName: exerciseDisplayName
    )
}

func applyStrengthRoutinePrescriptionUpdate(
    client: SupabaseClient,
    userId: UUID,
    routineId: Int64,
    exercises: [EditableExercise]
) async throws {
    let normalized = normalizedSupersetPrograms(exercises)
    let items = strengthProgramItems(from: normalized)
    guard !items.isEmpty else {
        throw NSError(
            domain: "StrengthRoutineOverwrite",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "No exercises to save."]
        )
    }
    try await applyStrengthRoutinePrescriptionUpdateFromProgramItems(
        client: client,
        userId: userId,
        routineId: routineId,
        items: items
    )
}

func applyStrengthRoutinePrescriptionUpdateFromProgramItems(
    client: SupabaseClient,
    userId: UUID,
    routineId: Int64,
    items: [StrengthProgramItem]
) async throws {
    guard !items.isEmpty else {
        throw NSError(
            domain: "StrengthRoutineOverwrite",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "No exercises to save."]
        )
    }

    struct RoutineExerciseIdRow: Decodable { let id: Int64 }

    let sortedItems = items.sorted { $0.orderIndex < $1.orderIndex }
    let contentHash = strengthRoutineContentFingerprint(from: sortedItems)

    struct ExistingRoutineExerciseId: Decodable { let id: Int64 }
    let existingRes = try await client
        .from("strength_routine_exercises")
        .select("id")
        .eq("routine_id", value: Int(routineId))
        .execute()
    let existingIds = try JSONDecoder.supabase().decode([ExistingRoutineExerciseId].self, from: existingRes.data).map(\.id)
    if !existingIds.isEmpty {
        let idInts = existingIds.map { Int($0) }
        _ = try await client
            .from("strength_routine_sets")
            .delete()
            .in("routine_exercise_id", values: idInts)
            .execute()
    }
    _ = try await client
        .from("strength_routine_exercises")
        .delete()
        .eq("routine_id", value: Int(routineId))
        .execute()

    struct StrengthRoutineSetRowInsert: Encodable {
        let routine_exercise_id: Int64
        let set_number: Int
        let reps: Int?
        let weight_kg: Double?
        let rpe: Double?
        let rest_sec: Int?
        let notes: String?
        let weight_segments: [StrengthWeightSegWire]?
    }

    for item in sortedItems {
        let exRes = try await client
            .from("strength_routine_exercises")
            .insert(
                StrengthRoutineExerciseRowInsert(
                    routine_id: routineId,
                    exercise_id: item.exerciseId,
                    order_index: item.orderIndex,
                    notes: item.notes,
                    custom_name: item.customName,
                    superset_group_id: item.supersetGroupId,
                    superset_position: item.supersetPosition
                ),
                returning: .representation
            )
            .select("id")
            .limit(1)
            .execute()

        let exIdRows = try JSONDecoder.supabase().decode([RoutineExerciseIdRow].self, from: exRes.data)
        guard let exerciseRowId = exIdRows.first?.id else {
            throw NSError(
                domain: "StrengthRoutineOverwrite",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Routine update failed (exercise row missing)."]
            )
        }

        let setRows: [StrengthRoutineSetRowInsert] = item.sets.map { s in
            let ws: [StrengthWeightSegWire]? = {
                guard let segs = s.weightSegments, segs.count >= 2 else { return nil }
                return segs.map { StrengthWeightSegWire(reps: $0.reps, weight_kg: $0.weightKg) }
            }()
            return StrengthRoutineSetRowInsert(
                routine_exercise_id: exerciseRowId,
                set_number: s.setNumber,
                reps: s.reps,
                weight_kg: s.weightKg,
                rpe: s.rpe,
                rest_sec: s.restSec,
                notes: s.notes,
                weight_segments: ws
            )
        }
        if !setRows.isEmpty {
            _ = try await client.from("strength_routine_sets").insert(setRows).execute()
        }
    }

    struct ContentHashPatch: Encodable {
        let content_hash: String
    }

    _ = try await client
        .from("strength_routines")
        .update(ContentHashPatch(content_hash: contentHash))
        .eq("id", value: Int(routineId))
        .eq("user_id", value: userId)
        .execute()
}

func applySelectiveStrengthRoutineOverwrite(
    client: SupabaseClient,
    userId: UUID,
    prompt: StrengthRoutineOverwritePrompt,
    proposed: [StrengthProgramItem],
    selectedLineIds: Set<String>
) async throws {
    let merged = mergedStrengthRoutineProgramItemsForOverwrite(
        prompt: prompt,
        proposed: proposed,
        selectedLineIds: selectedLineIds
    )
    try await applyStrengthRoutinePrescriptionUpdateFromProgramItems(
        client: client,
        userId: userId,
        routineId: prompt.routineId,
        items: merged
    )
}
