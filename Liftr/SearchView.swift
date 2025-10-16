import SwiftUI

struct SearchView: View {
  @State private var query = ""
  var body: some View {
    NavigationStack {
        GradientBackground {
          List {
            TextField("Buscar usuarios…", text: $query)
            Text("Resultados aparecerán aquí")
          }
          .scrollContentBackground(.hidden)
        }
        .navigationTitle("Buscar")
    }
  }
}
