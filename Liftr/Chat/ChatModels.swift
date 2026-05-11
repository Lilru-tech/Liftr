import Foundation
import Supabase

enum ChatKind: String, Decodable {
    case direct
    case group
}

enum ChatMessageKind: String, Codable {
    case text
    case image
    case file
    case system
    case workoutShare      = "workout_share"
    case routineShare      = "routine_share"
    case achievementShare  = "achievement_share"
    case segmentShare      = "segment_share"
}

struct ConversationOverview: Decodable, Identifiable, Hashable {
    let id: Int64
    let kind: String
    let title: String?
    let updated_at: Date
    let last_message_id: Int64?
    let last_message_user_id: UUID?
    let last_message_body: String?
    let last_message_at: Date?
    let unread_count: Int

    var conversationKind: ChatKind { ChatKind(rawValue: kind) ?? .direct }
}

struct ChatMessage: Decodable, Identifiable, Hashable {
    let id: Int64
    let user_id: UUID
    let kind: String
    let body: String?
    let metadata: AnyJSON?
    let reply_to_message_id: Int64?
    let created_at: Date
    let edited_at: Date?
    let deleted_at: Date?

    var messageKind: ChatMessageKind { ChatMessageKind(rawValue: kind) ?? .text }

    init(id: Int64,
         user_id: UUID,
         kind: String,
         body: String?,
         metadata: AnyJSON?,
         reply_to_message_id: Int64? = nil,
         created_at: Date,
         edited_at: Date? = nil,
         deleted_at: Date? = nil) {
        self.id = id
        self.user_id = user_id
        self.kind = kind
        self.body = body
        self.metadata = metadata
        self.reply_to_message_id = reply_to_message_id
        self.created_at = created_at
        self.edited_at = edited_at
        self.deleted_at = deleted_at
    }

    private enum CodingKeys: String, CodingKey {
        case id, user_id, kind, body, metadata, reply_to_message_id
        case created_at, edited_at, deleted_at
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(Int64.self, forKey: .id)
        self.user_id = try c.decode(UUID.self, forKey: .user_id)
        self.kind = try c.decode(String.self, forKey: .kind)
        self.body = try c.decodeIfPresent(String.self, forKey: .body)
        self.metadata = try c.decodeIfPresent(AnyJSON.self, forKey: .metadata)
        self.reply_to_message_id = try c.decodeIfPresent(Int64.self, forKey: .reply_to_message_id)
        self.created_at = try c.decode(Date.self, forKey: .created_at)
        self.edited_at = try c.decodeIfPresent(Date.self, forKey: .edited_at)
        self.deleted_at = try c.decodeIfPresent(Date.self, forKey: .deleted_at)
    }
}

enum ReactionEmoji: String, CaseIterable, Codable, Hashable {
    case heart      = "heart"
    case haha       = "haha"
    case wow        = "wow"
    case sad        = "sad"
    case thumbsUp   = "thumbs_up"
    case thumbsDown = "thumbs_down"

    var glyph: String {
        switch self {
        case .heart:      return "❤️"
        case .haha:       return "😂"
        case .wow:        return "😮"
        case .sad:        return "😢"
        case .thumbsUp:   return "👍"
        case .thumbsDown: return "👎"
        }
    }
}

struct MessageReaction: Decodable, Hashable {
    let message_id: Int64
    let user_id: UUID
    let emoji: String
    let created_at: Date

    var reaction: ReactionEmoji? { ReactionEmoji(rawValue: emoji) }
}

struct ChatProfile: Decodable, Identifiable, Hashable {
    let user_id: UUID
    let username: String
    let avatar_url: String?
    var id: UUID { user_id }
}

struct WorkoutShareSnapshot: Codable, Hashable {
    let v: Int
    let workout_id: Int64
    let title: String?
    let kind: String?
    let score: Int?
    let kcal: Int?
    let performed_at: String?
    let owner_user_id: UUID?
    let owner_username: String?
    let owner_avatar_url: String?
}

struct RoutineShareSnapshot: Codable, Hashable {
    let v: Int
    let type: String
    let routine_kind: String
    let name: String
    let routine_id: Int64?
    let updated_at: String?
    let owner_user_id: UUID?
    let owner_username: String?
    let owner_avatar_url: String?
    let share_nonce: String
    let detail_json: String
    let exercise_count: Int?
    let total_sets: Int?
    let preview_exercise_name: String?

    init(v: Int,
         type: String,
         routine_kind: String,
         name: String,
         routine_id: Int64?,
         updated_at: String?,
         owner_user_id: UUID?,
         owner_username: String?,
         owner_avatar_url: String?,
         share_nonce: String,
         detail_json: String,
         exercise_count: Int? = nil,
         total_sets: Int? = nil,
         preview_exercise_name: String? = nil) {
        self.v = v
        self.type = type
        self.routine_kind = routine_kind
        self.name = name
        self.routine_id = routine_id
        self.updated_at = updated_at
        self.owner_user_id = owner_user_id
        self.owner_username = owner_username
        self.owner_avatar_url = owner_avatar_url
        self.share_nonce = share_nonce
        self.detail_json = detail_json
        self.exercise_count = exercise_count
        self.total_sets = total_sets
        self.preview_exercise_name = preview_exercise_name
    }
}

struct AchievementShareSnapshot: Codable, Hashable {
    let v: Int
    let type: String
    let code: String
    let achievement_id: Int
    let title: String
    let category: String
    let description: String?
    let icon_url: String?
    let owner_user_id: UUID?
    let owner_username: String?
    let owner_avatar_url: String?
}

struct SegmentShareSnapshot: Codable, Hashable {
    let v: Int
    let type: String
    let segment_id: String
    let name: String
    let segment_length_m: Double?
    let leaderboard_effort_count: Int64?
    let owner_user_id: UUID?
    let owner_username: String?
    let owner_avatar_url: String?
}

extension ChatMessage {
    func workoutShare() -> WorkoutShareSnapshot? {
        guard messageKind == .workoutShare, let metadata else { return nil }
        return try? metadata.decode(as: WorkoutShareSnapshot.self)
    }

    func routineShare() -> RoutineShareSnapshot? {
        guard messageKind == .routineShare, let metadata else { return nil }
        return try? metadata.decode(as: RoutineShareSnapshot.self)
    }

    func achievementShare() -> AchievementShareSnapshot? {
        guard messageKind == .achievementShare, let metadata else { return nil }
        return try? metadata.decode(as: AchievementShareSnapshot.self)
    }

    func segmentShare() -> SegmentShareSnapshot? {
        guard messageKind == .segmentShare, let metadata else { return nil }
        return try? metadata.decode(as: SegmentShareSnapshot.self)
    }
}
