package com.lilru.liftr.ui.feature

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.ExperimentalMaterialApi
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.pullrefresh.PullRefreshIndicator
import androidx.compose.material.pullrefresh.pullRefresh
import androidx.compose.material.pullrefresh.rememberPullRefreshState
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.lilru.liftr.R
import com.lilru.liftr.ui.components.LiftrBackTopBar
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.auth

@OptIn(ExperimentalMaterialApi::class)
@Composable
fun FeatureRequestsListScreen(
    supabase: SupabaseClient,
    onBack: () -> Unit,
    modifier: Modifier = Modifier
) {
    val vm: FeatureRequestsListViewModel = viewModel(factory = FeatureRequestsListViewModelFactory(supabase))
    val st by vm.uiState.collectAsStateWithLifecycle()
    var selected by remember { mutableStateOf<FeatureRequestRow?>(null) }
    var showCreate by remember { mutableStateOf(false) }
    val me = supabase.auth.currentUserOrNull()?.id
    val pull = rememberPullRefreshState(
        refreshing = st.isRefreshing,
        onRefresh = { vm.refresh(showBlockingLoader = false) }
    )

    if (showCreate) {
        FeatureRequestCreateScreen(
            supabase = supabase,
            onDismiss = { showCreate = false },
            onCreated = {
                showCreate = false
                vm.refresh(showBlockingLoader = false)
            },
            modifier = modifier
        )
        return
    }
    if (selected != null) {
        FeatureRequestDetailScreen(
            supabase = supabase,
            row = selected!!,
            onBack = { selected = null },
            modifier = modifier
        )
        return
    }

    Box(
        modifier = modifier
            .fillMaxSize()
            .pullRefresh(pull)
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .statusBarsPadding()
                .padding(12.dp)
        ) {
            LiftrBackTopBar(onBack = onBack)
            Text(
                stringResource(R.string.feature_requests_header),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(bottom = 8.dp)
            )
            if (me == null) {
                Text(
                    stringResource(R.string.feature_requests_login_hint),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(bottom = 6.dp)
                )
            }
            when {
                st.loading && st.items.isEmpty() -> {
                    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        CircularProgressIndicator()
                    }
                }
                st.error != null && st.items.isEmpty() -> {
                    Text(
                        st.error!!,
                        color = MaterialTheme.colorScheme.error
                    )
                }
                st.items.isEmpty() -> {
                    Text(
                        stringResource(R.string.feature_requests_empty),
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(24.dp)
                    )
                }
                else -> {
                    LazyColumn(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        items(st.items, key = { it.id }) { fr ->
                            FeatureRequestListCard(
                                fr = fr,
                                voted = st.voteByRequestId[fr.id],
                                voting = st.votingRequestId == fr.id,
                                showVote = me != null,
                                onOpen = { selected = fr },
                                onToggleVote = { vm.toggleVote(fr.id) },
                                onEnsureVote = { vm.ensureVoteState(fr.id) }
                            )
                        }
                    }
                }
            }
        }
        if (me != null) {
            FloatingActionButton(
                onClick = { showCreate = true },
                modifier = Modifier
                    .align(Alignment.BottomEnd)
                    .padding(16.dp)
            ) {
                Icon(Icons.Filled.Add, contentDescription = stringResource(R.string.feature_requests_fab_cd))
            }
        }
        PullRefreshIndicator(
            refreshing = st.isRefreshing,
            state = pull,
            modifier = Modifier.align(Alignment.TopCenter)
        )
    }
}

@Composable
private fun FeatureRequestListCard(
    fr: FeatureRequestRow,
    voted: Boolean?,
    voting: Boolean,
    showVote: Boolean,
    onOpen: () -> Unit,
    onToggleVote: () -> Unit,
    onEnsureVote: () -> Unit
) {
    LaunchedEffect(fr.id) {
        onEnsureVote()
    }
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.45f)
        )
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(12.dp),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            verticalAlignment = Alignment.Top
        ) {
            Column(
                Modifier
                    .weight(1f)
                    .clickable { onOpen() },
                verticalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                Text(
                    fr.title,
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                Text(
                    fr.description,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 3,
                    overflow = TextOverflow.Ellipsis
                )
                Text(
                    stringResource(
                        R.string.feature_requests_meta_counts,
                        fr.votesCount ?: 0,
                        fr.commentsCount ?: 0
                    ),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            if (showVote) {
                FilledTonalButton(
                    onClick = onToggleVote,
                    enabled = voted != null && !voting,
                    modifier = Modifier.padding(0.dp)
                ) {
                    if (voting) {
                        CircularProgressIndicator(
                            strokeWidth = 2.dp,
                            modifier = Modifier
                                .size(22.dp)
                                .padding(2.dp)
                        )
                    } else {
                        Text(
                            if (voted == true) {
                                stringResource(R.string.feature_requests_voted)
                            } else {
                                stringResource(R.string.feature_requests_upvote)
                            }
                        )
                    }
                }
            }
        }
    }
}
