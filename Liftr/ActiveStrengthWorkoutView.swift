import SwiftUI
import Supabase

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
    
    @Environment(\.dismiss) private var dismiss
    
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
    @State private var extraSetsByExercise: [Int: Int] = [:]
    @State private var performedSetsByExercise: [Int: [PerformedSet]] = [:]
    @State private var showEditSheet = false
    @State private var editRepsText: String = ""
    @State private var editWeightText: String = ""
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
                    } else if let ex = currentExercise {
                        exerciseContent(ex)
                    } else {
                        VStack(spacing: 12) {
                            Text("No exercises found")
                                .font(.headline)
                            Button("Close") { dismiss() }
                        }
                        .padding()
                    }
                }
                .padding(16)
                
                if isSaving {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                    ProgressView("Saving workout…")
                        .padding(24)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
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
                Text("Edit reps & weight")
                    .font(.title3.weight(.semibold))
                
                TextField("Reps", text: $editRepsText)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                
                TextField("Weight (kg)", text: $editWeightText)
                    .keyboardType(.decimalPad)
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
            guard isResting, remainingRest > 0 else { return }
            remainingRest -= 1
            if remainingRest <= 0 {
                isResting = false
            }
        }
        .task { await load() }
    }
    
    @ViewBuilder
    private func exerciseContent(_ ex: ExerciseRow) -> some View {
        let sets = setsFor(ex)
        let plannedSets = sets.count
        let extraSets = extraSetsByExercise[ex.id] ?? 0
        let totalSets = plannedSets + extraSets
        let currentSet = currentSetFor(ex)
        let allSetsDone = (totalSets > 0 && currentSet == nil)
        let isExtraCurrentSet = (currentSetIndex + 1) > plannedSets
        
        VStack(spacing: 24) {
            Spacer()
            
            if let previous = previousExercise {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Previous:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Text(previous.custom_name?.isEmpty == false
                         ? previous.custom_name!
                         : (previous.exercise_name ?? "Exercise"))
                        .font(.subheadline.weight(.semibold))
                    
                    let prevSets = setsFor(previous)
                    if let firstPrev = prevSets.first {
                        Text("\(firstPrev.reps ?? 0) reps • \(weightStr(firstPrev.weight_kg))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                .blur(radius: 3)
                .opacity(0.8)
            }
            
            VStack(spacing: 8) {
                Text(ex.custom_name?.isEmpty == false
                     ? ex.custom_name!
                     : (ex.exercise_name ?? "Exercise"))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                
                if let notes = ex.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
            
            if let s = currentSet {
                VStack(spacing: 12) {
                    Text("Set \(currentSetIndex + 1) of \(totalSets)")
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
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
                
                Button {
                    editRepsText = "\(s.reps ?? 0)"
                    if let w = s.weight_kg {
                        editWeightText = String(
                            format: "%.1f",
                            NSDecimalNumber(decimal: w).doubleValue
                        )
                    } else {
                        editWeightText = ""
                    }
                    showEditSheet = true
                } label: {
                    Text("Edit reps & weight")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
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
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
            } else {
                Text("No sets configured.")
                    .foregroundStyle(.secondary)
            }
            
            if let s = currentSet, (s.rest_sec ?? 0) > 0 {
                VStack(spacing: 12) {
                    if isResting {
                        Text("Rest")
                            .font(.headline)
                        Text("\(remainingRest)s")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                        
                        Button("Skip rest") {
                            isResting = false
                            remainingRest = 0
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
            
            if allSetsDone {
                VStack(spacing: 12) {
                    Button {
                        if let ex = currentExercise {
                            addExtraSet(for: ex)
                        }
                    } label: {
                        Text("Add another set")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Color.accentColor, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    
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
                            Task {
                                await saveAndFinishWorkout()
                            }
                        } label: {
                            HStack(spacing: 8) {
                                if isSaving {
                                    ProgressView()
                                        .progressViewStyle(.circular)
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
            
            if let next = nextExercise {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Next:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(next.custom_name?.isEmpty == false
                         ? next.custom_name!
                         : (next.exercise_name ?? "Exercise"))
                        .font(.subheadline.weight(.semibold))
                    
                    let nextSets = setsFor(next)
                    if let firstSet = nextSets.first {
                        Text("\(firstSet.reps ?? 0) reps • \(weightStr(firstSet.weight_kg))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                .blur(radius: 3)
                .opacity(0.8)
            }
            
            Spacer()
        }
    }
        
    private func setsFor(_ ex: ExerciseRow) -> [SetRow] {
        let configs = setsByExercise[ex.id] ?? []
        var expanded: [SetRow] = []
        
        let orderedConfigs = configs.sorted { $0.id < $1.id }
        
        for config in orderedConfigs {
            let count = max(config.set_number, 1)
            
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
        let sets = setsFor(ex)
        let plannedSets = sets.count
        let extraSets = extraSetsByExercise[ex.id] ?? 0
        let totalSets = plannedSets + extraSets
        
        guard totalSets > 0,
              currentSetIndex >= 0,
              currentSetIndex < totalSets
        else { return nil }
        
        if currentSetIndex < plannedSets {
            return sets[currentSetIndex]
        }
        
        guard let last = sets.last else { return nil }
        let sequentialNumber = currentSetIndex + 1
        
        return SetRow(
            id: last.id * 1000 + sequentialNumber,
            workout_exercise_id: last.workout_exercise_id,
            set_number: sequentialNumber,
            reps: last.reps,
            weight_kg: last.weight_kg,
            rpe: last.rpe,
            rest_sec: last.rest_sec
        )
    }
    
    private func startRest(for set: SetRow) {
        let sec = set.rest_sec ?? 0
        guard sec > 0 else { return }
        remainingRest = sec
        isResting = true
    }
    
    private func completeCurrentSet() {
        guard let ex = currentExercise else { return }
        let sets = setsFor(ex)
        guard !sets.isEmpty else { return }
        
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
        
        let plannedSets = sets.count
        let extraSets = extraSetsByExercise[ex.id] ?? 0
        let totalSets = plannedSets + extraSets
        
        if currentSetIndex < totalSets - 1 {
            currentSetIndex += 1
        } else {
            currentSetIndex = totalSets
        }
        
        isResting = false
        remainingRest = 0
    }
    
    private func addExtraSet(for ex: ExerciseRow) {
        let key = ex.id
        let currentExtra = extraSetsByExercise[key] ?? 0
        extraSetsByExercise[key] = currentExtra + 1
        
        let plannedSets = setsFor(ex).count
        let newTotal = plannedSets + currentExtra + 1
        
        currentSetIndex = newTotal - 1
        isResting = false
        remainingRest = 0
    }
    
    private func goToNextExercise() {
        let ordered = orderedExercises
        guard !ordered.isEmpty else { return }
        
        if currentExerciseIndex < ordered.count - 1 {
            currentExerciseIndex += 1
            currentSetIndex = 0
            isResting = false
            remainingRest = 0
        } else {
            dismiss()
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
                guard !performedSets.isEmpty else { continue }
                
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
        
        var configs = setsByExercise[ex.id] ?? []
        guard !configs.isEmpty else { return }
        
        let old = configs[0]
        let updated = SetRow(
            id: old.id,
            workout_exercise_id: old.workout_exercise_id,
            set_number: old.set_number,
            reps: newReps ?? old.reps,
            weight_kg: newWeightDecimal ?? old.weight_kg,
            rpe: old.rpe,
            rest_sec: old.rest_sec
        )
        
        configs[0] = updated
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
}
