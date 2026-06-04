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

    var intValue: Int? {
        switch self {
        case .int(let i): return i
        case .string(let s): return Int(s)
        case .double(let d): return Int(d)
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
    @State private var markingAllRead = false
    @State private var showDeleteAllConfirm = false
    @State private var achievementsRefreshID = UUID()
    @State private var resolvedOwnerId: UUID?
    @State private var resolvingOwner = false

    private var hasUnreadNotifications: Bool {
        notifications.contains { !$0.is_read }
    }

    private var bulkActionBusy: Bool {
        loading || deletingAll || markingAllRead
    }
    
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
                            notificationLabel(for: n)
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
                    Menu {
                        Button {
                            Task { await markAllAsRead() }
                        } label: {
                            Label("Mark all as read", systemImage: "envelope.open")
                        }
                        .disabled(!hasUnreadNotifications || bulkActionBusy)

                        Button(role: .destructive) {
                            showDeleteAllConfirm = true
                        } label: {
                            Label("Delete all", systemImage: "trash")
                        }
                        .disabled(bulkActionBusy)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .disabled(bulkActionBusy)
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
        case "meal_plan_invite":
            if let targetId = notificationUUID(n.data?["target_id"]) {
                NutritionMealPlanInviteDetailView(targetId: targetId)
                    .environmentObject(app)
                    .gradientBG()
            } else if let planId = notificationUUID(n.data?["plan_id"]) {
                NutritionMealPlanInviteDetailView(planId: planId)
                    .environmentObject(app)
                    .gradientBG()
            } else {
                Text("Invitation not found")
            }

        case "new_follower":
            if let followerId = n.data?["follower_id"]?.stringValue,
               let uid = UUID(uuidString: followerId) {
                ProfileView(userId: uid).gradientBG()
            } else {
                Text("User not found")
            }

        case "apple_health_cardio_imported",
             "workout_like",
             "workout_comment",
             "comment_reply",
             "comment_like",
             "comment_mention",
             "added_as_participant":
            if let workoutIdStr = n.data?["workout_id"]?.stringValue,
               let workoutId = Int(workoutIdStr) {

                if let ownerIdStr = n.data?["owner_id"]?.stringValue,
                   let ownerId = UUID(uuidString: ownerIdStr) {

                    WorkoutDetailView(workoutId: workoutId, ownerId: ownerId)

                } else if let resolvedOwnerId {

                    WorkoutDetailView(workoutId: workoutId, ownerId: resolvedOwnerId)

                } else {
                    VStack(spacing: 12) {
                        if resolvingOwner {
                            ProgressView("Opening workout…")
                        } else {
                            Text("Opening workout…")
                        }
                    }
                    .task {
                        guard !resolvingOwner else { return }
                        resolvingOwner = true
                        defer { resolvingOwner = false }

                        struct Row: Decodable { let user_id: UUID }

                        do {
                            let res = try await SupabaseManager.shared.client
                                .from("workouts")
                                .select("user_id")
                                .eq("id", value: workoutId)
                                .limit(1)
                                .execute()

                            if let raw = String(data: res.data, encoding: .utf8) {
                                print("🧪 [Notifications] resolve owner raw:", raw)
                            }

                            let rows = try JSONDecoder.supabase().decode([Row].self, from: res.data)
                            resolvedOwnerId = rows.first?.user_id

                        } catch {
                            print("❌ [Notifications] resolve owner error:", error)
                        }
                    }
                }

            } else {
                Text("Workout not found")
            }

        case "achievement_unlocked":
            if let uid = app.userId {
                AchievementsFromNotificationView(
                    userId: uid,
                    viewedUsername: "",
                    showsCloseButton: false,
                    openAchievementId: n.data?["achievement_id"]?.intValue
                )
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

        case "competition_invite",
             "competition_accepted",
             "competition_declined",
             "competition_cancelled",
             "competition_expired",
             "competition_result_win",
             "competition_result_lose",
             "competition_workout_accepted",
             "competition_workout_rejected":
            NavigationStack {
                CompetitionsHubView()
                    .gradientBG()
            }

        case "competition_workout_pending_review":
            NavigationStack {
                CompetitionReviewsView()
                    .gradientBG()
            }
            
        case "workout_kind_inactive":
            InactiveWorkoutNudgeDestinationView(
                workoutKindRaw: n.data?["workout_kind"]?.stringValue
            )
            .environmentObject(app)

        case "segment_you_are_first", "segment_lost_first":
            if let sidStr = n.data?["segment_id"]?.stringValue,
               let sid = UUID(uuidString: sidStr) {
                NavigationStack {
                    SegmentDetailView(segmentId: sid, onClose: nil)
                        .environmentObject(app)
                }
            } else {
                Text("Segment not found")
            }

        case "challenge_won", "challenge_won_weekly":
            if let raw = n.data?["challenge_instance_id"]?.stringValue,
               let iid = UUID(uuidString: raw) {
                NavigationStack {
                    WeeklyChallengeDetailView(instanceId: iid, onClose: nil)
                        .environmentObject(app)
                        .gradientBG()
                }
            } else {
                Text("Challenge not found")
            }

        case "dm_message":
            if let cid = dmConversationId(from: n.data) {
                DeepLinkedChatThread(conversationId: cid, senderId: dmSenderId(from: n.data))
                    .environmentObject(app)
                    .gradientBG()
            } else {
                Text("Conversation not found")
            }

        case "territory_capture_from_user", "territory_lost_to_user":
            if let workoutIdStr = n.data?["workout_id"]?.stringValue,
               let workoutId = Int(workoutIdStr) {
                let knownOwnerId: UUID? = {
                    if n.type == "territory_lost_to_user",
                       let other = n.data?["other_user_id"]?.stringValue {
                        return UUID(uuidString: other)
                    }
                    if n.type == "territory_capture_from_user" {
                        return app.userId
                    }
                    return nil
                }()

                if let knownOwnerId {
                    WorkoutDetailView(workoutId: workoutId, ownerId: knownOwnerId)
                } else if let resolvedOwnerId {
                    WorkoutDetailView(workoutId: workoutId, ownerId: resolvedOwnerId)
                } else {
                    VStack(spacing: 12) {
                        if resolvingOwner {
                            ProgressView("Opening workout…")
                        } else {
                            Text("Opening workout…")
                        }
                    }
                    .task {
                        guard !resolvingOwner else { return }
                        resolvingOwner = true
                        defer { resolvingOwner = false }

                        struct Row: Decodable { let user_id: UUID }

                        do {
                            let res = try await SupabaseManager.shared.client
                                .from("workouts")
                                .select("user_id")
                                .eq("id", value: workoutId)
                                .limit(1)
                                .execute()

                            let rows = try JSONDecoder.supabase().decode([Row].self, from: res.data)
                            resolvedOwnerId = rows.first?.user_id
                        } catch {
                            print("❌ [Notifications] resolve owner error:", error)
                        }
                    }
                }
            } else {
                Text("Workout not found")
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

    private func dmConversationId(from data: [String: JSONValue]?) -> Int64? {
        guard let v = data?["conversation_id"] else { return nil }
        switch v {
        case .string(let s): return Int64(s)
        case .int(let i): return Int64(i)
        case .double(let d): return Int64(d)
        default: return nil
        }
    }

    private func dmSenderId(from data: [String: JSONValue]?) -> UUID? {
        guard let s = data?["sender_id"]?.stringValue else { return nil }
        return UUID(uuidString: s)
    }

    @ViewBuilder
    private func defaultNotificationLabel(_ n: NotificationRow, isUnread: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            if isUnread {
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
                        .background(Capsule().fill(Color.white.opacity(0.12)))
                    Spacer()
                    Text(relativeDate(n.created_at))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func notificationLabel(for n: NotificationRow) -> some View {
        if n.type == "meal_plan_invite" {
            mealPlanInviteNotificationLabel(n, isUnread: !n.is_read)
        } else {
            defaultNotificationLabel(n, isUnread: !n.is_read)
        }
    }

    @ViewBuilder
    private func mealPlanInviteNotificationLabel(_ n: NotificationRow, isUnread: Bool) -> some View {
        let foodName = n.data?["food_name"]?.stringValue
        let mealSlot = n.data?["meal_slot"]?.stringValue
        HStack(alignment: .top, spacing: 10) {
            if isUnread {
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
                    .padding(.top, 10)
            }
            Image(systemName: "fork.knife.circle.fill")
                .font(.title2)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(n.title)
                    .font(.subheadline.weight(.semibold))
                if let foodName, !foodName.isEmpty {
                    Text(foodName)
                        .font(.footnote.weight(.medium))
                }
                if let body = n.body, !body.isEmpty {
                    Text(body)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text(mealSlot ?? "Meal plan")
                        .font(.caption2.weight(.semibold))
                        .padding(.vertical, 3)
                        .padding(.horizontal, 6)
                        .background(Capsule().fill(Color.white.opacity(0.12)))
                    Spacer()
                    Text(relativeDate(n.created_at))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 6)
    }

    private func notificationUUID(_ value: JSONValue?) -> UUID? {
        guard let raw = value?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        return UUID(uuidString: raw)
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
            await app.refreshUnreadNotificationsCount()
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
            }
        }
    }

    private func markAllAsRead() async {
        guard let uid = app.userId else { return }
        guard hasUnreadNotifications else { return }
        await MainActor.run { markingAllRead = true; error = nil }
        defer { Task { await MainActor.run { markingAllRead = false } } }

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
                .eq("user_id", value: uid.uuidString)
                .eq("is_read", value: false)
                .execute()

            await MainActor.run {
                for idx in self.notifications.indices {
                    self.notifications[idx].is_read = true
                }
            }
            await app.refreshUnreadNotificationsCount()
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
            await app.refreshUnreadNotificationsCount()

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
            await app.refreshUnreadNotificationsCount()
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
            await app.refreshUnreadNotificationsCount()
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
        case "comment_mention":       return "Mention"
        case "added_as_participant":  return "Participant"
        case "achievement_unlocked":  return "Achievement"
        case "goal_completed":        return "Goal"
        case "goal_almost_done":      return "Goal"
        case "competition_invite":                return "Competition"
        case "competition_accepted":              return "Competition"
        case "competition_declined":              return "Competition"
        case "competition_cancelled":             return "Competition"
        case "competition_expired":               return "Competition"
        case "competition_workout_pending_review":return "Workout review"
        case "competition_workout_accepted":      return "Workout review"
        case "competition_workout_rejected":      return "Workout review"
        case "competition_result_win":            return "Result"
        case "competition_result_lose":           return "Result"
        case "workout_kind_inactive":             return "Reminder"
        case "meal_plan_invite":                  return "Meal plan"
        case "apple_health_cardio_imported":      return "Apple Health"
        case "segment_you_are_first":             return "Segment"
        case "segment_lost_first":                return "Segment"
        case "challenge_won", "challenge_won_weekly": return "Challenge"
        case "territory_capture_from_user": return "Territory captured"
        case "territory_lost_to_user":      return "Territory lost"
        default:                      return t.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
    
    private func relativeDate(_ d: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: d, relativeTo: Date())
    }
}

private struct InactiveWorkoutNudgeDestinationView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    
    let workoutKindRaw: String?
    
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Opening add workout…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            let kind: WorkoutKind = {
                switch workoutKindRaw?.lowercased() {
                case "cardio": return .cardio
                case "sport": return .sport
                case "strength": return .strength
                default: return .strength
                }
            }()
            await MainActor.run {
                app.openAdd(with: AddWorkoutDraft(kind: kind))
                dismiss()
            }
        }
    }
}
