import SwiftUI

enum WorkoutRecommendationApply {
    case strength([StrengthRecommendationExercise])
    case cardio(CardioRecommendation)
    case sport(SportRecommendation)
}

struct WorkoutRecommendationFlowView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var app: AppState
    
    let workoutKind: WorkoutKind
    let catalog: [Exercise]
    let exerciseLanguage: ExerciseLanguage
    let onApply: (WorkoutRecommendationApply) -> Void
    
    @State private var source: RecommendationDataSource = .recentHistory
    @State private var strengthMode: StrengthSuggestionMode = .prioritizeUndertrainedMuscles
    
    private enum Phase {
        case questions
        case loading
        case resultStrength([StrengthRecommendationExercise])
        case resultCardio(CardioRecommendation)
        case resultSport(SportRecommendation)
    }
    
    @State private var phase: Phase = .questions
    @State private var errorMessage: String?
    @State private var showError = false
    
    var body: some View {
        GradientBackground {
            Group {
                switch phase {
                case .questions:
                    questionsView
                case .loading:
                    ProgressView("Building suggestion…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .resultStrength(let rows):
                    resultStrengthView(rows)
                case .resultCardio(let r):
                    resultCardioView(r)
                case .resultSport(let r):
                    resultSportView(r)
                }
            }
            .navigationTitle("Suggest workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .alert("Couldn’t load", isPresented: $showError, presenting: errorMessage) { _ in
                Button("OK", role: .cancel) {}
            } message: { msg in
                Text(msg)
            }
        }
    }
    
    private var dataSourcesForKind: [RecommendationDataSource] {
        switch workoutKind {
        case .sport:
            return RecommendationDataSource.allCases
        case .strength, .cardio:
            return RecommendationDataSource.allCases.filter { $0 != .hyrox && $0 != .hyroxRace }
        }
    }
    
    private var questionsView: some View {
        Form {
            Section {
                SectionCard {
                    Group {
                        Text("Uses your last 10 logged workouts of this type. Strength: weights from your latest sets with RPE (±2.5 kg). When RPE was easy we may add a set or a few reps if volume isn’t already high; when it was very hard we may trim reps or a set—otherwise we lean on weight changes.")
                        if workoutKind == .sport {
                            Text("For sport: Hyrox — mixed varies stations from your logs; Hyrox — race format follows competition order and standard distances. Otherwise we suggest session length and sport from your history or the catalog.")
                                .padding(.top, 6)
                        }
                    }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .listRowBackground(Color.clear)
            
            Section {
                SectionCard {
                    ForEach(Array(dataSourcesForKind.enumerated()), id: \.element.id) { idx, src in
                        if idx > 0 {
                            Divider().padding(.vertical, 6)
                        }
                        Button {
                            source = src
                        } label: {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(src.title)
                                    Text(src.detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.leading)
                                }
                                Spacer(minLength: 8)
                                if source == src {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            } header: {
                Text("DATA SOURCE").foregroundStyle(.secondary)
            }
            .listRowBackground(Color.clear)
            
            if workoutKind == .strength {
                Section {
                    SectionCard {
                        ForEach(Array(StrengthSuggestionMode.allCases.enumerated()), id: \.element.id) { idx, m in
                            if idx > 0 {
                                Divider().padding(.vertical, 6)
                            }
                            Button {
                                strengthMode = m
                            } label: {
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(m.title)
                                        Text(m.detail)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .multilineTextAlignment(.leading)
                                    }
                                    Spacer(minLength: 8)
                                    if strengthMode == m {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.blue)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } header: {
                    Text("STRENGTH SESSION").foregroundStyle(.secondary)
                }
                .listRowBackground(Color.clear)
            }
            
            Section {
                SectionCard {
                    Button {
                        Task { await runRecommendation() }
                    } label: {
                        Text("Generate")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(generateDisabled)
                }
            }
            .listRowBackground(Color.clear)
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .listRowBackground(Color.clear)
        .listSectionSpacing(8)
    }
    
    private var generateDisabled: Bool {
        workoutKind == .strength && catalog.isEmpty
    }
    
    @MainActor
    private func runRecommendation() async {
        guard let uid = app.userId else {
            errorMessage = WorkoutRecommendationError.notSignedIn.localizedDescription
            showError = true
            return
        }
        phase = .loading
        errorMessage = nil
        do {
            switch workoutKind {
            case .strength:
                let rows = try await WorkoutRecommendationService.recommendStrength(
                    userId: uid,
                    source: source,
                    mode: strengthMode,
                    catalog: catalog,
                    exerciseLanguage: exerciseLanguage
                )
                phase = .resultStrength(rows)
            case .cardio:
                let r = try await WorkoutRecommendationService.recommendCardio(userId: uid, source: source)
                phase = .resultCardio(r)
            case .sport:
                let r = try await WorkoutRecommendationService.recommendSport(userId: uid, source: source)
                phase = .resultSport(r)
            }
        } catch let e as WorkoutRecommendationError {
            errorMessage = e.localizedDescription
            showError = true
            phase = .questions
        } catch {
            errorMessage = error.localizedDescription
            showError = true
            phase = .questions
        }
    }
    
    private func resultStrengthView(_ rows: [StrengthRecommendationExercise]) -> some View {
        Form {
            Section {
                SectionCard {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { idx, ex in
                        if idx > 0 {
                            Divider().padding(.vertical, 6)
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Text(ex.displayName).font(.headline)
                            if let m = ex.musclePrimary, !m.isEmpty {
                                Text(m).font(.caption).foregroundStyle(.secondary)
                            }
                            ForEach(Array(groupedStrengthSetLines(ex.sets).enumerated()), id: \.offset) { _, line in
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text(line.count == 1 ? "1 set" : "\(line.count) sets")
                                    Spacer(minLength: 8)
                                    Text("\(line.reps) reps")
                                    Text(formatKg(line.weightKg))
                                    if let r = line.rpe {
                                        Text("RPE \(formatRpeDisplay(r))")
                                    }
                                    if let rs = line.restSec {
                                        Text("\(rs)s rest")
                                    }
                                }
                                .font(.subheadline)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } header: {
                Text("SUGGESTED").foregroundStyle(.secondary)
            }
            .listRowBackground(Color.clear)
            
            Section {
                SectionCard {
                    Button {
                        onApply(.strength(rows))
                        dismiss()
                    } label: {
                        Text("Apply to form")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    
                    Divider().padding(.vertical, 6)
                    
                    Button {
                        phase = .questions
                    } label: {
                        Text("Back to options")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }
            .listRowBackground(Color.clear)
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .listRowBackground(Color.clear)
        .listSectionSpacing(8)
    }
    
    private func formatKg(_ x: Double) -> String {
        if x == floor(x) { return "\(Int(x)) kg" }
        return String(format: "%.1f kg", x)
    }
    
    private func formatRpeDisplay(_ x: Double) -> String {
        if x == floor(x) { return String(Int(x)) }
        return String(format: "%.1f", x)
    }
    
    private func groupedStrengthSetLines(_ sets: [StrengthRecommendationSet]) -> [(count: Int, reps: Int, weightKg: Double, rpe: Double?, restSec: Int?)] {
        let sorted = sets.sorted { $0.setNumber < $1.setNumber }
        guard !sorted.isEmpty else { return [] }
        var out: [(Int, Int, Double, Double?, Int?)] = []
        var i = 0
        while i < sorted.count {
            let reps = sorted[i].reps
            let w = sorted[i].weightKg
            let rpeB = sorted[i].rpe
            let restB = sorted[i].restSec
            var count = 1
            var j = i + 1
            while j < sorted.count,
                  sorted[j].reps == reps,
                  abs(sorted[j].weightKg - w) < 0.02,
                  optionalRpeMatches(sorted[j].rpe, rpeB),
                  sorted[j].restSec == restB {
                count += 1
                j += 1
            }
            out.append((count, reps, w, rpeB, restB))
            i = j
        }
        return out
    }
    
    private func optionalRpeMatches(_ a: Double?, _ b: Double?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case let (x?, y?): return abs(x - y) < 0.02
        default: return false
        }
    }
    
    private func resultCardioView(_ r: CardioRecommendation) -> some View {
        Form {
            Section {
                SectionCard {
                    Text(r.rationale)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .listRowBackground(Color.clear)
            
            Section {
                SectionCard {
                    LabeledContent("Activity", value: r.activity.label)
                    Divider().padding(.vertical, 6)
                    LabeledContent("Duration", value: formatDuration(r.durationSec))
                    if let d = r.distanceKm {
                        Divider().padding(.vertical, 6)
                        let distValue = r.activity.usesSwimDistanceAndPace
                            ? CardioSwimDisplay.formatSwimDistance(km: d)
                            : String(format: "%.2f km", d)
                        LabeledContent("Distance", value: distValue)
                    }
                    if let h = r.avgHr {
                        Divider().padding(.vertical, 6)
                        LabeledContent("Avg HR", value: "\(h)")
                    }
                    if let h = r.maxHr {
                        Divider().padding(.vertical, 6)
                        LabeledContent("Max HR", value: "\(h)")
                    }
                    if r.activity.showsElevation, let m = r.elevationGainM {
                        Divider().padding(.vertical, 6)
                        LabeledContent("Elevation gain (m)", value: "\(m)")
                    }
                    if r.activity.showsIncline, let p = r.inclinePercent {
                        Divider().padding(.vertical, 6)
                        LabeledContent("Incline (%)", value: String(format: "%.1f", p))
                    }
                    if r.activity.showsCadenceRpm, let c = r.cadenceRpm {
                        Divider().padding(.vertical, 6)
                        LabeledContent("Cadence (rpm/spm)", value: "\(c)")
                    }
                    if r.activity.showsWatts, let w = r.wattsAvg {
                        Divider().padding(.vertical, 6)
                        LabeledContent("Avg watts", value: "\(w)")
                    }
                    if r.activity.showsSplit500m, let s = r.splitSecPer500m {
                        Divider().padding(.vertical, 6)
                        LabeledContent("Split (sec/500m)", value: "\(s)")
                    }
                    if r.activity.showsSwimFields {
                        if let laps = r.swimLaps {
                            Divider().padding(.vertical, 6)
                            LabeledContent("Laps", value: "\(laps)")
                        }
                        if let pl = r.poolLengthM {
                            Divider().padding(.vertical, 6)
                            LabeledContent("Pool length (m)", value: "\(pl)")
                        }
                        if let st = r.swimStyle, !st.isEmpty {
                            Divider().padding(.vertical, 6)
                            LabeledContent("Swim style", value: st)
                        }
                    }
                }
            }
            .listRowBackground(Color.clear)
            
            Section {
                SectionCard {
                    Button {
                        onApply(.cardio(r))
                        dismiss()
                    } label: {
                        Text("Apply to form")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    
                    Divider().padding(.vertical, 6)
                    
                    Button {
                        phase = .questions
                    } label: {
                        Text("Back to options")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }
            .listRowBackground(Color.clear)
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .listRowBackground(Color.clear)
        .listSectionSpacing(8)
    }
    
    private func formatDuration(_ sec: Int) -> String {
        let h = sec / 3600
        let m = (sec % 3600) / 60
        let s = sec % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }
    
    private func resultSportView(_ r: SportRecommendation) -> some View {
        Form {
            Section {
                SectionCard {
                    Text(r.rationaleText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .listRowBackground(Color.clear)
            
            Section {
                SectionCard {
                    switch r {
                    case .durationOnly(let durationMin, _):
                        LabeledContent("Session length", value: "\(durationMin) min")
                        Text("Pick any sport in the add form—this is only a time target.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 4)
                    case .hyrox(let durationMin, let exercises, _):
                        LabeledContent("Sport", value: SportType.hyrox.label)
                        Divider().padding(.vertical, 6)
                        LabeledContent("Duration", value: "\(durationMin) min")
                        if !exercises.isEmpty {
                            Divider().padding(.vertical, 6)
                            ForEach(Array(exercises.enumerated()), id: \.element.id) { idx, ex in
                                if idx > 0 {
                                    Divider().padding(.vertical, 6)
                                }
                                hyroxExerciseSummary(ex)
                            }
                        }
                    }
                }
            } header: {
                Text("SUGGESTED").foregroundStyle(.secondary)
            }
            .listRowBackground(Color.clear)
            
            Section {
                SectionCard {
                    Button {
                        onApply(.sport(r))
                        dismiss()
                    } label: {
                        Text("Apply to form")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    
                    Divider().padding(.vertical, 6)
                    
                    Button {
                        phase = .questions
                    } label: {
                        Text("Back to options")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }
            .listRowBackground(Color.clear)
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .listRowBackground(Color.clear)
        .listSectionSpacing(8)
    }
    
    @ViewBuilder
    private func hyroxExerciseSummary(_ ex: HyroxExerciseRecommendation) -> some View {
        let name = HyroxExerciseFormatting.label(
            code: ex.exerciseCode,
            displayName: ex.customDisplayName.isEmpty ? nil : ex.customDisplayName,
            notes: ex.notes
        )
        VStack(alignment: .leading, spacing: 6) {
            Text("\(ex.exerciseOrder). \(name)")
                .font(.headline)
            if let d = ex.distanceM {
                LabeledContent("Distance", value: "\(d) m")
            }
            if let r = ex.reps {
                LabeledContent("Reps", value: "\(r)")
            }
            if let w = ex.weightKg {
                LabeledContent("Weight", value: formatKg(w))
            }
            if let s = ex.durationSec {
                LabeledContent("Duration", value: formatDuration(s))
            }
            if let h = ex.heightCm {
                LabeledContent("Height", value: "\(h) cm")
            }
            if let i = ex.implementCount {
                LabeledContent("Implements", value: "\(i)")
            }
            if let n = ex.notes, !n.isEmpty {
                LabeledContent("Notes", value: n)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension SportRecommendation {
    var rationaleText: String {
        switch self {
        case .durationOnly(_, let rationale): return rationale
        case .hyrox(_, _, let rationale): return rationale
        }
    }
}
