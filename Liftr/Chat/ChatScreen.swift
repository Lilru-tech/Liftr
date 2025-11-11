import SwiftUI
import PhotosUI

struct ChatScreen: View {
    let conversationId: Int64
    let myUserId: UUID

    @StateObject private var vm: ChatViewModel
    @State private var input: String = ""
    @State private var picking = false
    @State private var imageItem: PhotosPickerItem?
    @State private var banner: Banner?

    init(conversationId: Int64, myUserId: UUID) {
        self.conversationId = conversationId
        self.myUserId = myUserId
        _vm = StateObject(wrappedValue: ChatViewModel(conversationId: conversationId, myUserId: myUserId))
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                List {
                    if vm.hasOlder {
                        Button("Load older…") {
                            Task { await vm.loadMore() }
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .listRowBackground(Color.clear)
                    }
                    ForEach(vm.messages) { msg in
                        bubble(for: msg)
                            .listRowSeparator(.hidden)
                            .id(msg.id)
                    }
                }
                .listStyle(.plain)
                .onChange(of: vm.messages.count) { _, _ in
                    if let last = vm.messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            HStack(spacing: 8) {
                PhotosPicker(selection: $imageItem, matching: .images) {
                    Image(systemName: "paperclip")
                        .font(.title3)
                }
                .onChange(of: imageItem) { _, newItem in
                    Task {
                        guard let newItem,
                              let data = try? await newItem.loadTransferable(type: Data.self),
                              let img = UIImage(data: data) else { return }
                        await vm.send(image: img)
                    }
                }

                TextField("Message", text: $input, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                Button {
                    let text = input
                    Task {
                        await MainActor.run { self.input = "" }
                        await vm.send(text: text)
                    }
                } label: {
                    Image(systemName: "paperplane.fill").font(.title3)
                }
                .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.all, 12)
            .background(.ultraThinMaterial)
        }
        .navigationTitle("Chat")
        .navigationBarTitleDisplayMode(.inline)
        .banner($banner)
        .task { await vm.loadFirstPage() }
        .onAppear { print("[UI] ChatScreen appear conv=\(conversationId)") }
        .onDisappear {
            print("[UI] ChatScreen disappear conv=\(conversationId)")
            Task { await ChatService.shared.unsubscribe(conversationId: conversationId) }
        }
    }

    @ViewBuilder
    private func bubble(for m: MessageLite) -> some View {
        let isMe = (m.user_id == myUserId)
        HStack {
            if isMe { Spacer() }
            VStack(alignment: .leading, spacing: 4) {
                if m.kind == "text" {
                    Text(m.body ?? " ").textSelection(.enabled)
                } else if m.kind == "image" {
                    Text("📷 Image").italic()
                } else if m.kind == "file" {
                    Text("📎 Attachment").italic()
                } else {
                    Text(m.body ?? "·").italic().foregroundStyle(.secondary)
                }
                Text(Self.timeOnly(m.created_at))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: isMe ? .trailing : .leading)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isMe ? Color.blue.opacity(0.18) : Color.gray.opacity(0.18))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            if !isMe { Spacer() }
        }
        .listRowBackground(Color.clear)
    }

    private static func timeOnly(_ d: Date) -> String {
        let f = DateFormatter(); f.timeStyle = .short; f.dateStyle = .none
        return f.string(from: d)
    }
}
