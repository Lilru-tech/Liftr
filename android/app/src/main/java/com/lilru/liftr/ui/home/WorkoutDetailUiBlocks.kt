package com.lilru.liftr.ui.home

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.FavoriteBorder
import androidx.compose.material.icons.filled.Groups
import androidx.compose.material.icons.filled.LocalFireDepartment
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.outlined.ChatBubbleOutline
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.lilru.liftr.R
import com.lilru.liftr.domain.strengthSetRowsWithMultiplicities
import com.lilru.liftr.domain.strengthSetSummaryWithMultiplier
import com.lilru.liftr.prefs.LiftrPreferences
import com.lilru.liftr.ui.components.LiftrAvatar
import com.lilru.liftr.ui.theme.liftrAppBackgroundGradient
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Locale
import kotlin.math.roundToInt

/** Paneles de campos sobre el gradiente (paridad iOS `.ultraThinMaterial` / gris de tarjeta). */
@Composable
fun workoutDetailFieldPanelColor(): Color =
    MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.72f)

/** Filas anidadas dentro de un panel (stats, series, etc.). */
@Composable
fun workoutDetailInsetFieldColor(): Color =
    MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.52f)

/** Tema de fondo del detalle (paridad con iOS [WorkoutDetailView] `.gradientBG()`). */
@Composable
fun workoutDetailScreenGradientModifier(): Modifier {
    val ctx = LocalContext.current
    return Modifier.liftrAppBackgroundGradient(LiftrPreferences.backgroundTheme(ctx))
}

/** Paridad con iOS [WorkoutDetailView.dateRange]. */
fun workoutDetailDateRangeLabel(startedAt: String?, endedAt: String?): String {
    val fmt = DateTimeFormatter.ofLocalizedDateTime(FormatStyle.MEDIUM, FormatStyle.SHORT)
        .withZone(ZoneId.systemDefault())
        .withLocale(Locale.getDefault())
    val s = startedAt?.trim()?.takeIf { it.isNotEmpty() }?.let {
        runCatching { fmt.format(Instant.parse(it)) }.getOrNull()
    } ?: return "—"
    val e = endedAt?.trim()?.takeIf { it.isNotEmpty() }?.let {
        runCatching { fmt.format(Instant.parse(it)) }.getOrNull()
    }
    return if (e != null) "$s – $e" else s
}

@Composable
fun workoutKindTintForDetail(kind: String?): Color = when (kind?.lowercase()) {
    "strength" -> Color(0xFF009E45)
    "cardio" -> Color(0xFF0061D1)
    "sport" -> Color(0xFFE07000)
    else -> Color(0xFF596673)
}

@Composable
fun WorkoutDetailHeaderCard(
    workout: WorkoutDetailRow,
    ownerUsername: String?,
    ownerAvatarUrl: String?,
    totalScore: Double?,
    caloriesKcal: Double?,
    participantsCount: Int,
    onOwnerClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    val tint = workoutKindTintForDetail(workout.kind)
    val shape = RoundedCornerShape(16.dp)
    val titleText = workout.title?.trim()?.takeIf { it.isNotEmpty() }
        ?: workout.kind?.replaceFirstChar { c ->
            if (c.isLowerCase()) c.titlecase(Locale.getDefault()) else c.toString()
        } ?: stringResource(R.string.home_untitled_workout)
    val kcal = caloriesKcal ?: 0.0
    Box(
        modifier = modifier
            .fillMaxWidth()
            .clip(shape)
            .background(
                brush = Brush.linearGradient(
                    listOf(tint.copy(alpha = 0.28f), tint.copy(alpha = 0.14f))
                )
            )
            .border(0.8.dp, Color.White.copy(alpha = 0.18f), shape)
            .padding(16.dp)
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(
                verticalAlignment = Alignment.Top,
                horizontalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                LiftrAvatar(
                    imageUrl = ownerAvatarUrl,
                    displayName = ownerUsername,
                    size = 44.dp
                )
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(
                        text = "@${ownerUsername?.takeIf { it.isNotBlank() } ?: "user"}",
                        style = MaterialTheme.typography.bodyMedium,
                        fontWeight = FontWeight.SemiBold,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.clickable(onClick = onOwnerClick)
                    )
                    Text(
                        text = titleText,
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold,
                        maxLines = 2
                    )
                }
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    if (kcal > 0) {
                        Surface(
                            shape = RoundedCornerShape(20.dp),
                            color = MaterialTheme.colorScheme.surface.copy(alpha = 0.85f)
                        ) {
                            Row(
                                modifier = Modifier.padding(horizontal = 10.dp, vertical = 6.dp),
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(4.dp)
                            ) {
                                Text(
                                    "${kcal.toInt()} kcal",
                                    style = MaterialTheme.typography.labelMedium,
                                    fontWeight = FontWeight.SemiBold
                                )
                                Icon(
                                    Icons.Filled.LocalFireDepartment,
                                    contentDescription = null,
                                    modifier = Modifier.size(16.dp),
                                    tint = Color(0xFFFF6B00)
                                )
                            }
                        }
                    }
                    totalScore?.let { sc ->
                        Surface(
                            shape = RoundedCornerShape(20.dp),
                            color = MaterialTheme.colorScheme.surface.copy(alpha = 0.85f)
                        ) {
                            Row(
                                modifier = Modifier.padding(horizontal = 10.dp, vertical = 6.dp),
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(4.dp)
                            ) {
                                Icon(
                                    Icons.Filled.Star,
                                    contentDescription = null,
                                    modifier = Modifier.size(16.dp),
                                    tint = Color(0xFFFFCC00)
                                )
                                Text(
                                    "${sc.roundToInt()}",
                                    style = MaterialTheme.typography.labelMedium,
                                    fontWeight = FontWeight.SemiBold
                                )
                            }
                        }
                    }
                }
            }
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                Text(
                    workoutDetailDateRangeLabel(workout.startedAt, workout.endedAt),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                workout.durationMin?.takeIf { it > 0 }?.let { dm ->
                    Text(
                        "• ${stringResource(R.string.workout_detail_header_min, dm)}",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                workout.perceivedIntensity?.trim()?.takeIf { it.isNotEmpty() }?.let { pi ->
                    Text(
                        "• ${pi.replaceFirstChar { c -> if (c.isLowerCase()) c.titlecase(Locale.getDefault()) else c.toString() }}",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                if (participantsCount > 0) {
                    Surface(
                        shape = CircleShape,
                        color = MaterialTheme.colorScheme.surface.copy(alpha = 0.75f)
                    ) {
                        Row(
                            Modifier.padding(horizontal = 8.dp, vertical = 2.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(6.dp)
                        ) {
                            Icon(
                                Icons.Filled.Groups,
                                contentDescription = null,
                                modifier = Modifier.size(14.dp)
                            )
                            Text(
                                "$participantsCount",
                                style = MaterialTheme.typography.labelSmall,
                                fontWeight = FontWeight.SemiBold
                            )
                        }
                    }
                }
                Spacer(Modifier.weight(1f))
                if (workout.state?.lowercase() == "planned") {
                    Surface(
                        shape = CircleShape,
                        color = Color(0xFFFFCC00).copy(alpha = 0.22f),
                        border = BorderStroke(0.5.dp, Color.White.copy(alpha = 0.12f))
                    ) {
                        Text(
                            stringResource(R.string.workout_detail_draft_badge),
                            modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp),
                            style = MaterialTheme.typography.labelSmall,
                            fontWeight = FontWeight.SemiBold,
                            fontSize = 11.sp
                        )
                    }
                }
            }
        }
    }
}

@Composable
fun WorkoutDetailStrengthReadonlySection(
    detail: StrengthReadonlyDetail?,
    modifier: Modifier = Modifier
) {
    val d = detail ?: return
    val shape = RoundedCornerShape(14.dp)
    Column(
        modifier = modifier
            .fillMaxWidth()
            .clip(shape)
            .background(workoutDetailFieldPanelColor())
            .border(0.8.dp, Color.White.copy(alpha = 0.18f), shape)
            .padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        Text(
            stringResource(R.string.workout_detail_strength_block_title),
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.SemiBold
        )
        if (d.exercises.isEmpty()) {
            Text(
                stringResource(R.string.workout_detail_strength_no_sets),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        } else {
            d.exercises.sortedBy { it.orderIndex }.forEach { ex ->
                Column(
                    Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(12.dp))
                        .background(workoutDetailInsetFieldColor())
                        .padding(12.dp),
                    verticalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    Text(ex.title, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold)
                    ex.notes?.let {
                        Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    if (ex.sets.isEmpty()) {
                        Text(
                            stringResource(R.string.workout_detail_strength_no_sets),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    } else {
                        val paired = strengthSetRowsWithMultiplicities(
                            rows = ex.sets,
                            orderIndex = { it.orderIndex },
                            id = { it.rowId },
                            setNumber = { it.setNumber }
                        )
                        paired.forEach { item ->
                            val s = item.row
                            val mult = item.multiplier
                            val dropSummary = if (s.weightSegments.size >= 2) {
                                s.weightSegments.joinToString(" → ") { seg ->
                                    "${seg.repsText.trim()}×${seg.weightText.trim().ifBlank { "0" }}"
                                }
                            } else {
                                null
                            }
                            val summaryBody = if (dropSummary != null) {
                                dropSummary
                            } else {
                                buildList {
                                    add("${s.reps ?: 0} reps")
                                    add("${String.format(Locale.US, "%.1f kg", s.weightKg ?: 0.0)}")
                                    s.rpe?.let { r ->
                                        add("RPE ${String.format(Locale.US, "%.1f", r)}")
                                    }
                                    s.restSec?.let { r -> add("Rest ${r}s") }
                                }.joinToString(" • ")
                            }
                            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                Text(
                                    "#${item.lineOrdinal}",
                                    style = MaterialTheme.typography.labelSmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    modifier = Modifier.padding(end = 4.dp)
                                )
                                Text(
                                    strengthSetSummaryWithMultiplier(summaryBody, mult),
                                    style = MaterialTheme.typography.bodySmall
                                )
                            }
                        }
                    }
                }
            }
        }
        d.totalVolumeKg?.let { v ->
            Text(
                stringResource(R.string.workout_detail_strength_total_volume, v),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(top = 4.dp)
            )
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun WorkoutDetailFeedbackRow(
    isLiked: Boolean,
    likeCount: Int,
    commentCount: Int,
    likeBusy: Boolean,
    onToggleLike: () -> Unit,
    onShowLikers: () -> Unit,
    onOpenComments: () -> Unit,
    modifier: Modifier = Modifier
) {
    val shape = RoundedCornerShape(14.dp)
    Column(
        modifier = modifier
            .fillMaxWidth()
            .clip(shape)
            .background(workoutDetailFieldPanelColor())
            .border(0.8.dp, Color.White.copy(alpha = 0.18f), shape)
            .padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        Text(
            stringResource(R.string.workout_detail_feedback_title),
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.SemiBold
        )
        Row(
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Surface(
                shape = CircleShape,
                color = MaterialTheme.colorScheme.surface.copy(alpha = 0.65f),
                border = BorderStroke(0.5.dp, Color.White.copy(alpha = 0.12f))
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Box(
                        modifier = Modifier
                            .combinedClickable(
                                enabled = !likeBusy,
                                onClick = onToggleLike,
                                onLongClick = onShowLikers
                            )
                            .padding(start = 12.dp, end = 10.dp, top = 8.dp, bottom = 8.dp)
                    ) {
                        Icon(
                            imageVector = if (isLiked) Icons.Filled.Favorite else Icons.Filled.FavoriteBorder,
                            contentDescription = null,
                            tint = if (isLiked) Color(0xFFE53935) else MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                    Box(
                        Modifier
                            .padding(vertical = 6.dp)
                            .size(width = 1.dp, height = 20.dp)
                            .background(MaterialTheme.colorScheme.outline.copy(alpha = 0.25f))
                    )
                    Box(
                        modifier = Modifier
                            .clickable(enabled = !likeBusy, onClick = onShowLikers)
                            .padding(start = 10.dp, end = 12.dp, top = 8.dp, bottom = 8.dp)
                    ) {
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(6.dp)
                        ) {
                            Icon(Icons.Filled.Groups, contentDescription = null)
                            Text("$likeCount", style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold)
                        }
                    }
                }
            }
            Surface(
                shape = RoundedCornerShape(20.dp),
                color = MaterialTheme.colorScheme.surface.copy(alpha = 0.65f),
                modifier = Modifier.clickable(onClick = onOpenComments)
            ) {
                Row(
                    Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    Icon(
                        Icons.Outlined.ChatBubbleOutline,
                        contentDescription = null,
                        modifier = Modifier.size(18.dp)
                    )
                    Text(
                        stringResource(R.string.workout_detail_open_comments),
                        style = MaterialTheme.typography.bodyMedium,
                        fontWeight = FontWeight.SemiBold
                    )
                    Text(
                        "$commentCount",
                        style = MaterialTheme.typography.bodyMedium,
                        fontWeight = FontWeight.SemiBold,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
            Spacer(Modifier.weight(1f))
        }
    }
}

@Composable
fun WorkoutDetailParticipantsCard(
    participants: List<ProfileLite>,
    onOpenProfile: (String) -> Unit,
    modifier: Modifier = Modifier
) {
    if (participants.isEmpty()) return
    val shape = RoundedCornerShape(14.dp)
    Column(
        modifier = modifier
            .fillMaxWidth()
            .clip(shape)
            .background(workoutDetailFieldPanelColor())
            .border(0.8.dp, Color.White.copy(alpha = 0.18f), shape)
            .padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Text(
            stringResource(R.string.home_detail_participants_title),
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.SemiBold
        )
        participants.forEach { p ->
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable { onOpenProfile(p.userId) }
                    .padding(vertical = 4.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                LiftrAvatar(
                    imageUrl = p.avatarUrl,
                    displayName = p.username,
                    size = 28.dp,
                    modifier = Modifier.clip(RoundedCornerShape(6.dp))
                )
                Text(
                    "@${p.username?.takeIf { it.isNotBlank() } ?: "user"}",
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 1
                )
            }
        }
    }
}

@Composable
fun WorkoutDetailNotesCard(
    notes: String,
    modifier: Modifier = Modifier
) {
    val shape = RoundedCornerShape(14.dp)
    Column(
        modifier = modifier
            .fillMaxWidth()
            .clip(shape)
            .background(workoutDetailFieldPanelColor())
            .border(0.8.dp, Color.White.copy(alpha = 0.18f), shape)
            .padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Text(
            stringResource(R.string.home_detail_notes_title),
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.SemiBold
        )
        Text(
            notes,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}
