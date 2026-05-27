package com.lilru.liftr.ui.profile

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.lilru.liftr.R
import com.lilru.liftr.data.BackendContracts
import com.lilru.liftr.ui.components.LiftrBackTopBar
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.postgrest.from
import kotlinx.coroutines.launch
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

@Serializable
private data class NotificationSettingsRow(
    @SerialName("user_id") val userId: String,
    @SerialName("push_enabled") val pushEnabled: Boolean,
    @SerialName("push_new_message") val pushNewMessage: Boolean,
    @SerialName("push_new_follower") val pushNewFollower: Boolean,
    @SerialName("push_workout_like") val pushWorkoutLike: Boolean,
    @SerialName("push_workout_comment") val pushWorkoutComment: Boolean,
    @SerialName("push_comment_like") val pushCommentLike: Boolean,
    @SerialName("push_comment_reply") val pushCommentReply: Boolean,
    @SerialName("push_comment_mention") val pushCommentMention: Boolean = true,
    @SerialName("push_added_as_participant") val pushAddedAsParticipant: Boolean,
    @SerialName("push_achievement_unlocked") val pushAchievementUnlocked: Boolean,
    @SerialName("push_goal_completed") val pushGoalCompleted: Boolean,
    @SerialName("push_goal_almost_done") val pushGoalAlmostDone: Boolean,
    @SerialName("push_competition_invite") val pushCompetitionInvite: Boolean,
    @SerialName("push_competition_accepted") val pushCompetitionAccepted: Boolean,
    @SerialName("push_competition_declined") val pushCompetitionDeclined: Boolean,
    @SerialName("push_competition_cancelled") val pushCompetitionCancelled: Boolean,
    @SerialName("push_competition_expired") val pushCompetitionExpired: Boolean,
    @SerialName("push_competition_result_win") val pushCompetitionResultWin: Boolean,
    @SerialName("push_competition_result_lose") val pushCompetitionResultLose: Boolean,
    @SerialName("push_competition_workout_pending_review") val pushCompetitionWorkoutPendingReview: Boolean,
    @SerialName("push_competition_workout_accepted") val pushCompetitionWorkoutAccepted: Boolean,
    @SerialName("push_competition_workout_rejected") val pushCompetitionWorkoutRejected: Boolean,
    @SerialName("push_segment_you_are_first") val pushSegmentYouAreFirst: Boolean,
    @SerialName("push_segment_lost_first") val pushSegmentLostFirst: Boolean,
    @SerialName("push_territory_capture_from_user") val pushTerritoryCaptureFromUser: Boolean,
    @SerialName("push_territory_lost_to_user") val pushTerritoryLostToUser: Boolean,
    @SerialName("push_challenge_won") val pushChallengeWon: Boolean,
    @SerialName("push_challenge_won_weekly") val pushChallengeWonWeekly: Boolean,
    @SerialName("push_workout_kind_inactive") val pushWorkoutKindInactive: Boolean
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun NotificationSettingsScreen(
    supabase: SupabaseClient,
    onBack: () -> Unit,
    modifier: Modifier = Modifier
) {
    val scope = rememberCoroutineScope()
    val meId = supabase.auth.currentUserOrNull()?.id

    var loading by remember { mutableStateOf(true) }
    var saving by remember { mutableStateOf(false) }
    var err by remember { mutableStateOf<String?>(null) }
    var row by remember { mutableStateOf<NotificationSettingsRow?>(null) }

    suspend fun load() {
        if (meId == null) {
            err = "Not signed in"
            loading = false
            return
        }
        loading = true
        err = null
        runCatching {
            supabase.from(BackendContracts.Tables.USER_NOTIFICATION_SETTINGS)
                .select {
                    filter { eq("user_id", meId) }
                    limit(1)
                }
                .decodeList<NotificationSettingsRow>()
                .firstOrNull()
        }.onSuccess {
            if (it == null) {
                runCatching {
                    supabase.from(BackendContracts.Tables.USER_NOTIFICATION_SETTINGS).insert(
                        buildJsonObject { put("user_id", meId) }
                    )
                }
                load()
            } else {
                row = it
            }
        }.onFailure {
            err = it.message
        }
        loading = false
    }

    fun save(update: Map<String, Boolean>) {
        val uid = meId ?: return
        if (saving) return
        saving = true
        err = null
        scope.launch {
            runCatching {
                supabase.from(BackendContracts.Tables.USER_NOTIFICATION_SETTINGS).update(
                    buildJsonObject {
                        for ((k, v) in update) put(k, v)
                    }
                ) {
                    filter { eq("user_id", uid) }
                }
            }.onFailure {
                err = it.message
            }
            saving = false
            load()
        }
    }

    LaunchedEffect(meId) { load() }

    Column(modifier = modifier.fillMaxSize()) {
        LiftrBackTopBar(onBack = onBack, title = stringResource(R.string.notifications_settings_title))
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 12.dp, vertical = 10.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            if (loading) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.Center
                ) {
                    CircularProgressIndicator()
                }
            }
            err?.let {
                Text(it, color = MaterialTheme.colorScheme.error)
            }
            val r = row
            if (!loading && r != null) {
                SettingsCard(
                    title = stringResource(R.string.notifications_settings_master),
                    subtitle = stringResource(R.string.notifications_settings_master_sub),
                    checked = r.pushEnabled,
                    enabled = !saving,
                    onToggle = { v -> save(mapOf("push_enabled" to v)) }
                )

                val enabled = r.pushEnabled && !saving

                SectionHeader(stringResource(R.string.notifications_settings_messages))
                SettingsCard(
                    title = stringResource(R.string.notifications_settings_dm),
                    subtitle = null,
                    checked = r.pushNewMessage,
                    enabled = enabled,
                    onToggle = { v -> save(mapOf("push_new_message" to v)) }
                )

                SectionHeader(stringResource(R.string.notifications_settings_social))
                SettingsCard(
                    title = stringResource(R.string.notifications_settings_followers),
                    subtitle = null,
                    checked = r.pushNewFollower,
                    enabled = enabled,
                    onToggle = { v -> save(mapOf("push_new_follower" to v)) }
                )

                SectionHeader(stringResource(R.string.notifications_settings_workouts))
                SettingsCard(
                    title = stringResource(R.string.notifications_settings_workout_likes),
                    subtitle = null,
                    checked = r.pushWorkoutLike,
                    enabled = enabled,
                    onToggle = { v -> save(mapOf("push_workout_like" to v)) }
                )
                SettingsCard(
                    title = stringResource(R.string.notifications_settings_workout_comments),
                    subtitle = null,
                    checked = r.pushWorkoutComment,
                    enabled = enabled,
                    onToggle = { v -> save(mapOf("push_workout_comment" to v)) }
                )
                SettingsCard(
                    title = stringResource(R.string.notifications_settings_comment_likes),
                    subtitle = null,
                    checked = r.pushCommentLike,
                    enabled = enabled,
                    onToggle = { v -> save(mapOf("push_comment_like" to v)) }
                )
                SettingsCard(
                    title = stringResource(R.string.notifications_settings_comment_replies),
                    subtitle = null,
                    checked = r.pushCommentReply,
                    enabled = enabled,
                    onToggle = { v -> save(mapOf("push_comment_reply" to v)) }
                )
                SettingsCard(
                    title = stringResource(R.string.notifications_settings_comment_mentions),
                    subtitle = null,
                    checked = r.pushCommentMention,
                    enabled = enabled,
                    onToggle = { v -> save(mapOf("push_comment_mention" to v)) }
                )
                SettingsCard(
                    title = stringResource(R.string.notifications_settings_added_participant),
                    subtitle = null,
                    checked = r.pushAddedAsParticipant,
                    enabled = enabled,
                    onToggle = { v -> save(mapOf("push_added_as_participant" to v)) }
                )

                SectionHeader(stringResource(R.string.notifications_settings_ach_goals))
                SettingsCard(
                    title = stringResource(R.string.notifications_settings_achievements),
                    subtitle = null,
                    checked = r.pushAchievementUnlocked,
                    enabled = enabled,
                    onToggle = { v -> save(mapOf("push_achievement_unlocked" to v)) }
                )
                SettingsCard(
                    title = stringResource(R.string.notifications_settings_goal_completed),
                    subtitle = null,
                    checked = r.pushGoalCompleted,
                    enabled = enabled,
                    onToggle = { v -> save(mapOf("push_goal_completed" to v)) }
                )
                SettingsCard(
                    title = stringResource(R.string.notifications_settings_goal_almost),
                    subtitle = null,
                    checked = r.pushGoalAlmostDone,
                    enabled = enabled,
                    onToggle = { v -> save(mapOf("push_goal_almost_done" to v)) }
                )

                SectionHeader(stringResource(R.string.notifications_settings_competitions))
                SettingsCard(
                    title = stringResource(R.string.notifications_settings_comp_invites),
                    subtitle = null,
                    checked = r.pushCompetitionInvite,
                    enabled = enabled,
                    onToggle = { v -> save(mapOf("push_competition_invite" to v)) }
                )
                SettingsCard(
                    title = stringResource(R.string.notifications_settings_comp_accepted),
                    subtitle = null,
                    checked = r.pushCompetitionAccepted,
                    enabled = enabled,
                    onToggle = { v -> save(mapOf("push_competition_accepted" to v)) }
                )
                SettingsCard(
                    title = stringResource(R.string.notifications_settings_comp_declined),
                    subtitle = null,
                    checked = r.pushCompetitionDeclined,
                    enabled = enabled,
                    onToggle = { v -> save(mapOf("push_competition_declined" to v)) }
                )
                SettingsCard(
                    title = stringResource(R.string.notifications_settings_comp_cancelled),
                    subtitle = null,
                    checked = r.pushCompetitionCancelled,
                    enabled = enabled,
                    onToggle = { v -> save(mapOf("push_competition_cancelled" to v)) }
                )
                SettingsCard(
                    title = stringResource(R.string.notifications_settings_comp_expired),
                    subtitle = null,
                    checked = r.pushCompetitionExpired,
                    enabled = enabled,
                    onToggle = { v -> save(mapOf("push_competition_expired" to v)) }
                )
                SettingsCard(
                    title = stringResource(R.string.notifications_settings_comp_win),
                    subtitle = null,
                    checked = r.pushCompetitionResultWin,
                    enabled = enabled,
                    onToggle = { v -> save(mapOf("push_competition_result_win" to v)) }
                )
                SettingsCard(
                    title = stringResource(R.string.notifications_settings_comp_lose),
                    subtitle = null,
                    checked = r.pushCompetitionResultLose,
                    enabled = enabled,
                    onToggle = { v -> save(mapOf("push_competition_result_lose" to v)) }
                )
                SettingsCard(
                    title = stringResource(R.string.notifications_settings_comp_pending_review),
                    subtitle = null,
                    checked = r.pushCompetitionWorkoutPendingReview,
                    enabled = enabled,
                    onToggle = { v -> save(mapOf("push_competition_workout_pending_review" to v)) }
                )
                SettingsCard(
                    title = stringResource(R.string.notifications_settings_comp_workout_accepted),
                    subtitle = null,
                    checked = r.pushCompetitionWorkoutAccepted,
                    enabled = enabled,
                    onToggle = { v -> save(mapOf("push_competition_workout_accepted" to v)) }
                )
                SettingsCard(
                    title = stringResource(R.string.notifications_settings_comp_workout_rejected),
                    subtitle = null,
                    checked = r.pushCompetitionWorkoutRejected,
                    enabled = enabled,
                    onToggle = { v -> save(mapOf("push_competition_workout_rejected" to v)) }
                )

                SectionHeader(stringResource(R.string.notifications_settings_segments_challenges))
                SettingsCard(
                    title = stringResource(R.string.notifications_settings_segment_first),
                    subtitle = null,
                    checked = r.pushSegmentYouAreFirst,
                    enabled = enabled,
                    onToggle = { v -> save(mapOf("push_segment_you_are_first" to v)) }
                )
                SettingsCard(
                    title = stringResource(R.string.notifications_settings_segment_lost),
                    subtitle = null,
                    checked = r.pushSegmentLostFirst,
                    enabled = enabled,
                    onToggle = { v -> save(mapOf("push_segment_lost_first" to v)) }
                )
                SettingsCard(
                    title = stringResource(R.string.notifications_settings_territory_capture),
                    subtitle = null,
                    checked = r.pushTerritoryCaptureFromUser,
                    enabled = enabled,
                    onToggle = { v -> save(mapOf("push_territory_capture_from_user" to v)) }
                )
                SettingsCard(
                    title = stringResource(R.string.notifications_settings_territory_lost),
                    subtitle = null,
                    checked = r.pushTerritoryLostToUser,
                    enabled = enabled,
                    onToggle = { v -> save(mapOf("push_territory_lost_to_user" to v)) }
                )
                SettingsCard(
                    title = stringResource(R.string.notifications_settings_challenge_won),
                    subtitle = null,
                    checked = r.pushChallengeWon,
                    enabled = enabled,
                    onToggle = { v -> save(mapOf("push_challenge_won" to v)) }
                )
                SettingsCard(
                    title = stringResource(R.string.notifications_settings_challenge_won_weekly),
                    subtitle = null,
                    checked = r.pushChallengeWonWeekly,
                    enabled = enabled,
                    onToggle = { v -> save(mapOf("push_challenge_won_weekly" to v)) }
                )

                SectionHeader(stringResource(R.string.notifications_settings_reminders))
                SettingsCard(
                    title = stringResource(R.string.notifications_settings_workout_reminders),
                    subtitle = null,
                    checked = r.pushWorkoutKindInactive,
                    enabled = enabled,
                    onToggle = { v -> save(mapOf("push_workout_kind_inactive" to v)) }
                )
            }
        }
    }
}

@Composable
private fun SectionHeader(text: String) {
    Text(
        text = text,
        style = MaterialTheme.typography.titleSmall,
        fontWeight = FontWeight.SemiBold,
        modifier = Modifier.padding(top = 6.dp, bottom = 2.dp)
    )
}

@Composable
private fun SettingsCard(
    title: String,
    subtitle: String?,
    checked: Boolean,
    enabled: Boolean,
    onToggle: (Boolean) -> Unit
) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 14.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(title, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.SemiBold)
                if (subtitle != null) {
                    Spacer(Modifier.padding(top = 2.dp))
                    Text(subtitle, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            Switch(checked = checked, onCheckedChange = onToggle, enabled = enabled)
        }
    }
}

