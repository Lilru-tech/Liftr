import SwiftUI

struct CommentMentionText: View {
    let text: String
    let usernameToUserId: [String: UUID]
    var onMentionTap: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(text.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                lineView(line)
            }
        }
    }

    @ViewBuilder
    private func lineView(_ line: String) -> some View {
        if let attributed = attributedLine(line) {
            Text(attributed)
                .font(.subheadline)
                .environment(\.openURL, OpenURLAction { url in
                    guard url.scheme == "liftr-profile",
                          let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                          let idStr = components.queryItems?.first(where: { $0.name == "id" })?.value,
                          let userId = UUID(uuidString: idStr) else {
                        return .systemAction
                    }
                    onMentionTap(userId)
                    return .handled
                })
        } else {
            Text(line)
                .font(.subheadline)
        }
    }

    private func attributedLine(_ line: String) -> AttributedString? {
        let segments = MentionTextSupport.mentionSegments(in: line)
        guard segments.contains(where: \.1) else { return nil }

        var result = AttributedString(line)
        for segment in segments where segment.1 {
            let username = String(segment.0.dropFirst())
            guard let userId = usernameToUserId[username],
                  let range = result.range(of: segment.0) else { continue }
            result[range].foregroundColor = .blue
            result[range].font = .subheadline.bold()
            result[range].link = URL(string: "liftr-profile://mention?id=\(userId.uuidString)")
        }
        return result
    }
}
