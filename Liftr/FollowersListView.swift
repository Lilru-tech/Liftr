import SwiftUI
import Supabase

struct FollowersListView: View {
  enum Mode { case followers, following }
  @EnvironmentObject var app: AppState

  let userId: UUID
  let mode: Mode

  @State private var query: String = ""
  @State private var users: [UserRow] = []
  @State private var loading = false
  @State private var error: String?
  @State private var myFollowing: Set<UUID> = []

  private struct UserRow: Decodable, Identifiable {
    let user_id: UUID
    let username: String
    let avatar_url: String?
    var id: UUID { user_id }
  }

  var title: String {
    switch mode { case .followers: return "Followers"; case .following: return "Following" }
  }

  var body: some View {
    VStack(spacing: 0) {
      List {
        Section {
          TextField("Search…", text: $query)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        }

        Section {
          if loading {
            ProgressView().frame(maxWidth: .infinity)
          } else if filtered.isEmpty {
            Text("No users found").foregroundStyle(.secondary)
          } else {
              ForEach(filtered) { row in
                HStack(spacing: 12) {
                  NavigationLink {
                    ProfileView(userId: row.user_id).gradientBG()
                  } label: {
                    HStack(spacing: 12) {
                      AvatarView(urlString: row.avatar_url)
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                      VStack(alignment: .leading, spacing: 2) {
                        Text("@\(row.username)")
                          .font(.body.weight(.semibold))
                      }
                    }
                  }
                  .buttonStyle(.plain)

                  Spacer()

                  if let me = app.userId, me != row.user_id {
                    followButton(for: row.user_id)
                      .buttonStyle(.bordered)
                      .controlSize(.small)
                  }
                }
                .contentShape(Rectangle())
              }
          }
        }
      }
      .listStyle(.insetGrouped)
      .scrollContentBackground(.hidden)
      .navigationTitle(title)
    }
    .gradientBG()
    .task { await load() }
    .onChange(of: query) { _, _ in
    }
  }

  private var filtered: [UserRow] {
    let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !q.isEmpty else { return users }
    return users.filter { $0.username.localizedCaseInsensitiveContains(q) }
  }
    
  private func load() async {
    let client = SupabaseManager.shared.client
    loading = true; defer { loading = false }

    do {
      let edgeCol = (mode == .followers) ? "follower_id" : "followee_id"
      let whereCol = (mode == .followers) ? "followee_id" : "follower_id"

      let edgeRes = try await client
        .from("follows")
        .select(edgeCol)
        .eq(whereCol, value: userId.uuidString)
        .limit(1000)
        .execute()

      struct EdgeRow: Decodable { let follower_id: UUID?; let followee_id: UUID? }
      let edges = try JSONDecoder.supabase().decode([EdgeRow].self, from: edgeRes.data)
      let ids: [UUID] = edges.compactMap { (mode == .followers) ? $0.follower_id : $0.followee_id }
      if ids.isEmpty {
        await MainActor.run { self.users = [] }
      } else {
        let pRes = try await client
          .from("profiles")
          .select("user_id, username, avatar_url")
          .in("user_id", values: ids.map { $0.uuidString })
          .order("username", ascending: true)
          .limit(1000)
          .execute()
        let rows = try JSONDecoder.supabase().decode([UserRow].self, from: pRes.data)

        await MainActor.run { self.users = rows }
      }

      if let me = app.userId {
        let myRes = try await client
          .from("follows")
          .select("followee_id")
          .eq("follower_id", value: me.uuidString)
          .limit(2000)
          .execute()
        struct Row: Decodable { let followee_id: UUID }
        let r = try JSONDecoder.supabase().decode([Row].self, from: myRes.data)
        await MainActor.run { self.myFollowing = Set(r.map { $0.followee_id }) }
      }
    } catch {
      await MainActor.run { self.error = error.localizedDescription }
    }
  }

  @ViewBuilder
  private func followButton(for other: UUID) -> some View {
    if myFollowing.contains(other) {
      Button("Unfollow") { Task { await unfollow(other) } }
        .buttonStyle(.bordered)
        .controlSize(.small)
    } else {
      Button("Follow") { Task { await follow(other) } }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
    }
  }

  private func follow(_ other: UUID) async {
    guard let me = app.userId else { return }
    do {
      _ = try await SupabaseManager.shared.client
        .from("follows")
        .insert(["follower_id": me.uuidString, "followee_id": other.uuidString])
        .execute()
        _ = await MainActor.run { myFollowing.insert(other) }
    } catch {
    }
  }

  private func unfollow(_ other: UUID) async {
    guard let me = app.userId else { return }
    do {
      _ = try await SupabaseManager.shared.client
        .from("follows")
        .delete()
        .eq("follower_id", value: me.uuidString)
        .eq("followee_id", value: other.uuidString)
        .execute()
        _ = await MainActor.run { myFollowing.remove(other) }
    } catch {
    }
  }
}
