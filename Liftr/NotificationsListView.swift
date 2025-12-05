import SwiftUI

struct NotificationRow: Decodable, Identifiable {
    let id: Int
    let type: String
    let title: String
    let body: String?
    let created_at: Date
    let sent_at: Date?
    let sendError: String?
    var is_read: Bool?
    let data: [String: String]?
    
    enum CodingKeys: String, CodingKey {
        case id
        case type
        case title
        case body
        case created_at
        case sent_at
        case sendError = "send_error"
        case is_read
        case data
    }
}

struct NotificationsListView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    
    @State private var notifications: [NotificationRow] = []
    @State private var loading = false
    @State private var error: String?
    @State private var deletingAll = false
    @State private var showDeleteAllConfirm = false
    
    var body: some View {
        Group {
            if loading {
                ProgressView("Loading notifications…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            else if let error {
                VStack(spacing: 12) {
                    Text("Error loading notifications")
                        .font(.headline)
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            else if notifications.isEmpty {
                Text("You have no notifications yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            else {
                List {
                    ForEach(notifications) { n in
                        NavigationLink {
                            destinationView(for: n)
                                .task { await markAsRead(n) }   // 👈 ahora aquí
                        } label: {
                            HStack(alignment: .top, spacing: 8) {
                                if n.is_read != true {
                                    Circle()
                                        .fill(Color.red)
                                        .frame(width: 8, height: 8)
                                        .padding(.top, 8)
                                }
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(n.title)
                                        .font(.subheadline.weight(.semibold))
                                    
                                    if let body = n.body, !body.isEmpty {
                                        Text(body)
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }
                                    
                                    HStack {
                                        Text(shortType(n.type))
                                            .font(.caption2.weight(.semibold))
                                            .padding(.vertical, 3)
                                            .padding(.horizontal, 6)
                                            .background(
                                                Capsule()
                                                    .fill(Color.white.opacity(0.12))
                                            )
                                        
                                        Spacer()
                                        
                                        Text(relativeDate(n.created_at))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.clear)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                Task { await deleteNotification(n) }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("Notifications")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !notifications.isEmpty {
                    Button(role: .destructive) {
                        showDeleteAllConfirm = true
                    } label: {
                        Text("Delete all")
                    }
                    .disabled(loading || deletingAll)
                }
            }
        }
        .alert("Delete all notifications?", isPresented: $showDeleteAllConfirm) {
            Button("Delete all", role: .destructive) {
                Task { await deleteAllNotifications() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
        }
        .task { await loadNotifications() }
    }

    @ViewBuilder
    private func destinationView(for n: NotificationRow) -> some View {
        switch n.type {
        case "new_follower":
            if let followerId = n.data?["follower_id"],
               let uid = UUID(uuidString: followerId) {
                ProfileView(userId: uid)
                    .gradientBG()
            } else {
                Text("User not found")
            }

        case "workout_like",
             "workout_comment",
             "comment_reply",
             "comment_like",
             "added_as_participant":
            if let workoutIdStr = n.data?["workout_id"],
               let workoutId = Int(workoutIdStr) {

                if let ownerIdStr = n.data?["owner_id"],
                   let ownerId = UUID(uuidString: ownerIdStr) {
                    WorkoutDetailView(workoutId: workoutId, ownerId: ownerId)
                } else if let fallbackOwner = app.userId {
                    WorkoutDetailView(workoutId: workoutId, ownerId: fallbackOwner)
                } else {
                    Text("Workout not found")
                }

            } else {
                Text("Workout not found")
            }

        case "achievement_unlocked":
            if let uid = app.userId {
                AchievementsGridView(userId: uid, viewedUsername: "")
                    .gradientBG()
            } else {
                Text("Achievements")
            }

        default:
            VStack(spacing: 12) {
                Text(n.title)
                    .font(.headline)
                if let body = n.body {
                    Text(body)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding()
        }
    }
    
    private func deleteAllNotifications() async {
        guard let uid = app.userId else { return }
        await MainActor.run { deletingAll = true; error = nil }
        defer { Task { await MainActor.run { deletingAll = false } } }
        
        do {
            _ = try await SupabaseManager.shared.client
                .from("notifications")
                .delete()
                .eq("user_id", value: uid.uuidString)
                .execute()
            
            await MainActor.run {
                self.notifications = []
            }
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
            }
        }
    }
    
    private func loadNotifications() async {
        guard let uid = app.userId else { return }
        await MainActor.run { loading = true; error = nil }
        defer { Task { await MainActor.run { loading = false } } }
        
        do {
            let res = try await SupabaseManager.shared.client
                .from("notifications")
                .select("id,type,title,body,created_at,sent_at,send_error,is_read,data")
                .eq("user_id", value: uid.uuidString)
                .order("created_at", ascending: false)
                .limit(100)
                .execute()
            
            let rows = try JSONDecoder.supabase().decode([NotificationRow].self, from: res.data)
            await MainActor.run { self.notifications = rows }
            
        } catch {
            await MainActor.run { self.error = error.localizedDescription }
        }
    }
    
    private func markAsRead(_ n: NotificationRow) async {
        guard n.is_read != true else { return }

        struct UpdatePayload: Encodable {
            let is_read: Bool
            let read_at: String
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = .current

        let payload = UpdatePayload(
            is_read: true,
            read_at: formatter.string(from: Date())
        )

        do {
            _ = try await SupabaseManager.shared.client
                .from("notifications")
                .update(payload)
                .eq("id", value: n.id)
                .execute()

            await MainActor.run {
                if let idx = self.notifications.firstIndex(where: { $0.id == n.id }) {
                    self.notifications[idx].is_read = true
                }
            }
        } catch {
            print("[Notifications] markAsRead error:", error.localizedDescription)
        }
    }
    
    private func deleteNotification(_ n: NotificationRow) async {
        await MainActor.run { error = nil }
        
        do {
            _ = try await SupabaseManager.shared.client
                .from("notifications")
                .delete()
                .eq("id", value: n.id)
                .execute()
            
            await MainActor.run {
                self.notifications.removeAll { $0.id == n.id }
            }
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
            }
        }
    }
    
    private func shortType(_ t: String) -> String {
        switch t {
        case "new_follower":          return "Follower"
        case "workout_like":          return "Workout like"
        case "workout_comment":       return "Workout comment"
        case "comment_like":          return "Comment like"
        case "comment_reply":         return "Reply"
        case "added_as_participant":  return "Participant"
        case "achievement_unlocked":  return "Achievement"
        default:                      return t.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
    
    private func relativeDate(_ d: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: d, relativeTo: Date())
    }
}
