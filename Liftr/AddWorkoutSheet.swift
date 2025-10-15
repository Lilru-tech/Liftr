import SwiftUI

struct AddWorkoutSheet: View {
  @Environment(\.dismiss) private var dismiss
  @State private var kind: String = "strength"
  @State private var title: String = ""
  @State private var note: String = ""

  var body: some View {
    NavigationStack {
      Form {
        Picker("Tipo", selection: $kind) {
          Text("Fuerza").tag("strength")
          Text("Cardio").tag("cardio")
          Text("Deporte").tag("sport")
        }
        TextField("Título", text: $title)
        TextField("Notas", text: $note)
      }
      .navigationTitle("Nuevo entreno")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancelar") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Guardar") { save() }
        }
      }
    }
  }

  private func save() {
    // Aquí conectarás con Supabase (insert en public.workouts)
    // Por ahora cerramos la sheet.
    dismiss()
  }
}
