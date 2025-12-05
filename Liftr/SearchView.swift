import SwiftUI
import Supabase

struct SearchView: View {
    @EnvironmentObject var app: AppState
    @AppStorage("isPremium") private var isPremium: Bool = false
    @State private var query = ""
    @State private var results: [UserRow] = []
    @State private var loading = false
    @State private var error: String?
    @State private var searchTask: Task<Void, Never>? = nil

    private struct UserRow: Decodable, Identifiable {
        let user_id: UUID
        let username: String
        let avatar_url: String?
        var id: UUID { user_id }
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                TextField("Search users…", text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            .padding(12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)

            List {
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
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            
            if !isPremium {
                BannerAdView(adUnitID: "ca-app-pub-7676731162362384/7781347704")
                    .frame(height: 50)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }
        }
        .onChange(of: query) { _, newValue in
            searchTask?.cancel()
            searchTask = Task {
                try? await Task.sleep(nanoseconds: 250_000_000)
                if Task.isCancelled { return }
                await searchUsers(q: newValue)
            }
        }
        .onDisappear { searchTask?.cancel() }
    }

    private func searchUsers(q: String) async {
        let term = q.trimmingCharacters(in: .whitespacesAndNewlines)
        guard term.count >= 2 else {
            await MainActor.run {
                self.results = []
                self.loading = false
            }
            return
        }

        await MainActor.run { self.loading = true; self.error = nil }
        defer { Task { await MainActor.run { self.loading = false } } }

        do {
            let res = try await SupabaseManager.shared.client
                .from("profiles")
                .select("user_id, username, avatar_url")
                .ilike("username", pattern: "%\(term)%")
                .order("username", ascending: true)
                .limit(50)
                .execute()

            var rows = try JSONDecoder.supabase().decode([UserRow].self, from: res.data)

            if let myId = app.userId {
                rows.removeAll { $0.user_id == myId }
            }

            await MainActor.run { self.results = rows }
        } catch {
            await MainActor.run { self.error = error.localizedDescription }
        }
    }
}
