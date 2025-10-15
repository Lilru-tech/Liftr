import SwiftUI

struct RankingView: View {
  var body: some View {
    NavigationStack {
      List {
        Section("Top 5 Fuerza (volumen total)") {
          Label("1. Alex", systemImage: "medal.fill")
          Label("2. Sara", systemImage: "medal.fill")
          Label("3. David", systemImage: "medal.fill")
          Label("4. Laura", systemImage: "figure.strengthtraining.traditional")
          Label("5. Marcos", systemImage: "figure.run")
        }

        Section("Top 5 Cardio (km/h promedio)") {
          Label("1. Marta", systemImage: "flame.fill")
          Label("2. Alex", systemImage: "flame.fill")
          Label("3. Sara", systemImage: "flame.fill")
        }
      }
      .navigationTitle("Ranking")
    }
  }
}
