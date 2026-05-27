import SwiftUI

struct MentionComposerField: View {
    @Binding var text: String
    @Binding var trackedMentions: [MentionUser]
    let followees: [FolloweesService.Profile]
    var placeholder: String = "Add a comment..."
    var onRequestFollowees: (() -> Void)?

    @FocusState private var focused: Bool
    @State private var showPicker = false
    @State private var mentionQuery = ""

    private var filteredFollowees: [FolloweesService.Profile] {
        let q = mentionQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return followees }
        return followees.filter { $0.username.lowercased().contains(q) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if showPicker {
                mentionPicker
            }
            TextField(placeholder, text: $text, axis: .vertical)
                .lineLimit(1...5)
                .focused($focused)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(.tertiarySystemFill))
                )
                .onChange(of: text) { _, newValue in
                    handleTextChange(newValue)
                }
        }
    }

    private var mentionPicker: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if filteredFollowees.isEmpty {
                    Text("No users found")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(12)
                } else {
                    ForEach(filteredFollowees) { profile in
                        Button {
                            insertMention(profile)
                        } label: {
                            HStack(spacing: 10) {
                                AvatarView(urlString: profile.avatar_url)
                                    .frame(width: 32, height: 32)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                Text("@\(profile.username)")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(maxHeight: 160)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func handleTextChange(_ newText: String) {
        let cursor = (newText as NSString).length
        if let active = MentionTextSupport.activeMentionQuery(in: newText, cursorUTF16Offset: cursor) {
            mentionQuery = active.query
            showPicker = true
            onRequestFollowees?()
        } else {
            showPicker = false
            mentionQuery = ""
        }
    }

    private func insertMention(_ profile: FolloweesService.Profile) {
        let mention = MentionUser(profile: profile)
        if !trackedMentions.contains(where: { $0.userId == mention.userId }) {
            trackedMentions.append(mention)
        }

        let token = "@\(profile.username) "
        let cursor = (text as NSString).length
        let replacementRange: Range<String.Index>?

        if let active = MentionTextSupport.activeMentionQuery(in: text, cursorUTF16Offset: cursor) {
            replacementRange = active.range
        } else if let at = text.range(of: "@", options: .backwards) {
            let after = text[at.upperBound...]
            if !after.contains(where: { $0.isWhitespace || $0.isNewline }) {
                replacementRange = at.lowerBound..<text.endIndex
            } else {
                replacementRange = nil
            }
        } else {
            replacementRange = nil
        }

        if let range = replacementRange {
            text.replaceSubrange(range, with: token)
        } else if text.isEmpty {
            text = token
        } else {
            text += " \(token)"
        }

        showPicker = false
        mentionQuery = ""
        focused = true
    }
}
