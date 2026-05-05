package com.lilru.liftr.ui.feature

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject

@Serializable
data class FeatureRequestRow(
    val id: Long,
    @SerialName("created_by") val createdBy: String,
    @SerialName("created_by_username") val createdByUsername: String? = null,
    val title: String,
    val description: String,
    val status: String,
    @SerialName("created_at") val createdAt: String? = null,
    @SerialName("updated_at") val updatedAt: String? = null,
    @SerialName("votes_count") val votesCount: Int? = null,
    @SerialName("comments_count") val commentsCount: Int? = null
)

@Serializable
data class FeatureRequestInsert(
    val title: String,
    val description: String,
    val email: String? = null,
    @SerialName("created_by") val createdBy: String
)

@Serializable
data class FeatureRequestCommentRow(
    val id: Long,
    @SerialName("feature_request_id") val featureRequestId: Long,
    @SerialName("user_id") val userId: String,
    @SerialName("user_username") val userUsername: String? = null,
    val body: String,
    @SerialName("created_at") val createdAt: String? = null,
    @SerialName("updated_at") val updatedAt: String? = null
)

@Serializable
data class FeatureVoteInsert(
    @SerialName("feature_request_id") val featureRequestId: Long,
    @SerialName("user_id") val userId: String
)

@Serializable
data class FeatureCommentInsert(
    @SerialName("feature_request_id") val featureRequestId: Long,
    @SerialName("user_id") val userId: String,
    val body: String
)

object FeatureRequestsJson {
    val json: Json = Json { ignoreUnknownKeys = true }

    inline fun <reified T> decodeList(raw: String): List<T> {
        val root = json.parseToJsonElement(raw)
        return when (root) {
            is JsonArray -> root.map { json.decodeFromString<T>(it.toString()) }
            is JsonObject -> listOf(json.decodeFromString<T>(root.toString()))
            else -> emptyList()
        }
    }
}
