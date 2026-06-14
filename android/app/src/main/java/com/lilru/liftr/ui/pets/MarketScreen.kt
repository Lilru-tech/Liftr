package com.lilru.liftr.ui.pets

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Paid
import androidx.compose.material.icons.filled.ShoppingBag
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.material3.Badge
import androidx.compose.material3.BadgedBox
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import com.lilru.liftr.R
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import coil.compose.AsyncImage
import com.lilru.liftr.data.CoinManager
import com.lilru.liftr.data.PetFullDataWire
import com.lilru.liftr.data.PetMarketItemWire
import com.lilru.liftr.data.PetService
import com.lilru.liftr.prefs.LiftrPreferences
import com.lilru.liftr.ui.theme.liftrAppBackgroundGradient
import io.github.jan.supabase.SupabaseClient

private val FOOD_TYPES = setOf("food_baby", "food_kid", "food_teen", "food_adult", "food_elder")

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MarketScreen(
    supabase: SupabaseClient,
    onBack: () -> Unit,
    onOpenMyItems: () -> Unit,
    modifier: Modifier = Modifier
) {
    val vm: MarketViewModel = viewModel(factory = MarketViewModelFactory(supabase))
    val ui by vm.uiState.collectAsStateWithLifecycle()
    val unseenMyItemsCount by PetMarketPurchaseFeedback.unseenMyItemsCount.collectAsStateWithLifecycle()
    var selected by remember { mutableStateOf<PetMarketItemWire?>(null) }
    var showPetHelp by remember { mutableStateOf(false) }
    val petHelpSheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val backgroundTheme = LiftrPreferences.backgroundTheme(LocalContext.current.applicationContext)

    Box(
        modifier = modifier
            .fillMaxSize()
            .liftrAppBackgroundGradient(backgroundTheme)
    ) {
        Scaffold(
            modifier = Modifier.fillMaxSize(),
            containerColor = Color.Transparent,
            topBar = {
                TopAppBar(
                    title = { Text("Market") },
                    navigationIcon = {
                        IconButton(onClick = onBack) {
                            Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = null)
                        }
                    },
                    actions = {
                        IconButton(onClick = { showPetHelp = true }) {
                            Icon(
                                imageVector = Icons.Filled.Info,
                                contentDescription = stringResource(R.string.pet_help_info_content_description)
                            )
                        }
                        IconButton(onClick = {
                            PetMarketPurchaseFeedback.clearBadge()
                            onOpenMyItems()
                        }) {
                            if (unseenMyItemsCount > 0) {
                                BadgedBox(
                                    badge = { Badge { Text(unseenMyItemsCount.toString()) } }
                                ) {
                                    Icon(Icons.Filled.ShoppingBag, contentDescription = null)
                                }
                            } else {
                                Icon(Icons.Filled.ShoppingBag, contentDescription = null)
                            }
                        }
                    },
                    colors = androidx.compose.material3.TopAppBarDefaults.topAppBarColors(
                        containerColor = Color.Transparent
                    )
                )
            }
        ) { padding ->
            when {
                ui.loading && ui.items.isEmpty() -> {
                    PetMarketSkeleton(modifier = Modifier.padding(padding).padding(top = 8.dp))
                }
                ui.error != null && ui.items.isEmpty() -> {
                    Text(
                        text = ui.error.orEmpty(),
                        color = MaterialTheme.colorScheme.error,
                        modifier = Modifier.padding(padding).padding(24.dp)
                    )
                }
                else -> {
                    LazyColumn(
                        modifier = Modifier
                            .fillMaxSize()
                            .padding(padding),
                        verticalArrangement = Arrangement.spacedBy(16.dp)
                    ) {
                        item {
                            Surface(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(horizontal = 16.dp),
                                shape = RoundedCornerShape(12.dp),
                                tonalElevation = 2.dp
                            ) {
                                Row(
                                    modifier = Modifier.padding(16.dp),
                                    horizontalArrangement = Arrangement.SpaceBetween,
                                    verticalAlignment = Alignment.CenterVertically
                                ) {
                                    Row(
                                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                                        verticalAlignment = Alignment.CenterVertically
                                    ) {
                                        Icon(Icons.Filled.Paid, contentDescription = null, tint = Color(0xFFFFC107))
                                        Text("${CoinManager.balance} coins", fontWeight = FontWeight.Bold)
                                    }
                                    ui.petData?.energy?.let { energy ->
                                        PetEnergyBadge(
                                            energy = energy,
                                            horizontalAlignment = Alignment.End
                                        )
                                    }
                                }
                            }
                        }

                        val visible = ui.items.filter {
                            PetMarketVisibility.shouldShowMarketItem(it, ui.petData)
                        }
                        val grouped = visible.groupBy { it.category }.toSortedMap()
                        grouped.forEach { (category, items) ->
                            item {
                                Text(
                                    PetMarketVisibility.categoryTitle(category),
                                    style = MaterialTheme.typography.titleMedium,
                                    fontWeight = FontWeight.Bold,
                                    modifier = Modifier.padding(horizontal = 16.dp)
                                )
                            }
                            item {
                                LazyRow(
                                    modifier = Modifier.fillMaxWidth(),
                                    horizontalArrangement = Arrangement.spacedBy(16.dp),
                                    contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 16.dp)
                                ) {
                                    items(items, key = { it.itemType }) { item ->
                                        val presentation = PetMarketItemPresentationFactory.make(item, ui.petData)
                                        PetMarketItemCard(
                                            item = item,
                                            userCoins = CoinManager.balance,
                                            onClick = { selected = item },
                                            effectivePrice = presentation.effectivePrice,
                                            subtitle = presentation.subtitle,
                                            imagePath = presentation.imagePath
                                        )
                                    }
                                }
                            }
                        }

                        item { Box(modifier = Modifier.height(20.dp)) }
                    }
                }
            }
        }

        if (showPetHelp) {
            ModalBottomSheet(
                onDismissRequest = { showPetHelp = false },
                sheetState = petHelpSheetState
            ) {
                PetHelpSheetContent(
                    onClose = { showPetHelp = false }
                )
            }
        }

        selected?.let { item ->
            Box(modifier = Modifier.fillMaxSize()) {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .background(Color.Black.copy(alpha = 0.4f))
                        .clickable { selected = null }
                )
                if (item.itemType == "pet_rarity_upgrade") {
                    RarityUpgradePurchaseOverlay(
                        item = item,
                        petData = ui.petData,
                        balance = CoinManager.balance,
                        isBuying = ui.upgradingRarity,
                        errorMessage = ui.error,
                        onClose = { selected = null },
                        onConfirm = { vm.upgradeRarity { selected = null } },
                        modifier = Modifier.align(Alignment.Center)
                    )
                } else if (item.itemType == "pet_energy_capacity") {
                    EnergyCapacityUpgradeOverlay(
                        item = item,
                        petData = ui.petData,
                        balance = CoinManager.balance,
                        isBuying = ui.upgradingEnergy,
                        errorMessage = ui.error,
                        onClose = { selected = null },
                        onConfirm = { vm.upgradeEnergyCapacity { selected = null } },
                        modifier = Modifier.align(Alignment.Center)
                    )
                } else {
                    MarketPurchaseOverlay(
                        item = item,
                        balance = CoinManager.balance,
                        onClose = { selected = null },
                        onBuy = { qty ->
                            vm.buy(item.itemType, qty) { selected = null }
                        },
                        modifier = Modifier.align(Alignment.Center)
                    )
                }
            }
        }
    }
}

@Composable
private fun MarketPurchaseOverlay(
    item: PetMarketItemWire,
    balance: Int,
    onClose: () -> Unit,
    onBuy: (Int) -> Unit,
    modifier: Modifier = Modifier
) {
    val isFood = item.itemType in FOOD_TYPES
    Surface(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 24.dp),
        shape = RoundedCornerShape(20.dp),
        tonalElevation = 8.dp
    ) {
        Column(
            modifier = Modifier.padding(24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            AsyncImage(
                model = PetService.marketImageUrl(item.imagePath),
                contentDescription = null,
                modifier = Modifier.height(120.dp)
            )
            Text(item.displayName, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
            Text(
                item.description,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center
            )
            Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
                Text("Price: ${item.price}", fontWeight = FontWeight.SemiBold)
                Icon(Icons.Filled.Paid, contentDescription = null, tint = Color(0xFFFFC107), modifier = Modifier.size(16.dp))
            }
            Text(
                color = if (item.price > balance) Color.Red else Color(0xFF22C55E),
                text = if (item.price > balance) "Not enough coins" else "You can afford this"
            )

            if (isFood) {
                Text("Select quantity", style = MaterialTheme.typography.labelLarge)
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    listOf(1, 5, 10, 25).forEach { qty ->
                        val total = item.price * qty
                        OutlinedButton(
                            onClick = { onBuy(qty) },
                            enabled = total <= balance
                        ) {
                            Text("$qty")
                        }
                    }
                }
            } else {
                Button(
                    onClick = { onBuy(1) },
                    enabled = item.price <= balance,
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text("Buy")
                }
            }

            TextButton(onClick = onClose) { Text("Close") }
        }
    }
}

