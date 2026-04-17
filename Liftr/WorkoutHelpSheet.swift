import SwiftUI

struct WorkoutHelpSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {

                    Text("General information")
                        .font(.title2.weight(.semibold))

                    Text("How to start a live workout")
                        .font(.headline)

                    Text("""
            You can start a planned workout in live mode for Strength, Cardio, and Sport:

            • Strength — exercise-by-exercise flow with rest timers, sets, and reps.
            • Cardio — session timer, distance, and optional GPS tracking for supported activities.
            • Sport — session timer plus sport-specific details (for example scores or structured blocks such as Hyrox).

            Steps (all types):

            1) Create the workout as a Plan (Mode: Plan)
            2) Save it
            3) Open the planned workout from your workouts list
            4) Tap Start

            Tip: If you just want to log what you did after training, choose Mode: Add.
            """)
                    .font(.body)
                    .foregroundStyle(.secondary)

                    Text("Linked workouts (dual or group)")
                        .font(.headline)
                        .padding(.top, 6)

                    Text("""
            For planned Strength workouts you can train with someone else on one device:

            • Dual — you and one guest; each person has their own lane while you follow the same session.
            • Group — you and up to two guests (three people in total), each with their own lane.

            Before you start, you can choose who joins from the participants on the workout. Liftr creates linked copies so everyone’s work is saved to their own workout.

            The host can be any participant, not only the person who created the workout — open the planned workout on your phone and tap Start when you’re leading the session.

            Finish ends the linked session for everyone when you confirm.
            """)
                    .font(.body)
                    .foregroundStyle(.secondary)

                    Text("Calories")
                        .font(.headline)
                        .padding(.top, 6)

                    Text("""
            • To show calories, the workout must have BOTH a start time and an end time.
            • Calories are estimated and may not be 100% accurate.
            """)
                    .font(.body)
                    .foregroundStyle(.secondary)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
            .padding(18)
            .navigationBarTitleDisplayMode(.inline)
        }
        .gradientBG()
    }
}
