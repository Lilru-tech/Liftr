package com.lilru.liftr.ui.pets

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.platform.LocalContext
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import coil.compose.AsyncImage
import com.lilru.liftr.data.CoinManager
import com.lilru.liftr.data.PetInstanceWire
import com.lilru.liftr.data.PetService
import com.lilru.liftr.data.PetStatsWire
import io.github.jan.supabase.SupabaseClient
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

private val FOOD_TYPES = listOf("food_baby", "food_kid", "food_teen", "food_adult", "food_elder")

@Composable
fun PetDetailScreen(
    vm: PetViewModel,
    supabase: SupabaseClient,
    onClose: () -> Unit,
    modifier: Modifier = Modifier
) {
    val context = LocalContext.current
    val ui by vm.uiState.collectAsStateWithLifecycle()
    var selectedTab by remember { mutableIntStateOf(0) }

    LaunchedEffect(Unit) {
        vm.load()
        vm.reloadLogs()
        CoinManager.refreshBalanceAfterMutation(supabase)
        vm.startPollingIfNeeded()
    }

    Column(
        modifier = modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
            TextButton(onClick = onClose) { Text("Close") }
        }

        if (ui.loading && ui.data == null) {
            CircularProgressIndicator()
            return@Column
        }

        val pet = ui.data?.pet ?: run {
            Text("No active pet yet.", color = MaterialTheme.colorScheme.onSurfaceVariant)
            return@Column
        }

        PetHeader(
            pet = pet,
            onSaveName = { vm.updateName(it) },
            modifier = Modifier.fillMaxWidth()
        )

        PetAsyncImage(
            pet = pet,
            modifier = Modifier.align(Alignment.CenterHorizontally),
            size = 120.dp
        )

        if (pet.evolutionStage.equals("egg", ignoreCase = true)) {
            EggSection(
                pet = pet,
                balance = CoinManager.balance,
                rerolling = ui.rerolling,
                onReroll = { vm.rerollEgg(context) }
            )
            HorizontalDivider(modifier = Modifier.padding(top = 8.dp))
            PetLogsSection(
                logs = ui.logs,
                hasMore = ui.hasMoreLogs,
                onLoadMore = { vm.loadMoreLogs() },
                onDeleteAll = { vm.deleteAllLogs() }
            )
        } else {
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
            HorizontalDivider()
            SingleChoiceSegmentedButtonRow(modifier = Modifier.fillMaxWidth()) {
                SegmentedButton(
                    selected = selectedTab == 0,
                    onClick = { selectedTab = 0 },
                    shape = SegmentedButtonDefaults.itemShape(index = 0, count = 2)
                ) { Text("Inventory") }
                SegmentedButton(
                    selected = selectedTab == 1,
                    onClick = { selectedTab = 1 },
                    shape = SegmentedButtonDefaults.itemShape(index = 1, count = 2)
                ) { Text("Logs") }
            }
            if (selectedTab == 0) {
                FoodSection(
                    inventory = ui.data?.inventory.orEmpty(),
                    feeding = ui.feeding,
                    onFeed = { vm.feed(it) }
                )
            } else {
                PetLogsSection(
                    logs = ui.logs,
                    hasMore = ui.hasMoreLogs,
                    onLoadMore = { vm.loadMoreLogs() },
                    onDeleteAll = { vm.deleteAllLogs() }
                )
            }
        }

        ui.error?.let {
            Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
        }
    }
}

@Composable
private fun PetHeader(
    pet: PetInstanceWire,
    onSaveName: (String) -> Unit,
    modifier: Modifier = Modifier
) {
    var editing by remember { mutableStateOf(false) }
    var draft by remember(pet.customName) { mutableStateOf(pet.customName.orEmpty()) }

    Column(
        modifier = modifier,
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        if (editing) {
            OutlinedTextField(
                value = draft,
                onValueChange = { draft = it },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true
            )
            Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                TextButton(onClick = { editing = false }) { Text("Cancel") }
                TextButton(onClick = {
                    onSaveName(draft)
                    editing = false
                }) { Text("Save") }
            }
        } else {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.Center
            ) {
                Text(
                    pet.customName?.takeIf { it.isNotBlank() } ?: titleForStage(pet.evolutionStage),
                    style = MaterialTheme.typography.headlineSmall,
                    fontWeight = FontWeight.Bold
                )
                TextButton(onClick = { editing = true }) {
                    Icon(
                        imageVector = Icons.Filled.Edit,
                        contentDescription = "Edit name",
                        modifier = Modifier.size(18.dp)
                    )
                }
            }
            PetRarityBadge(pet.rarity)
        }
    }
}

@Composable
private fun EggSection(
    pet: PetInstanceWire,
    balance: Int,
    rerolling: Boolean,
    onReroll: () -> Unit
) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        when {
            PetService.isPendingHatch(pet) -> {
                Text("Hatching soon...", fontWeight = FontWeight.SemiBold, color = Color(0xFFFF9800))
            }
            !pet.hatchAt.isNullOrBlank() -> {
                Text("Will hatch at: ${formatHatchAt(pet.hatchAt)}", style = MaterialTheme.typography.bodyMedium)
            }
        }
        Text(
            "Type: ${pet.petType.replace('_', ' ').replaceFirstChar { it.uppercase() }}",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Text("Your coins: $balance", style = MaterialTheme.typography.bodySmall, color = Color(0xFFFFC107))
        Button(
            onClick = onReroll,
            enabled = !rerolling && !PetService.isPendingHatch(pet),
            modifier = Modifier.fillMaxWidth(),
            colors = androidx.compose.material3.ButtonDefaults.buttonColors(
                containerColor = Color(0x33EF4444),
                contentColor = Color(0xFFEF4444)
            )
        ) {
            if (rerolling) CircularProgressIndicator(modifier = Modifier.padding(end = 8.dp).size(18.dp))
            Icon(Icons.Filled.Refresh, contentDescription = null, modifier = Modifier.padding(end = 4.dp))
            Text("Change Pet")
        }
        Text(
            "Costs ${PetService.rerollCost(pet.rerollCount)} coins. Rerolls species and rarity.",
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
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
        Text("Current stage: ${pet.evolutionStage.replaceFirstChar { it.uppercase() }}")
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
    }
}

@Composable
private fun FoodSection(
    inventory: List<com.lilru.liftr.data.PetInventoryWire>,
    feeding: Boolean,
    onFeed: (String) -> Unit
) {
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

private fun titleForStage(stage: String): String = when (stage.lowercase()) {
    "egg" -> "Your Egg"
    "baby" -> "Your Baby Pet"
    "kid" -> "Your Kid Pet"
    "teen" -> "Your Teen Pet"
    "adult" -> "Your Adult Pet"
    "elder" -> "Your Elder Pet"
    else -> "Your Pet"
}

private fun formatHatchAt(raw: String?): String = runCatching {
    val dt = Instant.parse(raw).atZone(ZoneId.systemDefault())
    DateTimeFormatter.ofPattern("d/M/yyyy, HH:mm", Locale.getDefault()).format(dt)
}.getOrDefault(raw.orEmpty())
