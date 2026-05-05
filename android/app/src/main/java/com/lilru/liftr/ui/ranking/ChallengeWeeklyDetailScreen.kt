package com.lilru.liftr.ui.ranking

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.lilru.liftr.R
import com.lilru.liftr.ui.components.LiftrAvatar
import com.lilru.liftr.ui.components.LiftrBackTopBar
import io.github.jan.supabase.SupabaseClient
import java.util.UUID

@Composable
fun ChallengeWeeklyDetailScreen(
    supabase: SupabaseClient,
    instanceId: UUID,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val vm: ChallengeWeeklyDetailViewModel = viewModel(
        factory = ChallengeWeeklyDetailViewModelFactory(supabase, instanceId)
    )
    val st by vm.state.collectAsStateWithLifecycle()

    Column(modifier = modifier.fillMaxSize()) {
        LiftrBackTopBar(
            onBack = onBack,
            title = stringResource(R.string.ranking_weekly_challenges_detail_title),
            modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp)
        )
        when {
            st.loading -> {
                Text(
                    stringResource(R.string.ranking_loading),
                    modifier = Modifier.padding(16.dp)
                )
            }
            st.error != null -> {
                Text(
                    st.error ?: "",
                    color = MaterialTheme.colorScheme.error,
                    modifier = Modifier.padding(16.dp)
                )
            }
            st.detail != null -> {
                val d = st.detail!!
                LazyColumn(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(horizontal = 16.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    item {
                        Text(
                            text = when (d.cadence.lowercase()) {
                                "week" -> "Weekly"
                                "month" -> "Monthly"
                                "once" -> "Open"
                                else -> d.cadence.replaceFirstChar { it.uppercase() }
                            },
                            style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                    item {
                        Text(
                            d.title,
                            style = MaterialTheme.typography.titleLarge,
                            color = MaterialTheme.colorScheme.onSurface
                        )
                    }
                    item {
                        Text(d.description, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    st.progressLine?.let { line ->
                        item {
                            Text(
                                stringResource(R.string.ranking_weekly_challenges_your_progress, line),
                                style = MaterialTheme.typography.bodyLarge,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    }
                    if (d.viewerClaimed && d.viewerRank != null) {
                        item {
                            Text(
                                stringResource(R.string.ranking_weekly_challenges_you_placed, d.viewerRank),
                                style = MaterialTheme.typography.titleSmall,
                                color = MaterialTheme.colorScheme.primary
                            )
                        }
                    }
                    item {
                        Text(
                            stringResource(R.string.ranking_weekly_challenges_leaderboard_heading, d.claimsCount, d.maxWinners.toLong()),
                            style = MaterialTheme.typography.titleMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                    if (st.leaderboard.isEmpty()) {
                        item {
                            Text(
                                stringResource(R.string.ranking_weekly_challenges_empty_leaderboard),
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    } else {
                        items(st.leaderboard, key = { "${it.userId}-${it.rank}" }) { row ->
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.spacedBy(10.dp)
                            ) {
                                Text(
                                    "#${row.rank}",
                                    style = MaterialTheme.typography.titleSmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                                LiftrAvatar(
                                    imageUrl = row.avatarUrl,
                                    displayName = row.username,
                                    size = 40.dp
                                )
                                Column {
                                    Text(
                                        row.username ?: row.userId,
                                        style = MaterialTheme.typography.titleSmall,
                                        color = MaterialTheme.colorScheme.onSurface
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
