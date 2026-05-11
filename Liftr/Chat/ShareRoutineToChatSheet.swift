import SwiftUI

struct ShareRoutineToChatSheet: View {
    let snapshot: RoutineShareSnapshot
    var onSent: () -> Void

    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = ShareWorkoutToChatPickerModel()
    @State private var showNewChat = false
    @State private var sendError: String?

    var body: some View {
        NavigationStack {
            ZStack {
                GradientBackground().ignoresSafeArea()
                content
            }
            .navigationTitle(String(localized: "Send routine"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(String(localized: "Cancel")) { dismiss() }
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
                        await sendToNew(profile: profile)
                    }
                }
                .environmentObject(app)
                .gradientBG()
            }
            .alert(String(localized: "Couldn't send"),
                   isPresented: Binding(
                    get: { sendError != nil },
                    set: { if !$0 { sendError = nil } }
                   )) {
                Button(String(localized: "OK"), role: .cancel) {}
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
                Text(String(localized: "Couldn't load conversations"))
                    .font(.headline)
                Text(err)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button(String(localized: "Retry")) { Task { await model.reload() } }
                    .buttonStyle(.borderedProminent)
            }
            .padding()
        } else if model.rows.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(.secondary)
                Text(String(localized: "No conversations yet"))
                    .font(.headline)
                Text(String(localized: "Tap + to start a chat, then send this routine."))
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
            _ = try await ChatService.sendRoutineShare(conversationId: conversationId, snapshot: snapshot)
            onSent()
            dismiss()
        } catch {
            sendError = error.localizedDescription
        }
    }

    private func sendToNew(profile: ChatProfile) async {
        do {
            let cid = try await ChatService.startDirect(with: profile.user_id)
            _ = try await ChatService.sendRoutineShare(conversationId: cid, snapshot: snapshot)
            await MainActor.run {
                showNewChat = false
                onSent()
                dismiss()
            }
        } catch {
            await MainActor.run {
                sendError = ShareWorkoutToChatPickerModel.friendlyStartError(error)
            }
        }
    }
}
