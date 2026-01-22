import SwiftUI

struct FeatureRequestDetailView: View {
    @EnvironmentObject var app: AppState

    let fr: FeatureRequestRow

    @State private var loading = false
    @State private var error: String?
    @State private var comments: [FeatureRequestCommentRow] = []

    @State private var newComment: String = ""
    @State private var isSending = false

    var body: some View {
        VStack(spacing: 14) {
            headerCard

            commentsSection

            if app.userId != nil {
                composerCard
            } else {
                Text("Log in to comment.")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
            }
        }
        .padding(.top, 10)
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadComments() }
        .refreshable { await loadComments() }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(fr.title)
                    .font(.title3.weight(.semibold))
                    .lineLimit(2)
            }

            Text(fr.description)
                .font(.body)
                .foregroundStyle(.secondary)

            Divider().opacity(0.35)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Submitted by")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(fr.created_by_username ?? shortUser(fr.created_by))
                        .font(.subheadline.weight(.semibold))
                }

                HStack {
                    Text("Created")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(relativeDate(fr.created_at))
                        .font(.subheadline.weight(.semibold))
                }
            }
            .font(.subheadline)
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(.white.opacity(0.22), lineWidth: 0.8)
        )
        .padding(.horizontal, 16)
    }

    private var commentsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Comments")
                    .font(.headline)
                Spacer()
                if loading { ProgressView().controlSize(.small) }
            }

            if let error {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            if !loading && comments.isEmpty {
                Text("No comments yet.")
                    .foregroundStyle(.secondary)
                    .font(.footnote)
            } else {
                VStack(spacing: 10) {
                    ForEach(comments) { c in
                        commentRow(c)
                    }
                }
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(.white.opacity(0.22), lineWidth: 0.8)
        )
        .padding(.horizontal, 16)
    }

    private func commentRow(_ c: FeatureRequestCommentRow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(c.user_username ?? shortUser(c.user_id))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Text(relativeDate(c.created_at))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(c.body)
                .font(.subheadline)
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(.white.opacity(0.14), lineWidth: 0.8)
        )
    }

    private var composerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Add a comment")
                .font(.headline)

            ZStack(alignment: .topLeading) {
                if newComment.isEmpty {
                    Text("Write a comment…")
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                }

                TextEditor(text: $newComment)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 110, maxHeight: 160)
                    .padding(8)
                    .background(Color.clear)
                    .onChange(of: newComment) { _, newValue in
                        if newValue.count > 500 {
                            newComment = String(newValue.prefix(500))
                        }
                    }
            }
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(.white.opacity(0.14), lineWidth: 0.8)
            )

            HStack {
                Spacer()
                Text("\(newComment.count)/500")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button {
                Task { await sendComment() }
            } label: {
                HStack {
                    if isSending { ProgressView().tint(.white) }
                    Text(isSending ? "Sending…" : "Post comment")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .background(canSend ? Color.blue : Color.gray.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))
            .foregroundStyle(.white)
            .disabled(!canSend || isSending)
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(.white.opacity(0.22), lineWidth: 0.8)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    private var canSend: Bool {
        app.userId != nil &&
        !newComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        newComment.count <= 500
    }

    @MainActor
    private func loadComments() async {
        loading = true
        error = nil
        defer { loading = false }

        do {
            let rows = try await FeatureRequestsAPI.fetchComments(requestId: fr.id)
            comments = rows
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func sendComment() async {
        guard let uid = app.userId else { return }
        guard !isSending else { return }

        let body = newComment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }

        await MainActor.run { isSending = true }
        defer { Task { @MainActor in isSending = false } }

        do {
            try await FeatureRequestsAPI.addComment(requestId: fr.id, userId: uid, body: body)
            await MainActor.run { newComment = "" }
            await loadComments()
        } catch {
            await MainActor.run { self.error = error.localizedDescription }
        }
    }

    private func shortUser(_ id: UUID) -> String {
        let s = id.uuidString
        return String(s.prefix(8))
    }

    private func relativeDate(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: date, relativeTo: Date())
    }

    @ViewBuilder
    private func statusPill(_ status: String) -> some View {
        Text(status.replacingOccurrences(of: "_", with: " ").capitalized)
            .font(.caption2.weight(.semibold))
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(Capsule().fill(Color.white.opacity(0.12)))
            .overlay(Capsule().stroke(Color.white.opacity(0.12)))
            .foregroundStyle(.secondary)
    }
}
