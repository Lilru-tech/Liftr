import SwiftUI
import Supabase

@MainActor
final class ChatThreadModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var reactionsByMessageId: [Int64: [MessageReaction]] = [:]
    @Published var replyTargetsById: [Int64: ChatService.ReplyPreview] = [:]
    @Published var typingUserIds: Set<UUID> = []
    @Published var error: String?
    @Published var loadingOlder = false
    @Published var hasMore = true
    @Published var peerLastReadMessageId: Int64?
    @Published var muted: Bool = false

    let conversationId: Int64
    private let realtime: ChatThreadRealtime
    private let reactionsRealtime: ChatReactionsRealtime
    private var typingChannel: ChatTypingChannel?
    private var typingDebounce: Task<Void, Never>?
    private var realtimeStarted = false

    init(conversationId: Int64) {
        self.conversationId = conversationId
        self.realtime = ChatThreadRealtime(conversationId: conversationId)
        self.reactionsRealtime = ChatReactionsRealtime(conversationId: conversationId)
    }

    func loadInitial() async {
        do {
            let page = try await ChatService.fetchMessages(
                conversationId: conversationId,
                before: nil,
                limit: 50
            )
            let asc = page.reversed()
            self.messages = Array(asc)
            self.hasMore = page.count >= 50
            await markReadIfNeeded()
            await refreshSidecars()
            await refreshPeerLastRead()
            await loadMutedFlag()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func loadOlderIfNeeded() async {
        guard !loadingOlder, hasMore, let oldestId = messages.first?.id else { return }
        loadingOlder = true
        defer { loadingOlder = false }
        do {
            let page = try await ChatService.fetchMessages(
                conversationId: conversationId,
                before: oldestId,
                limit: 50
            )
            let asc = page.reversed()
            var merged = Array(asc)
            merged.append(contentsOf: messages)
            self.messages = merged
            self.hasMore = page.count >= 50
            await refreshSidecars()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func send(text: String, myUserId: UUID, replyTo: Int64? = nil) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let clientId = UUID()
        let tentativeId = -Int64.random(in: 1...Int64.max)
        let tentative = ChatMessage(
            id: tentativeId,
            user_id: myUserId,
            kind: ChatMessageKind.text.rawValue,
            body: trimmed,
            metadata: nil,
            reply_to_message_id: replyTo,
            created_at: Date(),
            edited_at: nil,
            deleted_at: nil
        )
        self.messages.append(tentative)

        do {
            let serverId = try await ChatService.sendMessage(
                conversationId: conversationId,
                body: trimmed,
                clientMsgId: clientId,
                replyTo: replyTo
            )
            let alreadyArrived = messages.contains(where: { $0.id == serverId })
            if alreadyArrived {
                messages.removeAll { $0.id == tentativeId }
            } else if let idx = messages.firstIndex(where: { $0.id == tentativeId }) {
                messages[idx] = ChatMessage(
                    id: serverId,
                    user_id: myUserId,
                    kind: tentative.kind,
                    body: tentative.body,
                    metadata: tentative.metadata,
                    reply_to_message_id: tentative.reply_to_message_id,
                    created_at: tentative.created_at,
                    edited_at: nil,
                    deleted_at: nil
                )
            }
        } catch {
            self.messages.removeAll { $0.id == tentativeId }
            self.error = error.localizedDescription
        }
    }

    func startRealtimeIfNeeded(myUserId: UUID) async {
        guard !realtimeStarted else { return }
        realtimeStarted = true

        await realtime.start { [weak self] event in
            Task { @MainActor [weak self] in
                self?.apply(event: event)
            }
        }

        await reactionsRealtime.start { [weak self] event in
            Task { @MainActor [weak self] in
                self?.apply(reactionEvent: event)
            }
        }

        let typing = ChatTypingChannel(conversationId: conversationId, myUserId: myUserId)
        await typing.start { [weak self] state in
            Task { @MainActor [weak self] in
                self?.typingUserIds = state.typingUserIds
            }
        }
        self.typingChannel = typing
    }

    func tearDown() async {
        typingDebounce?.cancel()
        typingDebounce = nil
        await realtime.stop()
        await reactionsRealtime.stop()
        if let typing = typingChannel { await typing.stop() }
        typingChannel = nil
        realtimeStarted = false
    }

    func updateTyping(text: String) {
        let isEmpty = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let typing = !isEmpty
        let channel = typingChannel
        typingDebounce?.cancel()
        typingDebounce = Task { [weak self] in
            await channel?.setTyping(typing)
            if typing {
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                guard !Task.isCancelled else { return }
                await channel?.setTyping(false)
                _ = self
            }
        }
    }

    func toggleReaction(messageId: Int64, emoji: ReactionEmoji, myUserId: UUID) async {
        var current = reactionsByMessageId[messageId] ?? []
        if let idx = current.firstIndex(where: { $0.user_id == myUserId && $0.emoji == emoji.rawValue }) {
            current.remove(at: idx)
        } else {
            current.append(MessageReaction(message_id: messageId,
                                           user_id: myUserId,
                                           emoji: emoji.rawValue,
                                           created_at: Date()))
        }
        reactionsByMessageId[messageId] = current

        do {
            _ = try await ChatService.toggleReaction(messageId: messageId, emoji: emoji)
        } catch {
            self.error = error.localizedDescription
            do {
                let map = try await ChatService.fetchReactions(messageIds: [messageId])
                reactionsByMessageId[messageId] = map[messageId] ?? []
            } catch { }
        }
    }

    func editMessage(_ id: Int64, body: String) async {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try await ChatService.editMessage(id, body: trimmed)
            if let idx = messages.firstIndex(where: { $0.id == id }) {
                let m = messages[idx]
                messages[idx] = ChatMessage(
                    id: m.id, user_id: m.user_id, kind: m.kind,
                    body: trimmed, metadata: m.metadata,
                    reply_to_message_id: m.reply_to_message_id,
                    created_at: m.created_at, edited_at: Date(),
                    deleted_at: m.deleted_at
                )
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func deleteMessage(_ id: Int64) async {
        do {
            try await ChatService.deleteMessage(id)
            if let idx = messages.firstIndex(where: { $0.id == id }) {
                let m = messages[idx]
                messages[idx] = ChatMessage(
                    id: m.id, user_id: m.user_id, kind: m.kind,
                    body: nil, metadata: m.metadata,
                    reply_to_message_id: m.reply_to_message_id,
                    created_at: m.created_at, edited_at: m.edited_at,
                    deleted_at: Date()
                )
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func setMuted(_ muted: Bool) async {
        do {
            try await ChatService.setMuted(conversationId: conversationId, muted: muted)
            self.muted = muted
        } catch {
            self.error = error.localizedDescription
        }
    }

    func clearConversation() async {
        do {
            try await ChatService.clearConversation(conversationId)
            // The thread closes on success; the inbox will hide the row.
            self.messages = []
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func apply(reactionEvent: ChatReactionRealtimeEvent) {
        switch reactionEvent {
        case .insertedReaction(let r):
            var arr = reactionsByMessageId[r.message_id] ?? []
            if !arr.contains(where: { $0.user_id == r.user_id && $0.emoji == r.emoji }) {
                arr.append(r)
                reactionsByMessageId[r.message_id] = arr
            }
        case .deletedReaction(let mid, let uid, let emoji):
            var arr = reactionsByMessageId[mid] ?? []
            arr.removeAll { $0.user_id == uid && $0.emoji == emoji }
            reactionsByMessageId[mid] = arr
        }
    }

    private func apply(event: ChatRealtimeEvent) {
        switch event {
        case .inserted(let msg):
            if let idx = messages.firstIndex(where: { $0.id == msg.id }) {
                messages[idx] = msg
            } else {
                let pendingIdx = messages.firstIndex(where: { local in
                    guard local.id < 0, local.user_id == msg.user_id else { return false }
                    if local.kind == ChatMessageKind.text.rawValue {
                        return local.body == msg.body
                    }
                    if local.kind == ChatMessageKind.workoutShare.rawValue,
                       msg.messageKind == .workoutShare {
                        let a = local.workoutShare()?.workout_id
                        let b = msg.workoutShare()?.workout_id
                        return a != nil && a == b
                    }
                    if local.kind == ChatMessageKind.routineShare.rawValue,
                       msg.messageKind == .routineShare {
                        let a = local.routineShare()?.share_nonce
                        let b = msg.routineShare()?.share_nonce
                        return a != nil && !a!.isEmpty && a == b
                    }
                    if local.kind == ChatMessageKind.achievementShare.rawValue,
                       msg.messageKind == .achievementShare {
                        let a = local.achievementShare()?.code
                        let b = msg.achievementShare()?.code
                        return a != nil && a == b && a != ""
                    }
                    if local.kind == ChatMessageKind.segmentShare.rawValue,
                       msg.messageKind == .segmentShare {
                        let a = local.segmentShare()?.segment_id
                        let b = msg.segmentShare()?.segment_id
                        return a != nil && a == b && a != ""
                    }
                    return false
                })
                if let pendingIdx {
                    messages[pendingIdx] = msg
                } else {
                    messages.append(msg)
                }
            }
            Task { await markReadIfNeeded() }
            Task { await refreshSidecarsForNew(messageIds: [msg.id]) }
        case .updated(let msg):
            if let idx = messages.firstIndex(where: { $0.id == msg.id }) {
                messages[idx] = msg
            }
        case .deleted(let id, _):
            messages.removeAll { $0.id == id }
            reactionsByMessageId.removeValue(forKey: id)
        }
    }

    private func refreshSidecars() async {
        let ids = messages.map { $0.id }.filter { $0 > 0 }
        guard !ids.isEmpty else { return }
        do {
            let map = try await ChatService.fetchReactions(messageIds: ids)
            for id in ids {
                self.reactionsByMessageId[id] = map[id] ?? []
            }
        } catch { }

        let replyIds = Set(messages.compactMap { $0.reply_to_message_id })
        if !replyIds.isEmpty {
            do {
                let targets = try await ChatService.fetchReplyTargets(messageIds: Array(replyIds))
                self.replyTargetsById = targets
            } catch { }
        }
    }

    private func refreshSidecarsForNew(messageIds: [Int64]) async {
        let ids = messageIds.filter { $0 > 0 }
        guard !ids.isEmpty else { return }
        do {
            let map = try await ChatService.fetchReactions(messageIds: ids)
            for id in ids {
                if reactionsByMessageId[id] == nil {
                    reactionsByMessageId[id] = map[id] ?? []
                }
            }
        } catch { }

        let needed = messages
            .compactMap { $0.reply_to_message_id }
            .filter { replyTargetsById[$0] == nil }
        if !needed.isEmpty {
            do {
                let targets = try await ChatService.fetchReplyTargets(messageIds: needed)
                for (k, v) in targets { self.replyTargetsById[k] = v }
            } catch { }
        }
    }

    private func refreshPeerLastRead() async {
        guard let me = AppState.shared.userId else { return }
        do {
            self.peerLastReadMessageId = try await ChatService.fetchPeerLastRead(
                conversationId: conversationId, myUserId: me
            )
        } catch { }
    }

    private func loadMutedFlag() async {
        guard let me = AppState.shared.userId else { return }
        struct PartRow: Decodable { let muted: Bool }
        do {
            let res = try await SupabaseManager.shared.client
                .from("conversation_participants")
                .select("muted")
                .eq("conversation_id", value: Int(conversationId))
                .eq("user_id", value: me.uuidString)
                .limit(1)
                .execute()
            let rows = try JSONDecoder.supabase().decode([PartRow].self, from: res.data)
            self.muted = rows.first?.muted ?? false
        } catch { /* best effort */ }
    }

    private func markReadIfNeeded() async {
        guard let last = messages.last else { return }
        guard last.id > 0 else { return }
        do {
            try await ChatService.markRead(conversationId: conversationId, lastMessageId: last.id)
            await AppState.shared.refreshUnreadChatMessagesCount()
        } catch {
            #if DEBUG
            print("[Chat] markRead error:", error)
            #endif
        }
    }
}

struct ChatThreadView: View {
    let conversationId: Int64
    let otherProfile: ChatProfile?

    @EnvironmentObject var app: AppState
    @StateObject private var model: ChatThreadModel
    @State private var draft: String = ""
    @FocusState private var inputFocused: Bool
    @State private var replyingTo: ChatMessage?
    @State private var editingMessage: ChatMessage?
    @State private var showClearConfirm = false
    @State private var openSharedWorkout: SharedWorkoutNav?
    @State private var openSharedRoutine: SharedRoutineNav?
    @State private var openSharedAchievement: SharedAchievementNav?
    @State private var openSharedSegment: SharedSegmentNav?
    @State private var openSharedIngredient: SharedIngredientNav?
    @State private var openSharedRecipe: SharedRecipeNav?
    @State private var banner: Banner?

    init(conversationId: Int64, otherProfile: ChatProfile?) {
        self.conversationId = conversationId
        self.otherProfile = otherProfile
        _model = StateObject(wrappedValue: ChatThreadModel(conversationId: conversationId))
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    if model.hasMore {
                        ProgressView()
                            .padding(8)
                            .onAppear {
                                Task { await model.loadOlderIfNeeded() }
                            }
                    }
                    ForEach(Array(messageItems.enumerated()), id: \.offset) { _, item in
                        switch item {
                        case .day(let label):
                            Text(label)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 6)
                                .padding(.horizontal, 12)
                                .background(Capsule().fill(Color.black.opacity(0.05)))
                                .padding(.vertical, 6)
                        case .message(let msg, let isLastSeenMine):
                            messageRow(msg, isLastSeenMine: isLastSeenMine, scrollProxy: proxy)
                                .id(msg.id)
                        }
                    }
                    if !model.typingUserIds.isEmpty {
                        HStack {
                            Text("\(otherUsernamePrefix) is typing…")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 4)
                    }
                }
                .padding(.vertical, 12)
            }
            .onChange(of: model.messages.count) { _, _ in
                if let last = model.messages.last {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            composer
        }
        .navigationTitle(otherProfile.map { "@\($0.username)" } ?? "Conversation")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $openSharedWorkout) { dest in
            WorkoutDetailView(workoutId: dest.workoutId, ownerId: dest.ownerId)
                .environmentObject(app)
        }
        .navigationDestination(item: $openSharedRoutine) { dest in
            SharedRoutineFromChatView(snapshot: dest.snapshot)
                .environmentObject(app)
        }
        .navigationDestination(item: $openSharedAchievement) { dest in
            SharedAchievementFromChatView(achievementCode: dest.code)
                .environmentObject(app)
        }
        .navigationDestination(item: $openSharedSegment) { dest in
            SegmentDetailView(segmentId: dest.segmentId, onClose: nil)
                .environmentObject(app)
        }
        .navigationDestination(item: $openSharedIngredient) { dest in
            SharedIngredientFromChatView(snapshot: dest.snapshot)
                .environmentObject(app)
        }
        .navigationDestination(item: $openSharedRecipe) { dest in
            SharedRecipeFromChatView(snapshot: dest.snapshot)
                .environmentObject(app)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        Task { await model.setMuted(!model.muted) }
                    } label: {
                        Label(model.muted ? "Unmute" : "Mute",
                              systemImage: model.muted ? "bell" : "bell.slash")
                    }
                    Button(role: .destructive) {
                        showClearConfirm = true
                    } label: {
                        Label("Clear conversation", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .alert("Clear conversation?", isPresented: $showClearConfirm) {
            Button("Clear", role: .destructive) {
                Task { await model.clearConversation() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will hide all messages so far for you. New messages will still arrive.")
        }
        .task {
            await model.loadInitial()
            if let me = app.userId {
                await model.startRealtimeIfNeeded(myUserId: me)
            }
        }
        .onDisappear {
            Task { await model.tearDown() }
        }
        .alert("Couldn't send",
               isPresented: Binding(
                get: { model.error != nil },
                set: { if !$0 { model.error = nil } }
               )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.error ?? "")
        }
        .banner($banner)
    }

    private var otherUsernamePrefix: String {
        otherProfile.map { "@\($0.username)" } ?? "User"
    }

    private enum Item {
        case day(String)
        case message(ChatMessage, isLastSeenMine: Bool)
    }

    private var messageItems: [Item] {
        guard !model.messages.isEmpty else { return [] }
        let myId = app.userId
        let lastSeenMineId: Int64? = {
            guard let myId, let peerLast = model.peerLastReadMessageId else { return nil }
            return model.messages
                .filter { $0.user_id == myId && $0.id > 0 && $0.id <= peerLast }
                .last?.id
        }()
        var out: [Item] = []
        var prev: Date?
        let cal = Calendar.current
        for msg in model.messages {
            let day = cal.startOfDay(for: msg.created_at)
            if prev == nil || cal.startOfDay(for: prev!) != day {
                out.append(.day(Self.daySeparatorText(for: msg.created_at)))
            }
            out.append(.message(msg, isLastSeenMine: msg.id == lastSeenMineId))
            prev = msg.created_at
        }
        return out
    }

    private static func daySeparatorText(for date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        let f = DateFormatter()
        if cal.dateComponents([.year], from: date) == cal.dateComponents([.year], from: Date()) {
            f.setLocalizedDateFormatFromTemplate("d MMM")
        } else {
            f.setLocalizedDateFormatFromTemplate("d MMM yyyy")
        }
        return f.string(from: date)
    }

    @ViewBuilder
    private func messageRow(_ msg: ChatMessage,
                            isLastSeenMine: Bool,
                            scrollProxy: ScrollViewProxy) -> some View {
        let mine = msg.user_id == app.userId
        let deleted = msg.deleted_at != nil
        HStack {
            if mine { Spacer(minLength: 40) }
            VStack(alignment: mine ? .trailing : .leading, spacing: 2) {
                if let replyId = msg.reply_to_message_id,
                   let target = model.replyTargetsById[replyId] {
                    replyPreviewChip(target: target, mine: mine)
                        .onTapGesture {
                            withAnimation { scrollProxy.scrollTo(replyId, anchor: .center) }
                        }
                }

                Group {
                    if deleted {
                        Text("Message deleted")
                            .italic()
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(Color(.tertiarySystemFill))
                            )
                    } else if msg.messageKind == .workoutShare, let snap = msg.workoutShare() {
                        messageWorkoutShareContent(msg: msg, snapshot: snap, mine: mine)
                    } else if msg.messageKind == .routineShare, let rs = msg.routineShare() {
                        messageRoutineShareContent(msg: msg, snapshot: rs, mine: mine)
                    } else if msg.messageKind == .achievementShare, let ach = msg.achievementShare() {
                        messageAchievementShareContent(msg: msg, snapshot: ach, mine: mine)
                    } else if msg.messageKind == .segmentShare, let seg = msg.segmentShare() {
                        messageSegmentShareContent(msg: msg, snapshot: seg, mine: mine)
                    } else if msg.messageKind == .sharedIngredient, let s = msg.sharedIngredient() {
                        messageSharedIngredientContent(msg: msg, snapshot: s, mine: mine)
                    } else if msg.messageKind == .sharedRecipe, let s = msg.sharedRecipe() {
                        messageSharedRecipeContent(msg: msg, snapshot: s, mine: mine)
                    } else if msg.messageKind == .routineShare {
                        Text(msg.body?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                             ? (msg.body ?? "") : String(localized: "Shared routine"))
                            .font(.body)
                            .foregroundStyle(mine ? Color.white : Color.primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(mine ? Color.accentColor : Color(.tertiarySystemFill))
                            )
                            .frame(maxWidth: 320, alignment: mine ? .trailing : .leading)
                    } else if msg.messageKind == .workoutShare {
                        Text(msg.body?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                             ? (msg.body ?? "") : "Shared workout")
                            .font(.body)
                            .foregroundStyle(mine ? Color.white : Color.primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(mine ? Color.accentColor : Color(.tertiarySystemFill))
                            )
                            .frame(maxWidth: 320, alignment: mine ? .trailing : .leading)
                    } else if msg.messageKind == .achievementShare {
                        Text(msg.body?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                             ? (msg.body ?? "") : String(localized: "Shared achievement"))
                            .font(.body)
                            .foregroundStyle(mine ? Color.white : Color.primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(mine ? Color.accentColor : Color(.tertiarySystemFill))
                            )
                            .frame(maxWidth: 320, alignment: mine ? .trailing : .leading)
                    } else if msg.messageKind == .segmentShare {
                        Text(msg.body?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                             ? (msg.body ?? "") : String(localized: "Shared segment"))
                            .font(.body)
                            .foregroundStyle(mine ? Color.white : Color.primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(mine ? Color.accentColor : Color(.tertiarySystemFill))
                            )
                            .frame(maxWidth: 320, alignment: mine ? .trailing : .leading)
                    } else if msg.messageKind == .sharedIngredient {
                        Text(msg.body?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                             ? (msg.body ?? "") : String(localized: "Shared ingredient"))
                            .font(.body)
                            .foregroundStyle(mine ? Color.white : Color.primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(mine ? Color.accentColor : Color(.tertiarySystemFill))
                            )
                            .frame(maxWidth: 320, alignment: mine ? .trailing : .leading)
                    } else if msg.messageKind == .sharedRecipe {
                        Text(msg.body?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                             ? (msg.body ?? "") : String(localized: "Shared recipe"))
                            .font(.body)
                            .foregroundStyle(mine ? Color.white : Color.primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(mine ? Color.accentColor : Color(.tertiarySystemFill))
                            )
                            .frame(maxWidth: 320, alignment: mine ? .trailing : .leading)
                    } else {
                        Text(msg.body ?? "")
                            .font(.body)
                            .foregroundStyle(mine ? Color.white : Color.primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(mine ? Color.accentColor : Color(.tertiarySystemFill))
                            )
                            .frame(maxWidth: 320, alignment: mine ? .trailing : .leading)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    guard !deleted, msg.id > 0, let me = app.userId else { return }
                    Task { await model.toggleReaction(messageId: msg.id, emoji: .heart, myUserId: me) }
                }
                .contextMenu {
                    if !deleted, msg.id > 0 {
                        ForEach(ReactionEmoji.allCases, id: \.self) { emoji in
                            Button {
                                guard let me = app.userId else { return }
                                Task { await model.toggleReaction(messageId: msg.id, emoji: emoji, myUserId: me) }
                            } label: {
                                Text("\(emoji.glyph) React")
                            }
                        }
                        Divider()
                        Button {
                            editingMessage = nil
                            replyingTo = msg
                            inputFocused = true
                        } label: {
                            Label("Reply", systemImage: "arrowshape.turn.up.left")
                        }
                        Button {
                            UIPasteboard.general.string = pasteboardText(for: msg)
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                        if mine, msg.messageKind == .text {
                            Button {
                                replyingTo = nil
                                editingMessage = msg
                                draft = msg.body ?? ""
                                inputFocused = true
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                        }
                        if mine {
                            Button(role: .destructive) {
                                Task { await model.deleteMessage(msg.id) }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }

                let reactions = model.reactionsByMessageId[msg.id] ?? []
                if !reactions.isEmpty {
                    reactionsRow(reactions, mine: mine)
                }

                HStack(spacing: 6) {
                    if !deleted, msg.edited_at != nil {
                        Text("Edited")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text(msg.created_at, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if mine, isLastSeenMine {
                    Text("Seen")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            if !mine { Spacer(minLength: 40) }
        }
        .padding(.horizontal, 12)
    }

    @ViewBuilder
    private func reactionsRow(_ reactions: [MessageReaction], mine: Bool) -> some View {
        let groups = Dictionary(grouping: reactions, by: { $0.emoji })
        let myId = app.userId
        HStack(spacing: 4) {
            ForEach(Array(groups.keys.sorted()), id: \.self) { emojiRaw in
                let arr = groups[emojiRaw] ?? []
                let emoji = ReactionEmoji(rawValue: emojiRaw)
                let mineReacted = arr.contains(where: { $0.user_id == myId })
                Button {
                    guard let me = myId, let resolved = emoji else { return }
                    Task { await model.toggleReaction(messageId: arr.first?.message_id ?? 0,
                                                      emoji: resolved, myUserId: me) }
                } label: {
                    HStack(spacing: 2) {
                        Text(emoji?.glyph ?? "•")
                            .font(.caption)
                        if arr.count > 1 {
                            Text("\(arr.count)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(mineReacted ? Color.accentColor.opacity(0.15) : Color(.tertiarySystemFill))
                    )
                    .overlay(
                        Capsule().stroke(mineReacted ? Color.accentColor : .clear, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
    }

    private func replyPreviewChipText(_ target: ChatService.ReplyPreview) -> String {
        if target.deleted_at != nil { return "Original message was deleted" }
        let trimmed = target.body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty { return trimmed }
        guard let k = target.kind else { return "" }
        if k == ChatMessageKind.workoutShare.rawValue,
           let meta = target.metadata,
           let snap = try? meta.decode(as: WorkoutShareSnapshot.self) {
            return snap.title ?? snap.kind?.capitalized ?? "Workout"
        }
        if k == ChatMessageKind.routineShare.rawValue,
           let meta = target.metadata,
           let snap = try? meta.decode(as: RoutineShareSnapshot.self) {
            return snap.name
        }
        if k == ChatMessageKind.achievementShare.rawValue,
           let meta = target.metadata,
           let snap = try? meta.decode(as: AchievementShareSnapshot.self) {
            return snap.title
        }
        if k == ChatMessageKind.segmentShare.rawValue,
           let meta = target.metadata,
           let snap = try? meta.decode(as: SegmentShareSnapshot.self) {
            return snap.name
        }
        if k == ChatMessageKind.sharedIngredient.rawValue,
           let meta = target.metadata,
           let snap = try? meta.decode(as: SharedIngredientSnapshot.self) {
            return snap.name
        }
        if k == ChatMessageKind.sharedRecipe.rawValue,
           let meta = target.metadata,
           let snap = try? meta.decode(as: SharedRecipeSnapshot.self) {
            return snap.name
        }
        return ""
    }

    @ViewBuilder
    private func replyPreviewChip(target: ChatService.ReplyPreview, mine: Bool) -> some View {
        let preview = replyPreviewChipText(target)
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.accentColor)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                Text("Reply")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(preview)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(.tertiarySystemFill))
        )
        .frame(maxWidth: 280, alignment: mine ? .trailing : .leading)
    }

    @ViewBuilder
    private var composer: some View {
        VStack(spacing: 0) {
            if let target = replyingTo {
                composerContextBanner(
                    title: "Replying",
                    subtitle: replyBannerPreview(for: target),
                    onCancel: { replyingTo = nil }
                )
            } else if let target = editingMessage {
                composerContextBanner(
                    title: "Editing",
                    subtitle: target.body ?? "",
                    onCancel: cancelEdit
                )
            }

            HStack(alignment: .bottom, spacing: 8) {
                TextField("Message…", text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .focused($inputFocused)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color(.tertiarySystemFill))
                    )
                    .onChange(of: draft) { _, newValue in
                        model.updateTyping(text: newValue)
                    }

                Button {
                    Task { await submitCurrent() }
                } label: {
                    Group {
                        if editingMessage != nil {
                            Image(systemName: "checkmark")
                        } else {
                            Image(systemName: "paperplane.fill")
                        }
                    }
                    .font(.body.weight(.semibold))
                    .frame(width: 36, height: 36)
                    .background(Color.accentColor.opacity(canSubmit ? 1 : 0.3), in: Circle())
                    .foregroundStyle(.white)
                }
                .disabled(!canSubmit)
                .accessibilityLabel(editingMessage != nil ? "Save" : "Send")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private func composerContextBanner(title: String,
                                       subtitle: String,
                                       onCancel: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.accentColor)
                .frame(width: 3, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(subtitle)
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.caption)
                    .padding(6)
                    .background(Circle().fill(Color(.tertiarySystemFill)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cancel")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var canSubmit: Bool {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if let editing = editingMessage {
            let original = editing.body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed != original
        }
        return true
    }

    @MainActor
    private func submitCurrent() async {
        if editingMessage != nil {
            await saveCurrent()
        } else {
            await sendCurrent()
        }
    }

    @MainActor
    private func saveCurrent() async {
        guard let editing = editingMessage, canSubmit else { return }
        let text = draft
        editingMessage = nil
        draft = ""
        model.updateTyping(text: "")
        await model.editMessage(editing.id, body: text)
    }

    private func cancelEdit() {
        editingMessage = nil
        draft = ""
        model.updateTyping(text: "")
    }

    @MainActor
    private func sendCurrent() async {
        guard let me = app.userId, canSubmit else { return }
        let text = draft
        let replyId = replyingTo?.id
        draft = ""
        replyingTo = nil
        model.updateTyping(text: "")
        await model.send(text: text, myUserId: me, replyTo: replyId)
    }

    @ViewBuilder
    private func messageWorkoutShareContent(msg: ChatMessage, snapshot: WorkoutShareSnapshot, mine: Bool) -> some View {
        VStack(alignment: mine ? .trailing : .leading, spacing: 6) {
            if let cap = msg.body?.trimmingCharacters(in: .whitespacesAndNewlines), !cap.isEmpty {
                Text(cap)
                    .font(.body)
                    .foregroundStyle(mine ? Color.white : Color.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(mine ? Color.accentColor.opacity(0.92) : Color(.tertiarySystemFill))
                    )
                    .frame(maxWidth: 280, alignment: mine ? .trailing : .leading)
            }
            ChatThreadWorkoutShareCard(snapshot: snapshot, mine: mine) {
                if let oid = snapshot.owner_user_id {
                    openSharedWorkout = SharedWorkoutNav(
                        workoutId: Int(snapshot.workout_id),
                        ownerId: oid
                    )
                }
            }
        }
    }

    private func replyBannerPreview(for msg: ChatMessage) -> String {
        if msg.messageKind == .workoutShare {
            let t = msg.body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return t.isEmpty ? "Workout" : t
        }
        if msg.messageKind == .routineShare {
            let t = msg.body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return t.isEmpty ? String(localized: "Routine") : t
        }
        if msg.messageKind == .achievementShare {
            let t = msg.body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !t.isEmpty { return t }
            return msg.achievementShare()?.title ?? String(localized: "Achievement")
        }
        if msg.messageKind == .segmentShare {
            let t = msg.body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !t.isEmpty { return t }
            return msg.segmentShare()?.name ?? String(localized: "Segment")
        }
        if msg.messageKind == .sharedIngredient {
            let t = msg.body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !t.isEmpty { return t }
            return msg.sharedIngredient()?.name ?? String(localized: "Ingredient")
        }
        if msg.messageKind == .sharedRecipe {
            let t = msg.body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !t.isEmpty { return t }
            return msg.sharedRecipe()?.name ?? String(localized: "Recipe")
        }
        return msg.body ?? ""
    }

    private func pasteboardText(for msg: ChatMessage) -> String {
        if msg.messageKind == .workoutShare, let s = msg.workoutShare() {
            let cap = msg.body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let title = s.title ?? s.kind?.capitalized ?? "Workout"
            if cap.isEmpty { return title }
            return "\(cap)\n\(title)"
        }
        if msg.messageKind == .routineShare, let s = msg.routineShare() {
            let cap = msg.body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let title = s.name
            if cap.isEmpty { return title }
            return "\(cap)\n\(title)"
        }
        if msg.messageKind == .achievementShare, let s = msg.achievementShare() {
            let cap = msg.body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let title = s.title
            if cap.isEmpty { return title }
            return "\(cap)\n\(title)"
        }
        if msg.messageKind == .segmentShare, let s = msg.segmentShare() {
            let cap = msg.body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let title = s.name
            if cap.isEmpty { return title }
            return "\(cap)\n\(title)"
        }
        if msg.messageKind == .sharedIngredient, let s = msg.sharedIngredient() {
            let cap = msg.body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let title = s.name
            if cap.isEmpty { return title }
            return "\(cap)\n\(title)"
        }
        if msg.messageKind == .sharedRecipe, let s = msg.sharedRecipe() {
            let cap = msg.body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let title = s.name
            if cap.isEmpty { return title }
            return "\(cap)\n\(title)"
        }
        return msg.body ?? ""
    }

    private var saveToLibraryButtonTitle: String {
        if AppLanguage.isSpanish {
            return "Añadir a mis elementos"
        }
        return "Save to Library"
    }

    private var sharedIngredientLabel: String {
        if AppLanguage.isSpanish {
            return "Ingrediente"
        }
        return "Ingredient"
    }

    private var sharedRecipeLabel: String {
        if AppLanguage.isSpanish {
            return "Receta"
        }
        return "Recipe"
    }

    private func macroSummaryLine(calories: Double, protein: Double, carbs: Double, fat: Double) -> String {
        let c = Int(calories.rounded())
        let p = Int(protein.rounded())
        let ca = Int(carbs.rounded())
        let f = Int(fat.rounded())
        return "\(c) kcal · P \(p)g · C \(ca)g · F \(f)g"
    }

    @ViewBuilder
    private func messageSharedIngredientContent(msg: ChatMessage, snapshot: SharedIngredientSnapshot, mine: Bool) -> some View {
        VStack(alignment: mine ? .trailing : .leading, spacing: 6) {
            if let cap = msg.body?.trimmingCharacters(in: .whitespacesAndNewlines), !cap.isEmpty {
                Text(cap)
                    .font(.body)
                    .foregroundStyle(mine ? Color.white : Color.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(mine ? Color.accentColor.opacity(0.92) : Color(.tertiarySystemFill))
                    )
                    .frame(maxWidth: 280, alignment: mine ? .trailing : .leading)
            }
            SharedNutritionPreviewCard(
                kindLabel: sharedIngredientLabel,
                title: snapshot.name,
                subtitle: macroSummaryLine(
                    calories: snapshot.calories_per_100g,
                    protein: snapshot.protein_per_100g,
                    carbs: snapshot.carbs_per_100g,
                    fat: snapshot.fat_per_100g
                ),
                mine: mine
            ) {
                openSharedIngredient = SharedIngredientNav(snapshot: snapshot)
            }
        }
    }

    @ViewBuilder
    private func messageSharedRecipeContent(msg: ChatMessage, snapshot: SharedRecipeSnapshot, mine: Bool) -> some View {
        let subtitle: String = {
            if let p = snapshot.profile_per_100g {
                return macroSummaryLine(calories: p.calories, protein: p.protein, carbs: p.carbs, fat: p.fat)
            }
            return "\(snapshot.ingredients.count) ingredients"
        }()

        VStack(alignment: mine ? .trailing : .leading, spacing: 6) {
            if let cap = msg.body?.trimmingCharacters(in: .whitespacesAndNewlines), !cap.isEmpty {
                Text(cap)
                    .font(.body)
                    .foregroundStyle(mine ? Color.white : Color.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(mine ? Color.accentColor.opacity(0.92) : Color(.tertiarySystemFill))
                    )
                    .frame(maxWidth: 280, alignment: mine ? .trailing : .leading)
            }
            SharedNutritionPreviewCard(
                kindLabel: sharedRecipeLabel,
                title: snapshot.name,
                subtitle: subtitle,
                mine: mine
            ) {
                openSharedRecipe = SharedRecipeNav(snapshot: snapshot)
            }
        }
    }

    @ViewBuilder
    private func messageRoutineShareContent(msg: ChatMessage, snapshot: RoutineShareSnapshot, mine: Bool) -> some View {
        VStack(alignment: mine ? .trailing : .leading, spacing: 6) {
            if let cap = msg.body?.trimmingCharacters(in: .whitespacesAndNewlines), !cap.isEmpty {
                Text(cap)
                    .font(.body)
                    .foregroundStyle(mine ? Color.white : Color.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(mine ? Color.accentColor.opacity(0.92) : Color(.tertiarySystemFill))
                    )
                    .frame(maxWidth: 280, alignment: mine ? .trailing : .leading)
            }
            ChatThreadRoutineShareCard(snapshot: snapshot, mine: mine) {
                openSharedRoutine = SharedRoutineNav(snapshot: snapshot)
            }
        }
    }

    @ViewBuilder
    private func messageAchievementShareContent(msg: ChatMessage, snapshot: AchievementShareSnapshot, mine: Bool) -> some View {
        VStack(alignment: mine ? .trailing : .leading, spacing: 6) {
            if let cap = msg.body?.trimmingCharacters(in: .whitespacesAndNewlines), !cap.isEmpty {
                Text(cap)
                    .font(.body)
                    .foregroundStyle(mine ? Color.white : Color.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(mine ? Color.accentColor.opacity(0.92) : Color(.tertiarySystemFill))
                    )
                    .frame(maxWidth: 280, alignment: mine ? .trailing : .leading)
            }
            ChatThreadAchievementShareCard(snapshot: snapshot, mine: mine) {
                openSharedAchievement = SharedAchievementNav(code: snapshot.code)
            }
        }
    }

    @ViewBuilder
    private func messageSegmentShareContent(msg: ChatMessage, snapshot: SegmentShareSnapshot, mine: Bool) -> some View {
        VStack(alignment: mine ? .trailing : .leading, spacing: 6) {
            if let cap = msg.body?.trimmingCharacters(in: .whitespacesAndNewlines), !cap.isEmpty {
                Text(cap)
                    .font(.body)
                    .foregroundStyle(mine ? Color.white : Color.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(mine ? Color.accentColor.opacity(0.92) : Color(.tertiarySystemFill))
                    )
                    .frame(maxWidth: 280, alignment: mine ? .trailing : .leading)
            }
            ChatThreadSegmentShareCard(snapshot: snapshot, mine: mine) {
                if let u = UUID(uuidString: snapshot.segment_id) {
                    openSharedSegment = SharedSegmentNav(segmentId: u)
                }
            }
        }
    }
}

private struct SharedWorkoutNav: Identifiable, Hashable {
    let workoutId: Int
    let ownerId: UUID
    var id: String { "\(workoutId)|\(ownerId.uuidString)" }
}

private struct SharedRoutineNav: Identifiable, Hashable {
    let snapshot: RoutineShareSnapshot
    var id: String { snapshot.share_nonce }
}

private struct SharedAchievementNav: Identifiable, Hashable {
    let code: String
    var id: String { code }
}

private struct SharedSegmentNav: Identifiable, Hashable {
    let segmentId: UUID
    var id: UUID { segmentId }
}

private struct SharedIngredientNav: Identifiable, Hashable {
    let snapshot: SharedIngredientSnapshot
    var id: String { "ingredient|\(snapshot.name)|\(snapshot.v)" }
}

private struct SharedRecipeNav: Identifiable, Hashable {
    let snapshot: SharedRecipeSnapshot
    var id: String { "recipe|\(snapshot.name)|\(snapshot.v)" }
}

private struct SharedAchievementFromChatView: View {
    let achievementCode: String
    @EnvironmentObject var app: AppState

    var body: some View {
        AchievementsGridView(userId: app.userId, viewedUsername: "", openAchievementCode: achievementCode)
            .navigationTitle("Achievements")
            .navigationBarTitleDisplayMode(.inline)
            .gradientBG()
    }
}

private struct ChatThreadAchievementShareCard: View {
    let snapshot: AchievementShareSnapshot
    let mine: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 10) {
                AvatarView(urlString: snapshot.owner_avatar_url)
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(ownerLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(String(localized: "Achievement"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(snapshot.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                    Text(snapshot.category.capitalized)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: 280, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.tertiarySystemFill))
            )
        }
        .buttonStyle(.plain)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(mine ? Color.accentColor.opacity(0.45) : Color.clear, lineWidth: mine ? 1 : 0)
        )
    }

    private var ownerLabel: String {
        let u = snapshot.owner_username ?? "user"
        if u.hasPrefix("@") { return u }
        return "@\(u)"
    }
}

private struct ChatThreadSegmentShareCard: View {
    let snapshot: SegmentShareSnapshot
    let mine: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 10) {
                AvatarView(urlString: snapshot.owner_avatar_url)
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(ownerLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(String(localized: "Segment"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(snapshot.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                    if let len = snapshot.segment_length_m, len > 0 {
                        Text("\(Int(len.rounded())) m")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if let n = snapshot.leaderboard_effort_count, n > 0 {
                        Text("\(n) efforts")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: 280, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.tertiarySystemFill))
            )
        }
        .buttonStyle(.plain)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(mine ? Color.accentColor.opacity(0.45) : Color.clear, lineWidth: mine ? 1 : 0)
        )
    }

    private var ownerLabel: String {
        let u = snapshot.owner_username ?? "user"
        if u.hasPrefix("@") { return u }
        return "@\(u)"
    }
}

private struct ChatThreadRoutineShareCard: View {
    let snapshot: RoutineShareSnapshot
    let mine: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 10) {
                AvatarView(urlString: snapshot.owner_avatar_url)
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(ownerLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(kindSubtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(snapshot.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                    ForEach(Array(routineMetaLines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: 280, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.tertiarySystemFill))
            )
        }
        .buttonStyle(.plain)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(mine ? Color.accentColor.opacity(0.45) : Color.clear, lineWidth: mine ? 1 : 0)
        )
    }

    private var ownerLabel: String {
        let u = snapshot.owner_username ?? "user"
        if u.hasPrefix("@") { return u }
        return "@\(u)"
    }

    private var kindSubtitle: String {
        if snapshot.routine_kind == "hyrox" { return String(localized: "Hyrox routine") }
        if snapshot.routine_kind == "strength" { return String(localized: "Strength routine") }
        return snapshot.routine_kind
    }

    private var routineMetaLines: [String] {
        var lines: [String] = []
        if let n = snapshot.exercise_count, n > 0 {
            if snapshot.routine_kind == "hyrox" {
                lines.append(
                    String.localizedStringWithFormat(
                        String(localized: "routine_share_stations_count_format"),
                        n
                    )
                )
            } else {
                lines.append(
                    String.localizedStringWithFormat(
                        String(localized: "routine_share_exercises_count_format"),
                        n
                    )
                )
            }
        }
        if let ts = snapshot.total_sets, ts > 0, snapshot.routine_kind == "strength" {
            lines.append(
                String.localizedStringWithFormat(
                    String(localized: "routine_share_sets_count_format"),
                    ts
                )
            )
        }
        if let p = snapshot.preview_exercise_name?.trimmingCharacters(in: .whitespacesAndNewlines), !p.isEmpty {
            lines.append(p)
        }
        if let rel = routineShareUpdatedRelative(from: snapshot.updated_at) {
            lines.append("\(String(localized: "Updated")) \(rel)")
        }
        return lines
    }

    private func routineShareUpdatedRelative(from iso: String?) -> String? {
        guard let raw = iso?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var d = f.date(from: raw)
        if d == nil {
            f.formatOptions = [.withInternetDateTime]
            d = f.date(from: raw)
        }
        guard let date = d else { return nil }
        let r = RelativeDateTimeFormatter()
        r.dateTimeStyle = .named
        return r.localizedString(for: date, relativeTo: Date())
    }
}

private struct ChatThreadWorkoutShareCard: View {
    let snapshot: WorkoutShareSnapshot
    let mine: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack {
                WorkoutCardBackground(kind: snapshot.kind ?? "")
                HStack(alignment: .top, spacing: 10) {
                    AvatarView(urlString: snapshot.owner_avatar_url)
                        .frame(width: 36, height: 36)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(ownerLabel)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(snapshot.title ?? (snapshot.kind?.capitalized ?? "Workout"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                        if let rel = performedRelative {
                            Text(rel)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 6) {
                        if let k = snapshot.kcal, k > 0 {
                            caloriesPill(kcal: Double(k), kind: snapshot.kind ?? "strength")
                        }
                        if let s = snapshot.score {
                            scorePill(score: Double(s), kind: snapshot.kind ?? "strength")
                        }
                    }
                    .scaleEffect(0.88)
                    .frame(maxWidth: 140, alignment: .trailing)
                }
                .padding(10)
            }
            .frame(maxWidth: 280)
        }
        .buttonStyle(.plain)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(mine ? Color.white.opacity(0.35) : Color.clear, lineWidth: mine ? 1 : 0)
        )
    }

    private var ownerLabel: String {
        let u = snapshot.owner_username ?? "user"
        if u.hasPrefix("@") { return u }
        return "@\(u)"
    }

    private var performedRelative: String? {
        guard let raw = snapshot.performed_at, !raw.isEmpty else { return nil }
        let fFrac = ISO8601DateFormatter()
        fFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fPlain = ISO8601DateFormatter()
        fPlain.formatOptions = [.withInternetDateTime]
        guard let d = fFrac.date(from: raw) ?? fPlain.date(from: raw) else { return nil }
        let r = RelativeDateTimeFormatter()
        r.unitsStyle = .short
        return r.localizedString(for: d, relativeTo: Date())
    }
}

private struct SharedNutritionPreviewCard: View {
    let kindLabel: String
    let title: String
    let subtitle: String
    let mine: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.accentColor.opacity(0.14))
                    Image(systemName: kindLabel.lowercased().contains("rec") ? "fork.knife" : "leaf")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
                .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 3) {
                    Text(kindLabel)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: 280, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.tertiarySystemFill))
            )
        }
        .buttonStyle(.plain)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(mine ? Color.accentColor.opacity(0.45) : Color.clear, lineWidth: mine ? 1 : 0)
        )
    }
}
