import SwiftUI

struct ConversationsListView: View {
    @EnvironmentObject var app: AppState
    @State private var convs: [Conversation] = []
    @State private var loading = false
    @State private var error: String?
    @State private var banner: Banner?

    // Nuevo: sheet + navegación programática
    @State private var showNewConversation = false
    private struct Dest: Identifiable, Hashable { let id: Int64 }
    @State private var dest: Dest? = nil

    var body: some View {
        List {
            ForEach(convs) { c in
                NavigationLink {
                    if let me = app.userId {
                        ChatScreen(conversationId: c.id, myUserId: me)
                            .gradientBG()
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: c.kind == "direct" ? "person.circle" : "person.3")
                            .imageScale(.large)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(c.title ?? "Direct")
                                .font(.body.weight(.semibold))
                            Text(Self.relative(c.updated_at))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .listRowBackground(Color.clear)   // <- fondo transparente por fila
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)        // <- quita el fondo blanco de la List
        .banner($banner)
        .task { await load() }
        .refreshable { await load() }
        .navigationTitle("Messages")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showNewConversation = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("New conversation")
            }
        }
        .sheet(isPresented: $showNewConversation) {
            NewConversationSheet { convId in
                // refresca y navega al chat recién creado
                Task {
                    await load()
                    if app.userId != nil {
                        dest = Dest(id: convId)
                        print("[UI] open new ChatScreen conv=\(convId)")
                    }
                }
            }
            .environmentObject(app)
        }
        .navigationDestination(item: $dest) { d in
            if let me = app.userId {
                ChatScreen(conversationId: d.id, myUserId: me)
                    .gradientBG()
            }
        }
    }

    private func load() async {
        guard let me = app.userId else { return }
        loading = true; defer { loading = false }
        do {
            convs = try await ChatService.shared.loadConversations(for: me)
        } catch {
            self.error = error.localizedDescription
            BannerAction.showError(error.localizedDescription, banner: $banner)
        }
    }

    private static func relative(_ d: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: d, relativeTo: Date())
    }
}
