package com.lilru.liftr.ui.chat

import android.util.Log
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.realtime.PostgresAction
import io.github.jan.supabase.realtime.PresenceAction
import io.github.jan.supabase.realtime.RealtimeChannel
import io.github.jan.supabase.realtime.broadcastFlow
import io.github.jan.supabase.realtime.channel
import io.github.jan.supabase.realtime.decodeJoinsAs
import io.github.jan.supabase.realtime.decodeLeavesAs
import io.github.jan.supabase.realtime.postgresChangeFlow
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancelChildren
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.longOrNull
import kotlinx.serialization.json.put

/** UI-friendly events emitted by [ChatThreadRealtime]. */
sealed interface ChatRealtimeEvent {
    data class Inserted(val message: ChatMessageWire) : ChatRealtimeEvent
    data class Updated(val message: ChatMessageWire) : ChatRealtimeEvent
    data class Deleted(val messageId: Long, val conversationId: Long) : ChatRealtimeEvent
}

/** UI-friendly events emitted by [ChatReactionsRealtime]. */
sealed interface ChatReactionRealtimeEvent {
    data class Inserted(val reaction: ReactionWire) : ChatReactionRealtimeEvent
    data class Deleted(val messageId: Long, val userId: String, val emoji: String) :
        ChatReactionRealtimeEvent
}

/**
 * Subscribes to broadcast events emitted by
 * `public.conversation_messages_broadcast_trigger` for a single conversation.
 *
 * Topic: `conversation:<id>:messages`
 * Events: `INSERT`, `UPDATE`, `DELETE`
 * Payload: `{ schema, table, operation, commit_timestamp, record, old_record }`
 *
 * Because `realtime.broadcast_changes` lives on the *private* channel
 * namespace, we set `isPrivate = true`; RLS authorizes us via the channel JWT.
 */
class ChatThreadRealtime(
    private val supabase: SupabaseClient,
    private val conversationId: Long,
    private val onEvent: (ChatRealtimeEvent) -> Unit
) {
    private val json = Json { ignoreUnknownKeys = true }
    private val scope = CoroutineScope(Dispatchers.Default + SupervisorJob())
    private var channel: RealtimeChannel? = null

    suspend fun start() {
        if (channel != null) return
        val topic = "conversation:$conversationId:messages"
        val ch = supabase.channel(topic) {
            isPrivate = true
        }
        channel = ch
        listen(ch, "INSERT") { record, _ ->
            json.decodeFromJsonElement(ChatMessageWire.serializer(), record)
                .let { onEvent(ChatRealtimeEvent.Inserted(it)) }
        }
        listen(ch, "UPDATE") { record, _ ->
            json.decodeFromJsonElement(ChatMessageWire.serializer(), record)
                .let { onEvent(ChatRealtimeEvent.Updated(it)) }
        }
        listen(ch, "DELETE") { _, oldRecord ->
            val raw = oldRecord ?: return@listen
            val id = (raw["id"] as? JsonPrimitive)?.longOrNull ?: return@listen
            onEvent(ChatRealtimeEvent.Deleted(id, conversationId))
        }
        // Must wait until SUBSCRIBED (same idea as iOS `subscribeWithError`).
        // With blockUntilSubscribed=false the private channel often isn't ready yet,
        // so inbound broadcasts from other clients are dropped until you leave/re-enter.
        ch.subscribe(blockUntilSubscribed = true)
    }

    suspend fun stop() {
        scope.coroutineContext.cancelChildren()
        channel?.unsubscribe()
        channel = null
    }

    private fun listen(
        ch: RealtimeChannel,
        event: String,
        handle: (record: JsonObject, oldRecord: JsonObject?) -> Unit
    ) {
        scope.launch {
            ch.broadcastFlow<JsonObject>(event = event).collect { payload ->
                runCatching {
                    val inner = unwrapBroadcastEnvelope(payload)
                    // IMPORTANT: use `as? JsonObject` rather than `.jsonObject`.
                    // The Realtime envelope ships `old_record: null` (literal
                    // JsonNull) on INSERTs and `record: null` on DELETEs, and
                    // `.jsonObject` throws on JsonNull (only treats *absent*
                    // keys as null).
                    val record = inner["record"] as? JsonObject
                    val oldRecord = inner["old_record"] as? JsonObject
                    if (record != null) {
                        handle(record, oldRecord)
                    } else {
                        handle(buildJsonObject { }, oldRecord)
                    }
                }.onFailure { e ->
                    Log.w(TAG, "broadcast decode/handle failed event=$event", e)
                }
            }
        }
    }

    /**
     * Matches iOS [decodeEnvelope]: Realtime v2 often nests under `payload`,
     * but some paths expose `record`/`old_record` at the root.
     */
    private fun unwrapBroadcastEnvelope(payload: JsonObject): JsonObject {
        return (payload["payload"] as? JsonObject) ?: payload
    }

    private companion object {
        private const val TAG = "ChatThreadRealtime"
    }
}

/**
 * Subscribes to `conversation:<id>:reactions`, the topic emitted by
 * `public.message_reactions_broadcast_trigger`. Mirrors [ChatThreadRealtime]
 * so payloads are decoded the same way (including the `JsonNull` quirks of
 * `record` / `old_record`).
 */
class ChatReactionsRealtime(
    private val supabase: SupabaseClient,
    private val conversationId: Long,
    private val onEvent: (ChatReactionRealtimeEvent) -> Unit
) {
    private val json = Json { ignoreUnknownKeys = true }
    private val scope = CoroutineScope(Dispatchers.Default + SupervisorJob())
    private var channel: RealtimeChannel? = null

    suspend fun start() {
        if (channel != null) return
        val topic = "conversation:$conversationId:reactions"
        val ch = supabase.channel(topic) {
            isPrivate = true
        }
        channel = ch
        listen(ch, "INSERT") { record, _ ->
            json.decodeFromJsonElement(ReactionWire.serializer(), record)
                .let { onEvent(ChatReactionRealtimeEvent.Inserted(it)) }
        }
        listen(ch, "DELETE") { _, oldRecord ->
            val raw = oldRecord ?: return@listen
            val mid = (raw["message_id"] as? JsonPrimitive)?.longOrNull ?: return@listen
            val uid = (raw["user_id"] as? JsonPrimitive)?.contentOrNull ?: return@listen
            val emoji = (raw["emoji"] as? JsonPrimitive)?.contentOrNull ?: return@listen
            onEvent(ChatReactionRealtimeEvent.Deleted(mid, uid, emoji))
        }
        ch.subscribe(blockUntilSubscribed = true)
    }

    suspend fun stop() {
        scope.coroutineContext.cancelChildren()
        channel?.unsubscribe()
        channel = null
    }

    private fun listen(
        ch: RealtimeChannel,
        event: String,
        handle: (record: JsonObject, oldRecord: JsonObject?) -> Unit
    ) {
        scope.launch {
            ch.broadcastFlow<JsonObject>(event = event).collect { payload ->
                runCatching {
                    val inner = (payload["payload"] as? JsonObject) ?: payload
                    val record = inner["record"] as? JsonObject
                    val oldRecord = inner["old_record"] as? JsonObject
                    if (record != null) {
                        handle(record, oldRecord)
                    } else {
                        handle(buildJsonObject { }, oldRecord)
                    }
                }.onFailure { e ->
                    Log.w(TAG, "broadcast decode/handle failed event=$event", e)
                }
            }
        }
    }

    private companion object {
        private const val TAG = "ChatReactionsRealtime"
    }
}

/** "User X is typing…" presence channel. */
class ChatTypingChannel(
    private val supabase: SupabaseClient,
    private val conversationId: Long,
    private val myUserId: String,
    private val onState: (Set<String>) -> Unit
) {
    private val scope = CoroutineScope(Dispatchers.Default + SupervisorJob())
    private var channel: RealtimeChannel? = null
    private val presences = mutableMapOf<String, Pair<String, Boolean>>()
    private var debounceJob: Job? = null

    suspend fun start() {
        if (channel != null) return
        val topic = "chat:typing:$conversationId"
        val ch = supabase.channel(topic) {
            presence { key = myUserId }
        }
        channel = ch
        scope.launch {
            ch.presenceChangeFlow().collect { action: PresenceAction ->
                applyDiff(action)
            }
        }
        ch.subscribe(blockUntilSubscribed = true)
        track(false)
    }

    fun setTyping(isTyping: Boolean) {
        debounceJob?.cancel()
        debounceJob = scope.launch {
            track(isTyping)
            if (isTyping) {
                delay(2_500)
                track(false)
            }
        }
    }

    suspend fun stop() {
        debounceJob?.cancel()
        scope.coroutineContext.cancelChildren()
        channel?.untrack()
        channel?.unsubscribe()
        channel = null
        presences.clear()
    }

    private suspend fun track(typing: Boolean) {
        val payload = buildJsonObject {
            put("user_id", myUserId)
            put("typing", typing)
        }
        channel?.track(payload)
    }

    private fun applyDiff(action: PresenceAction) {
        val joins = runCatching {
            action.decodeJoinsAs<TypingPresence>(ignoreOtherTypes = true)
        }.getOrDefault(emptyList())
        val leaves = runCatching {
            action.decodeLeavesAs<TypingPresence>(ignoreOtherTypes = true)
        }.getOrDefault(emptyList())

        for (left in leaves) {
            // We index by user_id since `presence.key = myUserId`.
            presences.remove(left.user_id)
        }
        for (joined in joins) {
            presences[joined.user_id] = joined.user_id to (joined.typing == true)
        }
        val typingUsers = presences.values
            .filter { (uid, t) -> t && uid != myUserId }
            .map { it.first }
            .toSet()
        onState(typingUsers)
    }

    @kotlinx.serialization.Serializable
    private data class TypingPresence(
        val user_id: String,
        val typing: Boolean? = null
    )
}

/**
 * Single multiplexed channel that fires whenever ANY message row changes,
 * letting the inbox refresh its overview. RLS filters to rows the user can
 * see, so we don't need to pre-compute conversation ids client-side.
 */
class ChatInboxRealtime(
    private val supabase: SupabaseClient,
    private val myUserId: String,
    private val onChange: () -> Unit
) {
    private val scope = CoroutineScope(Dispatchers.Default + SupervisorJob())
    private var channel: RealtimeChannel? = null

    suspend fun start() {
        if (channel != null) return
        val topic = "inbox:$myUserId"
        val ch = supabase.channel(topic) { }
        channel = ch
        scope.launch {
            ch.postgresChangeFlow<PostgresAction>(schema = "public") {
                table = "messages"
            }.collect { _ ->
                onChange()
            }
        }
        ch.subscribe(blockUntilSubscribed = true)
    }

    suspend fun stop() {
        scope.coroutineContext.cancelChildren()
        channel?.unsubscribe()
        channel = null
    }
}
