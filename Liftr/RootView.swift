import SwiftUI

enum Tab: Hashable { case home, search, add, ranking, profile }

struct RootView: View {
    @EnvironmentObject var app: AppState
    @State private var showAuthAlert = false
    
    var body: some View {
        TabView(selection: $app.selectedTab) {
            NavigationStack { HomeView().gradientBG() }
                .tag(Tab.home)
                .tabItem { Label("Home", systemImage: "house.fill") }
            
            NavigationStack { SearchView().gradientBG() }
                .tag(Tab.search)
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
            
            NavigationStack {
                AddWorkoutSheet()
                    .gradientBG()
                    .id(app.addDraftKey)
            }
            .tag(Tab.add)
            .tabItem { Label("Add", systemImage: "plus.circle.fill") }
            
            NavigationStack { RankingView().gradientBG() }
                .tag(Tab.ranking)
                .tabItem { Label("Ranking", systemImage: "trophy.fill") }
            
            NavigationStack { ProfileGate().gradientBG() }
                .tag(Tab.profile)
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
        }
        .onChange(of: app.selectedTab) { old, new in
            if new == .add && !app.isAuthenticated {
                app.selectedTab = old
                showAuthAlert = true
            }
        }
        .alert("You need to log in", isPresented: $showAuthAlert) {
            Button("Go to Profile") { app.selectedTab = .profile }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Sign up or login to register your workouts.")
        }
    }
}
