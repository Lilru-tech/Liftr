package com.lilru.liftr.ui.profile

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.ui.Alignment
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Card
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.lilru.liftr.R
import com.lilru.liftr.ui.components.LiftrAvatar
import com.lilru.liftr.ui.components.LiftrBackTopBar
import io.github.jan.supabase.SupabaseClient

enum class FollowListMode { FOLLOWERS, FOLLOWING }

@Composable
fun FollowersListScreen(
    supabase: SupabaseClient,
    userId: String,
    mode: FollowListMode,
    onBack: () -> Unit,
    modifier: Modifier = Modifier
) {
    val vm: FollowersListViewModel = viewModel(
        key = "follow-list-$userId-$mode",
        factory = FollowersListViewModelFactory(supabase, userId, mode)
    )
    val ui by vm.uiState.collectAsStateWithLifecycle()
    var selectedProfile by rememberSaveable { mutableStateOf<String?>(null) }

    if (selectedProfile != null) {
        ProfileTabScreen(
            supabase = supabase,
            onSignOut = {},
            targetUserId = selectedProfile,
            showSignOutButton = false,
            onBack = { selectedProfile = null },
            modifier = modifier
        )
        return
    }

    Column(
        modifier = modifier
            .fillMaxSize()
            .statusBarsPadding()
            .padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        LiftrBackTopBar(onBack = onBack)

        Text(
            text = if (mode == FollowListMode.FOLLOWERS) {
                stringResource(R.string.profile_followers)
            } else {
                stringResource(R.string.profile_following)
            },
            style = MaterialTheme.typography.titleMedium
        )

        OutlinedTextField(
            value = ui.query,
            onValueChange = vm::onQueryChanged,
            label = { Text(stringResource(R.string.profile_connections_search)) },
            singleLine = true,
            modifier = Modifier.fillMaxWidth()
        )

        if (ui.loading) {
            Text(stringResource(R.string.profile_loading))
        }
        if (ui.error != null) {
            Text(
                text = ui.error ?: "",
                color = MaterialTheme.colorScheme.error
            )
        }
        if (!ui.loading && ui.filtered.isEmpty()) {
            Text(stringResource(R.string.profile_connections_empty))
        }

        LazyColumn(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            items(ui.filtered, key = { it.userId }) { u ->
                Card(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable { selectedProfile = u.userId }
                ) {
                    Row(
                        modifier = Modifier.padding(12.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(12.dp)
                    ) {
                        LiftrAvatar(
                            imageUrl = u.avatarUrl,
                            displayName = u.username,
                            size = 44.dp
                        )
                        Column(
                            modifier = Modifier.weight(1f),
                            verticalArrangement = Arrangement.spacedBy(4.dp)
                        ) {
                            Text(
                                text = u.username?.let { "@$it" } ?: "@user",
                                style = MaterialTheme.typography.titleSmall,
                                maxLines = 1
                            )
                        }
                        if (ui.meUserId != null && ui.meUserId != u.userId) {
                            OutlinedButton(
                                onClick = { vm.toggleFollow(u.userId) },
                                enabled = !ui.followBusyIds.contains(u.userId)
                            ) {
                                Text(
                                    if (ui.followBusyIds.contains(u.userId)) {
                                        stringResource(R.string.profile_follow_busy)
                                    } else if (u.isFollowedByMe) {
                                        stringResource(R.string.profile_unfollow)
                                    } else {
                                        stringResource(R.string.profile_follow)
                                    }
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}
