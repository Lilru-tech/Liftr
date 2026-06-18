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
    .navigationDestination(item: Binding(
      get: { app.profileWorkoutDeepLink },
      set: { app.profileWorkoutDeepLink = $0 }
    )) { link in
      if let ownerId = link.ownerId {
        WorkoutDetailView(workoutId: link.workoutId, ownerId: ownerId)
          .gradientBG()
      } else {
        WorkoutFromNotificationLoaderView(workoutId: link.workoutId)
          .gradientBG()
      }
    }
    .onAppear {
      let branch = app.isAuthenticated ? "ProfileView" : "LoginView"
      AuthCallbackLogger.log(
        "ProfileGate showing \(branch) tab=\(app.selectedTab) pending=\(app.passwordRecoveryPending) authenticated=\(app.isAuthenticated)",
        source: "ProfileGate"
      )
      app.flushPendingProfileWorkoutIfNeeded()
    }
    .onChange(of: app.isAuthenticated) { _, isAuthenticated in
      if isAuthenticated {
        app.flushPendingProfileWorkoutIfNeeded()
      }
    }
  }
}
