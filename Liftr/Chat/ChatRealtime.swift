import Foundation
import Supabase

enum ChatRealtimeEvent {
    case inserted(ChatMessage)
    case updated(ChatMessage)
    case deleted(messageId: Int64, conversationId: Int64)
}

enum ChatReactionRealtimeEvent {
    case insertedReaction(MessageReaction)
    case deletedReaction(messageId: Int64, userId: UUID, emoji: String)
}

actor ChatThreadRealtime {
    private let conversationId: Int64
    private var channel: RealtimeChannelV2?
    private var listenTask: Task<Void, Never>?

    init(conversationId: Int64) {
        self.conversationId = conversationId
    }

    func start(onEvent: @escaping @Sendable (ChatRealtimeEvent) -> Void) async {
        guard channel == nil else { return }
        let topic = "conversation:\(conversationId):messages"
        let ch = SupabaseManager.shared.client.channel(topic) { config in
            config.isPrivate = true
        }
        channel = ch

        listenTask = Task { [weak self] in
            guard let self else { return }
            await self.consume(channel: ch, onEvent: onEvent)
        }

        try? await ch.subscribeWithError()
    }

    func stop() async {
        listenTask?.cancel()
        listenTask = nil
        if let ch = channel {
            await ch.unsubscribe()
        }
        channel = nil
    }

    private func consume(channel: RealtimeChannelV2,
                         onEvent: @Sendable @escaping (ChatRealtimeEvent) -> Void) async {
        async let inserts: () = forwardBroadcast(channel: channel, event: "INSERT", to: onEvent, kind: .insert)
        async let updates: () = forwardBroadcast(channel: channel, event: "UPDATE", to: onEvent, kind: .update)
        async let deletes: () = forwardBroadcast(channel: channel, event: "DELETE", to: onEvent, kind: .delete)
        _ = await (inserts, updates, deletes)
    }

    private enum DecodeKind { case insert, update, delete }

    private func forwardBroadcast(channel: RealtimeChannelV2,
                                  event: String,
                                  to onEvent: @Sendable @escaping (ChatRealtimeEvent) -> Void,
                                  kind: DecodeKind) async {
        for await payload in channel.broadcastStream(event: event) {
            do {
                let envelope = try Self.decodeEnvelope(from: payload)
                switch kind {
                case .insert:
                    if let msg = try Self.decodeMessage(envelope.record) {
                        onEvent(.inserted(msg))
                    }
                case .update:
                    if let msg = try Self.decodeMessage(envelope.record) {
                        onEvent(.updated(msg))
                    }
                case .delete:
                    if case .object(let dict)? = envelope.oldRecord,
                       let id = Self.int64(from: dict["id"]) {
                        onEvent(.deleted(messageId: id, conversationId: conversationId))
                    }
                }
            } catch {
                #if DEBUG
                print("[ChatRealtime] decode error event=\(event):", error)
                #endif
            }
        }
    }

    struct BroadcastEnvelope {
        let record: AnyJSON?
        let oldRecord: AnyJSON?
    }

    static func decodeEnvelope(from payload: JSONObject) throws -> BroadcastEnvelope {
        let inner: [String: AnyJSON]
        if case .object(let nested)? = payload["payload"] {
            inner = nested
        } else {
            inner = payload
        }
        return BroadcastEnvelope(record: inner["record"], oldRecord: inner["old_record"])
    }

    private static func decodeMessage(_ raw: AnyJSON?) throws -> ChatMessage? {
        guard let raw else { return nil }
        let data = try JSONEncoder().encode(raw)
        return try JSONDecoder.supabase().decode(ChatMessage.self, from: data)
    }

    static func int64(from json: AnyJSON?) -> Int64? {
        guard let json else { return nil }
        switch json {
        case .integer(let v): return Int64(v)
        case .double(let v):  return Int64(v)
        case .string(let s):  return Int64(s)
        default: return nil
        }
    }
}

actor ChatReactionsRealtime {
    private let conversationId: Int64
    private var channel: RealtimeChannelV2?
    private var listenTask: Task<Void, Never>?

    init(conversationId: Int64) {
        self.conversationId = conversationId
    }

    func start(onEvent: @escaping @Sendable (ChatReactionRealtimeEvent) -> Void) async {
        guard channel == nil else { return }
        let topic = "conversation:\(conversationId):reactions"
        let ch = SupabaseManager.shared.client.channel(topic) { config in
            config.isPrivate = true
        }
        channel = ch

        listenTask = Task { [weak self] in
            guard let self else { return }
            await self.consume(channel: ch, onEvent: onEvent)
        }

        try? await ch.subscribeWithError()
    }

    func stop() async {
        listenTask?.cancel()
        listenTask = nil
        if let ch = channel {
            await ch.unsubscribe()
        }
        channel = nil
    }

    private func consume(channel: RealtimeChannelV2,
                         onEvent: @Sendable @escaping (ChatReactionRealtimeEvent) -> Void) async {
        async let inserts: () = forwardBroadcast(channel: channel, event: "INSERT", to: onEvent, kind: .insert)
        async let deletes: () = forwardBroadcast(channel: channel, event: "DELETE", to: onEvent, kind: .delete)
        _ = await (inserts, deletes)
    }

    private enum DecodeKind { case insert, delete }

    private func forwardBroadcast(channel: RealtimeChannelV2,
                                  event: String,
                                  to onEvent: @Sendable @escaping (ChatReactionRealtimeEvent) -> Void,
                                  kind: DecodeKind) async {
        for await payload in channel.broadcastStream(event: event) {
            do {
                let envelope = try ChatThreadRealtime.decodeEnvelope(from: payload)
                switch kind {
                case .insert:
                    if let row = try Self.decodeReaction(envelope.record) {
                        onEvent(.insertedReaction(row))
                    }
                case .delete:
                    if case .object(let dict)? = envelope.oldRecord,
                       let messageId = ChatThreadRealtime.int64(from: dict["message_id"]),
                       case .string(let userId)? = dict["user_id"],
                       let uid = UUID(uuidString: userId),
                       case .string(let emoji)? = dict["emoji"] {
                        onEvent(.deletedReaction(messageId: messageId, userId: uid, emoji: emoji))
                    }
                }
            } catch {
                #if DEBUG
                print("[ChatReactionsRealtime] decode error event=\(event):", error)
                #endif
            }
        }
    }

    private static func decodeReaction(_ raw: AnyJSON?) throws -> MessageReaction? {
        guard let raw else { return nil }
        let data = try JSONEncoder().encode(raw)
        return try JSONDecoder.supabase().decode(MessageReaction.self, from: data)
    }
}

struct ChatTypingState: Equatable {
    var typingUserIds: Set<UUID>
}

actor ChatTypingChannel {
    private let conversationId: Int64
    private let myUserId: UUID
    private var channel: RealtimeChannelV2?
    private var presenceTask: Task<Void, Never>?
    private var presences: [String: (userId: UUID, typing: Bool)] = [:]

    init(conversationId: Int64, myUserId: UUID) {
        self.conversationId = conversationId
        self.myUserId = myUserId
    }

    func start(onState: @escaping @Sendable (ChatTypingState) -> Void) async {
        guard channel == nil else { return }
        let me = myUserId.uuidString
        let topic = "chat:typing:\(conversationId)"
        let ch = SupabaseManager.shared.client.channel(topic) { config in
            config.presence.key = me
            config.isPrivate = false
        }
        channel = ch

        presenceTask = Task { [weak self] in
            guard let self else { return }
            await self.consumePresence(channel: ch, onState: onState)
        }

        try? await ch.subscribeWithError()
        await ch.track(state: ["user_id": .string(me), "typing": .bool(false)])
    }

    func setTyping(_ typing: Bool) async {
        guard let ch = channel else { return }
        await ch.track(state: [
            "user_id": .string(myUserId.uuidString),
            "typing": .bool(typing)
        ])
    }

    func stop() async {
        presenceTask?.cancel()
        presenceTask = nil
        if let ch = channel {
            await ch.untrack()
            await ch.unsubscribe()
        }
        channel = nil
        presences.removeAll()
    }

    private func consumePresence(channel: RealtimeChannelV2,
                                 onState: @Sendable @escaping (ChatTypingState) -> Void) async {
        for await action in channel.presenceChange() {
            self.applyDiff(joins: action.joins, leaves: action.leaves, onState: onState)
        }
    }

    private func applyDiff(joins: [String: PresenceV2],
                           leaves: [String: PresenceV2],
                           onState: @Sendable @escaping (ChatTypingState) -> Void) {
        for (_, presence) in leaves {
            presences.removeValue(forKey: presence.ref)
        }
        for (_, presence) in joins {
            let state = presence.state
            let typing = state["typing"]?.boolValue ?? false
            guard let raw = state["user_id"]?.stringValue,
                  let uid = UUID(uuidString: raw) else { continue }
            presences[presence.ref] = (uid, typing)
        }

        var typingUsers = Set<UUID>()
        for (_, info) in presences where info.typing && info.userId != myUserId {
            typingUsers.insert(info.userId)
        }
        onState(ChatTypingState(typingUserIds: typingUsers))
    }
}

actor ChatInboxRealtime {
    private var channel: RealtimeChannelV2?
    private var listenTask: Task<Void, Never>?

    func start(myUserId: UUID, onChange: @escaping @Sendable () -> Void) async {
        guard channel == nil else { return }
        let topic = "inbox:\(myUserId.uuidString)"
        let ch = SupabaseManager.shared.client.channel(topic) { config in
            config.isPrivate = false
        }
        channel = ch

        let stream = ch.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "messages"
        )
        listenTask = Task {
            for await _ in stream {
                onChange()
            }
        }
        try? await ch.subscribeWithError()
    }

    func stop() async {
        listenTask?.cancel()
        listenTask = nil
        if let ch = channel {
            await ch.unsubscribe()
        }
        channel = nil
    }
}

