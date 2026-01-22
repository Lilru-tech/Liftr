import Foundation
import Supabase

enum FeatureRequestsAPI {
    
    static func fetchRequests() async throws -> [FeatureRequestRow] {
        let res = try await SupabaseManager.shared.client
            .from("vw_feature_requests")
            .select("*")
            .order("created_at", ascending: false)
            .execute()
        
        return try JSONDecoder.supabase().decode([FeatureRequestRow].self, from: res.data)
    }
    
    static func fetchMyVote(requestId: Int64, userId: UUID) async throws -> Bool {
        let res = try await SupabaseManager.shared.client
            .from("feature_request_votes")
            .select("feature_request_id")
            .eq("feature_request_id", value: Int(requestId))
            .eq("user_id", value: userId.uuidString)
            .limit(1)
            .execute()
        
        struct Row: Decodable { let feature_request_id: Int64 }
        let rows = try JSONDecoder.supabase().decode([Row].self, from: res.data)
        return !rows.isEmpty
    }
    
    static func vote(requestId: Int64, userId: UUID) async throws {
        let payload: [String: AnyEncodable] = [
            "feature_request_id": AnyEncodable(requestId),
            "user_id": AnyEncodable(userId.uuidString)
        ]
        
        _ = try await SupabaseManager.shared.client
            .from("feature_request_votes")
            .upsert(payload, onConflict: "feature_request_id,user_id")
            .execute()
    }
    
    static func unvote(requestId: Int64, userId: UUID) async throws {
        _ = try await SupabaseManager.shared.client
            .from("feature_request_votes")
            .delete()
            .eq("feature_request_id", value: Int(requestId))
            .eq("user_id", value: userId.uuidString)
            .execute()
    }
    
    static func createRequest(title: String, description: String, email: String?, createdBy: UUID) async throws {
        struct Payload: Encodable {
            let title: String
            let description: String
            let email: String?
            let created_by: UUID
        }

        let payload = Payload(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            description: description.trimmingCharacters(in: .whitespacesAndNewlines),
            email: email,
            created_by: createdBy
        )

        _ = try await SupabaseManager.shared.client
            .from("feature_requests")
            .insert(payload)
            .execute()
    }
    
    static func fetchComments(requestId: Int64) async throws -> [FeatureRequestCommentRow] {
        let res = try await SupabaseManager.shared.client
            .from("vw_feature_request_comments")
            .select("*")
            .eq("feature_request_id", value: Int(requestId))
            .order("created_at", ascending: true)
            .execute()

        return try JSONDecoder.supabase().decode([FeatureRequestCommentRow].self, from: res.data)
    }

    static func addComment(requestId: Int64, userId: UUID, body: String) async throws {
        struct Payload: Encodable {
            let feature_request_id: Int64
            let user_id: UUID
            let body: String
        }

        let payload = Payload(
            feature_request_id: requestId,
            user_id: userId,
            body: body.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        _ = try await SupabaseManager.shared.client
            .from("feature_request_comments")
            .insert(payload)
            .execute()
    }
}

struct AnyEncodable: Encodable {
    private let _encode: (Encoder) throws -> Void
    init<T: Encodable>(_ value: T) {
        _encode = value.encode
    }
    func encode(to encoder: Encoder) throws { try _encode(encoder) }
}
