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
    .onAppear {
      let branch = app.isAuthenticated ? "ProfileView" : "LoginView"
      AuthCallbackLogger.log(
        "ProfileGate showing \(branch) tab=\(app.selectedTab) pending=\(app.passwordRecoveryPending) authenticated=\(app.isAuthenticated)",
        source: "ProfileGate"
      )
    }
  }
}
