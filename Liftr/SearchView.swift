import SwiftUI
import Supabase

struct SearchView: View {
    @EnvironmentObject var app: AppState
  @State private var query = ""
    @State private var results: [UserRow] = []
    @State private var loading = false
    @State private var error: String?

    private struct UserRow: Decodable, Identifiable {
      let user_id: UUID
      let username: String
      let avatar_url: String?
      var id: UUID { user_id }
    }
  var body: some View {
            List {
              Section {
                TextField("Search users…", text: $query)
                  .textInputAutocapitalization(.never)
                  .autocorrectionDisabled()
              }

              Section {
                if loading { ProgressView().frame(maxWidth: .infinity) }
                ForEach(results, id: \.user_id) { row in
                  NavigationLink {
                    ProfileView(userId: row.user_id)
                          .gradientBG() 
                  } label: {
                    HStack(spacing: 12) {
                      AvatarView(urlString: row.avatar_url)
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                      Text("@\(row.username)")
                    }
                  }
                }
                if !loading && results.isEmpty && !query.isEmpty {
                  Text("No users found").foregroundStyle(.secondary)
                }
              }
            }
          .scrollContentBackground(.hidden)
        .onChange(of: query) { _, _ in
          Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            await searchUsers()
          }
        }
  }

    private func searchUsers() async {
      let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
      // si no hay query, no devolvemos nada
      if q.isEmpty {
        await MainActor.run { self.results = [] }
        return
      }

      loading = true; defer { loading = false }

      do {
        // Trae un lote (ahora sí tiene sentido; ya hay query)
        let res = try await SupabaseManager.shared.client
          .from("profiles")
          .select("user_id, username, avatar_url")
          .order("username", ascending: true)
          .limit(100)
          .execute()

        var rows = try JSONDecoder.supabase().decode([UserRow].self, from: res.data)

        rows = rows.filter { $0.username.localizedCaseInsensitiveContains(q) }

        if let myId = app.userId {
          rows.removeAll { $0.user_id == myId }
        }

        await MainActor.run { self.results = rows }
      } catch {
        await MainActor.run { self.error = error.localizedDescription }
      }
    }
}

