import SwiftUI

struct ProfileGate: View {
  @EnvironmentObject var app: AppState
  var body: some View {
    Group {
      if app.isAuthenticated {
        ProfileView()
      } else {
        LoginView()
      }
    }
  }
}
