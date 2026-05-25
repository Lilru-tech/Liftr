import Foundation
import Combine
import SwiftUI
import Supabase
import UIKit
import CoreLocation

final class AppState: ObservableObject {
    @Published var selectedTab: Tab = .home
    @Published var addDraft: AddWorkoutDraft?
    @Published var addDraftKey = UUID()
    
    enum NotificationDestination: Equatable {
        case none
        case followerProfile(userId: UUID)
        case workout(workoutId: Int, ownerId: UUID?)
        case segmentDetail(segmentId: UUID)
        case achievements
        case goals(userId: UUID)
        case competitionsHub
        case competitionDetail(competitionId: Int)
        case competitionReviews
        case challengeWeekly(instanceId: UUID)
        case directMessage(conversationId: Int64, senderUserId: UUID?)
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
    @Published private(set) var isPremium: Bool = false
    @Published var userId: UUID?
    @Published var passwordRecoveryPending: Bool = false
    @Published var authCallbackError: String?
    
    @Published private(set) var tabBarProfileAvatar: UIImage?
    private var tabBarAvatarURLString: String?
    private static let tabBarAvatarPointDiameter: CGFloat = 26
    @Published private(set) var unreadNotificationsCount: Int = 0
    @Published private(set) var unreadChatMessagesCount: Int = 0
    @Published var territoryCaptureToast: String?
    @Published var territoryReferenceCoordinate: CLLocationCoordinate2D?
    
    private var authTask: Task<Void, Never>?
    private let chatInboxRealtime = ChatInboxRealtime()
    private var chatInboxRealtimeUserId: UUID?
    private var lastHandledAuthCallbackKey: String?
    private var lastHandledAuthCallbackAt: Date?
    private var isHandlingAuthCallback = false

    private init() {
        listenAuth()
    }
    
    deinit {
        authTask?.cancel()
    }
    
    @MainActor
    func preparePasswordRecoveryFromAuthCallback() {
        passwordRecoveryPending = true
        isAuthenticated = false
        Task { @MainActor in
            await stopChatUnreadRealtime()
        }
        withAnimation {
            selectedTab = .profile
        }
        authCallbackError = nil
        AuthCallbackLogger.log(
            "preparePasswordRecovery pending=\(passwordRecoveryPending) tab=\(selectedTab) authenticated=\(isAuthenticated)",
            source: "AppState"
        )
    }

    @MainActor
    func clearAuthCallbackError() {
        authCallbackError = nil
    }

    @MainActor
    func handleAuthCallbackURL(_ url: URL) async {
        AuthCallbackLogger.log("handleAuthCallbackURL entered \(AuthCallbackLogger.describeMatch(url))", url: url, source: "AppState")
        guard AuthRedirect.isAuthCallback(url) else {
            AuthCallbackLogger.log("ignored: URL did not match auth callback", url: url, source: "AppState")
            return
        }
        if isHandlingAuthCallback {
            AuthCallbackLogger.log("skipped: already handling auth callback", url: url, source: "AppState")
            return
        }
        let dedupeKey = url.absoluteString
        if lastHandledAuthCallbackKey == dedupeKey,
           let lastHandledAuthCallbackAt,
           Date().timeIntervalSince(lastHandledAuthCallbackAt) < 3 {
            AuthCallbackLogger.log("skipped duplicate within 3s", url: url, source: "AppState")
            return
        }
        isHandlingAuthCallback = true
        lastHandledAuthCallbackKey = dedupeKey
        lastHandledAuthCallbackAt = Date()
        defer { isHandlingAuthCallback = false }
        preparePasswordRecoveryFromAuthCallback()
        do {
            AuthCallbackLogger.log("exchanging PKCE code via session(from:)", source: "AppState")
            let session = try await SupabaseManager.shared.client.auth.session(from: url)
            userId = session.user.id
            passwordRecoveryPending = true
            isAuthenticated = false
            AuthCallbackLogger.log(
                "exchange succeeded userId=\(session.user.id.uuidString) pending=\(passwordRecoveryPending) tab=\(selectedTab)",
                source: "AppState"
            )
        } catch {
            authCallbackError = error.localizedDescription
            passwordRecoveryPending = false
            isAuthenticated = false
            userId = nil
            AuthCallbackLogger.log("exchange failed: \(error.localizedDescription)", source: "AppState")
        }
    }

    @MainActor
    func completePasswordRecovery() {
        passwordRecoveryPending = false
        authCallbackError = nil
        withAnimation {
            selectedTab = .home
        }
        Task { @MainActor in
            if let session = try? await SupabaseManager.shared.client.auth.session {
                userId = session.user.id
                isAuthenticated = true
            }
            await refreshTabBarProfileAvatarFromServer()
            await refreshUnreadNotificationsCount()
            if let userId {
                await startChatUnreadRealtimeIfNeeded(for: userId)
            }
        }
    }

    @MainActor
    func refreshSession() async {
        do {
            let session = try await SupabaseManager.shared.client.auth.session
            self.userId = session.user.id
            self.isAuthenticated = true
            await refreshTabBarProfileAvatarFromServer()
            await refreshUnreadNotificationsCount()
            await startChatUnreadRealtimeIfNeeded(for: session.user.id)
        } catch {
            self.userId = nil
            self.isAuthenticated = false
            clearTabBarProfileAvatar()
            unreadNotificationsCount = 0
            await stopChatUnreadRealtime()
        }
    }
    
    @MainActor
    func refreshUnreadNotificationsCount() async {
        guard let uid = userId else {
            unreadNotificationsCount = 0
            return
        }
        do {
            let res = try await SupabaseManager.shared.client
                .from("notifications")
                .select("id", head: true, count: .exact)
                .eq("user_id", value: uid.uuidString)
                .eq("is_read", value: false)
                .execute()
            unreadNotificationsCount = res.count ?? 0
        } catch {
            unreadNotificationsCount = 0
        }
    }

    @MainActor
    func refreshUnreadChatMessagesCount() async {
        guard userId != nil else {
            unreadChatMessagesCount = 0
            return
        }
        do {
            let list = try await ChatService.fetchConversations(limit: 100)
            unreadChatMessagesCount = list.reduce(0) { $0 + $1.unread_count }
        } catch {
            unreadChatMessagesCount = 0
        }
    }
    
    @MainActor
    func clearTabBarProfileAvatar() {
        tabBarAvatarURLString = nil
        tabBarProfileAvatar = nil
    }
    
    @MainActor
    func syncTabBarProfileAvatar(urlString: String?) async {
        let trimmed = urlString?.trimmingCharacters(in: .whitespacesAndNewlines)
        let effective: String? = (trimmed?.isEmpty == false) ? trimmed : nil
        
        if effective == tabBarAvatarURLString,
           let img = tabBarProfileAvatar,
           img.renderingMode == .alwaysOriginal,
           abs(img.size.width - Self.tabBarAvatarPointDiameter) < 0.51,
           abs(img.size.height - Self.tabBarAvatarPointDiameter) < 0.51 {
            #if DEBUG
            Self.logTabBarAvatar("sync skip (cache hit) size=\(img.size) renderingMode=\(img.renderingMode.rawValue)")
            #endif
            return
        }
        guard let urlString = effective else {
            #if DEBUG
            Self.logTabBarAvatar("sync clear (no URL)")
            #endif
            clearTabBarProfileAvatar()
            return
        }
        guard let url = URL(string: urlString) else {
            #if DEBUG
            Self.logTabBarAvatar("sync clear (invalid URL string)")
            #endif
            clearTabBarProfileAvatar()
            return
        }
        
        tabBarAvatarURLString = urlString
        #if DEBUG
        Self.logTabBarAvatar("download start url=\(url.absoluteString)")
        #endif
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            #if DEBUG
            let http = (response as? HTTPURLResponse)?.statusCode
            Self.logTabBarAvatar("download done bytes=\(data.count) http=\(http.map(String.init) ?? "n/a")")
            #endif
            guard let ui = UIImage(data: data) else {
                #if DEBUG
                Self.logTabBarAvatar("decode UIImage failed (data not an image?)")
                #endif
                tabBarProfileAvatar = nil
                return
            }
            #if DEBUG
            Self.logTabBarAvatar("decoded UIImage size=\(ui.size) scale=\(ui.scale) cgImage=\(ui.cgImage != nil)")
            #endif
            let icon = Self.makeCircularTabIcon(from: ui, pointDiameter: Self.tabBarAvatarPointDiameter)
            tabBarProfileAvatar = icon
            #if DEBUG
            Self.logTabBarAvatar("tab icon set size=\(icon.size) renderingMode=\(icon.renderingMode.rawValue) (alwaysOriginal=\(UIImage.RenderingMode.alwaysOriginal.rawValue))")
            #endif
        } catch {
            #if DEBUG
            Self.logTabBarAvatar("download error: \(error.localizedDescription)")
            #endif
            tabBarProfileAvatar = nil
        }
    }
    
    @MainActor
    func refreshTabBarProfileAvatarFromServer() async {
        guard let uid = userId else {
            clearTabBarProfileAvatar()
            return
        }
        struct Row: Decodable { let avatar_url: String? }
        do {
            let res = try await SupabaseManager.shared.client
                .from("profiles")
                .select("avatar_url")
                .eq("user_id", value: uid.uuidString)
                .single()
                .execute()
            let row = try JSONDecoder.supabase().decode(Row.self, from: res.data)
            #if DEBUG
            Self.logTabBarAvatar("refreshFromServer avatar_url=\(row.avatar_url ?? "nil")")
            #endif
            await syncTabBarProfileAvatar(urlString: row.avatar_url)
        } catch {
            #if DEBUG
            Self.logTabBarAvatar("refreshFromServer error: \(error.localizedDescription)")
            #endif
            await syncTabBarProfileAvatar(urlString: nil)
        }
    }
    
    #if DEBUG
    private static func logTabBarAvatar(_ message: String) {
        print("[TabBarAvatar]", message)
    }
    #endif
    
    private static func makeCircularTabIcon(from image: UIImage, pointDiameter: CGFloat) -> UIImage {
        let size = CGSize(width: pointDiameter, height: pointDiameter)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = UIScreen.main.scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let drawn = renderer.image { _ in
            let rect = CGRect(origin: .zero, size: size)
            UIBezierPath(ovalIn: rect).addClip()
            let imgSize = image.size
            guard imgSize.width > 0, imgSize.height > 0 else {
                image.draw(in: rect)
                return
            }
            let fillScale = max(pointDiameter / imgSize.width, pointDiameter / imgSize.height)
            let w = imgSize.width * fillScale
            let h = imgSize.height * fillScale
            let x = (pointDiameter - w) / 2
            let y = (pointDiameter - h) / 2
            image.draw(in: CGRect(x: x, y: y, width: w, height: h))
        }
        return drawn.withRenderingMode(.alwaysOriginal)
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
            Task { @MainActor in
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
                    await refreshUnreadNotificationsCount()
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
            
        case "apple_health_cardio_imported",
             "workout_like",
             "workout_comment",
             "comment_reply",
             "comment_like",
             "comment_mention":
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
            
        case "added_as_participant":
            print("📩 [AppState] routing to workout (participant)")

            let workoutId: Int?
            if let s = data["workout_id"] as? String {
                workoutId = Int(s)
            } else if let i = data["workout_id"] as? Int {
                workoutId = i
            } else {
                workoutId = nil
            }

            if let workoutId {
                let participantId = self.userId
                Task { @MainActor in
                    print("🧪 [Push] resolving owner for workoutId=\(workoutId) participantId=\(String(describing: participantId))")
                    let owner = await resolveWorkoutOwnerId(workoutId: workoutId)
                    print("🧪 [Push] resolved ownerId=\(String(describing: owner)) for workoutId=\(workoutId)")
                    self.notificationDestination = .workout(workoutId: workoutId, ownerId: owner)
                }
            } else {
                print("⚠️ [AppState] workout_id missing/invalid:", data)
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
            
        case "workout_kind_inactive":
            notificationDestination = .none
            let kind = Self.workoutKind(fromInactiveNudgeData: data)
            openAdd(with: AddWorkoutDraft(kind: kind))

        case "segment_you_are_first", "segment_lost_first":
            if let sidStr = data["segment_id"] as? String, let sid = UUID(uuidString: sidStr) {
                notificationDestination = .segmentDetail(segmentId: sid)
            } else {
                notificationDestination = .none
            }

        case "territory_capture_from_user", "territory_lost_to_user":
            let workoutId: Int? = {
                if let s = data["workout_id"] as? String { return Int(s) }
                if let i = data["workout_id"] as? Int { return i }
                if let n = data["workout_id"] as? NSNumber { return n.intValue }
                return nil
            }()
            if let workoutId {
                let ownerId: UUID?
                if type == "territory_lost_to_user",
                   let other = data["other_user_id"] as? String {
                    ownerId = UUID(uuidString: other)
                } else {
                    ownerId = self.userId
                }
                notificationDestination = .workout(workoutId: workoutId, ownerId: ownerId)
            } else {
                print("⚠️ [AppState] workout_id missing/invalid for territory notification:", data)
                notificationDestination = .none
            }

        case "challenge_won", "challenge_won_weekly":
            if let raw = data["challenge_instance_id"] as? String, let iid = UUID(uuidString: raw) {
                notificationDestination = .challengeWeekly(instanceId: iid)
            } else {
                notificationDestination = .none
            }

        case "dm_message":
            let convoId: Int64?
            if let s = data["conversation_id"] as? String { convoId = Int64(s) }
            else if let n = data["conversation_id"] as? NSNumber { convoId = n.int64Value }
            else if let i = data["conversation_id"] as? Int { convoId = Int64(i) }
            else if let i = data["conversation_id"] as? Int64 { convoId = i }
            else { convoId = nil }

            let sender: UUID?
            if let raw = data["sender_id"] as? String { sender = UUID(uuidString: raw) } else { sender = nil }

            if let convoId {
                notificationDestination = .directMessage(conversationId: convoId, senderUserId: sender)
            } else {
                notificationDestination = .none
            }

        default:
            notificationDestination = .none
        }
    }
    
    private static func workoutKind(fromInactiveNudgeData data: [String: Any]) -> WorkoutKind {
        let raw: String? = {
            if let s = data["workout_kind"] as? String { return s }
            if let n = data["workout_kind"] as? NSNumber { return n.stringValue }
            return nil
        }()
        switch raw?.lowercased() {
        case "cardio": return .cardio
        case "sport": return .sport
        case "strength": return .strength
        default: return .strength
        }
    }
    
    private func resolveWorkoutOwnerId(workoutId: Int) async -> UUID? {
        struct Row: Decodable { let user_id: UUID }

        do {
            let res = try await SupabaseManager.shared.client
                .from("workouts")
                .select("user_id")
                .eq("id", value: workoutId)
                .limit(1)
                .execute()

            if let raw = String(data: res.data, encoding: .utf8) {
                print("🧪 [Push] resolveWorkoutOwnerId raw:", raw)
            }

            let rows = try JSONDecoder.supabase().decode([Row].self, from: res.data)
            return rows.first?.user_id
        } catch {
            print("❌ [Push] resolveWorkoutOwnerId error:", error)
            return nil
        }
    }

    @MainActor
    private func startChatUnreadRealtimeIfNeeded(for userId: UUID) async {
        guard chatInboxRealtimeUserId != userId else {
            await refreshUnreadChatMessagesCount()
            return
        }
        if chatInboxRealtimeUserId != nil {
            await chatInboxRealtime.stop()
        }
        chatInboxRealtimeUserId = userId
        await chatInboxRealtime.start(myUserId: userId) { [weak self] in
            Task { @MainActor [weak self] in
                await self?.refreshUnreadChatMessagesCount()
            }
        }
        await refreshUnreadChatMessagesCount()
    }

    @MainActor
    private func stopChatUnreadRealtime() async {
        await chatInboxRealtime.stop()
        chatInboxRealtimeUserId = nil
        unreadChatMessagesCount = 0
    }

    @MainActor
    func refreshPremiumStatus() async {
        guard userId != nil, isAuthenticated, !passwordRecoveryPending else {
            isPremium = false
            return
        }
        isPremium = await PremiumStatusClient.fetchIsPremium()
    }
    
    private func listenAuth() {
        authTask?.cancel()
        authTask = Task { [weak self] in
            guard let self else { return }
            
            if let session = try? await SupabaseManager.shared.client.auth.session {
                await MainActor.run {
                    self.userId = session.user.id
                    if !self.passwordRecoveryPending {
                        self.isAuthenticated = true
                    } else {
                        self.isAuthenticated = false
                    }
                }
                let recoveryPending = await MainActor.run { self.passwordRecoveryPending }
                if !recoveryPending {
                    await self.refreshTabBarProfileAvatarFromServer()
                    await self.refreshUnreadNotificationsCount()
                    await self.refreshPremiumStatus()
                    await self.startChatUnreadRealtimeIfNeeded(for: session.user.id)
                } else {
                    await self.stopChatUnreadRealtime()
                }
            } else {
                await MainActor.run {
                    self.isAuthenticated = false
                    self.userId = nil
                    self.isPremium = false
                    self.clearTabBarProfileAvatar()
                    self.unreadNotificationsCount = 0
                }
                await self.stopChatUnreadRealtime()
            }
            
            for await state in SupabaseManager.shared.client.auth.authStateChanges {
                let event = state.event
                let session = state.session
                
                await MainActor.run {
                    switch event {
                    case .initialSession, .signedIn, .userUpdated, .tokenRefreshed:
                        if !self.passwordRecoveryPending {
                            self.isAuthenticated = (session != nil)
                            self.userId = session?.user.id
                        }

                    case .passwordRecovery:
                        self.passwordRecoveryPending = true
                        self.userId = session?.user.id
                        self.isAuthenticated = false

                    case .signedOut, .userDeleted:
                        self.isAuthenticated = false
                        self.userId = nil
                        self.isPremium = false
                        self.passwordRecoveryPending = false
                        self.authCallbackError = nil
                        self.clearTabBarProfileAvatar()
                        self.unreadNotificationsCount = 0
                        self.unreadChatMessagesCount = 0

                    default:
                        break
                    }
                }

                switch event {
                case .initialSession, .signedIn, .userUpdated, .tokenRefreshed:
                    if session != nil, !self.passwordRecoveryPending {
                        await self.refreshTabBarProfileAvatarFromServer()
                        await self.refreshUnreadNotificationsCount()
                        await self.refreshPremiumStatus()
                        if let userId = session?.user.id {
                            await self.startChatUnreadRealtimeIfNeeded(for: userId)
                        }
                    } else if session == nil {
                        await MainActor.run {
                            self.clearTabBarProfileAvatar()
                            self.unreadNotificationsCount = 0
                            self.isPremium = false
                        }
                        await self.stopChatUnreadRealtime()
                    } else {
                        await self.stopChatUnreadRealtime()
                    }
                case .signedOut, .userDeleted:
                    await self.stopChatUnreadRealtime()
                case .passwordRecovery:
                    await self.stopChatUnreadRealtime()
                default:
                    break
                }
            }
        }
    }
}
