import SwiftUI

struct ProfileGate: View {
  @EnvironmentObject var app: AppState

  var body: some View {
    Group {
      if app.isAuthenticated {
        ProfileView()
      } else {
        AuthView()
      }
    }
  }
}

struct ProfileView: View {
  @EnvironmentObject var app: AppState

  var body: some View {
    NavigationStack {
      List {
        Section("Cuenta") {
          Text("User ID: \(app.userId?.uuidString ?? "–")")
        }
        Section {
          Button(role: .destructive) {
            Task { try? await SupabaseManager.shared.client.auth.signOut() }
          } label: { Text("Cerrar sesión") }
        }
      }
      .navigationTitle("Perfil")
    }
  }
}

struct AuthView: View {
  @State private var email = ""
  @State private var password = ""
  @State private var error: String?

  var body: some View {
    NavigationStack {
      Form {
        if let error { Text(error).foregroundStyle(.red) }
        TextField("Email", text: $email).textInputAutocapitalization(.never)
        SecureField("Contraseña", text: $password)
        Button("Crear cuenta / Entrar") { signInOrSignUp() }
      }
      .navigationTitle("Entrar")
    }
  }

  private func signInOrSignUp() {
    Task {
      do {
        // Intenta sign-in, si no existe, sign-up
        try await SupabaseManager.shared.client.auth.signIn(email: email, password: password)
      } catch {
        do {
          try await SupabaseManager.shared.client.auth.signUp(email: email, password: password)
        } catch {
          await MainActor.run { self.error = error.localizedDescription }
        }
      }
    }
  }
}

