import SwiftUI

struct CreateCompetitionView: View {
    @EnvironmentObject var app: AppState
    let opponentId: UUID

    @Environment(\.dismiss) private var dismiss
    @State private var loading = false
    @State private var error: String?
    @State private var checkingExisting = true
    @State private var existingCompetition: CompetitionRow?
    @State private var includeTimeLimit = true
    @State private var timeLimitDays: Int = 7
    @State private var includePerformanceGoal = true
    @State private var metric: CompetitionMetric = .workouts
    @State private var targetText: String = "10"

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color("bgTop"), Color("bgBottom")],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            if checkingExisting {
                ProgressView()
                    .padding(.top, 40)
            } else if let existing = existingCompetition {
                alreadyCompetingView(existing)
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
            } else {
                ScrollView {
                    VStack(spacing: 20) {
                    
                    HStack(spacing: 10) {
                        Image(systemName: "figure.fencing")
                        Text("Challenge")
                            .font(.headline)
                        Spacer()
                    }
                    
                    VStack(spacing: 18) {
                        
                        VStack(spacing: 18) {
                            
                            if let error {
                                Text(error)
                                    .foregroundStyle(.red)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Time limit")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                
                                Toggle("Enable time limit", isOn: $includeTimeLimit)
                                
                                if includeTimeLimit {
                                    Stepper(value: $timeLimitDays, in: 1...60) {
                                        Text("\(timeLimitDays) days")
                                    }
                                }
                            }
                            
                            Divider()
                            
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Performance goal")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                
                                Toggle("Enable performance goal", isOn: $includePerformanceGoal)
                                
                                if includePerformanceGoal {
                                    Picker("Metric", selection: $metric) {
                                        ForEach(CompetitionMetric.allCases, id: \.self) { m in
                                            Label(m.title, systemImage: m.systemImage).tag(m)
                                        }
                                    }
                                    
                                    TextField(targetPlaceholder, text: $targetText)
                                        .keyboardType(metric == .workouts ? .numberPad : .decimalPad)
                                        .textFieldStyle(.plain)
                                        .padding(10)
                                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(.white.opacity(0.14), lineWidth: 0.8)
                                        )
                                }
                                
                                Text("Allowed: time limit only, performance goal only, or both. Not allowed: multiple performance goals.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(20)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(.white.opacity(0.22), lineWidth: 0.8)
                        )
                        .shadow(color: .black.opacity(0.12), radius: 10, y: 6)
                        
                        Button {
                            Task { await create() }
                        } label: {
                            HStack {
                                Spacer()
                                if loading { ProgressView().tint(.white) }
                                Text("Send invitation")
                                    .fontWeight(.semibold)
                                Spacer()
                            }
                            .padding(.vertical, 12)
                            .background(
                                (!loading && isValid)
                                ? Color.blue
                                : Color.gray.opacity(0.5),
                                in: RoundedRectangle(cornerRadius: 14)
                            )
                            .foregroundStyle(.white)
                        }
                        .disabled(loading || !isValid)
                    }
                    
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
            }
            .scrollContentBackground(.hidden)
            .background(Color.clear)
        }
        }
        .navigationTitle("Challenge")
        .task { await checkExistingCompetition() }
    }

    private var targetPlaceholder: String {
        switch metric {
        case .workouts: return "Target workouts (e.g. 10)"
        case .calories: return "Target kcal (e.g. 2000)"
        case .score:    return "Target score (e.g. 5000)"
        }
    }

    private var isValid: Bool {
        if !includeTimeLimit && !includePerformanceGoal { return false }

        if includePerformanceGoal {
            let t = targetText
                .replacingOccurrences(of: ",", with: ".")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if Double(t) == nil { return false }
            if (Double(t) ?? 0) <= 0 { return false }
        }
        return true
    }
    
    private func checkExistingCompetition() async {
        guard let myId = app.userId else { return }
        await MainActor.run {
            checkingExisting = true
            existingCompetition = nil
        }

        do {
            let existing = try await CompetitionService.shared.fetchActiveOrPendingCompetitionBetween(me: myId, other: opponentId)
            await MainActor.run {
                existingCompetition = existing
                checkingExisting = false
            }
        } catch {
            await MainActor.run { checkingExisting = false }
        }
    }

    @ViewBuilder
    private func alreadyCompetingView(_ existing: CompetitionRow) -> some View {
        VStack(spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                Text("You already have a competition with this user")
                    .font(.headline)
                Spacer()
            }

            Text(existing.status == .active
                 ? "You can’t start a second competition with the same user while one is active."
                 : "There is already a pending invitation with this user.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("Want another competition? Challenge someone else 👀")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 10) {
                NavigationLink {
                    CompetitionsHubView(contextOpponentId: opponentId)
                        .gradientBG()
                } label: {
                    Text("View competitions")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button("Pick another user") {
                    dismiss()
                }
                .frame(maxWidth: .infinity)
                .buttonStyle(.bordered)
            }
        }
        .padding(20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(.white.opacity(0.22), lineWidth: 0.8)
        )
    }

    private func create() async {
        guard let myId = app.userId else { return }
        await MainActor.run { loading = true; error = nil }
        defer { Task { await MainActor.run { loading = false } } }

        do {
            let timeLimitAt: Date? = includeTimeLimit
                ? Calendar.current.date(byAdding: .day, value: timeLimitDays, to: Date())
                : nil

            let targetValue: Double? = includePerformanceGoal
                ? Double(targetText.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespacesAndNewlines))
                : nil

            let metricValue: CompetitionMetric? = includePerformanceGoal ? metric : nil

            _ = try await CompetitionService.shared.createCompetition(
                creatorId: myId,
                opponentId: opponentId,
                metric: metricValue,
                targetValue: targetValue,
                timeLimitAt: timeLimitAt,
                inviteHours: 48
            )

            dismiss()
        } catch {
            let msg = error.localizedDescription
            await MainActor.run {
                if msg.contains("ux_competitions_active_pair") || msg.contains("duplicate key value") {
                    self.error = "You already have an active competition with this user. Challenge someone else to start a new one."
                    Task { await checkExistingCompetition() }
                } else {
                    self.error = msg
                }
            }
        }
    }
}
