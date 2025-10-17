import Foundation
import Combine
import Supabase

final class AppState: ObservableObject {
  static let shared = AppState()

  @Published var isAuthenticated: Bool = false
  @Published var userId: UUID?

  private var authTask: Task<Void, Never>?

  private init() {
    listenAuth()
  }

  deinit {
    authTask?.cancel()
  }

  // Fuerza un refresco puntual (por si lo necesitas al abrir la app)
  @MainActor
  func refreshSession() async {
    do {
      let session = try await SupabaseManager.shared.client.auth.session
      self.userId = session.user.id
      self.isAuthenticated = true
    } catch {
      self.userId = nil
      self.isAuthenticated = false
    }
  }

  func signOut() {
    Task {
      try? await SupabaseManager.shared.client.auth.signOut()
    }
  }

  private func listenAuth() {
    authTask?.cancel()
    authTask = Task { [weak self] in
      guard let self else { return }

      // 1) Estado inicial (best-effort)
      if let session = try? await SupabaseManager.shared.client.auth.session {
        await MainActor.run {
          self.isAuthenticated = true
          self.userId = session.user.id
        }
      } else {
        await MainActor.run {
          self.isAuthenticated = false
          self.userId = nil
        }
      }

      // 2) Escuchar cambios en caliente
      for await state in SupabaseManager.shared.client.auth.authStateChanges {
        await MainActor.run {
            switch state.event {
            case .initialSession, .signedIn, .userUpdated, .tokenRefreshed:
              self.isAuthenticated = (state.session != nil)
              self.userId = state.session?.user.id

            case .signedOut, .passwordRecovery, .userDeleted:
              self.isAuthenticated = false
              self.userId = nil

            default:                      // <- cubre cualquier caso presente o futuro
              break
            }
        }
      }
    }
  }
}
