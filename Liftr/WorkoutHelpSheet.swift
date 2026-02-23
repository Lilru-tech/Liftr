import SwiftUI

struct WorkoutHelpSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {

                Text("General information")
                    .font(.title2.weight(.semibold))

                Text("How to start a Strength workout")
                    .font(.headline)

                Text("""
            To use the live Strength workout (with timers and set tracking):

            1) Create the workout as a Plan (Mode: Plan)
            2) Save it
            3) Open the planned workout from your workouts list
            4) Tap Start

            Tip: If you just want to log what you did after training, choose Mode: Add.
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

                Spacer(minLength: 0)
            }
            .padding(18)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
            .padding(18)
            .navigationBarTitleDisplayMode(.inline)
        }
        .gradientBG()
    }
}
