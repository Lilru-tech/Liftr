import SwiftUI
import Supabase
import AVFoundation
import AudioToolbox

struct ActiveStrengthWorkoutView: View {
    let workoutId: Int
    
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
    }
    
    private struct WorkoutSanitizePatch: Encodable {
        let ended_at: Date?
    }
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @State private var restEndDate: Date? = nil
    @State private var restEndDateByExercise: [Int: Date] = [:]
    @State private var exercises: [ExerciseRow] = []
    @State private var setsByExercise: [Int: [SetRow]] = [:]
    @State private var loading = false
    @State private var error: String?
    @State private var isSaving = false
    @State private var showCountdown = true
    @State private var currentExerciseIndex: Int = 0
    @State private var currentSetIndex: Int = 0
    @State private var isResting = false
    @State private var remainingRest: Int = 0
    @State private var performedSetsByExercise: [Int: [PerformedSet]] = [:]
    @State private var showEditSheet = false
    @State private var editRepsText: String = ""
    @State private var showFinishEarlyConfirm = false
    @State private var editWeightText: String = ""
    @State private var editRestText: String = ""
    @State private var dragOffsetY: CGFloat = 0
    @State private var isTransitioningExercise: Bool = false
    @State private var currentSetIndexByExercise: [Int: Int] = [:]
    @State private var remainingRestByExercise: [Int: Int] = [:]
    @State private var isRestingByExercise: [Int: Bool] = [:]
    @State private var toastMessage: String? = nil
    @State private var restAudioPlayer: AVAudioPlayer? = nil
    @State private var didFireRestFinishedFeedback: Bool = false
    @State private var beepWorkItem: DispatchWorkItem? = nil
    @State private var isBeeping: Bool = false
    private let swipeThreshold: CGFloat = 110
    private let restTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    private var orderedExercises: [ExerciseRow] {
        exercises.sorted { $0.order_index < $1.order_index }
    }
    
    private var currentExercise: ExerciseRow? {
        guard !orderedExercises.isEmpty,
              currentExerciseIndex >= 0,
              currentExerciseIndex < orderedExercises.count
        else { return nil }
        return orderedExercises[currentExerciseIndex]
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
                    } else if currentExercise != nil {
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
                        withAnimation(.easeInOut) {
                            showCountdown = false
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.ultraThinMaterial)
                    .transition(.opacity.combined(with: .scale))
                    .zIndex(1)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
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
            guard isResting else { return }
            guard let end = restEndDate else {
                isResting = false
                remainingRest = 0
                if let ex = currentExercise {
                    isRestingByExercise[ex.id] = false
                    remainingRestByExercise[ex.id] = 0
                    restEndDateByExercise[ex.id] = nil
                }
                return
            }

            let newRemaining = max(0, Int(ceil(end.timeIntervalSinceNow)))
            if newRemaining != remainingRest {
                remainingRest = newRemaining
            }

            if remainingRest <= 0 {
                isResting = false
                remainingRest = 0
                restEndDate = nil
                if !didFireRestFinishedFeedback {
                    didFireRestFinishedFeedback = true
                    restFinishedFeedback()
                }
            }

            if let ex = currentExercise {
                isRestingByExercise[ex.id] = isResting
                remainingRestByExercise[ex.id] = remainingRest
                if let end = restEndDate {
                    restEndDateByExercise[ex.id] = end
                }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            syncRestCountdownFromEndDate()
        }
        .task { await load() }
        .onDisappear {
            Task { await sanitizeEndDateIfNeededOnClose() }
        }
    }
    
    @ViewBuilder
    private func exerciseContent(_ ex: ExerciseRow, isActive: Bool) -> some View {
        let sets = setsFor(ex)
        let totalSets = sets.count
        let plannedSets = totalSets
        let effectiveSetIndex = isActive ? currentSetIndex : 0
        let currentSet = currentSetFor(ex, setIndex: effectiveSetIndex)
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
    
    private func currentSetFor(_ ex: ExerciseRow, setIndex: Int) -> SetRow? {
        let sets = setsFor(ex)
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
        currentSet: SetRow?,
        totalSets: Int,
        plannedSets: Int,
        allSetsDone: Bool,
        isExtraCurrentSet: Bool,
        displaySetIndex: Int
    ) -> some View {

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
        
        let isActiveExercise = (currentExercise?.id == ex.id)
        let lockRestActions = isResting && isActiveExercise && !allSetsDone

        if isActiveExercise, let s = currentSet, (s.rest_sec ?? 0) > 0 {
            VStack(spacing: 12) {
                if isResting {
                    Text("Rest")
                        .font(.headline)
                    Text("\(remainingRest)s")
                        .font(.system(size: 36, weight: .bold, design: .rounded))

                    Button("Skip rest") {
                        isResting = false
                        remainingRest = 0
                        restEndDate = nil
                        didFireRestFinishedFeedback = false
                        if let ex = currentExercise {
                            isRestingByExercise[ex.id] = false
                            remainingRestByExercise[ex.id] = 0
                            restEndDateByExercise[ex.id] = nil
                        }
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button {
                        completeCurrentSet()
                        startRest(for: s)
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
        
        if allSetsDone && isActiveExercise && isResting && remainingRest > 0 {
            VStack(spacing: 12) {
                Text("Rest")
                    .font(.headline)
                Text("\(remainingRest)s")
                    .font(.system(size: 36, weight: .bold, design: .rounded))

                Button("Skip rest") {
                    isResting = false
                    remainingRest = 0
                    restEndDate = nil
                    didFireRestFinishedFeedback = false
                    isRestingByExercise[ex.id] = false
                    remainingRestByExercise[ex.id] = 0
                    restEndDateByExercise[ex.id] = nil
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity)
        }
        
        VStack(spacing: 10) {
            Button {
                ensureBaseSetExists(for: ex)
                addOneSetToConfigs(for: ex)
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
                removeOneSet(for: ex)
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
            .disabled(isResting || isSaving || (isActiveExercise && allSetsDone) || !canRemoveAnySet(for: ex))
            .opacity((isResting || isSaving || (isActiveExercise && allSetsDone) || !canRemoveAnySet(for: ex)) ? 0.45 : 1)
        }
        
        if allSetsDone {
            VStack(spacing: 12) {
                if nextExercise != nil {
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
                        Task { await saveAndFinishWorkout() }
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
        if nextExercise == nil && !allSetsDone {
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
                Text("You haven't completed all planned sets. The workout will be saved with only the sets you actually performed.")
            }
        }
    }
            
    private func setsFor(_ ex: ExerciseRow) -> [SetRow] {
        let configs = setsByExercise[ex.id] ?? []
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
    
    private func currentSetFor(_ ex: ExerciseRow) -> SetRow? {
        currentSetFor(ex, setIndex: currentSetIndex)
    }
    
    private func startRest(for set: SetRow) {
        let sec = set.rest_sec ?? 0
        guard sec > 0 else { return }

        let end = Date().addingTimeInterval(TimeInterval(sec))
        restEndDate = end

        remainingRest = sec
        isResting = true
        didFireRestFinishedFeedback = false

        if let ex = currentExercise {
            isRestingByExercise[ex.id] = true
            remainingRestByExercise[ex.id] = sec
            restEndDateByExercise[ex.id] = end
        }
    }
    
    private func syncRestCountdownFromEndDate() {
        guard isResting else { return }
        guard let end = restEndDate else { return }

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
        } else {
            if let ex = currentExercise {
                isRestingByExercise[ex.id] = true
                remainingRestByExercise[ex.id] = remainingRest
                restEndDateByExercise[ex.id] = end
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
    
    private func completeCurrentSet() {
        guard let ex = currentExercise else { return }
        var sets = setsFor(ex)
        if sets.isEmpty {
            ensureBaseSetExists(for: ex)
            sets = setsFor(ex)
            if sets.isEmpty { return }
        }
        
        if let s = currentSetFor(ex) {
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
    }
    
    private func addOneSetToConfigs(for ex: ExerciseRow) {
        let key = ex.id
        var configs = setsByExercise[key] ?? []

        if configs.isEmpty {
            ensureBaseSetExists(for: ex)
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

        let total = setsFor(ex).count
        if currentExercise?.id == key, currentSetIndex >= total {
            currentSetIndex = max(0, total - 1)
        }
        currentSetIndexByExercise[key] = (currentExercise?.id == key) ? currentSetIndex : (currentSetIndexByExercise[key] ?? 0)
    }
    
    private func ensureBaseSetExists(for ex: ExerciseRow) {
        let key = ex.id
        let planned = setsFor(ex).count
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
        setsByExercise[key] = [base]
    }
    
    private func canRemoveAnySet(for ex: ExerciseRow) -> Bool {
        _ = ex.id
        let total = setsFor(ex).count
        return total > 0
    }

    private func removeOneSet(for ex: ExerciseRow) {
        let key = ex.id

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

        let totalNow = setsFor(ex).count

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
    }
    
    private func goToNextExercise() {
        let ordered = orderedExercises
        guard !ordered.isEmpty else { return }
        guard currentExerciseIndex < ordered.count - 1 else { return }

        persistStateForCurrentExercise()

        currentExerciseIndex += 1

        if let ex = currentExercise {
            restoreStateForExercise(ex)
        } else {
            currentSetIndex = 0
            isResting = false
            remainingRest = 0
        }
    }
    
    private func goToPreviousExercise() {
        let ordered = orderedExercises
        guard !ordered.isEmpty else { return }
        guard currentExerciseIndex > 0 else { return }

        persistStateForCurrentExercise()

        currentExerciseIndex -= 1

        if let ex = currentExercise {
            restoreStateForExercise(ex)
        } else {
            currentSetIndex = 0
            isResting = false
            remainingRest = 0
        }
    }

    private func canSwipeBetweenExercises() -> Bool {
        if showCountdown { return false }
        if isSaving { return false }
        if showEditSheet { return false }
        if isTransitioningExercise { return false }

        if isResting {
            guard let ex = currentExercise else { return false }
            let total = setsFor(ex).count
            let isDone = (total > 0 && currentSetFor(ex, setIndex: currentSetIndex) == nil)
            if !isDone { return false }
        }

        return true
    }
    
    private func canGoNextExercise() -> Bool {
        currentExerciseIndex < orderedExercises.count - 1
    }

    private func canGoPreviousExercise() -> Bool {
        currentExerciseIndex > 0
    }
    
    private func persistStateForCurrentExercise() {
        guard let ex = currentExercise else { return }
        currentSetIndexByExercise[ex.id] = currentSetIndex
        isRestingByExercise[ex.id] = isResting
        remainingRestByExercise[ex.id] = remainingRest
        if let end = restEndDate {
            restEndDateByExercise[ex.id] = end
        } else {
            restEndDateByExercise[ex.id] = nil
        }
    }

    private func restoreStateForExercise(_ ex: ExerciseRow) {
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
    }

    private func exerciseTitle(_ ex: ExerciseRow?) -> String {
        guard let ex else { return "" }
        if let custom = ex.custom_name, !custom.isEmpty { return custom }
        return ex.exercise_name ?? "Exercise"
    }
    
    @ViewBuilder
    private func exercisePager() -> some View {
        GeometryReader { geo in
            let h = geo.size.height
            let cardHeight = h * 0.68
            let peekHeight: CGFloat = 86
            let peekGap: CGFloat = 14
            let step = cardHeight * 0.86
            let localThreshold = max(70, step * 0.35)
            let peekOffset = (cardHeight / 2) + (peekHeight / 2) + peekGap
            let needed = cardHeight + 2 * (peekHeight + peekGap)
            let verticalInset = max(0, (h - needed) / 2)

            ZStack {
                if let prev = previousExercise {
                    exercisePeekCard(prev, edge: .bottom)
                        .frame(height: peekHeight)
                        .offset(y: -peekOffset + dragOffsetY * 0.25)
                        .opacity(0.55)
                        .blur(radius: 6)
                        .scaleEffect(0.96)
                        .allowsHitTesting(false)
                }

                if let cur = currentExercise {
                    exerciseContent(cur, isActive: true)
                        .frame(height: cardHeight)
                        .offset(y: dragOffsetY)
                        .allowsHitTesting(true)
                }

                if let next = nextExercise {
                    exercisePeekCard(next, edge: .top)
                        .frame(height: peekHeight)
                        .offset(y: peekOffset + dragOffsetY * 0.25)
                        .opacity(0.55)
                        .blur(radius: 6)
                        .scaleEffect(0.96)
                        .allowsHitTesting(false)
                }
            }
            .padding(.vertical, verticalInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
    }
    
    private func saveAndFinishWorkout() async {
        var exList: [ExerciseRow] = []
        var performedMap: [Int: [PerformedSet]] = [:]
        
        await MainActor.run {
            exList = self.orderedExercises
            performedMap = self.performedSetsByExercise
            self.isSaving = true
        }
        
        let client = SupabaseManager.shared.client
        
        do {
            for ex in exList {
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
            
            _ = try await client
                .from("workouts")
                .update(WorkoutEndPatch(ended_at: Date()))
                .eq("id", value: workoutId)
                .execute()

            NotificationCenter.default.post(name: .workoutDidChange, object: workoutId)
            
            await MainActor.run {
                self.isSaving = false
                dismiss()
            }
        } catch {
            await MainActor.run {
                self.isSaving = false
                self.error = error.localizedDescription
            }
        }
    }

    private func sanitizeEndDateIfNeededOnClose() async {
        let saving = await MainActor.run { isSaving }
        if saving { return }

        do {
            struct WorkoutDates: Decodable {
                let started_at: Date?
                let ended_at: Date?
            }

            let res = try await SupabaseManager.shared.client
                .from("workouts")
                .select("started_at, ended_at")
                .eq("id", value: workoutId)
                .limit(1)
                .execute()

            let arr = try JSONDecoder.supabase().decode([WorkoutDates].self, from: res.data)
            guard let w = arr.first else { return }

            guard let start = w.started_at else { return }

            if let end = w.ended_at, end < start {
                _ = try await SupabaseManager.shared.client
                    .from("workouts")
                    .update(WorkoutSanitizePatch(ended_at: nil))
                    .eq("id", value: workoutId)
                    .execute()

                NotificationCenter.default.post(name: .workoutDidChange, object: workoutId)
            }
        } catch {
        }
    }
    
    private func configIndexForSetIndex(_ ex: ExerciseRow, setIndex: Int) -> Int? {
        let configs = (setsByExercise[ex.id] ?? []).sorted { $0.id < $1.id }
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
        guard let ex = currentExercise else { return }
        
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
        
        var configs = (setsByExercise[ex.id] ?? []).sorted { $0.id < $1.id }
        guard !configs.isEmpty else { return }

        let idx = configIndexForSetIndex(ex, setIndex: currentSetIndex) ?? 0
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
        setsByExercise[ex.id] = configs
    }
    
    private func load() async {
        loading = true
        defer { loading = false }
        
        do {
            let exQ = try await SupabaseManager.shared.client
                .from("workout_exercises")
                .select("id, exercise_id, order_index, notes, custom_name, exercises(name)")
                .eq("workout_id", value: workoutId)
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
            
            await MainActor.run {
                self.exercises = exRows
                self.setsByExercise = byEx
                self.error = nil

                self.currentExerciseIndex = 0
                self.currentSetIndex = 0

                self.isResting = false
                self.remainingRest = 0
            }
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
