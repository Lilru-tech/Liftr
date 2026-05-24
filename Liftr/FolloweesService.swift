import Foundation
import Supabase

enum FolloweesService {
    struct Profile: Decodable, Identifiable, Equatable {
        let user_id: UUID
        let username: String
        let avatar_url: String?
        var id: UUID { user_id }
    }

    static func loadFollowees(for userId: UUID) async throws -> [Profile] {
        let client = SupabaseManager.shared.client
        let edgeRes = try await client
            .from("follows")
            .select("followee_id")
            .eq("follower_id", value: userId.uuidString)
            .limit(1000)
            .execute()

        struct EdgeRow: Decodable { let followee_id: UUID }
        let edges = try JSONDecoder.supabase().decode([EdgeRow].self, from: edgeRes.data)
        let ids = edges.map(\.followee_id)
        guard !ids.isEmpty else { return [] }

        let pRes = try await client
            .from("profiles")
            .select("user_id, username, avatar_url")
            .in("user_id", values: ids.map { $0.uuidString })
            .order("username", ascending: true)
            .limit(1000)
            .execute()

        return try JSONDecoder.supabase().decode([Profile].self, from: pRes.data)
    }
}

struct MentionUser: Identifiable, Equatable {
    let userId: UUID
    let username: String
    var id: UUID { userId }

    init(profile: FolloweesService.Profile) {
        userId = profile.user_id
        username = profile.username
    }
}

enum MentionTextSupport {
    static func activeMentionQuery(in text: String, cursorUTF16Offset: Int) -> (range: Range<String.Index>, query: String)? {
        let ns = text as NSString
        let clamped = max(0, min(cursorUTF16Offset, ns.length))
        let cursorIdx = String.Index(utf16Offset: clamped, in: text)
        let prefix = String(text[..<cursorIdx])
        guard let atRange = prefix.range(of: "@", options: .backwards) else { return nil }
        let afterAt = prefix[atRange.upperBound...]
        if afterAt.contains(where: { $0.isWhitespace || $0.isNewline }) { return nil }
        let query = String(afterAt)
        let mentionRange = atRange.lowerBound..<cursorIdx
        return (mentionRange, query)
    }

    static func resolvedMentionIds(body: String, tracked: [MentionUser]) -> [UUID] {
        var seen = Set<UUID>()
        var result: [UUID] = []
        for m in tracked {
            let token = "@\(m.username)"
            guard body.contains(token), !seen.contains(m.userId) else { continue }
            seen.insert(m.userId)
            result.append(m.userId)
        }
        return result
    }

    static func mentionSegments(in body: String) -> [(String, Bool)] {
        var segments: [(String, Bool)] = []
        var idx = body.startIndex
        while idx < body.endIndex {
            if body[idx] == "@" {
                var scan = body.index(after: idx)
                while scan < body.endIndex, body[scan] == "@" {
                    scan = body.index(after: scan)
                }
                var end = scan
                while end < body.endIndex {
                    let ch = body[end]
                    if ch.isWhitespace || ch.isNewline { break }
                    if !ch.isLetter && !ch.isNumber && ch != "_" { break }
                    end = body.index(after: end)
                }
                if end > scan {
                    let token = "@" + String(body[scan..<end])
                    segments.append((token, true))
                    idx = end
                    continue
                }
            }
            var end = idx
            while end < body.endIndex, body[end] != "@" {
                end = body.index(after: end)
            }
            segments.append((String(body[idx..<end]), false))
            idx = end
        }
        if segments.isEmpty, !body.isEmpty {
            segments.append((body, false))
        }
        return segments
    }
}
