import Foundation
import SwiftUI

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [MessageLite] = []
    @Published var hasOlder = false
    @Published var loading = false
    @Published var error: String?

    let conversationId: Int64
    let myUserId: UUID

    private var oldestId: Int64? = nil
    private var subscribed = false

    init(conversationId: Int64, myUserId: UUID) {
        self.conversationId = conversationId
        self.myUserId = myUserId
    }
    
    // Inserta o actualiza un mensaje y mantiene el orden por id
    private func upsert(_ m: MessageLite) {
        if let i = messages.firstIndex(where: { $0.id == m.id }) {
            if messages[i] != m { messages[i] = m }
        } else {
            messages.append(m)
        }
        messages.sort { $0.id < $1.id }
    }

    // Elimina por id
    private func remove(id: Int64) {
        messages.removeAll { $0.id == id }
    }

    func loadFirstPage() async {
        guard !loading else { return }
        loading = true; defer { loading = false }
        print("[VM] loadFirstPage conv=\(conversationId)")
        let ok = await subscribeIfNeeded()
        print("[VM] subscribeIfNeeded done ok=\(ok)")
        // Depuración: si en 2s no ha saltado ningún handler, lo indicamos
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            // Busca si desde que nos suscribimos ha llegado algo nuevo
            let hasRecent = !self.messages.isEmpty
            print("[VM] post-subscribe check conv=\(self.conversationId) receivedAny=\(hasRecent)")
        }
        do {
            let page = try await ChatService.shared.loadMessages(conversationId: conversationId, pageSize: 30, beforeId: nil)
            self.messages = page.sorted { $0.id < $1.id }
            self.oldestId = page.first?.id
            self.hasOlder = (page.count == 30)
            print("[VM] firstPage conv=\(conversationId) loaded=\(page.count) oldest=\(self.messages.first?.id ?? -1) newest=\(self.messages.last?.id ?? -1)")
            if let last = messages.last, last.user_id != myUserId {
                await ChatService.shared.markRead(conversationId: conversationId, lastMessageId: last.id)
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func loadMore() async {
        guard !loading else { return }
        guard let before = messages.first?.id else { return }
        loading = true; defer { loading = false }
        do {
            let page = try await ChatService.shared.loadMessages(conversationId: conversationId, pageSize: 30, beforeId: before)
            let older = page.sorted { $0.id < $1.id }
            let existing = Set(messages.map(\.id))
            let deduped = older.filter { !existing.contains($0.id) }
            messages.insert(contentsOf: deduped, at: 0)
            hasOlder = (page.count == 30)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func send(text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        print("[VM] send text len=\(trimmed.count)")
        do {
            // 1) Enviamos y obtenemos el id real insertado por el RPC
            let newId = try await ChatService.shared.sendText(conversationId: conversationId, text: trimmed)

            // 2) Insertamos optimistamente en la lista
            await MainActor.run {
                let optimistic = MessageLite(
                    id: newId,
                    conversation_id: conversationId,
                    user_id: myUserId,
                    kind: "text",
                    body: trimmed,
                    created_at: Date(),
                    edited_at: nil,
                    deleted_at: nil
                )
                self.messages.append(optimistic)
                self.messages.sort { $0.id < $1.id }
            }
            print("[VM] optimistic append id=\(newId) total=\(self.messages.count)")
            // Fallback: si en 1s no llegó el evento, refetch del último mensaje
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if !self.messages.contains(where: { $0.id == newId }) {
                    if let last = try? await ChatService.shared
                        .loadMessages(conversationId: self.conversationId, pageSize: 1, beforeId: nil)
                        .last {
                        self.upsert(last)
                        print("[VM] fallback fetch appended id=\(last.id)")
                    }
                }
            }
        } catch {
            await MainActor.run { self.error = error.localizedDescription }
        }
    }

    func send(image: UIImage) async {
        do {
            let _ = try await ChatService.shared.sendImage(conversationId: conversationId, image: image)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func subscribeIfNeeded() async -> Bool {
        guard !subscribed else { print("[VM] subscribeIfNeeded skipped conv=\(conversationId)"); return true }
        subscribed = true
        print("[VM] subscribeIfNeeded start conv=\(conversationId)")

        let ok = await ChatService.shared.subscribeToMessages(
            conversationId: conversationId
        ) { [weak self] change in
            Task { @MainActor in
                guard let self = self else { return }
                switch change.kind {
                case .insert(let m):
                    print("[VM] change INSERT id=\(m.id)")
                    self.upsert(m)
                    if m.user_id != self.myUserId {
                        await ChatService.shared.markRead(conversationId: self.conversationId, lastMessageId: m.id)
                    }
                case .update(let m):
                    print("[VM] change UPDATE id=\(m.id)")
                    self.upsert(m)
                case .delete(let id):
                    print("[VM] change DELETE id=\(id)")
                    self.remove(id: id)
                }
            }
        }

        print("[VM] subscribeIfNeeded done ok=\(ok)")
        return ok
    }
}
