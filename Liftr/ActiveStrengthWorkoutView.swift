import SwiftUI
import Supabase
import Network
import AVFoundation
import AudioToolbox
import UIKit
import ImageIO

#if DEBUG
private let dualStrengthSessionDebugLog = true
private func dualStrengthDebug(_ message: String) {
    guard dualStrengthSessionDebugLog else { return }
    print("[DualStrengthSession] \(message)")
}
#else
private func dualStrengthDebug(_ message: String) {}
#endif

private struct NavStripScrollEdgeFades: Equatable {
    var showLeading: Bool
    var showTrailing: Bool
}

struct ActiveStrengthWorkoutView: View {
    let workoutId: Int
    let dualGuestWorkoutId: Int?
    let dualGuestAvatarURL: String?
    let dualGuest2WorkoutId: Int?
    let dualGuest2AvatarURL: String?
    let dualHostAvatarURL: String?

    private static let elborblaUsernameNormalized = "elborbla"
    private static let elborblaCelebrationBasename = "elborbla_celebration"

    init(
        workoutId: Int,
        dualGuestWorkoutId: Int? = nil,
        dualGuestAvatarURL: String? = nil,
        dualGuest2WorkoutId: Int? = nil,
        dualGuest2AvatarURL: String? = nil,
        dualHostAvatarURL: String? = nil
    ) {
        self.workoutId = workoutId
        self.dualGuestWorkoutId = dualGuestWorkoutId
        self.dualGuestAvatarURL = dualGuestAvatarURL
        self.dualGuest2WorkoutId = dualGuest2WorkoutId
        self.dualGuest2AvatarURL = dualGuest2AvatarURL
        self.dualHostAvatarURL = dualHostAvatarURL
        #if DEBUG
        dualStrengthDebug(
            "init workoutId=\(workoutId) guestWid=\(dualGuestWorkoutId.map(String.init) ?? "nil") "
                + "guest2Wid=\(dualGuest2WorkoutId.map(String.init) ?? "nil") "
                + "guestAvatarLen=\(dualGuestAvatarURL?.count ?? 0) hostAvatarLen=\(dualHostAvatarURL?.count ?? 0) "
                + "isDualMode=\(dualGuestWorkoutId != nil)"
        )
        #endif
    }

    private enum StrengthLaneKind {
        case host
        case guest
        case guest2
    }

    private enum EditMetricFocusField: Hashable {
        case reps
        case weight
        case rest
        case rpe
    }

    private struct ExerciseRow: Decodable, Identifiable {
        let id: Int
        let exercise_id: Int64
        let order_index: Int
        let superset_group_id: UUID?
        let superset_position: Int?
        let notes: String?
        let custom_name: String?
        let target_sets: Int?
        let exercise_name: String?
    }
    
    private struct SetRow: Identifiable, Decodable {
        let id: Int
        let workout_exercise_id: Int
        let set_number: Int
        let order_index: Int?
        let reps: Int?
        let weight_kg: Decimal?
        let rpe: Decimal?
        let rest_sec: Int?
        let weight_segments: [StrengthWeightSegWire]?
        let configId: Int
        let segmentsInRow: Int

        enum CodingKeys: String, CodingKey {
            case id, workout_exercise_id, set_number, order_index, reps, weight_kg, rpe, rest_sec, weight_segments
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(Int.self, forKey: .id)
            workout_exercise_id = try c.decode(Int.self, forKey: .workout_exercise_id)
            set_number = try c.decode(Int.self, forKey: .set_number)
            order_index = try c.decodeIfPresent(Int.self, forKey: .order_index)
            reps = try c.decodeIfPresent(Int.self, forKey: .reps)
            weight_kg = try c.decodeIfPresent(Decimal.self, forKey: .weight_kg)
            rpe = try c.decodeIfPresent(Decimal.self, forKey: .rpe)
            rest_sec = try c.decodeIfPresent(Int.self, forKey: .rest_sec)
            weight_segments = try c.decodeIfPresent([StrengthWeightSegWire].self, forKey: .weight_segments)
            let segmentCount = weight_segments?.count ?? 0
            segmentsInRow = segmentCount >= 2 ? segmentCount : 1
            configId = id
        }

        init(
            id: Int,
            workout_exercise_id: Int,
            set_number: Int,
            order_index: Int? = nil,
            reps: Int?,
            weight_kg: Decimal?,
            rpe: Decimal?,
            rest_sec: Int?,
            weight_segments: [StrengthWeightSegWire]?,
            configId: Int,
            segmentsInRow: Int
        ) {
            self.id = id
            self.workout_exercise_id = workout_exercise_id
            self.set_number = set_number
            self.order_index = order_index
            self.reps = reps
            self.weight_kg = weight_kg
            self.rpe = rpe
            self.rest_sec = rest_sec
            self.weight_segments = weight_segments
            self.configId = configId
            self.segmentsInRow = segmentsInRow
        }
    }

    private struct PerformedSet {
        let reps: Int?
        let weight_kg: Decimal?
        let rpe: Decimal?
        let rest_sec: Int?
        let configId: Int
        let segmentsInRow: Int
        let weight_segments: [StrengthWeightSegWire]?
    }

    private struct ActiveExerciseSetupSet: Identifiable {
        let id = UUID()
        var repsText: String = "10"
        var weightText: String = "0"
        var rpeText: String = ""
        var restText: String = "60"
        var dropSegments: [StrengthEditorSegment] = []
    }

    private struct ActiveExerciseSetupExercise: Identifiable {
        let id = UUID()
        let exercise: Exercise
        var sets: [ActiveExerciseSetupSet] = [ActiveExerciseSetupSet()]
    }

    private struct ActiveExerciseSetupParsedSet {
        let reps: Int?
        let weightKg: Decimal?
        let rpe: Decimal?
        let restSec: Int?
        let weightSegments: [StrengthWeightSegWire]?
        var segmentsInRow: Int { max(1, weightSegments?.count ?? 1) }
    }

    private struct ActiveWorkoutExerciseInsert: Encodable {
        let workout_id: Int
        let exercise_id: Int
        let order_index: Int
        let superset_group_id: UUID?
        let superset_position: Int?
        let notes: String?
        let custom_name: String?
    }

    private struct ActiveWorkoutExerciseInsertedId: Decodable {
        let id: Int
    }

    private struct ActiveWorkoutSetInsert: Encodable {
        let workout_exercise_id: Int
        let set_number: Int
        let order_index: Int
        let reps: Int?
        let weight_kg: Double?
        let rpe: Double?
        let rest_sec: Int?
        let weight_segments: [StrengthWeightSegWire]?
    }

    private struct ActiveWorkoutExerciseOrderPatch: Encodable {
        let order_index: Int
        let superset_group_id: UUID?
        let superset_position: Int?

        private enum CodingKeys: String, CodingKey {
            case order_index, superset_group_id, superset_position
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(order_index, forKey: .order_index)
            if let superset_group_id {
                try container.encode(superset_group_id, forKey: .superset_group_id)
            } else {
                try container.encodeNil(forKey: .superset_group_id)
            }
            if let superset_position {
                try container.encode(superset_position, forKey: .superset_position)
            } else {
                try container.encodeNil(forKey: .superset_position)
            }
        }
    }

    private struct NavStripBlock: Identifiable {
        let id: String
        let exerciseIndices: [Int]

        var isSuperset: Bool {
            exerciseIndices.count > 1
        }
    }

    private struct StrengthDisplayGroup: Identifiable {
        let id: String
        let supersetGroupId: UUID?
        let exerciseIndices: [Int]

        var isSuperset: Bool {
            supersetGroupId != nil && exerciseIndices.count > 1
        }
    }

    private struct NavRestOverlay {
        let seconds: Int
        let plannedTotalSeconds: Int
    }

    private struct SupersetGroupRestState {
        let isActive: Bool
        let seconds: Int
        let anchorExerciseId: Int?
    }

    private enum SupersetSetAction {
        case add
        case remove
    }

    private struct WorkoutSanitizePatch: Encodable {
        let ended_at: Date?
    }

    private struct FetchDualLinkedStrengthParams: Encodable {
        let p_workout_id: Int64
    }

    private struct DualLinkedStrengthBundle: Decodable {
        let exercises: [DualLinkedStrengthExWire]
        let sets: [SetRow]
    }

    private struct DualLinkedStrengthExWire: Decodable {
        let id: Int
        let exercise_id: Int64
        let order_index: Int
        let superset_group_id: UUID?
        let superset_position: Int?
        let notes: String?
        let custom_name: String?
        let target_sets: Int?
        let exercises: ExName?
        struct ExName: Decodable { let name: String? }
    }
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var app: AppState
    @AppStorage("activeStrengthNavHintSeen") private var activeStrengthNavHintSeen = false

    @State private var restEndDate: Date? = nil
    @State private var restEndDateByExercise: [Int: Date] = [:]
    @State private var restTotalPlannedByExercise: [Int: Int] = [:]
    @State private var gRestTotalPlannedByExercise: [Int: Int] = [:]
    @State private var g2RestTotalPlannedByExercise: [Int: Int] = [:]
    @State private var exercises: [ExerciseRow] = []
    @State private var setsByExercise: [Int: [SetRow]] = [:]
    @State private var loading = false
    @State private var error: String?
    @State private var startSyncStatus: WorkoutStartSyncStatus = .idle
    @State private var guestDataError: String?
    @State private var isSaving = false
    @State private var showCountdown = true
    @State private var strengthWorkoutSessionStart: Date? = nil
    @State private var strengthWorkoutElapsedTick: UInt32 = 0
    @State private var isSessionPaused = false
    @State private var accumulatedPausedSeconds: Int = 0
    @State private var sessionPauseBegan: Date? = nil
    @State private var currentExerciseIndex: Int = 0
    @State private var pagerDisplayIndexHost: Int = 0
    @State private var pagerDisplayIndexGuest: Int = 0
    @State private var pagerDisplayIndexGuest2: Int = 0
    @State private var navEmphasisLockExerciseIdHost: Int? = nil
    @State private var navEmphasisLockExerciseIdGuest: Int? = nil
    @State private var navEmphasisLockExerciseIdGuest2: Int? = nil
    @State private var guestCurrentExerciseIndex: Int = 0
    @State private var currentSetIndex: Int = 0
    @State private var isResting = false
    @State private var remainingRest: Int = 0
    @State private var performedSetsByExercise: [Int: [PerformedSet]] = [:]
    @State private var showEditSheet = false
    @State private var applyEditToRemainingSets = false
    @State private var editRepsText: String = ""
    @State private var showFinishEarlyConfirm = false
    @State private var showDualIncompleteFinishConfirm = false
    @State private var editWeightText: String = ""
    @State private var editRestText: String = ""
    @State private var editRpeText: String = ""
    @State private var editDropSegments: [StrengthWeightSegWire] = []
    @State private var showConvertToNormalSheet: Bool = false
    @State private var convertToNormalRepsText: String = ""
    @State private var convertToNormalWeightText: String = ""
    @FocusState private var editMetricFocus: EditMetricFocusField?
    @State private var dragOffsetY: CGFloat = 0
    @State private var isTransitioningExercise: Bool = false
    @State private var currentSetIndexByExercise: [Int: Int] = [:]
    @State private var visitedSetIndexByExercise: [Int: Int] = [:]
    @State private var visitedSupersetRoundByGroupId: [String: Int] = [:]
    @State private var gVisitedSetIndexByExercise: [Int: Int] = [:]
    @State private var g2VisitedSetIndexByExercise: [Int: Int] = [:]
    @State private var gVisitedSupersetRoundByGroupId: [String: Int] = [:]
    @State private var g2VisitedSupersetRoundByGroupId: [String: Int] = [:]
    @State private var editTargetExpandedIndex: Int? = nil
    @State private var editTargetExerciseId: Int? = nil
    @State private var editDraftsByExerciseId: [Int: EditSetDraft] = [:]

    private struct EditSetDraft {
        var repsText: String
        var weightText: String
        var restText: String
        var rpeText: String
        var dropSegments: [StrengthWeightSegWire]
    }
    @State private var remainingRestByExercise: [Int: Int] = [:]
    @State private var isRestingByExercise: [Int: Bool] = [:]
    @State private var gExercises: [ExerciseRow] = []
    @State private var gSetsByExercise: [Int: [SetRow]] = [:]
    @State private var gCurrentSetIndex: Int = 0
    @State private var gPerformedSetsByExercise: [Int: [PerformedSet]] = [:]
    @State private var gCurrentSetIndexByExercise: [Int: Int] = [:]
    @State private var gRemainingRestByExercise: [Int: Int] = [:]
    @State private var gIsRestingByExercise: [Int: Bool] = [:]
    @State private var gRestEndDateByExercise: [Int: Date] = [:]
    @State private var gRestEndDate: Date? = nil
    @State private var gIsResting: Bool = false
    @State private var gRemainingRest: Int = 0
    @State private var gDidFireRestFinishedFeedback: Bool = false
    @State private var g2Exercises: [ExerciseRow] = []
    @State private var g2SetsByExercise: [Int: [SetRow]] = [:]
    @State private var g2CurrentExerciseIndex: Int = 0
    @State private var g2CurrentSetIndex: Int = 0
    @State private var g2PerformedSetsByExercise: [Int: [PerformedSet]] = [:]
    @State private var g2CurrentSetIndexByExercise: [Int: Int] = [:]
    @State private var g2RemainingRestByExercise: [Int: Int] = [:]
    @State private var g2IsRestingByExercise: [Int: Bool] = [:]
    @State private var g2RestEndDateByExercise: [Int: Date] = [:]
    @State private var g2RestEndDate: Date? = nil
    @State private var g2IsResting: Bool = false
    @State private var g2RemainingRest: Int = 0
    @State private var g2DidFireRestFinishedFeedback: Bool = false
    @State private var guest2DataError: String?
    @State private var dualFocusLane: StrengthLaneKind = .host
    @State private var editTargetLane: StrengthLaneKind = .host
    @State private var toastMessage: String? = nil
    @State private var restAudioPlayer: AVAudioPlayer? = nil
    @State private var didFireRestFinishedFeedback: Bool = false
    @State private var beepWorkItem: DispatchWorkItem? = nil
    @State private var isBeeping: Bool = false
    @State private var navExercisePopoverIndex: String? = nil
    @State private var strengthNavStripWaveIndex: Int? = nil
    @State private var strengthNavStripWaveTask: Task<Void, Never>?
    @State private var navStripScrollEdgeFades = NavStripScrollEdgeFades(showLeading: false, showTrailing: false)
    @State private var showElborblaCelebration = false
    @State private var quickRestPresets: [Int] = StrengthRestPresetService.defaultPresets
    @State private var strengthFinishDeferral: StrengthFinishDeferral?
    @State private var showActiveExercisePicker = false
    @State private var showActiveExerciseSetup = false
    @State private var activeExerciseSetupLane: StrengthLaneKind = .host
    @State private var activeExerciseSetupDrafts: [ActiveExerciseSetupExercise] = []
    @State private var activeExerciseSetupError: String?
    @State private var isPersistingActiveExerciseEdit = false
    @State private var showDeleteExerciseConfirm = false
    @State private var deleteExerciseCandidate: ExerciseRow?
    @State private var deleteExerciseLane: StrengthLaneKind = .host
    @State private var showSupersetSetActionConfirm = false
    @State private var supersetSetActionCandidate: ExerciseRow?
    @State private var supersetSetActionLane: StrengthLaneKind = .host
    @State private var pendingSupersetSetAction: SupersetSetAction?
    private let swipeThreshold: CGFloat = 110

    private struct StrengthFinishDeferral: Identifiable {
        let id = UUID()
        let exList: [ExerciseRow]
        let performedMap: [Int: [PerformedSet]]
        let guestExList: [ExerciseRow]
        let guestPerformedMap: [Int: [PerformedSet]]
        let guestWorkoutId: Int?
        let guest2ExList: [ExerciseRow]
        let guest2PerformedMap: [Int: [PerformedSet]]
        let guest2WorkoutId: Int?
        let prompt: StrengthRoutineOverwritePrompt
        let editableForRoutine: [EditableExercise]
    }
    private let restTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    private var isDualMode: Bool { dualGuestWorkoutId != nil }
    private var isTripleMode: Bool { dualGuest2WorkoutId != nil }

    private var orderedExercises: [ExerciseRow] {
        exercises.sorted { $0.order_index < $1.order_index }
    }

    private var orderedGuestExercises: [ExerciseRow] {
        gExercises.sorted { $0.order_index < $1.order_index }
    }

    private var orderedGuest2Exercises: [ExerciseRow] {
        g2Exercises.sorted { $0.order_index < $1.order_index }
    }

    private func orderedExercises(lane: StrengthLaneKind) -> [ExerciseRow] {
        switch lane {
        case .host: return orderedExercises
        case .guest: return orderedGuestExercises
        case .guest2: return orderedGuest2Exercises
        }
    }

    private func navEmphasisTargetExerciseId(lane: StrengthLaneKind) -> Int? {
        let list = orderedExercises(lane: lane)
        guard !list.isEmpty else { return nil }
        switch lane {
        case .host:
            if let id = navEmphasisLockExerciseIdHost { return id }
            let idx = pagerDisplayIndexHost
            guard idx >= 0, idx < list.count else { return nil }
            return list[idx].id
        case .guest:
            if let id = navEmphasisLockExerciseIdGuest { return id }
            let idx = pagerDisplayIndexGuest
            guard idx >= 0, idx < list.count else { return nil }
            return list[idx].id
        case .guest2:
            if let id = navEmphasisLockExerciseIdGuest2 { return id }
            let idx = pagerDisplayIndexGuest2
            guard idx >= 0, idx < list.count else { return nil }
            return list[idx].id
        }
    }

    private var currentExercise: ExerciseRow? {
        guard !orderedExercises.isEmpty,
              currentExerciseIndex >= 0,
              currentExerciseIndex < orderedExercises.count
        else { return nil }
        return orderedExercises[currentExerciseIndex]
    }

    private var currentGuestExercise: ExerciseRow? {
        guard isDualMode,
              !orderedGuestExercises.isEmpty,
              guestCurrentExerciseIndex >= 0,
              guestCurrentExerciseIndex < orderedGuestExercises.count
        else { return nil }
        return orderedGuestExercises[guestCurrentExerciseIndex]
    }

    private var currentGuest2Exercise: ExerciseRow? {
        guard isTripleMode,
              !orderedGuest2Exercises.isEmpty,
              g2CurrentExerciseIndex >= 0,
              g2CurrentExerciseIndex < orderedGuest2Exercises.count
        else { return nil }
        return orderedGuest2Exercises[g2CurrentExerciseIndex]
    }

    private var mainDisplayLane: StrengthLaneKind {
        guard isDualMode else { return .host }
        return dualFocusLane
    }

    private var pagerExerciseIndex: Int {
        if !isDualMode { return pagerDisplayIndexHost }
        switch mainDisplayLane {
        case .host: return pagerDisplayIndexHost
        case .guest: return pagerDisplayIndexGuest
        case .guest2: return pagerDisplayIndexGuest2
        }
    }

    private var pagerOrdered: [ExerciseRow] {
        orderedExercises(lane: mainDisplayLane)
    }

    private func strengthDisplayGroups(lane: StrengthLaneKind) -> [StrengthDisplayGroup] {
        let list = orderedExercises(lane: lane)
        var groups: [StrengthDisplayGroup] = []
        var idx = 0
        while idx < list.count {
            let ex = list[idx]
            guard let groupId = ex.superset_group_id else {
                groups.append(StrengthDisplayGroup(id: "exercise-\(ex.id)", supersetGroupId: nil, exerciseIndices: [idx]))
                idx += 1
                continue
            }
            var indices = [idx]
            var nextIdx = idx + 1
            while nextIdx < list.count, list[nextIdx].superset_group_id == groupId {
                indices.append(nextIdx)
                nextIdx += 1
            }
            if indices.count > 1 {
                groups.append(
                    StrengthDisplayGroup(
                        id: "superset-\(groupId.uuidString)-\(idx)",
                        supersetGroupId: groupId,
                        exerciseIndices: indices
                    )
                )
            } else {
                groups.append(StrengthDisplayGroup(id: "exercise-\(ex.id)", supersetGroupId: nil, exerciseIndices: [idx]))
            }
            idx = nextIdx
        }
        return groups
    }

    private func displayGroup(forExerciseIndex exerciseIndex: Int, lane: StrengthLaneKind) -> StrengthDisplayGroup? {
        strengthDisplayGroups(lane: lane).first { $0.exerciseIndices.contains(exerciseIndex) }
    }

    private func displayGroupIndex(forExerciseIndex exerciseIndex: Int, lane: StrengthLaneKind) -> Int? {
        let groups = strengthDisplayGroups(lane: lane)
        return groups.firstIndex { $0.exerciseIndices.contains(exerciseIndex) }
    }

    private func pagerAnchorExerciseIndex(for exerciseIndex: Int, lane: StrengthLaneKind) -> Int {
        displayGroup(forExerciseIndex: exerciseIndex, lane: lane)?.exerciseIndices.first ?? exerciseIndex
    }

    private var pagerCurrentDisplayGroup: StrengthDisplayGroup? {
        displayGroup(forExerciseIndex: pagerExerciseIndex, lane: mainDisplayLane)
    }

    private var pagerCurrentExercise: ExerciseRow? {
        let list = pagerOrdered
        let anchorIdx = pagerAnchorExerciseIndex(for: pagerExerciseIndex, lane: mainDisplayLane)
        guard !list.isEmpty,
              anchorIdx >= 0,
              anchorIdx < list.count
        else { return nil }
        return list[anchorIdx]
    }

    private var pagerNextExercise: ExerciseRow? {
        let lane = mainDisplayLane
        let groups = strengthDisplayGroups(lane: lane)
        guard let gi = displayGroupIndex(forExerciseIndex: pagerExerciseIndex, lane: lane),
              gi + 1 < groups.count
        else { return nil }
        let list = pagerOrdered
        let nextIdx = groups[gi + 1].exerciseIndices.first ?? 0
        guard nextIdx >= 0, nextIdx < list.count else { return nil }
        return list[nextIdx]
    }

    private var pagerPreviousExercise: ExerciseRow? {
        let lane = mainDisplayLane
        let groups = strengthDisplayGroups(lane: lane)
        guard let gi = displayGroupIndex(forExerciseIndex: pagerExerciseIndex, lane: lane),
              gi > 0
        else { return nil }
        let list = pagerOrdered
        let prevIdx = groups[gi - 1].exerciseIndices.first ?? 0
        guard prevIdx >= 0, prevIdx < list.count else { return nil }
        return list[prevIdx]
    }

    private var nextExercise: ExerciseRow? {
        let nextIndex = currentExerciseIndex + 1
        guard nextIndex >= 0,
              nextIndex < orderedExercises.count
        else { return nil }
        return orderedExercises[nextIndex]
    }

    private var previousExercise: ExerciseRow? {
        let prevIndex = currentExerciseIndex - 1
        guard prevIndex >= 0,
              prevIndex < orderedExercises.count
        else { return nil }
        return orderedExercises[prevIndex]
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.clear
                    .gradientBG()
                
                Group {
                    if loading {
                        ProgressView("Loading workout…")
                    } else if let error, exercises.isEmpty {
                        VStack(spacing: 12) {
                            Text("Error").font(.headline)
                            Text(error).foregroundStyle(.secondary)
                            Button("Retry") { Task { await load() } }
                                .buttonStyle(.borderedProminent)
                            Button("Close") { dismiss() }
                        }
                        .padding()
                    } else if currentExercise != nil
                        || (isDualMode && !orderedGuestExercises.isEmpty)
                        || (isTripleMode && !orderedGuest2Exercises.isEmpty) {
                        exercisePager()
                    } else {
                        activeExerciseEmptyState(lane: .host)
                    }
                }
                
                if isSaving {
                    ZStack {
                        Color.black.opacity(0.4)
                            .ignoresSafeArea()
                        ProgressView("Saving workout…")
                            .padding(24)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                    }
                    .allowsHitTesting(true)
                    .zIndex(4)
                }
                
                if startSyncBannerVisible {
                    VStack {
                        Text(startSyncBannerText)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(.top, 8)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .zIndex(3)
                }

                if let msg = toastMessage {
                    VStack {
                        Spacer()
                        Text(msg)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(.ultraThinMaterial, in: Capsule())
                            .overlay(Capsule().stroke(.white.opacity(0.12), lineWidth: 1))
                            .padding(.bottom, 22)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(2)
                }
                
                if showCountdown {
                    StartWorkoutCountdownView {
                        let start = Date()
                        withAnimation(.easeInOut) {
                            showCountdown = false
                            strengthWorkoutSessionStart = start
                        }
                        WorkoutLiveActivityManager.startIfAvailable(
                            startTime: start,
                            kind: .strength
                        )
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.ultraThinMaterial)
                    .transition(.opacity.combined(with: .scale))
                    .zIndex(1)
                }

                if showElborblaCelebration {
                    ElborblaFinishCelebrationOverlay(
                        image: Self.loadElborblaCelebrationImage(),
                        onContinue: {
                            showElborblaCelebration = false
                            dismiss()
                        }
                    )
                    .zIndex(3)
                    .transition(.opacity)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !app.isPremium, !showElborblaCelebration {
                    BannerAdView(adUnitID: "ca-app-pub-7676731162362384/7781347704")
                        .frame(height: 50)
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(showElborblaCelebration ? .hidden : .visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .disabled(isSaving)
                }
                if !showCountdown, strengthWorkoutSessionStart != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        HStack(spacing: 8) {
                            strengthWorkoutSessionElapsedChip()
                            Button {
                                toggleSessionPause()
                            } label: {
                                Image(systemName: isSessionPaused ? "play.fill" : "pause.fill")
                                    .font(.body.weight(.semibold))
                                    .frame(width: 36, height: 36)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.bordered)
                            .accessibilityLabel(isSessionPaused ? String(localized: "Resume workout") : String(localized: "Pause workout"))
                        }
                    }
                }
            }
            .alert("Not everyone is finished", isPresented: $showDualIncompleteFinishConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Finish for everyone", role: .destructive) {
                    Task { await saveAndFinishWorkout() }
                }
            } message: {
                Text(dualIncompleteFinishMessage())
            }
        }
        .onDisappear {
            WorkoutLiveActivityManager.endIfAvailable()
        }
        .sheet(isPresented: $showActiveExercisePicker) {
            ExercisePickerSheet(
                all: [],
                selected: Binding(
                    get: { nil },
                    set: { picked in
                        showActiveExercisePicker = false
                        if let picked {
                            appendExerciseToActiveSetup(picked)
                        }
                    }
                )
            )
            .gradientBG()
            .presentationDetents([.large])
            .presentationBackground(.clear)
        }
        .sheet(isPresented: $showActiveExerciseSetup) {
            activeExerciseSetupSheet()
                .presentationBackground(.clear)
        }
        .alert("Delete exercise?", isPresented: $showDeleteExerciseConfirm) {
            Button("Delete", role: .destructive) {
                if let ex = deleteExerciseCandidate {
                    let lane = deleteExerciseLane
                    Task { await deleteActiveExercise(ex, lane: lane) }
                }
            }
            Button("Cancel", role: .cancel) {
                deleteExerciseCandidate = nil
            }
        } message: {
            if let ex = deleteExerciseCandidate {
                Text("This removes \(ex.custom_name ?? ex.exercise_name ?? "this exercise") and its completed sets from this active workout.")
            } else {
                Text("This removes the exercise and its completed sets from this active workout.")
            }
        }
        .alert("Update superserie sets?", isPresented: $showSupersetSetActionConfirm) {
            Button("Only this exercise") {
                applyPendingSupersetSetAction(toAllMembers: false)
            }
            Button("All superserie exercises (Recommended)") {
                applyPendingSupersetSetAction(toAllMembers: true)
            }
            Button("Cancel", role: .cancel) {
                clearPendingSupersetSetAction()
            }
        } message: {
            switch pendingSupersetSetAction {
            case .add:
                Text("This exercise is part of a superserie. Add one set only here, or keep the superserie balanced by adding one set to every exercise in the group.")
            case .remove:
                Text("This exercise is part of a superserie. Remove one set only here, or keep the superserie balanced by removing one set from every exercise in the group.")
            case .none:
                Text("Choose how to update this superserie.")
            }
        }
        .sheet(isPresented: $showEditSheet) {
            NavigationStack {
                ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    editSupersetMemberPicker(lane: editTargetLane)

                    if let ex = exerciseForEditSheet(),
                       let drop = dropIndicatorLabel(for: ex, setIndex: currentSetIndexForEditLane(), lane: editTargetLane) {
                        Text(drop)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                    if editDropSegments.count >= 2 {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Drop set")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)

                            ForEach(Array(editDropSegments.enumerated()), id: \.offset) { idx, _ in
                                HStack(alignment: .top, spacing: 6) {
                                    StrengthStyleMetricField(title: "Reps") {
                                        TextField(
                                            "—",
                                            text: Binding(
                                                get: { "\(editDropSegments[idx].reps)" },
                                                set: { t in
                                                    let v = Int(t.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
                                                    editDropSegments[idx] = StrengthWeightSegWire(reps: v, weight_kg: editDropSegments[idx].weight_kg)
                                                }
                                            )
                                        )
                                        .font(.body)
                                        .keyboardType(.numberPad)
                                    }
                                    StrengthStyleMetricField(title: "kg") {
                                        TextField(
                                            "—",
                                            text: Binding(
                                                get: { String(format: "%.1f", editDropSegments[idx].weight_kg) },
                                                set: { t in
                                                    let raw = t.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
                                                    let v = Double(raw) ?? 0
                                                    editDropSegments[idx] = StrengthWeightSegWire(reps: editDropSegments[idx].reps, weight_kg: v)
                                                }
                                            )
                                        )
                                        .font(.body)
                                        .keyboardType(.decimalPad)
                                    }
                                }
                            }

                            HStack(spacing: 10) {
                                Button("Add step") {
                                    let last = editDropSegments.last ?? StrengthWeightSegWire(reps: 10, weight_kg: 0)
                                    editDropSegments.append(last)
                                }
                                .buttonStyle(.bordered)

                                Button("Remove step") {
                                    if editDropSegments.count > 2 {
                                        editDropSegments.removeLast()
                                    }
                                }
                                .buttonStyle(.bordered)
                                .disabled(editDropSegments.count <= 2)
                            }
                        }
                    }

                    VStack(spacing: 10) {
                        if editDropSegments.count < 2 {
                            HStack(alignment: .top, spacing: 6) {
                                StrengthStyleMetricField(title: "Reps") {
                                    TextField("—", text: $editRepsText)
                                        .font(.body)
                                        .keyboardType(.numberPad)
                                        .focused($editMetricFocus, equals: .reps)
                                }
                                StrengthStyleMetricField(title: "kg") {
                                    TextField("—", text: $editWeightText)
                                        .font(.body)
                                        .keyboardType(.decimalPad)
                                        .focused($editMetricFocus, equals: .weight)
                                }
                            }
                        }
                        HStack(alignment: .top, spacing: 6) {
                            if editShowsRestFieldInSheet() {
                                StrengthStyleMetricField(title: "Rest s") {
                                    TextField("—", text: $editRestText)
                                        .font(.body)
                                        .keyboardType(.numberPad)
                                        .focused($editMetricFocus, equals: .rest)
                                }
                            }
                            StrengthStyleMetricField(title: "RPE") {
                                TextField("—", text: $editRpeText)
                                    .font(.body)
                                    .keyboardType(.decimalPad)
                                    .focused($editMetricFocus, equals: .rpe)
                            }
                        }
                    }

                    if editShowsRestFieldInSheet() {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Quick rest")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(quickRestPresets, id: \.self) { sec in
                                    Button {
                                        editRestText = "\(sec)"
                                    } label: {
                                        Text("\(sec)s")
                                            .font(.subheadline.weight(.medium))
                                            .monospacedDigit()
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                        }
                    }
                    }

                    if let ex = exerciseForEditSheet(), let set = currentSetFor(ex, setIndex: currentSetIndexForEditLane(), lane: editTargetLane) {
                        if editDropSegments.count >= 2 {
                            Button("Convert to normal set") {
                                let first = editDropSegments.first ?? StrengthWeightSegWire(reps: 10, weight_kg: 0)
                                convertToNormalRepsText = "\(first.reps)"
                                convertToNormalWeightText = String(format: "%.1f", first.weight_kg)
                                showConvertToNormalSheet = true
                            }
                            .buttonStyle(.bordered)
                        } else if (set.weight_segments?.count ?? 0) < 2 {
                            Button("Convert to drop set") {
                                convertCurrentConfigToDropSet()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }

                    if shouldShowApplyToRemainingSetsToggle(), let range = editRemainingSetRange() {
                        Toggle("Apply to sets \(range.start)–\(range.end)", isOn: $applyEditToRemainingSets)
                    }

                    Text("Edits update this workout flow now and are written when you finish the workout.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .top)
                }
                .navigationTitle("Edit set")
                .navigationBarTitleDisplayMode(.inline)
                .padding()
                .background(Color.clear.gradientBG().ignoresSafeArea())
                .toolbarBackground(.hidden, for: .navigationBar)
                .sheet(isPresented: $showConvertToNormalSheet) {
                    NavigationStack {
                        VStack(alignment: .leading, spacing: 16) {
                            StrengthStyleMetricField(title: "Reps") {
                                TextField("—", text: $convertToNormalRepsText)
                                    .font(.body)
                                    .keyboardType(.numberPad)
                            }
                            StrengthStyleMetricField(title: "kg") {
                                TextField("—", text: $convertToNormalWeightText)
                                    .font(.body)
                                    .keyboardType(.decimalPad)
                            }
                            Button("Convert") {
                                applyConvertCurrentConfigToNormal()
                                showConvertToNormalSheet = false
                                showEditSheet = false
                            }
                            .buttonStyle(.borderedProminent)
                            Spacer()
                        }
                        .padding()
                        .navigationTitle("Convert to normal")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Cancel") { showConvertToNormalSheet = false }
                            }
                        }
                    }
                    .presentationDetents([.medium])
                    .presentationBackground(.clear)
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            editMetricFocus = nil
                            clearEditDrafts()
                            applyEditToRemainingSets = false
                            showEditSheet = false
                            editTargetExpandedIndex = nil
                            editTargetExerciseId = nil
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            editMetricFocus = nil
                            applyAllStashedEditDrafts()
                            clearEditDrafts()
                            applyEditToRemainingSets = false
                            showEditSheet = false
                            editTargetExpandedIndex = nil
                            editTargetExerciseId = nil
                        }
                    }
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(.clear)
        }
        .onReceive(restTimer) { _ in
            if !isSessionPaused {
                if isResting || gIsResting || g2IsResting || hasActiveRestInExerciseTimerDictionaries() {
                    syncRestCountdownFromEndDate()
                }
                if strengthWorkoutSessionStart != nil, !showCountdown {
                    strengthWorkoutElapsedTick &+= 1
                }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            restoreActiveWorkoutStateOnForeground()
            guard !isSessionPaused else { return }
            syncRestCountdownFromEndDate()
            if strengthWorkoutSessionStart != nil {
                strengthWorkoutElapsedTick &+= 1
            }
        }
        .onChange(of: currentSetIndex) { _, _ in
            if let ex = currentExercise {
                withAnimation(.easeInOut(duration: 0.25)) {
                    snapVisitedToCurrent(for: ex, lane: .host)
                }
            }
        }
        .onChange(of: gCurrentSetIndex) { _, _ in
            if let ex = currentGuestExercise {
                withAnimation(.easeInOut(duration: 0.25)) {
                    snapVisitedToCurrent(for: ex, lane: .guest)
                }
            }
        }
        .onChange(of: g2CurrentSetIndex) { _, _ in
            if let ex = currentGuest2Exercise {
                withAnimation(.easeInOut(duration: 0.25)) {
                    snapVisitedToCurrent(for: ex, lane: .guest2)
                }
            }
        }
        .onChange(of: currentExerciseIndex) { _, _ in
            if let ex = currentExercise {
                withAnimation(.easeInOut(duration: 0.25)) {
                    snapVisitedToCurrent(for: ex, lane: .host)
                }
            }
        }
        .onChange(of: guestCurrentExerciseIndex) { _, _ in
            if let ex = currentGuestExercise {
                withAnimation(.easeInOut(duration: 0.25)) {
                    snapVisitedToCurrent(for: ex, lane: .guest)
                }
            }
        }
        .onChange(of: g2CurrentExerciseIndex) { _, _ in
            if let ex = currentGuest2Exercise {
                withAnimation(.easeInOut(duration: 0.25)) {
                    snapVisitedToCurrent(for: ex, lane: .guest2)
                }
            }
        }
        .onAppear {
            startSyncStatus = WorkoutStartSync.status(for: workoutId)
            #if DEBUG
            dualStrengthDebug(
                "onAppear showCountdown=\(showCountdown) isDualMode=\(dualGuestWorkoutId != nil) "
                    + "guestWid=\(dualGuestWorkoutId.map(String.init) ?? "nil") "
                    + "hostHasURL=\(dualHostAvatarURL != nil) guestHasURL=\(dualGuestAvatarURL != nil)"
            )
            #endif
        }
        .onReceive(NotificationCenter.default.publisher(for: .workoutStartSyncStatusChanged)) { note in
            guard let wid = note.userInfo?["workoutId"] as? Int, wid == workoutId,
                  let raw = note.userInfo?["status"] as? String
            else { return }
            switch raw {
            case "pending": startSyncStatus = .pending
            case "syncing": startSyncStatus = .syncing
            case "synced": startSyncStatus = .synced
            case "willRetry": startSyncStatus = .willRetry
            default: startSyncStatus = .idle
            }
        }
        .task { await load() }
        .task(id: app.userId) {
            guard let userId = app.userId else { return }
            quickRestPresets = await StrengthRestPresetService.fetchQuickRestPresets(userId: userId)
        }
        .onDisappear {
            Task { await sanitizeEndDateIfNeededOnClose() }
        }
        .sheet(item: $strengthFinishDeferral) { def in
            StrengthRoutineOverwriteConfirmSheet(
                prompt: def.prompt,
                onUpdate: {
                    let d = def
                    strengthFinishDeferral = nil
                    isSaving = true
                    Task { await commitDeferredStrengthFinish(deferral: d, updateRoutine: true) }
                },
                onNotNow: {
                    let d = def
                    strengthFinishDeferral = nil
                    isSaving = true
                    Task { await commitDeferredStrengthFinish(deferral: d, updateRoutine: false) }
                }
            )
            .presentationSizing(.fitted)
            .presentationDragIndicator(.visible)
            .presentationBackground(.clear)
            .frame(maxHeight: UIScreen.main.bounds.height * 0.92)
        }
        .overlay {
            if app.isAuthenticated, !showCountdown, !isSaving {
                MessagesFloatingButton()
                    .environmentObject(app)
                    .allowsHitTesting(true)
                    .zIndex(99)
            }
        }
    }
    
    @ViewBuilder
    private func exerciseContent(_ ex: ExerciseRow, isActive: Bool, lane: StrengthLaneKind) -> some View {
        let sets = setsFor(ex, lane: lane)
        let totalSets = sets.count
        let plannedSets = totalSets
        let laneSetIndex = currentSetIndex(for: lane)
        let effectiveSetIndex = isActive ? laneSetIndex : 0
        let currentSet = currentSetFor(ex, setIndex: effectiveSetIndex, lane: lane)
        let allSetsDone = (totalSets > 0 && currentSet == nil)
        let isExtraCurrentSet = false

        VStack {
            Spacer(minLength: 0)

            VStack(spacing: 16) {
                VStack(spacing: 8) {
                    Text(ex.custom_name?.isEmpty == false ? ex.custom_name! : (ex.exercise_name ?? "Exercise"))
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .minimumScaleFactor(0.80)
                        .allowsTightening(true)
                        .fixedSize(horizontal: false, vertical: true)

                    if let notes = ex.notes, !notes.isEmpty {
                        Text(notes)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity)

                exerciseMainContent(
                    ex,
                    lane: lane,
                    currentSet: currentSet,
                    totalSets: totalSets,
                    plannedSets: plannedSets,
                    allSetsDone: allSetsDone,
                    isExtraCurrentSet: isExtraCurrentSet,
                    displaySetIndex: effectiveSetIndex
                )
            }
            .padding(18)
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
            .overlay(
                RoundedRectangle(cornerRadius: 22)
                    .stroke(.white.opacity(isActive ? 0.18 : 0.10), lineWidth: 1)
            )

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func supersetExerciseContent(_ group: StrengthDisplayGroup, isActive: Bool, lane: StrengthLaneKind) -> some View {
        let list = orderedExercises(lane: lane)
        let members = group.exerciseIndices.compactMap { list.indices.contains($0) ? list[$0] : nil }
        let workSetIndex = supersetGroupWorkSetIndex(members: members, lane: lane)
        let groupAllSetsDone = members.allSatisfy { isExerciseCompleted($0, lane: lane) }
        let activeExerciseId: Int? = {
            switch lane {
            case .host: return currentExercise?.id
            case .guest: return currentGuestExercise?.id
            case .guest2: return currentGuest2Exercise?.id
            }
        }()
        let activeMember = members.first { $0.id == activeExerciseId } ?? members.first
        let maxRounds = supersetMaxRoundCount(members: members, lane: lane)
        let visitedRound = visitedSupersetRound(for: group, workRound: workSetIndex, lane: lane)
        let isVisitingCurrentRound = visitedRound == workSetIndex
        let visitedIsPastRound = visitedRound < workSetIndex
        let canShowRoundSlider = isActive && maxRounds > 0 && !groupAllSetsDone
        let activeSet = groupAllSetsDone
            ? nil
            : activeMember.flatMap { currentSetFor($0, setIndex: workSetIndex, lane: lane) }
        let groupRest = supersetGroupRestState(members: members, lane: lane)
        let membersBlockHeight = supersetMembersContentHeight(memberCount: members.count)

        VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Superserie")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    if groupAllSetsDone {
                        Text("All sets completed ✅")
                            .font(.subheadline.weight(.semibold))
                        Text("Great job! Move on when ready.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Set \(workSetIndex + 1) · \(members.count) exercises")
                            .font(.subheadline.weight(.semibold))
                        if canShowRoundSlider && !isVisitingCurrentRound {
                            Text("Viewing set \(visitedRound + 1)")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(supersetGroupTitle(members))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if canShowRoundSlider {
                    TabView(selection: visitedSupersetRoundBinding(for: group, workRound: workSetIndex, maxRounds: maxRounds, lane: lane)) {
                        ForEach(0..<maxRounds, id: \.self) { roundIdx in
                            supersetMembersRoundList(
                                members: members,
                                lane: lane,
                                roundIndex: roundIdx,
                                workSetIndex: workSetIndex,
                                activeExerciseId: activeExerciseId,
                                isActiveCard: isActive,
                                groupAllSetsDone: groupAllSetsDone,
                                groupRest: groupRest,
                                scrollWhenNeeded: membersBlockHeight >= 336
                            )
                            .frame(height: membersBlockHeight)
                            .tag(roundIdx)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .frame(height: membersBlockHeight)
                    .opacity(isVisitingCurrentRound ? 1.0 : 0.92)

                    setSlideDots(total: maxRounds, visited: visitedRound, current: workSetIndex)
                } else {
                    let displayRound = groupAllSetsDone
                        ? max(0, maxRounds - 1)
                        : workSetIndex
                    supersetMembersRoundList(
                        members: members,
                        lane: lane,
                        roundIndex: displayRound,
                        workSetIndex: workSetIndex,
                        activeExerciseId: activeExerciseId,
                        isActiveCard: isActive,
                        groupAllSetsDone: groupAllSetsDone,
                        groupRest: groupRest,
                        scrollWhenNeeded: membersBlockHeight >= 336
                    )
                    .frame(height: membersBlockHeight)
                }

                if let ex = activeMember {
                    supersetGroupActions(
                        ex: ex,
                        members: members,
                        group: group,
                        lane: lane,
                        laneSetIndex: workSetIndex,
                        visitedRound: visitedRound,
                        canShowRoundSlider: canShowRoundSlider,
                        isVisitingCurrentRound: isVisitingCurrentRound,
                        visitedIsPastRound: visitedIsPastRound,
                        currentSet: activeSet,
                        allSetsDone: groupAllSetsDone,
                        isActiveCard: isActive,
                        groupRest: groupRest
                    )
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
            .overlay(
                RoundedRectangle(cornerRadius: 22)
                    .stroke(.white.opacity(isActive ? 0.18 : 0.10), lineWidth: 1)
            )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private func supersetMembersRoundList(
        members: [ExerciseRow],
        lane: StrengthLaneKind,
        roundIndex: Int,
        workSetIndex: Int,
        activeExerciseId: Int?,
        isActiveCard: Bool,
        groupAllSetsDone: Bool,
        groupRest: SupersetGroupRestState,
        scrollWhenNeeded: Bool
    ) -> some View {
        let rows = VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(members.enumerated()), id: \.element.id) { offset, ex in
                supersetMemberRow(
                    ex,
                    position: offset + 1,
                    memberCount: members.count,
                    lane: lane,
                    setIndex: roundIndex,
                    isActiveMember: ex.id == activeExerciseId,
                    isActiveCard: isActiveCard,
                    groupAllSetsDone: groupAllSetsDone,
                    groupRest: groupRest
                )
                if offset < members.count - 1 {
                    Divider()
                }
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)

        if scrollWhenNeeded {
            ScrollView(showsIndicators: true) { rows }
        } else {
            rows
        }
    }

    private func supersetGroupTitle(_ members: [ExerciseRow]) -> String {
        members.map { exerciseTitle($0) }.joined(separator: " → ")
    }

    private func supersetGroupWorkSetIndex(members: [ExerciseRow], lane: StrengthLaneKind) -> Int {
        guard !members.isEmpty else { return 0 }
        return members.map { effectiveSetIndex(for: $0, lane: lane) }.min() ?? 0
    }

    private func supersetMaxRoundCount(members: [ExerciseRow], lane: StrengthLaneKind) -> Int {
        members.map { setsFor($0, lane: lane).count }.max() ?? 0
    }

    private func supersetMembersContentHeight(memberCount: Int) -> CGFloat {
        let rowHeight: CGFloat = 108
        let dividerHeight: CGFloat = 13
        let verticalPadding: CGFloat = 8
        let raw = CGFloat(memberCount) * rowHeight
            + CGFloat(max(0, memberCount - 1)) * dividerHeight
            + verticalPadding
        return min(raw, 336)
    }

    private func supersetRoundRestSec(members: [ExerciseRow], lane: StrengthLaneKind, setIndex: Int) -> Int {
        let available = members.filter { setsFor($0, lane: lane).count > setIndex }
        guard let last = available.last else { return 0 }
        return currentSetFor(last, setIndex: setIndex, lane: lane)?.rest_sec ?? 0
    }

    private func supersetRoundPrimaryButtonTitle(members: [ExerciseRow], lane: StrengthLaneKind, setIndex: Int) -> String {
        let rest = supersetRoundRestSec(members: members, lane: lane, setIndex: setIndex)
        if rest > 0 { return "Rest \(rest)s" }
        return "Set done"
    }

    private func appendPerformedSet(for ex: ExerciseRow, setIndex: Int, lane: StrengthLaneKind) {
        guard let s = currentSetFor(ex, setIndex: setIndex, lane: lane) else { return }
        let performed = PerformedSet(
            reps: s.reps,
            weight_kg: s.weight_kg,
            rpe: s.rpe,
            rest_sec: s.rest_sec,
            configId: s.configId,
            segmentsInRow: s.segmentsInRow,
            weight_segments: s.weight_segments
        )
        switch lane {
        case .host:
            var list = performedSetsByExercise[ex.id] ?? []
            list.append(performed)
            performedSetsByExercise[ex.id] = list
        case .guest:
            var list = gPerformedSetsByExercise[ex.id] ?? []
            list.append(performed)
            gPerformedSetsByExercise[ex.id] = list
        case .guest2:
            var list = g2PerformedSetsByExercise[ex.id] ?? []
            list.append(performed)
            g2PerformedSetsByExercise[ex.id] = list
        }
    }

    private func startRest(for set: SetRow, lane: StrengthLaneKind, exercise ex: ExerciseRow) {
        let sec = set.rest_sec ?? 0
        guard sec > 0 else { return }
        let end = Date().addingTimeInterval(TimeInterval(sec))
        switch lane {
        case .host:
            if navEmphasisLockExerciseIdHost == nil { navEmphasisLockExerciseIdHost = ex.id }
            restEndDate = end
            remainingRest = sec
            isResting = true
            didFireRestFinishedFeedback = false
            isRestingByExercise[ex.id] = true
            remainingRestByExercise[ex.id] = sec
            restEndDateByExercise[ex.id] = end
            restTotalPlannedByExercise[ex.id] = sec
        case .guest:
            if navEmphasisLockExerciseIdGuest == nil { navEmphasisLockExerciseIdGuest = ex.id }
            gRestEndDate = end
            gRemainingRest = sec
            gIsResting = true
            gDidFireRestFinishedFeedback = false
            gIsRestingByExercise[ex.id] = true
            gRemainingRestByExercise[ex.id] = sec
            gRestEndDateByExercise[ex.id] = end
            gRestTotalPlannedByExercise[ex.id] = sec
        case .guest2:
            if navEmphasisLockExerciseIdGuest2 == nil { navEmphasisLockExerciseIdGuest2 = ex.id }
            g2RestEndDate = end
            g2RemainingRest = sec
            g2IsResting = true
            g2DidFireRestFinishedFeedback = false
            g2IsRestingByExercise[ex.id] = true
            g2RemainingRestByExercise[ex.id] = sec
            g2RestEndDateByExercise[ex.id] = end
            g2RestTotalPlannedByExercise[ex.id] = sec
        }
        if isDualMode, sec > 0 {
            let nextLane: StrengthLaneKind = {
                if isTripleMode {
                    switch lane {
                    case .host: return .guest
                    case .guest: return .guest2
                    case .guest2: return .host
                    }
                } else {
                    return lane == .host ? .guest : .host
                }
            }()
            clampLaneExerciseIndex(nextLane)
            if laneHasRemainingWork(nextLane) {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
                    dualFocusLane = nextLane
                }
            }
        }
    }

    private func completeSupersetRound(members: [ExerciseRow], lane: StrengthLaneKind, setIndex: Int) {
        let available = members.filter { setsFor($0, lane: lane).count > setIndex }
        guard !available.isEmpty, let lastMember = available.last else { return }

        for member in available {
            appendPerformedSet(for: member, setIndex: setIndex, lane: lane)
        }

        let lastTotal = setsFor(lastMember, lane: lane).count
        applySupersetSetIndexAdvancement(
            for: lastMember,
            lane: lane,
            completedSetIndex: setIndex,
            totalSets: lastTotal
        )
        snapSupersetVisitedRoundIfNeeded(for: lastMember, lane: lane)

        if let first = members.first,
           let idx = orderedExercises(lane: lane).firstIndex(where: { $0.id == first.id }) {
            jumpToExercise(lane: lane, index: idx)
        }

        if let restSet = currentSetFor(lastMember, setIndex: setIndex, lane: lane),
           (restSet.rest_sec ?? 0) > 0 {
            startRest(for: restSet, lane: lane, exercise: lastMember)
        } else if navEmphasisLockExerciseId(for: lane) == nil, let first = members.first {
            switch lane {
            case .host: navEmphasisLockExerciseIdHost = first.id
            case .guest: navEmphasisLockExerciseIdGuest = first.id
            case .guest2: navEmphasisLockExerciseIdGuest2 = first.id
            }
        }
    }

    private func navEmphasisLockExerciseId(for lane: StrengthLaneKind) -> Int? {
        switch lane {
        case .host: return navEmphasisLockExerciseIdHost
        case .guest: return navEmphasisLockExerciseIdGuest
        case .guest2: return navEmphasisLockExerciseIdGuest2
        }
    }

    private func visitedSupersetRound(for group: StrengthDisplayGroup, workRound: Int, lane: StrengthLaneKind) -> Int {
        let raw: Int? = {
            switch lane {
            case .host: return visitedSupersetRoundByGroupId[group.id]
            case .guest: return gVisitedSupersetRoundByGroupId[group.id]
            case .guest2: return g2VisitedSupersetRoundByGroupId[group.id]
            }
        }()
        let list = orderedExercises(lane: lane)
        let groupMembers = group.exerciseIndices.compactMap { idx in
            list.indices.contains(idx) ? list[idx] : nil
        }
        let maxRounds = max(1, supersetMaxRoundCount(members: groupMembers, lane: lane))
        let boundedMax = max(0, maxRounds - 1)
        return min(max(0, raw ?? workRound), boundedMax)
    }

    private func visitedSupersetRoundBinding(
        for group: StrengthDisplayGroup,
        workRound: Int,
        maxRounds: Int,
        lane: StrengthLaneKind
    ) -> Binding<Int> {
        Binding(
            get: { visitedSupersetRound(for: group, workRound: workRound, lane: lane) },
            set: { newValue in
                let bounded = min(max(0, newValue), max(0, maxRounds - 1))
                switch lane {
                case .host: visitedSupersetRoundByGroupId[group.id] = bounded
                case .guest: gVisitedSupersetRoundByGroupId[group.id] = bounded
                case .guest2: g2VisitedSupersetRoundByGroupId[group.id] = bounded
                }
            }
        )
    }

    private func snapVisitedSupersetRoundToCurrent(
        for group: StrengthDisplayGroup,
        workRound: Int,
        lane: StrengthLaneKind
    ) {
        switch lane {
        case .host: visitedSupersetRoundByGroupId[group.id] = workRound
        case .guest: gVisitedSupersetRoundByGroupId[group.id] = workRound
        case .guest2: g2VisitedSupersetRoundByGroupId[group.id] = workRound
        }
    }

    private func snapSupersetVisitedRoundIfNeeded(for ex: ExerciseRow, lane: StrengthLaneKind) {
        let members = supersetMembers(for: ex, lane: lane)
        guard members.count > 1 else { return }
        let list = orderedExercises(lane: lane)
        guard let group = strengthDisplayGroups(lane: lane).first(where: { g in
            g.isSuperset && g.exerciseIndices.contains { idx in
                list.indices.contains(idx) && list[idx].id == ex.id
            }
        }) else { return }
        let workRound = supersetGroupWorkSetIndex(members: members, lane: lane)
        snapVisitedSupersetRoundToCurrent(for: group, workRound: workRound, lane: lane)
    }

    private func supersetMemberFinishedRound(_ ex: ExerciseRow, roundIndex: Int, lane: StrengthLaneKind) -> Bool {
        let performed = performedSetsFor(ex, lane: lane).count
        return performed > roundIndex || effectiveSetIndex(for: ex, lane: lane) > roundIndex
    }

    private func applySupersetSetIndexAdvancement(
        for ex: ExerciseRow,
        lane: StrengthLaneKind,
        completedSetIndex: Int,
        totalSets: Int
    ) {
        let members = supersetMembers(for: ex, lane: lane)
        let completesRound = members.count <= 1
            || shouldStartRestAfterCompletingSet(ex, lane: lane, setIndex: completedSetIndex)

        if members.count > 1 && !completesRound {
            setCurrentSetIndex(completedSetIndex, for: ex, lane: lane)
            return
        }

        if members.count > 1 && completesRound {
            for member in members {
                let memberTotal = setsFor(member, lane: lane).count
                let next = min(completedSetIndex + 1, memberTotal)
                setCurrentSetIndex(next, for: member, lane: lane)
            }
            return
        }

        let next = completedSetIndex < totalSets - 1 ? completedSetIndex + 1 : totalSets
        setCurrentSetIndex(next, for: ex, lane: lane)
    }

    private func setCurrentSetIndex(_ index: Int, for ex: ExerciseRow, lane: StrengthLaneKind) {
        switch lane {
        case .host:
            if currentExercise?.id == ex.id { currentSetIndex = index }
            currentSetIndexByExercise[ex.id] = index
            isRestingByExercise[ex.id] = isResting
            remainingRestByExercise[ex.id] = remainingRest
        case .guest:
            if currentGuestExercise?.id == ex.id { gCurrentSetIndex = index }
            gCurrentSetIndexByExercise[ex.id] = index
            gIsRestingByExercise[ex.id] = gIsResting
            gRemainingRestByExercise[ex.id] = gRemainingRest
        case .guest2:
            if currentGuest2Exercise?.id == ex.id { g2CurrentSetIndex = index }
            g2CurrentSetIndexByExercise[ex.id] = index
            g2IsRestingByExercise[ex.id] = g2IsResting
            g2RemainingRestByExercise[ex.id] = g2RemainingRest
        }
    }

    private func supersetGroupRestState(members: [ExerciseRow], lane: StrengthLaneKind) -> SupersetGroupRestState {
        var bestSeconds = 0
        var anchorId: Int?
        for ex in members {
            guard let overlay = navRestOverlay(lane: lane, exerciseId: ex.id) else { continue }
            if overlay.seconds > bestSeconds {
                bestSeconds = overlay.seconds
                anchorId = ex.id
            }
        }
        if bestSeconds > 0, let anchorId {
            return SupersetGroupRestState(isActive: true, seconds: bestSeconds, anchorExerciseId: anchorId)
        }
        return SupersetGroupRestState(isActive: false, seconds: 0, anchorExerciseId: nil)
    }

    @ViewBuilder
    private func supersetMemberRow(
        _ ex: ExerciseRow,
        position: Int,
        memberCount: Int,
        lane: StrengthLaneKind,
        setIndex: Int,
        isActiveMember: Bool,
        isActiveCard: Bool,
        groupAllSetsDone: Bool,
        groupRest: SupersetGroupRestState
    ) -> some View {
        let plannedSet = currentSetFor(ex, setIndex: setIndex, lane: lane)
        let memberDone = groupAllSetsDone || supersetMemberFinishedRound(ex, roundIndex: setIndex, lane: lane)
        let isGroupResting = groupRest.isActive
        let isInActiveRound = isActiveCard && !memberDone && !isGroupResting && !groupAllSetsDone
        let isCurrent = isInActiveRound
        let statusLabel: String = {
            if groupAllSetsDone || memberDone { return "Done" }
            if isGroupResting { return "Rest" }
            if isCurrent { return "Current" }
            return "Upcoming"
        }()
        let statusColor: Color = isGroupResting
            ? Color.accentColor
            : (memberDone ? .green : (isCurrent ? Color.accentColor : Color.orange))
        let rowBg: Color = isGroupResting
            ? Color.accentColor.opacity(0.10)
            : (isInActiveRound
                ? Color.accentColor.opacity(isActiveMember ? 0.14 : 0.10)
                : Color.clear)

        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Text("\(position). \(exerciseTitle(ex))")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 4) {
                    if memberDone && !isGroupResting {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(statusColor)
                    }
                    Text(statusLabel.uppercased())
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(statusColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(statusColor.opacity(0.15)))
                }
            }

            if memberDone && !isGroupResting {
                let performed = performedSetsFor(ex, lane: lane)
                let performedSet = performed.last
                    ?? (performed.indices.contains(setIndex) ? performed[setIndex] : nil)
                let reps = performedSet?.reps ?? plannedSet?.reps ?? 0
                let weight = performedSet?.weight_kg ?? plannedSet?.weight_kg
                Text("\(reps) reps · \(weightStr(weight))")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            } else if let s = plannedSet {
                if let ws = s.weight_segments, ws.count >= 2 {
                    Text("Drop set")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(Array(ws.enumerated()), id: \.offset) { _, seg in
                        Text("\(seg.reps) reps · \(weightStr(Decimal(seg.weight_kg)))")
                            .font(.subheadline.weight(.semibold))
                    }
                } else {
                    Text("\(s.reps ?? 0) reps · \(weightStr(s.weight_kg))")
                        .font(.subheadline.weight(.semibold))
                    if let rpe = s.rpe {
                        Text("Target RPE \(String(format: "%.1f", NSDecimalNumber(decimal: rpe).doubleValue))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else if isExerciseCompleted(ex, lane: lane) {
                Text("All sets done")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("Exercise \(position) of \(memberCount)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(rowBg, in: RoundedRectangle(cornerRadius: 14))
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onTapGesture {
            guard isActiveCard, canJumpBetweenExercises,
                  let idx = orderedExercises(lane: lane).firstIndex(where: { $0.id == ex.id })
            else { return }
            withAnimation(.easeInOut(duration: 0.22)) {
                jumpToExercise(lane: lane, index: idx)
            }
        }
    }

    @ViewBuilder
    private func strengthRestTimerBar(seconds: Int, compact: Bool) -> some View {
        let timerSize: CGFloat = compact ? 29 : 36
        let timeMinWidth: CGFloat = compact ? 48 : 56
        HStack {
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                Text("Rest")
                    .font(compact ? .subheadline.weight(.semibold) : .headline.weight(.semibold))
                    .foregroundStyle(compact ? .primary : .secondary)
                Text("\(seconds)s")
                    .font(.system(size: timerSize, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .frame(minWidth: timeMinWidth, alignment: .leading)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: compact ? 12 : 14))
    }

    @ViewBuilder
    private func supersetGroupRestCountdown(seconds: Int) -> some View {
        strengthRestTimerBar(seconds: seconds, compact: false)
    }

    @ViewBuilder
    private func supersetGroupActions(
        ex: ExerciseRow,
        members: [ExerciseRow],
        group: StrengthDisplayGroup,
        lane: StrengthLaneKind,
        laneSetIndex: Int,
        visitedRound: Int,
        canShowRoundSlider: Bool,
        isVisitingCurrentRound: Bool,
        visitedIsPastRound: Bool,
        currentSet: SetRow?,
        allSetsDone: Bool,
        isActiveCard: Bool,
        groupRest: SupersetGroupRestState
    ) -> some View {
        let isActiveExercise = isActiveCard
        let hasNextInLane = laneNextExercise(lane: lane) != nil
        let skipExerciseId = groupRest.anchorExerciseId ?? ex.id

        Group {
            if groupRest.isActive {
                VStack(spacing: 10) {
                    supersetGroupRestCountdown(seconds: groupRest.seconds)
                    strengthSkipRestButton {
                        skipRest(for: lane, exerciseId: skipExerciseId)
                    }
                }
            } else {
                VStack(spacing: 10) {
                    if members.count > 1, !allSetsDone, !visitedIsPastRound,
                       currentSetFor(ex, setIndex: visitedRound, lane: lane) != nil {
                        editSetOutlinedButton {
                            openEditSet(exerciseId: ex.id, lane: lane, setIndex: visitedRound)
                        }
                    }

                    if canShowRoundSlider && !isVisitingCurrentRound {
                        Button {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                snapVisitedSupersetRoundToCurrent(for: group, workRound: laneSetIndex, lane: lane)
                            }
                        } label: {
                            Text("Back to current set")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .foregroundColor(.white)
                                .background(
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(Color.accentColor.opacity(0.85))
                                )
                        }
                        .buttonStyle(.plain)
                    } else if members.count > 1, isVisitingCurrentRound, !visitedIsPastRound {
                        Button {
                            completeSupersetRound(members: members, lane: lane, setIndex: laneSetIndex)
                        } label: {
                            Text(supersetRoundPrimaryButtonTitle(members: members, lane: lane, setIndex: laneSetIndex))
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .foregroundColor(.white)
                                .background(
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(Color.accentColor)
                                )
                        }
                        .buttonStyle(.plain)
                    } else if members.count <= 1 {
                        strengthPrimarySetActions(
                            ex: ex,
                            lane: lane,
                            currentSet: currentSet,
                            allSetsDone: allSetsDone,
                            isActiveExercise: isActiveExercise,
                            canShowSetSlider: canShowRoundSlider,
                            laneSetIndex: laneSetIndex,
                            visitedIndex: visitedRound,
                            isVisitingCurrent: isVisitingCurrentRound,
                            visitedIsPast: visitedIsPastRound,
                            compactRest: true
                        )
                    }
                }
            }

            activeExerciseMoreMenu(
                ex,
                lane: lane,
                canAddSet: !(isSaving || (isResting && isActiveExercise && !allSetsDone)),
                canRemoveSet: !(isResting || isSaving || (isActiveExercise && allSetsDone) || !canRemoveAnySet(for: ex, lane: lane)),
                canDeleteExercise: canModifyActiveExercises
            )

            if allSetsDone {
                supersetGroupCompletionActions(lane: lane, hasNextInLane: hasNextInLane)
            } else if !hasNextInLane {
                finishWorkoutEarlyButton()
            }
        }
    }

    private func primarySetActionButtonTitle(
        for ex: ExerciseRow,
        lane: StrengthLaneKind,
        setIndex: Int,
        currentSet: SetRow
    ) -> String {
        let shouldStartRest = shouldStartRestAfterCompletingSet(ex, lane: lane, setIndex: setIndex)
        if shouldStartRest, (currentSet.rest_sec ?? 0) > 0 {
            return "Rest \(currentSet.rest_sec ?? 0)s"
        }
        if supersetMembers(for: ex, lane: lane).count > 1 {
            return "Set done"
        }
        if let next = nextSupersetMember(after: ex, lane: lane, setIndex: setIndex) {
            return "Next · \(exerciseTitle(next))"
        }
        return "Set done"
    }

    @ViewBuilder
    private func strengthRestTimerRow(seconds: Int, compact: Bool) -> some View {
        strengthRestTimerBar(seconds: seconds, compact: compact)
    }

    @ViewBuilder
    private func strengthSkipRestButton(onSkip: @escaping () -> Void) -> some View {
        Button(action: onSkip) {
            Text("Skip rest")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .contentShape(Rectangle())
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.accentColor.opacity(0.75), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func strengthRestCountdownBlock(
        laneRemainingRest: Int,
        compact: Bool,
        onSkip: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 10) {
            strengthRestTimerRow(seconds: laneRemainingRest, compact: compact)
            strengthSkipRestButton(onSkip: onSkip)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func strengthPrimarySetActions(
        ex: ExerciseRow,
        lane: StrengthLaneKind,
        currentSet: SetRow?,
        allSetsDone: Bool,
        isActiveExercise: Bool,
        canShowSetSlider: Bool,
        laneSetIndex: Int,
        visitedIndex: Int,
        isVisitingCurrent: Bool,
        visitedIsPast: Bool,
        compactRest: Bool = false
    ) -> some View {
        let laneIsResting: Bool = {
            switch lane {
            case .host: return isResting
            case .guest: return gIsResting
            case .guest2: return g2IsResting
            }
        }()
        let laneRemainingRest: Int = {
            switch lane {
            case .host: return remainingRest
            case .guest: return gRemainingRest
            case .guest2: return g2RemainingRest
            }
        }()

        if isActiveExercise, let s = currentSet, !allSetsDone {
            VStack(spacing: compactRest ? 10 : 12) {
                if laneIsResting {
                    strengthRestCountdownBlock(laneRemainingRest: laneRemainingRest, compact: compactRest) {
                        skipRest(for: lane, exerciseId: ex.id)
                    }
                } else if canShowSetSlider && !isVisitingCurrent {
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            snapVisitedToCurrent(for: ex, lane: lane)
                        }
                    } label: {
                        Text("Back to current set")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .foregroundColor(.white)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(Color.accentColor.opacity(0.85))
                            )
                    }
                    .buttonStyle(.plain)
                } else if !canShowSetSlider || isVisitingCurrent {
                    Button {
                        completeCurrentSet(lane: lane)
                        if shouldStartRestAfterCompletingSet(ex, lane: lane, setIndex: laneSetIndex) {
                            startRest(for: s, lane: lane)
                        }
                    } label: {
                        Text(primarySetActionButtonTitle(for: ex, lane: lane, setIndex: laneSetIndex, currentSet: s))
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .foregroundColor(.white)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(Color.accentColor)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity)
        }

        if allSetsDone && isActiveExercise && laneIsResting && laneRemainingRest > 0 {
            strengthRestCountdownBlock(laneRemainingRest: laneRemainingRest, compact: compactRest) {
                skipRest(for: lane, exerciseId: ex.id)
            }
        }
    }

    @ViewBuilder
    private func supersetGroupCompletionActions(lane: StrengthLaneKind, hasNextInLane: Bool) -> some View {
        VStack(spacing: 12) {
            if hasNextInLane {
                Button {
                    goToNextExercise()
                } label: {
                    Text("Next exercise")
                        .font(.headline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(
                            RoundedRectangle(cornerRadius: 18)
                                .fill(Color.accentColor)
                        )
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    if isDualMode && !bothLanesFullyComplete() {
                        showDualIncompleteFinishConfirm = true
                    } else {
                        Task { await saveAndFinishWorkout() }
                    }
                } label: {
                    HStack(spacing: 8) {
                        if isSaving {
                            ProgressView().progressViewStyle(.circular)
                        }
                        Text(isSaving ? "Saving workout…" : "Finish workout")
                            .font(.headline.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(
                        RoundedRectangle(cornerRadius: 18)
                            .fill(Color.green.gradient)
                    )
                    .foregroundColor(.white)
                }
                .buttonStyle(.plain)
                .disabled(isSaving)
            }
        }
    }

    @ViewBuilder
    private func finishWorkoutEarlyButton() -> some View {
        Button {
            showFinishEarlyConfirm = true
        } label: {
            Text("Finish workout")
                .font(.headline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color.green.gradient)
                )
                .foregroundColor(.white)
        }
        .buttonStyle(.plain)
        .disabled(isSaving)
        .alert("Finish workout early?", isPresented: $showFinishEarlyConfirm) {
            Button("Finish", role: .destructive) {
                Task { await saveAndFinishWorkout() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(earlyFinishAlertMessage())
        }
    }

    private func currentSetIndex(for lane: StrengthLaneKind) -> Int {
        switch lane {
        case .host: return currentSetIndex
        case .guest: return gCurrentSetIndex
        case .guest2: return g2CurrentSetIndex
        }
    }

    private func currentSetFor(_ ex: ExerciseRow, setIndex: Int, lane: StrengthLaneKind) -> SetRow? {
        let sets = setsFor(ex, lane: lane)
        guard !sets.isEmpty, setIndex >= 0, setIndex < sets.count else { return nil }
        return sets[setIndex]
    }

    private func visitedSetIndexBinding(for ex: ExerciseRow, lane: StrengthLaneKind) -> Binding<Int> {
        Binding(
            get: { visitedSetIndex(for: ex, lane: lane) },
            set: { newValue in
                switch lane {
                case .host: visitedSetIndexByExercise[ex.id] = newValue
                case .guest: gVisitedSetIndexByExercise[ex.id] = newValue
                case .guest2: g2VisitedSetIndexByExercise[ex.id] = newValue
                }
            }
        )
    }

    private func visitedSetIndex(for ex: ExerciseRow, lane: StrengthLaneKind) -> Int {
        let raw: Int
        switch lane {
        case .host: raw = visitedSetIndexByExercise[ex.id] ?? currentSetIndex
        case .guest: raw = gVisitedSetIndexByExercise[ex.id] ?? gCurrentSetIndex
        case .guest2: raw = g2VisitedSetIndexByExercise[ex.id] ?? g2CurrentSetIndex
        }
        let total = setsFor(ex, lane: lane).count
        guard total > 0 else { return 0 }
        let upperBound = max(0, total - 1)
        return min(max(raw, 0), upperBound)
    }

    private func snapVisitedToCurrent(for ex: ExerciseRow, lane: StrengthLaneKind) {
        let curr = currentSetIndex(for: lane)
        let total = setsFor(ex, lane: lane).count
        guard total > 0 else { return }
        let bounded = min(max(curr, 0), max(0, total - 1))
        switch lane {
        case .host: visitedSetIndexByExercise[ex.id] = bounded
        case .guest: gVisitedSetIndexByExercise[ex.id] = bounded
        case .guest2: g2VisitedSetIndexByExercise[ex.id] = bounded
        }
    }

    private func performedSetsFor(_ ex: ExerciseRow, lane: StrengthLaneKind) -> [PerformedSet] {
        switch lane {
        case .host: return performedSetsByExercise[ex.id] ?? []
        case .guest: return gPerformedSetsByExercise[ex.id] ?? []
        case .guest2: return g2PerformedSetsByExercise[ex.id] ?? []
        }
    }

    @ViewBuilder
    private func setSlidePanelView(
        ex: ExerciseRow,
        lane: StrengthLaneKind,
        expandedIndex: Int,
        currentIndex: Int,
        totalSets: Int
    ) -> some View {
        let expanded = setsFor(ex, lane: lane)
        let plannedSet = expanded.indices.contains(expandedIndex) ? expanded[expandedIndex] : nil
        let performed = performedSetsFor(ex, lane: lane)
        let performedSet = performed.indices.contains(expandedIndex) ? performed[expandedIndex] : nil
        let isPast = expandedIndex < currentIndex
        let isCurrent = expandedIndex == currentIndex
        let displayReps: Int? = isPast ? (performedSet?.reps ?? plannedSet?.reps) : plannedSet?.reps
        let displayWeight: Decimal? = isPast ? (performedSet?.weight_kg ?? plannedSet?.weight_kg) : plannedSet?.weight_kg
        let displayRpe: Decimal? = isPast ? (performedSet?.rpe ?? plannedSet?.rpe) : plannedSet?.rpe
        let displaySegments: [StrengthWeightSegWire]? = isPast
            ? (performedSet?.weight_segments ?? plannedSet?.weight_segments)
            : plannedSet?.weight_segments
        let statusLabel: String = isPast ? "Completed" : (isCurrent ? "Current" : "Upcoming")
        let statusColor: Color = isPast ? .green : (isCurrent ? Color.accentColor : Color.orange)

        VStack(spacing: 10) {
            HStack(spacing: 6) {
                Text(statusLabel.uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(statusColor.opacity(0.15))
                    )
                if isPast {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(statusColor)
                }
            }

            Text("Step \(expandedIndex + 1) of \(totalSets)")
                .font(.headline)

            if let segs = displaySegments, segs.count >= 2 {
                Text("Drop set")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                VStack(spacing: 4) {
                    ForEach(Array(segs.enumerated()), id: \.offset) { _, seg in
                        Text("\(seg.reps) reps · \(weightStr(Decimal(seg.weight_kg)))")
                            .font(.title3.weight(.semibold))
                            .multilineTextAlignment(.center)
                    }
                }
            } else {
                Text("\(displayReps ?? 0) reps")
                    .font(.title2.weight(.semibold))
                Text(weightStr(displayWeight))
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            if let rpe = displayRpe {
                Text("Target RPE \(String(format: "%.1f", NSDecimalNumber(decimal: rpe).doubleValue))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    @ViewBuilder
    private func setSlideDots(total: Int, visited: Int, current: Int) -> some View {
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { i in
                let isVisited = (i == visited)
                let isCurrent = (i == current)
                Circle()
                    .stroke(
                        isCurrent ? Color.accentColor : Color.secondary.opacity(0.3),
                        lineWidth: isCurrent ? 1.5 : 1
                    )
                    .background(
                        Circle()
                            .fill(isVisited ? Color.accentColor : Color.clear)
                    )
                    .frame(width: isCurrent ? 10 : 8, height: isCurrent ? 10 : 8)
                    .animation(.easeInOut(duration: 0.2), value: isVisited)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 2)
    }
    
    private enum PeekEdge {
        case top
        case bottom
    }

    @ViewBuilder
    private func exercisePeekCard(_ ex: ExerciseRow, edge: PeekEdge) -> some View {
        let title = ex.custom_name?.isEmpty == false ? ex.custom_name! : (ex.exercise_name ?? "Exercise")

        VStack(spacing: 10) {
            if edge == .bottom { Spacer(minLength: 0) }

            Text(title)
                .font(.headline.weight(.semibold))
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(edge == .top ? "Next exercise" : "Previous exercise")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if edge == .top { Spacer(minLength: 0) }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        )
    }
    
    @ViewBuilder
    private func exerciseMainContent(
        _ ex: ExerciseRow,
        lane: StrengthLaneKind,
        currentSet: SetRow?,
        totalSets: Int,
        plannedSets: Int,
        allSetsDone: Bool,
        isExtraCurrentSet: Bool,
        displaySetIndex: Int
    ) -> some View {
        let activeExerciseId: Int? = {
            switch lane {
            case .host: return currentExercise?.id
            case .guest: return currentGuestExercise?.id
            case .guest2: return currentGuest2Exercise?.id
            }
        }()
        let isActiveExercise = (activeExerciseId == ex.id)
        let laneIsResting: Bool = {
            switch lane {
            case .host: return isResting
            case .guest: return gIsResting
            case .guest2: return g2IsResting
            }
        }()
        let _: Int = {
            switch lane {
            case .host: return remainingRest
            case .guest: return gRemainingRest
            case .guest2: return g2RemainingRest
            }
        }()
        let lockRestActions = laneIsResting && isActiveExercise && !allSetsDone
        let expandedSets = setsFor(ex, lane: lane)
        let canShowSlider = isActiveExercise && totalSets > 0 && !allSetsDone
        let laneCurrentIndex = currentSetIndex(for: lane)
        let visitedIndex = visitedSetIndex(for: ex, lane: lane)
        let isVisitingCurrent = (visitedIndex == laneCurrentIndex)
        let visitedIsPast = canShowSlider && visitedIndex < laneCurrentIndex
        let hasNextInLane = laneNextExercise(lane: lane) != nil

        if canShowSlider {
            let maxSegments = expandedSets.map { max(1, $0.weight_segments?.count ?? 1) }.max() ?? 1
            let panelHeight: CGFloat = 200 + CGFloat(max(0, maxSegments - 1)) * 34

            TabView(selection: visitedSetIndexBinding(for: ex, lane: lane)) {
                ForEach(0..<expandedSets.count, id: \.self) { idx in
                    setSlidePanelView(
                        ex: ex,
                        lane: lane,
                        expandedIndex: idx,
                        currentIndex: laneCurrentIndex,
                        totalSets: totalSets
                    )
                    .padding(.horizontal, 2)
                    .tag(idx)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: panelHeight)
            .opacity(isVisitingCurrent ? 1.0 : 0.92)

            setSlideDots(total: totalSets, visited: visitedIndex, current: laneCurrentIndex)

            if !visitedIsPast, expandedSets.indices.contains(visitedIndex) || currentSet != nil {
                editSetOutlinedButton {
                    openEditSet(exerciseId: ex.id, lane: lane, setIndex: visitedIndex)
                }
            }
        } else if let s = currentSet {
            VStack(spacing: 12) {
                Text("Step \(displaySetIndex + 1) of \(totalSets)")
                    .font(.headline)
                    .foregroundStyle(isExtraCurrentSet ? .green : .primary)

                if let drop = dropIndicatorLabel(for: ex, setIndex: displaySetIndex, lane: lane) {
                    Text(drop)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                if let ws = s.weight_segments, ws.count >= 2 {
                    VStack(spacing: 6) {
                        ForEach(Array(ws.enumerated()), id: \.offset) { _, seg in
                            Text("\(seg.reps) reps · \(weightStr(Decimal(seg.weight_kg)))")
                                .font(.title3.weight(.semibold))
                                .multilineTextAlignment(.center)
                        }
                    }
                } else {
                    Text("\(s.reps ?? 0) reps")
                        .font(.title2.weight(.semibold))

                    Text(weightStr(s.weight_kg))
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                if let rpe = s.rpe {
                    Text("Target RPE \(String(format: "%.1f", NSDecimalNumber(decimal: rpe).doubleValue))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(20)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))

            editSetOutlinedButton {
                openEditSet(exerciseId: ex.id, lane: lane, setIndex: displaySetIndex)
            }
        } else if allSetsDone {
            VStack(spacing: 8) {
                Text("All sets completed ✅")
                    .font(.headline)
                Text("Great job! Move on when ready.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(20)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
        } else {
            Text("No sets configured yet. Add at least 1 set to start.")
                .foregroundStyle(.secondary)
        }

        Group {
            strengthPrimarySetActions(
                ex: ex,
                lane: lane,
                currentSet: currentSet,
                allSetsDone: allSetsDone,
                isActiveExercise: isActiveExercise,
                canShowSetSlider: canShowSlider,
                laneSetIndex: laneCurrentIndex,
                visitedIndex: visitedIndex,
                isVisitingCurrent: isVisitingCurrent,
                visitedIsPast: visitedIsPast
            )

            activeExerciseMoreMenu(
                ex,
                lane: lane,
                canAddSet: !(isSaving || lockRestActions),
                canRemoveSet: !(laneIsResting || isSaving || (isActiveExercise && allSetsDone) || !canRemoveAnySet(for: ex, lane: lane)),
                canDeleteExercise: canModifyActiveExercises
            )

            if allSetsDone {
                supersetGroupCompletionActions(lane: lane, hasNextInLane: hasNextInLane)
            } else if !hasNextInLane {
                finishWorkoutEarlyButton()
            }
        }
    }

    private func activeExerciseMoreMenu(
        _ ex: ExerciseRow,
        lane: StrengthLaneKind,
        canAddSet: Bool,
        canRemoveSet: Bool,
        canDeleteExercise: Bool
    ) -> some View {
        Menu {
            Button {
                requestAddSet(for: ex, lane: lane)
            } label: {
                Label("Add set", systemImage: "plus.circle")
            }
            .disabled(!canAddSet)

            Button(role: .destructive) {
                requestRemoveSet(for: ex, lane: lane)
            } label: {
                Label("Remove set", systemImage: "minus.circle")
            }
            .disabled(!canRemoveSet)

            Button(role: .destructive) {
                requestDeleteActiveExercise(ex, lane: lane)
            } label: {
                Label("Delete exercise", systemImage: "trash")
            }
            .disabled(!canDeleteExercise)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "ellipsis.circle")
                Text("More")
            }
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.accentColor.opacity(0.75), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!canAddSet && !canRemoveSet && !canDeleteExercise)
        .opacity((canAddSet || canRemoveSet || canDeleteExercise) ? 1 : 0.45)
    }

    private func laneNextExercise(lane: StrengthLaneKind) -> ExerciseRow? {
        let list = orderedExercises(lane: lane)
        let idx: Int = {
            switch lane {
            case .host: return currentExerciseIndex
            case .guest: return guestCurrentExerciseIndex
            case .guest2: return g2CurrentExerciseIndex
            }
        }()
        let groups = strengthDisplayGroups(lane: lane)
        guard let gi = displayGroupIndex(forExerciseIndex: idx, lane: lane),
              gi + 1 < groups.count,
              let nextIdx = groups[gi + 1].exerciseIndices.first,
              nextIdx >= 0,
              nextIdx < list.count
        else { return nil }
        return list[nextIdx]
    }

    private func hostLaneFullyComplete() -> Bool {
        guard isDualMode else { return true }
        for ex in orderedExercises {
            if !isExerciseCompleted(ex, lane: .host) { return false }
        }
        return true
    }

    private func guestLaneFullyComplete() -> Bool {
        guard isDualMode else { return true }
        for ex in orderedGuestExercises {
            if !isExerciseCompleted(ex, lane: .guest) { return false }
        }
        return true
    }

    private func guest2LaneFullyComplete() -> Bool {
        guard isTripleMode else { return true }
        for ex in orderedGuest2Exercises {
            if !isExerciseCompleted(ex, lane: .guest2) { return false }
        }
        return true
    }

    private func bothLanesFullyComplete() -> Bool {
        hostLaneFullyComplete() && guestLaneFullyComplete() && guest2LaneFullyComplete()
    }

    private func laneHasRemainingWork(_ lane: StrengthLaneKind) -> Bool {
        for ex in orderedExercises(lane: lane) {
            if !isExerciseCompleted(ex, lane: lane) { return true }
        }
        return false
    }

    private func allExercisesCompleted(for lane: StrengthLaneKind) -> Bool {
        let list = orderedExercises(lane: lane)
        for ex in list {
            if !isExerciseCompleted(ex, lane: lane) { return false }
        }
        return true
    }

    private func cancelStrengthNavStripWave() {
        strengthNavStripWaveTask?.cancel()
        strengthNavStripWaveTask = nil
        strengthNavStripWaveIndex = nil
    }

    private func startStrengthNavStripWaveIfNeeded(lane: StrengthLaneKind) {
        let list = orderedExercises(lane: lane)
        let n = list.count
        guard n > 0, allExercisesCompleted(for: lane) else { return }
        strengthNavStripWaveTask?.cancel()
        strengthNavStripWaveIndex = nil
        strengthNavStripWaveTask = Task { @MainActor in
            for i in 0..<n {
                if Task.isCancelled { return }
                withAnimation(.spring(response: 0.22, dampingFraction: 0.72)) {
                    strengthNavStripWaveIndex = i
                }
                try? await Task.sleep(nanoseconds: 150_000_000)
            }
            if n > 1 {
                for i in stride(from: n - 1, through: 0, by: -1) {
                    if Task.isCancelled { return }
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.72)) {
                        strengthNavStripWaveIndex = i
                    }
                    try? await Task.sleep(nanoseconds: 150_000_000)
                }
            }
            for i in 0..<n {
                if Task.isCancelled { return }
                withAnimation(.spring(response: 0.22, dampingFraction: 0.72)) {
                    strengthNavStripWaveIndex = i
                }
                try? await Task.sleep(nanoseconds: 150_000_000)
            }
            if Task.isCancelled { return }
            withAnimation(.spring(response: 0.26, dampingFraction: 0.8)) {
                strengthNavStripWaveIndex = nil
            }
        }
    }

    private func dualPartnerProgressNote() -> String? {
        guard isDualMode else { return nil }
        var lines: [String] = []
        if !hostLaneFullyComplete() {
            lines.append("Your workout still has exercises or sets left.")
        }
        if !guestLaneFullyComplete() {
            lines.append("Your partner's workout still has exercises or sets left.")
        }
        if !guest2LaneFullyComplete() {
            lines.append("Another partner's workout still has exercises or sets left.")
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    private func dualIncompleteFinishMessage() -> String {
        var s = "Not everyone has finished exercises or sets in this session.\n\n"
        if !hostLaneFullyComplete() { s += "· You\n" }
        if !guestLaneFullyComplete() { s += "· Partner 1\n" }
        if !guest2LaneFullyComplete() { s += "· Partner 2\n" }
        s += "\nThis will save, publish, and close all workouts on this phone. Continue?"
        return s
    }

    private func earlyFinishAlertMessage() -> String {
        let base = "You haven't completed all planned sets. The workout will be saved with only the sets you actually performed. If you finish now, it will be published automatically."
        if isDualMode, let extra = dualPartnerProgressNote(), !extra.isEmpty {
            return base + "\n\n" + extra
        }
        return base
    }

    private func skipRest(for lane: StrengthLaneKind, exerciseId: Int) {
        switch lane {
        case .host:
            isResting = false
            remainingRest = 0
            restEndDate = nil
            didFireRestFinishedFeedback = false
            isRestingByExercise[exerciseId] = false
            remainingRestByExercise[exerciseId] = 0
            restEndDateByExercise[exerciseId] = nil
            restTotalPlannedByExercise[exerciseId] = nil
        case .guest:
            gIsResting = false
            gRemainingRest = 0
            gRestEndDate = nil
            gDidFireRestFinishedFeedback = false
            gIsRestingByExercise[exerciseId] = false
            gRemainingRestByExercise[exerciseId] = 0
            gRestEndDateByExercise[exerciseId] = nil
            gRestTotalPlannedByExercise[exerciseId] = nil
        case .guest2:
            g2IsResting = false
            g2RemainingRest = 0
            g2RestEndDate = nil
            g2DidFireRestFinishedFeedback = false
            g2IsRestingByExercise[exerciseId] = false
            g2RemainingRestByExercise[exerciseId] = 0
            g2RestEndDateByExercise[exerciseId] = nil
            g2RestTotalPlannedByExercise[exerciseId] = nil
        }
    }

    private func setsFor(_ ex: ExerciseRow, lane: StrengthLaneKind = .host) -> [SetRow] {
        let configs: [SetRow]
        switch lane {
        case .host: configs = setsByExercise[ex.id] ?? []
        case .guest: configs = gSetsByExercise[ex.id] ?? []
        case .guest2: configs = g2SetsByExercise[ex.id] ?? []
        }
        var expanded: [SetRow] = []

        for config in configs {
            let k = (config.weight_segments?.count ?? 0) >= 2 ? (config.weight_segments?.count ?? 1) : 1
            let macro = max(config.set_number, 0)

            for repIdx in 0..<macro {
                let sequentialNumber = expanded.count + 1
                let pseudoId = config.id * 100_000 + repIdx + 1
                let firstSeg = config.weight_segments?.first
                let pseudoSet = SetRow(
                    id: pseudoId,
                    workout_exercise_id: config.workout_exercise_id,
                    set_number: sequentialNumber,
                    reps: firstSeg?.reps ?? config.reps,
                    weight_kg: firstSeg != nil ? Decimal(firstSeg!.weight_kg) : config.weight_kg,
                    rpe: config.rpe,
                    rest_sec: config.rest_sec,
                    weight_segments: config.weight_segments,
                    configId: config.id,
                    segmentsInRow: k
                )
                expanded.append(pseudoSet)
            }
        }

        return expanded
    }

    private func startRest(for set: SetRow, lane: StrengthLaneKind = .host) {
        let ex: ExerciseRow? = {
            switch lane {
            case .host: return currentExercise
            case .guest: return currentGuestExercise
            case .guest2: return currentGuest2Exercise
            }
        }()
        guard let ex else { return }
        startRest(for: set, lane: lane, exercise: ex)
    }
    
    private func hasActiveRestInExerciseTimerDictionaries() -> Bool {
        if restEndDateByExercise.values.contains(where: { $0.timeIntervalSinceNow > 0 }) { return true }
        if gRestEndDateByExercise.values.contains(where: { $0.timeIntervalSinceNow > 0 }) { return true }
        if g2RestEndDateByExercise.values.contains(where: { $0.timeIntervalSinceNow > 0 }) { return true }
        return false
    }

    private func syncRestCountdownFromEndDate() {
        syncHostRestTimersFromDictionaries()
        syncGuestRestTimersFromDictionaries()
        syncGuest2RestTimersFromDictionaries()
    }

    private func syncHostRestTimersFromDictionaries() {
        for id in Array(restEndDateByExercise.keys) {
            guard let end = restEndDateByExercise[id] else {
                restEndDateByExercise.removeValue(forKey: id)
                continue
            }
            let newR = max(0, Int(ceil(end.timeIntervalSinceNow)))
            if newR <= 0 {
                isRestingByExercise[id] = false
                remainingRestByExercise[id] = 0
                restEndDateByExercise[id] = nil
                restTotalPlannedByExercise[id] = nil
                if id == currentExercise?.id {
                    isResting = false
                    remainingRest = 0
                    restEndDate = nil
                    if !didFireRestFinishedFeedback {
                        didFireRestFinishedFeedback = true
                        restFinishedFeedback()
                    }
                }
            } else {
                remainingRestByExercise[id] = newR
                isRestingByExercise[id] = true
                if restTotalPlannedByExercise[id] == nil {
                    restTotalPlannedByExercise[id] = max(1, newR)
                }
                if id == currentExercise?.id {
                    isResting = true
                    remainingRest = newR
                    restEndDate = end
                }
            }
        }
        if let cur = currentExercise?.id, restEndDateByExercise[cur] == nil, isResting {
            isResting = false
            remainingRest = 0
            restEndDate = nil
        }
    }

    private func syncGuestRestTimersFromDictionaries() {
        for id in Array(gRestEndDateByExercise.keys) {
            guard let end = gRestEndDateByExercise[id] else {
                gRestEndDateByExercise.removeValue(forKey: id)
                continue
            }
            let newR = max(0, Int(ceil(end.timeIntervalSinceNow)))
            if newR <= 0 {
                gIsRestingByExercise[id] = false
                gRemainingRestByExercise[id] = 0
                gRestEndDateByExercise[id] = nil
                gRestTotalPlannedByExercise[id] = nil
                if id == currentGuestExercise?.id {
                    gIsResting = false
                    gRemainingRest = 0
                    gRestEndDate = nil
                    if !gDidFireRestFinishedFeedback {
                        gDidFireRestFinishedFeedback = true
                        restFinishedFeedback()
                    }
                }
            } else {
                gRemainingRestByExercise[id] = newR
                gIsRestingByExercise[id] = true
                if gRestTotalPlannedByExercise[id] == nil {
                    gRestTotalPlannedByExercise[id] = max(1, newR)
                }
                if id == currentGuestExercise?.id {
                    gIsResting = true
                    gRemainingRest = newR
                    gRestEndDate = end
                }
            }
        }
        if let cur = currentGuestExercise?.id, gRestEndDateByExercise[cur] == nil, gIsResting {
            gIsResting = false
            gRemainingRest = 0
            gRestEndDate = nil
        }
    }

    private func syncGuest2RestTimersFromDictionaries() {
        for id in Array(g2RestEndDateByExercise.keys) {
            guard let end = g2RestEndDateByExercise[id] else {
                g2RestEndDateByExercise.removeValue(forKey: id)
                continue
            }
            let newR = max(0, Int(ceil(end.timeIntervalSinceNow)))
            if newR <= 0 {
                g2IsRestingByExercise[id] = false
                g2RemainingRestByExercise[id] = 0
                g2RestEndDateByExercise[id] = nil
                g2RestTotalPlannedByExercise[id] = nil
                if id == currentGuest2Exercise?.id {
                    g2IsResting = false
                    g2RemainingRest = 0
                    g2RestEndDate = nil
                    if !g2DidFireRestFinishedFeedback {
                        g2DidFireRestFinishedFeedback = true
                        restFinishedFeedback()
                    }
                }
            } else {
                g2RemainingRestByExercise[id] = newR
                g2IsRestingByExercise[id] = true
                if g2RestTotalPlannedByExercise[id] == nil {
                    g2RestTotalPlannedByExercise[id] = max(1, newR)
                }
                if id == currentGuest2Exercise?.id {
                    g2IsResting = true
                    g2RemainingRest = newR
                    g2RestEndDate = end
                }
            }
        }
        if let cur = currentGuest2Exercise?.id, g2RestEndDateByExercise[cur] == nil, g2IsResting {
            g2IsResting = false
            g2RemainingRest = 0
            g2RestEndDate = nil
        }
    }
    
    private func restFinishedFeedback() {
        beepWorkItem?.cancel()
        isBeeping = true

        let haptic = UINotificationFeedbackGenerator()
        haptic.prepare()

        let soundID: SystemSoundID = 1103
        let repeats = 6
        let interval: TimeInterval = 0.32

        let work = DispatchWorkItem { [soundID] in
            for i in 0..<repeats {
                DispatchQueue.main.asyncAfter(deadline: .now() + (interval * Double(i))) {
                    guard !beepWorkItem!.isCancelled else { return }
                    haptic.notificationOccurred(.success)
                    AudioServicesPlaySystemSound(soundID)
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + (interval * Double(repeats))) {
                self.isBeeping = false
            }
        }

        beepWorkItem = work
        DispatchQueue.main.async(execute: work)
    }

    private func playCustomRestSound() {
        guard let url = Bundle.main.url(forResource: "rest_end", withExtension: "mp3") else { return }

        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, options: [.duckOthers])
            try AVAudioSession.sharedInstance().setActive(true)

            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = 1.0
            player.prepareToPlay()
            player.play()
            restAudioPlayer = player
        } catch {
        }
    }
    
    private func completeCurrentSet(lane: StrengthLaneKind) {
        switch lane {
        case .host:
            guard let ex = currentExercise else { return }
            let completedSetIndex = currentSetIndex
            var sets = setsFor(ex, lane: .host)
            if sets.isEmpty {
                ensureBaseSetExists(for: ex, lane: .host)
                sets = setsFor(ex, lane: .host)
                if sets.isEmpty { return }
            }

            let completedRestSec = currentSetFor(ex, setIndex: currentSetIndex, lane: .host).map { $0.rest_sec ?? 0 } ?? 0

            if let s = currentSetFor(ex, setIndex: currentSetIndex, lane: .host) {
                var list = performedSetsByExercise[ex.id] ?? []
                let performed = PerformedSet(
                    reps: s.reps,
                    weight_kg: s.weight_kg,
                    rpe: s.rpe,
                    rest_sec: s.rest_sec,
                    configId: s.configId,
                    segmentsInRow: s.segmentsInRow,
                    weight_segments: s.weight_segments
                )
                list.append(performed)
                performedSetsByExercise[ex.id] = list
            }

            applySupersetSetIndexAdvancement(for: ex, lane: .host, completedSetIndex: completedSetIndex, totalSets: sets.count)
            snapSupersetVisitedRoundIfNeeded(for: ex, lane: .host)

            if navEmphasisLockExerciseIdHost == nil, completedRestSec == 0 {
                navEmphasisLockExerciseIdHost = ex.id
            }
            advanceToNextSupersetMemberIfNeeded(from: ex, lane: .host, setIndex: completedSetIndex)

        case .guest:
            guard let ex = currentGuestExercise else { return }
            let completedSetIndex = gCurrentSetIndex
            var sets = setsFor(ex, lane: .guest)
            if sets.isEmpty {
                ensureBaseSetExists(for: ex, lane: .guest)
                sets = setsFor(ex, lane: .guest)
                if sets.isEmpty { return }
            }

            let completedRestSec = currentSetFor(ex, setIndex: gCurrentSetIndex, lane: .guest).map { $0.rest_sec ?? 0 } ?? 0

            if let s = currentSetFor(ex, setIndex: gCurrentSetIndex, lane: .guest) {
                var list = gPerformedSetsByExercise[ex.id] ?? []
                let performed = PerformedSet(
                    reps: s.reps,
                    weight_kg: s.weight_kg,
                    rpe: s.rpe,
                    rest_sec: s.rest_sec,
                    configId: s.configId,
                    segmentsInRow: s.segmentsInRow,
                    weight_segments: s.weight_segments
                )
                list.append(performed)
                gPerformedSetsByExercise[ex.id] = list
            }

            applySupersetSetIndexAdvancement(for: ex, lane: .guest, completedSetIndex: completedSetIndex, totalSets: sets.count)
            snapSupersetVisitedRoundIfNeeded(for: ex, lane: .guest)

            if navEmphasisLockExerciseIdGuest == nil, completedRestSec == 0 {
                navEmphasisLockExerciseIdGuest = ex.id
            }
            advanceToNextSupersetMemberIfNeeded(from: ex, lane: .guest, setIndex: completedSetIndex)

        case .guest2:
            guard let ex = currentGuest2Exercise else { return }
            let completedSetIndex = g2CurrentSetIndex
            var sets = setsFor(ex, lane: .guest2)
            if sets.isEmpty {
                ensureBaseSetExists(for: ex, lane: .guest2)
                sets = setsFor(ex, lane: .guest2)
                if sets.isEmpty { return }
            }

            let completedRestSec = currentSetFor(ex, setIndex: g2CurrentSetIndex, lane: .guest2).map { $0.rest_sec ?? 0 } ?? 0

            if let s = currentSetFor(ex, setIndex: g2CurrentSetIndex, lane: .guest2) {
                var list = g2PerformedSetsByExercise[ex.id] ?? []
                let performed = PerformedSet(
                    reps: s.reps,
                    weight_kg: s.weight_kg,
                    rpe: s.rpe,
                    rest_sec: s.rest_sec,
                    configId: s.configId,
                    segmentsInRow: s.segmentsInRow,
                    weight_segments: s.weight_segments
                )
                list.append(performed)
                g2PerformedSetsByExercise[ex.id] = list
            }

            applySupersetSetIndexAdvancement(for: ex, lane: .guest2, completedSetIndex: completedSetIndex, totalSets: sets.count)
            snapSupersetVisitedRoundIfNeeded(for: ex, lane: .guest2)

            if navEmphasisLockExerciseIdGuest2 == nil, completedRestSec == 0 {
                navEmphasisLockExerciseIdGuest2 = ex.id
            }
            advanceToNextSupersetMemberIfNeeded(from: ex, lane: .guest2, setIndex: completedSetIndex)
        }
    }

    private func supersetMembers(for ex: ExerciseRow, lane: StrengthLaneKind) -> [ExerciseRow] {
        guard let groupId = ex.superset_group_id else { return [] }
        return orderedExercises(lane: lane)
            .filter { $0.superset_group_id == groupId }
            .sorted {
                let ap = $0.superset_position ?? Int.max
                let bp = $1.superset_position ?? Int.max
                if ap != bp { return ap < bp }
                return $0.order_index < $1.order_index
            }
    }

    private func shouldStartRestAfterCompletingSet(_ ex: ExerciseRow, lane: StrengthLaneKind, setIndex: Int) -> Bool {
        let members = supersetMembers(for: ex, lane: lane)
        guard members.count > 1 else { return true }
        let available = members.filter { setsFor($0, lane: lane).count > setIndex }
        guard let currentAvailableIndex = available.firstIndex(where: { $0.id == ex.id }) else { return true }
        return currentAvailableIndex == available.count - 1
    }

    private func nextSupersetMember(after ex: ExerciseRow, lane: StrengthLaneKind, setIndex: Int) -> ExerciseRow? {
        let members = supersetMembers(for: ex, lane: lane)
        guard members.count > 1 else { return nil }
        let available = members.filter { setsFor($0, lane: lane).count > setIndex }
        guard let currentAvailableIndex = available.firstIndex(where: { $0.id == ex.id }) else { return nil }
        if currentAvailableIndex < available.count - 1 {
            return available[currentAvailableIndex + 1]
        }
        return available.first(where: { $0.id != ex.id && effectiveSetIndex(for: $0, lane: lane) < setsFor($0, lane: lane).count })
    }

    private func advanceToNextSupersetMemberIfNeeded(from ex: ExerciseRow, lane: StrengthLaneKind, setIndex: Int) {
        guard let next = nextSupersetMember(after: ex, lane: lane, setIndex: setIndex),
              let idx = orderedExercises(lane: lane).firstIndex(where: { $0.id == next.id })
        else { return }
        persistStateForCurrentDualIndex()
        let pagerAnchor = pagerAnchorExerciseIndex(for: idx, lane: lane)
        switch lane {
        case .host:
            currentExerciseIndex = idx
            pagerDisplayIndexHost = pagerAnchor
            navEmphasisLockExerciseIdHost = nil
        case .guest:
            guestCurrentExerciseIndex = idx
            pagerDisplayIndexGuest = pagerAnchor
            navEmphasisLockExerciseIdGuest = nil
        case .guest2:
            g2CurrentExerciseIndex = idx
            pagerDisplayIndexGuest2 = pagerAnchor
            navEmphasisLockExerciseIdGuest2 = nil
        }
        restoreStateForDualIndex()
        dragOffsetY = 0
    }

    private func requestAddSet(for ex: ExerciseRow, lane: StrengthLaneKind) {
        let members = supersetMembers(for: ex, lane: lane)
        guard members.count > 1 else {
            applyAddSet(to: [ex], lane: lane)
            return
        }
        supersetSetActionCandidate = ex
        supersetSetActionLane = lane
        pendingSupersetSetAction = .add
        showSupersetSetActionConfirm = true
    }

    private func requestRemoveSet(for ex: ExerciseRow, lane: StrengthLaneKind) {
        let members = supersetMembers(for: ex, lane: lane)
        guard members.count > 1 else {
            removeOneSet(for: ex, lane: lane)
            return
        }
        supersetSetActionCandidate = ex
        supersetSetActionLane = lane
        pendingSupersetSetAction = .remove
        showSupersetSetActionConfirm = true
    }

    private func applyPendingSupersetSetAction(toAllMembers: Bool) {
        guard let ex = supersetSetActionCandidate, let action = pendingSupersetSetAction else {
            clearPendingSupersetSetAction()
            return
        }
        let lane = supersetSetActionLane
        let targets: [ExerciseRow]
        if toAllMembers {
            let members = supersetMembers(for: ex, lane: lane)
            targets = members.isEmpty ? [ex] : members
        } else {
            targets = [ex]
        }

        switch action {
        case .add:
            applyAddSet(to: targets, lane: lane)
        case .remove:
            applyRemoveSet(to: targets, lane: lane)
        }
        clearPendingSupersetSetAction()
    }

    private func clearPendingSupersetSetAction() {
        supersetSetActionCandidate = nil
        pendingSupersetSetAction = nil
    }

    private func applyAddSet(to targets: [ExerciseRow], lane: StrengthLaneKind) {
        for target in targets {
            ensureBaseSetExists(for: target, lane: lane)
            addOneSetToConfigs(for: target, lane: lane)
        }
        focusAfterAddingSets(to: targets, lane: lane)
        withAnimation {
            showToast(targets.count > 1 ? "Added 1 set to superserie" : "Added 1 set")
        }
    }

    private func focusAfterAddingSets(to targets: [ExerciseRow], lane: StrengthLaneKind) {
        guard let anchor = targets.first else { return }
        let members = supersetMembers(for: anchor, lane: lane)
        let focusTargets = members.count > 1 ? members : [anchor]

        for target in focusTargets {
            let total = setsFor(target, lane: lane).count
            guard total > 0 else { continue }
            let newIndex = preservedSetIndexAfterAdd(for: target.id, lane: lane, total: total)
            setCurrentSetIndex(newIndex, for: target, lane: lane)
            snapVisitedToCurrent(for: target, lane: lane)
        }

        if members.count > 1 {
            if let group = strengthDisplayGroups(lane: lane).first(where: { g in
                g.isSuperset && g.exerciseIndices.contains(where: { idx in
                    let list = orderedExercises(lane: lane)
                    return list.indices.contains(idx) && list[idx].id == anchor.id
                })
            }) {
                let workRound = supersetGroupWorkSetIndex(members: members, lane: lane)
                snapVisitedSupersetRoundToCurrent(for: group, workRound: workRound, lane: lane)
            }
        } else if let target = focusTargets.first {
            snapVisitedToCurrent(for: target, lane: lane)
        }
    }

    private func preservedSetIndexAfterAdd(for exerciseId: Int, lane: StrengthLaneKind, total: Int) -> Int {
        let previous: Int
        switch lane {
        case .host:
            previous = currentSetIndexByExercise[exerciseId]
                ?? (currentExercise?.id == exerciseId ? currentSetIndex : 0)
        case .guest:
            previous = gCurrentSetIndexByExercise[exerciseId]
                ?? (currentGuestExercise?.id == exerciseId ? gCurrentSetIndex : 0)
        case .guest2:
            previous = g2CurrentSetIndexByExercise[exerciseId]
                ?? (currentGuest2Exercise?.id == exerciseId ? g2CurrentSetIndex : 0)
        }
        return min(max(0, previous), max(0, total - 1))
    }

    private func applyRemoveSet(to targets: [ExerciseRow], lane: StrengthLaneKind) {
        for target in targets {
            removeOneSet(for: target, lane: lane, showsToast: false)
        }
        withAnimation {
            showToast(targets.count > 1 ? "Removed 1 set from superserie" : "Removed 1 set")
        }
    }

    private func addOneSetToConfigs(for ex: ExerciseRow, lane: StrengthLaneKind = .host) {
        let key = ex.id
        switch lane {
        case .host:
            var configs = setsByExercise[key] ?? []

            if configs.isEmpty {
                ensureBaseSetExists(for: ex, lane: .host)
                configs = setsByExercise[key] ?? []
                if configs.isEmpty { return }
            }

            let lastIdx = configs.count - 1
            let last = configs[lastIdx]

            configs[lastIdx] = SetRow(
                id: last.id,
                workout_exercise_id: last.workout_exercise_id,
                set_number: max(0, last.set_number) + 1,
                reps: last.reps,
                weight_kg: last.weight_kg,
                rpe: last.rpe,
                rest_sec: last.rest_sec,
                weight_segments: last.weight_segments,
                configId: last.id,
                segmentsInRow: last.segmentsInRow
            )

            setsByExercise[key] = configs

            let total = setsFor(ex, lane: .host).count
            let newIndex = preservedSetIndexAfterAdd(for: key, lane: .host, total: total)
            if currentExercise?.id == key {
                currentSetIndex = newIndex
            }
            currentSetIndexByExercise[key] = newIndex

        case .guest:
            var configs = gSetsByExercise[key] ?? []

            if configs.isEmpty {
                ensureBaseSetExists(for: ex, lane: .guest)
                configs = gSetsByExercise[key] ?? []
                if configs.isEmpty { return }
            }

            let lastIdx = configs.count - 1
            let last = configs[lastIdx]

            configs[lastIdx] = SetRow(
                id: last.id,
                workout_exercise_id: last.workout_exercise_id,
                set_number: max(0, last.set_number) + 1,
                reps: last.reps,
                weight_kg: last.weight_kg,
                rpe: last.rpe,
                rest_sec: last.rest_sec,
                weight_segments: last.weight_segments,
                configId: last.id,
                segmentsInRow: last.segmentsInRow
            )

            gSetsByExercise[key] = configs

            let total = setsFor(ex, lane: .guest).count
            let newIndex = preservedSetIndexAfterAdd(for: key, lane: .guest, total: total)
            if currentGuestExercise?.id == key {
                gCurrentSetIndex = newIndex
            }
            gCurrentSetIndexByExercise[key] = newIndex

        case .guest2:
            var configs = g2SetsByExercise[key] ?? []

            if configs.isEmpty {
                ensureBaseSetExists(for: ex, lane: .guest2)
                configs = g2SetsByExercise[key] ?? []
                if configs.isEmpty { return }
            }

            let lastIdx = configs.count - 1
            let last = configs[lastIdx]

            configs[lastIdx] = SetRow(
                id: last.id,
                workout_exercise_id: last.workout_exercise_id,
                set_number: max(0, last.set_number) + 1,
                reps: last.reps,
                weight_kg: last.weight_kg,
                rpe: last.rpe,
                rest_sec: last.rest_sec,
                weight_segments: last.weight_segments,
                configId: last.id,
                segmentsInRow: last.segmentsInRow
            )

            g2SetsByExercise[key] = configs

            let total = setsFor(ex, lane: .guest2).count
            let newIndex = preservedSetIndexAfterAdd(for: key, lane: .guest2, total: total)
            if currentGuest2Exercise?.id == key {
                g2CurrentSetIndex = newIndex
            }
            g2CurrentSetIndexByExercise[key] = newIndex
        }
    }

    private func ensureBaseSetExists(for ex: ExerciseRow, lane: StrengthLaneKind = .host) {
        let key = ex.id
        let planned = setsFor(ex, lane: lane).count
        if planned > 0 { return }

        let sid = Int.random(in: 1_000_000...9_999_999)
        let base = SetRow(
            id: sid,
            workout_exercise_id: ex.id,
            set_number: 1,
            reps: 10,
            weight_kg: 0,
            rpe: nil,
            rest_sec: 60,
            weight_segments: nil,
            configId: sid,
            segmentsInRow: 1
        )
        switch lane {
        case .host: setsByExercise[key] = [base]
        case .guest: gSetsByExercise[key] = [base]
        case .guest2: g2SetsByExercise[key] = [base]
        }
    }

    private func canRemoveAnySet(for ex: ExerciseRow, lane: StrengthLaneKind = .host) -> Bool {
        setsFor(ex, lane: lane).count > 0
    }

    private func removeOneSet(for ex: ExerciseRow, lane: StrengthLaneKind = .host, showsToast: Bool = true) {
        let key = ex.id

        switch lane {
        case .host:
            var configs = setsByExercise[key] ?? []
            guard !configs.isEmpty else {
                if showsToast { showToast("No sets to remove") }
                return
            }

            let lastIdx = configs.count - 1
            let last = configs[lastIdx]
            let newCount = max(0, last.set_number - 1)

            configs[lastIdx] = SetRow(
                id: last.id,
                workout_exercise_id: last.workout_exercise_id,
                set_number: newCount,
                reps: last.reps,
                weight_kg: last.weight_kg,
                rpe: last.rpe,
                rest_sec: last.rest_sec,
                weight_segments: last.weight_segments,
                configId: last.id,
                segmentsInRow: last.segmentsInRow
            )

            if configs[lastIdx].set_number == 0 {
                configs.remove(at: lastIdx)
            }

            setsByExercise[key] = configs

            let totalNow = setsFor(ex, lane: .host).count

            if var performed = performedSetsByExercise[key], performed.count > totalNow {
                performed = Array(performed.prefix(totalNow))
                performedSetsByExercise[key] = performed
                if showsToast { showToast("Removed 1 set (and adjusted completed sets)") }
            } else {
                if showsToast { showToast("Removed 1 set") }
            }

            let currentIdxForThisExercise = currentSetIndexByExercise[key] ?? 0
            var newIdxForThisExercise = currentIdxForThisExercise

            if newIdxForThisExercise > totalNow {
                newIdxForThisExercise = totalNow
            } else if totalNow > 0, newIdxForThisExercise == totalNow {
                newIdxForThisExercise = totalNow - 1
            } else if totalNow == 0 {
                newIdxForThisExercise = 0
            }

            currentSetIndexByExercise[key] = newIdxForThisExercise

            if currentExercise?.id == key {
                currentSetIndex = newIdxForThisExercise
            }

            isRestingByExercise[key] = false
            remainingRestByExercise[key] = 0

            if currentExercise?.id == key {
                isResting = false
                remainingRest = 0
                restEndDate = nil
                restEndDateByExercise[key] = nil
                didFireRestFinishedFeedback = false
            }

        case .guest:
            var configs = gSetsByExercise[key] ?? []
            guard !configs.isEmpty else {
                if showsToast { showToast("No sets to remove") }
                return
            }

            let lastIdx = configs.count - 1
            let last = configs[lastIdx]
            let newCount = max(0, last.set_number - 1)

            configs[lastIdx] = SetRow(
                id: last.id,
                workout_exercise_id: last.workout_exercise_id,
                set_number: newCount,
                reps: last.reps,
                weight_kg: last.weight_kg,
                rpe: last.rpe,
                rest_sec: last.rest_sec,
                weight_segments: last.weight_segments,
                configId: last.id,
                segmentsInRow: last.segmentsInRow
            )

            if configs[lastIdx].set_number == 0 {
                configs.remove(at: lastIdx)
            }

            gSetsByExercise[key] = configs

            let totalNow = setsFor(ex, lane: .guest).count

            if var performed = gPerformedSetsByExercise[key], performed.count > totalNow {
                performed = Array(performed.prefix(totalNow))
                gPerformedSetsByExercise[key] = performed
                if showsToast { showToast("Removed 1 set (and adjusted completed sets)") }
            } else {
                if showsToast { showToast("Removed 1 set") }
            }

            let currentIdxForThisExercise = gCurrentSetIndexByExercise[key] ?? 0
            var newIdxForThisExercise = currentIdxForThisExercise

            if newIdxForThisExercise > totalNow {
                newIdxForThisExercise = totalNow
            } else if totalNow > 0, newIdxForThisExercise == totalNow {
                newIdxForThisExercise = totalNow - 1
            } else if totalNow == 0 {
                newIdxForThisExercise = 0
            }

            gCurrentSetIndexByExercise[key] = newIdxForThisExercise

            if currentGuestExercise?.id == key {
                gCurrentSetIndex = newIdxForThisExercise
            }

            gIsRestingByExercise[key] = false
            gRemainingRestByExercise[key] = 0

            if currentGuestExercise?.id == key {
                gIsResting = false
                gRemainingRest = 0
                gRestEndDate = nil
                gRestEndDateByExercise[key] = nil
                gDidFireRestFinishedFeedback = false
            }

        case .guest2:
            var configs = g2SetsByExercise[key] ?? []
            guard !configs.isEmpty else {
                if showsToast { showToast("No sets to remove") }
                return
            }

            let lastIdx = configs.count - 1
            let last = configs[lastIdx]
            let newCount = max(0, last.set_number - 1)

            configs[lastIdx] = SetRow(
                id: last.id,
                workout_exercise_id: last.workout_exercise_id,
                set_number: newCount,
                reps: last.reps,
                weight_kg: last.weight_kg,
                rpe: last.rpe,
                rest_sec: last.rest_sec,
                weight_segments: last.weight_segments,
                configId: last.id,
                segmentsInRow: last.segmentsInRow
            )

            if configs[lastIdx].set_number == 0 {
                configs.remove(at: lastIdx)
            }

            g2SetsByExercise[key] = configs

            let totalNow = setsFor(ex, lane: .guest2).count

            if var performed = g2PerformedSetsByExercise[key], performed.count > totalNow {
                performed = Array(performed.prefix(totalNow))
                g2PerformedSetsByExercise[key] = performed
                if showsToast { showToast("Removed 1 set (and adjusted completed sets)") }
            } else {
                if showsToast { showToast("Removed 1 set") }
            }

            let currentIdxForThisExercise = g2CurrentSetIndexByExercise[key] ?? 0
            var newIdxForThisExercise = currentIdxForThisExercise

            if newIdxForThisExercise > totalNow {
                newIdxForThisExercise = totalNow
            } else if totalNow > 0, newIdxForThisExercise == totalNow {
                newIdxForThisExercise = totalNow - 1
            } else if totalNow == 0 {
                newIdxForThisExercise = 0
            }

            g2CurrentSetIndexByExercise[key] = newIdxForThisExercise

            if currentGuest2Exercise?.id == key {
                g2CurrentSetIndex = newIdxForThisExercise
            }

            g2IsRestingByExercise[key] = false
            g2RemainingRestByExercise[key] = 0

            if currentGuest2Exercise?.id == key {
                g2IsResting = false
                g2RemainingRest = 0
                g2RestEndDate = nil
                g2RestEndDateByExercise[key] = nil
                g2DidFireRestFinishedFeedback = false
            }
        }
    }

    private func goToNextExercise() {
        let lane = mainDisplayLane
        let workIdx: Int = {
            switch lane {
            case .host: return currentExerciseIndex
            case .guest: return guestCurrentExerciseIndex
            case .guest2: return g2CurrentExerciseIndex
            }
        }()
        let groups = strengthDisplayGroups(lane: lane)
        guard let gi = displayGroupIndex(forExerciseIndex: workIdx, lane: lane),
              gi + 1 < groups.count,
              let nextIdx = groups[gi + 1].exerciseIndices.first
        else { return }

        persistStateForCurrentDualIndex()

        switch lane {
        case .host: navEmphasisLockExerciseIdHost = nil
        case .guest: navEmphasisLockExerciseIdGuest = nil
        case .guest2: navEmphasisLockExerciseIdGuest2 = nil
        }

        jumpToExercise(lane: lane, index: nextIdx)
    }

    private func pagerShiftForward() {
        let lane = mainDisplayLane
        let groups = strengthDisplayGroups(lane: lane)
        guard let gi = displayGroupIndex(forExerciseIndex: pagerExerciseIndex, lane: lane),
              gi + 1 < groups.count,
              let nextIdx = groups[gi + 1].exerciseIndices.first
        else { return }
        jumpToExercise(lane: lane, index: nextIdx)
    }
    
    private func pagerShiftBackward() {
        let lane = mainDisplayLane
        let groups = strengthDisplayGroups(lane: lane)
        guard let gi = displayGroupIndex(forExerciseIndex: pagerExerciseIndex, lane: lane),
              gi > 0,
              let prevIdx = groups[gi - 1].exerciseIndices.first
        else { return }
        jumpToExercise(lane: lane, index: prevIdx)
    }

    private func laneBlocksExerciseSwipe(_ lane: StrengthLaneKind) -> Bool {
        let list = orderedExercises(lane: lane)
        let laneIdx: Int = {
            switch lane {
            case .host: return currentExerciseIndex
            case .guest: return guestCurrentExerciseIndex
            case .guest2: return g2CurrentExerciseIndex
            }
        }()
        guard laneIdx >= 0, laneIdx < list.count else { return false }
        let ex = list[laneIdx]
        let resting: Bool = {
            switch lane {
            case .host: return isResting
            case .guest: return gIsResting
            case .guest2: return g2IsResting
            }
        }()
        guard resting else { return false }
        let idx = currentSetIndex(for: lane)
        let total = setsFor(ex, lane: lane).count
        let isDone = total > 0 && currentSetFor(ex, setIndex: idx, lane: lane) == nil
        return !isDone
    }

    private func canSwipeBetweenExercises() -> Bool {
        if showCountdown { return false }
        if isSaving { return false }
        if showEditSheet { return false }
        if showActiveExercisePicker { return false }
        if showActiveExerciseSetup { return false }
        if isPersistingActiveExerciseEdit { return false }
        if isTransitioningExercise { return false }

        if laneBlocksExerciseSwipe(mainDisplayLane) { return false }

        if pagerCurrentDisplayGroup?.isSuperset == true { return false }

        return true
    }
    
    private func canGoNextExercise() -> Bool {
        let lane = mainDisplayLane
        let groups = strengthDisplayGroups(lane: lane)
        guard !groups.isEmpty,
              let gi = displayGroupIndex(forExerciseIndex: pagerExerciseIndex, lane: lane)
        else { return false }
        return gi < groups.count - 1
    }

    private func canGoPreviousExercise() -> Bool {
        let lane = mainDisplayLane
        guard let gi = displayGroupIndex(forExerciseIndex: pagerExerciseIndex, lane: lane) else { return false }
        return gi > 0
    }

    private var shouldShowExerciseNavStrip: Bool {
        guard !loading && error == nil && !showCountdown else { return false }
        if isDualMode {
            return !orderedExercises.isEmpty || !orderedGuestExercises.isEmpty
                || (isTripleMode && !orderedGuest2Exercises.isEmpty)
        }
        return currentExercise != nil && !orderedExercises.isEmpty
    }
    
    private func effectiveSetIndex(for ex: ExerciseRow, lane: StrengthLaneKind = .host) -> Int {
        switch lane {
        case .host:
            if currentExercise?.id == ex.id {
                return currentSetIndex
            }
            return currentSetIndexByExercise[ex.id] ?? 0
        case .guest:
            if currentGuestExercise?.id == ex.id {
                return gCurrentSetIndex
            }
            return gCurrentSetIndexByExercise[ex.id] ?? 0
        case .guest2:
            if currentGuest2Exercise?.id == ex.id {
                return g2CurrentSetIndex
            }
            return g2CurrentSetIndexByExercise[ex.id] ?? 0
        }
    }
    
    private func isExerciseCompleted(_ ex: ExerciseRow, lane: StrengthLaneKind = .host) -> Bool {
        let total = setsFor(ex, lane: lane).count
        guard total > 0 else { return false }
        return effectiveSetIndex(for: ex, lane: lane) >= total
    }

    private func exerciseCompletionProgress(_ ex: ExerciseRow, lane: StrengthLaneKind = .host) -> Double {
        let total = setsFor(ex, lane: lane).count
        guard total > 0 else { return 0 }
        let completedSets = min(max(0, effectiveSetIndex(for: ex, lane: lane)), total)
        return Double(completedSets) / Double(total)
    }

    private var canJumpBetweenExercises: Bool {
        !showCountdown
            && !isSaving
            && !showEditSheet
            && !showActiveExercisePicker
            && !showActiveExerciseSetup
            && !isPersistingActiveExerciseEdit
            && !isTransitioningExercise
    }

    private var canModifyActiveExercises: Bool {
        canJumpBetweenExercises && !showDeleteExerciseConfirm && !showSupersetSetActionConfirm
    }

    @ViewBuilder
    private func dualPagerMissingExerciseFallback(cardHeight: CGFloat) -> some View {
        VStack(spacing: 12) {
            if mainDisplayLane == .guest, orderedGuestExercises.isEmpty {
                Image(systemName: "person.2.slash")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("Partner workout has no exercises.")
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.center)
                if let ge = guestDataError, !ge.isEmpty {
                    Text(ge)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            } else if mainDisplayLane == .guest2, orderedGuest2Exercises.isEmpty {
                Image(systemName: "person.2.slash")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("Second partner workout has no exercises.")
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.center)
                if let ge = guest2DataError, !ge.isEmpty {
                    Text(ge)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            } else {
                ProgressView()
                Text("Loading partner workout…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            activeAddExerciseButton(lane: mainDisplayLane, compact: false)
        }
        .frame(maxWidth: .infinity)
        .frame(height: cardHeight)
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    private func activeExerciseEmptyState(lane: StrengthLaneKind) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "dumbbell")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            VStack(spacing: 6) {
                Text("No exercises found")
                    .font(.headline)
                Text("Add an exercise and configure its sets to continue this workout.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            activeAddExerciseButton(lane: lane, compact: false)
            Button("Close") { dismiss() }
                .buttonStyle(.bordered)
        }
        .padding()
    }

    @ViewBuilder
    private func activeAddExerciseButton(lane: StrengthLaneKind, compact: Bool) -> some View {
        Button {
            startActiveExerciseAdd(lane: lane)
        } label: {
            if compact {
                VStack(spacing: 5) {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .bold))
                        .frame(width: 34, height: 34)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay(Circle().stroke(Color.accentColor.opacity(0.65), lineWidth: 1))
                    Text("Add")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } else {
                Label("Add exercise", systemImage: "plus.circle.fill")
                    .font(.headline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.accentColor)
                    )
                    .foregroundColor(.white)
            }
        }
        .buttonStyle(.plain)
        .disabled(!canModifyActiveExercises)
        .opacity(canModifyActiveExercises ? 1 : 0.45)
        .accessibilityLabel("Add exercise")
    }

    private func activeExerciseSetupSheet() -> some View {
        NavigationStack {
            ZStack {
                Color.clear
                    .gradientBG()
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(activeExerciseSetupDrafts.count > 1 ? "Superserie" : (activeExerciseSetupDrafts.first?.exercise.localizedName(for: exerciseLanguageFromGlobalStorage()) ?? "Exercise"))
                                .font(.title3.weight(.semibold))
                            Text(activeExerciseSetupDrafts.count > 1 ? "Configure each exercise. The active workout will alternate them set-by-set." : "Configure the sets before adding it to this active workout.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        VStack(spacing: 16) {
                            ForEach(activeExerciseSetupDrafts) { draft in
                                activeExerciseSetupExerciseCard(draft)
                            }
                        }

                        HStack(spacing: 10) {
                            Button {
                                addSetToActiveSetupDraft()
                            } label: {
                                Label("Add set", systemImage: "plus.circle")
                            }
                            .buttonStyle(.bordered)

                            Button(role: .destructive) {
                                removeSetFromActiveSetupDraft()
                            } label: {
                                Label("Remove set", systemImage: "minus.circle")
                            }
                            .buttonStyle(.bordered)
                            .disabled(!canRemoveSetFromActiveSetupDraft)
                        }

                        Button {
                            showActiveExercisePicker = true
                        } label: {
                            Label("Add superserie exercise", systemImage: "link.badge.plus")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                        }
                        .buttonStyle(.bordered)
                        .disabled(isPersistingActiveExerciseEdit)

                        if activeExerciseSetupDrafts.count > 1 {
                            Text("Superserie order: \(activeExerciseSetupDrafts.map { $0.exercise.localizedName(for: exerciseLanguageFromGlobalStorage()) }.joined(separator: " → "))")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }

                        if let activeExerciseSetupError {
                            Text(activeExerciseSetupError)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Configure exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        resetActiveExerciseSetup()
                    }
                    .disabled(isPersistingActiveExerciseEdit)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await saveConfiguredActiveExercise() }
                    } label: {
                        if isPersistingActiveExerciseEdit {
                            ProgressView()
                        } else {
                            Text("Add")
                        }
                    }
                    .disabled(isPersistingActiveExerciseEdit || activeExerciseSetupDrafts.isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func activeExerciseSetupExerciseCard(_ draft: ActiveExerciseSetupExercise) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(draft.exercise.localizedName(for: exerciseLanguageFromGlobalStorage()))
                        .font(.headline.weight(.semibold))
                    if activeExerciseSetupDrafts.count > 1, let pos = activeExerciseSetupDrafts.firstIndex(where: { $0.id == draft.id }) {
                        Text("Superserie \(pos + 1)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if activeExerciseSetupDrafts.count > 1 {
                    Button(role: .destructive) {
                        removeActiveSetupDraft(draft.id)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Remove superserie exercise")
                }
            }

            ForEach(draft.sets) { row in
                activeExerciseSetupRow(
                    exerciseId: draft.id,
                    row: row,
                    index: draft.sets.firstIndex(where: { $0.id == row.id }) ?? 0
                )
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private func activeExerciseSetupRow(exerciseId: UUID, row: ActiveExerciseSetupSet, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Set \(index + 1)")
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }

            if row.dropSegments.count >= 2 {
                ForEach(row.dropSegments) { segment in
                    let segmentIndex = row.dropSegments.firstIndex(where: { $0.id == segment.id }) ?? 0
                    HStack(alignment: .top, spacing: 6) {
                        Text("\(segmentIndex + 1)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 24, alignment: .leading)
                        StrengthStyleMetricField(title: "Reps") {
                            TextField("—", text: dropSegmentRepsBinding(exerciseId: exerciseId, setId: row.id, segmentId: segment.id))
                                .font(.body)
                                .keyboardType(.numberPad)
                        }
                        StrengthStyleMetricField(title: "kg") {
                            TextField("—", text: dropSegmentWeightBinding(exerciseId: exerciseId, setId: row.id, segmentId: segment.id))
                                .font(.body)
                                .keyboardType(.decimalPad)
                        }
                    }
                }
                HStack(spacing: 8) {
                    Button("Add step") {
                        appendDropSegment(exerciseId: exerciseId, setId: row.id)
                    }
                    .buttonStyle(.borderless)
                    .disabled(row.dropSegments.count >= 12)
                    Button("Remove step") {
                        removeDropSegment(exerciseId: exerciseId, setId: row.id)
                    }
                    .buttonStyle(.borderless)
                    .disabled(row.dropSegments.count <= 2)
                    Button("Clear drop") {
                        clearDropSet(exerciseId: exerciseId, setId: row.id)
                    }
                    .buttonStyle(.borderless)
                }
                .font(.caption.weight(.semibold))
                HStack(alignment: .top, spacing: 6) {
                    StrengthStyleMetricField(title: "Rest s") {
                        TextField("60", text: setupSetTextBinding(exerciseId: exerciseId, setId: row.id, keyPath: \.restText))
                            .font(.body)
                            .keyboardType(.numberPad)
                    }
                    StrengthStyleMetricField(title: "RPE") {
                        TextField("—", text: setupSetTextBinding(exerciseId: exerciseId, setId: row.id, keyPath: \.rpeText))
                            .font(.body)
                            .keyboardType(.decimalPad)
                    }
                }
            } else {
                HStack(alignment: .top, spacing: 6) {
                    StrengthStyleMetricField(title: "Reps") {
                        TextField("10", text: setupSetTextBinding(exerciseId: exerciseId, setId: row.id, keyPath: \.repsText))
                            .font(.body)
                            .keyboardType(.numberPad)
                    }
                    StrengthStyleMetricField(title: "kg") {
                        TextField("0", text: setupSetTextBinding(exerciseId: exerciseId, setId: row.id, keyPath: \.weightText))
                            .font(.body)
                            .keyboardType(.decimalPad)
                    }
                }
                HStack(alignment: .top, spacing: 6) {
                    StrengthStyleMetricField(title: "Rest s") {
                        TextField("60", text: setupSetTextBinding(exerciseId: exerciseId, setId: row.id, keyPath: \.restText))
                            .font(.body)
                            .keyboardType(.numberPad)
                    }
                    StrengthStyleMetricField(title: "RPE") {
                        TextField("—", text: setupSetTextBinding(exerciseId: exerciseId, setId: row.id, keyPath: \.rpeText))
                            .font(.body)
                            .keyboardType(.decimalPad)
                    }
                }
                Button("Drop set") {
                    convertSetupSetToDropSet(exerciseId: exerciseId, setId: row.id)
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.borderless)
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 14))
    }

    @MainActor
    private func startActiveExerciseAdd(lane: StrengthLaneKind) {
        guard canModifyActiveExercises else { return }
        guard workoutId(for: lane) != nil else {
            showToast("This workout lane is not available.")
            return
        }
        activeExerciseSetupLane = lane
        activeExerciseSetupDrafts = []
        activeExerciseSetupError = nil
        showActiveExercisePicker = true
    }

    @MainActor
    private func appendExerciseToActiveSetup(_ exercise: Exercise) {
        activeExerciseSetupError = nil
        if activeExerciseSetupDrafts.isEmpty {
            activeExerciseSetupDrafts = [ActiveExerciseSetupExercise(exercise: exercise)]
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 200_000_000)
                showActiveExerciseSetup = true
            }
        } else if !activeExerciseSetupDrafts.contains(where: { $0.exercise.id == exercise.id }) {
            activeExerciseSetupDrafts.append(ActiveExerciseSetupExercise(exercise: exercise))
            showActiveExerciseSetup = true
        }
    }

    @MainActor
    private func resetActiveExerciseSetup() {
        showActiveExerciseSetup = false
        activeExerciseSetupDrafts = []
        activeExerciseSetupError = nil
    }

    private var canRemoveSetFromActiveSetupDraft: Bool {
        activeExerciseSetupDrafts.contains { $0.sets.count > 1 }
    }

    private func addSetToActiveSetupDraft() {
        for idx in activeExerciseSetupDrafts.indices {
            activeExerciseSetupDrafts[idx].sets.append(ActiveExerciseSetupSet())
        }
    }

    private func removeSetFromActiveSetupDraft() {
        for idx in activeExerciseSetupDrafts.indices {
            if activeExerciseSetupDrafts[idx].sets.count > 1 {
                activeExerciseSetupDrafts[idx].sets.removeLast()
            }
        }
    }

    private func removeActiveSetupDraft(_ id: UUID) {
        activeExerciseSetupDrafts.removeAll { $0.id == id }
        if activeExerciseSetupDrafts.isEmpty {
            resetActiveExerciseSetup()
        }
    }

    private func setupSetTextBinding(
        exerciseId: UUID,
        setId: UUID,
        keyPath: WritableKeyPath<ActiveExerciseSetupSet, String>
    ) -> Binding<String> {
        Binding(
            get: {
                guard let draftIdx = activeExerciseSetupDrafts.firstIndex(where: { $0.id == exerciseId }),
                      let setIdx = activeExerciseSetupDrafts[draftIdx].sets.firstIndex(where: { $0.id == setId })
                else { return "" }
                return activeExerciseSetupDrafts[draftIdx].sets[setIdx][keyPath: keyPath]
            },
            set: { newValue in
                guard let draftIdx = activeExerciseSetupDrafts.firstIndex(where: { $0.id == exerciseId }),
                      let setIdx = activeExerciseSetupDrafts[draftIdx].sets.firstIndex(where: { $0.id == setId })
                else { return }
                activeExerciseSetupDrafts[draftIdx].sets[setIdx][keyPath: keyPath] = newValue
            }
        )
    }

    private func dropSegmentRepsBinding(exerciseId: UUID, setId: UUID, segmentId: UUID) -> Binding<String> {
        Binding(
            get: {
                guard let segment = setupDropSegment(exerciseId: exerciseId, setId: setId, segmentId: segmentId) else { return "" }
                return segment.reps.map(String.init) ?? ""
            },
            set: { newValue in
                updateDropSegment(exerciseId: exerciseId, setId: setId, segmentId: segmentId) { segment in
                    let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    segment.reps = trimmed.isEmpty ? nil : Int(trimmed)
                }
            }
        )
    }

    private func dropSegmentWeightBinding(exerciseId: UUID, setId: UUID, segmentId: UUID) -> Binding<String> {
        Binding(
            get: {
                setupDropSegment(exerciseId: exerciseId, setId: setId, segmentId: segmentId)?.weightKg ?? ""
            },
            set: { newValue in
                updateDropSegment(exerciseId: exerciseId, setId: setId, segmentId: segmentId) { segment in
                    segment.weightKg = newValue
                }
            }
        )
    }

    private func setupDropSegment(exerciseId: UUID, setId: UUID, segmentId: UUID) -> StrengthEditorSegment? {
        guard let draftIdx = activeExerciseSetupDrafts.firstIndex(where: { $0.id == exerciseId }),
              let setIdx = activeExerciseSetupDrafts[draftIdx].sets.firstIndex(where: { $0.id == setId }),
              let segmentIdx = activeExerciseSetupDrafts[draftIdx].sets[setIdx].dropSegments.firstIndex(where: { $0.id == segmentId })
        else { return nil }
        return activeExerciseSetupDrafts[draftIdx].sets[setIdx].dropSegments[segmentIdx]
    }

    private func updateDropSegment(
        exerciseId: UUID,
        setId: UUID,
        segmentId: UUID,
        update: (inout StrengthEditorSegment) -> Void
    ) {
        guard let draftIdx = activeExerciseSetupDrafts.firstIndex(where: { $0.id == exerciseId }),
              let setIdx = activeExerciseSetupDrafts[draftIdx].sets.firstIndex(where: { $0.id == setId }),
              let segmentIdx = activeExerciseSetupDrafts[draftIdx].sets[setIdx].dropSegments.firstIndex(where: { $0.id == segmentId })
        else { return }
        update(&activeExerciseSetupDrafts[draftIdx].sets[setIdx].dropSegments[segmentIdx])
    }

    private func convertSetupSetToDropSet(exerciseId: UUID, setId: UUID) {
        guard let draftIdx = activeExerciseSetupDrafts.firstIndex(where: { $0.id == exerciseId }),
              let setIdx = activeExerciseSetupDrafts[draftIdx].sets.firstIndex(where: { $0.id == setId })
        else { return }
        let set = activeExerciseSetupDrafts[draftIdx].sets[setIdx]
        activeExerciseSetupDrafts[draftIdx].sets[setIdx].dropSegments = [
            StrengthEditorSegment(reps: Int(set.repsText.trimmingCharacters(in: .whitespacesAndNewlines)), weightKg: set.weightText),
            StrengthEditorSegment(reps: nil, weightKg: "")
        ]
    }

    private func appendDropSegment(exerciseId: UUID, setId: UUID) {
        guard let draftIdx = activeExerciseSetupDrafts.firstIndex(where: { $0.id == exerciseId }),
              let setIdx = activeExerciseSetupDrafts[draftIdx].sets.firstIndex(where: { $0.id == setId })
        else { return }
        activeExerciseSetupDrafts[draftIdx].sets[setIdx].dropSegments.append(StrengthEditorSegment(reps: nil, weightKg: ""))
    }

    private func removeDropSegment(exerciseId: UUID, setId: UUID) {
        guard let draftIdx = activeExerciseSetupDrafts.firstIndex(where: { $0.id == exerciseId }),
              let setIdx = activeExerciseSetupDrafts[draftIdx].sets.firstIndex(where: { $0.id == setId }),
              activeExerciseSetupDrafts[draftIdx].sets[setIdx].dropSegments.count > 2
        else { return }
        activeExerciseSetupDrafts[draftIdx].sets[setIdx].dropSegments.removeLast()
    }

    private func clearDropSet(exerciseId: UUID, setId: UUID) {
        guard let draftIdx = activeExerciseSetupDrafts.firstIndex(where: { $0.id == exerciseId }),
              let setIdx = activeExerciseSetupDrafts[draftIdx].sets.firstIndex(where: { $0.id == setId })
        else { return }
        activeExerciseSetupDrafts[draftIdx].sets[setIdx].dropSegments = []
    }

    private func parseActiveExerciseSetupRows(_ rows: [ActiveExerciseSetupSet]) -> [ActiveExerciseSetupParsedSet]? {
        var parsed: [ActiveExerciseSetupParsedSet] = []
        for (idx, row) in rows.enumerated() {
            let repsRaw = row.repsText.trimmingCharacters(in: .whitespacesAndNewlines)
            let reps: Int?
            if repsRaw.isEmpty {
                reps = nil
            } else if let value = Int(repsRaw), value >= 0 {
                reps = value
            } else {
                activeExerciseSetupError = "Set \(idx + 1) has invalid reps."
                return nil
            }

            let weightRaw = row.weightText
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: ",", with: ".")
            let weight: Decimal?
            if weightRaw.isEmpty {
                weight = nil
            } else if let value = Decimal(string: weightRaw), value >= 0 {
                weight = value
            } else {
                activeExerciseSetupError = "Set \(idx + 1) has invalid weight."
                return nil
            }

            let rpeRaw = row.rpeText
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: ",", with: ".")
            let rpe: Decimal?
            if rpeRaw.isEmpty {
                rpe = nil
            } else if let value = Decimal(string: rpeRaw), value >= 0 {
                rpe = value
            } else {
                activeExerciseSetupError = "Set \(idx + 1) has invalid RPE."
                return nil
            }

            let restRaw = row.restText.trimmingCharacters(in: .whitespacesAndNewlines)
            let rest: Int?
            if restRaw.isEmpty {
                rest = nil
            } else if let value = Int(restRaw), value >= 0 {
                rest = value
            } else {
                activeExerciseSetupError = "Set \(idx + 1) has invalid rest."
                return nil
            }

            let weightSegments: [StrengthWeightSegWire]?
            if row.dropSegments.count >= 2 {
                var segments: [StrengthWeightSegWire] = []
                for (segmentIdx, segment) in row.dropSegments.enumerated() {
                    guard let segmentReps = segment.reps, segmentReps > 0 else {
                        activeExerciseSetupError = "Set \(idx + 1), drop step \(segmentIdx + 1) has invalid reps."
                        return nil
                    }
                    let segmentWeightRaw = segment.weightKg
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .replacingOccurrences(of: ",", with: ".")
                    guard let segmentWeight = Double(segmentWeightRaw), segmentWeight >= 0 else {
                        activeExerciseSetupError = "Set \(idx + 1), drop step \(segmentIdx + 1) has invalid weight."
                        return nil
                    }
                    segments.append(StrengthWeightSegWire(reps: segmentReps, weight_kg: segmentWeight))
                }
                weightSegments = segments
            } else {
                weightSegments = nil
            }

            parsed.append(
                ActiveExerciseSetupParsedSet(
                    reps: weightSegments?.first?.reps ?? reps,
                    weightKg: weightSegments?.first.map { Decimal($0.weight_kg) } ?? weight,
                    rpe: rpe,
                    restSec: rest,
                    weightSegments: weightSegments
                )
            )
        }
        activeExerciseSetupError = nil
        return parsed
    }

    private func workoutId(for lane: StrengthLaneKind) -> Int? {
        switch lane {
        case .host: return workoutId
        case .guest: return dualGuestWorkoutId
        case .guest2: return dualGuest2WorkoutId
        }
    }

    private func nextExerciseOrderIndex(for lane: StrengthLaneKind) -> Int {
        (orderedExercises(lane: lane).map(\.order_index).max() ?? 0) + 1
    }

    @MainActor
    private func saveConfiguredActiveExercise() async {
        guard !isPersistingActiveExerciseEdit else { return }
        guard !activeExerciseSetupDrafts.isEmpty else { return }
        guard let targetWorkoutId = workoutId(for: activeExerciseSetupLane) else {
            activeExerciseSetupError = "This workout lane is not available."
            return
        }

        let lane = activeExerciseSetupLane
        let baseOrderIndex = nextExerciseOrderIndex(for: lane)
        let supersetGroupId = activeExerciseSetupDrafts.count > 1 ? UUID() : nil
        var parsedDrafts: [(draft: ActiveExerciseSetupExercise, sets: [ActiveExerciseSetupParsedSet])] = []
        for draft in activeExerciseSetupDrafts {
            guard let parsed = parseActiveExerciseSetupRows(draft.sets), !parsed.isEmpty else { return }
            parsedDrafts.append((draft: draft, sets: parsed))
        }

        isPersistingActiveExerciseEdit = true
        defer { isPersistingActiveExerciseEdit = false }
        let client = SupabaseManager.shared.client

        do {
            var localRows: [(row: ExerciseRow, sets: [SetRow])] = []
            for (draftIndex, parsedDraft) in parsedDrafts.enumerated() {
                let orderIndex = baseOrderIndex + draftIndex
                let insertedData = try await client
                    .from("workout_exercises")
                    .insert(
                        ActiveWorkoutExerciseInsert(
                            workout_id: targetWorkoutId,
                            exercise_id: Int(parsedDraft.draft.exercise.id),
                            order_index: orderIndex,
                            superset_group_id: supersetGroupId,
                            superset_position: supersetGroupId == nil ? nil : draftIndex + 1,
                            notes: nil,
                            custom_name: nil
                        )
                    )
                    .select("id")
                    .single()
                    .execute()
                    .data
                let inserted = try JSONDecoder.supabase().decode(ActiveWorkoutExerciseInsertedId.self, from: insertedData)

                let setRows = parsedDraft.sets.enumerated().map { idx, set in
                    ActiveWorkoutSetInsert(
                        workout_exercise_id: inserted.id,
                        set_number: 1,
                        order_index: idx + 1,
                        reps: set.reps,
                        weight_kg: set.weightKg.map { NSDecimalNumber(decimal: $0).doubleValue },
                        rpe: set.rpe.map { NSDecimalNumber(decimal: $0).doubleValue },
                        rest_sec: set.restSec,
                        weight_segments: set.weightSegments
                    )
                }

                _ = try await client
                    .from("exercise_sets")
                    .insert(setRows)
                    .execute()

                let exerciseName = parsedDraft.draft.exercise.localizedName(for: exerciseLanguageFromGlobalStorage())
                let row = ExerciseRow(
                    id: inserted.id,
                    exercise_id: parsedDraft.draft.exercise.id,
                    order_index: orderIndex,
                    superset_group_id: supersetGroupId,
                    superset_position: supersetGroupId == nil ? nil : draftIndex + 1,
                    notes: nil,
                    custom_name: nil,
                    target_sets: nil,
                    exercise_name: exerciseName
                )
                let localSets = parsedDraft.sets.enumerated().map { idx, set in
                    SetRow(
                        id: -(inserted.id * 1000 + idx + 1),
                        workout_exercise_id: inserted.id,
                        set_number: 1,
                        order_index: idx + 1,
                        reps: set.reps,
                        weight_kg: set.weightKg,
                        rpe: set.rpe,
                        rest_sec: set.restSec,
                        weight_segments: set.weightSegments,
                        configId: -(inserted.id * 1000 + idx + 1),
                        segmentsInRow: set.segmentsInRow
                    )
                }
                localRows.append((row: row, sets: localSets))
            }

            withAnimation(.easeInOut(duration: 0.25)) {
                appendActiveExercises(localRows, lane: lane)
            }
            persistProgramCacheSnapshot()
            NotificationCenter.default.post(name: .workoutDidChange, object: targetWorkoutId)
            resetActiveExerciseSetup()
            showToast(supersetGroupId == nil ? "Added exercise" : "Added superserie")
        } catch {
            logActiveExerciseFailure(error, phase: "saveConfiguredActiveExercise")
            if isActiveExerciseConnectivityFailure(error) {
                showToast(activeExerciseConnectionUnstableMessage)
                activeExerciseSetupError = activeExerciseConnectionUnstableMessage
            } else {
                activeExerciseSetupError = error.localizedDescription
            }
        }
    }

    @MainActor
    private func appendActiveExercise(_ row: ExerciseRow, sets: [SetRow], lane: StrengthLaneKind) {
        appendActiveExercises([(row: row, sets: sets)], lane: lane)
    }

    @MainActor
    private func appendActiveExercises(_ rows: [(row: ExerciseRow, sets: [SetRow])], lane: StrengthLaneKind) {
        guard !rows.isEmpty else { return }
        persistStateForCurrentDualIndex()
        let focusId = rows.first?.row.id
        switch lane {
        case .host:
            for item in rows {
                exercises.append(item.row)
                setsByExercise[item.row.id] = item.sets
                currentSetIndexByExercise[item.row.id] = 0
                visitedSetIndexByExercise[item.row.id] = 0
            }
            if let focusId, let idx = orderedExercises.firstIndex(where: { $0.id == focusId }) {
                currentExerciseIndex = idx
                pagerDisplayIndexHost = pagerAnchorExerciseIndex(for: idx, lane: .host)
            }
        case .guest:
            for item in rows {
                gExercises.append(item.row)
                gSetsByExercise[item.row.id] = item.sets
                gCurrentSetIndexByExercise[item.row.id] = 0
                gVisitedSetIndexByExercise[item.row.id] = 0
            }
            if let focusId, let idx = orderedGuestExercises.firstIndex(where: { $0.id == focusId }) {
                guestCurrentExerciseIndex = idx
                pagerDisplayIndexGuest = pagerAnchorExerciseIndex(for: idx, lane: .guest)
            }
        case .guest2:
            for item in rows {
                g2Exercises.append(item.row)
                g2SetsByExercise[item.row.id] = item.sets
                g2CurrentSetIndexByExercise[item.row.id] = 0
                g2VisitedSetIndexByExercise[item.row.id] = 0
            }
            if let focusId, let idx = orderedGuest2Exercises.firstIndex(where: { $0.id == focusId }) {
                g2CurrentExerciseIndex = idx
                pagerDisplayIndexGuest2 = pagerAnchorExerciseIndex(for: idx, lane: .guest2)
            }
        }
        if isDualMode {
            dualFocusLane = lane
        }
        clampLaneExerciseIndex(lane)
        restoreStateForDualIndex()
        dragOffsetY = 0
    }

    private func requestDeleteActiveExercise(_ ex: ExerciseRow, lane: StrengthLaneKind) {
        guard canModifyActiveExercises else { return }
        deleteExerciseCandidate = ex
        deleteExerciseLane = lane
        showDeleteExerciseConfirm = true
    }

    @MainActor
    private func deleteActiveExercise(_ ex: ExerciseRow, lane: StrengthLaneKind) async {
        guard !isPersistingActiveExerciseEdit else { return }
        guard let targetWorkoutId = workoutId(for: lane) else { return }
        isPersistingActiveExerciseEdit = true
        defer { isPersistingActiveExerciseEdit = false }
        let client = SupabaseManager.shared.client

        do {
            _ = try await client
                .from("exercise_sets")
                .delete()
                .eq("workout_exercise_id", value: ex.id)
                .execute()

            _ = try await client
                .from("workout_exercises")
                .delete()
                .eq("id", value: ex.id)
                .execute()

            let orderPatches = removeActiveExerciseLocally(ex, lane: lane)
            for patch in orderPatches {
                _ = try await client
                    .from("workout_exercises")
                    .update(
                        ActiveWorkoutExerciseOrderPatch(
                            order_index: patch.orderIndex,
                            superset_group_id: patch.supersetGroupId,
                            superset_position: patch.supersetPosition
                        )
                    )
                    .eq("id", value: patch.id)
                    .execute()
            }

            persistProgramCacheSnapshot()
            NotificationCenter.default.post(name: .workoutDidChange, object: targetWorkoutId)
            deleteExerciseCandidate = nil
            showToast("Deleted exercise")
        } catch {
            logActiveExerciseFailure(error, phase: "deleteActiveExercise")
            if isActiveExerciseConnectivityFailure(error) {
                showToast(activeExerciseConnectionUnstableMessage)
            } else {
                showToast(error.localizedDescription)
            }
        }
    }

    private func removeActiveExerciseLocally(_ ex: ExerciseRow, lane: StrengthLaneKind) -> [(id: Int, orderIndex: Int, supersetGroupId: UUID?, supersetPosition: Int?)] {
        persistStateForCurrentDualIndex()
        let oldIndex = orderedExercises(lane: lane).firstIndex(where: { $0.id == ex.id }) ?? 0
        clearActiveExerciseState(ex.id, lane: lane)

        switch lane {
        case .host:
            exercises.removeAll { $0.id == ex.id }
            exercises = renumberExerciseRows(exercises)
            let n = orderedExercises.count
            currentExerciseIndex = n > 0 ? min(oldIndex, n - 1) : 0
            pagerDisplayIndexHost = pagerAnchorExerciseIndex(for: currentExerciseIndex, lane: .host)
        case .guest:
            gExercises.removeAll { $0.id == ex.id }
            gExercises = renumberExerciseRows(gExercises)
            let n = orderedGuestExercises.count
            guestCurrentExerciseIndex = n > 0 ? min(oldIndex, n - 1) : 0
            pagerDisplayIndexGuest = pagerAnchorExerciseIndex(for: guestCurrentExerciseIndex, lane: .guest)
        case .guest2:
            g2Exercises.removeAll { $0.id == ex.id }
            g2Exercises = renumberExerciseRows(g2Exercises)
            let n = orderedGuest2Exercises.count
            g2CurrentExerciseIndex = n > 0 ? min(oldIndex, n - 1) : 0
            pagerDisplayIndexGuest2 = pagerAnchorExerciseIndex(for: g2CurrentExerciseIndex, lane: .guest2)
        }

        if isDualMode {
            dualFocusLane = lane
        }
        clampLaneExerciseIndex(lane)
        restoreStateForDualIndex()
        dragOffsetY = 0
        return orderedExercises(lane: lane).enumerated().map { idx, row in
            (id: row.id, orderIndex: idx + 1, supersetGroupId: row.superset_group_id, supersetPosition: row.superset_position)
        }
    }

    private func clearActiveExerciseState(_ exerciseId: Int, lane: StrengthLaneKind) {
        switch lane {
        case .host:
            setsByExercise.removeValue(forKey: exerciseId)
            performedSetsByExercise.removeValue(forKey: exerciseId)
            currentSetIndexByExercise.removeValue(forKey: exerciseId)
            visitedSetIndexByExercise.removeValue(forKey: exerciseId)
            isRestingByExercise.removeValue(forKey: exerciseId)
            remainingRestByExercise.removeValue(forKey: exerciseId)
            restEndDateByExercise.removeValue(forKey: exerciseId)
            restTotalPlannedByExercise.removeValue(forKey: exerciseId)
            if currentExercise?.id == exerciseId {
                currentSetIndex = 0
                isResting = false
                remainingRest = 0
                restEndDate = nil
                didFireRestFinishedFeedback = false
            }
            if navEmphasisLockExerciseIdHost == exerciseId {
                navEmphasisLockExerciseIdHost = nil
            }
        case .guest:
            gSetsByExercise.removeValue(forKey: exerciseId)
            gPerformedSetsByExercise.removeValue(forKey: exerciseId)
            gCurrentSetIndexByExercise.removeValue(forKey: exerciseId)
            gVisitedSetIndexByExercise.removeValue(forKey: exerciseId)
            gIsRestingByExercise.removeValue(forKey: exerciseId)
            gRemainingRestByExercise.removeValue(forKey: exerciseId)
            gRestEndDateByExercise.removeValue(forKey: exerciseId)
            gRestTotalPlannedByExercise.removeValue(forKey: exerciseId)
            if currentGuestExercise?.id == exerciseId {
                gCurrentSetIndex = 0
                gIsResting = false
                gRemainingRest = 0
                gRestEndDate = nil
                gDidFireRestFinishedFeedback = false
            }
            if navEmphasisLockExerciseIdGuest == exerciseId {
                navEmphasisLockExerciseIdGuest = nil
            }
        case .guest2:
            g2SetsByExercise.removeValue(forKey: exerciseId)
            g2PerformedSetsByExercise.removeValue(forKey: exerciseId)
            g2CurrentSetIndexByExercise.removeValue(forKey: exerciseId)
            g2VisitedSetIndexByExercise.removeValue(forKey: exerciseId)
            g2IsRestingByExercise.removeValue(forKey: exerciseId)
            g2RemainingRestByExercise.removeValue(forKey: exerciseId)
            g2RestEndDateByExercise.removeValue(forKey: exerciseId)
            g2RestTotalPlannedByExercise.removeValue(forKey: exerciseId)
            if currentGuest2Exercise?.id == exerciseId {
                g2CurrentSetIndex = 0
                g2IsResting = false
                g2RemainingRest = 0
                g2RestEndDate = nil
                g2DidFireRestFinishedFeedback = false
            }
            if navEmphasisLockExerciseIdGuest2 == exerciseId {
                navEmphasisLockExerciseIdGuest2 = nil
            }
        }
    }

    private func renumberExerciseRows(_ rows: [ExerciseRow]) -> [ExerciseRow] {
        let sorted = rows.sorted { $0.order_index < $1.order_index }
        let groupCounts = Dictionary(grouping: sorted.compactMap(\.superset_group_id), by: { $0 }).mapValues(\.count)
        var groupPositions: [UUID: Int] = [:]
        return sorted.enumerated().map { idx, row in
            let groupId: UUID?
            let groupPosition: Int?
            if let existingGroupId = row.superset_group_id, (groupCounts[existingGroupId] ?? 0) > 1 {
                let nextPosition = (groupPositions[existingGroupId] ?? 0) + 1
                groupPositions[existingGroupId] = nextPosition
                groupId = existingGroupId
                groupPosition = nextPosition
            } else {
                groupId = nil
                groupPosition = nil
            }
            return ExerciseRow(
                id: row.id,
                exercise_id: row.exercise_id,
                order_index: idx + 1,
                superset_group_id: groupId,
                superset_position: groupPosition,
                notes: row.notes,
                custom_name: row.custom_name,
                target_sets: row.target_sets,
                exercise_name: row.exercise_name
            )
        }
    }

    private func clampLaneExerciseIndex(_ lane: StrengthLaneKind) {
        switch lane {
        case .host:
            let n = orderedExercises.count
            guard n > 0 else {
                currentExerciseIndex = 0
                pagerDisplayIndexHost = 0
                return
            }
            currentExerciseIndex = min(max(0, currentExerciseIndex), n - 1)
            pagerDisplayIndexHost = min(max(0, pagerDisplayIndexHost), n - 1)
        case .guest:
            let n = orderedGuestExercises.count
            guard n > 0 else {
                guestCurrentExerciseIndex = 0
                pagerDisplayIndexGuest = 0
                return
            }
            guestCurrentExerciseIndex = min(max(0, guestCurrentExerciseIndex), n - 1)
            pagerDisplayIndexGuest = min(max(0, pagerDisplayIndexGuest), n - 1)
        case .guest2:
            let n = orderedGuest2Exercises.count
            guard n > 0 else {
                g2CurrentExerciseIndex = 0
                pagerDisplayIndexGuest2 = 0
                return
            }
            g2CurrentExerciseIndex = min(max(0, g2CurrentExerciseIndex), n - 1)
            pagerDisplayIndexGuest2 = min(max(0, pagerDisplayIndexGuest2), n - 1)
        }
    }

    private func jumpToExercise(lane: StrengthLaneKind, index: Int) {
        clampLaneExerciseIndex(lane)
        let ordered = orderedExercises(lane: lane)
        guard ordered.indices.contains(index) else { return }
        guard canJumpBetweenExercises else { return }

        let currentIdx: Int = {
            switch lane {
            case .host: return currentExerciseIndex
            case .guest: return guestCurrentExerciseIndex
            case .guest2: return g2CurrentExerciseIndex
            }
        }()
        let indexChanged = index != currentIdx
        let laneFocusChanged = isDualMode && (dualFocusLane != lane)

        if !indexChanged && !laneFocusChanged { return }

        persistStateForCurrentDualIndex()

        if isDualMode {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
                dualFocusLane = lane
            }
        }

        if indexChanged {
            let pagerAnchor = pagerAnchorExerciseIndex(for: index, lane: lane)
            switch lane {
            case .host:
                currentExerciseIndex = index
                pagerDisplayIndexHost = pagerAnchor
            case .guest:
                guestCurrentExerciseIndex = index
                pagerDisplayIndexGuest = pagerAnchor
            case .guest2:
                g2CurrentExerciseIndex = index
                pagerDisplayIndexGuest2 = pagerAnchor
            }
        }

        restoreStateForDualIndex()
        dragOffsetY = 0
    }

    @ViewBuilder
    private func navStripBubblesRow(lane: StrengthLaneKind) -> some View {
        let list = orderedExercises(lane: lane)
        HStack(alignment: .top, spacing: 8) {
            ForEach(navStripBlocks(for: list)) { block in
                if block.isSuperset {
                    let restOverlay = navRestOverlay(lane: lane, indices: block.exerciseIndices, list: list)
                    HStack(alignment: .top, spacing: 8) {
                        ForEach(block.exerciseIndices, id: \.self) { idx in
                            exerciseNavColumnView(lane: lane, index: idx, showsRestOverlay: false)
                                .id(navStripRowId(lane: lane, index: idx))
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.accentColor.opacity(0.35), lineWidth: 1)
                    )
                    .overlay {
                        if let restOverlay {
                            supersetRestCountdownOverlay(restOverlay)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                } else if let idx = block.exerciseIndices.first {
                    exerciseNavColumnView(lane: lane, index: idx)
                        .id(navStripRowId(lane: lane, index: idx))
                }
            }
            activeAddExerciseButton(lane: lane, compact: true)
        }
    }

    private func navStripBlocks(for list: [ExerciseRow]) -> [NavStripBlock] {
        var blocks: [NavStripBlock] = []
        var idx = 0

        while idx < list.count {
            let ex = list[idx]
            guard let groupId = ex.superset_group_id else {
                blocks.append(NavStripBlock(id: "exercise-\(ex.id)", exerciseIndices: [idx]))
                idx += 1
                continue
            }

            var indices = [idx]
            var nextIdx = idx + 1
            while nextIdx < list.count, list[nextIdx].superset_group_id == groupId {
                indices.append(nextIdx)
                nextIdx += 1
            }

            if indices.count > 1 {
                blocks.append(NavStripBlock(id: "superset-\(groupId.uuidString)-\(idx)", exerciseIndices: indices))
            } else {
                blocks.append(NavStripBlock(id: "exercise-\(ex.id)", exerciseIndices: [idx]))
            }

            idx = nextIdx
        }

        return blocks
    }

    private func navRestOverlay(lane: StrengthLaneKind, indices: [Int], list: [ExerciseRow]) -> NavRestOverlay? {
        let overlays = indices.compactMap { idx -> NavRestOverlay? in
            guard list.indices.contains(idx) else { return nil }
            return navRestOverlay(lane: lane, exerciseId: list[idx].id)
        }
        return overlays.max { lhs, rhs in
            lhs.seconds < rhs.seconds
        }
    }

    private func navRestOverlay(lane: StrengthLaneKind, exerciseId: Int) -> NavRestOverlay? {
        let end: Date?
        let plannedTotal: Int?
        switch lane {
        case .host:
            end = restEndDateByExercise[exerciseId]
            plannedTotal = restTotalPlannedByExercise[exerciseId]
        case .guest:
            end = gRestEndDateByExercise[exerciseId]
            plannedTotal = gRestTotalPlannedByExercise[exerciseId]
        case .guest2:
            end = g2RestEndDateByExercise[exerciseId]
            plannedTotal = g2RestTotalPlannedByExercise[exerciseId]
        }
        guard let end else { return nil }
        let seconds = max(0, Int(ceil(end.timeIntervalSinceNow)))
        guard seconds > 0 else { return nil }
        return NavRestOverlay(seconds: seconds, plannedTotalSeconds: max(max(plannedTotal ?? seconds, seconds), 1))
    }

    private func supersetRestCountdownOverlay(_ overlay: NavRestOverlay) -> some View {
        let total = max(overlay.plannedTotalSeconds, overlay.seconds, 1)
        let elapsedFrac = CGFloat(Double(total - overlay.seconds) / Double(total))
        let restFrac = CGFloat(Double(overlay.seconds) / Double(total))
        return ZStack {
            RestDarkRectangleClockWedge(elapsedFraction: elapsedFrac, restFraction: restFrac)
                .fill(Color.black.opacity(0.56))
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Text("\(overlay.seconds)s")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.45), radius: 2, x: 0, y: 1)
                .zIndex(1)
        }
        .allowsHitTesting(false)
        .accessibilityLabel("Superserie rest, \(overlay.seconds) seconds remaining")
    }

    @ViewBuilder
    private func exerciseNavigationStrip(lane: StrengthLaneKind) -> some View {
        let list = orderedExercises(lane: lane)
        let currentIdx: Int = {
            switch lane {
            case .host: return currentExerciseIndex
            case .guest: return guestCurrentExerciseIndex
            case .guest2: return g2CurrentExerciseIndex
            }
        }()
        ScrollViewReader { proxy in
            GeometryReader { g in
                let availableWidth = g.size.width
                let minRowWidth = max(0, availableWidth - 16)
                let n = list.count + 1
                let bubbleBarWidth = CGFloat(n) * 34 + CGFloat(max(0, n - 1)) * 8
                let useCenteringSpacers = bubbleBarWidth < minRowWidth
                ZStack(alignment: .center) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        Group {
                            if useCenteringSpacers {
                                HStack(alignment: .top, spacing: 0) {
                                    Spacer(minLength: 0)
                                    navStripBubblesRow(lane: lane)
                                    Spacer(minLength: 0)
                                }
                                .frame(minWidth: minRowWidth)
                            } else {
                                navStripBubblesRow(lane: lane)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .onScrollGeometryChange(
                        for: NavStripScrollEdgeFades.self,
                        of: { geo in
                            let x = geo.contentOffset.x
                            let cw = geo.contentSize.width
                            let v = geo.containerSize.width
                            if cw <= v + 0.5 {
                                return NavStripScrollEdgeFades(showLeading: false, showTrailing: false)
                            }
                            let maxOff = max(0, cw - v)
                            return NavStripScrollEdgeFades(
                                showLeading: x > 2,
                                showTrailing: x < maxOff - 2
                            )
                        },
                        action: { _, new in
                            navStripScrollEdgeFades = new
                        }
                    )
                    HStack(alignment: .center, spacing: 0) {
                        if navStripScrollEdgeFades.showLeading {
                            LinearGradient(
                                stops: [
                                    .init(color: .black.opacity(0.2), location: 0),
                                    .init(color: .black.opacity(0.05), location: 0.55),
                                    .init(color: .black.opacity(0), location: 1)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            .frame(width: 28, height: 50)
                        }
                        Spacer(minLength: 0)
                        if navStripScrollEdgeFades.showTrailing {
                            LinearGradient(
                                stops: [
                                    .init(color: .black.opacity(0), location: 0),
                                    .init(color: .black.opacity(0.05), location: 0.45),
                                    .init(color: .black.opacity(0.2), location: 1)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            .frame(width: 28, height: 50)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 56, maxHeight: 56, alignment: .center)
                    .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 56, maxHeight: 56, alignment: .center)
            .onAppear {
                scrollExerciseStrip(proxy: proxy, lane: lane, to: currentIdx, animated: false)
            }
            .onChange(of: currentExerciseIndex) { _, new in
                if lane == .host {
                    scrollExerciseStrip(proxy: proxy, lane: lane, to: new, animated: true)
                }
            }
            .onChange(of: guestCurrentExerciseIndex) { _, new in
                if lane == .guest {
                    scrollExerciseStrip(proxy: proxy, lane: lane, to: new, animated: true)
                }
            }
            .onChange(of: g2CurrentExerciseIndex) { _, new in
                if lane == .guest2 {
                    scrollExerciseStrip(proxy: proxy, lane: lane, to: new, animated: true)
                }
            }
            .onChange(of: allExercisesCompleted(for: lane)) { was, now in
                if now, !was {
                    startStrengthNavStripWaveIfNeeded(lane: lane)
                } else if !now {
                    cancelStrengthNavStripWave()
                }
            }
            .onDisappear(perform: cancelStrengthNavStripWave)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 2)
    }

    private func navStripRowId(lane: StrengthLaneKind, index: Int) -> String {
        let prefix: String = {
            switch lane {
            case .host: return "h"
            case .guest: return "g"
            case .guest2: return "g2"
            }
        }()
        return "\(prefix)-\(index)"
    }

    @ViewBuilder
    private func exerciseNavigationStripWithHint(availableWidth: CGFloat) -> some View {
        VStack(spacing: 6) {
            if isDualMode {
                exerciseNavigationStrip(lane: mainDisplayLane)
                    .id(mainDisplayLane)
                    .frame(maxWidth: .infinity, maxHeight: 56, alignment: .center)
            } else {
                exerciseNavigationStrip(lane: .host)
                    .frame(maxWidth: .infinity, maxHeight: 56, alignment: .center)
            }
            if !activeStrengthNavHintSeen {
                activeStrengthNavFirstHintBanner()
            }
        }
        .frame(maxWidth: availableWidth)
    }

    private var strengthSessionActiveElapsedSeconds: Int {
        _ = strengthWorkoutElapsedTick
        guard let start = strengthWorkoutSessionStart else { return 0 }
        let gross = max(0, Int(floor(Date().timeIntervalSince(start))))
        let openPause = sessionPauseBegan.map { max(0, Int(floor(Date().timeIntervalSince($0)))) } ?? 0
        return max(0, gross - accumulatedPausedSeconds - openPause)
    }

    private var strengthWorkoutElapsedDisplayString: String {
        let elapsed = strengthSessionActiveElapsedSeconds
        let h = elapsed / 3600
        let m = (elapsed % 3600) / 60
        let s = elapsed % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }

    @ViewBuilder
    private func strengthWorkoutSessionElapsedChip() -> some View {
        HStack(spacing: 5) {
            Image(systemName: "stopwatch")
                .font(.caption.weight(.semibold))
                .accessibilityHidden(true)
            Text(strengthWorkoutElapsedDisplayString)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.18), lineWidth: 0.5))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Workout time, \(strengthWorkoutElapsedDisplayString)")
    }

    private func shiftAllRestEndDatesForward(by delta: TimeInterval) {
        guard delta > 0 else { return }
        if let e = restEndDate { restEndDate = e.addingTimeInterval(delta) }
        for id in restEndDateByExercise.keys {
            if let e = restEndDateByExercise[id] {
                restEndDateByExercise[id] = e.addingTimeInterval(delta)
            }
        }
        if let e = gRestEndDate { gRestEndDate = e.addingTimeInterval(delta) }
        for id in gRestEndDateByExercise.keys {
            if let e = gRestEndDateByExercise[id] {
                gRestEndDateByExercise[id] = e.addingTimeInterval(delta)
            }
        }
        if let e = g2RestEndDate { g2RestEndDate = e.addingTimeInterval(delta) }
        for id in g2RestEndDateByExercise.keys {
            if let e = g2RestEndDateByExercise[id] {
                g2RestEndDateByExercise[id] = e.addingTimeInterval(delta)
            }
        }
    }

    private func toggleSessionPause() {
        if isSessionPaused {
            guard let began = sessionPauseBegan else {
                isSessionPaused = false
                return
            }
            let dt = Date().timeIntervalSince(began)
            if dt > 0 {
                shiftAllRestEndDatesForward(by: dt)
                accumulatedPausedSeconds = min(Int.max / 4, accumulatedPausedSeconds + Int(floor(dt)))
            }
            sessionPauseBegan = nil
            isSessionPaused = false
            WorkoutLiveActivityManager.updateStrengthPauseIfAvailable(
                isPaused: false,
                activeElapsedSeconds: strengthSessionActiveElapsedSeconds
            )
        } else {
            sessionPauseBegan = Date()
            isSessionPaused = true
            WorkoutLiveActivityManager.updateStrengthPauseIfAvailable(
                isPaused: true,
                activeElapsedSeconds: strengthSessionActiveElapsedSeconds
            )
        }
    }

    private func activeStrengthNavFirstHintBanner() -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("Swipe up or down on the card, or tap a bubble, to change exercise.")
                .font(.caption)
                .multilineTextAlignment(.leading)
                .foregroundStyle(.primary)
            Button {
                activeStrengthNavHintSeen = true
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.body)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss hint")
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.16), lineWidth: 0.5))
        .padding(.horizontal, 6)
    }

    @ViewBuilder
    private func exerciseNavColumnView(lane: StrengthLaneKind, index idx: Int, showsRestOverlay: Bool = true) -> some View {
        let list = orderedExercises(lane: lane)
        let ex = list[idx]
        let completed = isExerciseCompleted(ex, lane: lane)
        let isLast = idx == list.count - 1
        let workAnchorExerciseId: Int? = {
            switch lane {
            case .host: return currentExercise?.id
            case .guest: return currentGuestExercise?.id
            case .guest2: return currentGuest2Exercise?.id
            }
        }()
        let emphasisTargetId = navEmphasisTargetExerciseId(lane: lane)
        let isEmphasized = (emphasisTargetId == ex.id)
        let isWorkAnchor = (workAnchorExerciseId == ex.id)
        let jumpOK = canJumpBetweenExercises
        let title = exerciseTitle(ex)
        let plannedSets = setsFor(ex, lane: lane).count
        let completionProgress = exerciseCompletionProgress(ex, lane: lane)
        let popId = navStripRowId(lane: lane, index: idx)
        let popBinding = Binding<Bool>(
            get: { navExercisePopoverIndex == popId },
            set: { newVal in
                if newVal {
                    navExercisePopoverIndex = popId
                } else if navExercisePopoverIndex == popId {
                    navExercisePopoverIndex = nil
                }
            }
        )
        let restOverlay = showsRestOverlay ? navRestOverlay(lane: lane, exerciseId: ex.id) : nil
        StrengthExerciseNavColumn(
            displayNumber: idx + 1,
            exerciseTitle: title,
            plannedSetCount: plannedSets,
            completed: completed,
            completionProgress: completionProgress,
            isLast: isLast,
            isEmphasized: isEmphasized,
            isWorkAnchor: isWorkAnchor,
            allWorkoutExercisesComplete: allExercisesCompleted(for: lane),
            isWavePulsing: strengthNavStripWaveIndex == idx,
            jumpOK: jumpOK,
            workAnchorExerciseId: workAnchorExerciseId,
            restOverlaySeconds: restOverlay?.seconds,
            restPlannedTotalSeconds: restOverlay?.plannedTotalSeconds,
            enlargeActiveBubbleForSolo: !isDualMode,
            popoverPresented: popBinding,
            onShortTap: { jumpToExercise(lane: lane, index: idx) },
            onLongPress: { navExercisePopoverIndex = popId }
        )
    }

    private func scrollExerciseStrip(proxy: ScrollViewProxy, lane: StrengthLaneKind, to index: Int, animated: Bool) {
        let list = orderedExercises(lane: lane)
        guard list.indices.contains(index) else { return }
        let id = navStripRowId(lane: lane, index: index)
        if animated {
            withAnimation(.easeInOut(duration: 0.28)) {
                proxy.scrollTo(id, anchor: .center)
            }
        } else {
            proxy.scrollTo(id, anchor: .center)
        }
    }

    private func persistStateForCurrentDualIndex() {
        if let ex = currentExercise {
            currentSetIndexByExercise[ex.id] = currentSetIndex
            isRestingByExercise[ex.id] = isResting
            remainingRestByExercise[ex.id] = remainingRest
            restEndDateByExercise[ex.id] = restEndDate
        }
        if isDualMode, let gx = currentGuestExercise {
            gCurrentSetIndexByExercise[gx.id] = gCurrentSetIndex
            gIsRestingByExercise[gx.id] = gIsResting
            gRemainingRestByExercise[gx.id] = gRemainingRest
            gRestEndDateByExercise[gx.id] = gRestEndDate
        }
        if isTripleMode, let gx2 = currentGuest2Exercise {
            g2CurrentSetIndexByExercise[gx2.id] = g2CurrentSetIndex
            g2IsRestingByExercise[gx2.id] = g2IsResting
            g2RemainingRestByExercise[gx2.id] = g2RemainingRest
            g2RestEndDateByExercise[gx2.id] = g2RestEndDate
        }
    }

    private func restoreStateForDualIndex() {
        if let ex = currentExercise {
            currentSetIndex = currentSetIndexByExercise[ex.id] ?? 0
            isResting = isRestingByExercise[ex.id] ?? false
            restEndDate = restEndDateByExercise[ex.id]

            if isResting, let end = restEndDate {
                remainingRest = max(0, Int(ceil(end.timeIntervalSinceNow)))
            } else {
                remainingRest = remainingRestByExercise[ex.id] ?? 0
            }

            if remainingRest <= 0 {
                isResting = false
                remainingRest = 0
                restEndDate = nil
                restEndDateByExercise[ex.id] = nil
                restTotalPlannedByExercise[ex.id] = nil
            } else if isResting, restTotalPlannedByExercise[ex.id] == nil {
                restTotalPlannedByExercise[ex.id] = max(1, remainingRest)
            }
        } else {
            currentSetIndex = 0
            isResting = false
            remainingRest = 0
            restEndDate = nil
        }

        if isDualMode, let gx = currentGuestExercise {
            gCurrentSetIndex = gCurrentSetIndexByExercise[gx.id] ?? 0
            gIsResting = gIsRestingByExercise[gx.id] ?? false
            gRestEndDate = gRestEndDateByExercise[gx.id]

            if gIsResting, let end = gRestEndDate {
                gRemainingRest = max(0, Int(ceil(end.timeIntervalSinceNow)))
            } else {
                gRemainingRest = gRemainingRestByExercise[gx.id] ?? 0
            }

            if gRemainingRest <= 0 {
                gIsResting = false
                gRemainingRest = 0
                gRestEndDate = nil
                gRestEndDateByExercise[gx.id] = nil
                gRestTotalPlannedByExercise[gx.id] = nil
            } else if gIsResting, gRestTotalPlannedByExercise[gx.id] == nil {
                gRestTotalPlannedByExercise[gx.id] = max(1, gRemainingRest)
            }
        } else if isDualMode {
            gCurrentSetIndex = 0
            gIsResting = false
            gRemainingRest = 0
            gRestEndDate = nil
        }

        if isTripleMode, let gx2 = currentGuest2Exercise {
            g2CurrentSetIndex = g2CurrentSetIndexByExercise[gx2.id] ?? 0
            g2IsResting = g2IsRestingByExercise[gx2.id] ?? false
            g2RestEndDate = g2RestEndDateByExercise[gx2.id]

            if g2IsResting, let end = g2RestEndDate {
                g2RemainingRest = max(0, Int(ceil(end.timeIntervalSinceNow)))
            } else {
                g2RemainingRest = g2RemainingRestByExercise[gx2.id] ?? 0
            }

            if g2RemainingRest <= 0 {
                g2IsResting = false
                g2RemainingRest = 0
                g2RestEndDate = nil
                g2RestEndDateByExercise[gx2.id] = nil
                g2RestTotalPlannedByExercise[gx2.id] = nil
            } else if g2IsResting, g2RestTotalPlannedByExercise[gx2.id] == nil {
                g2RestTotalPlannedByExercise[gx2.id] = max(1, g2RemainingRest)
            }
        } else if isTripleMode {
            g2CurrentSetIndex = 0
            g2IsResting = false
            g2RemainingRest = 0
            g2RestEndDate = nil
        }
    }

    @ViewBuilder
    private func dualPartnerHeader() -> some View {
        HStack(alignment: .center, spacing: 10) {
            Button {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
                    clampLaneExerciseIndex(.host)
                    dualFocusLane = .host
                }
            } label: {
                dualAvatarCell(
                    lane: .host,
                    url: dualHostAvatarURL,
                    isFocused: mainDisplayLane == .host,
                    restPlannedTotal: currentExercise.flatMap { restTotalPlannedByExercise[$0.id] }
                )
            }
            .buttonStyle(.plain)

            Image(systemName: "link")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 2)

            Button {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
                    clampLaneExerciseIndex(.guest)
                    dualFocusLane = .guest
                }
            } label: {
                dualAvatarCell(
                    lane: .guest,
                    url: dualGuestAvatarURL,
                    isFocused: mainDisplayLane == .guest,
                    restPlannedTotal: currentGuestExercise.flatMap { gRestTotalPlannedByExercise[$0.id] }
                )
            }
            .buttonStyle(.plain)

            if isTripleMode {
                Image(systemName: "link")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 2)

                Button {
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
                        clampLaneExerciseIndex(.guest2)
                        dualFocusLane = .guest2
                    }
                } label: {
                    dualAvatarCell(
                        lane: .guest2,
                        url: dualGuest2AvatarURL,
                        isFocused: mainDisplayLane == .guest2,
                        restPlannedTotal: currentGuest2Exercise.flatMap { g2RestTotalPlannedByExercise[$0.id] }
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(.ultraThinMaterial, in: Capsule())
        .id("\(dualHostAvatarURL ?? "")|\(dualGuestAvatarURL ?? "")|\(dualGuest2AvatarURL ?? "")")
        .task(id: dualHostAvatarURL) { await prefetchAvatarImageIfNeeded(dualHostAvatarURL) }
        .task(id: dualGuestAvatarURL) { await prefetchAvatarImageIfNeeded(dualGuestAvatarURL) }
        .task(id: dualGuest2AvatarURL) { await prefetchAvatarImageIfNeeded(dualGuest2AvatarURL) }
    }

    private func prefetchAvatarImageIfNeeded(_ urlString: String?) async {
        guard let urlString, let url = URL(string: urlString) else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        _ = try? await URLSession.shared.data(for: req)
    }

    @ViewBuilder
    private func dualAvatarCell(lane: StrengthLaneKind, url: String?, isFocused: Bool, restPlannedTotal: Int?) -> some View {
        let resting: Bool = {
            switch lane {
            case .host: return isResting
            case .guest: return gIsResting
            case .guest2: return g2IsResting
            }
        }()
        let secs: Int = {
            switch lane {
            case .host: return remainingRest
            case .guest: return gRemainingRest
            case .guest2: return g2RemainingRest
            }
        }()
        DualLaneAvatarCell(
            urlString: url,
            isFocused: isFocused,
            resting: resting,
            restSeconds: secs,
            restPlannedTotal: restPlannedTotal
        )
    }

    private func exerciseTitle(_ ex: ExerciseRow?) -> String {
        guard let ex else { return "" }
        if let custom = ex.custom_name, !custom.isEmpty { return custom }
        return ex.exercise_name ?? "Exercise"
    }
    
    @ViewBuilder
    private func exercisePager() -> some View {
        GeometryReader { outerGeo in
            let H = outerGeo.size.height
            let W = outerGeo.size.width
            let navOverlayBlock: CGFloat = {
                guard shouldShowExerciseNavStrip else { return 0 }
                let dualAvatarBar: CGFloat = isDualMode ? 92 : 0
                let stripApprox: CGFloat = isDualMode ? 52 : 44
                let hintApprox: CGFloat = activeStrengthNavHintSeen ? 0 : 64
                return dualAvatarBar + stripApprox + hintApprox
            }()
            let minGapBelowNav: CGFloat = 4
            let minClusterTop = navOverlayBlock + minGapBelowNav

            let peekHeight: CGFloat = 78
            let peekGap: CGFloat = 12
            let usableForCluster = H - minClusterTop
            let isSupersetPager = pagerCurrentDisplayGroup?.isSuperset == true
            let clusterFill: CGFloat = isSupersetPager ? 0.72 : 0.66
            let minCardHeight: CGFloat = isSupersetPager ? 264 : 220
            let cardHeightBase = max(usableForCluster * clusterFill, minCardHeight)
            let cardHeightIfLoose = isSupersetPager
                ? min(cardHeightBase * 1.2, usableForCluster - 2 * (peekHeight + peekGap))
                : cardHeightBase
            let neededIfLoose = cardHeightIfLoose + 2 * (peekHeight + peekGap)
            let cardHeight: CGFloat = neededIfLoose > usableForCluster
                ? max(usableForCluster - 2 * (peekHeight + peekGap), isSupersetPager ? 240 : 200)
                : cardHeightIfLoose
            let needed = cardHeight + 2 * (peekHeight + peekGap)

            let step = cardHeight * 0.86
            let localThreshold = max(70, step * 0.35)
            let peekOffset = (cardHeight / 2) + (peekHeight / 2) + peekGap

            let idealClusterTop = H * 0.5 - needed * 0.5
            let clusterTop = max(minClusterTop, idealClusterTop)
            let clusterBottomPad = max(0, H - clusterTop - needed)

            ZStack(alignment: .top) {
                VStack(spacing: 0) {
                    Color.clear.frame(height: clusterTop)
                    exercisePagerCardStack(
                        peekHeight: peekHeight,
                        peekGap: peekGap,
                        cardHeight: cardHeight,
                        peekOffset: peekOffset,
                        step: step,
                        localThreshold: localThreshold,
                        neededHeight: needed
                    )
                    Color.clear.frame(height: clusterBottomPad)
                }

                if isDualMode && !showCountdown {
                    dualPartnerHeader()
                        .padding(.top, 6)
                        .padding(.horizontal, 10)
                        .zIndex(20)
                }

                if shouldShowExerciseNavStrip {
                    exerciseNavigationStripWithHint(availableWidth: W)
                        .padding(.top, (isDualMode && !showCountdown) ? 92 : 0)
                        .zIndex(19)
                }
            }
        }
    }

    @ViewBuilder
    private func exercisePagerCardStack(
        peekHeight: CGFloat,
        peekGap: CGFloat,
        cardHeight: CGFloat,
        peekOffset: CGFloat,
        step: CGFloat,
        localThreshold: CGFloat,
        neededHeight: CGFloat
    ) -> some View {
        ZStack {
            if let prev = pagerPreviousExercise {
                exercisePeekCard(prev, edge: .bottom)
                    .frame(height: peekHeight)
                    .offset(y: -peekOffset + dragOffsetY * 0.25)
                    .opacity(0.55)
                    .blur(radius: 6)
                    .scaleEffect(0.96)
                    .allowsHitTesting(false)
            }

            if let group = pagerCurrentDisplayGroup, group.isSuperset {
                supersetExerciseContent(group, isActive: true, lane: mainDisplayLane)
                    .frame(height: cardHeight)
                    .offset(y: dragOffsetY)
                    .allowsHitTesting(true)
            } else if let cur = pagerCurrentExercise {
                exerciseContent(cur, isActive: true, lane: mainDisplayLane)
                    .frame(height: cardHeight)
                    .offset(y: dragOffsetY)
                    .allowsHitTesting(true)
            } else if isDualMode {
                dualPagerMissingExerciseFallback(cardHeight: cardHeight)
                    .offset(y: dragOffsetY)
                    .allowsHitTesting(false)
            }

            if let next = pagerNextExercise {
                exercisePeekCard(next, edge: .top)
                    .frame(height: peekHeight)
                    .offset(y: peekOffset + dragOffsetY * 0.25)
                    .opacity(0.55)
                    .blur(radius: 6)
                    .scaleEffect(0.96)
                    .allowsHitTesting(false)
            }
        }
        .frame(height: neededHeight)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture()
                .onChanged { value in
                    guard canSwipeBetweenExercises() else { return }
                    let raw = value.translation.height
                    dragOffsetY = max(-step, min(step, raw))
                }
                .onEnded { value in
                    guard canSwipeBetweenExercises() else {
                        dragOffsetY = 0
                        return
                    }

                    let t = value.translation.height

                    if t <= -localThreshold {
                        if canGoNextExercise() {
                            isTransitioningExercise = true
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
                                dragOffsetY = -step
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) {
                                pagerShiftForward()
                                dragOffsetY = 0
                                isTransitioningExercise = false
                            }
                        } else {
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
                                dragOffsetY = 0
                            }
                        }
                    } else if t >= localThreshold {
                        if canGoPreviousExercise() {
                            isTransitioningExercise = true
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
                                dragOffsetY = step
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) {
                                pagerShiftBackward()
                                dragOffsetY = 0
                                isTransitioningExercise = false
                            }
                        } else {
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
                                dragOffsetY = 0
                            }
                        }
                    } else {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
                            dragOffsetY = 0
                        }
                    }
                }
        )
    }
    
    private func programItemsForRoutineOverwrite(
        exList: [ExerciseRow],
        setsMap: [Int: [SetRow]],
        performedMap: [Int: [PerformedSet]]
    ) -> [StrengthProgramItem]? {
        var items: [StrengthProgramItem] = []
        for ex in exList.sorted(by: { $0.order_index < $1.order_index }) {
            let templateSets = orderedSetRows(setsMap[ex.id] ?? [])
            let sets: [StrengthProgramSet]
            if !templateSets.isEmpty {
                sets = templateSets.map { s in
                    let segs: [StrengthWeightSegment]? = {
                        guard let wss = s.weight_segments, wss.count >= 2 else { return nil }
                        return wss.map { StrengthWeightSegment(reps: $0.reps, weightKg: $0.weight_kg) }
                    }()
                    return StrengthProgramSet(
                        setNumber: s.set_number,
                        reps: s.reps,
                        weightKg: s.weight_kg.map { NSDecimalNumber(decimal: $0).doubleValue },
                        rpe: s.rpe.map { NSDecimalNumber(decimal: $0).doubleValue },
                        restSec: s.rest_sec,
                        notes: nil,
                        weightSegments: segs
                    )
                }
            } else {
                let performed = performedMap[ex.id] ?? []
                guard !performed.isEmpty else { return nil }
                sets = performed.enumerated().map { idx, p in
                    let segsFromPerformed: [StrengthWeightSegment]? = {
                        guard let wss = p.weight_segments, wss.count >= 2 else { return nil }
                        return wss.map { StrengthWeightSegment(reps: $0.reps, weightKg: $0.weight_kg) }
                    }()
                    return StrengthProgramSet(
                        setNumber: idx + 1,
                        reps: p.reps,
                        weightKg: p.weight_kg.map { NSDecimalNumber(decimal: $0).doubleValue },
                        rpe: p.rpe.map { NSDecimalNumber(decimal: $0).doubleValue },
                        restSec: p.rest_sec,
                        notes: nil,
                        weightSegments: segsFromPerformed
                    )
                }
            }
            items.append(
                StrengthProgramItem(
                    exerciseId: ex.exercise_id,
                    orderIndex: ex.order_index,
                    notes: ex.notes,
                    customName: ex.custom_name,
                    sets: sets
                )
            )
        }
        return items.isEmpty ? nil : items
    }

    private func orderedSetRows(_ rows: [SetRow]) -> [SetRow] {
        rows.sorted { a, b in
            let ao = a.order_index ?? Int.max
            let bo = b.order_index ?? Int.max
            if ao != bo { return ao < bo }
            return a.id < b.id
        }
    }

    private func editableExercisesForRoutineUpdateFromHost(
        exList: [ExerciseRow],
        setsMap: [Int: [SetRow]],
        performedMap: [Int: [PerformedSet]]
    ) -> [EditableExercise] {
        exList.sorted(by: { $0.order_index < $1.order_index }).map { ex in
            let templateSets = orderedSetRows(setsMap[ex.id] ?? [])
            var ee = EditableExercise()
            ee.exerciseId = ex.exercise_id
            ee.exerciseName = ex.custom_name ?? ""
            ee.orderIndex = ex.order_index
            ee.supersetGroupId = ex.superset_group_id
            ee.supersetPosition = ex.superset_position
            ee.notes = ex.notes ?? ""
            if !templateSets.isEmpty {
                ee.sets = templateSets.enumerated().map { idx, s in
                    let segDraft = (s.weight_segments ?? []).asEditorSegmentsIfDropSet()
                    return EditableSet(
                        setNumber: s.set_number,
                        orderIndex: s.order_index ?? idx + 1,
                        reps: s.reps,
                        weightKg: activeDecimalToWeightField(s.weight_kg),
                        rpe: activeDecimalToRpeField(s.rpe),
                        restSec: s.rest_sec,
                        notes: "",
                        segments: segDraft
                    )
                }
            } else {
                let performed = performedMap[ex.id] ?? []
                ee.sets = performed.enumerated().map { i, p in
                    let segDraft = (p.weight_segments ?? []).asEditorSegmentsIfDropSet()
                    return EditableSet(
                        setNumber: i + 1,
                        orderIndex: i + 1,
                        reps: p.reps,
                        weightKg: activeDecimalToWeightField(p.weight_kg),
                        rpe: activeDecimalToRpeField(p.rpe),
                        restSec: p.rest_sec,
                        notes: "",
                        segments: segDraft
                    )
                }
            }
            return ee
        }
    }

    private func activeDecimalToWeightField(_ d: Decimal?) -> String {
        guard let d else { return "" }
        return String(format: "%.1f", NSDecimalNumber(decimal: d).doubleValue)
    }

    private func activeDecimalToRpeField(_ d: Decimal?) -> String {
        guard let d else { return "" }
        let v = NSDecimalNumber(decimal: d).doubleValue
        if v == floor(v) { return String(Int(v)) }
        return String(format: "%.1f", v)
    }

    private func commitDeferredStrengthFinish(deferral: StrengthFinishDeferral, updateRoutine: Bool) async {
        let extra: (Int64, [EditableExercise])? = updateRoutine
            ? (deferral.prompt.routineId, deferral.editableForRoutine)
            : nil
        let (wallEndedAt, pausedSec) = await MainActor.run { () -> (Date, Int) in
            let openPause = sessionPauseBegan.map { max(0, Int(floor(Date().timeIntervalSince($0)))) } ?? 0
            let total = max(0, accumulatedPausedSeconds + openPause)
            return (Date(), total)
        }
        await runStrengthWorkoutPersistence(
            exList: deferral.exList,
            performedMap: deferral.performedMap,
            guestExList: deferral.guestExList,
            guestPerformedMap: deferral.guestPerformedMap,
            guestWorkoutId: deferral.guestWorkoutId,
            guest2ExList: deferral.guest2ExList,
            guest2PerformedMap: deferral.guest2PerformedMap,
            guest2WorkoutId: deferral.guest2WorkoutId,
            routinePrescriptionOverwrite: extra,
            wallEndedAt: wallEndedAt,
            pausedSec: pausedSec
        )
    }

    private func runStrengthWorkoutPersistence(
        exList: [ExerciseRow],
        performedMap: [Int: [PerformedSet]],
        guestExList: [ExerciseRow],
        guestPerformedMap: [Int: [PerformedSet]],
        guestWorkoutId: Int?,
        guest2ExList: [ExerciseRow],
        guest2PerformedMap: [Int: [PerformedSet]],
        guest2WorkoutId: Int?,
        routinePrescriptionOverwrite: (routineId: Int64, exercises: [EditableExercise])?,
        wallEndedAt: Date,
        pausedSec: Int
    ) async {
        let client = SupabaseManager.shared.client
        await MainActor.run { self.isSaving = true }

        func collapseInputs(
            rows: [ExerciseRow],
            performedMap: [Int: [PerformedSet]]
        ) -> [StrengthWorkoutExerciseSaveInput] {
            let performedByExercise = Dictionary(uniqueKeysWithValues: rows.map { row in
                let lines = (performedMap[row.id] ?? []).map {
                    StrengthWorkoutFinishCollapse.Line(
                        configId: $0.configId,
                        segmentsInRow: $0.segmentsInRow,
                        reps: $0.reps,
                        weightKg: $0.weight_kg,
                        rpe: $0.rpe,
                        restSec: $0.rest_sec,
                        weightSegments: $0.weight_segments
                    )
                }
                return (row.id, lines)
            })
            return StrengthWorkoutFinishCollapse.buildExerciseSaveInputs(
                exerciseIds: rows.map(\.id),
                performedByExercise: performedByExercise
            )
        }

        let hostExercises = collapseInputs(rows: exList, performedMap: performedMap)
        var linked: [StrengthWorkoutFinishLinkedInput] = []
        if let gid = guestWorkoutId {
            linked.append(
                StrengthWorkoutFinishLinkedInput(
                    workout_id: gid,
                    exercises: collapseInputs(rows: guestExList, performedMap: guestPerformedMap)
                )
            )
        }
        if let g2id = guest2WorkoutId {
            linked.append(
                StrengthWorkoutFinishLinkedInput(
                    workout_id: g2id,
                    exercises: collapseInputs(rows: guest2ExList, performedMap: guest2PerformedMap)
                )
            )
        }

        let hostSetCount = hostExercises.reduce(0) { $0 + $1.sets.count }
        let linkedCount = linked.count
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let endedAtIso = iso.string(from: wallEndedAt)

        do {
            WorkoutSavePerf.begin(.activeFinish)
            WorkoutSavePerf.mark(
                .activeFinish,
                "payload_built",
                exerciseCount: hostExercises.count,
                setCount: hostSetCount,
                linkedWorkoutCount: linkedCount
            )
            let results = try await WorkoutSavePerf.measure(
                .activeFinish,
                "finish_strength_workout_v1",
                exerciseCount: hostExercises.count,
                setCount: hostSetCount,
                linkedWorkoutCount: linkedCount
            ) {
                try await StrengthWorkoutSaveRPC.finishStrengthWorkoutV1(
                    client: client,
                    workoutId: workoutId,
                    endedAt: endedAtIso,
                    pausedSec: pausedSec,
                    exercises: hostExercises,
                    linked: linked
                )
            }
            WorkoutSavePerf.end(.activeFinish)

            for result in results {
                NotificationCenter.default.post(name: .workoutDidChange, object: result.workout_id)
            }

            if let o = routinePrescriptionOverwrite, let uid = await MainActor.run(body: { app.userId }) {
                try? await applyStrengthRoutinePrescriptionUpdate(
                    client: client,
                    userId: uid,
                    routineId: o.routineId,
                    exercises: o.exercises
                )
            }

            let celebrate = await shouldShowElborblaCelebration(using: client)

            await MainActor.run {
                self.isSaving = false
                if celebrate {
                    withAnimation(.easeOut(duration: 0.25)) {
                        self.showElborblaCelebration = true
                    }
                } else {
                    dismiss()
                }
            }
        } catch {
            await MainActor.run { self.isSaving = false }
            if WorkoutStartSync.isRetriable(error) {
                WorkoutFinishSync.enqueue(
                    workoutId: workoutId,
                    endedAtIso: endedAtIso,
                    pausedSec: pausedSec,
                    exercises: hostExercises,
                    linked: linked
                )
                await MainActor.run {
                    completeFinishLocallyAfterOfflineEnqueue()
                }
            } else {
                await MainActor.run {
                    showToast(error.localizedDescription)
                }
            }
        }
    }

    @MainActor
    private func completeFinishLocallyAfterOfflineEnqueue() {
        for wid in [workoutId, dualGuestWorkoutId, dualGuest2WorkoutId].compactMap({ $0 }) {
            NotificationCenter.default.post(name: .workoutDidChange, object: wid)
        }
        showToast(String(localized: "Workout saved on device — will sync when online"))
        dismiss()
    }

    private func saveAndFinishWorkout() async {
        var exList: [ExerciseRow] = []
        var performedMap: [Int: [PerformedSet]] = [:]
        var hostSetsMap: [Int: [SetRow]] = [:]
        var guestExList: [ExerciseRow] = []
        var guestPerformedMap: [Int: [PerformedSet]] = [:]
        var guestWorkoutId: Int?
        var guest2ExList: [ExerciseRow] = []
        var guest2PerformedMap: [Int: [PerformedSet]] = [:]
        var guest2WorkoutId: Int?

        await MainActor.run {
            exList = self.orderedExercises
            performedMap = self.performedSetsByExercise
            hostSetsMap = self.setsByExercise
            guestWorkoutId = self.dualGuestWorkoutId
            guest2WorkoutId = self.dualGuest2WorkoutId
            if guestWorkoutId != nil {
                guestExList = self.orderedGuestExercises
                guestPerformedMap = self.gPerformedSetsByExercise
            }
            if guest2WorkoutId != nil {
                guest2ExList = self.orderedGuest2Exercises
                guest2PerformedMap = self.g2PerformedSetsByExercise
            }
        }

        let client = SupabaseManager.shared.client

        if let proposed = programItemsForRoutineOverwrite(exList: exList, setsMap: hostSetsMap, performedMap: performedMap),
           let session = try? await client.auth.session {
            let candidate = (
                try? await fetchStrengthRoutineOverwriteCandidate(
                    client: client,
                    userId: session.user.id,
                    proposed: proposed,
                    exerciseDisplayName: { eid in
                        exList.first(where: { $0.exercise_id == eid })?.exercise_name ?? ""
                    }
                )
            ) ?? .none
            if case .prompt(let pr) = candidate {
                let editable = editableExercisesForRoutineUpdateFromHost(exList: exList, setsMap: hostSetsMap, performedMap: performedMap)
                await MainActor.run {
                    self.isSaving = false
                    self.strengthFinishDeferral = StrengthFinishDeferral(
                        exList: exList,
                        performedMap: performedMap,
                        guestExList: guestExList,
                        guestPerformedMap: guestPerformedMap,
                        guestWorkoutId: guestWorkoutId,
                        guest2ExList: guest2ExList,
                        guest2PerformedMap: guest2PerformedMap,
                        guest2WorkoutId: guest2WorkoutId,
                        prompt: pr,
                        editableForRoutine: editable
                    )
                }
                return
            }
        }

        let (wallEndedAt, pausedSec) = await MainActor.run { () -> (Date, Int) in
            let openPause = sessionPauseBegan.map { max(0, Int(floor(Date().timeIntervalSince($0)))) } ?? 0
            let total = max(0, accumulatedPausedSeconds + openPause)
            return (Date(), total)
        }
        await runStrengthWorkoutPersistence(
            exList: exList,
            performedMap: performedMap,
            guestExList: guestExList,
            guestPerformedMap: guestPerformedMap,
            guestWorkoutId: guestWorkoutId,
            guest2ExList: guest2ExList,
            guest2PerformedMap: guest2PerformedMap,
            guest2WorkoutId: guest2WorkoutId,
            routinePrescriptionOverwrite: nil,
            wallEndedAt: wallEndedAt,
            pausedSec: pausedSec
        )
    }

    private func shouldShowElborblaCelebration(using client: SupabaseClient) async -> Bool {
        guard let uid = await MainActor.run(body: { app.userId }) else { return false }
        struct Row: Decodable { let username: String }
        do {
            let res = try await client
                .from("profiles")
                .select("username")
                .eq("user_id", value: uid.uuidString)
                .limit(1)
                .execute()
            let rows = try JSONDecoder.supabase().decode([Row].self, from: res.data)
            guard let raw = rows.first?.username else { return false }
            let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return normalized == Self.elborblaUsernameNormalized
        } catch {
            return false
        }
    }

    private static func loadElborblaCelebrationImage() -> UIImage? {
        let bundle = Bundle.main
        let exts = ["GIF", "gif", "jpg", "jpeg", "png", "heic"]
        for ext in exts {
            if let url = bundle.url(forResource: elborblaCelebrationBasename, withExtension: ext),
               let data = try? Data(contentsOf: url) {
                return ElborblaCelebrationDecoder.uiImage(from: data, treatingGIF: ext.lowercased() == "gif")
            }
        }
        for ext in exts {
            let urls = bundle.urls(forResourcesWithExtension: ext, subdirectory: nil) ?? []
            for url in urls {
                let base = url.deletingPathExtension().lastPathComponent
                guard base.caseInsensitiveCompare(elborblaCelebrationBasename) == .orderedSame else { continue }
                if let data = try? Data(contentsOf: url) {
                    return ElborblaCelebrationDecoder.uiImage(from: data, treatingGIF: ext.lowercased() == "gif")
                }
            }
        }
        return nil
    }

    private func sanitizeEndDateIfNeededOnClose() async {
        let saving = await MainActor.run { isSaving }
        if saving { return }

        let (guestId, guest2Id) = await MainActor.run { (dualGuestWorkoutId, dualGuest2WorkoutId) }

        do {
            struct WorkoutDates: Decodable {
                let started_at: Date?
                let ended_at: Date?
            }

            func sanitizeIfInverted(workoutIdToCheck: Int) async throws {
                let res = try await SupabaseManager.shared.client
                    .from("workouts")
                    .select("started_at, ended_at")
                    .eq("id", value: workoutIdToCheck)
                    .limit(1)
                    .execute()

                let arr = try JSONDecoder.supabase().decode([WorkoutDates].self, from: res.data)
                guard let w = arr.first else { return }
                guard let start = w.started_at else { return }

                if let end = w.ended_at, end < start {
                    _ = try await SupabaseManager.shared.client
                        .from("workouts")
                        .update(WorkoutSanitizePatch(ended_at: nil))
                        .eq("id", value: workoutIdToCheck)
                        .execute()

                    NotificationCenter.default.post(name: .workoutDidChange, object: workoutIdToCheck)
                }
            }

            try await sanitizeIfInverted(workoutIdToCheck: workoutId)
            if let gid = guestId {
                try await sanitizeIfInverted(workoutIdToCheck: gid)
            }
            if let g2 = guest2Id {
                try await sanitizeIfInverted(workoutIdToCheck: g2)
            }
        } catch {
        }
    }
    
    private func exerciseForEditSheet() -> ExerciseRow? {
        if let id = editTargetExerciseId {
            return orderedExercises(lane: editTargetLane).first { $0.id == id }
        }
        switch editTargetLane {
        case .host: return currentExercise
        case .guest: return currentGuestExercise
        case .guest2: return currentGuest2Exercise
        }
    }

    private func editSupersetMembersForSheet(lane: StrengthLaneKind) -> [ExerciseRow] {
        guard let ex = exerciseForEditSheet() else { return [] }
        let members = supersetMembers(for: ex, lane: lane)
        return members.count > 1 ? members : []
    }

    @ViewBuilder
    private func editSupersetMemberPicker(lane: StrengthLaneKind) -> some View {
        let members = editSupersetMembersForSheet(lane: lane)
        if members.count > 1 {
            let roundIndex = currentSetIndexForEditLane()
            VStack(alignment: .leading, spacing: 8) {
                Text("Exercise")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(members, id: \.id) { member in
                            let selected = editTargetExerciseId == member.id
                            Button {
                                switchEditSupersetMember(exerciseId: member.id, lane: lane, setIndex: roundIndex)
                            } label: {
                                Text(exerciseTitle(member))
                                    .font(.subheadline.weight(selected ? .semibold : .regular))
                                    .lineLimit(1)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(
                                        Capsule()
                                            .fill(selected ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.12))
                                    )
                                    .overlay(
                                        Capsule()
                                            .stroke(selected ? Color.accentColor : Color.clear, lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func clearEditDrafts() {
        editDraftsByExerciseId = [:]
    }

    private func currentEditDraftFromForm() -> EditSetDraft {
        EditSetDraft(
            repsText: editRepsText,
            weightText: editWeightText,
            restText: editRestText,
            rpeText: editRpeText,
            dropSegments: editDropSegments
        )
    }

    private func applyDraftToEditForm(_ draft: EditSetDraft) {
        editRepsText = draft.repsText
        editWeightText = draft.weightText
        editRestText = draft.restText
        editRpeText = draft.rpeText
        editDropSegments = draft.dropSegments
    }

    private func stashCurrentEditDraft() {
        guard let id = editTargetExerciseId ?? exerciseForEditSheet()?.id else { return }
        editDraftsByExerciseId[id] = currentEditDraftFromForm()
    }

    private func loadEditFieldsFromSet(_ ex: ExerciseRow, set: SetRow) {
        editRepsText = "\(set.reps ?? 0)"
        if let w = set.weight_kg {
            editWeightText = String(format: "%.1f", NSDecimalNumber(decimal: w).doubleValue)
        } else {
            editWeightText = ""
        }
        editRestText = "\(set.rest_sec ?? 0)"
        if let rpe = set.rpe {
            editRpeText = String(format: "%.1f", NSDecimalNumber(decimal: rpe).doubleValue)
        } else {
            editRpeText = ""
        }
        editDropSegments = set.weight_segments ?? []
    }

    private func isLastSupersetMemberForRestEdit(_ ex: ExerciseRow, lane: StrengthLaneKind, setIndex: Int) -> Bool {
        let members = supersetMembers(for: ex, lane: lane)
        guard members.count > 1 else { return true }
        let available = members.filter { setsFor($0, lane: lane).count > setIndex }
        guard let last = available.last else { return true }
        return last.id == ex.id
    }

    private func editShowsRestFieldInSheet() -> Bool {
        guard let ex = exerciseForEditSheet() else { return true }
        return isLastSupersetMemberForRestEdit(ex, lane: editTargetLane, setIndex: currentSetIndexForEditLane())
    }

    private func openEditSet(exerciseId: Int, lane: StrengthLaneKind, setIndex: Int) {
        guard let ex = orderedExercises(lane: lane).first(where: { $0.id == exerciseId }),
              let s = currentSetFor(ex, setIndex: setIndex, lane: lane)
        else { return }
        let openingFresh = !showEditSheet
        editTargetLane = lane
        editTargetExpandedIndex = setIndex
        editTargetExerciseId = exerciseId
        if openingFresh {
            clearEditDrafts()
            applyEditToRemainingSets = false
        }
        loadEditFieldsFromSet(ex, set: s)
        showEditSheet = true
    }

    private func switchEditSupersetMember(exerciseId: Int, lane: StrengthLaneKind, setIndex: Int) {
        stashCurrentEditDraft()
        editTargetExerciseId = exerciseId
        editTargetExpandedIndex = setIndex
        if let draft = editDraftsByExerciseId[exerciseId] {
            applyDraftToEditForm(draft)
            return
        }
        guard let ex = orderedExercises(lane: lane).first(where: { $0.id == exerciseId }),
              let s = currentSetFor(ex, setIndex: setIndex, lane: lane)
        else { return }
        loadEditFieldsFromSet(ex, set: s)
    }

    private func editRemainingSetRange() -> (start: Int, end: Int)? {
        guard let ex = exerciseForEditSheet() else { return nil }
        let startIndex = currentSetIndexForEditLane()
        let lastIndex = max(0, setsFor(ex, lane: editTargetLane).count - 1)
        guard startIndex < lastIndex else { return nil }
        return (start: startIndex + 1, end: lastIndex + 1)
    }

    private func shouldShowApplyToRemainingSetsToggle() -> Bool {
        editRemainingSetRange() != nil
    }

    private func applyAllStashedEditDrafts() {
        stashCurrentEditDraft()
        let startIndex = currentSetIndexForEditLane()
        let lane = editTargetLane
        for (exerciseId, draft) in editDraftsByExerciseId {
            guard let ex = orderedExercises(lane: lane).first(where: { $0.id == exerciseId }) else { continue }
            let lastIndex = max(0, setsFor(ex, lane: lane).count - 1)
            let targetIndices: [Int]
            if applyEditToRemainingSets && startIndex < lastIndex {
                targetIndices = Array(startIndex...lastIndex)
            } else {
                targetIndices = [startIndex]
            }
            for setIndex in targetIndices {
                let applyRest = isLastSupersetMemberForRestEdit(ex, lane: lane, setIndex: setIndex)
                applyEdits(draft: draft, to: ex, lane: lane, setIndex: setIndex, applyRest: applyRest)
            }
        }
    }

    private func applyEdits(
        draft: EditSetDraft,
        to ex: ExerciseRow,
        lane: StrengthLaneKind,
        setIndex: Int,
        applyRest: Bool
    ) {
        let trimmedReps = draft.repsText.trimmingCharacters(in: .whitespacesAndNewlines)
        let newReps = Int(trimmedReps)
        let trimmedWeight = draft.weightText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")

        let newWeightDecimal: Decimal?
        if trimmedWeight.isEmpty {
            newWeightDecimal = nil
        } else {
            newWeightDecimal = Decimal(string: trimmedWeight)
        }

        let trimmedRpe = draft.rpeText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")

        let newRpeDecimal: Decimal?
        if trimmedRpe.isEmpty {
            newRpeDecimal = nil
        } else {
            newRpeDecimal = Decimal(string: trimmedRpe)
        }

        let newRestSecRaw: Int?
        let newRestSec: Int?
        if applyRest {
            let trimmedRest = draft.restText.trimmingCharacters(in: .whitespacesAndNewlines)
            newRestSecRaw = Int(trimmedRest)
            newRestSec = (newRestSecRaw != nil) ? max(0, newRestSecRaw!) : nil
        } else {
            newRestSecRaw = nil
            newRestSec = nil
        }

        var configs = sortedStrengthConfigs(ex, lane: lane)
        guard !configs.isEmpty else { return }

        guard let (idx, offset) = configBlockForSetIndex(ex, setIndex: setIndex, lane: lane) else { return }
        let old = configs[idx]

        let targetId = nextSyntheticConfigId(in: configs)
        let target: SetRow
        if draft.dropSegments.count >= 2 {
            let restOut: Int? = applyRest ? (newRestSec ?? old.rest_sec) : old.rest_sec
            let rpeOut = newRpeDecimal ?? old.rpe
            target = SetRow(
                id: targetId,
                workout_exercise_id: old.workout_exercise_id,
                set_number: 1,
                reps: draft.dropSegments.first?.reps ?? old.reps,
                weight_kg: draft.dropSegments.first != nil ? Decimal(draft.dropSegments.first!.weight_kg) : old.weight_kg,
                rpe: rpeOut,
                rest_sec: restOut,
                weight_segments: draft.dropSegments,
                configId: targetId,
                segmentsInRow: draft.dropSegments.count
            )
        } else {
            target = SetRow(
                id: targetId,
                workout_exercise_id: old.workout_exercise_id,
                set_number: 1,
                reps: newReps ?? old.reps,
                weight_kg: newWeightDecimal ?? old.weight_kg,
                rpe: newRpeDecimal ?? old.rpe,
                rest_sec: applyRest ? (newRestSec ?? old.rest_sec) : old.rest_sec,
                weight_segments: nil,
                configId: targetId,
                segmentsInRow: 1
            )
        }

        let replacement = splitConfigBlock(old: old, offset: offset, target: target, baseConfigs: configs)
        configs.replaceSubrange(idx...idx, with: replacement)
        switch lane {
        case .host: setsByExercise[ex.id] = configs
        case .guest: gSetsByExercise[ex.id] = configs
        case .guest2: g2SetsByExercise[ex.id] = configs
        }
        if applyRest, newRestSecRaw != nil {
            applySupersetRestEdit(from: ex, lane: lane, setIndex: setIndex, restSec: newRestSec)
        }
    }

    @ViewBuilder
    private func editSetOutlinedButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text("Edit set")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .contentShape(Rectangle())
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.accentColor, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func currentSetIndexForEditLane() -> Int {
        if let override = editTargetExpandedIndex {
            return override
        }
        switch editTargetLane {
        case .host: return currentSetIndex
        case .guest: return gCurrentSetIndex
        case .guest2: return g2CurrentSetIndex
        }
    }

    private func configIndexForSetIndex(_ ex: ExerciseRow, setIndex: Int, lane: StrengthLaneKind = .host) -> Int? {
        configBlockForSetIndex(ex, setIndex: setIndex, lane: lane)?.configIndex
    }

    private func configBlockForSetIndex(_ ex: ExerciseRow, setIndex: Int, lane: StrengthLaneKind) -> (configIndex: Int, offsetInBlock: Int)? {
        let configs = sortedStrengthConfigs(ex, lane: lane)
        var cursor = 0
        for (i, c) in configs.enumerated() {
            let blockCount = max(0, c.set_number)
            let next = cursor + blockCount
            if setIndex >= cursor && setIndex < next {
                return (i, setIndex - cursor)
            }
            cursor = next
        }
        return nil
    }

    private func nextSyntheticConfigId(in configs: [SetRow], avoiding extra: Set<Int> = []) -> Int {
        var minExisting = configs.map { $0.id }.min() ?? 0
        for id in extra where id < minExisting { minExisting = id }
        return min(minExisting - 1, -1)
    }

    private func dropIndicatorLabel(for ex: ExerciseRow, setIndex: Int, lane: StrengthLaneKind) -> String? {
        let expanded = setsFor(ex, lane: lane)
        guard setIndex >= 0, setIndex < expanded.count else { return nil }
        guard (expanded[setIndex].weight_segments?.count ?? 0) >= 2 else { return nil }
        return "Drop set"
    }

    private func sortedStrengthConfigs(_ ex: ExerciseRow, lane: StrengthLaneKind) -> [SetRow] {
        switch lane {
        case .host: return setsByExercise[ex.id] ?? []
        case .guest: return gSetsByExercise[ex.id] ?? []
        case .guest2: return g2SetsByExercise[ex.id] ?? []
        }
    }

    private func convertCurrentConfigToDropSet() {
        guard let ex = exerciseForEditSheet() else { return }
        let activeSetIndex = currentSetIndexForEditLane()
        var configs = sortedStrengthConfigs(ex, lane: editTargetLane)
        guard !configs.isEmpty else { return }

        guard let (idx, offset) = configBlockForSetIndex(ex, setIndex: activeSetIndex, lane: editTargetLane) else { return }
        let old = configs[idx]
        if (old.weight_segments?.count ?? 0) >= 2 { return }

        let reps0 = old.reps ?? Int(editRepsText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 10
        let weight0: Double = {
            if let w = old.weight_kg { return NSDecimalNumber(decimal: w).doubleValue }
            let t = editWeightText.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
            return Double(t) ?? 0
        }()
        let ws = [
            StrengthWeightSegWire(reps: reps0, weight_kg: weight0),
            StrengthWeightSegWire(reps: reps0, weight_kg: 0)
        ]

        let targetId = nextSyntheticConfigId(in: configs)
        let target = SetRow(
            id: targetId,
            workout_exercise_id: old.workout_exercise_id,
            set_number: 1,
            reps: ws[0].reps,
            weight_kg: Decimal(ws[0].weight_kg),
            rpe: old.rpe,
            rest_sec: old.rest_sec,
            weight_segments: ws,
            configId: targetId,
            segmentsInRow: 2
        )

        let replacement = splitConfigBlock(old: old, offset: offset, target: target, baseConfigs: configs)
        configs.replaceSubrange(idx...idx, with: replacement)
        switch editTargetLane {
        case .host: setsByExercise[ex.id] = configs
        case .guest: gSetsByExercise[ex.id] = configs
        case .guest2: g2SetsByExercise[ex.id] = configs
        }
        editDropSegments = ws
    }

    private func splitConfigBlock(old: SetRow, offset: Int, target: SetRow, baseConfigs: [SetRow]) -> [SetRow] {
        let blockCount = max(0, old.set_number)
        let beforeCount = max(0, offset)
        let afterCount = max(0, blockCount - offset - 1)
        var result: [SetRow] = []
        if beforeCount > 0 {
            result.append(SetRow(
                id: old.id,
                workout_exercise_id: old.workout_exercise_id,
                set_number: beforeCount,
                reps: old.reps,
                weight_kg: old.weight_kg,
                rpe: old.rpe,
                rest_sec: old.rest_sec,
                weight_segments: old.weight_segments,
                configId: old.id,
                segmentsInRow: old.segmentsInRow
            ))
        }
        result.append(target)
        if afterCount > 0 {
            let avoid: Set<Int> = beforeCount > 0 ? [old.id, target.id] : [target.id]
            let afterId = nextSyntheticConfigId(in: baseConfigs, avoiding: avoid)
            result.append(SetRow(
                id: afterId,
                workout_exercise_id: old.workout_exercise_id,
                set_number: afterCount,
                reps: old.reps,
                weight_kg: old.weight_kg,
                rpe: old.rpe,
                rest_sec: old.rest_sec,
                weight_segments: old.weight_segments,
                configId: afterId,
                segmentsInRow: old.segmentsInRow
            ))
        }
        return result
    }

    private func applyConvertCurrentConfigToNormal() {
        guard let ex = exerciseForEditSheet() else { return }
        let activeSetIndex = currentSetIndexForEditLane()

        var configs = sortedStrengthConfigs(ex, lane: editTargetLane)
        guard !configs.isEmpty else { return }

        guard let (idx, offset) = configBlockForSetIndex(ex, setIndex: activeSetIndex, lane: editTargetLane) else { return }
        let old = configs[idx]

        let reps = Int(convertToNormalRepsText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? (old.reps ?? 10)
        let weightRaw = convertToNormalWeightText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        let weight = Decimal(string: weightRaw) ?? old.weight_kg ?? 0

        let targetId = nextSyntheticConfigId(in: configs)
        let target = SetRow(
            id: targetId,
            workout_exercise_id: old.workout_exercise_id,
            set_number: 1,
            reps: reps,
            weight_kg: weight,
            rpe: old.rpe,
            rest_sec: old.rest_sec,
            weight_segments: nil,
            configId: targetId,
            segmentsInRow: 1
        )

        let replacement = splitConfigBlock(old: old, offset: offset, target: target, baseConfigs: configs)
        configs.replaceSubrange(idx...idx, with: replacement)
        switch editTargetLane {
        case .host: setsByExercise[ex.id] = configs
        case .guest: gSetsByExercise[ex.id] = configs
        case .guest2: g2SetsByExercise[ex.id] = configs
        }
        editDropSegments = []
        editRepsText = "\(reps)"
        if let d = Decimal(string: weightRaw) {
            editWeightText = String(format: "%.1f", NSDecimalNumber(decimal: d).doubleValue)
        } else {
            editWeightText = ""
        }
    }
            
    private func applyEditsToCurrentExercise() {
        stashCurrentEditDraft()
        applyAllStashedEditDrafts()
    }

    private func applySupersetRestEdit(from ex: ExerciseRow, lane: StrengthLaneKind, setIndex: Int, restSec: Int?) {
        let members = supersetMembers(for: ex, lane: lane)
        guard members.count > 1 else { return }

        for member in members where member.id != ex.id {
            var configs = sortedStrengthConfigs(member, lane: lane)
            guard !configs.isEmpty,
                  let (idx, offset) = configBlockForSetIndex(member, setIndex: setIndex, lane: lane)
            else { continue }

            let old = configs[idx]
            let targetId = nextSyntheticConfigId(in: configs)
            let target = SetRow(
                id: targetId,
                workout_exercise_id: old.workout_exercise_id,
                set_number: 1,
                reps: old.reps,
                weight_kg: old.weight_kg,
                rpe: old.rpe,
                rest_sec: restSec,
                weight_segments: old.weight_segments,
                configId: targetId,
                segmentsInRow: old.segmentsInRow
            )
            let replacement = splitConfigBlock(old: old, offset: offset, target: target, baseConfigs: configs)
            configs.replaceSubrange(idx...idx, with: replacement)
            switch lane {
            case .host: setsByExercise[member.id] = configs
            case .guest: gSetsByExercise[member.id] = configs
            case .guest2: g2SetsByExercise[member.id] = configs
            }
        }
    }
    
    private func fetchStrengthWorkoutData(forWid wid: Int) async throws -> ([ExerciseRow], [Int: [SetRow]]) {
        let exQ = try await SupabaseManager.shared.client
            .from("workout_exercises")
            .select("id, exercise_id, order_index, superset_group_id, superset_position, notes, custom_name, exercises(name)")
            .eq("workout_id", value: wid)
            .order("order_index", ascending: true)
            .execute()

        struct ExWire: Decodable {
            let id: Int
            let exercise_id: Int64
            let order_index: Int
            let superset_group_id: UUID?
            let superset_position: Int?
            let notes: String?
            let custom_name: String?
            let target_sets: Int?
            let exercises: ExName?
            struct ExName: Decodable { let name: String? }
        }
        let exWire = try JSONDecoder.supabase().decode([ExWire].self, from: exQ.data)
        let exRows: [ExerciseRow] = exWire.map {
            .init(
                id: $0.id,
                exercise_id: $0.exercise_id,
                order_index: $0.order_index,
                superset_group_id: $0.superset_group_id,
                superset_position: $0.superset_position,
                notes: $0.notes,
                custom_name: $0.custom_name,
                target_sets: $0.target_sets,
                exercise_name: $0.exercises?.name
            )
        }

        let ids = exRows.map { $0.id }
        var byEx: [Int: [SetRow]] = [:]

        if !ids.isEmpty {
            let setData: Data
            do {
                setData = try await SupabaseManager.shared.client
                    .from("exercise_sets")
                    .select("*")
                    .in("workout_exercise_id", values: ids)
                    .order("order_index", ascending: true)
                    .order("id", ascending: true)
                    .execute()
                    .data
            } catch {
                setData = try await SupabaseManager.shared.client
                    .from("exercise_sets")
                    .select("*")
                    .in("workout_exercise_id", values: ids)
                    .order("set_number", ascending: true)
                    .order("id", ascending: true)
                    .execute()
                    .data
            }
            let sets = try JSONDecoder.supabase().decode([SetRow].self, from: setData)
            for s in sets {
                byEx[s.workout_exercise_id, default: []].append(s)
            }
        }

        return (exRows, byEx)
    }

    private func fetchDualLinkedStrengthWorkoutData(forWid gid: Int) async throws -> ([ExerciseRow], [Int: [SetRow]]) {
        let res = try await SupabaseManager.shared.client
            .rpc("fetch_dual_linked_strength_workout_data", params: FetchDualLinkedStrengthParams(p_workout_id: Int64(gid)))
            .execute()

        let bundle = try JSONDecoder.supabase().decode(DualLinkedStrengthBundle.self, from: res.data)
        let exRows: [ExerciseRow] = bundle.exercises.map {
            ExerciseRow(
                id: $0.id,
                exercise_id: $0.exercise_id,
                order_index: $0.order_index,
                superset_group_id: $0.superset_group_id,
                superset_position: $0.superset_position,
                notes: $0.notes,
                custom_name: $0.custom_name,
                target_sets: $0.target_sets,
                exercise_name: $0.exercises?.name
            )
        }
        var byEx: [Int: [SetRow]] = [:]
        for s in bundle.sets {
            byEx[s.workout_exercise_id, default: []].append(s)
        }
        return (exRows, byEx)
    }

    private var startSyncBannerVisible: Bool {
        switch startSyncStatus {
        case .pending, .syncing, .willRetry:
            return true
        default:
            return false
        }
    }

    private var startSyncBannerText: String {
        switch startSyncStatus {
        case .pending, .syncing:
            return String(localized: "Syncing start…")
        case .willRetry:
            return String(localized: "Start saved locally — will sync when online")
        default:
            return ""
        }
    }

    @MainActor
    private func hydrateFromProgramCache() -> Bool {
        guard let entry = WorkoutProgramCache.entry(for: workoutId), !entry.exercises.isEmpty else {
            return false
        }
        exercises = entry.exercises.map {
            ExerciseRow(
                id: $0.id,
                exercise_id: $0.exercise_id,
                order_index: $0.order_index,
                superset_group_id: $0.superset_group_id,
                superset_position: $0.superset_position,
                notes: $0.notes,
                custom_name: $0.custom_name,
                target_sets: nil,
                exercise_name: $0.exercise_name
            )
        }
        setsByExercise = entry.setsByExerciseId.mapValues { rows in
            rows.map { s in
                SetRow(
                    id: s.id,
                    workout_exercise_id: s.workout_exercise_id,
                    set_number: s.set_number,
                    order_index: s.order_index,
                    reps: s.reps,
                    weight_kg: s.weight_kg,
                    rpe: s.rpe,
                    rest_sec: s.rest_sec,
                    weight_segments: nil,
                    configId: s.id,
                    segmentsInRow: 1
                )
            }
        }
        error = nil
        return true
    }

    private func load() async {
        let hydratedFromCache = await MainActor.run { hydrateFromProgramCache() }
        if hydratedFromCache {
            await MainActor.run { loading = false }
        } else {
            await MainActor.run { loading = true }
        }
        defer {
            Task { @MainActor in loading = false }
        }

        #if DEBUG
        dualStrengthDebug("load() start guestWid=\(dualGuestWorkoutId.map(String.init) ?? "nil")")
        #endif

        do {
            let (hostEx, hostSets) = try await fetchStrengthWorkoutData(forWid: workoutId)
            var guestEx: [ExerciseRow] = []
            var guestSets: [Int: [SetRow]] = [:]
            var guestErr: String?
            if let gid = dualGuestWorkoutId {
                do {
                    (guestEx, guestSets) = try await fetchDualLinkedStrengthWorkoutData(forWid: gid)
                } catch {
                    guestErr = error.localizedDescription
                }
            }

            var guest2Ex: [ExerciseRow] = []
            var guest2Sets: [Int: [SetRow]] = [:]
            var guest2Err: String?
            if let g2id = dualGuest2WorkoutId {
                do {
                    (guest2Ex, guest2Sets) = try await fetchDualLinkedStrengthWorkoutData(forWid: g2id)
                } catch {
                    guest2Err = error.localizedDescription
                }
            }

            await MainActor.run {
                self.exercises = hostEx
                self.setsByExercise = hostSets
                self.gExercises = guestEx
                self.gSetsByExercise = guestSets
                self.guestDataError = guestErr
                self.g2Exercises = guest2Ex
                self.g2SetsByExercise = guest2Sets
                self.guest2DataError = guest2Err

                self.currentExerciseIndex = 0
                self.pagerDisplayIndexHost = 0
                self.pagerDisplayIndexGuest = 0
                self.pagerDisplayIndexGuest2 = 0
                self.guestCurrentExerciseIndex = 0
                self.g2CurrentExerciseIndex = 0
                self.currentSetIndex = 0
                self.gCurrentSetIndex = 0
                self.g2CurrentSetIndex = 0

                self.navEmphasisLockExerciseIdHost = nil
                self.navEmphasisLockExerciseIdGuest = nil
                self.navEmphasisLockExerciseIdGuest2 = nil

                self.isResting = false
                self.remainingRest = 0
                self.gIsResting = false
                self.gRemainingRest = 0
                self.g2IsResting = false
                self.g2RemainingRest = 0

                self.clampLaneExerciseIndex(.host)
                self.clampLaneExerciseIndex(.guest)
                self.clampLaneExerciseIndex(.guest2)
                #if DEBUG
                dualStrengthDebug(
                    "load() done hostEx=\(hostEx.count) guestEx=\(guestEx.count) guest2Ex=\(guest2Ex.count) "
                        + "guestDataError=\(guestErr ?? "nil") guest2Err=\(guest2Err ?? "nil")"
                )
                #endif
            }
        } catch is CancellationError {
        } catch let urlError as URLError where urlError.code == .cancelled {
        } catch {
            await MainActor.run {
                if exercises.isEmpty {
                    self.error = error.localizedDescription
                }
            }
        }
    }
        
    private func weightStr(_ w: Decimal?) -> String {
        guard let w else { return "0.0 kg" }
        return String(format: "%.1f kg", NSDecimalNumber(decimal: w).doubleValue)
    }
    
    @MainActor
    private func showToast(_ msg: String) {
        toastMessage = msg
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            if toastMessage == msg {
                toastMessage = nil
            }
        }
    }

    private let activeExerciseConnectionUnstableMessage = "Connection unstable. Retrying offline..."

    @MainActor
    private func restoreActiveWorkoutStateOnForeground() {
        if workoutId(for: activeExerciseSetupLane) == nil {
            if showActiveExercisePicker || showActiveExerciseSetup {
                showActiveExercisePicker = false
                resetActiveExerciseSetup()
                showToast("This workout lane is not available.")
            }
        }
        if exercises.isEmpty && !loading {
            if hydrateFromProgramCache() {
                loading = false
            } else {
                Task { await load() }
            }
        }
    }

    @MainActor
    private func persistProgramCacheSnapshot() {
        guard !exercises.isEmpty else { return }
        let cachedExercises = exercises.map {
            WorkoutProgramCache.CachedExercise(
                id: $0.id,
                exercise_id: $0.exercise_id,
                order_index: $0.order_index,
                superset_group_id: $0.superset_group_id,
                superset_position: $0.superset_position,
                notes: $0.notes,
                custom_name: $0.custom_name,
                exercise_name: $0.exercise_name
            )
        }
        let cachedSets = setsByExercise.mapValues { rows in
            rows.map {
                WorkoutProgramCache.CachedSet(
                    id: $0.id,
                    workout_exercise_id: $0.workout_exercise_id,
                    set_number: $0.set_number,
                    order_index: $0.order_index,
                    reps: $0.reps,
                    weight_kg: $0.weight_kg,
                    rpe: $0.rpe,
                    rest_sec: $0.rest_sec,
                    notes: nil
                )
            }
        }
        WorkoutProgramCache.store(
            workoutId: workoutId,
            exercises: cachedExercises,
            setsByExerciseId: cachedSets
        )
    }

    private func activeWorkoutNetworkStatusLabel() -> String {
        let monitor = NWPathMonitor()
        let sem = DispatchSemaphore(value: 0)
        var label = "unknown"
        monitor.pathUpdateHandler = { path in
            label = "\(path.status)"
            if path.usesInterfaceType(.wifi) { label += ",wifi" }
            if path.usesInterfaceType(.cellular) { label += ",cellular" }
            sem.signal()
        }
        monitor.start(queue: DispatchQueue(label: "liftr.active-strength.net-snapshot"))
        _ = sem.wait(timeout: .now() + 0.3)
        monitor.cancel()
        return label
    }

    private func logActiveExerciseFailure(_ error: Error, phase: String) {
        print("[ActiveStrength][\(phase)] \(error.localizedDescription) network=\(activeWorkoutNetworkStatusLabel())")
    }

    private func isActiveExerciseConnectivityFailure(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .timedOut,
                 .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed,
                 .dataNotAllowed, .internationalRoamingOff:
                return true
            default:
                break
            }
        }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            let codes: [Int] = [
                NSURLErrorNotConnectedToInternet,
                NSURLErrorNetworkConnectionLost,
                NSURLErrorTimedOut,
                NSURLErrorCannotFindHost,
                NSURLErrorCannotConnectToHost,
                NSURLErrorDNSLookupFailed,
                NSURLErrorDataNotAllowed,
                NSURLErrorInternationalRoamingOff
            ]
            if codes.contains(ns.code) { return true }
        }
        let msg = error.localizedDescription.lowercased()
        if msg.contains("network") || msg.contains("connection") || msg.contains("offline") || msg.contains("timeout") {
            return true
        }
        return false
    }
}

private struct RestDarkClockWedge: Shape {
    var elapsedFraction: CGFloat
    var restFraction: CGFloat

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        let e = min(max(elapsedFraction, 0), 1)
        let rf = min(max(restFraction, 0), 1)
        if rf < 0.001 { return Path() }
        var p = Path()
        p.move(to: c)
        let startDeg = -90.0 + 360.0 * Double(e)
        let endDeg = startDeg + 360.0 * Double(rf)
        p.addArc(
            center: c,
            radius: r,
            startAngle: .degrees(startDeg),
            endAngle: .degrees(endDeg),
            clockwise: false
        )
        p.closeSubpath()
        return p
    }
}

private struct RestDarkRectangleClockWedge: Shape {
    var elapsedFraction: CGFloat
    var restFraction: CGFloat

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = hypot(rect.width, rect.height)
        let e = min(max(elapsedFraction, 0), 1)
        let rf = min(max(restFraction, 0), 1)
        if rf < 0.001 { return Path() }
        var p = Path()
        p.move(to: c)
        let startDeg = -90.0 + 360.0 * Double(e)
        let endDeg = startDeg + 360.0 * Double(rf)
        p.addArc(
            center: c,
            radius: r,
            startAngle: .degrees(startDeg),
            endAngle: .degrees(endDeg),
            clockwise: false
        )
        p.closeSubpath()
        return p
    }
}

private struct DualLaneAvatarCell: View {
    let urlString: String?
    let isFocused: Bool
    let resting: Bool
    let restSeconds: Int
    let restPlannedTotal: Int?

    @State private var restEndedPulse: CGFloat = 1

    private var showRestOverlay: Bool { resting && restSeconds > 0 }

    var body: some View {
        let baseSize: CGFloat = 40
        let focusScale: CGFloat = isFocused ? 1.18 : 0.88
        let total = max(restPlannedTotal ?? max(restSeconds, 1), 1)
        let elapsedFrac = CGFloat(Double(total - restSeconds) / Double(total))
        let restFrac = CGFloat(Double(restSeconds) / Double(total))

        ZStack {
            Circle()
                .fill(Color.secondary.opacity(isFocused ? 0.26 : 0.18))
                .frame(width: baseSize, height: baseSize)
            AvatarView(urlString: urlString)
                .frame(width: baseSize, height: baseSize)
                .clipped()
                .clipShape(Circle())
                .opacity(isFocused ? 1 : 0.88)

            if showRestOverlay {
                RestDarkClockWedge(elapsedFraction: elapsedFrac, restFraction: restFrac)
                    .fill(Color.black.opacity(0.56))
                    .frame(width: baseSize, height: baseSize)
                Text("\(restSeconds)s")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.45), radius: 2, x: 0, y: 1)
                    .zIndex(1)
            }
        }
        .frame(width: baseSize, height: baseSize)
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(isFocused ? Color.accentColor : Color.white.opacity(0.35), lineWidth: isFocused ? 3 : 1)
                .frame(width: baseSize, height: baseSize)
        )
        .scaleEffect(focusScale * restEndedPulse)
        .animation(.spring(response: 0.42, dampingFraction: 0.78), value: isFocused)
        .onChange(of: restSeconds) { old, new in
            if old > 0 && new == 0 {
                playRestEndedPulse()
            }
        }
    }

    private func playRestEndedPulse() {
        Task { @MainActor in
            withAnimation(.spring(response: 0.34, dampingFraction: 0.52)) {
                restEndedPulse = 1.11
            }
            try? await Task.sleep(nanoseconds: 320_000_000)
            withAnimation(.spring(response: 0.38, dampingFraction: 0.72)) {
                restEndedPulse = 1.0
            }
            try? await Task.sleep(nanoseconds: 340_000_000)
            withAnimation(.spring(response: 0.30, dampingFraction: 0.50)) {
                restEndedPulse = 1.07
            }
            try? await Task.sleep(nanoseconds: 280_000_000)
            withAnimation(.spring(response: 0.42, dampingFraction: 0.80)) {
                restEndedPulse = 1.0
            }
        }
    }
}

private struct StrengthExerciseNavColumn: View {
    private static let celebrationFill = Color(red: 0.99, green: 0.86, blue: 0.28)
    private static let celebrationProgress = Color(red: 0.90, green: 0.68, blue: 0.04)
    private static let celebrationDot = Color(red: 0.97, green: 0.80, blue: 0.18)

    let displayNumber: Int
    let exerciseTitle: String
    let plannedSetCount: Int
    let completed: Bool
    let completionProgress: Double
    let isLast: Bool
    let isEmphasized: Bool
    let isWorkAnchor: Bool
    let allWorkoutExercisesComplete: Bool
    let isWavePulsing: Bool
    let jumpOK: Bool
    let workAnchorExerciseId: Int?
    let restOverlaySeconds: Int?
    let restPlannedTotalSeconds: Int?
    let enlargeActiveBubbleForSolo: Bool
    @Binding var popoverPresented: Bool
    let onShortTap: () -> Void
    let onLongPress: () -> Void
    @State private var burstScale: CGFloat = 0.75
    @State private var burstOpacity: Double = 0
    @State private var restEndedPulse: CGFloat = 1

    private var numberLabel: String { String(displayNumber) }

    private var seriesLine: String {
        if plannedSetCount <= 0 { return "Sin series en el plan" }
        if plannedSetCount == 1 { return "1 serie" }
        return "\(plannedSetCount) series"
    }

    private var accessibilityLine: String {
        var parts = ["Exercise \(displayNumber)"]
        if isEmphasized { parts.append("current") }
        let pct = Int((min(max(completionProgress, 0), 1) * 100).rounded())
        parts.append("progress \(pct) percent")
        if completed { parts.append("completed") }
        if isLast { parts.append("last in workout") }
        if let r = restOverlaySeconds, r > 0 {
            parts.append("rest \(r) seconds remaining")
        }
        return parts.joined(separator: ", ")
    }

    private var bubbleLayoutScale: CGFloat {
        let currentBoost: CGFloat = isEmphasized
            ? (enlargeActiveBubbleForSolo ? 1.14 : 1.09)
            : 1.0
        return currentBoost * (isWavePulsing ? 1.18 : 1.0)
    }

    var body: some View {
        VStack(spacing: 5) {
            pillStack
            progressDot
        }
        .scaleEffect(bubbleLayoutScale * restEndedPulse)
        .animation(.spring(response: 0.34, dampingFraction: 0.72), value: workAnchorExerciseId)
        .animation(.spring(response: 0.34, dampingFraction: 0.72), value: isEmphasized)
        .animation(.spring(response: 0.24, dampingFraction: 0.75), value: isWavePulsing)
        .popover(isPresented: $popoverPresented) {
            VStack(alignment: .center, spacing: 8) {
                Text(exerciseTitle)
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text(seriesLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
            .frame(minWidth: 200)
            .presentationCompactAdaptation(.popover)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityLine))
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Mantén pulsado para ver el nombre y las series")
        .onChange(of: completionProgress) { oldValue, newValue in
            guard oldValue < 0.999, newValue >= 0.999 else { return }
            scheduleBurst()
        }
        .onChange(of: restOverlaySeconds) { oldValue, newValue in
            let oldS = oldValue ?? 0
            let newS = newValue ?? 0
            if oldS > 0 && newS == 0 {
                playRestEndedPulse()
            }
        }
    }

    private var pillStack: some View {
        ZStack {
            Circle()
                .fill(fillColor)
            GeometryReader { geo in
                let p = min(max(completionProgress, 0), 1)
                Rectangle()
                    .fill(completed && allWorkoutExercisesComplete ? Self.celebrationProgress.opacity(0.92) : Color.blue.opacity(0.88))
                    .frame(width: geo.size.width * p, height: geo.size.height)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .clipShape(Circle())
            }
            if completed && isLast {
                Circle()
                    .strokeBorder(
                        allWorkoutExercisesComplete ? Self.celebrationProgress : Color.green,
                        lineWidth: 2
                    )
            }
            if isEmphasized {
                Circle()
                    .strokeBorder(Color.white.opacity(0.95), lineWidth: 2.5)
            }
            if (restOverlaySeconds ?? 0) <= 0 {
                Text(verbatim: numberLabel)
                    .font(.callout.weight(isEmphasized ? .bold : .semibold))
                    .monospacedDigit()
                    .foregroundStyle(foregroundColor)
            }
            if let restSec = restOverlaySeconds, restSec > 0 {
                let total = max(max(restPlannedTotalSeconds ?? restSec, restSec), 1)
                let eFrac = CGFloat(Double(total - restSec) / Double(total))
                let rFrac = CGFloat(Double(restSec) / Double(total))
                RestDarkClockWedge(elapsedFraction: eFrac, restFraction: rFrac)
                    .fill(Color.black.opacity(0.56))
                Text("\(restSec)s")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.75)
                    .lineLimit(1)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.45), radius: 2, x: 0, y: 1)
                    .zIndex(1)
            }
            burstOverlay
                .zIndex(2)
                .allowsHitTesting(false)
        }
        .frame(width: 34, height: 34)
        .shadow(color: isEmphasized ? Color.black.opacity(0.25) : .clear, radius: isEmphasized ? 3 : 0, y: 1)
        .contentShape(Circle())
        .onTapGesture {
            guard jumpOK, !isWorkAnchor else { return }
            onShortTap()
        }
        .onLongPressGesture(minimumDuration: 0.45) {
            onLongPress()
        }
        .opacity(jumpOK || isEmphasized ? 1 : 0.55)
    }

    private var progressDot: some View {
        Circle()
            .fill(dotColor)
            .frame(width: 5, height: 5)
    }

    private var fillColor: Color {
        if completed {
            if allWorkoutExercisesComplete { return Self.celebrationFill.opacity(0.92) }
            return Color.blue.opacity(0.88)
        }
        if isLast { return Color.green.opacity(0.22) }
        return Color.primary.opacity(0.10)
    }

    private var foregroundColor: Color {
        if completed { return .white }
        if isLast { return .green }
        return Color.primary
    }

    private var dotColor: Color {
        if completed {
            if allWorkoutExercisesComplete { return Self.celebrationDot.opacity(0.95) }
            return Color.blue.opacity(0.9)
        }
        if isEmphasized { return Color.white }
        if isLast { return Color.green.opacity(0.95) }
        return Color.primary.opacity(0.28)
    }

    @ViewBuilder
    private var burstOverlay: some View {
        if burstOpacity > 0.001 {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.92), lineWidth: 2)
                    .scaleEffect(burstScale)
                    .opacity(burstOpacity)
                ForEach(0..<6, id: \.self) { i in
                    let angle = Double(i) * .pi / 3.0
                    Circle()
                        .fill(Color.white.opacity(0.95))
                        .frame(width: 3.5, height: 3.5)
                        .offset(
                            x: CGFloat(cos(angle)) * 12 * burstScale,
                            y: CGFloat(sin(angle)) * 12 * burstScale
                        )
                        .opacity(burstOpacity)
                }
            }
        }
    }

    private func scheduleBurst() {
        var snap = Transaction()
        snap.animation = nil
        withTransaction(snap) {
            burstScale = 0.65
            burstOpacity = 1
        }
        DispatchQueue.main.async {
            var t = Transaction()
            t.animation = .easeOut(duration: 2)
            withTransaction(t) {
                burstScale = 1.55
                burstOpacity = 0
            }
        }
    }

    private func playRestEndedPulse() {
        Task { @MainActor in
            withAnimation(.spring(response: 0.34, dampingFraction: 0.52)) {
                restEndedPulse = 1.11
            }
            try? await Task.sleep(nanoseconds: 320_000_000)
            withAnimation(.spring(response: 0.38, dampingFraction: 0.72)) {
                restEndedPulse = 1.0
            }
            try? await Task.sleep(nanoseconds: 340_000_000)
            withAnimation(.spring(response: 0.30, dampingFraction: 0.50)) {
                restEndedPulse = 1.07
            }
            try? await Task.sleep(nanoseconds: 280_000_000)
            withAnimation(.spring(response: 0.42, dampingFraction: 0.80)) {
                restEndedPulse = 1.0
            }
        }
    }
}

private enum ElborblaCelebrationDecoder {
    private static let maxAnimatedFrames = 150

    static func uiImage(from data: Data, treatingGIF: Bool) -> UIImage? {
        if treatingGIF || isLikelyGIF(data) {
            return animatedImageFromImageIO(data: data) ?? UIImage(data: data)
        }
        return UIImage(data: data)
    }

    private static func isLikelyGIF(_ data: Data) -> Bool {
        guard data.count >= 3 else { return false }
        return data[0] == 0x47 && data[1] == 0x49 && data[2] == 0x46
    }

    private static func animatedImageFromImageIO(data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let count = CGImageSourceGetCount(source)
        guard count > 1 else {
            guard let cg = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
            return UIImage(cgImage: cg)
        }

        let strideBy = count > maxAnimatedFrames ? Int(ceil(Double(count) / Double(maxAnimatedFrames))) : 1
        var frames: [UIImage] = []
        var duration: TimeInterval = 0

        var index = 0
        while index < count {
            guard let cg = CGImageSourceCreateImageAtIndex(source, index, nil) else {
                index += strideBy
                continue
            }
            frames.append(UIImage(cgImage: cg))
            var chunk: TimeInterval = 0
            for j in index..<min(index + strideBy, count) {
                chunk += gifFrameDelay(source: source, index: j)
            }
            duration += chunk
            index += strideBy
        }

        guard !frames.isEmpty else { return nil }
        let total = max(duration, 0.25)
        return UIImage.animatedImage(with: frames, duration: total)
    }

    private static func gifFrameDelay(source: CGImageSource, index: Int) -> TimeInterval {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [String: Any],
              let gif = props[kCGImagePropertyGIFDictionary as String] as? [String: Any] else {
            return 0.08
        }
        if let u = gif[kCGImagePropertyGIFUnclampedDelayTime as String] as? Double, u > 0.011 {
            return u
        }
        if let d = gif[kCGImagePropertyGIFDelayTime as String] as? Double, d > 0.011 {
            return d
        }
        return 0.08
    }
}

private struct ElborblaFinishCelebrationOverlay: View {
    let image: UIImage?
    let onContinue: () -> Void

    @State private var appeared = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.72)
                .ignoresSafeArea()

            GeometryReader { geo in
                let horizontalPad: CGFloat = 20
                let maxMediaW = min(geo.size.width - horizontalPad * 2, geo.size.width * 0.5)
                let maxMediaH = max(160, geo.size.height * 0.5)

                VStack(spacing: 0) {
                    Text("¡Entreno terminado!")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.45), radius: 6, y: 2)
                        .multilineTextAlignment(.center)
                        .padding(.top, geo.safeAreaInsets.top + 8)
                        .padding(.horizontal, horizontalPad)
                        .padding(.bottom, 12)

                    Spacer(minLength: 6)

                    Group {
                        if let image {
                            CelebrationGIFBox(image: image)
                                .frame(width: maxMediaW, height: maxMediaH)
                                .clipped()
                        } else {
                            Text("🎉")
                                .font(.system(size: 72))
                                .foregroundStyle(.white)
                                .frame(width: maxMediaW, height: min(maxMediaH, 200))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .scaleEffect(appeared ? 1 : 0.88)
                    .opacity(appeared ? 1 : 0)

                    Spacer(minLength: 6)

                    Button(action: onContinue) {
                        Text("Continuar")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.black.opacity(0.88))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color.white)
                            )
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, horizontalPad + 4)
                    .padding(.bottom, max(geo.safeAreaInsets.bottom, 12) + 10)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) {
                appeared = true
            }
        }
    }
}

private struct CelebrationGIFBox: UIViewRepresentable {
    let image: UIImage

    final class Coordinator {
        var imageView: UIImageView?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let box = UIView()
        box.backgroundColor = .clear
        box.clipsToBounds = true

        let iv = UIImageView(image: image)
        iv.contentMode = .scaleAspectFit
        iv.clipsToBounds = true
        iv.backgroundColor = .clear
        iv.isUserInteractionEnabled = false
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.setContentCompressionResistancePriority(.fittingSizeLevel, for: .horizontal)
        iv.setContentCompressionResistancePriority(.fittingSizeLevel, for: .vertical)
        box.addSubview(iv)

        NSLayoutConstraint.activate([
            iv.topAnchor.constraint(equalTo: box.topAnchor),
            iv.leadingAnchor.constraint(equalTo: box.leadingAnchor),
            iv.trailingAnchor.constraint(equalTo: box.trailingAnchor),
            iv.bottomAnchor.constraint(equalTo: box.bottomAnchor),
        ])

        context.coordinator.imageView = iv
        if (image.images?.count ?? 0) > 1 {
            iv.animationRepeatCount = 0
            iv.startAnimating()
        }
        return box
    }

    func updateUIView(_ box: UIView, context: Context) {
        guard let iv = context.coordinator.imageView else { return }
        iv.image = image
        if (image.images?.count ?? 0) > 1 {
            iv.animationRepeatCount = 0
            iv.startAnimating()
        } else {
            iv.stopAnimating()
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIView, context: Context) -> CGSize? {
        guard let w = proposal.width, let h = proposal.height,
              w.isFinite, h.isFinite, w > 1, h > 1 else { return nil }
        return CGSize(width: w, height: h)
    }
}
