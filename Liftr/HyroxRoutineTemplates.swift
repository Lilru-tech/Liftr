import CryptoKit
import Foundation
import SwiftUI
import Supabase

struct HyroxRoutineApplyPayload: Equatable {
    var exercises: [HyroxExerciseForm]
    var hyDivision: String
    var hyCategory: String
    var hyAgeGroup: String
    var hyOfficialTimeSec: String
    var hyPenaltyTimeSec: String
    var hyNoReps: String
    var hyRankOverall: String
    var hyRankCategory: String
    var hyAvgHR: String
    var hyMaxHR: String
}

extension SportForm {
    mutating func applyHyroxRoutineTemplate(_ p: HyroxRoutineApplyPayload) {
        sport = .hyrox
        hyExercises = p.exercises
        hyDivision = p.hyDivision
        hyCategory = p.hyCategory
        hyAgeGroup = p.hyAgeGroup
        hyOfficialTimeSec = p.hyOfficialTimeSec
        hyPenaltyTimeSec = p.hyPenaltyTimeSec
        hyNoReps = p.hyNoReps
        hyRankOverall = p.hyRankOverall
        hyRankCategory = p.hyRankCategory
        hyAvgHR = p.hyAvgHR
        hyMaxHR = p.hyMaxHR
        for idx in hyExercises.indices {
            hyExercises[idx].exerciseOrder = idx + 1
        }
    }
}

private struct HyroxRoutineFolderRow: Identifiable, Hashable, Decodable {
    let id: Int64
    let name: String
    let updated_at: Date?
    let sort_order: Int?
}

struct HyroxRoutineListRow: Identifiable, Hashable, Decodable {
    let id: Int64
    let name: String
    let updated_at: Date?
    let folder_id: Int64?
    let sort_order: Int?
}

struct HyroxRoutineExerciseWire: Decodable {
    let exercise_code: String
    let exercise_order: Int
    let zone_order: Int?
    let distance_m: Int?
    let reps: Int?
    let weight_kg: Double?
    let duration_sec: Int?
    let height_cm: Int?
    let implement_count: Int?
    let notes: String?
    let exercise_display_name: String?
}

struct HyroxRoutineDetailWire: Decodable {
    let id: Int64
    let name: String
    let division: String?
    let category: String?
    let age_group: String?
    let official_time_sec: Int?
    let penalty_time_sec: Int?
    let no_reps: Int?
    let rank_overall: Int?
    let rank_category: Int?
    let avg_hr: Int?
    let max_hr: Int?
    let hyrox_routine_exercises: [HyroxRoutineExerciseWire]?
}

func hyroxRoutineDetailSelect() -> String {
    "id,name,division,category,age_group,official_time_sec,penalty_time_sec,no_reps,rank_overall,rank_category,avg_hr,max_hr,hyrox_routine_exercises(exercise_code,exercise_order,zone_order,distance_m,reps,weight_kg,duration_sec,height_cm,implement_count,notes,exercise_display_name)"
}

func hyroxApplyPayloadFromDetail(_ detail: HyroxRoutineDetailWire) -> HyroxRoutineApplyPayload {
    let exs = (detail.hyrox_routine_exercises ?? []).sorted { $0.exercise_order < $1.exercise_order }
    let forms: [HyroxExerciseForm] = exs.map { w in
        let fields = HyroxExerciseFormatting.formFields(
            exerciseCode: w.exercise_code,
            exerciseDisplayName: w.exercise_display_name
        )
        func s(_ v: Int?) -> String { v.map(String.init) ?? "" }
        let wkg: String = {
            guard let x = w.weight_kg else { return "" }
            if x == floor(x) { return String(Int(x)) }
            return String(format: "%.1f", x)
        }()
        return HyroxExerciseForm(
            exerciseCode: fields.code,
            customDisplayName: fields.customDisplayName,
            exerciseOrder: w.exercise_order,
            zoneOrder: w.zone_order.map { max(1, $0) },
            distanceM: s(w.distance_m),
            reps: s(w.reps),
            weightKg: wkg,
            durationSec: s(w.duration_sec),
            heightCm: s(w.height_cm),
            implementCount: s(w.implement_count),
            notes: w.notes ?? ""
        )
    }
    return HyroxRoutineApplyPayload(
        exercises: forms,
        hyDivision: detail.division ?? "",
        hyCategory: detail.category ?? "",
        hyAgeGroup: detail.age_group ?? "",
        hyOfficialTimeSec: detail.official_time_sec.map(String.init) ?? "",
        hyPenaltyTimeSec: detail.penalty_time_sec.map(String.init) ?? "",
        hyNoReps: detail.no_reps.map(String.init) ?? "",
        hyRankOverall: detail.rank_overall.map(String.init) ?? "",
        hyRankCategory: detail.rank_category.map(String.init) ?? "",
        hyAvgHR: detail.avg_hr.map(String.init) ?? "",
        hyMaxHR: detail.max_hr.map(String.init) ?? ""
    )
}

enum HyroxRoutineNameValidator {
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
                .from("hyrox_routines")
                .select("id")
                .eq("user_id", value: userId)
                .eq("name", value: t)
                .eq("folder_id", value: Int(fid))
                .limit(1)
                .execute()
            rows = try JSONDecoder.supabase().decode([R].self, from: res.data)
        } else {
            let res = try await client
                .from("hyrox_routines")
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

struct HyroxRoutinePersistOutcome {
    let alsoHasAnotherRoutineWithSameProgram: Bool
}

private func hyroxIntOrNil(_ s: String) -> Int? {
    let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !t.isEmpty else { return nil }
    return Int(t)
}

private func hyroxParseDouble(_ s: String) -> Double? {
    let t = s.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespacesAndNewlines)
    return t.isEmpty ? nil : Double(t)
}

private func hyroxRoutineContentFingerprint(from sport: SportForm) -> String {
    guard sport.sport == .hyrox else { return "" }
    var lines: [String] = []
    lines.append(
        "H|\(sport.hyDivision)|\(sport.hyCategory)|\(sport.hyAgeGroup)|\(sport.hyOfficialTimeSec)|\(sport.hyPenaltyTimeSec)|\(sport.hyNoReps)|\(sport.hyRankOverall)|\(sport.hyRankCategory)|\(sport.hyAvgHR)|\(sport.hyMaxHR)"
    )
    let sorted = sport.hyExercises.sorted { $0.exerciseOrder < $1.exerciseOrder }
    for ex in sorted {
        let p = HyroxExerciseFormatting.persistedPayload(
            exerciseCode: ex.exerciseCode,
            customDisplayName: ex.customDisplayName,
            notes: ex.notes
        )
        lines.append(
            "\(p.code)|\(ex.exerciseOrder)|\(ex.zoneOrder.map { String(max(1, $0)) } ?? "")|\(p.displayName ?? "")|\(ex.distanceM)|\(ex.reps)|\(ex.weightKg)|\(ex.durationSec)|\(ex.heightCm)|\(ex.implementCount)|\(ex.notes)"
        )
    }
    let joined = lines.joined(separator: "\n")
    let digest = SHA256.hash(data: Data(joined.utf8))
    return digest.map { String(format: "%02x", $0) }.joined()
}

private func nextHyroxRoutineSortOrderForInsert(
    client: SupabaseClient,
    userId: UUID,
    folderId: Int64?
) async throws -> Int {
    struct R: Decodable { let sort_order: Int? }
    let res: [R]
    if let fid = folderId {
        let r = try await client
            .from("hyrox_routines")
            .select("sort_order")
            .eq("user_id", value: userId)
            .eq("folder_id", value: Int(fid))
            .order("sort_order", ascending: false)
            .limit(1)
            .execute()
        res = try JSONDecoder.supabase().decode([R].self, from: r.data)
    } else {
        let r = try await client
            .from("hyrox_routines")
            .select("sort_order")
            .eq("user_id", value: userId)
            .is("folder_id", value: nil)
            .order("sort_order", ascending: false)
            .limit(1)
            .execute()
        res = try JSONDecoder.supabase().decode([R].self, from: r.data)
    }
    return (res.first?.sort_order ?? 0) + 1
}

private func otherHyroxRoutinesWithSameContentCount(
    client: SupabaseClient,
    userId: UUID,
    folderId: Int64?,
    contentHash: String,
    excludingRoutineId: Int64
) async throws -> Int {
    struct R: Decodable { let id: Int64 }
    let res: [R]
    if let fid = folderId {
        let r = try await client
            .from("hyrox_routines")
            .select("id")
            .eq("user_id", value: userId)
            .eq("content_hash", value: contentHash)
            .eq("folder_id", value: Int(fid))
            .neq("id", value: Int(excludingRoutineId))
            .limit(8)
            .execute()
        res = try JSONDecoder.supabase().decode([R].self, from: r.data)
    } else {
        let r = try await client
            .from("hyrox_routines")
            .select("id")
            .eq("user_id", value: userId)
            .eq("content_hash", value: contentHash)
            .is("folder_id", value: nil)
            .neq("id", value: Int(excludingRoutineId))
            .limit(8)
            .execute()
        res = try JSONDecoder.supabase().decode([R].self, from: r.data)
    }
    return res.count
}

private func nextHyroxFolderSortOrderForInsert(client: SupabaseClient, userId: UUID) async throws -> Int {
    struct R: Decodable { let sort_order: Int? }
    let res = try await client
        .from("hyrox_routine_folders")
        .select("sort_order")
        .eq("user_id", value: userId)
        .order("sort_order", ascending: false)
        .limit(1)
        .execute()
    let rows = try JSONDecoder.supabase().decode([R].self, from: res.data)
    return (rows.first?.sort_order ?? 0) + 1
}

func insertHyroxRoutineTemplate(
    client: SupabaseClient,
    userId: UUID,
    name: String,
    folderId: Int64?,
    sport: SportForm,
    replaceRoutineId: Int64? = nil
) async throws -> HyroxRoutinePersistOutcome {
    guard sport.sport == .hyrox, !sport.hyExercises.isEmpty else {
        throw NSError(
            domain: "HyroxRoutine",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Add at least one Hyrox station before saving a routine."]
        )
    }

    struct RoutineIdRow: Decodable { let id: Int64 }

    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        return HyroxRoutinePersistOutcome(alsoHasAnotherRoutineWithSameProgram: false)
    }

    let contentHash = hyroxRoutineContentFingerprint(from: sport)

    if let rid = replaceRoutineId {
        _ = try await client
            .from("hyrox_routines")
            .delete()
            .eq("id", value: Int(rid))
            .eq("user_id", value: userId)
            .execute()
    }

    let nextSort = try await nextHyroxRoutineSortOrderForInsert(client: client, userId: userId, folderId: folderId)

    struct HyroxRoutineRowInsert: Encodable {
        let user_id: UUID
        let name: String
        let folder_id: Int64?
        let content_hash: String
        let sort_order: Int
        let division: String?
        let category: String?
        let age_group: String?
        let official_time_sec: Int?
        let penalty_time_sec: Int?
        let no_reps: Int?
        let rank_overall: Int?
        let rank_category: Int?
        let avg_hr: Int?
        let max_hr: Int?
    }

    let header = HyroxRoutineRowInsert(
        user_id: userId,
        name: trimmed,
        folder_id: folderId,
        content_hash: contentHash,
        sort_order: nextSort,
        division: sport.hyDivision.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
        category: sport.hyCategory.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
        age_group: sport.hyAgeGroup.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
        official_time_sec: hyroxIntOrNil(sport.hyOfficialTimeSec),
        penalty_time_sec: hyroxIntOrNil(sport.hyPenaltyTimeSec),
        no_reps: hyroxIntOrNil(sport.hyNoReps),
        rank_overall: hyroxIntOrNil(sport.hyRankOverall),
        rank_category: hyroxIntOrNil(sport.hyRankCategory),
        avg_hr: hyroxIntOrNil(sport.hyAvgHR),
        max_hr: hyroxIntOrNil(sport.hyMaxHR)
    )

    let headerRes = try await client
        .from("hyrox_routines")
        .insert(header, returning: .representation)
        .select("id")
        .limit(1)
        .execute()

    let idRows = try JSONDecoder.supabase().decode([RoutineIdRow].self, from: headerRes.data)
    guard let routineId = idRows.first?.id else {
        throw NSError(
            domain: "HyroxRoutine",
            code: 3,
            userInfo: [NSLocalizedDescriptionKey: "Routine was not saved (could not read the new routine)."]
        )
    }

    struct HyroxRoutineExerciseRowInsert: Encodable {
        let routine_id: Int64
        let exercise_code: String
        let exercise_order: Int
        let zone_order: Int?
        let distance_m: Int?
        let reps: Int?
        let weight_kg: Double?
        let duration_sec: Int?
        let height_cm: Int?
        let implement_count: Int?
        let notes: String?
        let exercise_display_name: String?
    }

    let ordered = sport.hyExercises.sorted { $0.exerciseOrder < $1.exerciseOrder }
    let exerciseRows: [HyroxRoutineExerciseRowInsert] = ordered.enumerated().map { idx, ex in
        let persisted = HyroxExerciseFormatting.persistedPayload(
            exerciseCode: ex.exerciseCode,
            customDisplayName: ex.customDisplayName,
            notes: ex.notes
        )
        let noteTrim = ex.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return HyroxRoutineExerciseRowInsert(
            routine_id: routineId,
            exercise_code: persisted.code,
            exercise_order: idx + 1,
            zone_order: ex.zoneOrder.map { max(1, $0) },
            distance_m: hyroxIntOrNil(ex.distanceM),
            reps: hyroxIntOrNil(ex.reps),
            weight_kg: hyroxParseDouble(ex.weightKg),
            duration_sec: hyroxIntOrNil(ex.durationSec),
            height_cm: hyroxIntOrNil(ex.heightCm),
            implement_count: hyroxIntOrNil(ex.implementCount),
            notes: noteTrim.isEmpty ? nil : noteTrim,
            exercise_display_name: persisted.displayName
        )
    }

    if !exerciseRows.isEmpty {
        _ = try await client.from("hyrox_routine_exercises").insert(exerciseRows).execute()
    }

    let dupCount = try await otherHyroxRoutinesWithSameContentCount(
        client: client,
        userId: userId,
        folderId: folderId,
        contentHash: contentHash,
        excludingRoutineId: routineId
    )
    return HyroxRoutinePersistOutcome(alsoHasAnotherRoutineWithSameProgram: dupCount > 0)
}

func updateHyroxRoutineTemplateInPlace(
    client: SupabaseClient,
    userId: UUID,
    routineId: Int64,
    sport: SportForm
) async throws -> HyroxRoutinePersistOutcome {
    guard sport.sport == .hyrox, !sport.hyExercises.isEmpty else {
        throw NSError(
            domain: "HyroxRoutine",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Add at least one Hyrox station before saving a routine."]
        )
    }

    struct FolderIdRow: Decodable { let folder_id: Int64? }
    let folderRes = try await client
        .from("hyrox_routines")
        .select("folder_id")
        .eq("id", value: Int(routineId))
        .eq("user_id", value: userId)
        .single()
        .execute()
    let folderRow = try JSONDecoder.supabase().decode(FolderIdRow.self, from: folderRes.data)

    let contentHash = hyroxRoutineContentFingerprint(from: sport)

    struct HyroxRoutineRowUpdate: Encodable {
        let content_hash: String
        let division: String?
        let category: String?
        let age_group: String?
        let official_time_sec: Int?
        let penalty_time_sec: Int?
        let no_reps: Int?
        let rank_overall: Int?
        let rank_category: Int?
        let avg_hr: Int?
        let max_hr: Int?
    }

    let headerUpdate = HyroxRoutineRowUpdate(
        content_hash: contentHash,
        division: sport.hyDivision.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
        category: sport.hyCategory.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
        age_group: sport.hyAgeGroup.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
        official_time_sec: hyroxIntOrNil(sport.hyOfficialTimeSec),
        penalty_time_sec: hyroxIntOrNil(sport.hyPenaltyTimeSec),
        no_reps: hyroxIntOrNil(sport.hyNoReps),
        rank_overall: hyroxIntOrNil(sport.hyRankOverall),
        rank_category: hyroxIntOrNil(sport.hyRankCategory),
        avg_hr: hyroxIntOrNil(sport.hyAvgHR),
        max_hr: hyroxIntOrNil(sport.hyMaxHR)
    )

    _ = try await client
        .from("hyrox_routines")
        .update(headerUpdate)
        .eq("id", value: Int(routineId))
        .eq("user_id", value: userId)
        .execute()

    _ = try await client
        .from("hyrox_routine_exercises")
        .delete()
        .eq("routine_id", value: Int(routineId))
        .execute()

    struct HyroxRoutineExerciseRowInsert: Encodable {
        let routine_id: Int64
        let exercise_code: String
        let exercise_order: Int
        let zone_order: Int?
        let distance_m: Int?
        let reps: Int?
        let weight_kg: Double?
        let duration_sec: Int?
        let height_cm: Int?
        let implement_count: Int?
        let notes: String?
        let exercise_display_name: String?
    }

    let ordered = sport.hyExercises.sorted { $0.exerciseOrder < $1.exerciseOrder }
    let exerciseRows: [HyroxRoutineExerciseRowInsert] = ordered.enumerated().map { idx, ex in
        let persisted = HyroxExerciseFormatting.persistedPayload(
            exerciseCode: ex.exerciseCode,
            customDisplayName: ex.customDisplayName,
            notes: ex.notes
        )
        let noteTrim = ex.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return HyroxRoutineExerciseRowInsert(
            routine_id: routineId,
            exercise_code: persisted.code,
            exercise_order: idx + 1,
            zone_order: ex.zoneOrder.map { max(1, $0) },
            distance_m: hyroxIntOrNil(ex.distanceM),
            reps: hyroxIntOrNil(ex.reps),
            weight_kg: hyroxParseDouble(ex.weightKg),
            duration_sec: hyroxIntOrNil(ex.durationSec),
            height_cm: hyroxIntOrNil(ex.heightCm),
            implement_count: hyroxIntOrNil(ex.implementCount),
            notes: noteTrim.isEmpty ? nil : noteTrim,
            exercise_display_name: persisted.displayName
        )
    }

    if !exerciseRows.isEmpty {
        _ = try await client.from("hyrox_routine_exercises").insert(exerciseRows).execute()
    }

    let dupCount = try await otherHyroxRoutinesWithSameContentCount(
        client: client,
        userId: userId,
        folderId: folderRow.folder_id,
        contentHash: contentHash,
        excludingRoutineId: routineId
    )
    return HyroxRoutinePersistOutcome(alsoHasAnotherRoutineWithSameProgram: dupCount > 0)
}

func hyroxRoutineUserFacingSaveError(_ error: Error) -> String {
    let ns = error as NSError
    if ns.domain == "HyroxRoutine",
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

private extension String {
    var nilIfEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
struct HyroxRoutinesPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var app: AppState
    let onApply: (HyroxRoutineApplyPayload) -> Void

    @State private var routines: [HyroxRoutineListRow] = []
    @State private var folders: [HyroxRoutineFolderRow] = []
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
    @AppStorage("hyroxRoutinesSheet.collapsedFolderIdsCSV") private var collapsedFolderIdsCSV: String = ""
    @AppStorage("hyroxRoutinesSheet.unfiledSectionCollapsed") private var storedUnfiledCollapsed: Bool = false
    @State private var routineSearchText: String = ""
    @State private var showDuplicateSheet = false
    @State private var duplicateSourceRoutine: HyroxRoutineListRow?
    @State private var duplicateNameDraft: String = ""
    @State private var duplicateTargetFolderId: Int64? = nil
    @State private var duplicateError: String?
    @State private var shareRoutineChatToken: HyroxShareRoutineChatToken?
    @State private var shareRoutineBuildError: String?
    @State private var routinePreviewToken: RoutinePreviewToken?
    @State private var previewBuildError: String?
    @State private var routinePendingEdit: HyroxRoutineListRow?

    private struct HyroxShareRoutineChatToken: Identifiable {
        let id = UUID()
        let snapshot: RoutineShareSnapshot
    }

    private struct RoutinePreviewToken: Identifiable {
        let id = UUID()
        let row: HyroxRoutineListRow
        let snapshot: RoutineShareSnapshot
    }

    private var sortedFolders: [HyroxRoutineFolderRow] {
        folders.sorted { a, b in
            let ao = Int64(a.sort_order ?? 0)
            let bo = Int64(b.sort_order ?? 0)
            if ao != bo { return ao < bo }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    private var displayRoutines: [HyroxRoutineListRow] {
        let q = routineSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return routines }
        return routines.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    private var displayFolders: [HyroxRoutineFolderRow] {
        let q = routineSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return sortedFolders }
        return sortedFolders.filter { f in
            f.name.localizedCaseInsensitiveContains(q)
                || displayRoutines.contains(where: { $0.folder_id == f.id })
        }
    }

    private func routinesUnfiled() -> [HyroxRoutineListRow] {
        displayRoutines
            .filter { $0.folder_id == nil }
            .sorted { a, b in
                let ao = Int64(a.sort_order ?? 0)
                let bo = Int64(b.sort_order ?? 0)
                if ao != bo { return ao < bo }
                return (a.updated_at ?? .distantPast) > (b.updated_at ?? .distantPast)
            }
    }

    private func routines(inFolderId fid: Int64) -> [HyroxRoutineListRow] {
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
                            Text("No saved routines yet. Save one when you publish a Hyrox workout.")
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
                                        let snap = try await buildHyroxRoutineShareSnapshot(row: row)
                                        await MainActor.run { routinePreviewToken = nil }
                                        let chatToken = HyroxShareRoutineChatToken(snapshot: snap)
                                        DispatchQueue.main.async {
                                            shareRoutineChatToken = chatToken
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
            EditSavedHyroxRoutineSheet(
                routineId: row.id,
                routineName: row.name,
                onClose: { routinePendingEdit = nil },
                onSaved: {
                    routinePendingEdit = nil
                    Task { await loadRoutines() }
                }
            )
            .gradientBG()
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
    private func folderSection(_ folder: HyroxRoutineFolderRow) -> some View {
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
    private func routineCard(_ row: HyroxRoutineListRow) -> some View {
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
                            let snap = try await buildHyroxRoutineShareSnapshot(row: row)
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
                            let snap = try await buildHyroxRoutineShareSnapshot(row: row)
                            await MainActor.run { shareRoutineChatToken = HyroxShareRoutineChatToken(snapshot: snap) }
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

    private func buildHyroxRoutineShareSnapshot(row: HyroxRoutineListRow) async throws -> RoutineShareSnapshot {
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
            .from("hyrox_routines")
            .select(hyroxRoutineDetailSelect())
            .eq("id", value: Int(row.id))
            .single()
            .execute()
        let json = String(decoding: res.data, as: UTF8.self)
        let detail = try JSONDecoder.supabase().decode(HyroxRoutineDetailWire.self, from: res.data)
        let rows = (detail.hyrox_routine_exercises ?? []).sorted { $0.exercise_order < $1.exercise_order }
        let exerciseCount = rows.count
        let previewExerciseName: String? = rows.first.map {
            HyroxExerciseFormatting.label(code: $0.exercise_code, displayName: $0.exercise_display_name, notes: $0.notes)
        }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let updated = row.updated_at.map { iso.string(from: $0) }
        return RoutineShareSnapshot(
            v: 1,
            type: "routine_share",
            routine_kind: "hyrox",
            name: row.name,
            routine_id: row.id,
            updated_at: updated,
            owner_user_id: session.user.id,
            owner_username: prof.username,
            owner_avatar_url: prof.avatar_url,
            share_nonce: UUID().uuidString,
            detail_json: json,
            exercise_count: exerciseCount > 0 ? exerciseCount : nil,
            total_sets: nil,
            preview_exercise_name: previewExerciseName
        )
    }

    private func orderedRoutinesInGroup(_ row: HyroxRoutineListRow) -> [HyroxRoutineListRow] {
        routines
            .filter { $0.folder_id == row.folder_id }
            .sorted { a, b in
                let ao = Int64(a.sort_order ?? 0)
                let bo = Int64(b.sort_order ?? 0)
                if ao != bo { return ao < bo }
                return a.id < b.id
            }
    }

    private func routineNeighborInfo(_ row: HyroxRoutineListRow) -> (list: [HyroxRoutineListRow], index: Int)? {
        let list = orderedRoutinesInGroup(row)
        guard let i = list.firstIndex(where: { $0.id == row.id }) else { return nil }
        return (list, i)
    }

    private func swapRoutineSortOrder(_ row: HyroxRoutineListRow, withOffset: Int) async {
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
                .from("hyrox_routines")
                .update(P(sort_order: bo))
                .eq("id", value: Int(a.id))
                .execute()
            _ = try await client
                .from("hyrox_routines")
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
                .from("hyrox_routine_folders")
                .update(P(sort_order: bo))
                .eq("id", value: Int(a.id))
                .execute()
            _ = try await client
                .from("hyrox_routine_folders")
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
            let taken = try await HyroxRoutineNameValidator.isRoutineNameTaken(
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
                .from("hyrox_routines")
                .select(hyroxRoutineDetailSelect())
                .eq("id", value: Int(src.id))
                .single()
                .execute()
            let detail = try JSONDecoder.supabase().decode(HyroxRoutineDetailWire.self, from: res.data)
            let payload = hyroxApplyPayloadFromDetail(detail)
            guard !payload.exercises.isEmpty else {
                await MainActor.run { duplicateError = "This routine has no exercises to copy." }
                return
            }
            var sport = SportForm()
            sport.applyHyroxRoutineTemplate(payload)
            _ = try await insertHyroxRoutineTemplate(
                client: client,
                userId: session.user.id,
                name: name,
                folderId: duplicateTargetFolderId,
                sport: sport,
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
                .from("hyrox_routines")
                .select("id,name,updated_at,folder_id,sort_order")
                .order("sort_order", ascending: true)
                .order("name", ascending: true)
                .execute()
            let fRes = try await client
                .from("hyrox_routine_folders")
                .select("id,name,updated_at,sort_order")
                .order("sort_order", ascending: true)
                .order("name", ascending: true)
                .execute()
            let rRows = try JSONDecoder.supabase().decode([HyroxRoutineListRow].self, from: rRes.data)
            let fRows = try JSONDecoder.supabase().decode([HyroxRoutineFolderRow].self, from: fRes.data)
            await MainActor.run {
                routines = rRows
                folders = fRows
            }
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
        }
    }

    private func applyRoutine(id: Int64, dismissRoutinesPicker: Bool = true) async {
        await MainActor.run { errorMessage = nil }
        do {
            let client = SupabaseManager.shared.client
            let res = try await client
                .from("hyrox_routines")
                .select(hyroxRoutineDetailSelect())
                .eq("id", value: Int(id))
                .single()
                .execute()
            let detail = try JSONDecoder.supabase().decode(HyroxRoutineDetailWire.self, from: res.data)
            let payload = hyroxApplyPayloadFromDetail(detail)
            guard !payload.exercises.isEmpty else {
                await MainActor.run { errorMessage = "This routine has no exercises." }
                return
            }
            await MainActor.run {
                onApply(payload)
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
                .from("hyrox_routines")
                .delete()
                .eq("id", value: Int(id))
                .execute()
            await loadRoutines()
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
        }
    }

    private func moveRoutine(_ row: HyroxRoutineListRow, to folderId: Int64?) async {
        await MainActor.run { errorMessage = nil }
        if row.folder_id == folderId { return }
        do {
            let client = SupabaseManager.shared.client
            let session = try await client.auth.session
            let taken = try await HyroxRoutineNameValidator.isRoutineNameTaken(
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
            let nextOrder = try await nextHyroxRoutineSortOrderForInsert(
                client: client,
                userId: session.user.id,
                folderId: folderId
            )
            struct Patch: Encodable { let folder_id: Int64?; let sort_order: Int }
            _ = try await client
                .from("hyrox_routines")
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
            let next = try await nextHyroxFolderSortOrderForInsert(client: client, userId: session.user.id)
            struct Ins: Encodable { let user_id: UUID; let name: String; let sort_order: Int }
            _ = try await client
                .from("hyrox_routine_folders")
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
                .from("hyrox_routine_folders")
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
                .from("hyrox_routine_folders")
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
                .from("hyrox_routine_folders")
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
                if lower.contains("foreign key") || lower.contains("hyrox_routines") || lower.contains("violat") {
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
            let taken = try await HyroxRoutineNameValidator.isRoutineNameTaken(
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
                .from("hyrox_routines")
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
