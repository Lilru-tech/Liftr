import Foundation

struct Conversation: Decodable, Identifiable, Hashable {
    let id: Int64
    let kind: String
    let title: String?
    let updated_at: Date
}

struct MessageLite: Decodable, Identifiable, Hashable {
    let id: Int64
    let conversation_id: Int64
    let user_id: UUID
    let kind: String
    let body: String?
    let created_at: Date
    let edited_at: Date?
    let deleted_at: Date?
}
