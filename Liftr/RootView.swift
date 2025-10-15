import SwiftUI

enum Tab: Hashable {
  case home, search, add, ranking, profile
}

struct RootView: View {
  @EnvironmentObject var app: AppState
  @State private var selected: Tab = .home
  @State private var showAddSheet = false

  var body: some View {
    ZStack {
      TabView(selection: $selected) {
        HomeView()
          .tag(Tab.home)

        SearchView()
          .tag(Tab.search)

        // El tab .add no muestra contenido; lo gestionamos con el botón central
        Color.clear
          .tag(Tab.add)
          
        RankingView()
          .tag(Tab.ranking)

        ProfileGate()
          .tag(Tab.profile)
      }
      .onChange(of: selected) { old, new in
        if new == .add {
          selected = old // vuelve a la anterior
          showAddSheet = true
        }
      }
      .safeAreaInset(edge: .bottom) {    // deja hueco para la isla
        Color.clear.frame(height: 90)
      }

      // Tab bar “isla”
      VStack {
        Spacer()
        CustomTabBar(selected: $selected, onPlus: { showAddSheet = true })
          .padding(.horizontal, 16)
          .padding(.bottom, 10)
      }
      .ignoresSafeArea(.keyboard)
    }
    .sheet(isPresented: $showAddSheet) {
      AddWorkoutSheet()
    }
  }
}
