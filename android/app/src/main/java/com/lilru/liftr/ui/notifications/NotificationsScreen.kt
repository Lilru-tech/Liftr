package com.lilru.liftr.ui.notifications

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Card
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material.ExperimentalMaterialApi
import androidx.compose.material.pullrefresh.PullRefreshIndicator
import androidx.compose.material.pullrefresh.pullRefresh
import androidx.compose.material.pullrefresh.rememberPullRefreshState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.lilru.liftr.R
import com.lilru.liftr.ui.components.LiftrBackTopBar
import com.lilru.liftr.navigation.AppNavEvents
import com.lilru.liftr.navigation.MainOverlay
import com.lilru.liftr.navigation.NotificationRouter
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.auth
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterialApi::class)
@Composable
fun NotificationsScreen(
    supabase: SupabaseClient,
    onBack: () -> Unit,
    modifier: Modifier = Modifier
) {
    val vm: NotificationsViewModel = viewModel(factory = NotificationsViewModelFactory(supabase))
    val ui by vm.uiState.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()

    val pull = rememberPullRefreshState(
        refreshing = ui.isRefreshing,
        onRefresh = { vm.refresh(false) }
    )
    Box(modifier = modifier.fillMaxSize()) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .statusBarsPadding()
                .pullRefresh(pull)
                .padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            LiftrBackTopBar(onBack = onBack)
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Text(
                    text = stringResource(R.string.notifications_title),
                    style = MaterialTheme.typography.titleMedium
                )
                Text(
                    text = stringResource(R.string.notifications_unread_count, ui.unreadCount),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            if (ui.items.isNotEmpty()) {
                FilledTonalButton(
                    onClick = vm::deleteAllNotifications,
                    enabled = !ui.deleteAllBusy,
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(
                        if (ui.deleteAllBusy) {
                            stringResource(R.string.notifications_delete_all_busy)
                        } else {
                            stringResource(R.string.notifications_delete_all)
                        }
                    )
                }
            }
            if (ui.loading) {
                Text(stringResource(R.string.notifications_loading))
            }
            if (ui.error != null) {
                Text(ui.error ?: "", color = MaterialTheme.colorScheme.error)
            }
            if (!ui.loading && ui.items.isEmpty()) {
                Text(stringResource(R.string.notifications_empty))
            }

            LazyColumn(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                items(ui.items, key = { it.id }) { n ->
                    Card(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable {
                                vm.markAsRead(n.id)
                                scope.launch {
                                    val me = supabase.auth.currentUserOrNull()?.id
                                    var dest = NotificationRouter.overlayFromInAppRow(
                                        n.type,
                                        n.data,
                                        me
                                    )
                                    if (dest is MainOverlay.WorkoutDetail) {
                                        val wId = dest.workoutId
                                        if (dest.ownerId == null) {
                                            val oid = NotificationRouter.resolveWorkoutOwnerId(
                                                supabase,
                                                wId
                                            )
                                            dest = MainOverlay.WorkoutDetail(wId, oid)
                                        }
                                    }
                                    if (dest == null) {
                                        when {
                                            n.profileUserId != null -> {
                                                dest = MainOverlay.FollowerProfile(n.profileUserId)
                                            }
                                            n.workoutId != null -> {
                                                val oid2 = NotificationRouter.resolveWorkoutOwnerId(
                                                    supabase,
                                                    n.workoutId
                                                )
                                                dest = MainOverlay.WorkoutDetail(
                                                    n.workoutId,
                                                    oid2
                                                )
                                            }
                                        }
                                    }
                                    dest?.let { AppNavEvents.send(it) }
                                    onBack()
                                }
                            }
                    ) {
                        Column(modifier = Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            Text(
                                text = n.title,
                                style = MaterialTheme.typography.titleSmall
                            )
                            if (!n.body.isNullOrBlank()) {
                                Text(
                                    text = n.body,
                                    style = MaterialTheme.typography.bodyMedium
                                )
                            }
                            Text(
                                text = "${n.type} • ${n.createdAt?.substringBefore("T") ?: "-"}",
                                style = MaterialTheme.typography.bodySmall,
                                color = if (n.isRead) {
                                    MaterialTheme.colorScheme.onSurfaceVariant
                                } else {
                                    MaterialTheme.colorScheme.primary
                                }
                            )
                            OutlinedButton(
                                onClick = { vm.deleteNotification(n.id) },
                                enabled = !ui.deletingIds.contains(n.id),
                                modifier = Modifier.fillMaxWidth()
                            ) {
                                Text(
                                    if (ui.deletingIds.contains(n.id)) {
                                        stringResource(R.string.notifications_delete_busy)
                                    } else {
                                        stringResource(R.string.notifications_delete_one)
                                    }
                                )
                            }
                        }
                    }
                }
            }
        }
        PullRefreshIndicator(
            refreshing = ui.isRefreshing,
            state = pull,
            modifier = Modifier.align(Alignment.TopCenter)
        )
    }
}
