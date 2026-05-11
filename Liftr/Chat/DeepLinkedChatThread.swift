import SwiftUI

struct DeepLinkedChatThread: View {
    let conversationId: Int64
    let senderId: UUID?
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var resolvedProfile: ChatProfile?

    var body: some View {
        ChatThreadView(conversationId: conversationId, otherProfile: resolvedProfile)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await resolve() }
    }

    private func resolve() async {
        guard let me = app.userId else { return }
        if let sid = senderId {
            self.resolvedProfile = try? await ChatService.fetchProfile(userId: sid)
        } else {
            self.resolvedProfile = try? await ChatService.fetchOtherParticipant(
                conversationId: conversationId, myUserId: me
            )
        }
    }
}
