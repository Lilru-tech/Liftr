import CryptoKit
import Foundation
import Supabase
import SwiftUI

struct StrengthProgramItem: Equatable {
    var exerciseId: Int64
    var orderIndex: Int
    var notes: String?
    var customName: String?
    var sets: [StrengthProgramSet]

    init(exerciseId: Int64, orderIndex: Int, notes: String?, customName: String?, sets: [StrengthProgramSet]) {
        self.exerciseId = exerciseId
        self.orderIndex = orderIndex
        self.notes = notes
        self.customName = customName
        self.sets = sets
    }

    init?(from editable: EditableExercise) {
        guard let item = editable.toStrengthItem() else { return nil }
        self.init(
            exerciseId: item.exercise_id,
            orderIndex: item.order_index,
            notes: item.notes,
            customName: item.custom_name,
            sets: item.sets
                .sorted { $0.set_number < $1.set_number }
                .map { StrengthProgramSet(from: $0) }
        )
    }
}

struct StrengthProgramSet: Equatable {
    var setNumber: Int
    var reps: Int?
    var weightKg: Double?
    var rpe: Double?
    var restSec: Int?
    var notes: String?

    init(setNumber: Int, reps: Int?, weightKg: Double?, rpe: Double?, restSec: Int?, notes: String?) {
        self.setNumber = setNumber
        self.reps = reps
        self.weightKg = weightKg
        self.rpe = rpe
        self.restSec = restSec
        self.notes = notes
    }

    fileprivate init(from s: RPCStrengthParams.StrengthItem.StrengthSet) {
        setNumber = s.set_number
        reps = s.reps
        weightKg = s.weight_kg
        rpe = s.rpe
        restSec = s.rest_sec
        notes = s.notes
    }
}

func strengthRoutineContentFingerprint(from exercises: [EditableExercise]) -> String {
    let items = strengthProgramItems(from: exercises)
    return strengthRoutineContentFingerprint(from: items)
}

func strengthRoutineContentFingerprint(from items: [StrengthProgramItem]) -> String {
    let sorted = items.sorted { $0.orderIndex < $1.orderIndex }
    var lines: [String] = []
    for item in sorted {
        let setParts = item.sets.sorted { $0.setNumber < $1.setNumber }.map { s in
            let w = s.weightKg.map { String($0) } ?? ""
            let r = s.rpe.map { String($0) } ?? ""
            let rest = s.restSec.map { String($0) } ?? ""
            let rep = s.reps.map { String($0) } ?? ""
            let n = s.notes ?? ""
            return "\(s.setNumber)|\(rep)|\(w)|\(r)|\(rest)|\(n)"
        }
        let cn = item.customName ?? ""
        let note = item.notes ?? ""
        lines.append("\(item.exerciseId)|\(item.orderIndex)|\(cn)|\(note)|" + setParts.joined(separator: ";"))
    }
    let joined = lines.joined(separator: "\n")
    let digest = SHA256.hash(data: Data(joined.utf8))
    return digest.map { String(format: "%02x", $0) }.joined()
}

func strengthRoutineStructureFingerprint(from items: [StrengthProgramItem]) -> String {
    let sorted = items.sorted { $0.orderIndex < $1.orderIndex }
    var lines: [String] = []
    for item in sorted {
        let cn = (item.customName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let note = (item.notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        lines.append("\(item.exerciseId)|\(item.orderIndex)|\(cn)|\(note)|\(item.sets.count)")
    }
    let joined = lines.joined(separator: "\n")
    let digest = SHA256.hash(data: Data(joined.utf8))
    return digest.map { String(format: "%02x", $0) }.joined()
}

func strengthProgramItems(from exercises: [EditableExercise]) -> [StrengthProgramItem] {
    exercises.compactMap { StrengthProgramItem(from: $0) }.sorted { $0.orderIndex < $1.orderIndex }
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

    var id: Int64 { routineId }
}

enum StrengthRoutineOverwriteCandidate {
    case none
    case prompt(StrengthRoutineOverwritePrompt)
}

struct StrengthRoutineOverwriteConfirmSheet: View {
    let prompt: StrengthRoutineOverwritePrompt
    let onUpdate: () -> Void
    let onNotNow: () -> Void

    private var groupedDiff: [ExerciseDiffGroup] {
        StrengthRoutineOverwriteConfirmSheet.buildGroups(from: prompt.diffLines)
    }

    private var changeCount: Int { prompt.diffLines.count }
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
                                            diffRow(line)
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
        let ch = changeCount
        if ex == 1 {
            return "\(ch) change · 1 exercise"
        }
        return "\(ch) changes · \(ex) exercises"
    }

    private var actionFooter: some View {
        VStack(spacing: 12) {
            Button(action: onUpdate) {
                Text("Overwrite template")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

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
    private func diffRow(_ line: StrengthRoutineOverwriteDiffLine) -> some View {
        HStack(alignment: .top, spacing: 10) {
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
            "Reps": 0, "Weight": 1, "RPE": 2, "Rest": 3, "Set notes": 4
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
}

private struct StrengthRoutineExerciseWire: Decodable {
    let exercise_id: Int64
    let order_index: Int
    let notes: String?
    let custom_name: String?
    let strength_routine_sets: [StrengthRoutineSetWire]?
}

private struct StrengthRoutineSetWire: Decodable {
    let set_number: Int
    let reps: Int?
    let weight_kg: Double?
    let rpe: Double?
    let rest_sec: Int?
    let notes: String?
}

private func strengthRoutineFullDetailSelect() -> String {
    "id,name,updated_at,strength_routine_exercises(exercise_id,order_index,notes,custom_name,strength_routine_sets(set_number,reps,weight_kg,rpe,rest_sec,notes))"
}

private func programItemsFromRoutineRow(_ row: StrengthRoutineFullRow) -> [StrengthProgramItem] {
    let exs = (row.strength_routine_exercises ?? []).sorted { $0.order_index < $1.order_index }
    return exs.map { ex in
        let setsSorted = (ex.strength_routine_sets ?? []).sorted { $0.set_number < $1.set_number }
        let mapped: [StrengthProgramSet] = setsSorted.map { s in
            StrengthProgramSet(
                setNumber: s.set_number,
                reps: s.reps,
                weightKg: s.weight_kg,
                rpe: s.rpe,
                restSec: s.rest_sec,
                notes: s.notes
            )
        }
        return StrengthProgramItem(
            exerciseId: ex.exercise_id,
            orderIndex: ex.order_index,
            notes: ex.notes,
            customName: ex.custom_name,
            sets: mapped
        )
    }
}

private func structuresMatch(_ a: [StrengthProgramItem], _ b: [StrengthProgramItem]) -> Bool {
    strengthRoutineStructureFingerprint(from: a) == strengthRoutineStructureFingerprint(from: b)
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

private func buildDiffLines(
    proposed: [StrengthProgramItem],
    routine: [StrengthProgramItem],
    exerciseDisplayName: (Int64) -> String
) -> [StrengthRoutineOverwriteDiffLine] {
    var lines: [StrengthRoutineOverwriteDiffLine] = []
    let prop = proposed.sorted { $0.orderIndex < $1.orderIndex }
    let rout = routine.sorted { $0.orderIndex < $1.orderIndex }
    for i in prop.indices {
        let pEx = prop[i]
        let rEx = rout[i]
        let exLabel = displayNameForDiff(exerciseName: exerciseDisplayName(pEx.exerciseId), item: pEx)
        let setsP = pEx.sets.sorted { $0.setNumber < $1.setNumber }
        let setsR = rEx.sets.sorted { $0.setNumber < $1.setNumber }
        for j in setsP.indices {
            let ps = setsP[j]
            let rs = setsR[j]
            let setLabel = "\(exLabel) · Set \(ps.setNumber)"
            let baseId = "\(pEx.exerciseId)-\(ps.setNumber)"
            if ps.reps != rs.reps {
                lines.append(StrengthRoutineOverwriteDiffLine(
                    id: "\(baseId)-reps",
                    exerciseContext: setLabel,
                    exerciseTitle: exLabel,
                    setNumber: ps.setNumber,
                    exerciseOrderIndex: pEx.orderIndex,
                    fieldTitle: "Reps",
                    oldValue: rs.reps.map(String.init) ?? "—",
                    newValue: ps.reps.map(String.init) ?? "—"
                ))
            }
            if ps.weightKg != rs.weightKg {
                lines.append(StrengthRoutineOverwriteDiffLine(
                    id: "\(baseId)-kg",
                    exerciseContext: setLabel,
                    exerciseTitle: exLabel,
                    setNumber: ps.setNumber,
                    exerciseOrderIndex: pEx.orderIndex,
                    fieldTitle: "Weight",
                    oldValue: formatWeight(rs.weightKg) + " kg",
                    newValue: formatWeight(ps.weightKg) + " kg"
                ))
            }
            if ps.rpe != rs.rpe {
                lines.append(StrengthRoutineOverwriteDiffLine(
                    id: "\(baseId)-rpe",
                    exerciseContext: setLabel,
                    exerciseTitle: exLabel,
                    setNumber: ps.setNumber,
                    exerciseOrderIndex: pEx.orderIndex,
                    fieldTitle: "RPE",
                    oldValue: formatRpe(rs.rpe),
                    newValue: formatRpe(ps.rpe)
                ))
            }
            if ps.restSec != rs.restSec {
                lines.append(StrengthRoutineOverwriteDiffLine(
                    id: "\(baseId)-rest",
                    exerciseContext: setLabel,
                    exerciseTitle: exLabel,
                    setNumber: ps.setNumber,
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
                    setNumber: ps.setNumber,
                    exerciseOrderIndex: pEx.orderIndex,
                    fieldTitle: "Set notes",
                    oldValue: rn.isEmpty ? "—" : rn,
                    newValue: pn.isEmpty ? "—" : pn
                ))
            }
        }
    }
    return lines
}

func fetchStrengthRoutineOverwriteCandidate(
    client: SupabaseClient,
    userId: UUID,
    proposed: [StrengthProgramItem],
    exerciseDisplayName: @escaping (Int64) -> String
) async throws -> StrengthRoutineOverwriteCandidate {
    guard !proposed.isEmpty else { return .none }
    let proposedContent = strengthRoutineContentFingerprint(from: proposed)

    let res = try await client
        .from("strength_routines")
        .select(strengthRoutineFullDetailSelect())
        .eq("user_id", value: userId)
        .execute()

    let rows = try JSONDecoder.supabase().decode([StrengthRoutineFullRow].self, from: res.data)
    var matches: [(row: StrengthRoutineFullRow, items: [StrengthProgramItem], contentHash: String)] = []
    for row in rows {
        let items = programItemsFromRoutineRow(row)
        guard !items.isEmpty, structuresMatch(proposed, items) else { continue }
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
    let diff = buildDiffLines(
        proposed: proposed,
        routine: best.items,
        exerciseDisplayName: exerciseDisplayName
    )
    guard !diff.isEmpty else { return .none }
    return .prompt(StrengthRoutineOverwritePrompt(
        routineId: best.row.id,
        routineName: best.row.name,
        diffLines: diff
    ))
}

func applyStrengthRoutinePrescriptionUpdate(
    client: SupabaseClient,
    userId: UUID,
    routineId: Int64,
    exercises: [EditableExercise]
) async throws {
    let strengthItems = exercises.compactMap { $0.toStrengthItem() }
    guard !strengthItems.isEmpty else {
        throw NSError(
            domain: "StrengthRoutineOverwrite",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "No exercises to save."]
        )
    }

    struct RoutineExerciseIdRow: Decodable { let id: Int64 }

    let contentHash = strengthRoutineContentFingerprint(from: exercises)

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

    struct StrengthRoutineExerciseRowInsert: Encodable {
        let routine_id: Int64
        let exercise_id: Int64
        let order_index: Int
        let notes: String?
        let custom_name: String?
    }

    struct StrengthRoutineSetRowInsert: Encodable {
        let routine_exercise_id: Int64
        let set_number: Int
        let reps: Int?
        let weight_kg: Double?
        let rpe: Double?
        let rest_sec: Int?
        let notes: String?
    }

    for item in strengthItems.sorted(by: { $0.order_index < $1.order_index }) {
        let exRes = try await client
            .from("strength_routine_exercises")
            .insert(
                StrengthRoutineExerciseRowInsert(
                    routine_id: routineId,
                    exercise_id: item.exercise_id,
                    order_index: item.order_index,
                    notes: item.notes,
                    custom_name: item.custom_name
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
            StrengthRoutineSetRowInsert(
                routine_exercise_id: exerciseRowId,
                set_number: s.set_number,
                reps: s.reps,
                weight_kg: s.weight_kg,
                rpe: s.rpe,
                rest_sec: s.rest_sec,
                notes: s.notes
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
