package com.lilru.liftr.ui.pets

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import coil.compose.AsyncImage
import com.lilru.liftr.data.PetInstanceWire
import com.lilru.liftr.data.PetService
import com.lilru.liftr.data.PetStatsWire
import kotlinx.coroutines.delay
import java.time.Instant
import java.time.format.DateTimeParseException

private val FOOD_TYPES = listOf("food_baby", "food_kid", "food_teen", "food_adult", "food_elder")

@Composable
fun PetDetailPopover(
    vm: PetViewModel,
    modifier: Modifier = Modifier
) {
    val context = LocalContext.current
    val ui by vm.uiState.collectAsStateWithLifecycle()
  LaunchedEffect(Unit) {
        vm.load()
        vm.startPollingIfNeeded()
    }

    Column(
        modifier = modifier
            .fillMaxWidth()
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Text("Your Pet", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)

        if (ui.loading && ui.data == null) {
            CircularProgressIndicator()
            return@Column
        }

        val pet = ui.data?.pet ?: run {
            Text("No active pet yet.", color = MaterialTheme.colorScheme.onSurfaceVariant)
            return@Column
        }

        PetAsyncImage(
            pet = pet,
            modifier = Modifier.align(Alignment.CenterHorizontally),
            size = 96.dp
        )

        PetNameEditor(pet, onSave = { vm.updateName(it) })

        Text("Rarity: ${pet.rarity.replaceFirstChar { it.uppercase() }}", style = MaterialTheme.typography.bodySmall)

        if (isIncubating(pet)) {
            IncubationSection(pet, onReroll = { vm.rerollEgg(context) })
        } else if (!pet.evolutionStage.equals("egg", ignoreCase = true)) {
            HatchedSection(
                pet = pet,
                stats = ui.data?.stats,
                xpRequired = ui.data?.xpRequired ?: 1,
                canEvolve = ui.data?.canEvolve == true,
                inventory = ui.data?.inventory.orEmpty(),
                feeding = ui.feeding,
                evolving = ui.evolving,
                onEvolve = { vm.confirmEvolution() },
                onFeed = { vm.feed(it) }
            )
        }

        ui.error?.let { Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall) }
    }
}

@Composable
private fun PetNameEditor(pet: PetInstanceWire, onSave: (String) -> Unit) {
    var editing by remember { mutableStateOf(false) }
    var draft by remember(pet.customName) { mutableStateOf(pet.customName.orEmpty()) }
    if (editing) {
        OutlinedTextField(
            value = draft,
            onValueChange = { draft = it },
            modifier = Modifier.fillMaxWidth(),
            singleLine = true,
            trailingIcon = {
                TextButton(onClick = {
                    onSave(draft)
                    editing = false
                }) { Text("Save") }
            }
        )
    } else {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                pet.customName?.takeIf { it.isNotBlank() }
                    ?: pet.petType.replace('_', ' ').replaceFirstChar { it.uppercase() },
                fontWeight = FontWeight.Bold
            )
            TextButton(onClick = { editing = true }) { Text("Edit") }
        }
    }
}

@Composable
private fun IncubationSection(pet: PetInstanceWire, onReroll: () -> Unit) {
    var remaining by remember { mutableStateOf(hatchRemainingMs(pet.hatchAt)) }
    LaunchedEffect(pet.hatchAt) {
        while (remaining > 0) {
            delay(1000)
            remaining = hatchRemainingMs(pet.hatchAt)
        }
    }
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text("Hatching in", fontWeight = FontWeight.SemiBold)
        Text(formatRemaining(remaining), fontWeight = FontWeight.Bold)
        Text("Species: ${pet.petType}", style = MaterialTheme.typography.bodySmall)
        TextButton(onClick = onReroll) { Text("Reroll egg") }
    }
}

@Composable
private fun HatchedSection(
    pet: PetInstanceWire,
    stats: PetStatsWire?,
    xpRequired: Int,
    canEvolve: Boolean,
    inventory: List<com.lilru.liftr.data.PetInventoryWire>,
    feeding: Boolean,
    evolving: Boolean,
    onEvolve: () -> Unit,
    onFeed: (String) -> Unit
) {
    val req = xpRequired.coerceAtLeast(1)
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text("Level ${pet.currentLevel}", fontWeight = FontWeight.SemiBold)
        LinearProgressIndicator(progress = { pet.currentXp.toFloat() / req }, modifier = Modifier.fillMaxWidth())
        Text("${pet.currentXp} / $req XP", style = MaterialTheme.typography.bodySmall)

        if (canEvolve) {
            Button(onClick = onEvolve, enabled = !evolving, modifier = Modifier.fillMaxWidth()) {
                if (evolving) CircularProgressIndicator(modifier = Modifier.padding(end = 8.dp))
                Text("Evolve to next stage")
            }
        }

        stats?.let { StatsGrid(it) }

        Text("Food", fontWeight = FontWeight.SemiBold)
        val foods = inventory.filter { it.itemType in FOOD_TYPES && it.quantity > 0 }
        if (foods.isEmpty()) {
            Text("No food in inventory.", style = MaterialTheme.typography.bodySmall)
        } else {
            Row(
                modifier = Modifier.horizontalScroll(rememberScrollState()),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                foods.forEach { item ->
                    TextButton(onClick = { onFeed(item.itemType) }, enabled = !feeding) {
                        Text("${item.itemType.substringAfter("food_")} ×${item.quantity}")
                    }
                }
            }
        }
    }
}

@Composable
private fun StatsGrid(stats: PetStatsWire) {
    val pairs = listOf(
        "Health" to stats.health,
        "Strength" to stats.strength,
        "Defense" to stats.defense,
        "Speed" to stats.speed,
        "Intelligence" to stats.intelligence,
        "Agility" to stats.agility,
        "Stamina" to stats.stamina,
        "Crit" to stats.criticalRate,
        "Resistance" to stats.resistance,
        "Explore" to stats.exploration,
        "Happiness" to stats.happiness
    )
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        pairs.chunked(2).forEach { row ->
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                row.forEach { (label, value) ->
                    Text("$label: $value", style = MaterialTheme.typography.bodySmall, modifier = Modifier.weight(1f))
                }
            }
        }
    }
}

private fun isIncubating(pet: PetInstanceWire): Boolean {
    if (!pet.evolutionStage.equals("egg", ignoreCase = true)) return false
    return hatchRemainingMs(pet.hatchAt) > 0
}

private fun hatchRemainingMs(hatchAt: String?): Long {
    if (hatchAt.isNullOrBlank()) return 0
    return try {
        val target = Instant.parse(hatchAt)
        (target.toEpochMilli() - System.currentTimeMillis()).coerceAtLeast(0)
    } catch (_: DateTimeParseException) {
        0
    }
}

private fun formatRemaining(ms: Long): String {
    val totalSec = ms / 1000
    val h = totalSec / 3600
    val m = (totalSec % 3600) / 60
    val s = totalSec % 60
    return "%02d:%02d:%02d".format(h, m, s)
}
