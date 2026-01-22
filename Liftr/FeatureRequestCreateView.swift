import SwiftUI

struct FeatureRequestCreateView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    let onCreated: () -> Void

    @State private var title: String = ""
    @State private var description: String = ""
    @State private var userEmail: String = ""

    @State private var isSaving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                VStack(spacing: 14) {

                    if let error {
                        Text(error)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Title")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(title.count)/50")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        TextField("Short title", text: $title)
                            .textInputAutocapitalization(.sentences)
                            .autocorrectionDisabled()
                            .padding(12)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(.white.opacity(0.22), lineWidth: 0.8)
                            )
                            .onChange(of: title) { _, newValue in
                                if newValue.count > 50 { title = String(newValue.prefix(50)) }
                            }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Description")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(description.count)/500")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        ZStack(alignment: .topLeading) {
                            if description.isEmpty {
                                Text("Describe the feature request in as much detail as possible…")
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 12)
                            }

                            TextEditor(text: $description)
                                .scrollContentBackground(.hidden)
                                .frame(minHeight: 180, maxHeight: 260)
                                .padding(8)
                                .background(Color.clear)
                                .onChange(of: description) { _, newValue in
                                    if newValue.count > 500 { description = String(newValue.prefix(500)) }
                                }
                        }
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(.white.opacity(0.22), lineWidth: 0.8)
                        )
                    }

                    VStack(spacing: 10) {
                        LabeledContent {
                            Text(userEmail.isEmpty ? "—" : userEmail)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        } label: {
                            Text("Your email")
                                .foregroundStyle(.secondary)
                        }
                        .labelStyle(.titleOnly)

                        Text("We’ll use your account email to contact you if we need more details.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button {
                        Task { await save() }
                    } label: {
                        HStack {
                            if isSaving { ProgressView().controlSize(.small) }
                            Text(isSaving ? "Saving…" : "Save")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .background(
                        (!isSaving && canSave) ? Color.blue : Color.gray.opacity(0.5),
                        in: RoundedRectangle(cornerRadius: 14)
                    )
                    .foregroundStyle(.white)
                    .disabled(isSaving || !canSave)

                }
                .padding(20)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(.white.opacity(0.22), lineWidth: 0.8)
                )
                .shadow(color: .black.opacity(0.12), radius: 10, y: 6)
                .padding(.horizontal, 24)

                Spacer(minLength: 0)
            }
            .padding(.top, 16)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
            .task { await loadUserEmail() }
        }
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !userEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func loadUserEmail() async {
        let client = SupabaseManager.shared.client
        if let session = try? await client.auth.session {
            await MainActor.run {
                self.userEmail = session.user.email ?? ""
            }
        }
    }

    private func save() async {
        guard let uid = app.userId else {
            await MainActor.run { error = "You must be logged in." }
            return
        }

        let emailToSend = userEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !emailToSend.isEmpty else {
            await MainActor.run {
                error = "We couldn’t detect your account email. Please sign out and sign in again."
            }
            return
        }

        await MainActor.run { isSaving = true; error = nil }
        defer { Task { await MainActor.run { isSaving = false } } }

        do {
            try await FeatureRequestsAPI.createRequest(
                title: title,
                description: description,
                email: emailToSend,
                createdBy: uid
            )
            await MainActor.run { onCreated() }
        } catch {
            await MainActor.run { self.error = error.localizedDescription }
        }
    }
}
