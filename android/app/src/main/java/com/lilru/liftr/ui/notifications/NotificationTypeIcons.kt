package com.lilru.liftr.ui.notifications

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AlternateEmail
import androidx.compose.material.icons.filled.Block
import androidx.compose.material.icons.filled.Cancel
import androidx.compose.material.icons.filled.Chat
import androidx.compose.material.icons.filled.ChatBubble
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.EmojiEvents
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.Flag
import androidx.compose.material.icons.filled.GroupAdd
import androidx.compose.material.icons.outlined.Flag
import androidx.compose.material.icons.filled.Mail
import androidx.compose.material.icons.filled.Map
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.filled.Pets
import androidx.compose.material.icons.filled.PersonAdd
import androidx.compose.material.icons.filled.RateReview
import androidx.compose.material.icons.filled.Reply
import androidx.compose.material.icons.filled.Restaurant
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.ThumbUp
import androidx.compose.material.icons.filled.TrackChanges
import androidx.compose.material.icons.filled.Verified
import androidx.compose.ui.graphics.vector.ImageVector

fun notificationIcon(type: String): ImageVector {
    return when (type) {
        "dm_message" -> Icons.Filled.Chat
        "new_follower" -> Icons.Filled.PersonAdd
        "workout_like" -> Icons.Filled.Favorite
        "workout_comment" -> Icons.Filled.ChatBubble
        "comment_like" -> Icons.Filled.ThumbUp
        "comment_reply" -> Icons.Filled.Reply
        "comment_mention" -> Icons.Filled.AlternateEmail
        "added_as_participant" -> Icons.Filled.GroupAdd
        "achievement_unlocked" -> Icons.Filled.EmojiEvents
        "goal_completed", "goal_almost_done" -> Icons.Filled.TrackChanges
        "competition_invite" -> Icons.Filled.Mail
        "competition_accepted" -> Icons.Filled.CheckCircle
        "competition_declined" -> Icons.Filled.Cancel
        "competition_cancelled", "competition_expired" -> Icons.Filled.Schedule
        "competition_result_win" -> Icons.Filled.EmojiEvents
        "competition_result_lose" -> Icons.Filled.Flag
        "competition_workout_pending_review" -> Icons.Filled.RateReview
        "competition_workout_accepted" -> Icons.Filled.Verified
        "competition_workout_rejected" -> Icons.Filled.Block
        "meal_plan_invite" -> Icons.Filled.Restaurant
        "apple_health_cardio_imported" -> Icons.Filled.Favorite
        "segment_you_are_first" -> Icons.Filled.Flag
        "segment_lost_first" -> Icons.Outlined.Flag
        "territory_capture_from_user", "territory_lost_to_user" -> Icons.Filled.Map
        "challenge_won", "challenge_won_weekly" -> Icons.Filled.Star
        "workout_kind_inactive" -> Icons.Filled.Notifications
        "pet_hatched" -> Icons.Filled.Pets
        else -> Icons.Filled.Notifications
    }
}

fun notificationTypeLabel(type: String): String {
    return when (type) {
        "new_follower" -> "Follower"
        "workout_like" -> "Workout like"
        "workout_comment" -> "Workout comment"
        "comment_like" -> "Comment like"
        "comment_reply" -> "Reply"
        "comment_mention" -> "Mention"
        "added_as_participant" -> "Participant"
        "achievement_unlocked" -> "Achievement"
        "goal_completed", "goal_almost_done" -> "Goal"
        "competition_invite",
        "competition_accepted",
        "competition_declined",
        "competition_cancelled",
        "competition_expired" -> "Competition"
        "competition_workout_pending_review",
        "competition_workout_accepted",
        "competition_workout_rejected" -> "Workout review"
        "competition_result_win",
        "competition_result_lose" -> "Result"
        "workout_kind_inactive" -> "Reminder"
        "meal_plan_invite" -> "Meal plan"
        "apple_health_cardio_imported" -> "Apple Health"
        "segment_you_are_first",
        "segment_lost_first" -> "Segment"
        "challenge_won",
        "challenge_won_weekly" -> "Challenge"
        "territory_capture_from_user" -> "Territory captured"
        "territory_lost_to_user" -> "Territory lost"
        "dm_message" -> "Message"
        else -> type.replace('_', ' ').replaceFirstChar { it.uppercase() }
    }
}
