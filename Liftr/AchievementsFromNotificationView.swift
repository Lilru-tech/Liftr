import SwiftUI

struct AchievementsFromNotificationView: View {
    let userId: UUID
    let viewedUsername: String
    let showsCloseButton: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var reloadToken = UUID()

    var body: some View {
        NavigationStack {
            AchievementsGridView(
                userId: userId,
                viewedUsername: viewedUsername,
                externalReloadToken: reloadToken
            )
            .navigationTitle("Achievements")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if showsCloseButton {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .accessibilityLabel("Close")
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        reloadToken = UUID()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Reload")
                }
            }
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }
}
