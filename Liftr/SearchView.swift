import SwiftUI

struct SearchView: View {
  @State private var query = ""
  var body: some View {
    NavigationStack {
      List {
        TextField("Buscar usuarios…", text: $query)
        Text("Resultados aparecerán aquí")
      }
      .navigationTitle("Buscar")
    }
  }
}
