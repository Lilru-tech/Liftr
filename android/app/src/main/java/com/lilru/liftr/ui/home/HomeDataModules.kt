package com.lilru.liftr.ui.home

import android.content.Intent
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Image
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.WorkspacePremium
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.lilru.liftr.R
import com.lilru.liftr.ui.components.LiftrAvatar
import androidx.compose.ui.platform.LocalContext

@Composable
fun HomeTodayCard(
    count: Int,
    minutes: Int,
    points: Int,
    kcal: Int
) {
    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(
                stringResource(R.string.home_today_headline),
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold
            )
            Text(
                if (kcal > 0) {
                    stringResource(R.string.home_today_body_kcal, count, minutes, points, kcal)
                } else {
                    stringResource(R.string.home_today_body_no_kcal, count, minutes, points)
                },
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

@Composable
fun HomeStreakCard(
    streak: Int,
    weekWorkouts: Int,
    weekPoints: Int,
    weekKcal: Int
) {
    Card(Modifier.fillMaxWidth()) {
        Row(
            Modifier
                .padding(12.dp)
                .fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Text(
                text = if (streak > 0) {
                    "🔥 " + stringResource(R.string.home_streak_badge, streak)
                } else {
                    "🔥 " + stringResource(R.string.home_streak_start)
                },
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.SemiBold
            )
            Text(
                text = if (weekKcal > 0) {
                    stringResource(R.string.home_streak_line_kcal, weekWorkouts, weekPoints, weekKcal)
                } else {
                    stringResource(R.string.home_streak_line, weekWorkouts, weekPoints)
                },
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.SemiBold
            )
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun HomeInsightsRow(
    bestWeekPts: Int,
    bestWeekKcal: Int,
    bestSportLabel: String,
    bestSportScore: Int
) {
    val sport = bestSportLabel.ifBlank { "—" }
    Card(Modifier.fillMaxWidth()) {
        FlowRow(
            modifier = Modifier
                .fillMaxWidth()
                .padding(12.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            if (bestWeekPts > 0) {
                InsightPill(
                    text = if (bestWeekKcal > 0) {
                        "💪 " + stringResource(
                            R.string.home_insight_strongest_week_kcal,
                            bestWeekPts,
                            bestWeekKcal
                        )
                    } else {
                        "💪 " + stringResource(R.string.home_insight_strongest_week_pts, bestWeekPts)
                    }
                )
            }
            if (bestSportScore > 0) {
                InsightPill(
                    text = "⚽ " + stringResource(
                        R.string.home_insight_best_sport,
                        bestSportScore,
                        sport
                    )
                )
            }
        }
    }
}

@Composable
private fun InsightPill(text: String) {
    Text(
        text = text,
        style = MaterialTheme.typography.labelLarge,
        fontWeight = FontWeight.SemiBold,
        modifier = Modifier
            .background(
                MaterialTheme.colorScheme.surface.copy(alpha = 0.6f),
                RoundedCornerShape(50)
            )
            .border(1.dp, Color.White.copy(alpha = 0.18f), RoundedCornerShape(50))
            .padding(vertical = 6.dp, horizontal = 10.dp)
    )
}

@Composable
fun HomeGoalsCompetitionsRow(
    compact: Boolean,
    onGoals: () -> Unit,
    onCompetitions: () -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 4.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        GoalsOrCompetitionsCard(
            compact = compact,
            icon = { Text("🎯", style = MaterialTheme.typography.headlineSmall) },
            title = stringResource(R.string.home_weekly_goals),
            subtitle = stringResource(R.string.home_goals_subtitle),
            onClick = onGoals,
            modifier = Modifier.weight(1f)
        )
        GoalsOrCompetitionsCard(
            compact = compact,
            icon = { Text("🏆", style = MaterialTheme.typography.headlineSmall) },
            title = stringResource(R.string.home_competitions),
            subtitle = stringResource(R.string.home_competitions_subtitle),
            onClick = onCompetitions,
            modifier = Modifier.weight(1f)
        )
    }
}

@Composable
private fun GoalsOrCompetitionsCard(
    compact: Boolean,
    icon: @Composable () -> Unit,
    title: String,
    subtitle: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    Card(
        modifier = modifier
            .clickable(onClick = onClick)
    ) {
        if (compact) {
            Row(
                Modifier
                    .fillMaxWidth()
                    .padding(12.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                icon()
                Text(
                    text = title,
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold
                )
                Spacer(Modifier.weight(1f))
                Text("›", style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        } else {
            Row(
                Modifier
                    .fillMaxWidth()
                    .padding(12.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                icon()
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(
                        text = title,
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.SemiBold
                    )
                    Text(
                        text = subtitle,
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 1
                    )
                }
                Text("›", style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

@Composable
fun HomeHighlightsCard(
    prs: List<HomePrRow>,
    weeklyTop: List<HomeWeeklyTopUser>
) {
    if (prs.isEmpty() && weeklyTop.isEmpty()) return
    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            if (prs.isNotEmpty()) {
                Text(
                    stringResource(R.string.home_pr_section_title),
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold
                )
                prs.take(5).forEach { pr ->
                    val owner = pr.username ?: "user"
                    val metricPretty = HomePrFormatting.prettyMetric(pr.metric)
                    val valuePretty = HomePrFormatting.formatValue(pr.metric, pr.value)
                    val rel = HomePrFormatting.relativeShort(pr.achievedAt)
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(10.dp),
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        LiftrAvatar(
                            imageUrl = null,
                            displayName = owner,
                            size = 28.dp
                        )
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                Text(
                                    "@$owner",
                                    style = MaterialTheme.typography.bodySmall,
                                    fontWeight = FontWeight.SemiBold
                                )
                                Text(
                                    "• $metricPretty",
                                    style = MaterialTheme.typography.labelSmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                            }
                            Text(
                                "${pr.label}: $valuePretty",
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                maxLines = 1
                            )
                        }
                        Text(
                            rel,
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }
            }
            if (weeklyTop.isNotEmpty() && prs.isNotEmpty()) {
                HorizontalDivider(Modifier.padding(vertical = 4.dp))
            }
            if (weeklyTop.isNotEmpty()) {
                Text(
                    stringResource(R.string.home_weekly_top),
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold
                )
                weeklyTop.forEachIndexed { i, u ->
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(10.dp),
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text(
                            "#${i + 1}",
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                        LiftrAvatar(
                            imageUrl = u.avatarUrl,
                            displayName = u.username,
                            size = 28.dp
                        )
                        Text(
                            text = "@${u.username ?: "—"}",
                            style = MaterialTheme.typography.bodySmall
                        )
                        Spacer(Modifier.weight(1f))
                        Text(
                            "${u.points} pts",
                            style = MaterialTheme.typography.bodySmall,
                            fontWeight = FontWeight.SemiBold
                        )
                    }
                }
            }
        }
    }
}

@Composable
fun HomeMonthlySummaryCard(
    month: HomeMonthSummaryUi,
    onHide: () -> Unit
) {
    var expanded by remember { mutableStateOf(false) }
    val ctx = LocalContext.current
    val medalTrophy = month.workoutCount >= 20 || (month.deltaPercent ?: 0.0) >= 10.0
    val imp = month.deltaPercent?.let { d ->
        (if (d >= 0) "+" else "") + "%.0f%%".format(d)
    } ?: "0%"
    val bodyLine = stringResource(
        R.string.home_month_line_stats,
        month.workoutCount,
        month.scoreTotal,
        imp
    )

    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(
                Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Text(
                    stringResource(R.string.home_month_header, month.label),
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold,
                    modifier = Modifier.weight(1f)
                )
                Icon(
                    imageVector = if (medalTrophy) Icons.Filled.WorkspacePremium else Icons.Filled.Star,
                    contentDescription = null,
                    tint = if (medalTrophy) Color(0xFFFFC107) else MaterialTheme.colorScheme.onSurfaceVariant
                )
                TextButton(onClick = onHide) {
                    Text(stringResource(R.string.home_hide_section))
                }
            }
            Text(
                bodyLine,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            TextButton(
                onClick = { expanded = !expanded }
            ) {
                Text(
                    if (expanded) {
                        stringResource(R.string.home_month_show_less)
                    } else {
                        stringResource(R.string.home_month_show_more)
                    }
                )
            }
            if (expanded && month.series.size > 1) {
                HomeMonthLineChart(
                    points = month.series,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(top = 4.dp)
                )
            }
            if (expanded) {
                Row(
                    Modifier
                        .fillMaxWidth()
                        .padding(top = 4.dp),
                    horizontalArrangement = Arrangement.Center
                ) {
                    Button(
                        onClick = { HomeMonthShareImage.sharePng(ctx, month) }
                    ) {
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(8.dp)
                        ) {
                            Icon(
                                imageVector = Icons.Filled.Share,
                                contentDescription = null
                            )
                            Text(stringResource(R.string.home_month_share_progress))
                        }
                    }
                }
                Row(
                    Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.End
                ) {
                    IconButton(
                        onClick = {
                            val t = ctx.getString(
                                R.string.home_month_share,
                                month.label,
                                month.workoutCount,
                                month.scoreTotal
                            )
                            val send = Intent(Intent.ACTION_SEND).apply {
                                type = "text/plain"
                                putExtra(Intent.EXTRA_TEXT, t)
                            }
                            ctx.startActivity(Intent.createChooser(send, null))
                        }
                    ) {
                        Icon(
                            imageVector = Icons.Filled.Share,
                            contentDescription = stringResource(R.string.home_share_month_content_description)
                        )
                    }
                    IconButton(
                        onClick = { HomeMonthShareImage.sharePng(ctx, month) }
                    ) {
                        Icon(
                            imageVector = Icons.Filled.Image,
                            contentDescription = stringResource(R.string.home_share_image_cd)
                        )
                    }
                }
            }
        }
    }
}
