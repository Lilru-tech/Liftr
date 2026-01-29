import SwiftUI

struct CompetitionReviewsView: View {
    @EnvironmentObject var app: AppState
    @State private var loading = false
    @State private var rows: [CompetitionWorkoutRow] = []
    @State private var error: String?

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color("bgTop"), Color("bgBottom")],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {

                    if loading {
                        ProgressView()
                            .padding(.top, 40)

                    } else if rows.isEmpty {
                        Text("No workouts pending review")
                            .foregroundStyle(.secondary)
                            .padding(.top, 40)

                    } else {
                        reviewsCard
                    }

                    Color.clear.frame(height: 12)
                }
                .padding(.top, 12)
            }
        }
        .navigationTitle("Workout Reviews")
        .task { await load() }
        .refreshable { await load() }
        .background(Color.clear)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    private var reviewsCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { idx, row in

                VStack(alignment: .leading, spacing: 10) {

                    NavigationLink {
                        WorkoutDetailView(workoutId: row.workout_id, ownerId: row.workout_owner_id)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Workout from opponent")
                                    .font(.headline)

                                Text("Tap to view details")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    HStack {
                        Button("Reject") {
                            Task { await review(row, accept: false) }
                        }
                        .buttonStyle(.bordered)

                        Button("Accept") {
                            Task { await review(row, accept: true) }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)

                if idx < rows.count - 1 {
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
        .padding(.horizontal)
    }
    
    private func load() async {
        guard let uid = app.userId else { return }
        await MainActor.run { loading = true; error = nil }
        defer { Task { await MainActor.run { loading = false } } }

        do {
            rows = try await CompetitionService.shared.fetchPendingWorkoutReviews(for: uid)
        } catch {
            await MainActor.run { self.error = error.localizedDescription }
        }
    }

    private func review(_ row: CompetitionWorkoutRow, accept: Bool) async {
        do {
            try await CompetitionService.shared.reviewWorkout(
                competitionWorkoutId: row.id,
                accept: accept
            )
            await load()
        } catch {
            await MainActor.run { self.error = error.localizedDescription }
        }
    }
}
