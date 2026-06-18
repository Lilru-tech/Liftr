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
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
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
    @SerialName("push_workout_kind_inactive") val pushWorkoutKindInactive: Boolean,
    @SerialName("push_meal_plan_invite") val pushMealPlanInvite: Boolean = true,
    @SerialName("push_apple_health_cardio_imported") val pushAppleHealthCardioImported: Boolean = true,
    @SerialName("push_pet_hatched") val pushPetHatched: Boolean = true,
    @SerialName("push_pet_combat_challenged") val pushPetCombatChallenged: Boolean = true
)

private data class NotificationSettingItem(
    val sectionRes: Int,
    val titleRes: Int,
    val column: String,
    val value: (NotificationSettingsRow) -> Boolean
)

private data class ResolvedNotificationSettingItem(
    val item: NotificationSettingItem,
    val section: String,
    val title: String
)

private val notificationSettingItems = listOf(
    NotificationSettingItem(R.string.notifications_settings_messages, R.string.notifications_settings_dm, "push_new_message") { it.pushNewMessage },
    NotificationSettingItem(R.string.notifications_settings_social, R.string.notifications_settings_followers, "push_new_follower") { it.pushNewFollower },
    NotificationSettingItem(R.string.notifications_settings_workouts, R.string.notifications_settings_workout_likes, "push_workout_like") { it.pushWorkoutLike },
    NotificationSettingItem(R.string.notifications_settings_workouts, R.string.notifications_settings_workout_comments, "push_workout_comment") { it.pushWorkoutComment },
    NotificationSettingItem(R.string.notifications_settings_workouts, R.string.notifications_settings_comment_likes, "push_comment_like") { it.pushCommentLike },
    NotificationSettingItem(R.string.notifications_settings_workouts, R.string.notifications_settings_comment_replies, "push_comment_reply") { it.pushCommentReply },
    NotificationSettingItem(R.string.notifications_settings_workouts, R.string.notifications_settings_comment_mentions, "push_comment_mention") { it.pushCommentMention },
    NotificationSettingItem(R.string.notifications_settings_workouts, R.string.notifications_settings_added_participant, "push_added_as_participant") { it.pushAddedAsParticipant },
    NotificationSettingItem(R.string.notifications_settings_ach_goals, R.string.notifications_settings_achievements, "push_achievement_unlocked") { it.pushAchievementUnlocked },
    NotificationSettingItem(R.string.notifications_settings_ach_goals, R.string.notifications_settings_goal_completed, "push_goal_completed") { it.pushGoalCompleted },
    NotificationSettingItem(R.string.notifications_settings_ach_goals, R.string.notifications_settings_goal_almost, "push_goal_almost_done") { it.pushGoalAlmostDone },
    NotificationSettingItem(R.string.notifications_settings_competitions, R.string.notifications_settings_comp_invites, "push_competition_invite") { it.pushCompetitionInvite },
    NotificationSettingItem(R.string.notifications_settings_competitions, R.string.notifications_settings_comp_accepted, "push_competition_accepted") { it.pushCompetitionAccepted },
    NotificationSettingItem(R.string.notifications_settings_competitions, R.string.notifications_settings_comp_declined, "push_competition_declined") { it.pushCompetitionDeclined },
    NotificationSettingItem(R.string.notifications_settings_competitions, R.string.notifications_settings_comp_cancelled, "push_competition_cancelled") { it.pushCompetitionCancelled },
    NotificationSettingItem(R.string.notifications_settings_competitions, R.string.notifications_settings_comp_expired, "push_competition_expired") { it.pushCompetitionExpired },
    NotificationSettingItem(R.string.notifications_settings_competitions, R.string.notifications_settings_comp_win, "push_competition_result_win") { it.pushCompetitionResultWin },
    NotificationSettingItem(R.string.notifications_settings_competitions, R.string.notifications_settings_comp_lose, "push_competition_result_lose") { it.pushCompetitionResultLose },
    NotificationSettingItem(R.string.notifications_settings_competitions, R.string.notifications_settings_comp_pending_review, "push_competition_workout_pending_review") { it.pushCompetitionWorkoutPendingReview },
    NotificationSettingItem(R.string.notifications_settings_competitions, R.string.notifications_settings_comp_workout_accepted, "push_competition_workout_accepted") { it.pushCompetitionWorkoutAccepted },
    NotificationSettingItem(R.string.notifications_settings_competitions, R.string.notifications_settings_comp_workout_rejected, "push_competition_workout_rejected") { it.pushCompetitionWorkoutRejected },
    NotificationSettingItem(R.string.notifications_settings_segments_challenges, R.string.notifications_settings_segment_first, "push_segment_you_are_first") { it.pushSegmentYouAreFirst },
    NotificationSettingItem(R.string.notifications_settings_segments_challenges, R.string.notifications_settings_segment_lost, "push_segment_lost_first") { it.pushSegmentLostFirst },
    NotificationSettingItem(R.string.notifications_settings_segments_challenges, R.string.notifications_settings_territory_capture, "push_territory_capture_from_user") { it.pushTerritoryCaptureFromUser },
    NotificationSettingItem(R.string.notifications_settings_segments_challenges, R.string.notifications_settings_territory_lost, "push_territory_lost_to_user") { it.pushTerritoryLostToUser },
    NotificationSettingItem(R.string.notifications_settings_segments_challenges, R.string.notifications_settings_challenge_won, "push_challenge_won") { it.pushChallengeWon },
    NotificationSettingItem(R.string.notifications_settings_segments_challenges, R.string.notifications_settings_challenge_won_weekly, "push_challenge_won_weekly") { it.pushChallengeWonWeekly },
    NotificationSettingItem(R.string.notifications_settings_reminders, R.string.notifications_settings_workout_reminders, "push_workout_kind_inactive") { it.pushWorkoutKindInactive },
    NotificationSettingItem(R.string.notifications_settings_nutrition, R.string.notifications_settings_meal_plan_invites, "push_meal_plan_invite") { it.pushMealPlanInvite },
    NotificationSettingItem(R.string.notifications_settings_pets, R.string.notifications_settings_pet_hatched, "push_pet_hatched") { it.pushPetHatched },
    NotificationSettingItem(R.string.notifications_settings_pets, R.string.notifications_settings_pet_combat_challenged, "push_pet_combat_challenged") { it.pushPetCombatChallenged },
    NotificationSettingItem(R.string.notifications_settings_apple_health, R.string.notifications_settings_apple_health_cardio, "push_apple_health_cardio_imported") { it.pushAppleHealthCardioImported }
)

private val notificationSectionOrder = listOf(
    R.string.notifications_settings_messages,
    R.string.notifications_settings_social,
    R.string.notifications_settings_workouts,
    R.string.notifications_settings_ach_goals,
    R.string.notifications_settings_competitions,
    R.string.notifications_settings_segments_challenges,
    R.string.notifications_settings_reminders,
    R.string.notifications_settings_nutrition,
    R.string.notifications_settings_pets,
    R.string.notifications_settings_apple_health
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
    var searchQuery by remember { mutableStateOf("") }

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

                OutlinedTextField(
                    value = searchQuery,
                    onValueChange = { searchQuery = it },
                    modifier = Modifier.fillMaxWidth(),
                    singleLine = true,
                    placeholder = { Text(stringResource(R.string.notifications_settings_search_hint)) },
                    leadingIcon = {
                        Icon(Icons.Default.Search, contentDescription = null)
                    },
                    trailingIcon = {
                        if (searchQuery.isNotEmpty()) {
                            IconButton(onClick = { searchQuery = "" }) {
                                Icon(Icons.Default.Close, contentDescription = null)
                            }
                        }
                    }
                )

                val enabled = r.pushEnabled && !saving
                val normalizedQuery = searchQuery.trim()
                val resolvedItems = notificationSettingItems.map { item ->
                    ResolvedNotificationSettingItem(
                        item = item,
                        section = stringResource(item.sectionRes),
                        title = stringResource(item.titleRes)
                    )
                }
                val filteredItems = if (normalizedQuery.isEmpty()) {
                    resolvedItems
                } else {
                    resolvedItems.filter {
                        it.section.contains(normalizedQuery, ignoreCase = true)
                            || it.title.contains(normalizedQuery, ignoreCase = true)
                    }
                }

                if (filteredItems.isEmpty()) {
                    Text(
                        stringResource(R.string.notifications_settings_search_empty),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(vertical = 8.dp)
                    )
                } else {
                    val grouped = filteredItems.groupBy { it.item.sectionRes }
                    notificationSectionOrder.forEach { sectionRes ->
                        val sectionItems = grouped[sectionRes].orEmpty()
                        if (sectionItems.isEmpty()) return@forEach
                        SectionHeader(stringResource(sectionRes))
                        sectionItems.forEach { resolved ->
                            val item = resolved.item
                            SettingsCard(
                                title = resolved.title,
                                subtitle = null,
                                checked = item.value(r),
                                enabled = enabled,
                                onToggle = { v -> save(mapOf(item.column to v)) }
                            )
                        }
                    }
                }
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
