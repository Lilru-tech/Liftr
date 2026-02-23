import SwiftUI

struct CompetitionsHubView: View {
    @EnvironmentObject var app: AppState
    
    let contextOpponentId: UUID?
    
    init(contextOpponentId: UUID? = nil) {
        self.contextOpponentId = contextOpponentId
    }

    private enum HubTab: String, CaseIterable {
        case active = "Active"
        case pending = "Pending"
        case history = "History"
    }

    @State private var tab: HubTab = .active
    
    @State private var loading = false
    @State private var error: String?

    @State private var comps: [CompetitionRow] = []
    @State private var goalsByCompId: [Int: CompetitionGoalRow] = [:]
    @State private var profilesById: [UUID: ProfileLiteRow] = [:]
    @State private var progressByCompId: [Int: [UUID: CompetitionProgress]] = [:]
    
    struct CompetitionHistorySummary {
        let totalHistory: Int
        let finished: Int
        let wins: Int
        let losses: Int
        let draws: Int
        let winRate: Double
        let mostChallengedOpponentId: UUID?
        let mostChallengedOpponentName: String
        let mostChallengedOpponentAvatarURL: String?
        let bestRivalId: UUID?
        let bestRivalName: String
        let bestRivalAvatarURL: String?
        let bestRivalWinRateText: String
        let bestRivalRecordText: String
        let favoriteMetricLabel: String
        let avgDurationText: String
    }

    private var historySummary: CompetitionHistorySummary {
        guard let myId = app.userId else {
            return CompetitionHistorySummary(
                totalHistory: 0, finished: 0, wins: 0, losses: 0, draws: 0, winRate: 0,
                mostChallengedOpponentId: nil,
                mostChallengedOpponentName: "—",
                mostChallengedOpponentAvatarURL: nil,
                bestRivalId: nil,
                bestRivalName: "—",
                bestRivalAvatarURL: nil,
                bestRivalWinRateText: "—",
                bestRivalRecordText: "—",
                favoriteMetricLabel: "—",
                avgDurationText: "—"
            )
        }

        let history = comps.filter { [.finished, .declined, .cancelled, .expired].contains($0.status) }
        let finished = history.filter { $0.status == .finished }

        var wins = 0
        var losses = 0
        var draws = 0

        for c in finished {
            if let w = c.winner_user_id {
                if w == myId { wins += 1 } else { losses += 1 }
            } else {
                draws += 1
            }
        }

        let finishedCount = finished.count
        let winRate = finishedCount > 0 ? Double(wins) / Double(finishedCount) : 0

        var opponentCount: [UUID: Int] = [:]
        for c in history {
            let opp = (c.user_a == myId) ? c.user_b : c.user_a
            opponentCount[opp, default: 0] += 1
        }
        let mostOppId = opponentCount.max(by: { $0.value < $1.value })?.key
        let mostOppName = mostOppId.flatMap { profilesById[$0]?.username } ?? "—"
        let mostOppAvatar = mostOppId.flatMap { profilesById[$0]?.avatar_url }
        
        struct RivalAgg {
            var w: Int = 0
            var l: Int = 0
            var d: Int = 0
            var total: Int { w + l + d }
            var score: Double { total > 0 ? (Double(w) + 0.5 * Double(d)) / Double(total) : 0 } // win=1, draw=0.5
        }

        var rivalAgg: [UUID: RivalAgg] = [:]

        for c in finished {
            let opp = (c.user_a == myId) ? c.user_b : c.user_a
            var agg = rivalAgg[opp] ?? RivalAgg()

            if let winner = c.winner_user_id {
                if winner == myId { agg.w += 1 } else { agg.l += 1 }
            } else {
                agg.d += 1
            }

            rivalAgg[opp] = agg
        }

        let bestRivalPair = rivalAgg.max { a, b in
            if a.value.score != b.value.score { return a.value.score < b.value.score }
            return a.value.total < b.value.total
        }

        let bestRivalId = bestRivalPair?.key
        let bestAgg = bestRivalPair?.value

        let bestRivalName = bestRivalId.flatMap { profilesById[$0]?.username } ?? "—"
        let bestRivalAvatar = bestRivalId.flatMap { profilesById[$0]?.avatar_url }

        let bestRivalWinRateText: String = {
            guard let bestAgg else { return "—" }
            return "\(Int((bestAgg.score * 100).rounded()))%"
        }()

        let bestRivalRecordText: String = {
            guard let bestAgg else { return "—" }
            return "\(bestAgg.w)-\(bestAgg.l)-\(bestAgg.d)"
        }()

        var metricCount: [String: Int] = [:]
        for c in history {
            if let m = goalsByCompId[c.id]?.metric {
                metricCount[m, default: 0] += 1
            }
        }
        let favoriteMetricRaw = metricCount.max(by: { $0.value < $1.value })?.key
        let favoriteMetricLabel: String = {
            switch favoriteMetricRaw {
            case "workouts": return "Workouts"
            case "calories": return "Calories"
            case "score": return "Score"
            case nil: return "—"
            default: return favoriteMetricRaw ?? "—"
            }
        }()

        let durations: [TimeInterval] = finished.compactMap { c in
            guard let end = c.finished_at else { return nil }
            return end.timeIntervalSince(c.created_at)
        }
        let avgDuration: TimeInterval? = durations.isEmpty ? nil : (durations.reduce(0, +) / Double(durations.count))
        let avgDurationText = avgDuration.map(formatDuration) ?? "—"

        return CompetitionHistorySummary(
            totalHistory: history.count,
            finished: finishedCount,
            wins: wins,
            losses: losses,
            draws: draws,
            winRate: winRate,
            mostChallengedOpponentId: mostOppId,
            mostChallengedOpponentName: mostOppName,
            mostChallengedOpponentAvatarURL: mostOppAvatar,
            bestRivalId: bestRivalId,
            bestRivalName: bestRivalName,
            bestRivalAvatarURL: bestRivalAvatar,
            bestRivalWinRateText: bestRivalWinRateText,
            bestRivalRecordText: bestRivalRecordText,
            favoriteMetricLabel: favoriteMetricLabel,
            avgDurationText: avgDurationText
        )
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded())
        let days = s / 86400
        let hours = (s % 86400) / 3600
        let mins = (s % 3600) / 60

        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(mins)m" }
        return "\(max(mins, 1))m"
    }

    var body: some View {
        VStack(spacing: 12) {
            Picker("", selection: $tab) {
                ForEach(HubTab.allCases, id: \.self) { t in
                    Text(t.rawValue).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            if loading {
                ProgressView().padding(.top, 20)
            } else if let error {
                Text(error).foregroundStyle(.red).padding(.horizontal)
            } else {
                content
            }
        }
        .navigationTitle("Competitions")
        .toolbar {
            NavigationLink {
                CompetitionReviewsView()
                    .gradientBG()
            } label: {
                Image(systemName: "checkmark.shield")
            }
        }
        .task { await loadAll() }
        .refreshable { await loadAll() }
    }

    @ViewBuilder
    private var content: some View {
        let myId = app.userId
        
        let active = comps.filter { $0.status == .active }
        let pending = comps.filter { $0.status == .pending }
        let history = comps.filter { [.finished, .declined, .cancelled, .expired].contains($0.status) }

        let headToHead: [CompetitionRow] = {
            guard let opp = contextOpponentId else { return [] }
            return history.filter { c in
                (c.user_a == opp || c.user_b == opp) && (myId == c.user_a || myId == c.user_b)
            }
        }()

        let list: [CompetitionRow] = {
            switch tab {
            case .active: return active
            case .pending: return pending
            case .history: return history
            }
        }()

        ScrollView {
            LazyVStack(spacing: 12) {

                if tab == .history {
                    HistorySummaryCard(summary: historySummary)
                    .padding(.horizontal, 20)
                }

                if tab == .history, !headToHead.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Your history vs this user")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        ForEach(headToHead) { c in
                            CompetitionCard(
                                competition: c,
                                goal: goalsByCompId[c.id],
                                myId: myId,
                                profilesById: profilesById,
                                progressByCompId: progressByCompId,
                                onAccept: nil,
                                onDecline: nil,
                                onCancel: nil
                            )
                        }
                    }
                }

                if list.isEmpty {
                    Text(emptyText)
                        .foregroundStyle(.secondary)
                        .padding(.top, 30)
                } else {
                    ForEach(list) { c in
                        let acceptAction: (() -> Void)? = tab == .pending ? {
                            Task { await accept(c) }
                        } : nil
                        
                        let declineAction: (() -> Void)? = tab == .pending ? {
                            Task { await decline(c) }
                        } : nil
                        
                        let cancelAction: (() -> Void)? = tab == .pending ? {
                            Task { await cancel(c) }
                        } : nil

                        NavigationLink {
                            CompetitionDetailView(
                                competition: c,
                                goal: goalsByCompId[c.id],
                                myId: myId,
                                profilesById: profilesById
                            )
                            .gradientBG()
                        } label: {
                            CompetitionCard(
                                competition: c,
                                goal: goalsByCompId[c.id],
                                myId: myId,
                                profilesById: profilesById,
                                progressByCompId: progressByCompId,
                                onAccept: acceptAction,
                                onDecline: declineAction,
                                onCancel: cancelAction
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                Color.clear.frame(height: 10)
            }
            .padding(.top, 8)
        }
    }

    private var emptyText: String {
        switch tab {
        case .active: return "No active competitions"
        case .pending: return "No pending invitations"
        case .history: return "No competition history yet"
        }
    }

    private func loadAll() async {
        guard let uid = app.userId else { return }
        await MainActor.run { loading = true; error = nil }
        defer { Task { await MainActor.run { loading = false } } }

        do {
            await CompetitionService.shared.expirePendingIfNeeded()

            let rows = try await CompetitionService.shared.fetchCompetitions(for: uid)
            let ids = rows.map { $0.id }

            let goals = try await CompetitionService.shared.fetchGoals(for: ids)

            var userIds: [UUID] = []
            for c in rows {
                userIds.append(c.user_a)
                userIds.append(c.user_b)
            }
            let profs = try await CompetitionService.shared.fetchProfiles(userIds: userIds)

            let progress = try await CompetitionService.shared.fetchProgress(for: ids)

            await MainActor.run {
                comps = rows
                goalsByCompId = goals
                profilesById = profs
                progressByCompId = progress
            }
        } catch {
            await MainActor.run { self.error = error.localizedDescription }
        }
    }

    private func accept(_ c: CompetitionRow) async {
        do {
            try await CompetitionService.shared.acceptCompetition(competitionId: c.id)
            await loadAll()
        } catch {
            await MainActor.run { self.error = error.localizedDescription }
        }
    }

    private func decline(_ c: CompetitionRow) async {
        do {
            try await CompetitionService.shared.declineCompetition(competitionId: c.id)
            await loadAll()
        } catch {
            await MainActor.run { self.error = error.localizedDescription }
        }
    }

    private func cancel(_ c: CompetitionRow) async {
        do {
            try await CompetitionService.shared.cancelCompetition(competitionId: c.id)
            await loadAll()
        } catch {
            await MainActor.run { self.error = error.localizedDescription }
        }
    }
}

private struct CompetitionCard: View {
    let competition: CompetitionRow
    let goal: CompetitionGoalRow?
    let myId: UUID?
    let profilesById: [UUID: ProfileLiteRow]
    let progressByCompId: [Int: [UUID: CompetitionProgress]]

    let onAccept: (() -> Void)?
    let onDecline: (() -> Void)?
    let onCancel: (() -> Void)?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(.white.opacity(0.18), lineWidth: 0.8)
                )

            VStack(alignment: .leading, spacing: 10) {
                header

                if competition.status == .active {
                    progressBlock
                } else {
                    goalBlock
                }

                if let actions = actionsBlock {
                    actions
                }
                if competition.status == .pending,
                   let oppId = opponentId,
                   let myId = myId {
                    
                    Button("Block this user from competitions") {
                        Task {
                            try? await CompetitionService.shared.blockUser(me: myId, other: oppId)
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.red)
                }
            }
            .padding(12)
        }
        .padding(.horizontal)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            let oppId = opponentId
            AvatarMini(urlString: profilesById[oppId ?? UUID()]?.avatar_url)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(opponentName)
                    .font(.subheadline.weight(.semibold))
                Text(statusLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if competition.status == .pending {
                Text(expiresLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if competition.status == .active, let tl = goal?.time_limit_at {
                Text(remainingLabel(until: tl))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var goalBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Goal")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(goalText)
                .font(.footnote.weight(.semibold))

            if let tl = goal?.time_limit_at {
                Text("Time limit: \(dateTime(tl))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var progressBlock: some View {
        let byUser = progressByCompId[competition.id] ?? [:]
        let a = byUser[competition.user_a] ?? CompetitionProgress()
        let b = byUser[competition.user_b] ?? CompetitionProgress()

        return VStack(alignment: .leading, spacing: 8) {
            Text("Progress")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ProgressRow(
                name: profilesById[competition.user_a]?.username ?? "User A",
                isMe: competition.user_a == myId,
                p: a,
                metric: goalMetric,
                targetValue: goalTargetValue
            )

            ProgressRow(
                name: profilesById[competition.user_b]?.username ?? "User B",
                isMe: competition.user_b == myId,
                p: b,
                metric: goalMetric,
                targetValue: goalTargetValue
            )
        }
    }

    private var actionsBlock: AnyView? {
        guard competition.status == .pending else { return nil }

        let invitedId = competition.created_by == competition.user_a ? competition.user_b : competition.user_a
        let amInvited = (myId == invitedId)

        if amInvited {
            return AnyView(
                HStack(spacing: 10) {
                    Button("Decline") { onDecline?() }
                        .buttonStyle(.bordered)
                    Button("Accept") { onAccept?() }
                        .buttonStyle(.borderedProminent)
                }
            )
        } else if myId == competition.created_by {
            return AnyView(
                HStack {
                    Spacer()
                    Button("Cancel invitation") { onCancel?() }
                        .buttonStyle(.bordered)
                }
            )
        }
        return nil
    }

    private var opponentId: UUID? {
        guard let myId else { return nil }
        return (competition.user_a == myId) ? competition.user_b : competition.user_a
    }

    private var opponentName: String {
        guard let oid = opponentId else { return "Opponent" }
        return profilesById[oid]?.username ?? "Opponent"
    }

    private var statusLabel: String {
        competition.status.rawValue.capitalized
    }

    private var expiresLabel: String {
        "Expires: \(dateTime(competition.invite_expires_at))"
    }

    private var goalText: String {
        if goal?.metric == nil && goal?.time_limit_at != nil {
            return "Time limit only"
        }
        if let m = goal?.metric {
            let tv = NSDecimalNumber(decimal: (goal?.target_value ?? 0)).doubleValue
            switch m {
            case "workouts": return "First to \(Int(tv.rounded())) workouts"
            case "calories": return "First to \(Int(tv.rounded())) kcal"
            case "score":    return "First to \(Int(tv.rounded())) score"
            default:         return "Goal"
            }
        }
        return "Goal"
    }

    private var goalMetric: CompetitionMetric? {
        guard let m = goal?.metric else { return nil }
        return CompetitionMetric(rawValue: m)
    }
    
    private var goalTargetValue: Double? {
        guard let tv = goal?.target_value else { return nil }
        return NSDecimalNumber(decimal: tv).doubleValue
    }
    
    private func remainingLabel(until end: Date) -> String {
        let now = Date()
        if end <= now { return "Ended" }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return "Ends \(formatter.localizedString(for: end, relativeTo: now))"
    }

    private func dateTime(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: d)
    }
}

private struct ProgressRow: View {
    let name: String
    let isMe: Bool
    let p: CompetitionProgress
    let metric: CompetitionMetric?
    let targetValue: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(isMe ? "\(name) (you)" : name)
                    .font(.footnote.weight(.semibold))
                Spacer()
                Text(valueText)
                    .font(.footnote.weight(.bold))
                    .monospacedDigit()
            }

            if let pct = progressRatio {
                HStack(spacing: 8) {
                    ProgressView(value: pct, total: 1.0)
                        .tint(isMe ? .blue : .white.opacity(0.55))

                    Text("\(Int((pct * 100).rounded()))%")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
    }

    private var valueText: String {
        guard let metric else {
            return "\(p.workoutsCount) w · \(Int(p.caloriesTotal.rounded())) kcal · \(Int(p.scoreTotal.rounded()))"
        }
        switch metric {
        case .workouts:
            return "\(p.workoutsCount) workouts"
        case .calories:
            return "\(Int(p.caloriesTotal.rounded())) kcal"
        case .score:
            return "\(Int(p.scoreTotal.rounded()))"
        }
    }
    
    private var progressRatio: Double? {
        guard let metric, let targetValue, targetValue > 0 else { return nil }

        let current: Double
        switch metric {
        case .workouts:
            current = Double(p.workoutsCount)
        case .calories:
            current = p.caloriesTotal
        case .score:
            current = p.scoreTotal
        }

        return min(max(current / targetValue, 0), 1)
    }
}

private struct HistorySummaryCard: View {
    let summary: CompetitionsHubView.CompetitionHistorySummary

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {

            HStack {
                Text("Summary")
                    .font(.headline)
                Spacer()
                Text("\(Int((summary.winRate * 100).rounded()))% win")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            HStack(spacing: 12) {
                StatPill(title: "Competitions", value: "\(summary.totalHistory)")
                StatPill(title: "Finished", value: "\(summary.finished)")
                StatPill(title: "W-L-D", value: "\(summary.wins)-\(summary.losses)-\(summary.draws)")
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Most challenged")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Spacer()

                    HStack(spacing: 8) {
                        AvatarMini(urlString: summary.mostChallengedOpponentAvatarURL)
                        Text(summary.mostChallengedOpponentName)
                            .font(.caption.weight(.semibold))
                    }
                }
                
                HStack {
                    Text("Best rival")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Spacer()

                    HStack(spacing: 8) {
                        AvatarMini(urlString: summary.bestRivalAvatarURL)
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(summary.bestRivalName)
                                .font(.caption.weight(.semibold))
                            Text("\(summary.bestRivalWinRateText) · \(summary.bestRivalRecordText)")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }

                HStack {
                    Text("Favorite metric")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(summary.favoriteMetricLabel)
                        .font(.caption.weight(.semibold))
                }

                HStack {
                    Text("Avg duration")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(summary.avgDurationText)
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                }
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.16), lineWidth: 0.8)
        )
    }
}

private struct StatPill: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
