package com.lilru.liftr.ui.home

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.FavoriteBorder
import androidx.compose.material.icons.filled.ModeEdit
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.lilru.liftr.R
import com.lilru.liftr.ui.components.LiftrAvatar
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import kotlin.math.roundToInt

/**
 * Paridad con [Liftr/WorkoutCard.swift] `WorkoutFeedCard`: gradiente, jerarquía, píldoras, *Draft*.
 * El **tap** abre el detalle; no hay *like* en línea (como en iOS).
 */
@Composable
fun HomeWorkoutFeedCard(
    workout: WorkoutSummary,
    meUserId: String?,
    dayGroupLabel: String?,
    onClick: () -> Unit
) {
    val planned = workout.state?.lowercase() == "planned"
    val tint = workoutKindTintForFeed(workout.kind)
    val shape = RoundedCornerShape(14.dp)
    val displayName = when {
        meUserId != null && workout.userId == meUserId -> stringResource(R.string.home_feed_you)
        !workout.ownerUsername.isNullOrBlank() -> workout.ownerUsername!!
        else -> "—"
    }
    val kindKey = workout.kind?.lowercase().orEmpty()

    Box(
        modifier = Modifier
            .fillMaxWidth()
            .then(if (planned) Modifier.alpha(0.72f) else Modifier)
            .clip(shape)
            .background(
                brush = Brush.linearGradient(
                    listOf(
                        tint.copy(alpha = 0.28f),
                        tint.copy(alpha = 0.14f)
                    )
                )
            )
            .border(0.8.dp, Color.White.copy(alpha = 0.18f), shape)
            .clickable(onClick = onClick)
            .padding(14.dp)
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(if (dayGroupLabel == null) 8.dp else 4.dp)) {
            if (dayGroupLabel != null) {
                Text(
                    text = dayGroupLabel,
                    style = MaterialTheme.typography.labelSmall,
                    fontWeight = FontWeight.SemiBold,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    fontSize = 11.sp
                )
            }
            Row(
                verticalAlignment = Alignment.Top,
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                Box {
                    LiftrAvatar(
                        imageUrl = workout.ownerAvatarUrl,
                        displayName = workout.ownerUsername,
                        size = 42.dp
                    )
                    if (workout.coAvatarUrls.isNotEmpty()) {
                        Row(
                            modifier = Modifier
                                .align(Alignment.BottomEnd)
                                .offset(x = 2.dp, y = 2.dp),
                            horizontalArrangement = Arrangement.spacedBy((-8).dp)
                        ) {
                            for (u in workout.coAvatarUrls.take(3)) {
                                LiftrAvatar(
                                    imageUrl = u,
                                    displayName = null,
                                    size = 18.dp,
                                    modifier = Modifier
                                        .clip(CircleShape)
                                        .border(2.dp, MaterialTheme.colorScheme.surface, CircleShape)
                                )
                            }
                            if (workout.coAvatarUrls.size > 3) {
                                Surface(
                                    shape = CircleShape,
                                    color = MaterialTheme.colorScheme.surface,
                                    shadowElevation = 0.dp
                                ) {
                                    Text(
                                        text = "+${workout.coAvatarUrls.size - 3}",
                                        style = MaterialTheme.typography.labelSmall,
                                        fontWeight = FontWeight.Bold,
                                        modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp)
                                    )
                                }
                            }
                        }
                    }
                }
                Column(
                    modifier = Modifier.weight(1f),
                    verticalArrangement = Arrangement.spacedBy(4.dp)
                ) {
                    Text(
                        text = displayName,
                        style = MaterialTheme.typography.bodyMedium,
                        fontWeight = FontWeight.SemiBold,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                    if (!workout.title.isNullOrBlank()) {
                        Text(
                            text = workout.title,
                            style = MaterialTheme.typography.bodyLarge,
                            fontStyle = if (planned) FontStyle.Italic else FontStyle.Normal,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis
                        )
                    } else {
                        Text(
                            text = workoutKindLabel(workout.kind),
                            style = MaterialTheme.typography.bodyLarge,
                            fontStyle = if (planned) FontStyle.Italic else FontStyle.Normal,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis
                        )
                    }
                    Text(
                        text = homeFeedRelativeStartedAt(workout.startedAt),
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        fontSize = 11.sp
                    )
                }
                Column(
                    horizontalAlignment = Alignment.End,
                    verticalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        workout.caloriesKcal?.takeIf { it > 0 }?.let { k ->
                            HomeFeedPill(
                                text = "${k.roundToInt()} 🔥",
                                tint = tint
                            )
                        }
                        workout.score?.let { s ->
                            HomeFeedPill(
                                text = "⭐️ ${s.roundToInt()}",
                                tint = tint
                            )
                        }
                    }
                }
            }
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween,
                modifier = Modifier.fillMaxWidth()
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(4.dp),
                    modifier = Modifier
                        .clip(RoundedCornerShape(50))
                        .background(tint.copy(alpha = 0.18f))
                        .border(0.6.dp, Color.White.copy(alpha = 0.12f), RoundedCornerShape(50))
                        .padding(horizontal = 6.dp, vertical = 3.dp)
                ) {
                    Text(
                        text = workoutKindLabel(workout.kind).replaceFirstChar { it.titlecase() },
                        style = MaterialTheme.typography.labelSmall,
                        fontWeight = FontWeight.SemiBold
                    )
                    when (kindKey) {
                        "sport" -> {
                            val icon = sportIconEmoji(workout.sportName)
                            if (icon.isNotEmpty()) Text(text = icon, style = MaterialTheme.typography.labelSmall)
                        }
                        "cardio" -> {
                            val icon = cardioIconEmoji(workout.cardioActivityCode)
                            if (icon.isNotEmpty()) Text(text = icon, style = MaterialTheme.typography.labelSmall)
                        }
                        "strength" -> Text("🏋️‍♂️", style = MaterialTheme.typography.labelSmall)
                    }
                }
                Spacer(Modifier.weight(1f))
                HomeLikesPill(
                    likeCount = workout.likeCount,
                    isLiked = workout.isLikedByMe
                )
                if (planned) {
                    Row(
                        horizontalArrangement = Arrangement.spacedBy(4.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        modifier = Modifier
                            .padding(start = 8.dp)
                            .clip(RoundedCornerShape(50))
                            .background(Color(0xFFFFC107).copy(alpha = 0.22f))
                            .border(0.6.dp, Color.White.copy(alpha = 0.12f), RoundedCornerShape(50))
                            .padding(horizontal = 6.dp, vertical = 3.dp)
                    ) {
                        Icon(
                            imageVector = Icons.Filled.ModeEdit,
                            contentDescription = null,
                            modifier = Modifier.size(14.dp)
                        )
                        Text(
                            text = stringResource(R.string.home_workout_draft_badge),
                            style = MaterialTheme.typography.labelSmall,
                            fontWeight = FontWeight.SemiBold
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun HomeFeedPill(text: String, tint: Color) {
    Box(
        modifier = Modifier
            .clip(RoundedCornerShape(50))
            .background(
                brush = Brush.horizontalGradient(
                    listOf(
                        MaterialTheme.colorScheme.surface.copy(alpha = 0.88f),
                        tint.copy(alpha = 0.14f)
                    )
                )
            )
            .border(0.6.dp, Color.White.copy(alpha = 0.18f), RoundedCornerShape(50))
            .padding(vertical = 6.dp, horizontal = 10.dp)
    ) {
        Text(
            text = text,
            style = MaterialTheme.typography.bodySmall,
            fontWeight = FontWeight.SemiBold
        )
    }
}

@Composable
private fun HomeLikesPill(likeCount: Int, isLiked: Boolean) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        modifier = Modifier
            .clip(RoundedCornerShape(50))
            .background(Color.White.copy(alpha = 0.12f))
            .border(0.6.dp, Color.White.copy(alpha = 0.18f), RoundedCornerShape(50))
            .padding(vertical = 6.dp, horizontal = 10.dp)
    ) {
        Icon(
            imageVector = if (isLiked) Icons.Filled.Favorite else Icons.Filled.FavoriteBorder,
            contentDescription = null,
            modifier = Modifier.size(18.dp),
            tint = if (isLiked) Color(0xFFE53935) else MaterialTheme.colorScheme.onSurfaceVariant
        )
        Text(
            text = "$likeCount",
            style = MaterialTheme.typography.bodySmall,
            fontWeight = FontWeight.SemiBold
        )
    }
}

private fun sportIconEmoji(sport: String?): String {
    if (sport.isNullOrBlank()) return ""
    return when (sport.lowercase()) {
        "padel", "tennis", "squash", "badminton", "table_tennis" -> "🎾"
        "football" -> "⚽️"
        "basketball" -> "🏀"
        "volleyball" -> "🏐"
        "running" -> "🏃‍♂️"
        "cycling" -> "🚴‍♂️"
        "rugby" -> "🏉"
        "hockey", "field_hockey" -> "🏑"
        "ice_hockey" -> "🏒"
        "handball" -> "🤾‍♂️"
        "hyrox" -> "🔥"
        else -> ""
    }
}

private fun cardioIconEmoji(activity: String?): String {
    if (activity.isNullOrBlank()) return "❤️‍🔥"
    return when (activity.lowercase()) {
        "run", "outdoor_run", "trail_run" -> "🏃‍♂️"
        "treadmill" -> "🏃‍♀️"
        "walk", "hike" -> "🚶‍♂️"
        "cycling", "road_cycling" -> "🚴‍♂️"
        "indoor_cycling", "spinning" -> "🚲"
        "rowerg", "rowing" -> "🚣‍♂️"
        "ski_erg" -> "⛷️"
        "elliptical" -> "🌀"
        "stairs", "stairmaster" -> "🪜"
        "swim_pool" -> "🏊‍♂️"
        "swim_open_water" -> "🌊"
        else -> "❤️‍🔥"
    }
}

private fun workoutKindTintForFeed(kind: String?): Color = when (kind?.lowercase()) {
    "strength" -> Color(0xFF009E45)
    "cardio" -> Color(0xFF0061D1)
    "sport" -> Color(0xFFE07000)
    else -> Color(0xFF596673)
}
