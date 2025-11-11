import SwiftUI
import Supabase

struct NewConversationSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    let onStarted: (Int64) -> Void

    @State private var loading = false
    @State private var error: String?
    @State private var users: [Row] = []

    struct FollowRow: Decodable { let followee_id: UUID }
    struct Row: Decodable, Identifiable, Hashable {
        let user_id: UUID
        let username: String
        let avatar_url: String?
        var id: UUID { user_id }
    }

    var body: some View {
        NavigationStack {
            List(users) { u in
                HStack(spacing: 12) {
                    AvatarView(urlString: u.avatar_url).frame(width: 34, height: 34)
                    Text("@\(u.username)")
                    Spacer()
                }
                .contentShape(Rectangle())
                .onTapGesture { Task { await start(with: u.user_id) } }
                .listRowBackground(Color.clear)
            }
            .overlay {
                if loading { ProgressView() }
                else if users.isEmpty {
                    ContentUnavailableView("No follows yet",
                                           systemImage: "person.2",
                                           description: Text("Follow someone to start a chat."))
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .navigationTitle("New message")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .task { await loadUsers() }
    }

    private func loadUsers() async {
        guard let me = app.userId else { return }
        loading = true; defer { loading = false }
        do {
            // 1) ids que sigo
            let fRes = try await SupabaseManager.shared.client
                .from("follows")
                .select("followee_id")
                .eq("follower_id", value: me.uuidString)
                .limit(500)
                .execute()
            let fRows = try JSONDecoder.supabase().decode([FollowRow].self, from: fRes.data)
            let ids = fRows.map { $0.followee_id.uuidString }
            guard !ids.isEmpty else { users = []; return }

            // 2) perfiles de esos ids
            let pRes = try await SupabaseManager.shared.client
                .from("profiles")
                .select("user_id,username,avatar_url")
                .in("user_id", values: ids)
                .order("username", ascending: true)
                .execute()
            let rows = try JSONDecoder.supabase().decode([Row].self, from: pRes.data)
            users = rows
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func start(with other: UUID) async {
        do {
            let convId = try await ChatService.shared.startDirectConversation(with: other)
            onStarted(convId)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
