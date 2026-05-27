package com.lilru.liftr.ui.nutrition

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
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
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.YearMonth
import java.time.format.TextStyle
import java.util.Locale

@Composable
private val CalendarBudgetUnderColor = Color(0xFFFF9800)
private val CalendarBudgetOverColor = Color(0xFFE53935)

fun NutritionCalendarCard(
    month: YearMonth,
    selectedDate: LocalDate,
    dayBalance: Map<LocalDate, NutritionMonthDayBalance>,
    onPrevMonth: () -> Unit,
    onNextMonth: () -> Unit,
    onToday: () -> Unit,
    onSelectDay: (LocalDate) -> Unit,
    modifier: Modifier = Modifier
) {
    val cells = buildMonthCells(month)
    Card(
        modifier = modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.45f)
        )
    ) {
        Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                IconButton(onClick = onPrevMonth) {
                    Icon(Icons.Filled.ChevronLeft, contentDescription = null)
                }
                Text(
                    text = month.month.getDisplayName(TextStyle.FULL, Locale.getDefault()) + " " + month.year,
                    style = MaterialTheme.typography.titleSmall,
                    modifier = Modifier.weight(1f),
                    textAlign = TextAlign.Center
                )
                TextButton(onClick = onToday) { Text("Today") }
                IconButton(onClick = onNextMonth) {
                    Icon(Icons.Filled.ChevronRight, contentDescription = null)
                }
            }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceEvenly) {
                DayOfWeek.values().forEach { d ->
                    Text(
                        d.getDisplayName(TextStyle.SHORT, Locale.getDefault()).take(2),
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.weight(1f),
                        textAlign = TextAlign.Center
                    )
                }
            }
            for (row in cells.chunked(7)) {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    row.forEach { day ->
                        NutritionDayCell(
                            day = day,
                            summary = day?.let { dayBalance[it] },
                            selected = day == selectedDate,
                            today = day == LocalDate.now(),
                            onClick = { if (day != null) onSelectDay(day) },
                            modifier = Modifier.weight(1f)
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun NutritionDayCell(
    day: LocalDate?,
    summary: NutritionMonthDayBalance?,
    selected: Boolean,
    today: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    if (day == null) {
        Box(modifier.height(34.dp))
        return
    }
    val count = summary?.mealLogCount ?: 0
    val bg = when {
        count > 0 -> {
            val accent = if ((summary?.remainingCalories ?: 0.0) < 0) {
                CalendarBudgetOverColor
            } else {
                CalendarBudgetUnderColor
            }
            accent.copy(alpha = if (selected) 0.55f else 0.32f)
        }
        selected -> MaterialTheme.colorScheme.onSurface.copy(alpha = 0.12f)
        else -> MaterialTheme.colorScheme.onSurface.copy(alpha = 0.05f)
    }
    Box(
        modifier = modifier
            .height(34.dp)
            .clip(RoundedCornerShape(10.dp))
            .background(bg)
            .then(
                when {
                    selected -> Modifier.border(2.dp, MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f), RoundedCornerShape(10.dp))
                    today -> Modifier.border(1.5.dp, MaterialTheme.colorScheme.tertiary, RoundedCornerShape(10.dp))
                    else -> Modifier
                }
            )
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center
    ) {
        Text("${day.dayOfMonth}", style = MaterialTheme.typography.labelMedium, fontWeight = if (selected) FontWeight.Bold else FontWeight.Normal)
        if (count > 1) {
            Text(
                "$count",
                style = MaterialTheme.typography.labelSmall,
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .padding(2.dp)
            )
        }
    }
}

private fun buildMonthCells(month: YearMonth): List<LocalDate?> {
    val first = month.atDay(1)
    val daysInMonth = month.lengthOfMonth()
    val leading = (first.dayOfWeek.value + 6) % 7
    val cells = mutableListOf<LocalDate?>()
    repeat(leading) { cells.add(null) }
    for (d in 1..daysInMonth) cells.add(month.atDay(d))
    while (cells.size % 7 != 0) cells.add(null)
    return cells
}
