import SwiftUI

struct NewChatView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    let onPick: (ChatProfile) -> Void

    @State private var query: String = ""
    @State private var loading = false
    @State private var profiles: [ChatProfile] = []
    @State private var error: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                content
            }
            .navigationTitle("New chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task { await load() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if loading && profiles.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error {
            VStack(spacing: 12) {
                Text("Couldn't load contacts")
                    .font(.headline)
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Retry") { Task { await load() } }
                    .buttonStyle(.borderedProminent)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if profiles.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "person.2.slash")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(.secondary)
                Text("No mutual follows yet")
                    .font(.headline)
                Text("You can DM any user that follows you back.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                Section {
                    TextField("Search…", text: $query)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .listRowBackground(Color.clear)
                }
                Section {
                    ForEach(filtered) { p in
                        Button {
                            onPick(p)
                        } label: {
                            HStack(spacing: 12) {
                                AvatarView(urlString: p.avatar_url)
                                    .frame(width: 40, height: 40)
                                    .clipShape(Circle())
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("@\(p.username)")
                                        .font(.body.weight(.semibold))
                                }
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.clear)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
    }

    private var filtered: [ChatProfile] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return profiles }
        return profiles.filter { $0.username.localizedCaseInsensitiveContains(q) }
    }

    @MainActor
    private func load() async {
        guard let me = app.userId else { return }
        loading = true
        defer { loading = false }
        do {
            self.profiles = try await ChatService.fetchMutualFollowees(myUserId: me)
            self.error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}
