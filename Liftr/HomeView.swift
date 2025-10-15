import SwiftUI

struct HomeView: View {
  var body: some View {
    NavigationStack {
      List {
        Section("Tus últimos entrenos") {
          Text("Back Squat 3x5 @80kg")
          Text("Easy Run 5km")
        }
        Section("Amigos") {
          Text("Alex • Bench PR 100kg")
          Text("Sara • 7km en 38:20")
        }
      }
    }
  }
}
