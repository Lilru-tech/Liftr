import SwiftUI

enum Tab: Hashable {
  case home, search, add, profile
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
          .tabItem { Label("Home", systemImage: "house.fill") }

        SearchView()
          .tag(Tab.search)
          .tabItem { Label("Search", systemImage: "magnifyingglass") }

        // El tab .add no muestra contenido; lo gestionamos con el botón central
        Color.clear
          .tag(Tab.add)
          .tabItem { Label("", systemImage: "plus.circle") }

        ProfileGate()
          .tag(Tab.profile)
          .tabItem { Label("Profile", systemImage: "person.crop.circle") }
      }
      .onChange(of: selected) { old, new in
        if new == .add {
          selected = old // vuelve a la anterior
          showAddSheet = true
        }
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
