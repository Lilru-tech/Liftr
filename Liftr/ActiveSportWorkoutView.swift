import SwiftUI
import Supabase

struct ActiveSportWorkoutView: View {
    let workoutId: Int
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var app: AppState
    @State private var showCountdown = true
    @State private var isRunning = false
    @State private var elapsedSec: Int = 0
    @State private var remainingSec: Int = 0
    @State private var initialTargetSec: Int = 0
    @State private var hasTargetTime: Bool = false
    @State private var mode: TimerMode = .stopwatch
    @State private var sportRow: SportRow?
    @State private var sportType: SportType = .padel
    @State private var isSaving = false
    @State private var sportForm = SportForm()
    @State private var error: String?
    @State private var detailsTab: DetailsTab = .summary
    @State private var hyroxExercises: [ActiveHyroxExercise] = []
    @State private var currentHyroxExerciseIndex: Int = 0
    @State private var activeHyroxExerciseId: Int?
    @State private var completedHyroxExerciseIds: Set<Int> = []
    @State private var hyroxDragOffsetY: CGFloat = 0
    @State private var hyroxZoneScrollContentBottom: CGFloat = 0
    @State private var hyroxZoneScrollViewportHeight: CGFloat = 0
    @State private var hyroxZoneScrollCanScrollDown = false
    @State private var showEditHyroxExerciseSheet = false
    @State private var isAddingHyroxExercise = false
    @State private var showDeleteHyroxExerciseConfirm = false
    @State private var deleteHyroxExerciseId: Int?
    @State private var nextTempHyroxExerciseId = -1
    @State private var editHyroxExerciseId: Int?
    @State private var editHyroxExerciseCode = HyroxExerciseCode.run.rawValue
    @State private var editHyroxCustomDisplayName = ""
    @State private var editHyroxDistanceM = ""
    @State private var editHyroxReps = ""
    @State private var editHyroxWeightKg = ""
    @State private var editHyroxDurationSec = ""
    @State private var editHyroxHeightCm = ""
    @State private var editHyroxImplementCount = ""
    @State private var editHyroxNotes = ""
    @State private var didLoadEditHyroxCustomDisplayNameSuggestions = false
    @State private var editHyroxCustomDisplayNameSuggestionsFromDB: [String] = []
    @FocusState private var editHyroxNameFocused: Bool
    
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    private struct SportRow: Decodable {
        var id: Int
        let sport: String
        let duration_sec: Int?
        let score_for: Int?
        let score_against: Int?
        let match_result: String?
        let match_score_text: String?
        let location: String?
        let notes: String?
    }

    private struct WorkoutStateRow: Decodable {
        let state: String?
    }

    private struct WorkoutFinishPatch: Encodable {
        let ended_at: Date
        let state: String?
    }
    
    private struct ActiveHyroxExercise: Identifiable, Decodable {
        let id: Int
        var exercise_code: String
        var exercise_order: Int
        var zone_order: Int?
        var distance_m: Int?
        var reps: Int?
        var weight_kg: Decimal?
        var duration_sec: Int?
        var height_cm: Int?
        var implement_count: Int?
        var notes: String?
        var exercise_display_name: String?

        var displayName: String {
            HyroxExerciseFormatting.label(code: exercise_code, displayName: exercise_display_name, notes: notes)
        }
    }
    
    private enum TimerMode {
        case stopwatch
        case countdown
    }

    private enum DetailsTab: String, CaseIterable, Identifiable {
        case summary
        case stats
        
        var id: String { rawValue }
        
        var label: String {
            switch self {
            case .summary: return "Summary"
            case .stats:   return "Stats"
            }
        }
    }

    private struct ActiveHyroxDisplayGroup: Identifiable {
        let id: String
        let zoneOrder: Int?
        let exercises: [ActiveHyroxExercise]

        var isZone: Bool {
            zoneOrder != nil && exercises.count > 1
        }
    }

    private struct HyroxZoneScrollContentBottomPreferenceKey: PreferenceKey {
        static var defaultValue: CGFloat = 0

        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = nextValue()
        }
    }

    private struct HyroxZoneScrollViewportHeightPreferenceKey: PreferenceKey {
        static var defaultValue: CGFloat = 0

        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = nextValue()
        }
    }
    
    private var orderedHyroxExercises: [ActiveHyroxExercise] {
        hyroxExercises.sorted { $0.exercise_order < $1.exercise_order }
    }

    private var hyroxDisplayGroups: [ActiveHyroxDisplayGroup] {
        var groups: [ActiveHyroxDisplayGroup] = []
        let ordered = orderedHyroxExercises
        var index = 0
        while ordered.indices.contains(index) {
            let ex = ordered[index]
            guard let zoneOrder = ex.zone_order else {
                groups.append(ActiveHyroxDisplayGroup(id: "exercise-\(ex.id)", zoneOrder: nil, exercises: [ex]))
                index += 1
                continue
            }

            var zoneExercises: [ActiveHyroxExercise] = [ex]
            var nextIndex = index + 1
            while ordered.indices.contains(nextIndex), ordered[nextIndex].zone_order == zoneOrder {
                zoneExercises.append(ordered[nextIndex])
                nextIndex += 1
            }

            groups.append(
                ActiveHyroxDisplayGroup(
                    id: "zone-\(zoneOrder)-\(zoneExercises.map(\.id).map(String.init).joined(separator: "-"))",
                    zoneOrder: zoneOrder,
                    exercises: zoneExercises
                )
            )
            index = nextIndex
        }
        return groups
    }

    private var currentHyroxDisplayGroup: ActiveHyroxDisplayGroup? {
        guard hyroxDisplayGroups.indices.contains(currentHyroxExerciseIndex) else { return nil }
        return hyroxDisplayGroups[currentHyroxExerciseIndex]
    }

    private var currentHyroxExercise: ActiveHyroxExercise? {
        guard let group = currentHyroxDisplayGroup else { return nil }
        if let activeHyroxExerciseId,
           let selected = group.exercises.first(where: { $0.id == activeHyroxExerciseId }) {
            return selected
        }
        return group.exercises.first
    }

    private var nextHyroxDisplayGroup: ActiveHyroxDisplayGroup? {
        let nextIndex = currentHyroxExerciseIndex + 1
        guard hyroxDisplayGroups.indices.contains(nextIndex) else { return nil }
        return hyroxDisplayGroups[nextIndex]
    }

    private var previousHyroxDisplayGroup: ActiveHyroxDisplayGroup? {
        let prevIndex = currentHyroxExerciseIndex - 1
        guard hyroxDisplayGroups.indices.contains(prevIndex) else { return nil }
        return hyroxDisplayGroups[prevIndex]
    }

    private var orderedHyroxExercisePairs: [(offset: Int, element: ActiveHyroxExercise)] {
        Array(orderedHyroxExercises.enumerated())
    }

    private var canShowHyroxNextCTA: Bool {
        currentHyroxDisplayGroup != nil && nextHyroxDisplayGroup != nil
    }

    private var canShowHyroxFinishCTA: Bool {
        guard nextHyroxDisplayGroup == nil, let group = currentHyroxDisplayGroup else { return false }
        return group.isZone || isCurrentHyroxExerciseLastInGroup
    }

    private var isCurrentHyroxExerciseLastInGroup: Bool {
        guard let group = currentHyroxDisplayGroup,
              let currentHyroxExercise,
              let last = group.exercises.last
        else { return false }
        return currentHyroxExercise.id == last.id
    }

    private var currentHyroxExerciseGlobalIndex: Int? {
        guard let currentHyroxExercise else { return nil }
        return orderedHyroxExercises.firstIndex(where: { $0.id == currentHyroxExercise.id })
    }
    
    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Color.clear
                    .gradientBG()
                    .ignoresSafeArea()
                if sportType == .hyrox {
                    hyroxExercisePagerSection
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, app.isPremium ? 140 : 200)
                } else {
                    ScrollView {
                        VStack(spacing: 24) {
                            if let row = sportRow {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(sportType.label)
                                        .font(.title2.weight(.bold))

                                    if let secs = row.duration_sec, secs > 0 {
                                        let mins = max(1, secs / 60)
                                        Text("Target \(mins) min")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            } else {
                                Text("Active sport session")
                                    .font(.title2.weight(.bold))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            if hasTargetTime {
                                Picker("", selection: $mode) {
                                    Text("Target time").tag(TimerMode.countdown)
                                    Text("Free timer").tag(TimerMode.stopwatch)
                                }
                                .pickerStyle(.segmented)
                                .onChange(of: mode) { _, newMode in
                                    isRunning = false
                                    elapsedSec = 0
                                    if newMode == .countdown && hasTargetTime {
                                        remainingSec = initialTargetSec
                                    }
                                }
                            }

                            VStack(spacing: 8) {
                                Text(formatTime(mode == .countdown ? remainingSec : elapsedSec))
                                    .font(.system(size: 40, weight: .bold, design: .rounded))
                                    .monospacedDigit()
                                Text(mode == .countdown ? "Time left" : "Elapsed time")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(24)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
                            .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.15)))

                            statsOrSummarySection
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, app.isPremium ? 140 : 200)
                    }
                }
                VStack {
                    Spacer()
                    if !showCountdown, sportType != .hyrox {
                        VStack(spacing: 8) {
                            bottomControls
                            if !app.isPremium {
                                BannerAdView(adUnitID: "ca-app-pub-7676731162362384/7781347704")
                                    .frame(height: 50)
                                    .padding(.horizontal)
                            }
                        }
                    }
                }
                .padding(.bottom, 8)
                
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
                            isRunning = true
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.ultraThinMaterial)
                    .transition(.opacity.combined(with: .scale))
                    .zIndex(1)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                if sportType == .hyrox, !showCountdown {
                    ToolbarItem(placement: .topBarTrailing) {
                        HStack(spacing: 8) {
                            sportWorkoutSessionElapsedChip()
                            Button {
                                isRunning.toggle()
                            } label: {
                                Image(systemName: isRunning ? "pause.fill" : "play.fill")
                                    .font(.body.weight(.semibold))
                                    .frame(width: 36, height: 36)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.bordered)
                            .accessibilityLabel(isRunning ? "Pause workout" : "Resume workout")
                        }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !app.isPremium, !showCountdown, !isSaving, sportType == .hyrox {
                BannerAdView(adUnitID: "ca-app-pub-7676731162362384/7781347704")
                    .frame(height: 50)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }
        }
        .sheet(isPresented: $showEditHyroxExerciseSheet) {
            editHyroxExerciseSheet
        }
        .alert("Delete exercise?", isPresented: $showDeleteHyroxExerciseConfirm) {
            Button("Delete", role: .destructive) {
                deleteSelectedHyroxExercise()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the exercise from this active workout.")
        }
        .onReceive(timer) { _ in
            guard isRunning else { return }
            
            if mode == .countdown && hasTargetTime {
                if remainingSec > 0 {
                    remainingSec -= 1
                    elapsedSec += 1
                } else {
                    isRunning = false
                }
            } else {
                elapsedSec += 1
            }
        }
        .task {
            await loadSport()
        }
        .onChange(of: isRunning) { _, running in
            if running {
                WorkoutLiveActivityManager.startIfAvailable(
                    startTime: Date().addingTimeInterval(-Double(elapsedSec)),
                    kind: .sport
                )
            } else {
                WorkoutLiveActivityManager.endIfAvailable()
            }
        }
        .onDisappear {
            WorkoutLiveActivityManager.endIfAvailable()
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
    
    private var statsOrSummarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("", selection: $detailsTab) {
                ForEach(DetailsTab.allCases) { tab in
                    Text(tab.label).tag(tab)
                }
            }
            .pickerStyle(.segmented)

            Group {
                if detailsTab == .summary {
                    summaryCard
                } else {
                    statsCard
                }
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var bottomControls: some View {
        VStack(spacing: 12) {
            if sportType != .hyrox {
                HStack(spacing: 16) {
                    Button {
                        isRunning.toggle()
                    } label: {
                        Text(isRunning
                             ? "Pause"
                             : (elapsedSec == 0 ? "Start" : "Resume"))
                            .font(.headline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 42)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(Color.accentColor)
                            )
                            .foregroundColor(.white)
                    }
                    .buttonStyle(.plain)

                    Button {
                        isRunning = false
                        elapsedSec = 0
                        if mode == .countdown && hasTargetTime {
                            remainingSec = initialTargetSec
                        } else {
                            remainingSec = 0
                        }
                    } label: {
                        Text("Reset")
                            .font(.subheadline.weight(.semibold))
                            .frame(width: 90, height: 40)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.gray.opacity(0.40))
                            )
                            .foregroundColor(.primary)
                    }
                    .buttonStyle(.plain)
                    .disabled(isRunning || elapsedSec == 0)
                }
            }
            
            Button {
                Task {
                    await saveAndFinishWorkout()
                }
            } label: {
                Text("Finish workout")
                    .font(.headline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 49)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.green.gradient)
                    )
                    .foregroundColor(.white)
            }
            .buttonStyle(.plain)
            .disabled(isSaving || elapsedSec == 0)
            
            if let error {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private func sportWorkoutSessionElapsedChip() -> some View {
        HStack(spacing: 5) {
            Image(systemName: "stopwatch")
                .font(.caption.weight(.semibold))
                .accessibilityHidden(true)
            Text(formatTime(elapsedSec))
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.18), lineWidth: 0.5))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Workout time, \(formatTime(elapsedSec))")
    }
        
    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            if sportUsesNumericScore(sportType) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Score")
                        .font(.subheadline.weight(.semibold))
                    HStack {
                        TextField("For", text: $sportForm.scoreFor)
                            .keyboardType(.numberPad)
                        TextField("Against", text: $sportForm.scoreAgainst)
                            .keyboardType(.numberPad)
                    }
                }
            }
            
            if sportUsesSetText(sportType) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Match score")
                        .font(.subheadline.weight(.semibold))
                    TextField("e.g. 6/4 3/6 7/5", text: $sportForm.matchScoreText)
                        .textFieldStyle(.roundedBorder)
                }
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Result")
                    .font(.subheadline.weight(.semibold))
                Picker("", selection: $sportForm.matchResult) {
                    ForEach(MatchResult.allCases) {
                        Text($0.label).tag($0)
                    }
                }
                .pickerStyle(.menu)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Location")
                    .font(.subheadline.weight(.semibold))
                TextField("Location (optional)", text: $sportForm.location)
                    .textFieldStyle(.roundedBorder)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Session notes")
                    .font(.subheadline.weight(.semibold))
                TextField("Notes (optional)", text: $sportForm.sessionNotes, axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.roundedBorder)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.12)))
    }

    private var statsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            SportStatsFields(sportForm: $sportForm, sportType: sportType)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.12)))
    }

    private var hyroxExercisePagerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            hyroxExerciseBubbleNavigation
                .zIndex(2)

            if orderedHyroxExercises.isEmpty {
                hyroxEmptyActiveExerciseState
            } else {
                GeometryReader { geo in
                    let height = geo.size.height
                    let cardHeight = min(
                        max(hyroxCurrentCardEstimatedHeight, 240),
                        max(300, height * 0.88) + hyroxCurrentCardCTAExtraHeight
                    )
                    let peekHeight: CGFloat = 82
                    let peekGap: CGFloat = 12
                    let neededHeight = cardHeight + 2 * (peekHeight + peekGap)
                    let step = cardHeight * 0.82
                    hyroxExerciseCardStack(
                        cardHeight: cardHeight,
                        peekHeight: peekHeight,
                        peekOffset: (cardHeight / 2) + (peekHeight / 2) + peekGap,
                        step: step,
                        threshold: max(70, step * 0.35),
                        neededHeight: neededHeight
                    )
                    .frame(height: neededHeight)
                    .frame(maxWidth: .infinity)
                    .position(x: geo.size.width / 2, y: height / 2)
                }
                .zIndex(1)
            }
        }
    }

    private var hyroxEmptyActiveExerciseState: some View {
        VStack(spacing: 14) {
            Text("No exercises planned")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button {
                beginAddingHyroxExercise()
            } label: {
                Label("Add exercise", systemImage: "plus.circle.fill")
                    .font(.headline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.14), lineWidth: 1))
    }

    @ViewBuilder
    private func hyroxExerciseCardStack(
        cardHeight: CGFloat,
        peekHeight: CGFloat,
        peekOffset: CGFloat,
        step: CGFloat,
        threshold: CGFloat,
        neededHeight: CGFloat
    ) -> some View {
        let canSwipeCards = currentHyroxDisplayGroup?.isZone != true
        ZStack {
            if let prev = previousHyroxDisplayGroup {
                hyroxExercisePeekCard(prev, label: "Previous exercise")
                    .frame(height: peekHeight)
                    .offset(y: -peekOffset + hyroxDragOffsetY * 0.25)
                    .opacity(0.55)
                    .blur(radius: 6)
                    .scaleEffect(0.96)
                    .allowsHitTesting(false)
            }

            if let group = currentHyroxDisplayGroup {
                hyroxExerciseCard(group)
                    .frame(height: cardHeight)
                    .offset(y: hyroxDragOffsetY)
            }

            if let next = nextHyroxDisplayGroup {
                hyroxExercisePeekCard(next, label: "Next exercise")
                    .frame(height: peekHeight)
                    .offset(y: peekOffset + hyroxDragOffsetY * 0.25)
                    .opacity(0.55)
                    .blur(radius: 6)
                    .scaleEffect(0.96)
                    .allowsHitTesting(false)
            }
        }
        .frame(height: neededHeight)
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture()
                .onChanged { value in
                    guard canSwipeCards, orderedHyroxExercises.count > 1 else { return }
                    hyroxDragOffsetY = max(-step, min(step, value.translation.height))
                }
                .onEnded { value in
                    guard canSwipeCards, orderedHyroxExercises.count > 1 else {
                        hyroxDragOffsetY = 0
                        return
                    }
                    if value.translation.height <= -threshold, nextHyroxDisplayGroup != nil {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
                            hyroxDragOffsetY = -step
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                            shiftHyroxExercise(by: 1)
                            hyroxDragOffsetY = 0
                        }
                    } else if value.translation.height >= threshold, previousHyroxDisplayGroup != nil {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
                            hyroxDragOffsetY = step
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                            shiftHyroxExercise(by: -1)
                            hyroxDragOffsetY = 0
                        }
                    } else {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
                            hyroxDragOffsetY = 0
                        }
                    }
                }
        )
    }

    private var hyroxCurrentCardEstimatedHeight: CGFloat {
        guard let group = currentHyroxDisplayGroup else { return 280 }
        let metricsRows = group.exercises.reduce(0) { partial, ex in
            partial + max(1, hyroxMetricCount(for: ex) / 2 + hyroxMetricCount(for: ex) % 2)
        }
        if group.isZone {
            return CGFloat(210 + group.exercises.count * 92 + metricsRows * 48) + hyroxCurrentCardCTAExtraHeight
        }
        return CGFloat(154 + metricsRows * 56) + hyroxCurrentCardCTAExtraHeight
    }

    private var hyroxCurrentCardCTAExtraHeight: CGFloat {
        (canShowHyroxNextCTA || canShowHyroxFinishCTA) ? 66 : 0
    }

    private func hyroxExercisePeekCard(_ group: ActiveHyroxDisplayGroup, label: String) -> some View {
        VStack(spacing: 8) {
            Text(hyroxGroupTitle(group))
                .font(.headline.weight(.semibold))
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.10), lineWidth: 1))
    }

    private func hyroxGroupTitle(_ group: ActiveHyroxDisplayGroup) -> String {
        if group.isZone, let zoneOrder = group.zoneOrder {
            return "Zone \(max(1, zoneOrder))"
        }
        return group.exercises.first?.displayName ?? "Exercise"
    }

    private func hyroxGroupSubtitle(_ group: ActiveHyroxDisplayGroup) -> String {
        guard group.exercises.count > 1 else {
            let current = (currentHyroxExerciseGlobalIndex ?? 0) + 1
            return "Exercise \(current) of \(max(1, orderedHyroxExercises.count))"
        }
        return "\(group.exercises.count) exercises"
    }

    private func hyroxMetricCount(for ex: ActiveHyroxExercise) -> Int {
        var count = 0
        if ex.distance_m != nil { count += 1 }
        if ex.reps != nil { count += 1 }
        if ex.weight_kg != nil { count += 1 }
        if ex.duration_sec != nil { count += 1 }
        if ex.height_cm != nil { count += 1 }
        if ex.implement_count != nil { count += 1 }
        if ex.notes?.trimmedOrNil != nil { count += 1 }
        return count
    }

    @ViewBuilder
    private func hyroxMetricGridValues(_ ex: ActiveHyroxExercise) -> some View {
        if let distance = ex.distance_m {
            hyroxExerciseMainValue(title: "Distance", value: "\(distance) m")
        }
        if let reps = ex.reps {
            hyroxExerciseMainValue(title: "Reps", value: "\(reps)")
        }
        if let weight = ex.weight_kg {
            hyroxExerciseMainValue(
                title: "Weight",
                value: String(format: "%.1f kg", NSDecimalNumber(decimal: weight).doubleValue)
            )
        }
        if let duration = ex.duration_sec {
            hyroxExerciseMainValue(title: "Duration", value: formatTime(duration))
        }
        if let height = ex.height_cm {
            hyroxExerciseMainValue(title: "Height", value: "\(height) cm")
        }
        if let implements = ex.implement_count {
            hyroxExerciseMainValue(title: "Implements", value: "\(implements)")
        }
        if let notes = ex.notes, !notes.isEmpty {
            hyroxExerciseMainValue(title: "Notes", value: notes)
        }
    }

    private func hyroxExerciseCard(_ group: ActiveHyroxDisplayGroup) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    if let zoneOrder = group.zoneOrder {
                        Text("Zone \(max(1, zoneOrder))")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                    Text(hyroxGroupTitle(group))
                        .font(.system(size: 27, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.leading)

                    Text(hyroxGroupSubtitle(group))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                if group.exercises.count == 1, let ex = group.exercises.first {
                    hyroxExerciseActionMenu(for: ex)
                }
            }

            if group.isZone {
                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: true) {
                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(Array(group.exercises.enumerated()), id: \.element.id) { offset, ex in
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack(alignment: .top, spacing: 10) {
                                        Text("\(offset + 1). \(ex.displayName)")
                                            .font(.headline.weight(.semibold))
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        hyroxExerciseActionMenu(for: ex)
                                    }
                                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                                        hyroxMetricGridValues(ex)
                                    }
                                }
                                .padding(.vertical, 6)
                                .padding(.horizontal, 8)
                                .contentShape(RoundedRectangle(cornerRadius: 14))
                                .onTapGesture {
                                    withAnimation(.easeInOut(duration: 0.22)) {
                                        activeHyroxExerciseId = ex.id
                                    }
                                }
                                .id(ex.id)

                                if offset < group.exercises.count - 1 {
                                    Divider().padding(.top, 2)
                                }
                            }
                        }
                        .padding(.bottom, 18)
                        .background(alignment: .bottom) {
                            GeometryReader { contentProxy in
                                Color.clear.preference(
                                    key: HyroxZoneScrollContentBottomPreferenceKey.self,
                                    value: contentProxy.frame(in: .named("hyrox-zone-scroll")).maxY
                                )
                            }
                        }
                    }
                    .frame(maxHeight: 340)
                    .coordinateSpace(name: "hyrox-zone-scroll")
                    .background {
                        GeometryReader { viewportProxy in
                            Color.clear.preference(
                                key: HyroxZoneScrollViewportHeightPreferenceKey.self,
                                value: viewportProxy.size.height
                            )
                        }
                    }
                    .overlay(alignment: .bottom) {
                        if hyroxZoneScrollCanScrollDown {
                            LinearGradient(
                                colors: [.clear, Color.black.opacity(0.16)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(height: 26)
                            .allowsHitTesting(false)
                        }
                    }
                    .onAppear {
                        if let activeHyroxExerciseId {
                            proxy.scrollTo(activeHyroxExerciseId, anchor: .center)
                        }
                        updateHyroxZoneScrollFade()
                    }
                    .onChange(of: activeHyroxExerciseId) { _, newValue in
                        guard let newValue else { return }
                        withAnimation(.easeInOut(duration: 0.24)) {
                            proxy.scrollTo(newValue, anchor: .center)
                        }
                    }
                    .onPreferenceChange(HyroxZoneScrollContentBottomPreferenceKey.self) { value in
                        hyroxZoneScrollContentBottom = value
                        updateHyroxZoneScrollFade()
                    }
                    .onPreferenceChange(HyroxZoneScrollViewportHeightPreferenceKey.self) { value in
                        hyroxZoneScrollViewportHeight = value
                        updateHyroxZoneScrollFade()
                    }
                }
            } else if let ex = group.exercises.first {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    hyroxMetricGridValues(ex)
                }
            }

            if canShowHyroxNextCTA {
                Button {
                    advanceHyroxFromNextCTA()
                } label: {
                    Text("Next")
                        .font(.headline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(RoundedRectangle(cornerRadius: 16).fill(Color.accentColor))
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)
            } else if canShowHyroxFinishCTA {
                Button {
                    if let currentHyroxDisplayGroup {
                        markHyroxGroupCompleted(currentHyroxDisplayGroup)
                    }
                    Task { await saveAndFinishWorkout() }
                } label: {
                    Text("Finish workout")
                        .font(.headline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(RoundedRectangle(cornerRadius: 16).fill(Color.green.gradient))
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)
                .disabled(isSaving)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.18), lineWidth: 1))
    }

    private func hyroxExerciseActionMenu(for ex: ActiveHyroxExercise) -> some View {
        Menu {
            Button {
                beginEditingHyroxExercise(ex)
            } label: {
                Label("Edit exercise", systemImage: "pencil")
            }
            Button(role: .destructive) {
                deleteHyroxExerciseId = ex.id
                showDeleteHyroxExerciseConfirm = true
            } label: {
                Label("Remove exercise", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3.weight(.semibold))
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.bordered)
        .accessibilityLabel("Exercise actions")
    }

    private var hyroxExerciseBubbleNavigation: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(orderedHyroxExercisePairs, id: \.element.id) { pair in
                        if let zoneOrder = pair.element.zone_order {
                            if isFirstHyroxExerciseInZone(position: pair.offset, zoneOrder: zoneOrder) {
                                HStack(spacing: 6) {
                                    ForEach(hyroxZoneExercisePairs(zoneOrder), id: \.element.id) { zonePair in
                                        hyroxExerciseBubble(index: zonePair.offset)
                                    }
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 18)
                                        .fill(Color.accentColor.opacity(0.10))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 18)
                                        .stroke(Color.accentColor.opacity(0.45), lineWidth: 1.2)
                                )
                                .accessibilityLabel("Zone \(max(1, zoneOrder))")
                            }
                        } else {
                            hyroxExerciseBubble(index: pair.offset)
                        }
                    }

                    hyroxAddExerciseBubble()
                        .id("hyrox-add-bubble")
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 4)
            }
            .onAppear {
                if let activeHyroxExerciseId {
                    proxy.scrollTo("hyrox-bubble-\(activeHyroxExerciseId)", anchor: .center)
                }
            }
            .onChange(of: activeHyroxExerciseId) { _, newValue in
                guard let newValue else { return }
                withAnimation(.easeInOut(duration: 0.28)) {
                    proxy.scrollTo("hyrox-bubble-\(newValue)", anchor: .center)
                }
            }
        }
    }

    private func hyroxAddExerciseBubble() -> some View {
        Button {
            beginAddingHyroxExercise()
        } label: {
            VStack(spacing: 4) {
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
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add exercise")
    }

    private func hyroxZoneExercisePairs(_ zoneOrder: Int) -> [(offset: Int, element: ActiveHyroxExercise)] {
        orderedHyroxExercisePairs.filter { $0.element.zone_order == zoneOrder }
    }

    private func isFirstHyroxExerciseInZone(position: Int, zoneOrder: Int) -> Bool {
        guard orderedHyroxExercisePairs.indices.contains(position) else { return false }
        guard position > 0 else { return true }
        return orderedHyroxExercisePairs[position - 1].element.zone_order != zoneOrder
    }

    @ViewBuilder
    private func hyroxExerciseBubble(index: Int) -> some View {
        if orderedHyroxExercises.indices.contains(index) {
            let ex = orderedHyroxExercises[index]
            let isCurrent = currentHyroxExercise?.id == ex.id
            let isCompleted = completedHyroxExerciseIds.contains(ex.id)
            let isFinalExercise = index == orderedHyroxExercises.count - 1
            let isFinishBubble = isFinalExercise
            Button {
                if let groupIndex = hyroxDisplayGroups.firstIndex(where: { group in
                    group.exercises.contains { $0.id == ex.id }
                }) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
                        currentHyroxExerciseIndex = groupIndex
                        activeHyroxExerciseId = ex.id
                    }
                }
            } label: {
                Text("\(index + 1)")
                    .font(isCurrent ? .callout.weight(.bold) : .caption.weight(.bold))
                    .frame(width: isCurrent ? 40 : 32, height: isCurrent ? 40 : 32)
                    .background(
                        Circle()
                            .fill(isFinishBubble ? Color.green : (isCurrent || isCompleted ? Color.accentColor : Color.primary.opacity(0.10)))
                    )
                    .foregroundStyle(isFinishBubble || isCurrent || isCompleted ? .white : .primary)
                    .overlay(
                        Circle()
                            .stroke(isCurrent ? Color.white : Color.primary.opacity(0.15), lineWidth: isCurrent ? 2 : 1)
                    )
            }
            .buttonStyle(.plain)
            .id("hyrox-bubble-\(ex.id)")
            .accessibilityLabel("Exercise \(index + 1)")
        } else {
            EmptyView()
        }
    }

    private func shiftHyroxExercise(by delta: Int) {
        let nextIndex = currentHyroxExerciseIndex + delta
        guard hyroxDisplayGroups.indices.contains(nextIndex) else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
            currentHyroxExerciseIndex = nextIndex
            activeHyroxExerciseId = hyroxDisplayGroups[nextIndex].exercises.first?.id
        }
    }

    private func advanceHyroxFromNextCTA() {
        guard let currentHyroxDisplayGroup else { return }
        guard hyroxDisplayGroups.indices.contains(currentHyroxExerciseIndex + 1) else { return }

        markHyroxGroupCompleted(currentHyroxDisplayGroup)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
            currentHyroxExerciseIndex += 1
            activeHyroxExerciseId = hyroxDisplayGroups[currentHyroxExerciseIndex].exercises.first?.id
        }
    }

    private func markHyroxGroupCompleted(_ group: ActiveHyroxDisplayGroup) {
        for ex in group.exercises {
            completedHyroxExerciseIds.insert(ex.id)
        }
    }

    private func updateHyroxZoneScrollFade() {
        let canScrollDown = hyroxZoneScrollContentBottom > hyroxZoneScrollViewportHeight + 2
        if hyroxZoneScrollCanScrollDown != canScrollDown {
            hyroxZoneScrollCanScrollDown = canScrollDown
        }
    }

    private func normalizeActiveHyroxExerciseOrdering() {
        let ordered = orderedHyroxExercises
        for (idx, ex) in ordered.enumerated() {
            guard let originalIndex = hyroxExercises.firstIndex(where: { $0.id == ex.id }) else { continue }
            hyroxExercises[originalIndex].exercise_order = idx + 1
            hyroxExercises[originalIndex].zone_order = hyroxExercises[originalIndex].zone_order.map { max(1, $0) }
        }
        currentHyroxExerciseIndex = min(max(0, currentHyroxExerciseIndex), max(0, hyroxDisplayGroups.count - 1))
        if let activeHyroxExerciseId,
           let groupIndex = hyroxDisplayGroups.firstIndex(where: { group in
               group.exercises.contains { $0.id == activeHyroxExerciseId }
           }) {
            currentHyroxExerciseIndex = groupIndex
        } else {
            activeHyroxExerciseId = currentHyroxDisplayGroup?.exercises.first?.id
        }
        completedHyroxExerciseIds = completedHyroxExerciseIds.filter { id in
            hyroxExercises.contains { $0.id == id }
        }
    }
    
    @ViewBuilder
    private func sportCardField(_ title: String, text: Binding<String>, keyboard: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField(title, text: text)
                .keyboardType(keyboard)
                .textFieldStyle(.roundedBorder)
        }
    }

    @ViewBuilder
    private func hyroxExerciseValueRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }
    
    @ViewBuilder
    private func hyroxExerciseMainValue(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)

            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var editHyroxExerciseSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("Exercise", selection: $editHyroxExerciseCode) {
                        ForEach(HyroxExerciseCode.allCases) { ex in
                            Text(ex.label).tag(ex.rawValue)
                        }
                        Text("Other").tag(HyroxExerciseFormatting.customExerciseCode)
                    }
                    .pickerStyle(.menu)

                    if HyroxExerciseCode(rawValue: editHyroxExerciseCode) == nil
                        || editHyroxExerciseCode == HyroxExerciseFormatting.customExerciseCode {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Exercise name")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextField("Exercise name", text: $editHyroxCustomDisplayName)
                                .textFieldStyle(.roundedBorder)
                                .focused($editHyroxNameFocused)
                            if editHyroxNameFocused {
                                editHyroxExerciseNameSuggestionsList
                            }
                        }
                    }

                    HStack {
                        sportCardField("Distance (m)", text: $editHyroxDistanceM, keyboard: .numberPad)
                        sportCardField("Reps", text: $editHyroxReps, keyboard: .numberPad)
                    }

                    HStack {
                        sportCardField("Weight (kg)", text: $editHyroxWeightKg, keyboard: .decimalPad)
                        sportCardField("Duration (sec)", text: $editHyroxDurationSec, keyboard: .numberPad)
                    }

                    HStack {
                        sportCardField("Height (cm)", text: $editHyroxHeightCm, keyboard: .numberPad)
                        sportCardField("Implements", text: $editHyroxImplementCount, keyboard: .numberPad)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Notes")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("Notes", text: $editHyroxNotes, axis: .vertical)
                            .lineLimit(2...6)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                .padding()
            }
            .navigationTitle(isAddingHyroxExercise ? "Add exercise" : "Edit exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isAddingHyroxExercise = false
                        showEditHyroxExerciseSheet = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isAddingHyroxExercise ? "Add" : "Save") {
                        applyHyroxExerciseEdits()
                        isAddingHyroxExercise = false
                        showEditHyroxExerciseSheet = false
                    }
                }
            }
            .background(Color.clear.gradientBG().ignoresSafeArea())
            .task {
                await loadEditHyroxCustomDisplayNameSuggestionsFromServer()
            }
        }
        .presentationDetents(isAddingHyroxExercise ? [.large] : [.medium, .large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private var editHyroxExerciseNameSuggestionsList: some View {
        let rows = filteredEditHyroxExerciseNameSuggestions()
        if !rows.isEmpty {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(rows, id: \.self) { name in
                        Button {
                            editHyroxCustomDisplayName = name
                            editHyroxNameFocused = false
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

    private func loadEditHyroxCustomDisplayNameSuggestionsFromServer() async {
        await MainActor.run {
            guard !didLoadEditHyroxCustomDisplayNameSuggestions else { return }
            didLoadEditHyroxCustomDisplayNameSuggestions = true
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
            let deduped = canonicalSortedEditHyroxDisplayNames(from: raw)
            await MainActor.run { editHyroxCustomDisplayNameSuggestionsFromDB = deduped }
        } catch {
            await MainActor.run { didLoadEditHyroxCustomDisplayNameSuggestions = false }
        }
    }

    private func filteredEditHyroxExerciseNameSuggestions() -> [String] {
        var raw = editHyroxCustomDisplayNameSuggestionsFromDB
        for ex in hyroxExercises {
            let t = (ex.exercise_display_name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty, HyroxExerciseCode(rawValue: ex.exercise_code) == nil else { continue }
            raw.append(t)
        }
        let deduped = canonicalSortedEditHyroxDisplayNames(from: raw)
        let q = editHyroxCustomDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty {
            return Array(deduped.prefix(8))
        }
        let qn = normalizedEditHyroxDisplayNameKey(q)
        let filtered = deduped.filter {
            normalizedEditHyroxDisplayNameKey($0).contains(qn) || $0.localizedStandardContains(q)
        }
        return Array(filtered.prefix(8))
    }

    private func normalizedEditHyroxDisplayNameKey(_ s: String) -> String {
        s.folding(options: .diacriticInsensitive, locale: .current).lowercased()
    }

    private func canonicalSortedEditHyroxDisplayNames(from raw: [String]) -> [String] {
        var bestByNorm: [String: String] = [:]
        for r in raw {
            let t = r.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { continue }
            let k = normalizedEditHyroxDisplayNameKey(t)
            if let existing = bestByNorm[k] {
                if t.count > existing.count { bestByNorm[k] = t }
            } else {
                bestByNorm[k] = t
            }
        }
        return bestByNorm.values.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func beginEditingHyroxExercise(_ ex: ActiveHyroxExercise) {
        let fields = HyroxExerciseFormatting.formFields(
            exerciseCode: ex.exercise_code,
            exerciseDisplayName: ex.exercise_display_name
        )
        isAddingHyroxExercise = false
        editHyroxExerciseId = ex.id
        editHyroxExerciseCode = fields.code
        editHyroxCustomDisplayName = fields.customDisplayName
        editHyroxDistanceM = ex.distance_m.map(String.init) ?? ""
        editHyroxReps = ex.reps.map(String.init) ?? ""
        editHyroxWeightKg = hyroxDecimalText(ex.weight_kg)
        editHyroxDurationSec = ex.duration_sec.map(String.init) ?? ""
        editHyroxHeightCm = ex.height_cm.map(String.init) ?? ""
        editHyroxImplementCount = ex.implement_count.map(String.init) ?? ""
        editHyroxNotes = ex.notes ?? ""
        showEditHyroxExerciseSheet = true
    }

    private func beginAddingHyroxExercise() {
        isAddingHyroxExercise = true
        editHyroxExerciseId = nil
        editHyroxExerciseCode = HyroxExerciseCode.run.rawValue
        editHyroxCustomDisplayName = ""
        editHyroxDistanceM = ""
        editHyroxReps = ""
        editHyroxWeightKg = ""
        editHyroxDurationSec = ""
        editHyroxHeightCm = ""
        editHyroxImplementCount = ""
        editHyroxNotes = ""
        showEditHyroxExerciseSheet = true
    }

    private func applyHyroxExerciseEdits() {
        let persisted = HyroxExerciseFormatting.persistedPayload(
            exerciseCode: editHyroxExerciseCode,
            customDisplayName: editHyroxCustomDisplayName,
            notes: editHyroxNotes
        )
        if isAddingHyroxExercise {
            let newId = nextTempHyroxExerciseId
            nextTempHyroxExerciseId -= 1
            let insertionOrder = hyroxDisplayGroups.indices.contains(currentHyroxExerciseIndex)
                ? (hyroxDisplayGroups[currentHyroxExerciseIndex].exercises.map(\.exercise_order).max() ?? hyroxExercises.count) + 1
                : hyroxExercises.count + 1
            for idx in hyroxExercises.indices where hyroxExercises[idx].exercise_order >= insertionOrder {
                hyroxExercises[idx].exercise_order += 1
            }
            hyroxExercises.append(
                ActiveHyroxExercise(
                    id: newId,
                    exercise_code: persisted.code,
                    exercise_order: insertionOrder,
                    zone_order: nil,
                    distance_m: parseIntField(editHyroxDistanceM),
                    reps: parseIntField(editHyroxReps),
                    weight_kg: parseDecimalField(editHyroxWeightKg),
                    duration_sec: parseIntField(editHyroxDurationSec),
                    height_cm: parseIntField(editHyroxHeightCm),
                    implement_count: parseIntField(editHyroxImplementCount),
                    notes: editHyroxNotes.trimmedOrNil,
                    exercise_display_name: persisted.displayName
                )
            )
            normalizeActiveHyroxExerciseOrdering()
            if let newIndex = hyroxDisplayGroups.firstIndex(where: { group in
                group.exercises.contains { $0.id == newId }
            }) {
                currentHyroxExerciseIndex = newIndex
                activeHyroxExerciseId = newId
            }
            return
        }

        guard let editHyroxExerciseId,
              let index = hyroxExercises.firstIndex(where: { $0.id == editHyroxExerciseId })
        else { return }

        hyroxExercises[index].exercise_code = persisted.code
        hyroxExercises[index].exercise_display_name = persisted.displayName
        hyroxExercises[index].distance_m = parseIntField(editHyroxDistanceM)
        hyroxExercises[index].reps = parseIntField(editHyroxReps)
        hyroxExercises[index].weight_kg = parseDecimalField(editHyroxWeightKg)
        hyroxExercises[index].duration_sec = parseIntField(editHyroxDurationSec)
        hyroxExercises[index].height_cm = parseIntField(editHyroxHeightCm)
        hyroxExercises[index].implement_count = parseIntField(editHyroxImplementCount)
        hyroxExercises[index].notes = editHyroxNotes.trimmedOrNil
    }

    private func deleteSelectedHyroxExercise() {
        let targetId = deleteHyroxExerciseId ?? currentHyroxExercise?.id
        guard let targetId else { return }
        let oldIndex = currentHyroxExerciseIndex
        hyroxExercises.removeAll { $0.id == targetId }
        completedHyroxExerciseIds.remove(targetId)
        deleteHyroxExerciseId = nil
        normalizeActiveHyroxExerciseOrdering()
        currentHyroxExerciseIndex = min(oldIndex, max(0, hyroxDisplayGroups.count - 1))
        let activeExerciseStillInCurrentGroup = activeHyroxExerciseId.map { id in
            currentHyroxDisplayGroup?.exercises.contains { $0.id == id } == true
        } == true
        if activeHyroxExerciseId == targetId || !activeExerciseStillInCurrentGroup {
            activeHyroxExerciseId = currentHyroxDisplayGroup?.exercises.first?.id
        }
    }

    private func hyroxDecimalText(_ value: Decimal?) -> String {
        guard let value else { return "" }
        let doubleValue = NSDecimalNumber(decimal: value).doubleValue
        if doubleValue == floor(doubleValue) { return String(Int(doubleValue)) }
        return String(format: "%.1f", doubleValue)
    }

    private func parseDecimalField(_ text: String) -> Decimal? {
        let trimmed = text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return Decimal(string: trimmed, locale: Locale(identifier: "en_US_POSIX"))
    }
    
    private func loadSport() async {
        do {
            let res = try await SupabaseManager.shared.client
                .from("sport_sessions")
                .select("id, sport, duration_sec, score_for, score_against, match_result, match_score_text, location, notes")
                .eq("workout_id", value: workoutId)
                .single()
                .execute()
            
            let row = try JSONDecoder.supabase().decode(SportRow.self, from: res.data)
            
            let loadedSportType = SportType(rawValue: row.sport) ?? .padel

            await MainActor.run {
                self.sportRow = row
                self.sportType = loadedSportType
                self.sportForm.sport = self.sportType
                
                if loadedSportType != .hyrox, let secs = row.duration_sec, secs > 0 {
                    self.hasTargetTime = true
                    self.initialTargetSec = secs
                    self.remainingSec = self.initialTargetSec
                    self.elapsedSec = 0
                    self.mode = .countdown
                } else {
                    self.hasTargetTime = false
                    self.initialTargetSec = 0
                    self.remainingSec = 0
                    self.elapsedSec = 0
                    self.mode = .stopwatch
                }
                
                if let s = row.score_for     { self.sportForm.scoreFor     = String(s) }
                if let s = row.score_against { self.sportForm.scoreAgainst = String(s) }
                if let t = row.match_score_text { self.sportForm.matchScoreText = t }
                self.sportForm.location     = row.location ?? ""
                self.sportForm.sessionNotes = row.notes ?? ""
                
                if let mr = row.match_result,
                   let mapped = MatchResult(rawValue: mr) {
                    self.sportForm.matchResult = mapped
                } else {
                    self.sportForm.matchResult = .unfinished
                }
            }
            
            await loadSportSpecificStats(
                sessionId: row.id,
                sportType: SportType(rawValue: row.sport) ?? .padel
            )
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
            }
        }
    }
    
    private func saveAndFinishWorkout() async {
        await MainActor.run {
            isSaving = true
            isRunning = false
        }
        
        do {
            struct UpdatePayload: Encodable {
                let duration_sec: Int?
                let score_for: Int?
                let score_against: Int?
                let match_result: String?
                let match_score_text: String?
                let location: String?
                let notes: String?
            }
            
            let durationSeconds: Int?
            if elapsedSec > 0 {
                durationSeconds = elapsedSec
            } else {
                durationSeconds = nil
            }
            
            let scoreFor      = Int(sportForm.scoreFor.trimmingCharacters(in: .whitespacesAndNewlines))
            let scoreAgainst  = Int(sportForm.scoreAgainst.trimmingCharacters(in: .whitespacesAndNewlines))
            let matchScore    = sportForm.matchScoreText.trimmedOrNil
            let location      = sportForm.location.trimmedOrNil
            let notes         = sportForm.sessionNotes.trimmedOrNil
            
            let payload = UpdatePayload(
                duration_sec: durationSeconds,
                score_for: sportUsesNumericScore(sportType) ? scoreFor : nil,
                score_against: sportUsesNumericScore(sportType) ? scoreAgainst : nil,
                match_result: sportForm.matchResult.rawValue,
                match_score_text: sportUsesSetText(sportType) ? matchScore : nil,
                location: location,
                notes: notes
            )
            
            _ = try await SupabaseManager.shared.client
                .from("sport_sessions")
                .update(payload)
                .eq("workout_id", value: workoutId)
                .execute()

            let endTime = Date()
            let stateRes = try await SupabaseManager.shared.client
                .from("workouts")
                .select("state")
                .eq("id", value: workoutId)
                .single()
                .execute()
            let stateRow = try JSONDecoder.supabase().decode(WorkoutStateRow.self, from: stateRes.data)
            let stateToPublish = stateRow.state?.lowercased() == "planned" ? "published" : nil
            _ = try await SupabaseManager.shared.client
                .from("workouts")
                .update(WorkoutFinishPatch(ended_at: endTime, state: stateToPublish))
                .eq("id", value: workoutId)
                .execute()
            NotificationCenter.default.post(name: .workoutDidChange, object: workoutId)
            
            if let sessionId = sportRow?.id {
                try await saveSportSpecificStats(sessionId: sessionId)
            }
            
            await MainActor.run {
                isSaving = false
                dismiss()
            }
        } catch {
            await MainActor.run {
                isSaving = false
                self.error = error.localizedDescription
            }
        }
    }
    
    private func parseIntField(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : Int(trimmed)
    }
    
    private func loadSportSpecificStats(sessionId: Int, sportType: SportType) async {
        let client = SupabaseManager.shared.client
        
        switch sportType {
        case .football:
            struct Row: Decodable {
                let position: String?
                let assists: Int?
                let shots_on_target: Int?
                let passes_completed: Int?
                let tackles: Int?
                let saves: Int?
                let yellow_cards: Int?
                let red_cards: Int?
            }
            
            do {
                let res = try await client
                    .from("football_session_stats")
                    .select("position, assists, shots_on_target, passes_completed, tackles, saves, yellow_cards, red_cards")
                    .eq("session_id", value: sessionId)
                    .single()
                    .execute()
                
                let row = try JSONDecoder.supabase().decode(Row.self, from: res.data)
                
                await MainActor.run {
                    if let pos = row.position {
                        self.sportForm.fbPosition = FootballPosition(rawValue: pos) ?? self.sportForm.fbPosition
                    }
                    if let v = row.assists          { self.sportForm.fbAssists         = String(v) }
                    if let v = row.shots_on_target  { self.sportForm.fbShotsOnTarget   = String(v) }
                    if let v = row.passes_completed { self.sportForm.fbPassesCompleted = String(v) }
                    if let v = row.tackles          { self.sportForm.fbTackles         = String(v) }
                    if let v = row.saves            { self.sportForm.fbSaves           = String(v) }
                    if let v = row.yellow_cards     { self.sportForm.fbYellow          = String(v) }
                    if let v = row.red_cards        { self.sportForm.fbRed             = String(v) }
                }
            } catch {
                print("Error loading football stats: \(error)")
            }
            
        case .basketball:
            struct Row: Decodable {
                let points: Int?
                let rebounds: Int?
                let assists: Int?
                let steals: Int?
                let blocks: Int?
                let turnovers: Int?
                let fouls: Int?
            }
            
            do {
                let res = try await client
                    .from("basketball_session_stats")
                    .select("points, rebounds, assists, steals, blocks, turnovers, fouls")
                    .eq("session_id", value: sessionId)
                    .single()
                    .execute()
                
                let row = try JSONDecoder.supabase().decode(Row.self, from: res.data)
                
                await MainActor.run {
                    if let v = row.points    { self.sportForm.bbPoints    = String(v) }
                    if let v = row.rebounds  { self.sportForm.bbRebounds  = String(v) }
                    if let v = row.assists   { self.sportForm.bbAssists   = String(v) }
                    if let v = row.steals    { self.sportForm.bbSteals    = String(v) }
                    if let v = row.blocks    { self.sportForm.bbBlocks    = String(v) }
                    if let v = row.turnovers { self.sportForm.bbTurnovers = String(v) }
                    if let v = row.fouls     { self.sportForm.bbFouls     = String(v) }
                }
            } catch {
                print("Error loading basketball stats: \(error)")
            }
            
        case .padel, .tennis, .badminton, .squash, .table_tennis:
            struct Row: Decodable {
                let mode: String?
                let format: String?
                let aces: Int?
                let double_faults: Int?
                let winners: Int?
                let unforced_errors: Int?
                let sets_won: Int?
                let sets_lost: Int?
                let games_won: Int?
                let games_lost: Int?
                let break_points_won: Int?
                let break_points_total: Int?
                let net_points_won: Int?
                let net_points_total: Int?
            }
            
            do {
                let res = try await client
                    .from("racket_session_stats")
                    .select("mode, format, aces, double_faults, winners, unforced_errors, sets_won, sets_lost, games_won, games_lost, break_points_won, break_points_total, net_points_won, net_points_total")
                    .eq("session_id", value: sessionId)
                    .single()
                    .execute()
                
                let row = try JSONDecoder.supabase().decode(Row.self, from: res.data)
                
                await MainActor.run {
                    if let m = row.mode {
                        switch m {
                        case "singles":       self.sportForm.racketMode = .singles
                        case "doubles":       self.sportForm.racketMode = .doubles
                        case "mixed_doubles": self.sportForm.racketMode = .mixedDoubles
                        default: break
                        }
                    }
                    if let f = row.format {
                        switch f {
                        case "best_of_3": self.sportForm.racketFormat = .bestOfThree
                        case "best_of_5": self.sportForm.racketFormat = .bestOfFive
                        default: break
                        }
                    }
                    
                    if let v = row.aces               { self.sportForm.rkAces             = String(v) }
                    if let v = row.double_faults      { self.sportForm.rkDoubleFaults     = String(v) }
                    if let v = row.winners            { self.sportForm.rkWinners          = String(v) }
                    if let v = row.unforced_errors    { self.sportForm.rkUnforcedErrors   = String(v) }
                    if let v = row.sets_won           { self.sportForm.rkSetsWon          = String(v) }
                    if let v = row.sets_lost          { self.sportForm.rkSetsLost         = String(v) }
                    if let v = row.games_won          { self.sportForm.rkGamesWon         = String(v) }
                    if let v = row.games_lost         { self.sportForm.rkGamesLost        = String(v) }
                    if let v = row.break_points_won   { self.sportForm.rkBreakPointsWon   = String(v) }
                    if let v = row.break_points_total { self.sportForm.rkBreakPointsTotal = String(v) }
                    if let v = row.net_points_won     { self.sportForm.rkNetPointsWon     = String(v) }
                    if let v = row.net_points_total   { self.sportForm.rkNetPointsTotal   = String(v) }
                }
            } catch {
                print("Error loading racket stats: \(error)")
            }
            
        case .volleyball:
            struct VBRow: Decodable {
                let points: Int?
                let aces: Int?
                let blocks: Int?
                let digs: Int?
            }
            
            do {
                let res = try await client
                    .from("volleyball_session_stats")
                    .select("points, aces, blocks, digs")
                    .eq("session_id", value: sessionId)
                    .single()
                    .execute()
                
                let row = try JSONDecoder.supabase().decode(VBRow.self, from: res.data)
                
                await MainActor.run {
                    if let v = row.points { self.sportForm.vbPoints = String(v) }
                    if let v = row.aces   { self.sportForm.vbAces   = String(v) }
                    if let v = row.blocks { self.sportForm.vbBlocks = String(v) }
                    if let v = row.digs   { self.sportForm.vbDigs   = String(v) }
                }
            } catch {
                print("Error loading volleyball stats: \(error)")
            }
            
        case .handball:
            struct HBRow: Decodable {
                let position: String?
                let goals: Int?
                let shots: Int?
                let shots_on_target: Int?
                let assists: Int?
                let steals: Int?
                let blocks: Int?
                let turnovers_lost: Int?
                let seven_m_goals: Int?
                let seven_m_attempts: Int?
                let saves: Int?
                let yellow_cards: Int?
                let two_min_suspensions: Int?
                let red_cards: Int?
            }
            
            do {
                let res = try await client
                    .from("handball_session_stats")
                    .select("position, goals, shots, shots_on_target, assists, steals, blocks, turnovers_lost, seven_m_goals, seven_m_attempts, saves, yellow_cards, two_min_suspensions, red_cards")
                    .eq("session_id", value: sessionId)
                    .single()
                    .execute()
                
                let row = try JSONDecoder.supabase().decode(HBRow.self, from: res.data)
                
                await MainActor.run {
                    self.sportForm.hbPosition = row.position ?? ""
                    if let v = row.goals              { self.sportForm.hbGoals          = String(v) }
                    if let v = row.shots              { self.sportForm.hbShots          = String(v) }
                    if let v = row.shots_on_target    { self.sportForm.hbShotsOnTarget  = String(v) }
                    if let v = row.assists            { self.sportForm.hbAssists        = String(v) }
                    if let v = row.steals             { self.sportForm.hbSteals         = String(v) }
                    if let v = row.blocks             { self.sportForm.hbBlocks         = String(v) }
                    if let v = row.turnovers_lost     { self.sportForm.hbTurnoversLost  = String(v) }
                    if let v = row.seven_m_goals      { self.sportForm.hbSevenMGoals    = String(v) }
                    if let v = row.seven_m_attempts   { self.sportForm.hbSevenMAttempts = String(v) }
                    if let v = row.saves              { self.sportForm.hbSaves          = String(v) }
                    if let v = row.yellow_cards       { self.sportForm.hbYellow         = String(v) }
                    if let v = row.two_min_suspensions{ self.sportForm.hbTwoMin         = String(v) }
                    if let v = row.red_cards          { self.sportForm.hbRed            = String(v) }
                }
            } catch {
                print("Error loading handball stats: \(error)")
            }
            
        case .hockey:
            struct HKRow: Decodable {
                let position: String?
                let goals: Int?
                let assists: Int?
                let shots_on_goal: Int?
                let plus_minus: Int?
                let hits: Int?
                let blocks: Int?
                let faceoffs_won: Int?
                let faceoffs_total: Int?
                let saves: Int?
                let penalty_minutes: Int?
            }
            
            do {
                let res = try await client
                    .from("hockey_session_stats")
                    .select("position, goals, assists, shots_on_goal, plus_minus, hits, blocks, faceoffs_won, faceoffs_total, saves, penalty_minutes")
                    .eq("session_id", value: sessionId)
                    .single()
                    .execute()
                
                let row = try JSONDecoder.supabase().decode(HKRow.self, from: res.data)
                
                await MainActor.run {
                    self.sportForm.hkPosition = row.position ?? ""
                    if let v = row.goals          { self.sportForm.hkGoals          = String(v) }
                    if let v = row.assists        { self.sportForm.hkAssists        = String(v) }
                    if let v = row.shots_on_goal  { self.sportForm.hkShotsOnGoal    = String(v) }
                    if let v = row.plus_minus     { self.sportForm.hkPlusMinus      = String(v) }
                    if let v = row.hits           { self.sportForm.hkHits           = String(v) }
                    if let v = row.blocks         { self.sportForm.hkBlocks         = String(v) }
                    if let v = row.faceoffs_won   { self.sportForm.hkFaceoffsWon    = String(v) }
                    if let v = row.faceoffs_total { self.sportForm.hkFaceoffsTotal  = String(v) }
                    if let v = row.saves          { self.sportForm.hkSaves          = String(v) }
                    if let v = row.penalty_minutes{ self.sportForm.hkPenaltyMinutes = String(v) }
                }
            } catch {
                print("Error loading hockey stats: \(error)")
            }
            
        case .rugby:
            struct RGRow: Decodable {
                let position: String?
                let tries: Int?
                let conversions_made: Int?
                let conversions_attempted: Int?
                let penalty_goals_made: Int?
                let penalty_goals_attempted: Int?
                let runs: Int?
                let meters_gained: Int?
                let offloads: Int?
                let tackles_made: Int?
                let tackles_missed: Int?
                let turnovers_won: Int?
                let yellow_cards: Int?
                let red_cards: Int?
            }
            
            do {
                let res = try await client
                    .from("rugby_session_stats")
                    .select("position, tries, conversions_made, conversions_attempted, penalty_goals_made, penalty_goals_attempted, runs, meters_gained, offloads, tackles_made, tackles_missed, turnovers_won, yellow_cards, red_cards")
                    .eq("session_id", value: sessionId)
                    .single()
                    .execute()
                
                let row = try JSONDecoder.supabase().decode(RGRow.self, from: res.data)
                
                await MainActor.run {
                    self.sportForm.rgPosition = row.position ?? ""
                    if let v = row.tries                  { self.sportForm.rgTries                 = String(v) }
                    if let v = row.conversions_made       { self.sportForm.rgConversionsMade       = String(v) }
                    if let v = row.conversions_attempted  { self.sportForm.rgConversionsAttempted  = String(v) }
                    if let v = row.penalty_goals_made     { self.sportForm.rgPenaltyGoalsMade      = String(v) }
                    if let v = row.penalty_goals_attempted{ self.sportForm.rgPenaltyGoalsAttempted = String(v) }
                    if let v = row.runs                   { self.sportForm.rgRuns                  = String(v) }
                    if let v = row.meters_gained          { self.sportForm.rgMetersGained          = String(v) }
                    if let v = row.offloads               { self.sportForm.rgOffloads              = String(v) }
                    if let v = row.tackles_made           { self.sportForm.rgTacklesMade           = String(v) }
                    if let v = row.tackles_missed         { self.sportForm.rgTacklesMissed         = String(v) }
                    if let v = row.turnovers_won          { self.sportForm.rgTurnoversWon          = String(v) }
                    if let v = row.yellow_cards           { self.sportForm.rgYellow                = String(v) }
                    if let v = row.red_cards              { self.sportForm.rgRed                   = String(v) }
                }
            } catch {
                print("Error loading rugby stats: \(error)")
            }
            
        case .hyrox:
            struct HYRow: Decodable {
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
            
            do {
                let res = try await client
                    .from("hyrox_session_stats")
                    .select("division, category, age_group, official_time_sec, penalty_time_sec, no_reps, rank_overall, rank_category, avg_hr, max_hr")
                    .eq("session_id", value: sessionId)
                    .single()
                    .execute()
                
                let row = try JSONDecoder.supabase().decode(HYRow.self, from: res.data)
                
                await MainActor.run {
                    self.sportForm.hyDivision   = row.division   ?? ""
                    self.sportForm.hyCategory   = row.category   ?? ""
                    self.sportForm.hyAgeGroup   = row.age_group  ?? ""
                    if let v = row.official_time_sec { self.sportForm.hyOfficialTimeSec = String(v) }
                    if let v = row.penalty_time_sec  { self.sportForm.hyPenaltyTimeSec  = String(v) }
                    if let v = row.no_reps           { self.sportForm.hyNoReps          = String(v) }
                    if let v = row.rank_overall      { self.sportForm.hyRankOverall     = String(v) }
                    if let v = row.rank_category     { self.sportForm.hyRankCategory    = String(v) }
                    if let v = row.avg_hr            { self.sportForm.hyAvgHR           = String(v) }
                    if let v = row.max_hr            { self.sportForm.hyMaxHR           = String(v) }
                }
                let exRes = try await client
                    .from("hyrox_session_exercises")
                    .select("id, exercise_code, exercise_order, zone_order, distance_m, reps, weight_kg, duration_sec, height_cm, implement_count, notes, exercise_display_name")
                    .eq("session_id", value: sessionId)
                    .order("exercise_order", ascending: true)
                    .execute()

                let exRows = try JSONDecoder.supabase().decode([ActiveHyroxExercise].self, from: exRes.data)

                await MainActor.run {
                    self.hyroxExercises = exRows
                    self.currentHyroxExerciseIndex = 0
                    self.activeHyroxExerciseId = exRows.first?.id
                    self.completedHyroxExerciseIds = []
                    self.nextTempHyroxExerciseId = -1
                }
            } catch {
                print("Error loading hyrox stats: \(error)")
            }
            
        case .ski:
            struct SKRow: Decodable {
                let total_distance_km: Double?
                let runs_count: Int?
                let max_speed_kmh: Double?
                let avg_speed_kmh: Double?
                let vertical_drop_m: Int?
                let moving_time_sec: Int?
                let paused_time_sec: Int?
                let resort_name: String?
                let snow_condition: String?
                let weather: String?
            }

            do {
                let res = try await client
                    .from("ski_session_stats")
                    .select("total_distance_km, runs_count, max_speed_kmh, avg_speed_kmh, vertical_drop_m, moving_time_sec, paused_time_sec, resort_name, snow_condition, weather")
                    .eq("session_id", value: sessionId)
                    .single()
                    .execute()

                let row = try JSONDecoder.supabase().decode(SKRow.self, from: res.data)

                await MainActor.run {
                    if let v = row.total_distance_km { self.sportForm.skiTotalDistanceKm = String(v) }
                    if let v = row.runs_count        { self.sportForm.skiRunsCount       = String(v) }
                    if let v = row.max_speed_kmh     { self.sportForm.skiMaxSpeedKmh     = String(v) }
                    if let v = row.avg_speed_kmh     { self.sportForm.skiAvgSpeedKmh     = String(v) }
                    if let v = row.vertical_drop_m   { self.sportForm.skiVerticalDropM   = String(v) }
                    if let v = row.moving_time_sec   { self.sportForm.skiMovingTimeSec   = String(v) }
                    if let v = row.paused_time_sec   { self.sportForm.skiPausedTimeSec   = String(v) }

                    self.sportForm.skiResortName    = row.resort_name ?? ""
                    self.sportForm.skiSnowCondition = row.snow_condition ?? ""
                    self.sportForm.skiWeather       = row.weather ?? ""
                }
            } catch {
                print("Error loading ski stats: \(error)")
            }
        }
    }
    
    private func saveSportSpecificStats(sessionId: Int) async throws {
        let client = SupabaseManager.shared.client
        
        switch sportType {
        case .football:
            struct Payload: Encodable {
                let position: String?
                let assists: Int?
                let shots_on_target: Int?
                let passes_completed: Int?
                let tackles: Int?
                let saves: Int?
                let yellow_cards: Int?
                let red_cards: Int?
            }
            
            let payload = Payload(
                position: sportForm.fbPosition.dbValue,
                assists: parseIntField(sportForm.fbAssists),
                shots_on_target: parseIntField(sportForm.fbShotsOnTarget),
                passes_completed: parseIntField(sportForm.fbPassesCompleted),
                tackles: parseIntField(sportForm.fbTackles),
                saves: parseIntField(sportForm.fbSaves),
                yellow_cards: parseIntField(sportForm.fbYellow),
                red_cards: parseIntField(sportForm.fbRed)
            )
            
            _ = try await client
                .from("football_session_stats")
                .update(payload)
                .eq("session_id", value: sessionId)
                .execute()
            
        case .basketball:
            struct Payload: Encodable {
                let points: Int?
                let rebounds: Int?
                let assists: Int?
                let steals: Int?
                let blocks: Int?
                let turnovers: Int?
                let fouls: Int?
            }
            
            let payload = Payload(
                points:    parseIntField(sportForm.bbPoints),
                rebounds:  parseIntField(sportForm.bbRebounds),
                assists:   parseIntField(sportForm.bbAssists),
                steals:    parseIntField(sportForm.bbSteals),
                blocks:    parseIntField(sportForm.bbBlocks),
                turnovers: parseIntField(sportForm.bbTurnovers),
                fouls:     parseIntField(sportForm.bbFouls)
            )
            
            _ = try await client
                .from("basketball_session_stats")
                .update(payload)
                .eq("session_id", value: sessionId)
                .execute()
            
        case .padel, .tennis, .badminton, .squash, .table_tennis:
            struct Payload: Encodable {
                let mode: String?
                let format: String?
                let aces: Int?
                let double_faults: Int?
                let winners: Int?
                let unforced_errors: Int?
                let sets_won: Int?
                let sets_lost: Int?
                let games_won: Int?
                let games_lost: Int?
                let break_points_won: Int?
                let break_points_total: Int?
                let net_points_won: Int?
                let net_points_total: Int?
            }
            
            let modeString: String? = {
                switch sportForm.racketMode {
                case .singles:      return "singles"
                case .doubles:      return "doubles"
                case .mixedDoubles: return "mixed_doubles"
                }
            }()
            
            let formatString: String? = {
                switch sportForm.racketFormat {
                case .bestOfThree: return "best_of_3"
                case .bestOfFive:  return "best_of_5"
                }
            }()
            
            let payload = Payload(
                mode: modeString,
                format: formatString,
                aces: parseIntField(sportForm.rkAces),
                double_faults: parseIntField(sportForm.rkDoubleFaults),
                winners: parseIntField(sportForm.rkWinners),
                unforced_errors: parseIntField(sportForm.rkUnforcedErrors),
                sets_won: parseIntField(sportForm.rkSetsWon),
                sets_lost: parseIntField(sportForm.rkSetsLost),
                games_won: parseIntField(sportForm.rkGamesWon),
                games_lost: parseIntField(sportForm.rkGamesLost),
                break_points_won: parseIntField(sportForm.rkBreakPointsWon),
                break_points_total: parseIntField(sportForm.rkBreakPointsTotal),
                net_points_won: parseIntField(sportForm.rkNetPointsWon),
                net_points_total: parseIntField(sportForm.rkNetPointsTotal)
            )
            
            _ = try await client
                .from("racket_session_stats")
                .update(payload)
                .eq("session_id", value: sessionId)
                .execute()
            
        case .volleyball:
            struct Payload: Encodable {
                let points: Int?
                let aces: Int?
                let blocks: Int?
                let digs: Int?
            }
            
            let payload = Payload(
                points: parseIntField(sportForm.vbPoints),
                aces:   parseIntField(sportForm.vbAces),
                blocks: parseIntField(sportForm.vbBlocks),
                digs:   parseIntField(sportForm.vbDigs)
            )
            
            _ = try await client
                .from("volleyball_session_stats")
                .update(payload)
                .eq("session_id", value: sessionId)
                .execute()
            
        case .handball:
            struct Payload: Encodable {
                let position: String?
                let goals: Int?
                let shots: Int?
                let shots_on_target: Int?
                let assists: Int?
                let steals: Int?
                let blocks: Int?
                let turnovers_lost: Int?
                let seven_m_goals: Int?
                let seven_m_attempts: Int?
                let saves: Int?
                let yellow_cards: Int?
                let two_min_suspensions: Int?
                let red_cards: Int?
            }
            
            let payload = Payload(
                position: sportForm.hbPosition.trimmedOrNil,
                goals: parseIntField(sportForm.hbGoals),
                shots: parseIntField(sportForm.hbShots),
                shots_on_target: parseIntField(sportForm.hbShotsOnTarget),
                assists: parseIntField(sportForm.hbAssists),
                steals: parseIntField(sportForm.hbSteals),
                blocks: parseIntField(sportForm.hbBlocks),
                turnovers_lost: parseIntField(sportForm.hbTurnoversLost),
                seven_m_goals: parseIntField(sportForm.hbSevenMGoals),
                seven_m_attempts: parseIntField(sportForm.hbSevenMAttempts),
                saves: parseIntField(sportForm.hbSaves),
                yellow_cards: parseIntField(sportForm.hbYellow),
                two_min_suspensions: parseIntField(sportForm.hbTwoMin),
                red_cards: parseIntField(sportForm.hbRed)
            )
            
            _ = try await client
                .from("handball_session_stats")
                .update(payload)
                .eq("session_id", value: sessionId)
                .execute()
            
        case .hockey:
            struct Payload: Encodable {
                let position: String?
                let goals: Int?
                let assists: Int?
                let shots_on_goal: Int?
                let plus_minus: Int?
                let hits: Int?
                let blocks: Int?
                let faceoffs_won: Int?
                let faceoffs_total: Int?
                let saves: Int?
                let penalty_minutes: Int?
            }
            
            let payload = Payload(
                position: sportForm.hkPosition.trimmedOrNil,
                goals: parseIntField(sportForm.hkGoals),
                assists: parseIntField(sportForm.hkAssists),
                shots_on_goal: parseIntField(sportForm.hkShotsOnGoal),
                plus_minus: parseIntField(sportForm.hkPlusMinus),
                hits: parseIntField(sportForm.hkHits),
                blocks: parseIntField(sportForm.hkBlocks),
                faceoffs_won: parseIntField(sportForm.hkFaceoffsWon),
                faceoffs_total: parseIntField(sportForm.hkFaceoffsTotal),
                saves: parseIntField(sportForm.hkSaves),
                penalty_minutes: parseIntField(sportForm.hkPenaltyMinutes)
            )
            
            _ = try await client
                .from("hockey_session_stats")
                .update(payload)
                .eq("session_id", value: sessionId)
                .execute()
            
        case .rugby:
            struct Payload: Encodable {
                let position: String?
                let tries: Int?
                let conversions_made: Int?
                let conversions_attempted: Int?
                let penalty_goals_made: Int?
                let penalty_goals_attempted: Int?
                let runs: Int?
                let meters_gained: Int?
                let offloads: Int?
                let tackles_made: Int?
                let tackles_missed: Int?
                let turnovers_won: Int?
                let yellow_cards: Int?
                let red_cards: Int?
            }
            
            let payload = Payload(
                position: sportForm.rgPosition.trimmedOrNil,
                tries: parseIntField(sportForm.rgTries),
                conversions_made: parseIntField(sportForm.rgConversionsMade),
                conversions_attempted: parseIntField(sportForm.rgConversionsAttempted),
                penalty_goals_made: parseIntField(sportForm.rgPenaltyGoalsMade),
                penalty_goals_attempted: parseIntField(sportForm.rgPenaltyGoalsAttempted),
                runs: parseIntField(sportForm.rgRuns),
                meters_gained: parseIntField(sportForm.rgMetersGained),
                offloads: parseIntField(sportForm.rgOffloads),
                tackles_made: parseIntField(sportForm.rgTacklesMade),
                tackles_missed: parseIntField(sportForm.rgTacklesMissed),
                turnovers_won: parseIntField(sportForm.rgTurnoversWon),
                yellow_cards: parseIntField(sportForm.rgYellow),
                red_cards: parseIntField(sportForm.rgRed)
            )
            
            _ = try await client
                .from("rugby_session_stats")
                .update(payload)
                .eq("session_id", value: sessionId)
                .execute()
            
        case .hyrox:
            struct Payload: Encodable {
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
            
            let payload = Payload(
                division: sportForm.hyDivision.trimmedOrNil,
                category: sportForm.hyCategory.trimmedOrNil,
                age_group: sportForm.hyAgeGroup.trimmedOrNil,
                official_time_sec: parseIntField(sportForm.hyOfficialTimeSec),
                penalty_time_sec: parseIntField(sportForm.hyPenaltyTimeSec),
                no_reps: parseIntField(sportForm.hyNoReps),
                rank_overall: parseIntField(sportForm.hyRankOverall),
                rank_category: parseIntField(sportForm.hyRankCategory),
                avg_hr: parseIntField(sportForm.hyAvgHR),
                max_hr: parseIntField(sportForm.hyMaxHR)
            )
            
            _ = try await client
                .from("hyrox_session_stats")
                .update(payload)
                .eq("session_id", value: sessionId)
                .execute()
            
            _ = try await client
                .from("hyrox_session_exercises")
                .delete()
                .eq("session_id", value: sessionId)
                .execute()

            struct HyroxExerciseInsertPayload: Encodable {
                let session_id: Int
                let exercise_code: String
                let exercise_order: Int
                let zone_order: Int?
                let distance_m: Int?
                let reps: Int?
                let weight_kg: Decimal?
                let duration_sec: Int?
                let height_cm: Int?
                let implement_count: Int?
                let notes: String?
                let exercise_display_name: String?
            }

            let exercisePayloads: [HyroxExerciseInsertPayload] = hyroxExercises.map { ex in
                HyroxExerciseInsertPayload(
                    session_id: sessionId,
                    exercise_code: ex.exercise_code,
                    exercise_order: ex.exercise_order,
                    zone_order: ex.zone_order.map { max(1, $0) },
                    distance_m: ex.distance_m,
                    reps: ex.reps,
                    weight_kg: ex.weight_kg,
                    duration_sec: ex.duration_sec,
                    height_cm: ex.height_cm,
                    implement_count: ex.implement_count,
                    notes: ex.notes,
                    exercise_display_name: ex.exercise_display_name
                )
            }

            if !exercisePayloads.isEmpty {
                _ = try await client
                    .from("hyrox_session_exercises")
                    .insert(exercisePayloads)
                    .execute()
            }
            
        case .ski:
            struct Payload: Encodable {
                let total_distance_km: Double?
                let runs_count: Int?
                let max_speed_kmh: Double?
                let avg_speed_kmh: Double?
                let vertical_drop_m: Int?
                let moving_time_sec: Int?
                let paused_time_sec: Int?
                let resort_name: String?
                let snow_condition: String?
                let weather: String?
            }

            func parseDoubleField(_ text: String) -> Double? {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return nil }
                return Double(trimmed.replacingOccurrences(of: ",", with: "."))
            }

            let payload = Payload(
                total_distance_km: parseDoubleField(sportForm.skiTotalDistanceKm),
                runs_count: parseIntField(sportForm.skiRunsCount),
                max_speed_kmh: parseDoubleField(sportForm.skiMaxSpeedKmh),
                avg_speed_kmh: parseDoubleField(sportForm.skiAvgSpeedKmh),
                vertical_drop_m: parseIntField(sportForm.skiVerticalDropM),
                moving_time_sec: parseIntField(sportForm.skiMovingTimeSec),
                paused_time_sec: parseIntField(sportForm.skiPausedTimeSec),
                resort_name: sportForm.skiResortName.trimmedOrNil,
                snow_condition: sportForm.skiSnowCondition.trimmedOrNil,
                weather: sportForm.skiWeather.trimmedOrNil
            )

            _ = try await client
                .from("ski_session_stats")
                .update(payload)
                .eq("session_id", value: sessionId)
                .execute()
        }
    }
    
    private func formatTime(_ total: Int) -> String {
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        } else {
            return String(format: "%d:%02d", m, s)
        }
    }
    
    private func sportUsesNumericScore(_ s: SportType) -> Bool {
        switch s {
        case .football, .basketball, .handball, .hockey, .rugby:
            return true
        default:
            return false
        }
    }
    
    private func sportUsesSetText(_ s: SportType) -> Bool {
        switch s {
        case .padel, .tennis, .badminton, .squash, .table_tennis, .volleyball:
            return true
        default:
            return false
        }
    }
}

struct SportStatsFields: View {
    @Binding var sportForm: SportForm
    let sportType: SportType

    var body: some View {
        switch sportType {
        case .football:
            Divider()
            FieldRowPlain {
                Picker("", selection: $sportForm.fbPosition) {
                    ForEach(FootballPosition.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.menu)
            }
            Divider()
            FieldRowPlain {
                HStack {
                    TextField("Assists", text: $sportForm.fbAssists)
                        .keyboardType(.numberPad)
                    TextField("Shots on target", text: $sportForm.fbShotsOnTarget)
                        .keyboardType(.numberPad)
                }
            }
            Divider()
            FieldRowPlain {
                HStack {
                    TextField("Passes completed", text: $sportForm.fbPassesCompleted)
                        .keyboardType(.numberPad)
                    TextField("Tackles", text: $sportForm.fbTackles)
                        .keyboardType(.numberPad)
                }
            }
            Divider()
            FieldRowPlain {
                HStack {
                    TextField("Saves (GK)", text: $sportForm.fbSaves)
                        .keyboardType(.numberPad)
                    TextField("Yellow cards", text: $sportForm.fbYellow)
                        .keyboardType(.numberPad)
                    TextField("Red cards", text: $sportForm.fbRed)
                        .keyboardType(.numberPad)
                }
            }

        case .basketball:
            Divider()
            FieldRowPlain {
                HStack {
                    TextField("Points", text: $sportForm.bbPoints)
                        .keyboardType(.numberPad)
                    TextField("Rebounds", text: $sportForm.bbRebounds)
                        .keyboardType(.numberPad)
                    TextField("Assists", text: $sportForm.bbAssists)
                        .keyboardType(.numberPad)
                }
            }
            Divider()
            FieldRowPlain {
                HStack {
                    TextField("Steals", text: $sportForm.bbSteals)
                        .keyboardType(.numberPad)
                    TextField("Blocks", text: $sportForm.bbBlocks)
                        .keyboardType(.numberPad)
                    TextField("Turnovers", text: $sportForm.bbTurnovers)
                        .keyboardType(.numberPad)
                }
            }
            Divider()
            FieldRowPlain {
                TextField("Fouls", text: $sportForm.bbFouls)
                    .keyboardType(.numberPad)
            }

        case .padel, .tennis, .badminton, .squash, .table_tennis:
            Divider()
            FieldRowPlain {
                Picker("", selection: $sportForm.racketMode) {
                    ForEach(RacketMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.menu)
            }
            Divider()
            FieldRowPlain {
                Picker("", selection: $sportForm.racketFormat) {
                    ForEach(RacketFormat.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            Divider()
            FieldRowPlain {
                HStack {
                    TextField("Aces",          text: $sportForm.rkAces)
                        .keyboardType(.numberPad)
                    TextField("Double faults", text: $sportForm.rkDoubleFaults)
                        .keyboardType(.numberPad)
                    TextField("Winners",       text: $sportForm.rkWinners)
                        .keyboardType(.numberPad)
                }
            }
            Divider()
            FieldRowPlain {
                TextField("Unforced errors", text: $sportForm.rkUnforcedErrors)
                    .keyboardType(.numberPad)
            }
            Divider()
            FieldRowPlain {
                HStack {
                    TextField("Sets won",  text: $sportForm.rkSetsWon)
                        .keyboardType(.numberPad)
                    TextField("Sets lost", text: $sportForm.rkSetsLost)
                        .keyboardType(.numberPad)
                }
            }
            Divider()
            FieldRowPlain {
                HStack {
                    TextField("Games won",  text: $sportForm.rkGamesWon)
                        .keyboardType(.numberPad)
                    TextField("Games lost", text: $sportForm.rkGamesLost)
                        .keyboardType(.numberPad)
                }
            }
            Divider()
            FieldRowPlain {
                HStack {
                    TextField("Break pts won",   text: $sportForm.rkBreakPointsWon)
                        .keyboardType(.numberPad)
                    TextField("Break pts total", text: $sportForm.rkBreakPointsTotal)
                        .keyboardType(.numberPad)
                }
            }
            Divider()
            FieldRowPlain {
                HStack {
                    TextField("Net pts won",   text: $sportForm.rkNetPointsWon)
                        .keyboardType(.numberPad)
                    TextField("Net pts total", text: $sportForm.rkNetPointsTotal)
                        .keyboardType(.numberPad)
                }
            }

        case .volleyball:
            Divider()
            FieldRowPlain {
                HStack {
                    TextField("Points", text: $sportForm.vbPoints)
                        .keyboardType(.numberPad)
                    TextField("Aces",   text: $sportForm.vbAces)
                        .keyboardType(.numberPad)
                }
            }

        case .handball:
            Divider()
            FieldRowPlain {
                TextField("Position (optional)", text: $sportForm.hbPosition)
                    .textFieldStyle(.plain)
            }
            Divider()
            FieldRowPlain {
                HStack {
                    TextField("Goals",           text: $sportForm.hbGoals)
                        .keyboardType(.numberPad)
                    TextField("Shots",           text: $sportForm.hbShots)
                        .keyboardType(.numberPad)
                    TextField("Shots on target", text: $sportForm.hbShotsOnTarget)
                        .keyboardType(.numberPad)
                }
            }
            Divider()
            FieldRowPlain {
                HStack {
                    TextField("Assists",         text: $sportForm.hbAssists)
                        .keyboardType(.numberPad)
                    TextField("Steals",          text: $sportForm.hbSteals)
                        .keyboardType(.numberPad)
                    TextField("Blocks",          text: $sportForm.hbBlocks)
                        .keyboardType(.numberPad)
                }
            }
            Divider()
            FieldRowPlain {
                HStack {
                    TextField("Turnovers lost",  text: $sportForm.hbTurnoversLost)
                        .keyboardType(.numberPad)
                    TextField("7m goals",        text: $sportForm.hbSevenMGoals)
                        .keyboardType(.numberPad)
                    TextField("7m attempts",     text: $sportForm.hbSevenMAttempts)
                        .keyboardType(.numberPad)
                }
            }
            Divider()
            FieldRowPlain {
                HStack {
                    TextField("Saves (GK)",      text: $sportForm.hbSaves)
                        .keyboardType(.numberPad)
                    TextField("Yellow cards",    text: $sportForm.hbYellow)
                        .keyboardType(.numberPad)
                    TextField("2-min susp.",     text: $sportForm.hbTwoMin)
                        .keyboardType(.numberPad)
                    TextField("Red cards",       text: $sportForm.hbRed)
                        .keyboardType(.numberPad)
                }
            }

        case .hockey:
            Divider()
            FieldRowPlain {
                TextField("Position (optional)", text: $sportForm.hkPosition)
                    .textFieldStyle(.plain)
            }
            Divider()
            FieldRowPlain {
                HStack {
                    TextField("Goals",         text: $sportForm.hkGoals)
                        .keyboardType(.numberPad)
                    TextField("Assists",       text: $sportForm.hkAssists)
                        .keyboardType(.numberPad)
                    TextField("Shots on goal", text: $sportForm.hkShotsOnGoal)
                        .keyboardType(.numberPad)
                }
            }
            Divider()
            FieldRowPlain {
                HStack {
                    TextField("+/-",           text: $sportForm.hkPlusMinus)
                        .keyboardType(.numberPad)
                    TextField("Hits",          text: $sportForm.hkHits)
                        .keyboardType(.numberPad)
                    TextField("Blocks",        text: $sportForm.hkBlocks)
                        .keyboardType(.numberPad)
                }
            }
            Divider()
            FieldRowPlain {
                HStack {
                    TextField("Faceoffs won",  text: $sportForm.hkFaceoffsWon)
                        .keyboardType(.numberPad)
                    TextField("Faceoffs total",text: $sportForm.hkFaceoffsTotal)
                        .keyboardType(.numberPad)
                }
            }
            Divider()
            FieldRowPlain {
                HStack {
                    TextField("Saves (GK)",      text: $sportForm.hkSaves)
                        .keyboardType(.numberPad)
                    TextField("Penalty minutes", text: $sportForm.hkPenaltyMinutes)
                        .keyboardType(.numberPad)
                }
            }

        case .rugby:
            Divider()
            FieldRowPlain {
                TextField("Position (optional)", text: $sportForm.rgPosition)
                    .textFieldStyle(.plain)
            }
            Divider()
            FieldRowPlain {
                HStack {
                    TextField("Tries",        text: $sportForm.rgTries)
                        .keyboardType(.numberPad)
                    TextField("Conv. made",   text: $sportForm.rgConversionsMade)
                        .keyboardType(.numberPad)
                    TextField("Conv. att.",   text: $sportForm.rgConversionsAttempted)
                        .keyboardType(.numberPad)
                }
            }
            Divider()
            FieldRowPlain {
                HStack {
                    TextField("Pen. goals made", text: $sportForm.rgPenaltyGoalsMade)
                        .keyboardType(.numberPad)
                    TextField("Pen. goals att.", text: $sportForm.rgPenaltyGoalsAttempted)
                        .keyboardType(.numberPad)
                }
            }
            Divider()
            FieldRowPlain {
                HStack {
                    TextField("Runs",          text: $sportForm.rgRuns)
                        .keyboardType(.numberPad)
                    TextField("Meters gained", text: $sportForm.rgMetersGained)
                        .keyboardType(.numberPad)
                    TextField("Offloads",      text: $sportForm.rgOffloads)
                        .keyboardType(.numberPad)
                }
            }
            Divider()
            FieldRowPlain {
                HStack {
                    TextField("Tackles made",   text: $sportForm.rgTacklesMade)
                        .keyboardType(.numberPad)
                    TextField("Tackles missed", text: $sportForm.rgTacklesMissed)
                        .keyboardType(.numberPad)
                    TextField("Turnovers won",  text: $sportForm.rgTurnoversWon)
                        .keyboardType(.numberPad)
                }
            }
            Divider()
            FieldRowPlain {
                HStack {
                    TextField("Yellow cards", text: $sportForm.rgYellow)
                        .keyboardType(.numberPad)
                    TextField("Red cards",    text: $sportForm.rgRed)
                        .keyboardType(.numberPad)
                }
            }

        case .hyrox:
            Divider()
            FieldRowPlain {
                HStack {
                    TextField("Division (Open/Pro…)",  text: $sportForm.hyDivision)
                        .textFieldStyle(.plain)
                    TextField("Category (Men/Women…)", text: $sportForm.hyCategory)
                        .textFieldStyle(.plain)
                }
            }
            Divider()
            FieldRowPlain {
                TextField("Age group (e.g. 30–34)", text: $sportForm.hyAgeGroup)
                    .textFieldStyle(.plain)
            }
            Divider()
            FieldRowPlain {
                HStack {
                    TextField("Official time (sec)", text: $sportForm.hyOfficialTimeSec)
                        .keyboardType(.numberPad)
                    TextField("Penalty time (sec)",  text: $sportForm.hyPenaltyTimeSec)
                        .keyboardType(.numberPad)
                }
            }
            Divider()
            FieldRowPlain {
                HStack {
                    TextField("No reps",       text: $sportForm.hyNoReps)
                        .keyboardType(.numberPad)
                    TextField("Rank overall",  text: $sportForm.hyRankOverall)
                        .keyboardType(.numberPad)
                    TextField("Rank category", text: $sportForm.hyRankCategory)
                        .keyboardType(.numberPad)
                }
            }
            Divider()
            FieldRowPlain {
                HStack {
                    TextField("Avg HR", text: $sportForm.hyAvgHR)
                        .keyboardType(.numberPad)
                    TextField("Max HR", text: $sportForm.hyMaxHR)
                        .keyboardType(.numberPad)
                }
            }
            
        case .ski:
            Divider()
            FieldRowPlain {
                HStack {
                    TextField("Total distance (km)", text: $sportForm.skiTotalDistanceKm)
                        .keyboardType(.decimalPad)
                    TextField("Runs", text: $sportForm.skiRunsCount)
                        .keyboardType(.numberPad)
                }
            }

            Divider()
            FieldRowPlain {
                HStack {
                    TextField("Max speed (km/h)", text: $sportForm.skiMaxSpeedKmh)
                        .keyboardType(.decimalPad)
                    TextField("Avg speed (km/h)", text: $sportForm.skiAvgSpeedKmh)
                        .keyboardType(.decimalPad)
                }
            }

            Divider()
            FieldRowPlain {
                HStack {
                    TextField("Vertical drop (m)", text: $sportForm.skiVerticalDropM)
                        .keyboardType(.numberPad)
                    TextField("Moving time (sec)", text: $sportForm.skiMovingTimeSec)
                        .keyboardType(.numberPad)
                    TextField("Paused time (sec)", text: $sportForm.skiPausedTimeSec)
                        .keyboardType(.numberPad)
                }
            }

            Divider()
            FieldRowPlain {
                TextField("Resort name", text: $sportForm.skiResortName)
                    .textFieldStyle(.plain)
            }

            Divider()
            FieldRowPlain {
                TextField("Snow condition", text: $sportForm.skiSnowCondition)
                    .textFieldStyle(.plain)
            }

            Divider()
            FieldRowPlain {
                TextField("Weather", text: $sportForm.skiWeather)
                    .textFieldStyle(.plain)
            }
        }
    }
}
