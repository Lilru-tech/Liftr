package com.lilru.liftr.data

import com.lilru.liftr.ui.chat.ChatMessageWire
import com.lilru.liftr.ui.chat.ChatParticipantRow
import com.lilru.liftr.ui.chat.ConversationOverviewWire
import com.lilru.liftr.ui.chat.ConversationReadRow
import com.lilru.liftr.ui.chat.FollowEdge
import com.lilru.liftr.ui.chat.ParticipantMutedRow
import com.lilru.liftr.ui.chat.ProfileLite
import com.lilru.liftr.ui.chat.ReactionWire
import com.lilru.liftr.ui.chat.AchievementShareSnapshot
import com.lilru.liftr.ui.chat.ReplyPreviewWire
import com.lilru.liftr.ui.chat.RoutineShareSnapshot
import com.lilru.liftr.ui.chat.SharedIngredientSnapshot
import com.lilru.liftr.ui.chat.SharedRecipeSnapshot
import com.lilru.liftr.ui.chat.SegmentShareSnapshot
import com.lilru.liftr.ui.chat.WorkoutShareSnapshot
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Order
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.encodeToJsonElement
import kotlinx.serialization.json.put
import java.util.UUID

/**
 * Thin wrapper around the chat RPCs and follow lookups. Mirrors
 * `Liftr/Chat/ChatService.swift`.
 *
 * The 5 RPCs were created in migration `20260509140000_chat_realtime_v1.sql`.
 */
class ChatRepository(private val supabase: SupabaseClient) {

    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = false }

    private val shareMetadataOutboundJson = Json { ignoreUnknownKeys = true; encodeDefaults = true }

    suspend fun fetchConversations(limit: Int = 50, offset: Int = 0): List<ConversationOverviewWire> {
        val params = buildJsonObject {
            put("p_limit", limit)
            put("p_offset", offset)
        }
        val res = supabase.postgrest.rpc(BackendContracts.Rpc.GET_CONVERSATIONS_OVERVIEW, params) { }
        return json.decodeFromString(ListSerializer(ConversationOverviewWire.serializer()), res.data)
    }

    /**
     * Fetch one page of messages older than [beforeId]. Server returns DESC.
     * Caller is expected to flip the order for display.
     */
    suspend fun fetchMessages(conversationId: Long, beforeId: Long? = null, limit: Int = 50): List<ChatMessageWire> {
        val params = buildJsonObject {
            put("p_conversation_id", conversationId)
            if (beforeId != null) put("p_cursor_before_id", beforeId)
            put("p_limit", limit)
        }
        val res = supabase.postgrest.rpc(BackendContracts.Rpc.GET_MESSAGES, params) { }
        return json.decodeFromString(ListSerializer(ChatMessageWire.serializer()), res.data)
    }

    /**
     * Idempotent: if a direct conversation already exists with [otherUserId]
     * the same id is returned. Throws when [are_mutual_followers] is false.
     */
    suspend fun startDirectConversation(otherUserId: String): Long {
        val params = buildJsonObject {
            put("p_other", otherUserId)
        }
        val res = supabase.postgrest.rpc(BackendContracts.Rpc.START_DIRECT_CONVERSATION, params) { }
        return parseSingleLong(res.data)
    }

    suspend fun sendMessage(
        conversationId: Long,
        body: String,
        clientMsgId: UUID = UUID.randomUUID(),
        kind: String = "text",
        replyToMessageId: Long? = null
    ): Long {
        val params = buildJsonObject {
            put("p_conversation_id", conversationId)
            put("p_kind", kind)
            put("p_body", body)
            put("p_metadata", JsonObject(emptyMap()))
            put("p_client_msg_id", clientMsgId.toString())
            if (replyToMessageId != null) put("p_reply_to_message_id", replyToMessageId)
        }
        val res = supabase.postgrest.rpc(BackendContracts.Rpc.SEND_MESSAGE, params) { }
        return parseSingleLong(res.data)
    }

    /**
     * Sends a `workout_share` message: same RPC as text, but with kind set
     * to `workout_share` and the snapshot serialized into `metadata`. The
     * optional [caption] becomes the message body so push previews and the
     * inbox snippet show the user's caption when present.
     */
    suspend fun sendWorkoutShare(
        conversationId: Long,
        snapshot: WorkoutShareSnapshot,
        caption: String? = null,
        clientMsgId: UUID = UUID.randomUUID(),
        replyToMessageId: Long? = null
    ): Long {
        val metadataElement = shareMetadataOutboundJson.encodeToJsonElement(WorkoutShareSnapshot.serializer(), snapshot)
        val params = buildJsonObject {
            put("p_conversation_id", conversationId)
            put("p_kind", "workout_share")
            put("p_body", caption?.trim().orEmpty())
            put("p_metadata", metadataElement)
            put("p_client_msg_id", clientMsgId.toString())
            if (replyToMessageId != null) put("p_reply_to_message_id", replyToMessageId)
        }
        val res = supabase.postgrest.rpc(BackendContracts.Rpc.SEND_MESSAGE, params) { }
        return parseSingleLong(res.data)
    }

    suspend fun sendRoutineShare(
        conversationId: Long,
        snapshot: RoutineShareSnapshot,
        caption: String? = null,
        clientMsgId: UUID = UUID.randomUUID(),
        replyToMessageId: Long? = null
    ): Long {
        val metadataElement = shareMetadataOutboundJson.encodeToJsonElement(RoutineShareSnapshot.serializer(), snapshot)
        val params = buildJsonObject {
            put("p_conversation_id", conversationId)
            put("p_kind", "routine_share")
            put("p_body", caption?.trim().orEmpty())
            put("p_metadata", metadataElement)
            put("p_client_msg_id", clientMsgId.toString())
            if (replyToMessageId != null) put("p_reply_to_message_id", replyToMessageId)
        }
        val res = supabase.postgrest.rpc(BackendContracts.Rpc.SEND_MESSAGE, params) { }
        return parseSingleLong(res.data)
    }

    suspend fun sendAchievementShare(
        conversationId: Long,
        snapshot: AchievementShareSnapshot,
        caption: String? = null,
        clientMsgId: UUID = UUID.randomUUID(),
        replyToMessageId: Long? = null
    ): Long {
        val metadataElement = shareMetadataOutboundJson.encodeToJsonElement(AchievementShareSnapshot.serializer(), snapshot)
        val params = buildJsonObject {
            put("p_conversation_id", conversationId)
            put("p_kind", "achievement_share")
            put("p_body", caption?.trim().orEmpty())
            put("p_metadata", metadataElement)
            put("p_client_msg_id", clientMsgId.toString())
            if (replyToMessageId != null) put("p_reply_to_message_id", replyToMessageId)
        }
        val res = supabase.postgrest.rpc(BackendContracts.Rpc.SEND_MESSAGE, params) { }
        return parseSingleLong(res.data)
    }

    suspend fun sendSegmentShare(
        conversationId: Long,
        snapshot: SegmentShareSnapshot,
        caption: String? = null,
        clientMsgId: UUID = UUID.randomUUID(),
        replyToMessageId: Long? = null
    ): Long {
        val metadataElement = shareMetadataOutboundJson.encodeToJsonElement(SegmentShareSnapshot.serializer(), snapshot)
        val params = buildJsonObject {
            put("p_conversation_id", conversationId)
            put("p_kind", "segment_share")
            put("p_body", caption?.trim().orEmpty())
            put("p_metadata", metadataElement)
            put("p_client_msg_id", clientMsgId.toString())
            if (replyToMessageId != null) put("p_reply_to_message_id", replyToMessageId)
        }
        val res = supabase.postgrest.rpc(BackendContracts.Rpc.SEND_MESSAGE, params) { }
        return parseSingleLong(res.data)
    }

    suspend fun sendSharedIngredient(
        conversationId: Long,
        snapshot: SharedIngredientSnapshot,
        caption: String? = null,
        clientMsgId: UUID = UUID.randomUUID(),
        replyToMessageId: Long? = null
    ): Long {
        val metadataElement = shareMetadataOutboundJson.encodeToJsonElement(
            SharedIngredientSnapshot.serializer(),
            snapshot
        )
        val params = buildJsonObject {
            put("p_conversation_id", conversationId)
            put("p_kind", "shared_ingredient")
            put("p_body", caption?.trim().orEmpty())
            put("p_metadata", metadataElement)
            put("p_client_msg_id", clientMsgId.toString())
            if (replyToMessageId != null) put("p_reply_to_message_id", replyToMessageId)
        }
        val res = supabase.postgrest.rpc(BackendContracts.Rpc.SEND_MESSAGE, params) { }
        return parseSingleLong(res.data)
    }

    suspend fun sendSharedRecipe(
        conversationId: Long,
        snapshot: SharedRecipeSnapshot,
        caption: String? = null,
        clientMsgId: UUID = UUID.randomUUID(),
        replyToMessageId: Long? = null
    ): Long {
        val metadataElement = shareMetadataOutboundJson.encodeToJsonElement(
            SharedRecipeSnapshot.serializer(),
            snapshot
        )
        val params = buildJsonObject {
            put("p_conversation_id", conversationId)
            put("p_kind", "shared_recipe")
            put("p_body", caption?.trim().orEmpty())
            put("p_metadata", metadataElement)
            put("p_client_msg_id", clientMsgId.toString())
            if (replyToMessageId != null) put("p_reply_to_message_id", replyToMessageId)
        }
        val res = supabase.postgrest.rpc(BackendContracts.Rpc.SEND_MESSAGE, params) { }
        return parseSingleLong(res.data)
    }

    suspend fun cloneSharedIngredient(snapshot: SharedIngredientSnapshot): String {
        val payload = shareMetadataOutboundJson.encodeToJsonElement(SharedIngredientSnapshot.serializer(), snapshot)
        val params = buildJsonObject { put("p_snapshot", payload) }
        val res = supabase.postgrest.rpc(BackendContracts.Rpc.CLONE_SHARED_INGREDIENT, params) { }
        return parseSingleUuidString(res.data)
    }

    suspend fun cloneSharedRecipe(snapshot: SharedRecipeSnapshot): String {
        val payload = shareMetadataOutboundJson.encodeToJsonElement(SharedRecipeSnapshot.serializer(), snapshot)
        val params = buildJsonObject { put("p_snapshot", payload) }
        val res = supabase.postgrest.rpc(BackendContracts.Rpc.CLONE_SHARED_RECIPE, params) { }
        return parseSingleUuidString(res.data)
    }

    suspend fun markRead(conversationId: Long, lastMessageId: Long) {
        val params = buildJsonObject {
            put("p_conversation_id", conversationId)
            put("p_last_read_message_id", lastMessageId)
        }
        supabase.postgrest.rpc(BackendContracts.Rpc.MARK_CONVERSATION_READ, params) { }
    }

    /** Hides the conversation for the current user until a new message arrives. */
    suspend fun clearConversation(conversationId: Long) {
        val params = buildJsonObject { put("p_conversation_id", conversationId) }
        supabase.postgrest.rpc(BackendContracts.Rpc.CLEAR_CONVERSATION, params) { }
    }

    /** Toggle per-user mute. Muted conversations don't trigger pushes. */
    suspend fun setMuted(conversationId: Long, muted: Boolean) {
        val params = buildJsonObject {
            put("p_conversation_id", conversationId)
            put("p_muted", muted)
        }
        supabase.postgrest.rpc(BackendContracts.Rpc.SET_CONVERSATION_MUTED, params) { }
    }

    /** True if the reaction was added, false if it was removed (toggle). */
    suspend fun toggleReaction(messageId: Long, emojiRaw: String): Boolean {
        val params = buildJsonObject {
            put("p_message_id", messageId)
            put("p_emoji", emojiRaw)
        }
        val res = supabase.postgrest.rpc(BackendContracts.Rpc.TOGGLE_MESSAGE_REACTION, params) { }
        return runCatching { json.decodeFromString(Boolean.serializer(), res.data.trim()) }
            .getOrElse {
                json.parseToJsonElement(res.data.trim()).jsonArray
                    .firstOrNull()?.toString()?.toBooleanStrictOrNull() ?: true
            }
    }

    suspend fun editMessage(messageId: Long, body: String) {
        val params = buildJsonObject {
            put("p_message_id", messageId)
            put("p_body", body)
        }
        supabase.postgrest.rpc(BackendContracts.Rpc.EDIT_MESSAGE, params) { }
    }

    suspend fun deleteMessage(messageId: Long) {
        val params = buildJsonObject { put("p_message_id", messageId) }
        supabase.postgrest.rpc(BackendContracts.Rpc.DELETE_MESSAGE, params) { }
    }

    /** Bulk-load reactions for a list of message ids. */
    suspend fun fetchReactions(messageIds: List<Long>): Map<Long, List<ReactionWire>> {
        if (messageIds.isEmpty()) return emptyMap()
        val rows = supabase.from(BackendContracts.Tables.MESSAGE_REACTIONS)
            .select {
                filter { isIn("message_id", messageIds.map { it.toString() }) }
                order("created_at", Order.ASCENDING)
                limit((messageIds.size * 12L).coerceAtLeast(12L))
            }
            .decodeList<ReactionWire>()
        return rows.groupBy { it.messageId }
    }

    /** Compact preview rows for the parent messages of replies. */
    suspend fun fetchReplyTargets(messageIds: List<Long>): Map<Long, ReplyPreviewWire> {
        if (messageIds.isEmpty()) return emptyMap()
        val rows = supabase.from(BackendContracts.Tables.MESSAGES)
            .select(columns = io.github.jan.supabase.postgrest.query.Columns.raw(
                "id, user_id, body, kind, metadata, deleted_at"
            )) {
                filter { isIn("id", messageIds.map { it.toString() }) }
                limit((messageIds.size + 1L))
            }
            .decodeList<ReplyPreviewWire>()
        return rows.associateBy { it.id }
    }

    /**
     * Peer's last_read_message_id for a 1:1 conversation. Returns null
     * when the peer hasn't read anything yet.
     */
    suspend fun fetchPeerLastRead(conversationId: Long, myUserId: String): Long? {
        val rows = supabase.from(BackendContracts.Tables.CONVERSATION_READS)
            .select {
                filter {
                    eq("conversation_id", conversationId.toString())
                    neq("user_id", myUserId)
                }
                limit(8)
            }
            .decodeList<ConversationReadRow>()
        return rows.mapNotNull { it.lastReadMessageId }.maxOrNull()
    }

    /** Whether the current user has muted this conversation. */
    suspend fun fetchMutedFlag(conversationId: Long, myUserId: String): Boolean {
        val rows = supabase.from(BackendContracts.Tables.CONVERSATION_PARTICIPANTS)
            .select(columns = io.github.jan.supabase.postgrest.query.Columns.raw("muted")) {
                filter {
                    eq("conversation_id", conversationId.toString())
                    eq("user_id", myUserId)
                }
                limit(1)
            }
            .decodeList<ParticipantMutedRow>()
        return rows.firstOrNull()?.muted ?: false
    }

    /** Resolve the "other" participant for each conversation in a batch. */
    suspend fun fetchOtherParticipantIds(
        conversationIds: List<Long>,
        myUserId: String
    ): Map<Long, String> {
        if (conversationIds.isEmpty()) return emptyMap()
        val rows = supabase.from(BackendContracts.Tables.CONVERSATION_PARTICIPANTS)
            .select {
                filter {
                    isIn("conversation_id", conversationIds.map { it.toString() })
                    neq("user_id", myUserId)
                }
                limit((conversationIds.size * 8L).coerceAtLeast(8L))
            }
            .decodeList<ChatParticipantRow>()
        val out = mutableMapOf<Long, String>()
        for (r in rows) {
            if (out.containsKey(r.conversationId)) continue
            out[r.conversationId] = r.userId
        }
        return out
    }

    suspend fun fetchProfiles(userIds: Collection<String>): Map<String, ProfileLite> {
        if (userIds.isEmpty()) return emptyMap()
        val list = supabase.from(BackendContracts.Tables.PROFILES)
            .select {
                filter { isIn("user_id", userIds.toList()) }
                limit((userIds.size + 1).toLong())
            }
            .decodeList<ProfileLite>()
        return list.associateBy { it.userId }
    }

    suspend fun fetchProfile(userId: String): ProfileLite? {
        val list = supabase.from(BackendContracts.Tables.PROFILES)
            .select {
                filter { eq("user_id", userId) }
                limit(1)
            }
            .decodeList<ProfileLite>()
        return list.firstOrNull()
    }

    /**
     * Mutual followees: the intersection of (people I follow) and
     * (people who follow me). Hydrates `profiles` for the result.
     */
    suspend fun fetchMutualFollowees(myUserId: String): List<ProfileLite> {
        val following = supabase.from(BackendContracts.Tables.FOLLOWS)
            .select(columns = io.github.jan.supabase.postgrest.query.Columns.raw("followee_id")) {
                filter { eq("follower_id", myUserId) }
                limit(2000)
            }
            .decodeList<FollowEdge>()
        val followers = supabase.from(BackendContracts.Tables.FOLLOWS)
            .select(columns = io.github.jan.supabase.postgrest.query.Columns.raw("follower_id")) {
                filter { eq("followee_id", myUserId) }
                limit(2000)
            }
            .decodeList<FollowEdge>()

        val followingIds = following.mapNotNull { it.followeeId }.toSet()
        val followerIds = followers.mapNotNull { it.followerId }.toSet()
        val mutuals = followingIds.intersect(followerIds)
        if (mutuals.isEmpty()) return emptyList()

        return supabase.from(BackendContracts.Tables.PROFILES)
            .select {
                filter { isIn("user_id", mutuals.toList()) }
                order("username", Order.ASCENDING)
                limit(2000)
            }
            .decodeList<ProfileLite>()
    }

    /**
     * Postgres RPC functions returning a scalar can either come back as `42`
     * or `[42]` depending on PostgREST settings. Tolerate both.
     */
    private fun parseSingleLong(raw: String): Long {
        val trimmed = raw.trim()
        if (trimmed.isEmpty()) error("Empty RPC response")
        return runCatching { json.decodeFromString(Long.serializer(), trimmed) }
            .getOrElse {
                val arr = json.parseToJsonElement(trimmed).jsonArray
                arr.firstOrNull()?.toString()?.toLongOrNull()
                    ?: error("Unexpected RPC response: $trimmed")
            }
    }

    private fun parseSingleUuidString(raw: String): String {
        val trimmed = raw.trim()
        if (trimmed.isEmpty()) error("Empty RPC response")
        val direct = trimmed.trim('"')
        if (!direct.startsWith("[")) return direct
        val arr = json.parseToJsonElement(trimmed).jsonArray
        return arr.firstOrNull()?.toString()?.trim('"')
            ?: error("Unexpected RPC response: $trimmed")
    }

}
