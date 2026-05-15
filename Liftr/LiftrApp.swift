import SwiftUI

@main
struct LiftrApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .onOpenURL { url in
                    AuthCallbackLogger.log("SwiftUI onOpenURL", url: url, source: "LiftrApp")
                    Task { await appState.handleAuthCallbackURL(url) }
                }
        }
    }
}
