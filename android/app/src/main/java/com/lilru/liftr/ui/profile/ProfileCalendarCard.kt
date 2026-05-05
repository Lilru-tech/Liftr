package com.lilru.liftr.ui.profile

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ChevronLeft
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.lilru.liftr.R
import com.lilru.liftr.navigation.AppNavEvents
import com.lilru.liftr.navigation.MainOverlay
import io.github.jan.supabase.SupabaseClient
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter

@Composable
fun ProfileCalendarCard(
    supabase: SupabaseClient,
    profileUserId: String,
    modifier: Modifier = Modifier
) {
    val calVm: ProfileMonthCalendarViewModel = viewModel(
        key = "profile-cal-$profileUserId",
        factory = ProfileMonthCalendarViewModelFactory(supabase, profileUserId)
    )
    val cal by calVm.uiState.collectAsStateWithLifecycle()
    val zone = ZoneId.systemDefault()
    val cells = buildMonthGridCells(cal.yearMonth)
    val weekLabels = weekDayLabels()

    Card(
        modifier = modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.background
        )
    ) {
        Column(
            modifier = Modifier.padding(14.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Text(
                stringResource(R.string.profile_calendar_section),
                style = MaterialTheme.typography.titleMedium
            )
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically
            ) {
                IconButton(
                    onClick = { calVm.shiftMonth(-1) },
                    enabled = !cal.loadingMonth
                ) { Icon(Icons.Filled.ChevronLeft, contentDescription = null) }
                Text(
                    text = formatMonthTitle(cal.yearMonth),
                    style = MaterialTheme.typography.titleSmall,
                    modifier = Modifier.weight(1f),
                    textAlign = TextAlign.Center
                )
                IconButton(
                    onClick = { calVm.shiftMonth(1) },
                    enabled = !cal.loadingMonth
                ) { Icon(Icons.Filled.ChevronRight, contentDescription = null) }
            }
            if (cal.loadingMonth) {
                Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator(Modifier.size(32.dp), strokeWidth = 3.dp)
                }
            } else {
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceEvenly) {
                        for (w in weekLabels) {
                            Text(
                                w,
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                modifier = Modifier.weight(1f),
                                textAlign = TextAlign.Center
                            )
                        }
                    }
                    for (row in 0 until (cells.size / 7)) {
                        Row(
                            Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.spacedBy(4.dp)
                        ) {
                            for (c in 0..6) {
                                val idx = row * 7 + c
                                val day = cells.getOrNull(idx)
                                val selected = day != null && cal.selectedDay == day
                                val total = if (day != null) cal.totalOn(day) else 0
                                val own = if (day != null) cal.ownOn(day) else 0
                                val planned = day != null && cal.plannedOn(day)
                                val cellColor = cellBackground(total, own, planned)
                                Box(
                                    modifier = Modifier
                                        .weight(1f)
                                        .height(36.dp)
                                        .clip(RoundedCornerShape(8.dp))
                                        .background(cellColor)
                                        .then(
                                            if (selected) {
                                                Modifier.border(2.5.dp, Color.White.copy(alpha = 0.92f), RoundedCornerShape(8.dp))
                                            } else {
                                                Modifier
                                            }
                                        )
                                        .clickable(enabled = day != null) {
                                            if (day != null) calVm.selectDay(day)
                                        },
                                    contentAlignment = Alignment.Center
                                ) {
                                    if (day != null) {
                                        Text(
                                            "${day.dayOfMonth}",
                                            style = MaterialTheme.typography.labelMedium.copy(
                                                fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal
                                            )
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
            }
            if (cal.error != null) {
                Text(
                    cal.error!!,
                    color = MaterialTheme.colorScheme.error,
                    style = MaterialTheme.typography.bodySmall
                )
            }
            if (cal.selectedDay == null) {
                Text(
                    stringResource(R.string.profile_calendar_select_day),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            } else {
                Text(
                    dayTitle(cal.selectedDay!!),
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold
                )
                if (cal.dayLoading) {
                    Box(Modifier.fillMaxWidth().padding(8.dp), contentAlignment = Alignment.Center) {
                        CircularProgressIndicator(Modifier.size(28.dp), strokeWidth = 2.dp)
                    }
                } else {
                    if (cal.dayOwn.isEmpty() && cal.dayParticipated.isEmpty()) {
                        Text(
                            stringResource(R.string.profile_calendar_no_workouts),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    } else {
                        Column(
                            verticalArrangement = Arrangement.spacedBy(8.dp),
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            for (w in cal.dayOwn) {
                                key(w.id) {
                                    DayWorkoutRow(
                                        w = w,
                                        zone = zone,
                                        onOpen = { AppNavEvents.send(MainOverlay.WorkoutDetail(w.id, w.userId)) }
                                    )
                                }
                            }
                            if (cal.dayParticipated.isNotEmpty() && cal.dayOwn.isNotEmpty()) {
                                Spacer(Modifier.height(4.dp))
                            }
                            for (w in cal.dayParticipated) {
                                key(w.id) {
                                    DayWorkoutRow(
                                        w = w,
                                        zone = zone,
                                        onOpen = { AppNavEvents.send(MainOverlay.WorkoutDetail(w.id, w.userId)) }
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

private fun dayTitle(day: LocalDate): String {
    val f = DateTimeFormatter.ofPattern("EEEE, d MMM yyyy", java.util.Locale.getDefault())
    return day.format(f)
}

private fun cellBackground(total: Int, own: Int, planned: Boolean): Color {
    if (total <= 0) return Color.Transparent
    if (planned) {
        return Color(0.6f, 0.1f, 0.2f).copy(alpha = (0.2f + total * 0.05f).coerceAtMost(0.45f))
    }
    if (own > 0) {
        return Color(0.2f, 0.65f, 0.3f).copy(alpha = (0.15f + total * 0.1f).coerceAtMost(0.35f))
    }
    return Color(0.9f, 0.8f, 0.1f).copy(alpha = (0.15f + total * 0.1f).coerceAtMost(0.35f))
}

@Composable
private fun DayWorkoutRow(
    w: ProfileDayWorkoutUi,
    zone: ZoneId,
    onOpen: () -> Unit
) {
    val isPlanned = (w.state ?: "published") == "planned"
    val time = formatWorkoutTime(w.startedAt, zone)
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onOpen),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = if (isPlanned) 0.55f else 1f)
        )
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(12.dp),
            verticalAlignment = Alignment.Top,
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(
                    (w.title ?: w.kind.replaceFirstChar { it.titlecase() }),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.SemiBold
                )
                Text(
                    time,
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(
                        w.kind.replaceFirstChar { it.titlecase() },
                        fontSize = 10.sp,
                        fontWeight = FontWeight.SemiBold,
                        modifier = Modifier
                            .clip(RoundedCornerShape(50))
                            .background(MaterialTheme.colorScheme.outline.copy(alpha = 0.2f))
                            .padding(horizontal = 6.dp, vertical = 2.dp)
                    )
                    if (w.isParticipated) {
                        Text(
                            stringResource(R.string.profile_calendar_participated),
                            fontSize = 10.sp,
                            fontWeight = FontWeight.SemiBold,
                            modifier = Modifier
                                .clip(RoundedCornerShape(50))
                                .background(Color(0.9f, 0.8f, 0.1f).copy(alpha = 0.35f))
                                .padding(horizontal = 6.dp, vertical = 2.dp)
                        )
                    }
                    if (isPlanned) {
                        Text(
                            stringResource(R.string.profile_calendar_planned),
                            fontSize = 10.sp,
                            fontWeight = FontWeight.SemiBold,
                            modifier = Modifier
                                .clip(RoundedCornerShape(50))
                                .background(Color(0.95f, 0.85f, 0.2f).copy(alpha = 0.4f))
                                .padding(horizontal = 6.dp, vertical = 2.dp)
                        )
                    }
                }
            }
            w.score?.let { sc ->
                Text(
                    "${sc.toInt()}",
                    style = MaterialTheme.typography.labelLarge,
                    fontWeight = FontWeight.Bold
                )
            }
        }
    }
}

private fun formatWorkoutTime(startedAt: String?, zone: ZoneId): String {
    if (startedAt.isNullOrBlank()) return "—"
    return runCatching {
        val z = Instant.parse(startedAt).atZone(zone)
        DateTimeFormatter.ofPattern("HH:mm", java.util.Locale.getDefault()).format(z)
    }.getOrDefault("—")
}
