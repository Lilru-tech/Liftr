import SwiftUI
import Supabase
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

    private struct ExerciseRow: Decodable, Identifiable {
        let id: Int
        let exercise_id: Int64
        let order_index: Int
        let notes: String?
        let custom_name: String?
        let target_sets: Int?
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
    
    private struct InsertSetPayload: Encodable {
        let workout_exercise_id: Int
        let set_number: Int
        let reps: Int?
        let weight_kg: Decimal?
        let rpe: Decimal?
        let rest_sec: Int?
    }
    
    private struct PerformedSet {
        let reps: Int?
        let weight_kg: Decimal?
        let rpe: Decimal?
        let rest_sec: Int?
    }
    
    private struct WorkoutEndPatch: Encodable {
        let ended_at: Date
        let duration_min: Int?
    }

    private struct WorkoutStartedAtRow: Decodable {
        let started_at: Date?
    }

    private func fetchWorkoutStartedAt(client: SupabaseClient, workoutId: Int) async throws -> Date? {
        let res = try await client
            .from("workouts")
            .select("started_at")
            .eq("id", value: workoutId)
            .single()
            .execute()
        return try JSONDecoder.supabase().decode(WorkoutStartedAtRow.self, from: res.data).started_at
    }

    private func strengthSessionDurationMinutes(startedAt: Date?, endedAt: Date) -> Int? {
        guard let start = startedAt else { return nil }
        let sec = endedAt.timeIntervalSince(start)
        guard sec > 0 else { return 1 }
        return max(1, Int(sec / 60.0))
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
        let notes: String?
        let custom_name: String?
        let target_sets: Int?
        let exercises: ExName?
        struct ExName: Decodable { let name: String? }
    }
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var app: AppState
    @AppStorage("isPremium") private var isPremium = false
    @AppStorage("activeStrengthNavHintSeen") private var activeStrengthNavHintSeen = false

    @State private var restEndDate: Date? = nil
    @State private var restEndDateByExercise: [Int: Date] = [:]
    @State private var exercises: [ExerciseRow] = []
    @State private var setsByExercise: [Int: [SetRow]] = [:]
    @State private var loading = false
    @State private var error: String?
    @State private var guestDataError: String?
    @State private var isSaving = false
    @State private var showCountdown = true
    @State private var strengthWorkoutSessionStart: Date? = nil
    @State private var strengthWorkoutElapsedTick: UInt32 = 0
    @State private var currentExerciseIndex: Int = 0
    @State private var guestCurrentExerciseIndex: Int = 0
    @State private var currentSetIndex: Int = 0
    @State private var isResting = false
    @State private var remainingRest: Int = 0
    @State private var performedSetsByExercise: [Int: [PerformedSet]] = [:]
    @State private var showEditSheet = false
    @State private var editRepsText: String = ""
    @State private var showFinishEarlyConfirm = false
    @State private var showDualIncompleteFinishConfirm = false
    @State private var editWeightText: String = ""
    @State private var editRestText: String = ""
    @State private var dragOffsetY: CGFloat = 0
    @State private var isTransitioningExercise: Bool = false
    @State private var currentSetIndexByExercise: [Int: Int] = [:]
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
    private let swipeThreshold: CGFloat = 110
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
        if !isDualMode { return currentExerciseIndex }
        switch mainDisplayLane {
        case .host: return currentExerciseIndex
        case .guest: return guestCurrentExerciseIndex
        case .guest2: return g2CurrentExerciseIndex
        }
    }

    private var pagerOrdered: [ExerciseRow] {
        orderedExercises(lane: mainDisplayLane)
    }

    private var pagerCurrentExercise: ExerciseRow? {
        let list = pagerOrdered
        let idx = pagerExerciseIndex
        guard !list.isEmpty,
              idx >= 0,
              idx < list.count
        else { return nil }
        return list[idx]
    }

    private var pagerNextExercise: ExerciseRow? {
        let list = pagerOrdered
        let nextIndex = pagerExerciseIndex + 1
        guard nextIndex >= 0, nextIndex < list.count else { return nil }
        return list[nextIndex]
    }

    private var pagerPreviousExercise: ExerciseRow? {
        let list = pagerOrdered
        let prevIndex = pagerExerciseIndex - 1
        guard prevIndex >= 0, prevIndex < list.count else { return nil }
        return list[prevIndex]
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
                    } else if let error {
                        VStack(spacing: 12) {
                            Text("Error").font(.headline)
                            Text(error).foregroundStyle(.secondary)
                            Button("Close") { dismiss() }
                        }
                        .padding()
                    } else if currentExercise != nil
                        || (isDualMode && !orderedGuestExercises.isEmpty)
                        || (isTripleMode && !orderedGuest2Exercises.isEmpty) {
                        exercisePager()
                    } else {
                        VStack(spacing: 12) {
                            Text("No exercises found")
                                .font(.headline)
                            Button("Close") { dismiss() }
                        }
                        .padding()
                    }
                }
                
                if isSaving {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                    ProgressView("Saving workout…")
                        .padding(24)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
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
                if !isPremium, !showElborblaCelebration {
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
                }
                if !showCountdown, strengthWorkoutSessionStart != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        strengthWorkoutSessionElapsedChip()
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
        .sheet(isPresented: $showEditSheet) {
            VStack(spacing: 20) {
                Text("Edit reps, weight & rest")
                    .font(.title3.weight(.semibold))
                
                TextField("Reps", text: $editRepsText)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                
                TextField("Weight (kg)", text: $editWeightText)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                
                TextField("Rest (sec)", text: $editRestText)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)

                Text("Edits update this workout flow now and are written when you finish the workout.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                
                HStack {
                    Button("Cancel") {
                        showEditSheet = false
                    }
                    .frame(maxWidth: .infinity)
                    
                    Button("Save") {
                        applyEditsToCurrentExercise()
                        showEditSheet = false
                    }
                    .frame(maxWidth: .infinity)
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
            .presentationDetents([.medium])
        }
        .onReceive(restTimer) { _ in
            if isResting || gIsResting || g2IsResting {
                syncRestCountdownFromEndDate()
            }
            if strengthWorkoutSessionStart != nil, !showCountdown {
                strengthWorkoutElapsedTick &+= 1
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            syncRestCountdownFromEndDate()
            if strengthWorkoutSessionStart != nil {
                strengthWorkoutElapsedTick &+= 1
            }
        }
        .onAppear {
            #if DEBUG
            dualStrengthDebug(
                "onAppear showCountdown=\(showCountdown) isDualMode=\(dualGuestWorkoutId != nil) "
                    + "guestWid=\(dualGuestWorkoutId.map(String.init) ?? "nil") "
                    + "hostHasURL=\(dualHostAvatarURL != nil) guestHasURL=\(dualGuestAvatarURL != nil)"
            )
            #endif
        }
        .task { await load() }
        .onDisappear {
            Task { await sanitizeEndDateIfNeededOnClose() }
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
        let laneRemainingRest: Int = {
            switch lane {
            case .host: return remainingRest
            case .guest: return gRemainingRest
            case .guest2: return g2RemainingRest
            }
        }()
        let lockRestActions = laneIsResting && isActiveExercise && !allSetsDone

        if let s = currentSet {
            VStack(spacing: 12) {
                Text("Set \(displaySetIndex + 1) of \(totalSets)")
                    .font(.headline)
                    .foregroundStyle(isExtraCurrentSet ? .green : .primary)

                Text("\(s.reps ?? 0) reps")
                    .font(.title2.weight(.semibold))

                Text(weightStr(s.weight_kg))
                    .font(.title3)
                    .foregroundStyle(.secondary)

                if let rpe = s.rpe {
                    Text("Target RPE \(String(format: "%.1f", NSDecimalNumber(decimal: rpe).doubleValue))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(20)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))

            Button {
                editRepsText = "\(s.reps ?? 0)"
                if let w = s.weight_kg {
                    editWeightText = String(format: "%.1f", NSDecimalNumber(decimal: w).doubleValue)
                } else {
                    editWeightText = ""
                }
                editRestText = "\(s.rest_sec ?? 0)"
                editTargetLane = lane
                showEditSheet = true
            } label: {
                Text("Edit reps, weight & rest")
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

        if isActiveExercise, let s = currentSet, (s.rest_sec ?? 0) > 0 {
            VStack(spacing: 12) {
                if laneIsResting {
                    Text("Rest")
                        .font(.headline)
                    Text("\(laneRemainingRest)s")
                        .font(.system(size: 36, weight: .bold, design: .rounded))

                    Button("Skip rest") {
                        skipRest(for: lane, exerciseId: ex.id)
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button {
                        completeCurrentSet(lane: lane)
                        startRest(for: s, lane: lane)
                    } label: {
                        Text("Rest \(s.rest_sec ?? 0)s")
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
            VStack(spacing: 12) {
                Text("Rest")
                    .font(.headline)
                Text("\(laneRemainingRest)s")
                    .font(.system(size: 36, weight: .bold, design: .rounded))

                Button("Skip rest") {
                    skipRest(for: lane, exerciseId: ex.id)
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity)
        }

        VStack(spacing: 10) {
            Button {
                ensureBaseSetExists(for: ex, lane: lane)
                addOneSetToConfigs(for: ex, lane: lane)
                withAnimation { showToast("Added 1 set") }
            } label: {
                Text("Add set")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .contentShape(Rectangle())
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.accentColor, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .disabled(isSaving || lockRestActions)
            .opacity((isSaving || lockRestActions) ? 0.45 : 1)

            Button {
                removeOneSet(for: ex, lane: lane)
            } label: {
                Text("Remove set")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .contentShape(Rectangle())
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.red.opacity(0.75), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .disabled(laneIsResting || isSaving || (isActiveExercise && allSetsDone) || !canRemoveAnySet(for: ex, lane: lane))
            .opacity((laneIsResting || isSaving || (isActiveExercise && allSetsDone) || !canRemoveAnySet(for: ex, lane: lane)) ? 0.45 : 1)
        }

        let hasNextInLane = laneNextExercise(lane: lane) != nil

        if allSetsDone {
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
        if !hasNextInLane && !allSetsDone {
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
        let nextIndex = idx + 1
        guard nextIndex >= 0, nextIndex < list.count else { return nil }
        return list[nextIndex]
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
        s += "\nThis will save and close all workouts on this phone. Continue?"
        return s
    }

    private func earlyFinishAlertMessage() -> String {
        let base = "You haven't completed all planned sets. The workout will be saved with only the sets you actually performed."
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
        case .guest:
            gIsResting = false
            gRemainingRest = 0
            gRestEndDate = nil
            gDidFireRestFinishedFeedback = false
            gIsRestingByExercise[exerciseId] = false
            gRemainingRestByExercise[exerciseId] = 0
            gRestEndDateByExercise[exerciseId] = nil
        case .guest2:
            g2IsResting = false
            g2RemainingRest = 0
            g2RestEndDate = nil
            g2DidFireRestFinishedFeedback = false
            g2IsRestingByExercise[exerciseId] = false
            g2RemainingRestByExercise[exerciseId] = 0
            g2RestEndDateByExercise[exerciseId] = nil
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

        let orderedConfigs = configs.sorted { $0.id < $1.id }

        for config in orderedConfigs {
            let count = max(config.set_number, 0)

            for _ in 0..<count {
                let sequentialNumber = expanded.count + 1

                let pseudoSet = SetRow(
                    id: config.id * 1000 + sequentialNumber,
                    workout_exercise_id: config.workout_exercise_id,
                    set_number: sequentialNumber,
                    reps: config.reps,
                    weight_kg: config.weight_kg,
                    rpe: config.rpe,
                    rest_sec: config.rest_sec
                )

                expanded.append(pseudoSet)
            }
        }

        return expanded
    }

    private func startRest(for set: SetRow, lane: StrengthLaneKind = .host) {
        let sec = set.rest_sec ?? 0
        guard sec > 0 else { return }

        let end = Date().addingTimeInterval(TimeInterval(sec))
        switch lane {
        case .host:
            restEndDate = end
            remainingRest = sec
            isResting = true
            didFireRestFinishedFeedback = false
            if let ex = currentExercise {
                isRestingByExercise[ex.id] = true
                remainingRestByExercise[ex.id] = sec
                restEndDateByExercise[ex.id] = end
            }
        case .guest:
            gRestEndDate = end
            gRemainingRest = sec
            gIsResting = true
            gDidFireRestFinishedFeedback = false
            if let ex = currentGuestExercise {
                gIsRestingByExercise[ex.id] = true
                gRemainingRestByExercise[ex.id] = sec
                gRestEndDateByExercise[ex.id] = end
            }
        case .guest2:
            g2RestEndDate = end
            g2RemainingRest = sec
            g2IsResting = true
            g2DidFireRestFinishedFeedback = false
            if let ex = currentGuest2Exercise {
                g2IsRestingByExercise[ex.id] = true
                g2RemainingRestByExercise[ex.id] = sec
                g2RestEndDateByExercise[ex.id] = end
            }
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
    
    private func syncRestCountdownFromEndDate() {
        if isResting, let end = restEndDate {
            let newRemaining = max(0, Int(ceil(end.timeIntervalSinceNow)))
            remainingRest = newRemaining

            if remainingRest <= 0 {
                isResting = false
                remainingRest = 0
                restEndDate = nil
                if !didFireRestFinishedFeedback {
                    didFireRestFinishedFeedback = true
                    restFinishedFeedback()
                }
                if let ex = currentExercise {
                    isRestingByExercise[ex.id] = false
                    remainingRestByExercise[ex.id] = 0
                    restEndDateByExercise[ex.id] = nil
                }
            } else if let ex = currentExercise {
                isRestingByExercise[ex.id] = true
                remainingRestByExercise[ex.id] = remainingRest
                restEndDateByExercise[ex.id] = end
            }
        }

        if gIsResting, let gEnd = gRestEndDate {
            let newGR = max(0, Int(ceil(gEnd.timeIntervalSinceNow)))
            gRemainingRest = newGR

            if gRemainingRest <= 0 {
                gIsResting = false
                gRemainingRest = 0
                gRestEndDate = nil
                if !gDidFireRestFinishedFeedback {
                    gDidFireRestFinishedFeedback = true
                    restFinishedFeedback()
                }
                if let ex = currentGuestExercise {
                    gIsRestingByExercise[ex.id] = false
                    gRemainingRestByExercise[ex.id] = 0
                    gRestEndDateByExercise[ex.id] = nil
                }
            } else if let ex = currentGuestExercise {
                gIsRestingByExercise[ex.id] = true
                gRemainingRestByExercise[ex.id] = gRemainingRest
                gRestEndDateByExercise[ex.id] = gEnd
            }
        }

        if g2IsResting, let g2End = g2RestEndDate {
            let newG2 = max(0, Int(ceil(g2End.timeIntervalSinceNow)))
            g2RemainingRest = newG2

            if g2RemainingRest <= 0 {
                g2IsResting = false
                g2RemainingRest = 0
                g2RestEndDate = nil
                if !g2DidFireRestFinishedFeedback {
                    g2DidFireRestFinishedFeedback = true
                    restFinishedFeedback()
                }
                if let ex = currentGuest2Exercise {
                    g2IsRestingByExercise[ex.id] = false
                    g2RemainingRestByExercise[ex.id] = 0
                    g2RestEndDateByExercise[ex.id] = nil
                }
            } else if let ex = currentGuest2Exercise {
                g2IsRestingByExercise[ex.id] = true
                g2RemainingRestByExercise[ex.id] = g2RemainingRest
                g2RestEndDateByExercise[ex.id] = g2End
            }
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
            var sets = setsFor(ex, lane: .host)
            if sets.isEmpty {
                ensureBaseSetExists(for: ex, lane: .host)
                sets = setsFor(ex, lane: .host)
                if sets.isEmpty { return }
            }

            if let s = currentSetFor(ex, setIndex: currentSetIndex, lane: .host) {
                var list = performedSetsByExercise[ex.id] ?? []
                let performed = PerformedSet(
                    reps: s.reps,
                    weight_kg: s.weight_kg,
                    rpe: s.rpe,
                    rest_sec: s.rest_sec
                )
                list.append(performed)
                performedSetsByExercise[ex.id] = list
            }

            let totalSets = sets.count

            if currentSetIndex < totalSets - 1 {
                currentSetIndex += 1
            } else {
                currentSetIndex = totalSets
            }

            currentSetIndexByExercise[ex.id] = currentSetIndex
            isRestingByExercise[ex.id] = isResting
            remainingRestByExercise[ex.id] = remainingRest

        case .guest:
            guard let ex = currentGuestExercise else { return }
            var sets = setsFor(ex, lane: .guest)
            if sets.isEmpty {
                ensureBaseSetExists(for: ex, lane: .guest)
                sets = setsFor(ex, lane: .guest)
                if sets.isEmpty { return }
            }

            if let s = currentSetFor(ex, setIndex: gCurrentSetIndex, lane: .guest) {
                var list = gPerformedSetsByExercise[ex.id] ?? []
                let performed = PerformedSet(
                    reps: s.reps,
                    weight_kg: s.weight_kg,
                    rpe: s.rpe,
                    rest_sec: s.rest_sec
                )
                list.append(performed)
                gPerformedSetsByExercise[ex.id] = list
            }

            let totalSets = sets.count

            if gCurrentSetIndex < totalSets - 1 {
                gCurrentSetIndex += 1
            } else {
                gCurrentSetIndex = totalSets
            }

            gCurrentSetIndexByExercise[ex.id] = gCurrentSetIndex
            gIsRestingByExercise[ex.id] = gIsResting
            gRemainingRestByExercise[ex.id] = gRemainingRest

        case .guest2:
            guard let ex = currentGuest2Exercise else { return }
            var sets = setsFor(ex, lane: .guest2)
            if sets.isEmpty {
                ensureBaseSetExists(for: ex, lane: .guest2)
                sets = setsFor(ex, lane: .guest2)
                if sets.isEmpty { return }
            }

            if let s = currentSetFor(ex, setIndex: g2CurrentSetIndex, lane: .guest2) {
                var list = g2PerformedSetsByExercise[ex.id] ?? []
                let performed = PerformedSet(
                    reps: s.reps,
                    weight_kg: s.weight_kg,
                    rpe: s.rpe,
                    rest_sec: s.rest_sec
                )
                list.append(performed)
                g2PerformedSetsByExercise[ex.id] = list
            }

            let totalSets = sets.count

            if g2CurrentSetIndex < totalSets - 1 {
                g2CurrentSetIndex += 1
            } else {
                g2CurrentSetIndex = totalSets
            }

            g2CurrentSetIndexByExercise[ex.id] = g2CurrentSetIndex
            g2IsRestingByExercise[ex.id] = g2IsResting
            g2RemainingRestByExercise[ex.id] = g2RemainingRest
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
                rest_sec: last.rest_sec
            )

            setsByExercise[key] = configs

            let total = setsFor(ex, lane: .host).count
            if currentExercise?.id == key, currentSetIndex >= total {
                currentSetIndex = max(0, total - 1)
            }
            currentSetIndexByExercise[key] = (currentExercise?.id == key) ? currentSetIndex : (currentSetIndexByExercise[key] ?? 0)

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
                rest_sec: last.rest_sec
            )

            gSetsByExercise[key] = configs

            let total = setsFor(ex, lane: .guest).count
            if currentGuestExercise?.id == key, gCurrentSetIndex >= total {
                gCurrentSetIndex = max(0, total - 1)
            }
            gCurrentSetIndexByExercise[key] = (currentGuestExercise?.id == key) ? gCurrentSetIndex : (gCurrentSetIndexByExercise[key] ?? 0)

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
                rest_sec: last.rest_sec
            )

            g2SetsByExercise[key] = configs

            let total = setsFor(ex, lane: .guest2).count
            if currentGuest2Exercise?.id == key, g2CurrentSetIndex >= total {
                g2CurrentSetIndex = max(0, total - 1)
            }
            g2CurrentSetIndexByExercise[key] = (currentGuest2Exercise?.id == key) ? g2CurrentSetIndex : (g2CurrentSetIndexByExercise[key] ?? 0)
        }
    }

    private func ensureBaseSetExists(for ex: ExerciseRow, lane: StrengthLaneKind = .host) {
        let key = ex.id
        let planned = setsFor(ex, lane: lane).count
        if planned > 0 { return }

        let base = SetRow(
            id: Int.random(in: 1_000_000...9_999_999),
            workout_exercise_id: ex.id,
            set_number: 1,
            reps: 10,
            weight_kg: 0,
            rpe: nil,
            rest_sec: 60
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

    private func removeOneSet(for ex: ExerciseRow, lane: StrengthLaneKind = .host) {
        let key = ex.id

        switch lane {
        case .host:
            var configs = setsByExercise[key] ?? []
            guard !configs.isEmpty else {
                showToast("No sets to remove")
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
                rest_sec: last.rest_sec
            )

            if configs[lastIdx].set_number == 0 {
                configs.remove(at: lastIdx)
            }

            setsByExercise[key] = configs

            let totalNow = setsFor(ex, lane: .host).count

            if var performed = performedSetsByExercise[key], performed.count > totalNow {
                performed = Array(performed.prefix(totalNow))
                performedSetsByExercise[key] = performed
                showToast("Removed 1 set (and adjusted completed sets)")
            } else {
                showToast("Removed 1 set")
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
                showToast("No sets to remove")
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
                rest_sec: last.rest_sec
            )

            if configs[lastIdx].set_number == 0 {
                configs.remove(at: lastIdx)
            }

            gSetsByExercise[key] = configs

            let totalNow = setsFor(ex, lane: .guest).count

            if var performed = gPerformedSetsByExercise[key], performed.count > totalNow {
                performed = Array(performed.prefix(totalNow))
                gPerformedSetsByExercise[key] = performed
                showToast("Removed 1 set (and adjusted completed sets)")
            } else {
                showToast("Removed 1 set")
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
                showToast("No sets to remove")
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
                rest_sec: last.rest_sec
            )

            if configs[lastIdx].set_number == 0 {
                configs.remove(at: lastIdx)
            }

            g2SetsByExercise[key] = configs

            let totalNow = setsFor(ex, lane: .guest2).count

            if var performed = g2PerformedSetsByExercise[key], performed.count > totalNow {
                performed = Array(performed.prefix(totalNow))
                g2PerformedSetsByExercise[key] = performed
                showToast("Removed 1 set (and adjusted completed sets)")
            } else {
                showToast("Removed 1 set")
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
        let ordered = orderedExercises(lane: lane)
        let idx = pagerExerciseIndex
        guard !ordered.isEmpty, idx < ordered.count - 1 else { return }

        persistStateForCurrentDualIndex()

        switch lane {
        case .host: currentExerciseIndex += 1
        case .guest: guestCurrentExerciseIndex += 1
        case .guest2: g2CurrentExerciseIndex += 1
        }

        restoreStateForDualIndex()
    }
    
    private func goToPreviousExercise() {
        let lane = mainDisplayLane
        let ordered = orderedExercises(lane: lane)
        let idx = pagerExerciseIndex
        guard !ordered.isEmpty, idx > 0 else { return }

        persistStateForCurrentDualIndex()

        switch lane {
        case .host: currentExerciseIndex -= 1
        case .guest: guestCurrentExerciseIndex -= 1
        case .guest2: g2CurrentExerciseIndex -= 1
        }

        restoreStateForDualIndex()
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
        if isTransitioningExercise { return false }

        if laneBlocksExerciseSwipe(mainDisplayLane) { return false }

        return true
    }
    
    private func canGoNextExercise() -> Bool {
        let ordered = orderedExercises(lane: mainDisplayLane)
        guard !ordered.isEmpty else { return false }
        return pagerExerciseIndex < ordered.count - 1
    }

    private func canGoPreviousExercise() -> Bool {
        pagerExerciseIndex > 0
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
        !showCountdown && !isSaving && !showEditSheet && !isTransitioningExercise
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
        }
        .frame(maxWidth: .infinity)
        .frame(height: cardHeight)
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    private func clampLaneExerciseIndex(_ lane: StrengthLaneKind) {
        switch lane {
        case .host:
            let n = orderedExercises.count
            guard n > 0 else {
                currentExerciseIndex = 0
                return
            }
            currentExerciseIndex = min(max(0, currentExerciseIndex), n - 1)
        case .guest:
            let n = orderedGuestExercises.count
            guard n > 0 else {
                guestCurrentExerciseIndex = 0
                return
            }
            guestCurrentExerciseIndex = min(max(0, guestCurrentExerciseIndex), n - 1)
        case .guest2:
            let n = orderedGuest2Exercises.count
            guard n > 0 else {
                g2CurrentExerciseIndex = 0
                return
            }
            g2CurrentExerciseIndex = min(max(0, g2CurrentExerciseIndex), n - 1)
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
            switch lane {
            case .host: currentExerciseIndex = index
            case .guest: guestCurrentExerciseIndex = index
            case .guest2: g2CurrentExerciseIndex = index
            }
        }

        restoreStateForDualIndex()
        dragOffsetY = 0
    }

    @ViewBuilder
    private func navStripBubblesRow(lane: StrengthLaneKind) -> some View {
        let list = orderedExercises(lane: lane)
        HStack(alignment: .top, spacing: 8) {
            ForEach(Array(list.enumerated()), id: \.element.id) { idx, _ in
                exerciseNavColumnView(lane: lane, index: idx)
                    .id(navStripRowId(lane: lane, index: idx))
            }
        }
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
                let n = list.count
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

    private var strengthWorkoutElapsedDisplayString: String {
        _ = strengthWorkoutElapsedTick
        guard let start = strengthWorkoutSessionStart else { return "0:00" }
        let elapsed = max(0, Int(floor(Date().timeIntervalSince(start))))
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
    private func exerciseNavColumnView(lane: StrengthLaneKind, index idx: Int) -> some View {
        let list = orderedExercises(lane: lane)
        let ex = list[idx]
        let completed = isExerciseCompleted(ex, lane: lane)
        let isLast = idx == list.count - 1
        let currentIdx: Int = {
            switch lane {
            case .host: return currentExerciseIndex
            case .guest: return guestCurrentExerciseIndex
            case .guest2: return g2CurrentExerciseIndex
            }
        }()
        let isCurrent = idx == currentIdx
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
        StrengthExerciseNavColumn(
            displayNumber: idx + 1,
            exerciseTitle: title,
            plannedSetCount: plannedSets,
            completed: completed,
            completionProgress: completionProgress,
            isLast: isLast,
            isCurrent: isCurrent,
            allWorkoutExercisesComplete: allExercisesCompleted(for: lane),
            isWavePulsing: strengthNavStripWaveIndex == idx,
            jumpOK: jumpOK,
            navAnimationIndex: currentIdx,
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
                dualAvatarCell(lane: .host, url: dualHostAvatarURL, isFocused: mainDisplayLane == .host)
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
                dualAvatarCell(lane: .guest, url: dualGuestAvatarURL, isFocused: mainDisplayLane == .guest)
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
                    dualAvatarCell(lane: .guest2, url: dualGuest2AvatarURL, isFocused: mainDisplayLane == .guest2)
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
    private func dualAvatarCell(lane: StrengthLaneKind, url: String?, isFocused: Bool) -> some View {
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
        let showRestOverlay = resting && secs > 0
        let baseSize: CGFloat = 40
        let scale: CGFloat = isFocused ? 1.18 : 0.88

        ZStack {
            Circle()
                .fill(Color.secondary.opacity(isFocused ? 0.26 : 0.18))
                .frame(width: baseSize, height: baseSize)
            AvatarView(urlString: url)
                .frame(width: baseSize, height: baseSize)
                .clipped()
                .clipShape(Circle())
                .opacity(isFocused ? 1 : 0.88)

            if showRestOverlay {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.black.opacity(0.35),
                                Color.black.opacity(0.62)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: baseSize, height: baseSize)
                Text("\(secs)s")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.45), radius: 2, x: 0, y: 1)
            }
        }
        .frame(width: baseSize, height: baseSize)
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(isFocused ? Color.accentColor : Color.white.opacity(0.35), lineWidth: isFocused ? 3 : 1)
                .frame(width: baseSize, height: baseSize)
        )
        .scaleEffect(scale)
        .animation(.spring(response: 0.42, dampingFraction: 0.78), value: isFocused)
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
            let cardHeightIfLoose = max(usableForCluster * 0.66, 220)
            let neededIfLoose = cardHeightIfLoose + 2 * (peekHeight + peekGap)
            let cardHeight: CGFloat = neededIfLoose > usableForCluster
                ? max(usableForCluster - 2 * (peekHeight + peekGap), 200)
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

            if let cur = pagerCurrentExercise {
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
                                goToNextExercise()
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
                                goToPreviousExercise()
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
    
    private func saveAndFinishWorkout() async {
        var exList: [ExerciseRow] = []
        var performedMap: [Int: [PerformedSet]] = [:]
        var guestExList: [ExerciseRow] = []
        var guestPerformedMap: [Int: [PerformedSet]] = [:]
        var guestWorkoutId: Int?
        var guest2ExList: [ExerciseRow] = []
        var guest2PerformedMap: [Int: [PerformedSet]] = [:]
        var guest2WorkoutId: Int?

        await MainActor.run {
            exList = self.orderedExercises
            performedMap = self.performedSetsByExercise
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
            self.isSaving = true
        }

        let client = SupabaseManager.shared.client

        func persistExerciseRows(_ rows: [ExerciseRow], performedMap: [Int: [PerformedSet]]) async throws {
            for ex in rows {
                let performedSets = performedMap[ex.id] ?? []
                var blocks: [(count: Int, template: PerformedSet)] = []
                var currentTemplate: PerformedSet?
                var currentCount = 0

                for p in performedSets {
                    if let cur = currentTemplate,
                       cur.reps == p.reps,
                       cur.weight_kg == p.weight_kg,
                       cur.rpe == p.rpe,
                       cur.rest_sec == p.rest_sec {
                        currentCount += 1
                    } else {
                        if let cur = currentTemplate {
                            blocks.append((currentCount, cur))
                        }
                        currentTemplate = p
                        currentCount = 1
                    }
                }
                if let cur = currentTemplate {
                    blocks.append((currentCount, cur))
                }

                _ = try await client
                    .from("exercise_sets")
                    .delete()
                    .eq("workout_exercise_id", value: ex.id)
                    .execute()

                let payloads: [InsertSetPayload] = blocks.map { block in
                    InsertSetPayload(
                        workout_exercise_id: ex.id,
                        set_number: block.count,
                        reps: block.template.reps,
                        weight_kg: block.template.weight_kg,
                        rpe: block.template.rpe,
                        rest_sec: block.template.rest_sec
                    )
                }

                if !payloads.isEmpty {
                    _ = try await client
                        .from("exercise_sets")
                        .insert(payloads)
                        .execute()
                }
            }
        }

        do {
            try await persistExerciseRows(exList, performedMap: performedMap)

            let endTime = Date()
            let hostStart = try await fetchWorkoutStartedAt(client: client, workoutId: workoutId)
            let hostDur = strengthSessionDurationMinutes(startedAt: hostStart, endedAt: endTime)

            _ = try await client
                .from("workouts")
                .update(WorkoutEndPatch(ended_at: endTime, duration_min: hostDur))
                .eq("id", value: workoutId)
                .execute()

            NotificationCenter.default.post(name: .workoutDidChange, object: workoutId)

            if let gid = guestWorkoutId {
                try await persistExerciseRows(guestExList, performedMap: guestPerformedMap)
                let gStart = try await fetchWorkoutStartedAt(client: client, workoutId: gid)
                let gDur = strengthSessionDurationMinutes(startedAt: gStart, endedAt: endTime)
                _ = try await client
                    .from("workouts")
                    .update(WorkoutEndPatch(ended_at: endTime, duration_min: gDur))
                    .eq("id", value: gid)
                    .execute()
                NotificationCenter.default.post(name: .workoutDidChange, object: gid)
            }

            if let g2id = guest2WorkoutId {
                try await persistExerciseRows(guest2ExList, performedMap: guest2PerformedMap)
                let g2Start = try await fetchWorkoutStartedAt(client: client, workoutId: g2id)
                let g2Dur = strengthSessionDurationMinutes(startedAt: g2Start, endedAt: endTime)
                _ = try await client
                    .from("workouts")
                    .update(WorkoutEndPatch(ended_at: endTime, duration_min: g2Dur))
                    .eq("id", value: g2id)
                    .execute()
                NotificationCenter.default.post(name: .workoutDidChange, object: g2id)
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
            await MainActor.run {
                self.isSaving = false
                self.error = error.localizedDescription
            }
        }
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
    
    private func configIndexForSetIndex(_ ex: ExerciseRow, setIndex: Int, lane: StrengthLaneKind = .host) -> Int? {
        let configs: [SetRow]
        switch lane {
        case .host: configs = (setsByExercise[ex.id] ?? []).sorted { $0.id < $1.id }
        case .guest: configs = (gSetsByExercise[ex.id] ?? []).sorted { $0.id < $1.id }
        case .guest2: configs = (g2SetsByExercise[ex.id] ?? []).sorted { $0.id < $1.id }
        }
        var cursor = 0
        for (i, c) in configs.enumerated() {
            let blockCount = max(0, c.set_number)
            let next = cursor + blockCount
            if setIndex >= cursor && setIndex < next {
                return i
            }
            cursor = next
        }
        return nil
    }
            
    private func applyEditsToCurrentExercise() {
        let ex: ExerciseRow?
        let activeSetIndex: Int
        switch editTargetLane {
        case .host:
            ex = currentExercise
            activeSetIndex = currentSetIndex
        case .guest:
            ex = currentGuestExercise
            activeSetIndex = gCurrentSetIndex
        case .guest2:
            ex = currentGuest2Exercise
            activeSetIndex = g2CurrentSetIndex
        }
        guard let ex else { return }

        let trimmedReps = editRepsText.trimmingCharacters(in: .whitespacesAndNewlines)
        let newReps = Int(trimmedReps)
        let trimmedWeight = editWeightText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")

        let newWeightDecimal: Decimal?
        if trimmedWeight.isEmpty {
            newWeightDecimal = nil
        } else {
            newWeightDecimal = Decimal(string: trimmedWeight)
        }

        let trimmedRest = editRestText.trimmingCharacters(in: .whitespacesAndNewlines)
        let newRestSecRaw = Int(trimmedRest)
        let newRestSec = (newRestSecRaw != nil) ? max(0, newRestSecRaw!) : nil

        var configs: [SetRow]
        switch editTargetLane {
        case .host: configs = (setsByExercise[ex.id] ?? []).sorted { $0.id < $1.id }
        case .guest: configs = (gSetsByExercise[ex.id] ?? []).sorted { $0.id < $1.id }
        case .guest2: configs = (g2SetsByExercise[ex.id] ?? []).sorted { $0.id < $1.id }
        }
        guard !configs.isEmpty else { return }

        let idx = configIndexForSetIndex(ex, setIndex: activeSetIndex, lane: editTargetLane) ?? 0
        let old = configs[idx]

        let updated = SetRow(
            id: old.id,
            workout_exercise_id: old.workout_exercise_id,
            set_number: old.set_number,
            reps: newReps ?? old.reps,
            weight_kg: newWeightDecimal ?? old.weight_kg,
            rpe: old.rpe,
            rest_sec: newRestSec ?? old.rest_sec
        )

        configs[idx] = updated
        switch editTargetLane {
        case .host: setsByExercise[ex.id] = configs
        case .guest: gSetsByExercise[ex.id] = configs
        case .guest2: g2SetsByExercise[ex.id] = configs
        }
    }
    
    private func fetchStrengthWorkoutData(forWid wid: Int) async throws -> ([ExerciseRow], [Int: [SetRow]]) {
        let exQ = try await SupabaseManager.shared.client
            .from("workout_exercises")
            .select("id, exercise_id, order_index, notes, custom_name, exercises(name)")
            .eq("workout_id", value: wid)
            .order("order_index", ascending: true)
            .execute()

        struct ExWire: Decodable {
            let id: Int
            let exercise_id: Int64
            let order_index: Int
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
                notes: $0.notes,
                custom_name: $0.custom_name,
                target_sets: $0.target_sets,
                exercise_name: $0.exercises?.name
            )
        }

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

    private func load() async {
        loading = true
        defer { loading = false }

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
                self.guestCurrentExerciseIndex = 0
                self.g2CurrentExerciseIndex = 0
                self.currentSetIndex = 0
                self.gCurrentSetIndex = 0
                self.g2CurrentSetIndex = 0

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
                self.error = error.localizedDescription
            }
        }
    }
        
    private func weightStr(_ w: Decimal?) -> String {
        guard let w else { return "0.0 kg" }
        return String(format: "%.1f kg", NSDecimalNumber(decimal: w).doubleValue)
    }
    
    private func showToast(_ msg: String) {
        toastMessage = msg
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            if toastMessage == msg {
                toastMessage = nil
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
    let isCurrent: Bool
    let allWorkoutExercisesComplete: Bool
    let isWavePulsing: Bool
    let jumpOK: Bool
    let navAnimationIndex: Int
    @Binding var popoverPresented: Bool
    let onShortTap: () -> Void
    let onLongPress: () -> Void
    @State private var burstScale: CGFloat = 0.75
    @State private var burstOpacity: Double = 0

    private var numberLabel: String { String(displayNumber) }

    private var seriesLine: String {
        if plannedSetCount <= 0 { return "Sin series en el plan" }
        if plannedSetCount == 1 { return "1 serie" }
        return "\(plannedSetCount) series"
    }

    private var accessibilityLine: String {
        var parts = ["Exercise \(displayNumber)"]
        if isCurrent { parts.append("current") }
        let pct = Int((min(max(completionProgress, 0), 1) * 100).rounded())
        parts.append("progress \(pct) percent")
        if completed { parts.append("completed") }
        if isLast { parts.append("last in workout") }
        return parts.joined(separator: ", ")
    }

    private var bubbleLayoutScale: CGFloat {
        (isCurrent ? 1.09 : 1.0) * (isWavePulsing ? 1.18 : 1.0)
    }

    var body: some View {
        VStack(spacing: 5) {
            pillStack
            progressDot
        }
        .scaleEffect(bubbleLayoutScale)
        .animation(.spring(response: 0.34, dampingFraction: 0.72), value: navAnimationIndex)
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
            if isCurrent {
                Circle()
                    .strokeBorder(Color.white.opacity(0.95), lineWidth: 2.5)
            }
            Text(verbatim: numberLabel)
                .font(.callout.weight(isCurrent ? .bold : .semibold))
                .monospacedDigit()
                .foregroundStyle(foregroundColor)
            burstOverlay
                .zIndex(2)
                .allowsHitTesting(false)
        }
        .frame(width: 34, height: 34)
        .shadow(color: isCurrent ? Color.black.opacity(0.25) : .clear, radius: isCurrent ? 3 : 0, y: 1)
        .contentShape(Circle())
        .onTapGesture {
            guard jumpOK, !isCurrent else { return }
            onShortTap()
        }
        .onLongPressGesture(minimumDuration: 0.45) {
            onLongPress()
        }
        .opacity(jumpOK || isCurrent ? 1 : 0.55)
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
        if isCurrent { return Color.white }
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
