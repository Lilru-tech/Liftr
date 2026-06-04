import SwiftUI

@MainActor
final class ShareIngredientToChatPickerModel: ObservableObject {
    @Published var loading = false
    @Published var rows: [ConversationOverview] = []
    @Published var profilesByUserId: [UUID: ChatProfile] = [:]
    @Published var otherUserByConversationId: [Int64: UUID] = [:]
    @Published var error: String?
    @Published var sendBusyConversationId: Int64?

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
        } catch {}
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

struct ShareIngredientToChatSheet: View {
    let snapshot: SharedIngredientSnapshot
    var onSent: () -> Void

    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = ShareIngredientToChatPickerModel()
    @State private var showNewChat = false
    @State private var sendError: String?

    var body: some View {
        NavigationStack {
            ZStack {
                GradientBackground().ignoresSafeArea()
                content
            }
            .navigationTitle("Send ingredient")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
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
                    Task { await sendToNew(profile: profile) }
                }
                .environmentObject(app)
                .gradientBG()
            }
            .alert("Couldn't send",
                   isPresented: Binding(
                    get: { sendError != nil },
                    set: { if !$0 { sendError = nil } }
                   )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(sendError ?? "")
            }
            .task { await model.reload() }
            .refreshable { await model.reload() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.loading && model.rows.isEmpty {
            ProgressView()
        } else if let err = model.error, model.rows.isEmpty {
            VStack(spacing: 12) {
                Text("Couldn't load conversations")
                    .font(.headline)
                Text(err)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Retry") { Task { await model.reload() } }
                    .buttonStyle(.borderedProminent)
            }
            .padding()
        } else if model.rows.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(.secondary)
                Text("No conversations yet")
                    .font(.headline)
                Text("Tap + to start a chat, then send this ingredient.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)
        } else {
            List {
                ForEach(model.rows) { row in
                    let otherId = model.otherUserByConversationId[row.id]
                    let profile = otherId.flatMap { model.profilesByUserId[$0] }
                    let busy = model.sendBusyConversationId == row.id
                    Button {
                        Task { await send(to: row.id) }
                    } label: {
                        HStack(alignment: .center, spacing: 12) {
                            AvatarView(urlString: profile?.avatar_url)
                                .frame(width: 44, height: 44)
                                .clipShape(Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text(profile.map { "@\($0.username)" } ?? row.title ?? "Conversation")
                                    .font(.body.weight(.semibold))
                                    .lineLimit(1)
                                Text(row.last_message_body?.isEmpty == false ? row.last_message_body! : "Say hi")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 8)
                            if busy {
                                ProgressView()
                            }
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(busy)
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private func send(to conversationId: Int64) async {
        model.sendBusyConversationId = conversationId
        defer { model.sendBusyConversationId = nil }
        do {
            _ = try await ChatService.sendSharedIngredient(conversationId: conversationId, snapshot: snapshot)
            onSent()
            dismiss()
        } catch {
            sendError = error.localizedDescription
        }
    }

    private func sendToNew(profile: ChatProfile) async {
        do {
            let cid = try await ChatService.startDirect(with: profile.user_id)
            _ = try await ChatService.sendSharedIngredient(conversationId: cid, snapshot: snapshot)
            await MainActor.run {
                showNewChat = false
                onSent()
                dismiss()
            }
        } catch {
            await MainActor.run {
                sendError = ShareIngredientToChatPickerModel.friendlyStartError(error)
            }
        }
    }
}

