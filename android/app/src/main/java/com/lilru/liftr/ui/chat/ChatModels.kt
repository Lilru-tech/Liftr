package com.lilru.liftr.ui.chat

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.decodeFromJsonElement

/**
 * Inbox row produced by `public.get_conversations_overview()`.
 */
@Serializable
data class ConversationOverviewWire(
    val id: Long,
    val kind: String,
    val title: String? = null,
    @SerialName("updated_at") val updatedAt: String,
    @SerialName("last_message_id") val lastMessageId: Long? = null,
    @SerialName("last_message_user_id") val lastMessageUserId: String? = null,
    @SerialName("last_message_body") val lastMessageBody: String? = null,
    @SerialName("last_message_at") val lastMessageAt: String? = null,
    @SerialName("unread_count") val unreadCount: Int = 0
)

/**
 * Single message returned by `public.get_messages()` and broadcast events.
 */
@Serializable
data class ChatMessageWire(
    val id: Long,
    @SerialName("user_id") val userId: String,
    val kind: String = "text",
    val body: String? = null,
    val metadata: JsonObject? = null,
    @SerialName("reply_to_message_id") val replyToMessageId: Long? = null,
    @SerialName("created_at") val createdAt: String,
    @SerialName("edited_at") val editedAt: String? = null,
    @SerialName("deleted_at") val deletedAt: String? = null,
    @SerialName("conversation_id") val conversationId: Long? = null
)

/**
 * One reaction row produced by `public.message_reactions` (and the
 * `conversation:<id>:reactions` realtime topic).
 */
@Serializable
data class ReactionWire(
    @SerialName("message_id") val messageId: Long,
    @SerialName("user_id") val userId: String,
    val emoji: String,
    @SerialName("created_at") val createdAt: String
)

/**
 * Six-emoji set matching the CHECK constraint on
 * `public.message_reactions.emoji`.
 */
enum class ReactionEmoji(val raw: String, val glyph: String) {
    HEART("heart", "\u2764\ufe0f"),
    HAHA("haha", "\ud83d\ude02"),
    WOW("wow", "\ud83d\ude2e"),
    SAD("sad", "\ud83d\ude22"),
    THUMBS_UP("thumbs_up", "\ud83d\udc4d"),
    THUMBS_DOWN("thumbs_down", "\ud83d\udc4e");

    companion object {
        fun fromRaw(raw: String): ReactionEmoji? = entries.firstOrNull { it.raw == raw }
    }
}

/**
 * Compact preview of a parent message used by the in-bubble reply chip.
 */
@Serializable
data class ReplyPreviewWire(
    val id: Long,
    @SerialName("user_id") val userId: String,
    val body: String? = null,
    val kind: String? = null,
    val metadata: JsonObject? = null,
    @SerialName("deleted_at") val deletedAt: String? = null
)

/**
 * Row from `conversation_reads` used to build the "Seen" indicator.
 */
@Serializable
data class ConversationReadRow(
    @SerialName("user_id") val userId: String,
    @SerialName("last_read_message_id") val lastReadMessageId: Long? = null
)

/**
 * Mute flag on `conversation_participants` for the current user.
 */
@Serializable
data class ParticipantMutedRow(
    val muted: Boolean = false
)

@Serializable
data class ProfileLite(
    @SerialName("user_id") val userId: String,
    val username: String,
    @SerialName("avatar_url") val avatarUrl: String? = null
)

@Serializable
data class ChatParticipantRow(
    @SerialName("conversation_id") val conversationId: Long,
    @SerialName("user_id") val userId: String
)

@Serializable
data class FollowEdge(
    @SerialName("follower_id") val followerId: String? = null,
    @SerialName("followee_id") val followeeId: String? = null
)

/**
 * `messages.kind` values understood by the client. New entries (e.g. share
 * variants) must default to [TEXT] in older builds via [fromRaw], so unknown
 * kinds keep rendering as plain bubbles instead of crashing.
 */
enum class ChatKind(val raw: String) {
    TEXT("text"),
    IMAGE("image"),
    FILE("file"),
    SYSTEM("system"),
    WORKOUT_SHARE("workout_share"),
    ROUTINE_SHARE("routine_share"),
    ACHIEVEMENT_SHARE("achievement_share"),
    SEGMENT_SHARE("segment_share"),
    SHARED_INGREDIENT("shared_ingredient"),
    SHARED_RECIPE("shared_recipe");

    companion object {
        fun fromRaw(raw: String?): ChatKind =
            entries.firstOrNull { it.raw == raw } ?: TEXT
    }
}

/**
 * Compact, self-contained snapshot of a workout that travels inside a
 * `workout_share` message's `metadata`. The snapshot keeps the chat preview
 * readable even if the original workout is later deleted.
 */
@Serializable
data class WorkoutShareSnapshot(
    val v: Int = 1,
    val type: String = "workout_share",
    @SerialName("workout_id") val workoutId: Long,
    val title: String? = null,
    val kind: String? = null,
    val score: Int? = null,
    val kcal: Int? = null,
    @SerialName("performed_at") val performedAt: String? = null,
    @SerialName("owner_user_id") val ownerUserId: String? = null,
    @SerialName("owner_username") val ownerUsername: String? = null,
    @SerialName("owner_avatar_url") val ownerAvatarUrl: String? = null
)

@Serializable
data class RoutineShareSnapshot(
    val v: Int = 1,
    val type: String = "routine_share",
    @SerialName("routine_kind") val routineKind: String,
    val name: String,
    @SerialName("routine_id") val routineId: Long? = null,
    @SerialName("updated_at") val updatedAt: String? = null,
    @SerialName("owner_user_id") val ownerUserId: String? = null,
    @SerialName("owner_username") val ownerUsername: String? = null,
    @SerialName("owner_avatar_url") val ownerAvatarUrl: String? = null,
    @SerialName("share_nonce") val shareNonce: String,
    @SerialName("detail_json") val detailJson: String,
    @SerialName("exercise_count") val exerciseCount: Int? = null,
    @SerialName("total_sets") val totalSets: Int? = null,
    @SerialName("preview_exercise_name") val previewExerciseName: String? = null
)

@Serializable
data class AchievementShareSnapshot(
    val v: Int = 1,
    val type: String = "achievement_share",
    val code: String,
    @SerialName("achievement_id") val achievementId: Int,
    val title: String,
    val category: String,
    val description: String? = null,
    @SerialName("icon_url") val iconUrl: String? = null,
    @SerialName("owner_user_id") val ownerUserId: String? = null,
    @SerialName("owner_username") val ownerUsername: String? = null,
    @SerialName("owner_avatar_url") val ownerAvatarUrl: String? = null
)

@Serializable
data class SegmentShareSnapshot(
    val v: Int = 1,
    val type: String = "segment_share",
    @SerialName("segment_id") val segmentId: String,
    val name: String,
    @SerialName("segment_length_m") val segmentLengthM: Double? = null,
    @SerialName("leaderboard_effort_count") val leaderboardEffortCount: Long? = null,
    @SerialName("owner_user_id") val ownerUserId: String? = null,
    @SerialName("owner_username") val ownerUsername: String? = null,
    @SerialName("owner_avatar_url") val ownerAvatarUrl: String? = null
)

@Serializable
data class SharedIngredientSnapshot(
    val v: Int = 1,
    val type: String = "shared_ingredient",
    val name: String,
    @SerialName("calories_per_100g") val caloriesPer100g: Double,
    @SerialName("protein_per_100g") val proteinPer100g: Double = 0.0,
    @SerialName("carbs_per_100g") val carbsPer100g: Double = 0.0,
    @SerialName("fat_per_100g") val fatPer100g: Double = 0.0,
    @SerialName("saturated_fat_per_100g") val saturatedFatPer100g: Double = 0.0,
    @SerialName("sugars_per_100g") val sugarsPer100g: Double = 0.0,
    @SerialName("fiber_per_100g") val fiberPer100g: Double = 0.0,
    @SerialName("sodium_mg_per_100g") val sodiumMgPer100g: Double = 0.0
)

@Serializable
data class SharedRecipeIngredientSnapshot(
    val name: String,
    @SerialName("weight_g") val weightG: Double,
    @SerialName("calories_per_100g") val caloriesPer100g: Double,
    @SerialName("protein_per_100g") val proteinPer100g: Double = 0.0,
    @SerialName("carbs_per_100g") val carbsPer100g: Double = 0.0,
    @SerialName("fat_per_100g") val fatPer100g: Double = 0.0,
    @SerialName("saturated_fat_per_100g") val saturatedFatPer100g: Double = 0.0,
    @SerialName("sugars_per_100g") val sugarsPer100g: Double = 0.0,
    @SerialName("fiber_per_100g") val fiberPer100g: Double = 0.0,
    @SerialName("sodium_mg_per_100g") val sodiumMgPer100g: Double = 0.0
)

@Serializable
data class SharedRecipeProfilePer100gSnapshot(
    val calories: Double,
    val protein: Double,
    val carbs: Double,
    val fat: Double,
    val saturatedFat: Double,
    val sugars: Double,
    val fiber: Double,
    val sodiumMg: Double
)

@Serializable
data class SharedRecipeSnapshot(
    val v: Int = 1,
    val type: String = "shared_recipe",
    val name: String,
    val description: String? = null,
    val ingredients: List<SharedRecipeIngredientSnapshot>,
    @SerialName("profile_per_100g") val profilePer100g: SharedRecipeProfilePer100gSnapshot? = null
)

private val shareMetadataJson = Json { ignoreUnknownKeys = true }

private fun JsonObject.withDetailJsonCoercedToString(): JsonObject {
    return buildJsonObject {
        this@withDetailJsonCoercedToString.forEach { (k, v) ->
            if (k == "detail_json") {
                val normalized = when (v) {
                    is JsonPrimitive -> v
                    is JsonObject -> JsonPrimitive(v.toString())
                    is JsonArray -> JsonPrimitive(v.toString())
                    else -> v
                }
                put(k, normalized)
            } else {
                put(k, v)
            }
        }
    }
}

fun ChatMessageWire.decodeWorkoutShare(): WorkoutShareSnapshot? {
    if (ChatKind.fromRaw(kind) != ChatKind.WORKOUT_SHARE) return null
    val m = metadata ?: return null
    return runCatching { shareMetadataJson.decodeFromJsonElement(WorkoutShareSnapshot.serializer(), m) }.getOrNull()
}

fun ChatMessageWire.decodeRoutineShare(): RoutineShareSnapshot? {
    if (ChatKind.fromRaw(kind) != ChatKind.ROUTINE_SHARE) return null
    val m = metadata ?: return null
    val normalized = m.withDetailJsonCoercedToString()
    return runCatching {
        shareMetadataJson.decodeFromJsonElement(RoutineShareSnapshot.serializer(), normalized)
    }.getOrNull()
}

fun ChatMessageWire.decodeAchievementShare(): AchievementShareSnapshot? {
    if (ChatKind.fromRaw(kind) != ChatKind.ACHIEVEMENT_SHARE) return null
    val m = metadata ?: return null
    return runCatching {
        shareMetadataJson.decodeFromJsonElement(AchievementShareSnapshot.serializer(), m)
    }.getOrNull()
}

fun ChatMessageWire.decodeSegmentShare(): SegmentShareSnapshot? {
    if (ChatKind.fromRaw(kind) != ChatKind.SEGMENT_SHARE) return null
    val m = metadata ?: return null
    return runCatching {
        shareMetadataJson.decodeFromJsonElement(SegmentShareSnapshot.serializer(), m)
    }.getOrNull()
}

fun ChatMessageWire.decodeSharedIngredient(): SharedIngredientSnapshot? {
    if (ChatKind.fromRaw(kind) != ChatKind.SHARED_INGREDIENT) return null
    val m = metadata ?: return null
    return runCatching {
        shareMetadataJson.decodeFromJsonElement(SharedIngredientSnapshot.serializer(), m)
    }.getOrNull()
}

fun ChatMessageWire.decodeSharedRecipe(): SharedRecipeSnapshot? {
    if (ChatKind.fromRaw(kind) != ChatKind.SHARED_RECIPE) return null
    val m = metadata ?: return null
    return runCatching {
        shareMetadataJson.decodeFromJsonElement(SharedRecipeSnapshot.serializer(), m)
    }.getOrNull()
}

fun ChatMessageWire.replyComposerSubtitle(): String = when (ChatKind.fromRaw(kind)) {
    ChatKind.ROUTINE_SHARE -> decodeRoutineShare()?.let { r -> "Routine · ${r.name}" } ?: body.orEmpty()
    ChatKind.WORKOUT_SHARE -> decodeWorkoutShare()?.let { w ->
        val t = w.title?.trim()?.takeIf { it.isNotEmpty() }
        if (t != null) "Workout · $t" else "Workout"
    } ?: body.orEmpty()
    ChatKind.ACHIEVEMENT_SHARE -> decodeAchievementShare()?.let { a ->
        val t = a.title.trim().takeIf { it.isNotEmpty() }
        if (t != null) "Achievement · $t" else "Achievement"
    } ?: body.orEmpty()
    ChatKind.SEGMENT_SHARE -> decodeSegmentShare()?.let { s ->
        val t = s.name.trim().takeIf { it.isNotEmpty() }
        if (t != null) "Segment · $t" else "Segment"
    } ?: body.orEmpty()
    ChatKind.SHARED_INGREDIENT -> decodeSharedIngredient()?.let { "Ingredient · ${it.name}" } ?: body.orEmpty()
    ChatKind.SHARED_RECIPE -> decodeSharedRecipe()?.let { "Recipe · ${it.name}" } ?: body.orEmpty()
    else -> body.orEmpty()
}

fun ChatMessageWire.clipboardTextForCopy(): String = when (ChatKind.fromRaw(kind)) {
    ChatKind.ROUTINE_SHARE -> decodeRoutineShare()?.let { r ->
        buildString {
            append("Routine: ${r.name}")
            r.ownerUsername?.takeIf { it.isNotBlank() }?.let { append("\nFrom @").append(it) }
        }
    } ?: body.orEmpty()
    ChatKind.WORKOUT_SHARE -> decodeWorkoutShare()?.let { w ->
        buildString {
            append("Workout")
            w.title?.takeIf { it.isNotBlank() }?.let { append(": ").append(it) }
            w.ownerUsername?.takeIf { it.isNotBlank() }?.let { append("\nFrom @").append(it) }
        }
    } ?: body.orEmpty()
    ChatKind.ACHIEVEMENT_SHARE -> decodeAchievementShare()?.let { a ->
        buildString {
            append("Achievement: ${a.title}")
            a.ownerUsername?.takeIf { it.isNotBlank() }?.let { append("\nFrom @").append(it) }
        }
    } ?: body.orEmpty()
    ChatKind.SEGMENT_SHARE -> decodeSegmentShare()?.let { s ->
        buildString {
            append("Segment: ${s.name}")
            s.ownerUsername?.takeIf { it.isNotBlank() }?.let { append("\nFrom @").append(it) }
        }
    } ?: body.orEmpty()
    ChatKind.SHARED_INGREDIENT -> decodeSharedIngredient()?.let { s ->
        buildString { append("Ingredient: ${s.name}") }
    } ?: body.orEmpty()
    ChatKind.SHARED_RECIPE -> decodeSharedRecipe()?.let { s ->
        buildString { append("Recipe: ${s.name}") }
    } ?: body.orEmpty()
    else -> body.orEmpty()
}

fun ReplyPreviewWire.previewText(): String {
    if (deletedAt != null) return "Original message was deleted"
    return when (ChatKind.fromRaw(kind)) {
        ChatKind.ROUTINE_SHARE -> {
            val m = metadata ?: return body.orEmpty()
            runCatching {
                shareMetadataJson.decodeFromJsonElement(
                    RoutineShareSnapshot.serializer(),
                    m.withDetailJsonCoercedToString()
                ).name
            }.getOrNull()?.let { "Routine · $it" } ?: body.orEmpty()
        }
        ChatKind.WORKOUT_SHARE -> {
            val m = metadata ?: return body.orEmpty()
            runCatching {
                shareMetadataJson.decodeFromJsonElement(WorkoutShareSnapshot.serializer(), m)
            }.getOrNull()?.let { w ->
                val t = w.title?.trim()?.takeIf { it.isNotEmpty() }
                if (t != null) "Workout · $t" else "Workout"
            } ?: body.orEmpty()
        }
        ChatKind.ACHIEVEMENT_SHARE -> {
            val m = metadata ?: return body.orEmpty()
            runCatching {
                shareMetadataJson.decodeFromJsonElement(AchievementShareSnapshot.serializer(), m)
            }.getOrNull()?.let { a ->
                val t = a.title.trim().takeIf { it.isNotEmpty() }
                if (t != null) "Achievement · $t" else "Achievement"
            } ?: body.orEmpty()
        }
        ChatKind.SEGMENT_SHARE -> {
            val m = metadata ?: return body.orEmpty()
            runCatching {
                shareMetadataJson.decodeFromJsonElement(SegmentShareSnapshot.serializer(), m)
            }.getOrNull()?.let { s ->
                val t = s.name.trim().takeIf { it.isNotEmpty() }
                if (t != null) "Segment · $t" else "Segment"
            } ?: body.orEmpty()
        }
        ChatKind.SHARED_INGREDIENT -> {
            val m = metadata ?: return body.orEmpty()
            runCatching {
                shareMetadataJson.decodeFromJsonElement(SharedIngredientSnapshot.serializer(), m)
            }.getOrNull()?.let { s ->
                val t = s.name.trim().takeIf { it.isNotEmpty() }
                if (t != null) "Ingredient · $t" else "Ingredient"
            } ?: body.orEmpty()
        }
        ChatKind.SHARED_RECIPE -> {
            val m = metadata ?: return body.orEmpty()
            runCatching {
                shareMetadataJson.decodeFromJsonElement(SharedRecipeSnapshot.serializer(), m)
            }.getOrNull()?.let { s ->
                val t = s.name.trim().takeIf { it.isNotEmpty() }
                if (t != null) "Recipe · $t" else "Recipe"
            } ?: body.orEmpty()
        }
        else -> body.orEmpty()
    }
}
