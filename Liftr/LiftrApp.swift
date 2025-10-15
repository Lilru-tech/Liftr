import SwiftUI

@main
struct LiftrApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(AppState.shared)
        }
    }
}
