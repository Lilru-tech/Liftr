import SwiftUI

struct CompetitionDetailView: View {
    @EnvironmentObject var app: AppState

    let competition: CompetitionRow
    let goal: CompetitionGoalRow?
    let myId: UUID?
    let profilesById: [UUID: ProfileLiteRow]

    @State private var loading = false
    @State private var error: String?

    @State private var entries: [CompetitionWorkoutRow] = []
    @State private var workoutsById: [Int: WorkoutLiteRow] = [:]

    var body: some View {
        VStack(spacing: 12) {
            header

            if loading {
                ProgressView().padding(.top, 20)
            } else if let error {
                Text(error).foregroundStyle(.red).padding(.horizontal)
            } else if entries.isEmpty {
                Text("No workouts in this competition yet.")
                    .foregroundStyle(.secondary)
                    .padding(.top, 30)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Workouts")
                            .font(.headline)
                            .padding(.horizontal)

                        workoutsCard
                            .padding(.horizontal)
                    }
                    .padding(.top, 6)
                }
            }
        }
        .navigationTitle("Competition")
        .task { await load() }
        .refreshable { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                AvatarMini(urlString: profilesById[opponentId ?? UUID()]?.avatar_url)

                VStack(alignment: .leading, spacing: 2) {
                    Text(opponentName)
                        .font(.headline.weight(.semibold))
                    Text(goalTitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if competition.status == .active, let tl = goal?.time_limit_at {
                    Text(remainingLabel(until: tl))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal)
        .padding(.top, 6)
    }

    private var workoutsCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { idx, e in
                if let w = workoutsById[e.workout_id] {
                    NavigationLink {
                        WorkoutDetailView(workoutId: w.id, ownerId: e.workout_owner_id)
                    } label: {
                        WorkoutRowView(
                            entry: e,
                            workout: w,
                            ownerName: username(for: e.workout_owner_id)
                        )
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("Workout #\(e.workout_id)")
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                }

                if idx < entries.count - 1 {
                    Divider()
                        .opacity(0.25)
                        .padding(.leading, 14)
                }
            }
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.16), lineWidth: 0.8)
        )
    }
    
    private func load() async {
        await MainActor.run { loading = true; error = nil }
        defer { Task { await MainActor.run { loading = false } } }

        do {
            let e = try await CompetitionService.shared.fetchCompetitionWorkouts(competitionId: competition.id)
            let ids = Array(Set(e.map { $0.workout_id }))
            let w = try await CompetitionService.shared.fetchWorkoutsLite(ids: ids)

            await MainActor.run {
                entries = e
                workoutsById = w
            }
        } catch {
            await MainActor.run { self.error = error.localizedDescription }
        }
    }

    private var opponentId: UUID? {
        guard let myId else { return nil }
        return (competition.user_a == myId) ? competition.user_b : competition.user_a
    }

    private var opponentName: String {
        guard let oid = opponentId else { return "Opponent" }
        return profilesById[oid]?.username ?? "Opponent"
    }

    private func username(for uid: UUID) -> String {
        profilesById[uid]?.username ?? "User"
    }

    private var goalTitle: String {
        if goal?.metric == nil && goal?.time_limit_at != nil { return "Time limit only" }
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

    private func remainingLabel(until end: Date) -> String {
        let now = Date()
        if end <= now { return "Ended" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return "Ends \(formatter.localizedString(for: end, relativeTo: now))"
    }
}

private struct WorkoutRowView: View {
    let entry: CompetitionWorkoutRow
    let workout: WorkoutLiteRow
    let ownerName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(ownerName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(workout.title?.isEmpty == false ? workout.title! : (workout.kind ?? "Workout").capitalized)
                .font(.subheadline.weight(.semibold))

            HStack {
                Text(entry.status.uppercased())
                    .font(.caption2.weight(.semibold))
                    .padding(.vertical, 3)
                    .padding(.horizontal, 6)
                    .background(Capsule().fill(.white.opacity(0.12)))

                Spacer()

                Text(dateTime(workout.started_at))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }

    private func dateTime(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: d)
    }
}
