package com.lilru.liftr.ui.health

internal fun isHealthConnectUuidUniqueViolation(error: Throwable): Boolean {
    val text = (error.message ?: error.toString()).lowercase()
    if (!text.contains("23505") && !text.contains("duplicate key")) return false
    return text.contains("healthkit_uuid")
        || text.contains("workouts_healthkit_uuid_unique")
        || text.contains("workouts_user_healthkit_uuid_unique")
}
