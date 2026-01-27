import SwiftUI

enum JSONValue: Decodable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()

        if c.decodeNil() { self = .null; return }
        if let v = try? c.decode(Bool.self) { self = .bool(v); return }
        if let v = try? c.decode(Int.self) { self = .int(v); return }
        if let v = try? c.decode(Double.self) { self = .double(v); return }
        if let v = try? c.decode(String.self) { self = .string(v); return }
        if let v = try? c.decode([String: JSONValue].self) { self = .object(v); return }
        if let v = try? c.decode([JSONValue].self) { self = .array(v); return }

        throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unsupported JSONValue")
    }

    var stringValue: String? {
        switch self {
        case .string(let s): return s
        case .int(let i): return String(i)
        case .double(let d): return String(d)
        case .bool(let b): return String(b)
        default: return nil
        }
    }
}

struct NotificationRow: Decodable, Identifiable {
    let id: Int
    let type: String
    let title: String
    let body: String?
    let created_at: Date
    let sent_at: Date?
    let sendError: String?
    var is_read: Bool
    let data: [String: JSONValue]?

    enum CodingKeys: String, CodingKey {
        case id, type, title, body, created_at, sent_at, is_read, data
        case sendError = "send_error"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        id = try c.decode(Int.self, forKey: .id)
        type = try c.decode(String.self, forKey: .type)
        title = try c.decode(String.self, forKey: .title)
        body = try c.decodeIfPresent(String.self, forKey: .body)
        created_at = try c.decode(Date.self, forKey: .created_at)
        sent_at = try c.decodeIfPresent(Date.self, forKey: .sent_at)
        sendError = try c.decodeIfPresent(String.self, forKey: .sendError)
        is_read = (try? c.decode(Bool.self, forKey: .is_read)) ?? false
        data = try c.decodeIfPresent([String: JSONValue].self, forKey: .data)
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
    @State private var achievementsRefreshID = UUID()
    
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
                                .task { await markAsRead(n) }
                        } label: {
                            HStack(alignment: .top, spacing: 8) {
                                if !n.is_read {
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
            if let followerId = n.data?["follower_id"]?.stringValue,
               let uid = UUID(uuidString: followerId) {
                ProfileView(userId: uid).gradientBG()
            } else {
                Text("User not found")
            }

        case "workout_like",
             "workout_comment",
             "comment_reply",
             "comment_like",
             "added_as_participant":
            if let workoutIdStr = n.data?["workout_id"]?.stringValue,
               let workoutId = Int(workoutIdStr) {

                if let ownerIdStr = n.data?["owner_id"]?.stringValue,
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
                AchievementsFromNotificationView(userId: uid, viewedUsername: "", showsCloseButton: false)
                    .gradientBG()
            } else {
                Text("Achievements")
            }
            
        case "goal_completed", "goal_almost_done":
            if let uid = app.userId {
                GoalsView(userId: uid, viewedUsername: "")
                    .gradientBG()
            } else {
                Text("Goals")
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
        
        var resData: Data = Data()

        do {
            let res = try await SupabaseManager.shared.client
                .from("notifications")
                .select("id,type,title,body,created_at,sent_at,send_error,is_read,data")
                .eq("user_id", value: uid.uuidString)
                .order("created_at", ascending: false)
                .limit(100)
                .execute()

            resData = res.data

            let rows = try JSONDecoder.supabase().decode([NotificationRow].self, from: res.data)
            await MainActor.run { self.notifications = rows }

        } catch {
            if let decodingError = error as? DecodingError {
                print("[Notifications] DecodingError:", decodingError)
            } else {
                print("[Notifications] Error:", error)
            }

            if resData.isEmpty {
                print("[Notifications] Raw JSON: <empty>")
            } else if let jsonString = String(data: resData, encoding: .utf8) {
                print("[Notifications] Raw JSON:", jsonString)
            }

            await MainActor.run { self.error = error.localizedDescription }
        }
    }
    
    private func markAsRead(_ n: NotificationRow) async {
        guard !n.is_read else { return }

        struct UpdatePayload: Encodable {
            let is_read: Bool
            let read_at: String
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)

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
        case "goal_completed":        return "Goal"
        case "goal_almost_done":      return "Goal"
        default:                      return t.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
    
    private func relativeDate(_ d: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: d, relativeTo: Date())
    }
}
