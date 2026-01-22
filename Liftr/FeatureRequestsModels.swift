import Foundation

struct FeatureRequestRow: Decodable, Identifiable {
    let id: Int64
    let created_by: UUID
    let created_by_username: String?
    let title: String
    let description: String
    let status: String
    let created_at: Date
    let updated_at: Date
    let votes_count: Int?
    let comments_count: Int?
}

struct FeatureRequestInsert: Encodable {
    let title: String
    let description: String
    let email: String?
    let created_by: UUID
}

struct FeatureRequestCommentRow: Decodable, Identifiable {
    let id: Int64
    let feature_request_id: Int64
    let user_id: UUID
    let user_username: String?
    let body: String
    let created_at: Date
    let updated_at: Date
}

struct FeatureRequestVoteRow: Decodable {
    let feature_request_id: Int64
    let user_id: UUID
    let created_at: Date
}
