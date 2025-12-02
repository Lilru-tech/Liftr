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
    
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    private struct SportRow: Decodable {
        let id: Int
        let sport: String
        let duration_sec: Int?
        let score_for: Int?
        let score_against: Int?
        let match_result: String?
        let match_score_text: String?
        let location: String?
        let notes: String?
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
    
    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Color.clear
                    .gradientBG()
                    .ignoresSafeArea()
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
                .padding(.bottom, 140)
            }
                VStack {
                    Spacer()
                    if !showCountdown {
                        bottomControls
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
            }
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
    
    private func loadSport() async {
        do {
            let res = try await SupabaseManager.shared.client
                .from("sport_sessions")
                .select("id, sport, duration_sec, score_for, score_against, match_result, match_score_text, location, notes")
                .eq("workout_id", value: workoutId)
                .single()
                .execute()
            
            let row = try JSONDecoder.supabase().decode(SportRow.self, from: res.data)
            
            await MainActor.run {
                self.sportRow = row
                self.sportType = SportType(rawValue: row.sport) ?? .padel
                self.sportForm.sport = self.sportType
                
                if let secs = row.duration_sec, secs > 0 {
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
            } catch {
                print("Error loading hyrox stats: \(error)")
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
        }
    }
}
