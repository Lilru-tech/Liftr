import SwiftUI

enum Tab: Hashable { case home, search, add, ranking, profile }

struct RootView: View {
  @EnvironmentObject var app: AppState
  @State private var selected: Tab = .home
  @State private var showAddSheet = false
  @State private var showAuthAlert = false

  var body: some View {
    ZStack {
      TabView(selection: $selected) {
        HomeView().tag(Tab.home)
        SearchView().tag(Tab.search)
        Color.clear.tag(Tab.add)  // reservado
        RankingView().tag(Tab.ranking)
        ProfileGate().tag(Tab.profile)
      }
      .onChange(of: selected) { old, new in
        if new == .add {
          selected = old
          if app.isAuthenticated { showAddSheet = true } else { showAuthAlert = true }
        }
      }
      .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 90) }

      VStack {
        Spacer()
        CustomTabBar(
          selected: $selected,
          isAuthenticated: app.isAuthenticated,
          onPlus: { showAddSheet = true },
          onRequireAuth: { showAuthAlert = true }
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
      }
      .ignoresSafeArea(.keyboard)
    }
    .sheet(isPresented: $showAddSheet) { AddWorkoutSheet() }
    .alert("Necesitas iniciar sesión", isPresented: $showAuthAlert) {
      Button("Ir a Perfil") { selected = .profile }
      Button("Cancelar", role: .cancel) {}
    } message: {
      Text("Crea una cuenta o inicia sesión para registrar entrenos.")
    }
  }
}
