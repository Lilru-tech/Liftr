import SwiftUI

struct ActiveWorkoutRecoveryLaunch: Identifiable, Equatable {
    let workoutId: Int
    let kind: ActiveWorkoutSessionCheckpoint.Kind
    let guestWorkoutId: Int?
    let guest2WorkoutId: Int?

    var id: String { "\(kind.rawValue)-\(workoutId)" }
}

struct ActiveWorkoutRecoveryOverlay: ViewModifier {
    @EnvironmentObject private var app: AppState
    @State private var pendingEntry: ActiveWorkoutSessionCheckpoint.Entry?
    @State private var showRecoveryAlert = false
    @State private var recoveryLaunch: ActiveWorkoutRecoveryLaunch?
    @State private var finishInFlight = false
    @State private var finishError: String?

    func body(content: Content) -> some View {
        content
            .task(id: app.isAuthenticated) {
                guard app.isAuthenticated else { return }
                guard let entry = await ActiveWorkoutSessionCheckpoint.findRecoverable() else { return }
                await MainActor.run {
                    pendingEntry = entry
                    showRecoveryAlert = true
                }
            }
            .alert(
                String(localized: "Unfinished workout"),
                isPresented: $showRecoveryAlert,
                presenting: pendingEntry
            ) { entry in
                Button(String(localized: "Resume")) {
                    resume(entry)
                }
                Button(String(localized: "Finish now")) {
                    Task { await finishNow(entry) }
                }
                Button(String(localized: "Discard"), role: .destructive) {
                    ActiveWorkoutSessionCheckpoint.clear()
                    pendingEntry = nil
                }
                Button(String(localized: "Cancel"), role: .cancel) {
                    pendingEntry = nil
                }
            } message: { entry in
                Text(recoveryMessage(for: entry))
            }
            .alert(
                String(localized: "Could not finish workout"),
                isPresented: Binding(
                    get: { finishError != nil },
                    set: { if !$0 { finishError = nil } }
                )
            ) {
                Button(String(localized: "OK"), role: .cancel) {}
            } message: {
                Text(finishError ?? "")
            }
            .fullScreenCover(item: $recoveryLaunch) { launch in
                recoveryActiveView(launch)
                    .environmentObject(app)
                    .gradientBG()
            }
    }

    private func recoveryMessage(for entry: ActiveWorkoutSessionCheckpoint.Entry) -> String {
        let relative = entry.savedAt.formatted(.relative(presentation: .named))
        return String(
            localized: "You have an unfinished \(entry.kindLabel()) workout from \(relative). \(entry.summaryLine())."
        )
    }

    private func resume(_ entry: ActiveWorkoutSessionCheckpoint.Entry) {
        let guest = entry.strength?.guestWorkoutId
        let guest2 = entry.strength?.guest2WorkoutId
        recoveryLaunch = ActiveWorkoutRecoveryLaunch(
            workoutId: entry.workoutId,
            kind: entry.kind,
            guestWorkoutId: guest,
            guest2WorkoutId: guest2
        )
        pendingEntry = nil
    }

    @MainActor
    private func finishNow(_ entry: ActiveWorkoutSessionCheckpoint.Entry) async {
        guard !finishInFlight else { return }
        finishInFlight = true
        defer { finishInFlight = false }
        if let err = await ActiveWorkoutRecoveryFinish.finishNow(entry: entry) {
            finishError = err
        } else {
            pendingEntry = nil
        }
    }

    @ViewBuilder
    private func recoveryActiveView(_ launch: ActiveWorkoutRecoveryLaunch) -> some View {
        switch launch.kind {
        case .strength:
            if let g2 = launch.guest2WorkoutId, let g1 = launch.guestWorkoutId {
                ActiveStrengthWorkoutView(
                    workoutId: launch.workoutId,
                    dualGuestWorkoutId: g1,
                    dualGuestAvatarURL: nil,
                    dualGuest2WorkoutId: g2,
                    dualGuest2AvatarURL: nil,
                    dualHostAvatarURL: nil
                )
            } else if let g1 = launch.guestWorkoutId {
                ActiveStrengthWorkoutView(
                    workoutId: launch.workoutId,
                    dualGuestWorkoutId: g1,
                    dualGuestAvatarURL: nil,
                    dualGuest2WorkoutId: nil,
                    dualGuest2AvatarURL: nil,
                    dualHostAvatarURL: nil
                )
            } else {
                ActiveStrengthWorkoutView(
                    workoutId: launch.workoutId,
                    dualGuestWorkoutId: nil,
                    dualGuestAvatarURL: nil,
                    dualGuest2WorkoutId: nil,
                    dualGuest2AvatarURL: nil,
                    dualHostAvatarURL: nil
                )
            }
        case .cardio:
            ActiveCardioWorkoutView(workoutId: launch.workoutId)
        case .sport:
            ActiveSportWorkoutView(workoutId: launch.workoutId)
        }
    }
}

extension View {
    func activeWorkoutRecoveryOverlay() -> some View {
        modifier(ActiveWorkoutRecoveryOverlay())
    }
}
