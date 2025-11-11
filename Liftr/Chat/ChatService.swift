import Foundation
import Supabase
import Realtime
import UIKit

final class ChatService {
    static let shared = ChatService()
    private init() {}
    
    private let client = SupabaseManager.shared.client
    private var channels: [Int64: RealtimeChannelV2] = [:]
    private var rtHandlers: [Int64: [Any]] = [:]   // <- retenemos handlers para que no los libere ARC
    private struct StartDirectParams: Encodable { let p_other: UUID }
    private struct SendMessageParams: Encodable {
        let p_conversation_id: Int64
        let p_kind: String
        let p_body: String?
        let p_client_msg_id: UUID
    }
    private struct MarkReadParams: Encodable {
        let p_conversation_id: Int64
        let p_last_read_message_id: Int64
    }
    
    func startDirectConversation(with other: UUID) async throws -> Int64 {
        let resp = try await client
            .rpc("start_direct_conversation", params: StartDirectParams(p_other: other))
            .execute()
        return try JSONDecoder().decode(Int64.self, from: resp.data)
    }
    
    @discardableResult
    func sendText(conversationId: Int64, text: String) async throws -> Int64 {
        print("[RT] sendText rpc start conv=\(conversationId) len=\(text.count)")
        let resp = try await client
            .rpc("send_message",
                 params: SendMessageParams(
                    p_conversation_id: conversationId,
                    p_kind: "text",
                    p_body: text,
                    p_client_msg_id: UUID()
                 ))
            .execute()
        let id = try JSONDecoder().decode(Int64.self, from: resp.data)
        print("[RT] sendText ok conv=\(conversationId) id=\(id)")
        return id
    }
    
    func markRead(conversationId: Int64, lastMessageId: Int64?) async {
        guard let lastId = lastMessageId else { return }
        do {
            _ = try await client
                .rpc("mark_conversation_read",
                     params: MarkReadParams(
                        p_conversation_id: conversationId,
                        p_last_read_message_id: lastId
                     ))
                .execute()
        } catch {
            print("markRead error:", error)
        }
    }
    
    func loadConversations(for userId: UUID, limit: Int = 50, offset: Int = 0) async throws -> [Conversation] {
        let resp = try await client
            .from("conversations")
            .select("id,kind,title,updated_at,conversation_participants!inner(user_id)")
            .eq("conversation_participants.user_id", value: userId.uuidString)
            .order("updated_at", ascending: false)
            .range(from: offset, to: offset + limit - 1)
            .execute()
        
        return try JSONDecoder.supabase().decode([Conversation].self, from: resp.data)
    }
    
    func loadMessages(conversationId: Int64, pageSize: Int = 30, beforeId: Int64? = nil) async throws -> [MessageLite] {
        var qb = client
            .from("messages")
            .select("id,conversation_id,user_id,kind,body,created_at,edited_at,deleted_at")
            .eq("conversation_id", value: Int(conversationId))
        
        if let beforeId {
            if #available(iOS 9999, *) {
                qb = qb.lt("id", value: Int(beforeId))
            } else {
                qb = qb.filter("id", operator: "lt", value: String(beforeId))
            }
        }
        
        let resp = try await qb
            .order("id", ascending: false)
            .range(from: 0, to: pageSize - 1)
            .execute()
        
        let items = try JSONDecoder.supabase().decode([MessageLite].self, from: resp.data)
        let sorted = items.sorted { $0.id < $1.id }
        print("[RT] loadMessages conv=\(conversationId) count=\(items.count) oldest=\(sorted.first?.id ?? -1) newest=\(sorted.last?.id ?? -1)")
        return items
    }
    
    struct MessageChange {
        enum Kind { case insert(MessageLite), update(MessageLite), delete(Int64) }
        let kind: Kind
    }
    
    func subscribeToMessages(
        conversationId: Int64,
        onChange: @escaping (MessageChange) -> Void
    ) async -> Bool {
        if channels[conversationId] != nil {
            print("[RT] subscribe skipped (already has channel) conv=\(conversationId)")
            return true
        }
        print("[RT] subscribe start conv=\(conversationId)")
        // Asegura orden: setAuth -> connect
        await SupabaseManager.shared.primeRealtimeAuth()
        // *pequeño margen* para evitar carrera al registrar handlers justo después de conectar
        try? await Task.sleep(nanoseconds: 100_000_000) // 100 ms

        let ch = client.realtimeV2.channel("public:messages")
        let filter = "conversation_id=eq.\(conversationId)"
        print("[RT] channel=public:messages serverFilter=\(filter)")

        let hInsert = ch.onPostgresChange(
            InsertAction.self,
            schema: "public",
            table: "messages",
            filter: filter
        ) { payload in
            print("[RT] INSERT handler (filtered) raw=\(payload.record)")
            if let msg = Self.decodeMessageLite(from: payload.record) {
                print("[RT] INSERT parsed id=\(msg.id) conv=\(msg.conversation_id)")
                onChange(.init(kind: .insert(msg)))
            } else {
                print("[RT][WARN] INSERT decode failed (filtered) record=\(payload.record)")
            }
        }
        rtHandlers[conversationId, default: []].append(hInsert)

        let hUpdate = ch.onPostgresChange(
            UpdateAction.self,
            schema: "public",
            table: "messages",
            filter: filter
        ) { payload in
            print("[RT] UPDATE handler (filtered) raw=\(payload.record)")
            if let msg = Self.decodeMessageLite(from: payload.record) {
                onChange(.init(kind: .update(msg)))
            } else {
                print("[RT][WARN] UPDATE decode failed (filtered) record=\(payload.record)")
            }
        }
        rtHandlers[conversationId, default: []].append(hUpdate)

        let hDelete = ch.onPostgresChange(
            DeleteAction.self,
            schema: "public",
            table: "messages",
            filter: filter
        ) { payload in
            print("[RT] DELETE handler (filtered) old=\(payload.oldRecord)")
            struct IdOnly: Decodable { let id: Int64 }
            if let data = try? JSONEncoder().encode(payload.oldRecord),
               let obj  = try? JSONDecoder().decode(IdOnly.self, from: data) {
                onChange(.init(kind: .delete(obj.id)))
            } else {
                print("[RT][WARN] DELETE decode failed (filtered) old=\(payload.oldRecord)")
            }
        }
        rtHandlers[conversationId, default: []].append(hDelete)

        // === DEBUG: SIN FILTRO (debe imprimir SIEMPRE que haya inserts en public.messages) ===
        #if DEBUG
        let hDbgIns = ch.onPostgresChange(
            InsertAction.self,
            schema: "public",
            table: "messages",
            filter: nil
        ) { e in
            print("[RT][DBG] RAW INSERT (unfiltered) rec=\(e.record)")
        }
        rtHandlers[conversationId, default: []].append(hDbgIns)
        let hDbgUpd = ch.onPostgresChange(
            UpdateAction.self,
            schema: "public",
            table: "messages",
            filter: nil
        ) { e in
            print("[RT][DBG] RAW UPDATE (unfiltered) rec=\(e.record)")
        }
        rtHandlers[conversationId, default: []].append(hDbgUpd)
        let hDbgDel = ch.onPostgresChange(
            DeleteAction.self,
            schema: "public",
            table: "messages",
            filter: nil
        ) { e in
            print("[RT][DBG] RAW DELETE (unfiltered) old=\(e.oldRecord)")
        }
        rtHandlers[conversationId, default: []].append(hDbgDel)
        #endif

        let hReads = ch.onPostgresChange(
            UpdateAction.self,
            schema: "public",
            table: "conversation_reads",
            filter: "conversation_id=eq.\(conversationId)"
        ) { e in
            print("[RT][TAP] conversation_reads UPDATE conv=\(conversationId) row=\(e.record)")
        }
        rtHandlers[conversationId, default: []].append(hReads)

        do {
            try await ch.subscribeWithError()
            channels[conversationId] = ch
            print("[RT] subscribed OK conv=\(conversationId)")
            return true
        } catch {
            print("[RT] subscribe ERROR conv=\(conversationId): \(error)")
            return false
        }
    }
    
    func unsubscribe(conversationId: Int64) async {
        if let ch = channels.removeValue(forKey: conversationId) {
            print("[RT] unsubscribe conv=\(conversationId)")
            // Limpia handlers retenidos para esta conversación
            rtHandlers[conversationId] = nil
            await ch.unsubscribe()
        }
    }
    
    @discardableResult
    func sendImage(conversationId: Int64, image: UIImage, jpegQuality: CGFloat = 0.85) async throws -> Int64 {
        guard let data = image.jpegData(compressionQuality: jpegQuality) else {
            throw NSError(domain: "image", code: -1, userInfo: [NSLocalizedDescriptionKey: "JPEG encode failed"])
        }
        
        let msgId = try await sendMessageShell(conversationId: conversationId, kind: "image")
        let objectPath = "\(conversationId)/\(msgId)/image.jpg"
        
        try await client.storage
            .from("chat-attachments")
            .upload(objectPath, data: data, options: FileOptions(contentType: "image/jpeg", upsert: false))
        
        var meta: [String: AnyJSON] = [:]
        meta["storage_key"] = try AnyJSON(objectPath)
        meta["mime"] = AnyJSON("image/jpeg")
        meta["width"]       = try AnyJSON(Int(image.size.width))
        meta["height"]      = try AnyJSON(Int(image.size.height))
        meta["size_bytes"]  = try AnyJSON(data.count)
        
        struct MsgUpdate: Encodable { let metadata: [String: AnyJSON] }
        _ = try await client
            .from("messages")
            .update(MsgUpdate(metadata: meta))
            .eq("id", value: Int(msgId))
            .execute()
        
        return msgId
    }
    
    private func sendMessageShell(conversationId: Int64, kind: String) async throws -> Int64 {
        let resp = try await client
            .rpc("send_message",
                 params: SendMessageParams(
                    p_conversation_id: conversationId,
                    p_kind: kind,
                    p_body: nil,
                    p_client_msg_id: UUID()
                 ))
            .execute()
        let id = try JSONDecoder().decode(Int64.self, from: resp.data)
        print("[RT] sendText ok conv=\(conversationId) id=\(id)")
        return id
    }
    
    private static func decodeMessageLite(from rec: [String: AnyJSON]) -> MessageLite? {
        do {
            let data = try JSONEncoder().encode(rec) // AnyJSON -> Data
            return try JSONDecoder.supabase().decode(MessageLite.self, from: data)
        } catch {
            print("decodeMessageLite v2 error:", error)
            return nil
        }
    }
    
    // Extrae conversation_id de un record AnyJSON -> Int64
    private static func convId(from rec: [String: AnyJSON]) -> Int64? {
        struct OnlyCid: Decodable { let conversation_id: Int64 }
        guard let data = try? JSONEncoder().encode(rec),
              let obj  = try? JSONDecoder().decode(OnlyCid.self, from: data) else { return nil }
        return obj.conversation_id
    }
}
