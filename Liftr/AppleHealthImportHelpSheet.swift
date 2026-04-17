import SwiftUI

struct AppleHealthImportHelpSheet: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Apple Health import")
                        .font(.title2.weight(.semibold))

                    Text("Apple HealthKit")
                        .font(.headline)

                    Text(
                        "This screen uses HealthKit (Apple’s health framework) to read workout samples from the Health app "
                            + "and copy them into Liftr as cardio workouts. Nothing is written back to Health from this import; "
                            + "granting access happens in the system permission sheet."
                    )
                    .font(.body)
                    .foregroundStyle(.secondary)

                    Text("How import works")
                        .font(.headline)
                        .padding(.top, 4)

                    Text(
                        "You choose a date range (or a quick preset), then tap Import workouts. "
                            + "Liftr looks in the Health app—including data from your Apple Watch if you use one—and "
                            + "creates matching sessions here as cardio workouts. Nothing is removed or changed in Health."
                    )
                    .font(.body)
                    .foregroundStyle(.secondary)

                    Text("What we import")
                        .font(.headline)
                        .padding(.top, 4)

                    Text(
                        "Runs, walks, hikes, outdoor bike rides, indoor cycling / stationary bike "
                            + "(when Apple marks them indoor or as an indoor cycle workout), swims, and rowing. "
                            + "Indoor walks and runs are saved as Treadmill. If Apple saved a GPS route, distance, or heart rate, we copy those in when they’re available."
                    )
                    .font(.body)
                    .foregroundStyle(.secondary)

                    Text("What we skip")
                        .font(.headline)
                        .padding(.top, 4)

                    Text(
                        "Strength training, HIIT, yoga, team sports, and every other activity type that isn’t in the import list—log those in Liftr yourself. "
                            + "Sessions you already imported are ignored so you don’t get duplicates."
                    )
                    .font(.body)
                    .foregroundStyle(.secondary)
                }
                .padding(18)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
                .padding(18)
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .gradientBG()
    }
}
