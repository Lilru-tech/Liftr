package com.lilru.liftr.ui.profile

import android.text.format.DateUtils
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.lilru.liftr.R
import com.lilru.liftr.ui.components.LiftrBackTopBar
import com.lilru.liftr.ui.ranking.RankingInitial
import com.lilru.liftr.ui.ranking.RankingMetric
import com.lilru.liftr.ui.ranking.RankingScope
import com.lilru.liftr.ui.ranking.RankingTabScreen
import io.github.jan.supabase.SupabaseClient
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Locale
import kotlin.math.abs
import kotlin.math.round

@Composable
fun UserLevelDetailScreen(
    supabase: SupabaseClient,
    userId: String,
    onBack: () -> Unit,
    onOpenAddWithPendingDuplicate: () -> Unit = {},
    modifier: Modifier = Modifier
) {
    var showFriendsLeaderboard by rememberSaveable { mutableStateOf(false) }
    if (showFriendsLeaderboard) {
        RankingTabScreen(
            supabase = supabase,
            onOpenAddWithPendingDuplicate = onOpenAddWithPendingDuplicate,
            rankingInitial = RankingInitial(
                metric = RankingMetric.LEVEL,
                scope = RankingScope.FRIENDS
            ),
            embedBack = { showFriendsLeaderboard = false },
            modifier = modifier
        )
        return
    }

    val vm: UserLevelDetailViewModel = viewModel(
        key = "user-level-detail-$userId",
        factory = UserLevelDetailViewModelFactory(supabase, userId)
    )
    val st by vm.uiState.collectAsStateWithLifecycle()
    var historyExpanded by rememberSaveable { mutableStateOf(false) }

    Column(
        modifier = modifier
            .fillMaxSize()
            .statusBarsPadding()
            .padding(12.dp)
    ) {
        LiftrBackTopBar(onBack = onBack)
        Text(
            stringResource(R.string.user_level_title),
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.SemiBold,
            modifier = Modifier.padding(vertical = 4.dp)
        )
        when {
            st.loading -> {
                Box(
                    Modifier
                        .weight(1f)
                        .fillMaxWidth(),
                    contentAlignment = Alignment.Center
                ) {
                    CircularProgressIndicator()
                }
            }
            st.error != null -> {
                Text(
                    st.error!!,
                    color = MaterialTheme.colorScheme.error,
                    style = MaterialTheme.typography.bodyMedium
                )
            }
            else -> {
                Column(
                    modifier = Modifier
                        .weight(1f)
                        .fillMaxWidth()
                        .verticalScroll(rememberScrollState()),
                    verticalArrangement = Arrangement.spacedBy(10.dp)
                ) {
                    LevelProgressCard(st = st)
                    MilestonesCard(st = st)
                    XpSnapshotCard(st = st)
                    LastXpActivityCard(
                        st = st,
                        historyExpanded = historyExpanded,
                        onToggleHistory = { historyExpanded = !historyExpanded },
                        onLoadMore = { vm.loadMoreXpEvents() }
                    )
                    HowItWorksCard()
                }
            }
        }
        if (!st.loading && st.error == null) {
            FilledTonalButton(
                onClick = { showFriendsLeaderboard = true },
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = 8.dp)
            ) {
                Text(stringResource(R.string.user_level_leaderboard_friends))
            }
        }
    }
}

@Composable
private fun LevelProgressCard(st: UserLevelDetailUiState) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(16.dp),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.45f)
        )
    ) {
        Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                Text(
                    stringResource(R.string.user_level_lv, st.level),
                    style = MaterialTheme.typography.titleLarge,
                    fontWeight = FontWeight.Black
                )
                Text(
                    stringResource(R.string.user_level_xp_value, formatXpNumber(st.xp)),
                    style = MaterialTheme.typography.titleMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            val nextCap = st.nextLevelThresholdXp
            if (nextCap != null) {
                LinearProgressIndicator(
                    progress = { st.progressRatio.toFloat() },
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(8.dp)
                )
                Text(
                    stringResource(R.string.user_level_next_needs, formatXpNumber(nextCap)),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                val need = st.xpToNextLevel
                if (need != null) {
                    if (need == 0L) {
                        Text(
                            stringResource(R.string.user_level_reached_next),
                            style = MaterialTheme.typography.bodyMedium
                        )
                    } else {
                        Text(
                            stringResource(
                                R.string.user_level_to_go,
                                formatXpNumber(need),
                                st.level + 1
                            ),
                            style = MaterialTheme.typography.bodyMedium
                        )
                    }
                }
            } else {
                Text(
                    stringResource(R.string.user_level_at_top),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }
}

@Composable
private fun MilestonesCard(st: UserLevelDetailUiState) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(16.dp),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.45f)
        )
    ) {
        Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(
                stringResource(R.string.user_level_milestones_header),
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold
            )
            if (st.milestones.isEmpty()) {
                Text(
                    stringResource(R.string.user_level_milestones_empty),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            } else {
                st.milestones.forEachIndexed { i, m ->
                    if (i > 0) HorizontalDivider(Modifier.padding(vertical = 4.dp))
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                        Text(
                            stringResource(R.string.user_level_milestone_level, m.level),
                            style = MaterialTheme.typography.bodyMedium
                        )
                        Text(
                            stringResource(R.string.user_level_milestone_xp, formatXpNumber(m.xpRequired)),
                            style = MaterialTheme.typography.bodyMedium,
                            fontFamily = FontFamily.Monospace,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun XpSnapshotCard(st: UserLevelDetailUiState) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(16.dp),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.45f)
        )
    ) {
        Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(
                stringResource(R.string.user_level_xp_snapshot),
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold
            )
            if (st.xpStatsLoading) {
                CircularProgressIndicator(Modifier.padding(8.dp))
            } else {
                val s = st.xpStatsSummary
                if (s == null) {
                    Text(
                        stringResource(R.string.user_level_xp_snapshot_empty),
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                } else {
                    Text(
                        stringResource(R.string.user_level_xp_sample_line, s.sampledEventCount, 800),
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceEvenly) {
                        XpStatMini(
                            stringResource(R.string.user_level_sum_sample),
                            formatXpNumber(s.totalXpFromSample)
                        )
                        XpStatMini(
                            stringResource(R.string.user_level_best_single),
                            formatXpNumber(s.maxSingleAward)
                        )
                        XpStatMini(
                            stringResource(R.string.user_level_avg_event),
                            formatAvgXp(s.avgPerEvent)
                        )
                    }
                    if (s.byKind.isNotEmpty()) {
                        Text(
                            stringResource(R.string.user_level_by_type),
                            style = MaterialTheme.typography.labelSmall,
                            fontWeight = FontWeight.SemiBold,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.padding(top = 6.dp)
                        )
                        s.byKind.forEachIndexed { i, row ->
                            if (i > 0) HorizontalDivider(Modifier.padding(vertical = 4.dp))
                            Row(
                                Modifier
                                    .fillMaxWidth()
                                    .padding(vertical = 4.dp),
                                horizontalArrangement = Arrangement.SpaceBetween
                            ) {
                                Text(row.kindLabel, style = MaterialTheme.typography.bodyMedium)
                                Column(horizontalAlignment = Alignment.End) {
                                    Text(
                                        stringResource(
                                            R.string.user_level_kind_max_avg,
                                            formatXpNumber(row.maxXp),
                                            formatAvgXp(row.avgXp)
                                        ),
                                        style = MaterialTheme.typography.labelSmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                        fontFamily = FontFamily.Monospace
                                    )
                                    Text(
                                        stringResource(
                                            R.string.user_level_kind_count_sum,
                                            row.eventCount,
                                            formatXpNumber(row.totalXp)
                                        ),
                                        style = MaterialTheme.typography.labelSmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant
                                    )
                                }
                            }
                        }
                    }
                    if (s.bonusNoWorkoutEventCount > 0) {
                        Text(
                            stringResource(R.string.user_level_bonus_no_workout_title),
                            style = MaterialTheme.typography.labelSmall,
                            fontWeight = FontWeight.Medium,
                            modifier = Modifier.padding(top = 4.dp)
                        )
                        Text(
                            stringResource(
                                R.string.user_level_bonus_line,
                                s.bonusNoWorkoutEventCount,
                                formatXpNumber(s.bonusNoWorkoutTotalXp)
                            ),
                            style = MaterialTheme.typography.labelSmall
                        )
                    }
                    if (s.orphanWorkoutRefEventCount > 0) {
                        Text(
                            stringResource(R.string.user_level_orphan_title),
                            style = MaterialTheme.typography.labelSmall,
                            fontWeight = FontWeight.Medium,
                            modifier = Modifier.padding(top = 4.dp)
                        )
                        Text(
                            stringResource(R.string.user_level_orphan_body),
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                        Text(
                            stringResource(
                                R.string.user_level_orphan_line,
                                s.orphanWorkoutRefEventCount,
                                formatXpNumber(s.orphanWorkoutRefTotalXp)
                            ),
                            style = MaterialTheme.typography.labelSmall
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun XpStatMini(title: String, value: String) {
    Column(Modifier.width(100.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(title, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(
            value,
            style = MaterialTheme.typography.bodySmall,
            fontWeight = FontWeight.SemiBold,
            fontFamily = FontFamily.Monospace
        )
    }
}

@Composable
private fun LastXpActivityCard(
    st: UserLevelDetailUiState,
    historyExpanded: Boolean,
    onToggleHistory: () -> Unit,
    onLoadMore: () -> Unit
) {
    val summaryDateMs = st.xpEvents.firstOrNull()?.createdAtMs ?: st.lastActivityAtMs
    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(16.dp),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.45f)
        )
    ) {
        Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable { onToggleHistory() }
            ) {
                Text(
                    stringResource(R.string.user_level_last_xp),
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold
                )
            }
            if (summaryDateMs == null) {
                Text(
                    stringResource(R.string.user_level_no_timestamp),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            } else {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    Column {
                        Text(
                            relTime(summaryDateMs),
                            style = MaterialTheme.typography.bodyMedium,
                            fontWeight = FontWeight.Medium
                        )
                        Text(
                            formatDateTimeShort(summaryDateMs),
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                    val g = st.xpEvents.firstOrNull()?.gainedXp
                    if (g != null && g != 0L) {
                        Text(
                            stringResource(R.string.user_level_plus_xp, formatXpNumber(g)),
                            style = MaterialTheme.typography.titleSmall,
                            color = MaterialTheme.colorScheme.primary
                        )
                    } else if (st.xpEvents.isNotEmpty()) {
                        Text(
                            stringResource(R.string.user_level_plus_zero),
                            style = MaterialTheme.typography.labelSmall
                        )
                    }
                }
            }
            if (historyExpanded) {
                when {
                    st.xpEventsFailed -> {
                        Text(
                            stringResource(R.string.user_level_events_error),
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                    st.xpEvents.isEmpty() -> {
                        Text(
                            stringResource(R.string.user_level_events_empty),
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                    else -> {
                        Column(
                            modifier = Modifier
                                .heightIn(max = 240.dp)
                                .fillMaxWidth()
                                .verticalScroll(rememberScrollState())
                        ) {
                            st.xpEvents.forEach { ev ->
                                Row(
                                    Modifier
                                        .fillMaxWidth()
                                        .padding(vertical = 6.dp),
                                    horizontalArrangement = Arrangement.SpaceBetween
                                ) {
                                    Column {
                                        Text(
                                            formatDateTimeShort(ev.createdAtMs),
                                            style = MaterialTheme.typography.bodySmall,
                                            fontWeight = FontWeight.Medium
                                        )
                                        Text(
                                            relTime(ev.createdAtMs),
                                            style = MaterialTheme.typography.labelSmall,
                                            color = MaterialTheme.colorScheme.onSurfaceVariant
                                        )
                                    }
                                    Text(
                                        if (ev.gainedXp >= 0) {
                                            stringResource(
                                                R.string.user_level_plus_xp,
                                                formatXpNumber(ev.gainedXp)
                                            )
                                        } else {
                                            stringResource(
                                                R.string.user_level_signed_xp,
                                                formatXpNumber(ev.gainedXp)
                                            )
                                        },
                                        style = MaterialTheme.typography.bodySmall,
                                        color = if (ev.gainedXp >= 0) {
                                            MaterialTheme.colorScheme.onSurface
                                        } else {
                                            MaterialTheme.colorScheme.error
                                        }
                                    )
                                }
                                HorizontalDivider(Modifier.padding(vertical = 2.dp))
                            }
                            if (st.xpEventsCanLoadMore) {
                                if (st.xpEventsLoadingMore) {
                                    Box(
                                        Modifier
                                            .fillMaxWidth()
                                            .padding(12.dp),
                                        contentAlignment = Alignment.Center
                                    ) {
                                        CircularProgressIndicator(Modifier.size(24.dp))
                                    }
                                } else {
                                    TextButton(
                                        onClick = onLoadMore,
                                        modifier = Modifier.fillMaxWidth()
                                    ) {
                                        Text(stringResource(R.string.user_level_load_more))
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun HowItWorksCard() {
    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(16.dp),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.45f)
        )
    ) {
        Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(
                stringResource(R.string.user_level_how_title),
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold
            )
            Text("•  " + stringResource(R.string.user_level_bullet1), color = MaterialTheme.colorScheme.onSurfaceVariant)
            Text("•  " + stringResource(R.string.user_level_bullet2), color = MaterialTheme.colorScheme.onSurfaceVariant)
            Text("•  " + stringResource(R.string.user_level_bullet3), color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

private fun formatXpNumber(v: Long): String = when {
    v >= 1_000_000_000L -> String.format(Locale.US, "%.1fB", v / 1_000_000_000.0)
    v >= 1_000_000L -> String.format(Locale.US, "%.1fM", v / 1_000_000.0)
    v >= 1_000L -> String.format(Locale.US, "%.1fk", v / 1_000.0)
    else -> v.toString()
}

private fun formatAvgXp(v: Double): String {
    if (!v.isFinite()) return "—"
    if (abs(v - round(v)) < 0.05) return String.format(Locale.US, "%.0f", v)
    return String.format(Locale.US, "%.1f", v)
}

private fun formatDateTimeShort(ms: Long): String {
    val zdt = Instant.ofEpochMilli(ms).atZone(ZoneId.systemDefault())
    return DateTimeFormatter.ofLocalizedDateTime(FormatStyle.MEDIUM, FormatStyle.SHORT).format(zdt)
}

private fun relTime(ms: Long): String =
    DateUtils.getRelativeTimeSpanString(
        ms,
        System.currentTimeMillis(),
        DateUtils.MINUTE_IN_MILLIS
    ).toString()
