import Foundation
import Supabase

enum ChatService {
    private static var client: SupabaseClient { SupabaseManager.shared.client }

    private struct EmptyParams: Encodable {}

    private struct ConvOverviewParams: Encodable {
        let p_limit: Int
        let p_offset: Int
    }

    static func fetchConversations(limit: Int = 50, offset: Int = 0) async throws -> [ConversationOverview] {
        let res = try await client
            .rpc("get_conversations_overview",
                 params: ConvOverviewParams(p_limit: limit, p_offset: offset))
            .execute()
        return try JSONDecoder.supabase().decode([ConversationOverview].self, from: res.data)
    }

    private struct GetMessagesParams: Encodable {
        let p_conversation_id: Int64
        let p_cursor_before_id: Int64?
        let p_limit: Int
    }

    static func fetchMessages(conversationId: Int64,
                              before: Int64? = nil,
                              limit: Int = 50) async throws -> [ChatMessage] {
        let res = try await client
            .rpc("get_messages",
                 params: GetMessagesParams(
                    p_conversation_id: conversationId,
                    p_cursor_before_id: before,
                    p_limit: limit))
            .execute()
        return try JSONDecoder.supabase().decode([ChatMessage].self, from: res.data)
    }

    private struct StartDirectParams: Encodable {
        let p_other: UUID
    }

    static func startDirect(with other: UUID) async throws -> Int64 {
        let res = try await client
            .rpc("start_direct_conversation", params: StartDirectParams(p_other: other))
            .execute()
        if let id = try? JSONDecoder().decode(Int64.self, from: res.data) { return id }
        let arr = try JSONDecoder().decode([Int64].self, from: res.data)
        guard let first = arr.first else {
            throw NSError(domain: "Chat", code: 0,
                          userInfo: [NSLocalizedDescriptionKey: "Empty start_direct_conversation response"])
        }
        return first
    }

    private struct SendMessageParams: Encodable {
        let p_conversation_id: Int64
        let p_kind: String
        let p_body: String?
        let p_metadata: AnyJSON
        let p_client_msg_id: UUID
        let p_reply_to_message_id: Int64?
    }

    static func sendMessage(conversationId: Int64,
                            body: String,
                            clientMsgId: UUID = UUID(),
                            replyTo: Int64? = nil) async throws -> Int64 {
        let params = SendMessageParams(
            p_conversation_id: conversationId,
            p_kind: ChatMessageKind.text.rawValue,
            p_body: body,
            p_metadata: .object([:]),
            p_client_msg_id: clientMsgId,
            p_reply_to_message_id: replyTo
        )
        let res = try await client.rpc("send_message", params: params).execute()
        if let id = try? JSONDecoder().decode(Int64.self, from: res.data) { return id }
        let arr = try JSONDecoder().decode([Int64].self, from: res.data)
        guard let first = arr.first else {
            throw NSError(domain: "Chat", code: 0,
                          userInfo: [NSLocalizedDescriptionKey: "Empty send_message response"])
        }
        return first
    }

    @discardableResult
    static func sendWorkoutShare(conversationId: Int64,
                                 snapshot: WorkoutShareSnapshot,
                                 caption: String? = nil,
                                 clientMsgId: UUID = UUID(),
                                 replyTo: Int64? = nil) async throws -> Int64 {
        let metadata = try AnyJSON(snapshot)
        let params = SendMessageParams(
            p_conversation_id: conversationId,
            p_kind: ChatMessageKind.workoutShare.rawValue,
            p_body: caption?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            p_metadata: metadata,
            p_client_msg_id: clientMsgId,
            p_reply_to_message_id: replyTo
        )
        let res = try await client.rpc("send_message", params: params).execute()
        if let id = try? JSONDecoder().decode(Int64.self, from: res.data) { return id }
        let arr = try JSONDecoder().decode([Int64].self, from: res.data)
        guard let first = arr.first else {
            throw NSError(domain: "Chat", code: 0,
                          userInfo: [NSLocalizedDescriptionKey: "Empty send_message response"])
        }
        return first
    }

    @discardableResult
    static func sendRoutineShare(conversationId: Int64,
                                 snapshot: RoutineShareSnapshot,
                                 caption: String? = nil,
                                 clientMsgId: UUID = UUID(),
                                 replyTo: Int64? = nil) async throws -> Int64 {
        let metadata = try AnyJSON(snapshot)
        let params = SendMessageParams(
            p_conversation_id: conversationId,
            p_kind: ChatMessageKind.routineShare.rawValue,
            p_body: caption?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            p_metadata: metadata,
            p_client_msg_id: clientMsgId,
            p_reply_to_message_id: replyTo
        )
        let res = try await client.rpc("send_message", params: params).execute()
        if let id = try? JSONDecoder().decode(Int64.self, from: res.data) { return id }
        let arr = try JSONDecoder().decode([Int64].self, from: res.data)
        guard let first = arr.first else {
            throw NSError(domain: "Chat", code: 0,
                          userInfo: [NSLocalizedDescriptionKey: "Empty send_message response"])
        }
        return first
    }

    @discardableResult
    static func sendAchievementShare(conversationId: Int64,
                                     snapshot: AchievementShareSnapshot,
                                     caption: String? = nil,
                                     clientMsgId: UUID = UUID(),
                                     replyTo: Int64? = nil) async throws -> Int64 {
        let metadata = try AnyJSON(snapshot)
        let params = SendMessageParams(
            p_conversation_id: conversationId,
            p_kind: ChatMessageKind.achievementShare.rawValue,
            p_body: caption?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            p_metadata: metadata,
            p_client_msg_id: clientMsgId,
            p_reply_to_message_id: replyTo
        )
        let res = try await client.rpc("send_message", params: params).execute()
        if let id = try? JSONDecoder().decode(Int64.self, from: res.data) { return id }
        let arr = try JSONDecoder().decode([Int64].self, from: res.data)
        guard let first = arr.first else {
            throw NSError(domain: "Chat", code: 0,
                          userInfo: [NSLocalizedDescriptionKey: "Empty send_message response"])
        }
        return first
    }

    @discardableResult
    static func sendSegmentShare(conversationId: Int64,
                                 snapshot: SegmentShareSnapshot,
                                 caption: String? = nil,
                                 clientMsgId: UUID = UUID(),
                                 replyTo: Int64? = nil) async throws -> Int64 {
        let metadata = try AnyJSON(snapshot)
        let params = SendMessageParams(
            p_conversation_id: conversationId,
            p_kind: ChatMessageKind.segmentShare.rawValue,
            p_body: caption?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            p_metadata: metadata,
            p_client_msg_id: clientMsgId,
            p_reply_to_message_id: replyTo
        )
        let res = try await client.rpc("send_message", params: params).execute()
        if let id = try? JSONDecoder().decode(Int64.self, from: res.data) { return id }
        let arr = try JSONDecoder().decode([Int64].self, from: res.data)
        guard let first = arr.first else {
            throw NSError(domain: "Chat", code: 0,
                          userInfo: [NSLocalizedDescriptionKey: "Empty send_message response"])
        }
        return first
    }

    @discardableResult
    static func sendSharedIngredient(conversationId: Int64,
                                     snapshot: SharedIngredientSnapshot,
                                     caption: String? = nil,
                                     clientMsgId: UUID = UUID(),
                                     replyTo: Int64? = nil) async throws -> Int64 {
        let metadata = try AnyJSON(snapshot)
        let params = SendMessageParams(
            p_conversation_id: conversationId,
            p_kind: ChatMessageKind.sharedIngredient.rawValue,
            p_body: caption?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            p_metadata: metadata,
            p_client_msg_id: clientMsgId,
            p_reply_to_message_id: replyTo
        )
        let res = try await client.rpc("send_message", params: params).execute()
        if let id = try? JSONDecoder().decode(Int64.self, from: res.data) { return id }
        let arr = try JSONDecoder().decode([Int64].self, from: res.data)
        guard let first = arr.first else {
            throw NSError(domain: "Chat", code: 0,
                          userInfo: [NSLocalizedDescriptionKey: "Empty send_message response"])
        }
        return first
    }

    @discardableResult
    static func sendSharedRecipe(conversationId: Int64,
                                 snapshot: SharedRecipeSnapshot,
                                 caption: String? = nil,
                                 clientMsgId: UUID = UUID(),
                                 replyTo: Int64? = nil) async throws -> Int64 {
        let metadata = try AnyJSON(snapshot)
        let params = SendMessageParams(
            p_conversation_id: conversationId,
            p_kind: ChatMessageKind.sharedRecipe.rawValue,
            p_body: caption?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            p_metadata: metadata,
            p_client_msg_id: clientMsgId,
            p_reply_to_message_id: replyTo
        )
        let res = try await client.rpc("send_message", params: params).execute()
        if let id = try? JSONDecoder().decode(Int64.self, from: res.data) { return id }
        let arr = try JSONDecoder().decode([Int64].self, from: res.data)
        guard let first = arr.first else {
            throw NSError(domain: "Chat", code: 0,
                          userInfo: [NSLocalizedDescriptionKey: "Empty send_message response"])
        }
        return first
    }

    private struct CloneSnapshotParams: Encodable {
        let p_snapshot: AnyJSON
    }

    static func cloneSharedIngredient(snapshot: SharedIngredientSnapshot) async throws -> UUID {
        let res = try await client
            .rpc("clone_shared_ingredient",
                 params: CloneSnapshotParams(p_snapshot: try AnyJSON(snapshot)))
            .execute()
        if let id = try? JSONDecoder.supabase().decode(UUID.self, from: res.data) { return id }
        let arr = try JSONDecoder.supabase().decode([UUID].self, from: res.data)
        guard let first = arr.first else {
            throw NSError(domain: "Nutrition", code: 0,
                          userInfo: [NSLocalizedDescriptionKey: "Empty clone_shared_ingredient response"])
        }
        return first
    }

    static func cloneSharedRecipe(snapshot: SharedRecipeSnapshot) async throws -> UUID {
        let res = try await client
            .rpc("clone_shared_recipe",
                 params: CloneSnapshotParams(p_snapshot: try AnyJSON(snapshot)))
            .execute()
        if let id = try? JSONDecoder.supabase().decode(UUID.self, from: res.data) { return id }
        let arr = try JSONDecoder.supabase().decode([UUID].self, from: res.data)
        guard let first = arr.first else {
            throw NSError(domain: "Nutrition", code: 0,
                          userInfo: [NSLocalizedDescriptionKey: "Empty clone_shared_recipe response"])
        }
        return first
    }

    private struct MarkReadParams: Encodable {
        let p_conversation_id: Int64
        let p_last_read_message_id: Int64
    }

    static func markRead(conversationId: Int64, lastMessageId: Int64) async throws {
        _ = try await client
            .rpc("mark_conversation_read",
                 params: MarkReadParams(
                    p_conversation_id: conversationId,
                    p_last_read_message_id: lastMessageId))
            .execute()
    }

    private struct ConversationIdParams: Encodable { let p_conversation_id: Int64 }

    static func clearConversation(_ conversationId: Int64) async throws {
        _ = try await client
            .rpc("clear_conversation", params: ConversationIdParams(p_conversation_id: conversationId))
            .execute()
    }

    private struct SetMutedParams: Encodable {
        let p_conversation_id: Int64
        let p_muted: Bool
    }

    static func setMuted(conversationId: Int64, muted: Bool) async throws {
        _ = try await client
            .rpc("set_conversation_muted",
                 params: SetMutedParams(p_conversation_id: conversationId, p_muted: muted))
            .execute()
    }

    private struct ToggleReactionParams: Encodable {
        let p_message_id: Int64
        let p_emoji: String
    }

    @discardableResult
    static func toggleReaction(messageId: Int64, emoji: ReactionEmoji) async throws -> Bool {
        let res = try await client
            .rpc("toggle_message_reaction",
                 params: ToggleReactionParams(p_message_id: messageId, p_emoji: emoji.rawValue))
            .execute()
        return (try? JSONDecoder().decode(Bool.self, from: res.data)) ?? false
    }

    private struct EditMessageParams: Encodable {
        let p_message_id: Int64
        let p_body: String
    }

    static func editMessage(_ messageId: Int64, body: String) async throws {
        _ = try await client
            .rpc("edit_message", params: EditMessageParams(p_message_id: messageId, p_body: body))
            .execute()
    }

    private struct DeleteMessageParams: Encodable { let p_message_id: Int64 }

    static func deleteMessage(_ messageId: Int64) async throws {
        _ = try await client
            .rpc("delete_message", params: DeleteMessageParams(p_message_id: messageId))
            .execute()
    }

    static func fetchReactions(messageIds: [Int64]) async throws -> [Int64: [MessageReaction]] {
        guard !messageIds.isEmpty else { return [:] }
        let res = try await client
            .from("message_reactions")
            .select("message_id, user_id, emoji, created_at")
            .in("message_id", values: messageIds.map { Int($0) })
            .order("created_at", ascending: true)
            .limit(messageIds.count * 12)
            .execute()
        let rows = try JSONDecoder.supabase().decode([MessageReaction].self, from: res.data)
        return Dictionary(grouping: rows, by: { $0.message_id })
    }

    static func fetchPeerLastRead(conversationId: Int64,
                                  myUserId: UUID) async throws -> Int64? {
        struct Row: Decodable {
            let user_id: UUID
            let last_read_message_id: Int64?
        }
        let res = try await client
            .from("conversation_reads")
            .select("user_id, last_read_message_id")
            .eq("conversation_id", value: Int(conversationId))
            .neq("user_id", value: myUserId.uuidString)
            .limit(8)
            .execute()
        let rows = try JSONDecoder.supabase().decode([Row].self, from: res.data)
        return rows.compactMap { $0.last_read_message_id }.max()
    }

    struct ReplyPreview: Decodable {
        let id: Int64
        let user_id: UUID
        let body: String?
        let kind: String?
        let metadata: AnyJSON?
        let deleted_at: Date?
    }

    static func fetchReplyTargets(messageIds: [Int64]) async throws -> [Int64: ReplyPreview] {
        guard !messageIds.isEmpty else { return [:] }
        let res = try await client
            .from("messages")
            .select("id, user_id, body, kind, metadata, deleted_at")
            .in("id", values: messageIds.map { Int($0) })
            .limit(messageIds.count + 1)
            .execute()
        let rows = try JSONDecoder.supabase().decode([ReplyPreview].self, from: res.data)
        return Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
    }

    static func fetchOtherParticipant(conversationId: Int64,
                                      myUserId: UUID) async throws -> ChatProfile? {
        struct PartRow: Decodable { let user_id: UUID }
        let pres = try await client
            .from("conversation_participants")
            .select("user_id")
            .eq("conversation_id", value: Int(conversationId))
            .neq("user_id", value: myUserId.uuidString)
            .limit(8)
            .execute()
        let rows = try JSONDecoder.supabase().decode([PartRow].self, from: pres.data)
        guard let firstId = rows.first?.user_id else { return nil }
        return try await fetchProfile(userId: firstId)
    }

    static func fetchProfile(userId: UUID) async throws -> ChatProfile? {
        let res = try await client
            .from("profiles")
            .select("user_id, username, avatar_url")
            .eq("user_id", value: userId.uuidString)
            .limit(1)
            .execute()
        let rows = try JSONDecoder.supabase().decode([ChatProfile].self, from: res.data)
        return rows.first
    }

    static func fetchProfiles(userIds: [UUID]) async throws -> [UUID: ChatProfile] {
        guard !userIds.isEmpty else { return [:] }
        let res = try await client
            .from("profiles")
            .select("user_id, username, avatar_url")
            .in("user_id", values: userIds.map { $0.uuidString })
            .limit(userIds.count + 1)
            .execute()
        let rows = try JSONDecoder.supabase().decode([ChatProfile].self, from: res.data)
        return Dictionary(uniqueKeysWithValues: rows.map { ($0.user_id, $0) })
    }

    static func fetchMutualFollowees(myUserId: UUID) async throws -> [ChatProfile] {
        struct EdgeRow: Decodable {
            let follower_id: UUID?
            let followee_id: UUID?
        }
        async let followingRes = client
            .from("follows")
            .select("followee_id")
            .eq("follower_id", value: myUserId.uuidString)
            .limit(2000)
            .execute()
        async let followersRes = client
            .from("follows")
            .select("follower_id")
            .eq("followee_id", value: myUserId.uuidString)
            .limit(2000)
            .execute()

        let following = try JSONDecoder.supabase().decode([EdgeRow].self, from: try await followingRes.data)
        let followers = try JSONDecoder.supabase().decode([EdgeRow].self, from: try await followersRes.data)

        let followingIds = Set(following.compactMap { $0.followee_id })
        let followerIds  = Set(followers.compactMap  { $0.follower_id  })
        let mutuals = followingIds.intersection(followerIds)
        if mutuals.isEmpty { return [] }

        let res = try await client
            .from("profiles")
            .select("user_id, username, avatar_url")
            .in("user_id", values: mutuals.map { $0.uuidString })
            .order("username", ascending: true)
            .limit(2000)
            .execute()
        return try JSONDecoder.supabase().decode([ChatProfile].self, from: res.data)
    }
}
