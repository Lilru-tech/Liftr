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

  private func listenAuth() {
    authTask?.cancel()
    authTask = Task { [weak self] in
      guard let self else { return }

      // Estado inicial
      if let session = try? await SupabaseManager.shared.client.auth.session {
        await MainActor.run {
          self.isAuthenticated = true
          self.userId = session.user.id
        }
      }

      // Escuchar cambios de autenticación
      for await state in SupabaseManager.shared.client.auth.authStateChanges {
        await MainActor.run {
          switch state.event {
          case .initialSession, .signedIn, .userUpdated, .tokenRefreshed:
            self.isAuthenticated = (state.session != nil)
            self.userId = state.session?.user.id
          case .signedOut, .passwordRecovery:
            self.isAuthenticated = false
            self.userId = nil
          default:
            break
          }
        }
      }
    }
  }
}
