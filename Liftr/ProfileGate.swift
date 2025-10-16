import SwiftUI

struct ProfileGate: View {
  @EnvironmentObject var app: AppState

  var body: some View {
    Group {
      if app.isAuthenticated {
        ProfileView()
      } else {
        LoginView() // 👈 ahora mostramos la pantalla de login nueva
      }
    }
  }
}

struct ProfileView: View {
  @EnvironmentObject var app: AppState

  var body: some View {
    NavigationStack {
        GradientBackground {
            
            List {
                Section("Account") {
                    Text("User ID: \(app.userId?.uuidString ?? "–")")
                }
                Section {
                    Button(role: .destructive) {
                        app.signOut()   // ← usa el helper
                    } label: { Text("Sign out") }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Profile")
        }
    }
  }
}
