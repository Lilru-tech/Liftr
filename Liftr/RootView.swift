import SwiftUI

enum Tab: Hashable { case home, search, add, ranking, profile }

struct RootView: View {
  @EnvironmentObject var app: AppState
  @State private var selected: Tab = .home
  @State private var showAddSheet = false
  @State private var showAuthAlert = false

  var body: some View {
    NavigationStack {
      TabView(selection: $selected) {
        HomeView()
          .gradientBG() // 👈 aplica el fondo aquí
          .tag(Tab.home)
          .tabItem { Label("Home", systemImage: "house.fill") }

        SearchView()
          .gradientBG()
          .tag(Tab.search)
          .tabItem { Label("Search", systemImage: "magnifyingglass") }

        Color.clear
          .tag(Tab.add)
          .tabItem { Label("Add", systemImage: "plus.circle.fill") }

        RankingView()
          .gradientBG()
          .tag(Tab.ranking)
          .tabItem { Label("Ranking", systemImage: "trophy.fill") }

        ProfileGate()
          .gradientBG()
          .tag(Tab.profile)
          .tabItem { Label("Profile", systemImage: "person.crop.circle") }
      }
      .onChange(of: selected) { old, new in
        if new == .add {
          selected = old
          app.isAuthenticated ? (showAddSheet = true) : (showAuthAlert = true)
        }
      }
      .sheet(isPresented: $showAddSheet) { AddWorkoutSheet() }
      .alert("Necesitas iniciar sesión", isPresented: $showAuthAlert) {
        Button("Ir a Perfil") { selected = .profile }
        Button("Cancelar", role: .cancel) {}
      } message: { Text("Crea una cuenta o inicia sesión para registrar entrenos.") }
    }
  }
}
