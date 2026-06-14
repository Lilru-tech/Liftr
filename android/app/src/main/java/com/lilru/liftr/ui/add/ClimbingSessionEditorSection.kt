package com.lilru.liftr.ui.add

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.lilru.liftr.climbing.ClimbingEnvironment
import com.lilru.liftr.climbing.ClimbingGradeSystem
import com.lilru.liftr.climbing.ClimbingRouteForm
import com.lilru.liftr.climbing.ClimbingRouteFormatting
import com.lilru.liftr.climbing.ClimbingStyle

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun ClimbingSessionEditorSection(
    sportStats: Map<String, String>,
    onSportStatChange: (String, String) -> Unit,
    routes: List<ClimbingRouteForm>,
    onRoutesChange: (List<ClimbingRouteForm>) -> Unit,
    modifier: Modifier = Modifier
) {
    val environment = ClimbingEnvironment.fromWire(sportStats["environment"])
    val primaryStyle = ClimbingStyle.fromWire(sportStats["primary_style"])
    val highestGradeSystem = ClimbingGradeSystem.fromWire(sportStats["highest_grade_system"])

    LaunchedEffect(routes) {
        val synced = sportStats.toMutableMap()
        ClimbingRouteFormatting.syncSessionSummary(routes, synced)
        synced.forEach { (key, value) ->
            if (sportStats[key] != value) {
                onSportStatChange(key, value)
            }
        }
    }

    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text("Environment", style = MaterialTheme.typography.titleSmall)
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            ClimbingEnvironment.entries.forEach { env ->
                FilterChip(
                    selected = environment == env,
                    onClick = { onSportStatChange("environment", env.wire) },
                    label = { Text(env.label) }
                )
            }
        }

        Text("Primary style", style = MaterialTheme.typography.titleSmall)
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            ClimbingStyle.entries.forEach { style ->
                FilterChip(
                    selected = primaryStyle == style,
                    onClick = { onSportStatChange("primary_style", style.wire) },
                    label = { Text(style.label) }
                )
            }
        }

        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedTextField(
                value = sportStats["routes_sent"].orEmpty(),
                onValueChange = { onSportStatChange("routes_sent", it) },
                label = { Text("Routes sent") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                modifier = Modifier.weight(1f)
            )
            OutlinedTextField(
                value = sportStats["routes_attempted"].orEmpty(),
                onValueChange = { onSportStatChange("routes_attempted", it) },
                label = { Text("Attempts") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                modifier = Modifier.weight(1f)
            )
        }

        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedTextField(
                value = sportStats["total_vertical_m"].orEmpty(),
                onValueChange = { onSportStatChange("total_vertical_m", it) },
                label = { Text("Vertical m") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                modifier = Modifier.weight(1f)
            )
            OutlinedTextField(
                value = sportStats["flashes"].orEmpty(),
                onValueChange = { onSportStatChange("flashes", it) },
                label = { Text("Flashes") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                modifier = Modifier.weight(1f)
            )
            OutlinedTextField(
                value = sportStats["falls"].orEmpty(),
                onValueChange = { onSportStatChange("falls", it) },
                label = { Text("Falls") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                modifier = Modifier.weight(1f)
            )
        }

        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedTextField(
                value = sportStats["moving_time_sec"].orEmpty(),
                onValueChange = { onSportStatChange("moving_time_sec", it) },
                label = { Text("Move s") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                modifier = Modifier.weight(1f)
            )
            OutlinedTextField(
                value = sportStats["paused_time_sec"].orEmpty(),
                onValueChange = { onSportStatChange("paused_time_sec", it) },
                label = { Text("Pause s") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                modifier = Modifier.weight(1f)
            )
        }

        OutlinedTextField(
            value = sportStats["venue_name"].orEmpty(),
            onValueChange = { onSportStatChange("venue_name", it) },
            label = { Text("Venue") },
            singleLine = true,
            modifier = Modifier.fillMaxWidth()
        )

        if (environment == ClimbingEnvironment.OUTDOOR) {
            OutlinedTextField(
                value = sportStats["weather"].orEmpty(),
                onValueChange = { onSportStatChange("weather", it) },
                label = { Text("Weather") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth()
            )
        }

        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedTextField(
                value = sportStats["avg_hr"].orEmpty(),
                onValueChange = { onSportStatChange("avg_hr", it) },
                label = { Text("Avg HR") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                modifier = Modifier.weight(1f)
            )
            OutlinedTextField(
                value = sportStats["max_hr"].orEmpty(),
                onValueChange = { onSportStatChange("max_hr", it) },
                label = { Text("Max HR") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                modifier = Modifier.weight(1f)
            )
        }

        Text("Highest grade system", style = MaterialTheme.typography.titleSmall)
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            ClimbingGradeSystem.entries.forEach { sys ->
                FilterChip(
                    selected = highestGradeSystem == sys,
                    onClick = {
                        onSportStatChange("highest_grade_system", sys.wire)
                        val current = sportStats["highest_grade_value"].orEmpty()
                        if (current.isNotEmpty() && current !in ClimbingGradeSystem.grades(sys)) {
                            onSportStatChange("highest_grade_value", "")
                        }
                    },
                    label = { Text(sys.label) }
                )
            }
        }

        Text("Highest grade", style = MaterialTheme.typography.titleSmall)
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            FilterChip(
                selected = sportStats["highest_grade_value"].orEmpty().isEmpty(),
                onClick = { onSportStatChange("highest_grade_value", "") },
                label = { Text("—") }
            )
            ClimbingGradeSystem.grades(highestGradeSystem).forEach { grade ->
                FilterChip(
                    selected = sportStats["highest_grade_value"] == grade,
                    onClick = { onSportStatChange("highest_grade_value", grade) },
                    label = { Text(grade) }
                )
            }
        }

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text("Routes", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
            TextButton(
                onClick = {
                    val defaultSystem = ClimbingGradeSystem.defaultForStyle(primaryStyle)
                    onRoutesChange(
                        routes + ClimbingRouteForm(
                            style = primaryStyle,
                            gradeSystem = defaultSystem
                        )
                    )
                }
            ) {
                Text("Add route")
            }
        }

        routes.forEach { route ->
            ClimbingRouteCard(
                route = route,
                onRouteChange = { updated ->
                    onRoutesChange(routes.map { if (it.id == route.id) updated else it })
                },
                onDelete = {
                    val next = routes.filterNot { it.id == route.id }
                    onRoutesChange(next)
                    val synced = sportStats.toMutableMap()
                    ClimbingRouteFormatting.syncSessionSummary(next, synced)
                    synced.forEach { (key, value) -> onSportStatChange(key, value) }
                }
            )
            HorizontalDivider()
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun ClimbingRouteCard(
    route: ClimbingRouteForm,
    onRouteChange: (ClimbingRouteForm) -> Unit,
    onDelete: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 4.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            OutlinedTextField(
                value = route.routeName,
                onValueChange = { onRouteChange(route.copy(routeName = it)) },
                label = { Text("Route name") },
                singleLine = true,
                modifier = Modifier.weight(1f)
            )
            TextButton(onClick = onDelete) { Text("Delete") }
        }

        Text("Style", style = MaterialTheme.typography.labelLarge)
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            ClimbingStyle.entries.forEach { style ->
                FilterChip(
                    selected = route.style == style,
                    onClick = { onRouteChange(route.copy(style = style)) },
                    label = { Text(style.label) }
                )
            }
        }

        Text("Grade system", style = MaterialTheme.typography.labelLarge)
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            ClimbingGradeSystem.entries.forEach { sys ->
                FilterChip(
                    selected = route.gradeSystem == sys,
                    onClick = {
                        onRouteChange(
                            route.copy(
                                gradeSystem = sys,
                                gradeValue = if (route.gradeValue in ClimbingGradeSystem.grades(sys)) {
                                    route.gradeValue
                                } else {
                                    ""
                                }
                            )
                        )
                    },
                    label = { Text(sys.label) }
                )
            }
        }

        Text("Grade", style = MaterialTheme.typography.labelLarge)
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            FilterChip(
                selected = route.gradeValue.isEmpty(),
                onClick = { onRouteChange(route.copy(gradeValue = "")) },
                label = { Text("—") }
            )
            ClimbingGradeSystem.grades(route.gradeSystem).forEach { grade ->
                FilterChip(
                    selected = route.gradeValue == grade,
                    onClick = { onRouteChange(route.copy(gradeValue = grade)) },
                    label = { Text(grade) }
                )
            }
        }

        Row(
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            OutlinedTextField(
                value = route.attempts,
                onValueChange = { onRouteChange(route.copy(attempts = it)) },
                label = { Text("Attempts") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                modifier = Modifier.weight(1f)
            )
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("Sent", modifier = Modifier.padding(end = 4.dp))
                Switch(
                    checked = route.sent,
                    onCheckedChange = { onRouteChange(route.copy(sent = it)) }
                )
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("Flash", modifier = Modifier.padding(end = 4.dp))
                Switch(
                    checked = route.flash,
                    onCheckedChange = { onRouteChange(route.copy(flash = it)) }
                )
            }
        }

        OutlinedTextField(
            value = route.notes,
            onValueChange = { onRouteChange(route.copy(notes = it)) },
            label = { Text("Notes") },
            singleLine = true,
            modifier = Modifier.fillMaxWidth()
        )
    }
}
