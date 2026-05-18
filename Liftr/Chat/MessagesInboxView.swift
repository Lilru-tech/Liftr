import SwiftUI

@MainActor
final class MessagesInboxModel: ObservableObject {
    @Published var loading = false
    @Published var rows: [ConversationOverview] = []
    @Published var profilesByUserId: [UUID: ChatProfile] = [:]
    @Published var otherUserByConversationId: [Int64: UUID] = [:]
    @Published var error: String?

    private let inboxRealtime = ChatInboxRealtime()
    private var realtimeStarted = false

    func reload() async {
        loading = true
        defer { loading = false }
        do {
            let list = try await ChatService.fetchConversations(limit: 100)
            self.rows = list
            self.error = nil
            await refreshSidecars(for: list)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func refreshSidecars(for list: [ConversationOverview]) async {
        guard let me = AppState.shared.userId, !list.isEmpty else { return }
        do {
            struct PartRow: Decodable { let conversation_id: Int64; let user_id: UUID }
            let res = try await SupabaseManager.shared.client
                .from("conversation_participants")
                .select("conversation_id, user_id")
                .in("conversation_id", values: list.map { Int($0.id) })
                .neq("user_id", value: me.uuidString)
                .limit(list.count * 8)
                .execute()
            let parts = try JSONDecoder.supabase().decode([PartRow].self, from: res.data)

            var map: [Int64: UUID] = [:]
            for p in parts where map[p.conversation_id] == nil {
                map[p.conversation_id] = p.user_id
            }
            self.otherUserByConversationId = map

            let unique = Array(Set(map.values))
            let profiles = try await ChatService.fetchProfiles(userIds: unique)
            self.profilesByUserId = profiles
        } catch {
        }
    }

    func startRealtimeIfNeeded() async {
        guard !realtimeStarted, let me = AppState.shared.userId else { return }
        realtimeStarted = true
        await inboxRealtime.start(myUserId: me) { [weak self] in
            Task { @MainActor [weak self] in
                await self?.reload()
            }
        }
    }

    func tearDown() async {
        await inboxRealtime.stop()
        realtimeStarted = false
    }

    func startDirect(with profile: ChatProfile) async -> Int64? {
        do {
            let id = try await ChatService.startDirect(with: profile.user_id)
            self.profilesByUserId[profile.user_id] = profile
            self.otherUserByConversationId[id] = profile.user_id
            await reload()
            return id
        } catch {
            self.error = Self.friendlyStartError(error)
            return nil
        }
    }

    func clearConversation(_ conversationId: Int64) async {
        let removed = rows.first(where: { $0.id == conversationId })
        rows.removeAll { $0.id == conversationId }
        do {
            try await ChatService.clearConversation(conversationId)
        } catch {
            if let removed { rows.append(removed) }
            self.error = error.localizedDescription
        }
    }

    static func friendlyStartError(_ error: Error) -> String {
        let raw = "\(error)".lowercased()
        if raw.contains("not_mutual_follow") {
            return "You can only DM people who follow you back."
        }
        if raw.contains("cannot_dm_self") {
            return "You can't message yourself."
        }
        return error.localizedDescription
    }
}

struct MessagesInboxView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = MessagesInboxModel()

    @State private var showNewChat = false
    @State private var pendingThread: ThreadDestination?

    private struct ThreadDestination: Identifiable, Hashable {
        let id: Int64
        let other: ChatProfile?
    }

    var body: some View {
        NavigationStack {
            ZStack {
                GradientBackground().ignoresSafeArea()
                content
            }
            .navigationTitle("Messages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showNewChat = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showNewChat) {
                NewChatView { profile in
                    Task {
                        if let id = await model.startDirect(with: profile) {
                            await MainActor.run {
                                self.showNewChat = false
                                self.pendingThread = ThreadDestination(id: id, other: profile)
                            }
                        }
                    }
                }
                .gradientBG()
            }
            .navigationDestination(item: $pendingThread) { dest in
                ChatThreadView(conversationId: dest.id, otherProfile: dest.other)
                    .gradientBG()
            }
            .task { await model.reload() }
            .task { await model.startRealtimeIfNeeded() }
            .refreshable { await model.reload() }
            .onDisappear { Task { await model.tearDown() } }
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.loading && model.rows.isEmpty {
            ProgressView()
        } else if let error = model.error, model.rows.isEmpty {
            VStack(spacing: 12) {
                Text("Couldn't load messages")
                    .font(.headline)
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Retry") { Task { await model.reload() } }
                    .buttonStyle(.borderedProminent)
            }
            .padding()
        } else if model.rows.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "paperplane")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(.secondary)
                Text("No conversations yet")
                    .font(.headline)
                Text("Tap + to start a chat with someone you follow.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)
        } else {
            List {
                ForEach(model.rows) { row in
                    Button {
                        let other = model.otherUserByConversationId[row.id]
                            .flatMap { model.profilesByUserId[$0] }
                        pendingThread = ThreadDestination(id: row.id, other: other)
                    } label: {
                        rowView(row)
                    }
                    .listRowBackground(Color.clear)
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            Task { await model.clearConversation(row.id) }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    @ViewBuilder
    private func rowView(_ row: ConversationOverview) -> some View {
        let otherId = model.otherUserByConversationId[row.id]
        let profile = otherId.flatMap { model.profilesByUserId[$0] }
        HStack(alignment: .center, spacing: 12) {
            AvatarView(urlString: profile?.avatar_url)
                .frame(width: 44, height: 44)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(profile.map { "@\($0.username)" } ?? row.title ?? "Conversation")
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if let when = row.last_message_at {
                        Text(Self.shortDate(when))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(alignment: .top) {
                    Text(Self.previewText(for: row))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Spacer(minLength: 8)
                    if row.unread_count > 0 {
                        Text("\(row.unread_count)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.accentColor, in: Capsule())
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private static func shortDate(_ d: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: d, relativeTo: Date())
    }

    private static func previewText(for row: ConversationOverview) -> String {
        let preview = row.last_message_body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return preview.isEmpty ? "Say hi" : preview
    }
}
