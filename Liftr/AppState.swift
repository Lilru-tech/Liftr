import Foundation
import Combine
import Supabase

final class AppState: ObservableObject {
    @Published var selectedTab: Tab = .home
    @Published var addDraft: AddWorkoutDraft?
    @Published var addDraftKey = UUID()
    
    enum NotificationDestination: Equatable {
        case none
        case followerProfile(userId: UUID)
        case workout(workoutId: Int, ownerId: UUID?)
        case achievements
        case goals(userId: UUID)
        case competitionsHub
        case competitionDetail(competitionId: Int)
        case competitionReviews
    }
    
    @Published var notificationDestination: NotificationDestination = .none
    @Published var pendingNotification: (id: Int?, type: String, data: [String: Any])?
    
    @MainActor
    func openAdd(with draft: AddWorkoutDraft?) {
        self.addDraft = draft
        self.addDraftKey = UUID()
        self.selectedTab = .add
    }
    static let shared = AppState()
    
    @Published var isAuthenticated: Bool = false
    @Published var userId: UUID?
    
    private var authTask: Task<Void, Never>?
    
    private init() {
        listenAuth()
    }
    
    deinit {
        authTask?.cancel()
    }
    
    @MainActor
    func refreshSession() async {
        do {
            let session = try await SupabaseManager.shared.client.auth.session
            self.userId = session.user.id
            self.isAuthenticated = true
        } catch {
            self.userId = nil
            self.isAuthenticated = false
        }
    }
    
    func signOut() {
        Task {
            try? await SupabaseManager.shared.client.auth.signOut()
        }
    }
    
    @MainActor
    func handlePushNotificationTap(notificationId: Int?, type: String, data: [String: Any]) {
        print("📩 [AppState] handlePushNotificationTap id=\(notificationId ?? -1) type=\(type) data=\(data)")
        pendingNotification = (notificationId, type, data)
    }
    
    @MainActor
    func processNotification(notificationId: Int?, type: String, data: [String: Any]) {
        print("📩 [AppState] processNotification id=\(notificationId ?? -1) type=\(type) data=\(data)")
        if let notificationId {
            Task {
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
                        .eq("id", value: notificationId)
                        .execute()
                } catch {
                    print("[Push] markAsRead error:", error.localizedDescription)
                }
            }
        }
        
        switch type {
        case "new_follower":
            print("📩 [AppState] routing to followerProfile")
            if let followerIdStr = data["follower_id"] as? String,
               let followerId = UUID(uuidString: followerIdStr) {
                notificationDestination = .followerProfile(userId: followerId)
            } else {
                print("⚠️ [AppState] follower_id not found or invalid in data:", data)
                notificationDestination = .none
            }
            
        case "workout_like",
             "workout_comment",
             "comment_reply",
             "comment_like",
             "added_as_participant":
            print("📩 [AppState] routing to workout")
            if let workoutIdStr = data["workout_id"] as? String,
               let workoutId = Int(workoutIdStr) {
                
                let ownerId: UUID?
                if let ownerIdStr = data["owner_id"] as? String {
                    ownerId = UUID(uuidString: ownerIdStr)
                } else {
                    ownerId = nil
                }
                notificationDestination = .workout(workoutId: workoutId, ownerId: ownerId)
            } else {
                print("⚠️ [AppState] workout_id missing/invalid in data:", data)
                notificationDestination = .none
            }
            
        case "achievement_unlocked":
            notificationDestination = .achievements
            
        case "goal_completed", "goal_almost_done":
            if let uid = self.userId {
                notificationDestination = .goals(userId: uid)
            } else {
                notificationDestination = .none
            }
            
        case "competition_invite",
             "competition_accepted",
             "competition_declined",
             "competition_cancelled",
             "competition_expired",
             "competition_result_win",
             "competition_result_lose":
            if let compIdStr = data["competition_id"] as? String,
               let compId = Int(compIdStr) {
                notificationDestination = .competitionDetail(competitionId: compId)
            } else if let compIdInt = data["competition_id"] as? Int {
                notificationDestination = .competitionDetail(competitionId: compIdInt)
            } else {
                notificationDestination = .competitionsHub
            }

        case "competition_workout_pending_review":
            notificationDestination = .competitionReviews

        case "competition_workout_accepted",
             "competition_workout_rejected":
            if let compIdStr = data["competition_id"] as? String,
               let compId = Int(compIdStr) {
                notificationDestination = .competitionDetail(competitionId: compId)
            } else if let compIdInt = data["competition_id"] as? Int {
                notificationDestination = .competitionDetail(competitionId: compIdInt)
            } else {
                notificationDestination = .competitionsHub
            }
            
        default:
            notificationDestination = .none
        }
    }
    
    private func listenAuth() {
        authTask?.cancel()
        authTask = Task { [weak self] in
            guard let self else { return }
            
            if let session = try? await SupabaseManager.shared.client.auth.session {
                await MainActor.run {
                    self.isAuthenticated = true
                    self.userId = session.user.id
                }
            } else {
                await MainActor.run {
                    self.isAuthenticated = false
                    self.userId = nil
                }
            }
            
            for await state in SupabaseManager.shared.client.auth.authStateChanges {
                await MainActor.run {
                    switch state.event {
                    case .initialSession, .signedIn, .userUpdated, .tokenRefreshed:
                        self.isAuthenticated = (state.session != nil)
                        self.userId = state.session?.user.id
                        
                    case .signedOut, .passwordRecovery, .userDeleted:
                        self.isAuthenticated = false
                        self.userId = nil
                        
                    default:
                        break
                    }
                }
            }
        }
    }
}
