package com.lilru.liftr.data

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class ProfileInsert(
    @SerialName("user_id")
    val userId: String,
    val username: String,
    val sex: String = "prefer_not_to_say"
)
