package com.lilru.liftr.ui.pets

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import coil.compose.AsyncImage
import com.lilru.liftr.data.PetService
import com.lilru.liftr.prefs.LiftrPreferences
import com.lilru.liftr.ui.theme.liftrAppBackgroundGradient
import io.github.jan.supabase.SupabaseClient

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PetUserItemsScreen(
    supabase: SupabaseClient,
    onBack: () -> Unit,
    modifier: Modifier = Modifier
) {
    val context = LocalContext.current
    val vm: PetUserItemsViewModel = viewModel(factory = PetUserItemsViewModelFactory(supabase))
    val ui by vm.uiState.collectAsStateWithLifecycle()
    var selected by remember { mutableStateOf<PetInventoryDisplayItem?>(null) }
    val backgroundTheme = LiftrPreferences.backgroundTheme(context.applicationContext)

    val displayItems = remember(ui.petData, ui.catalog) {
        ui.petData?.inventory.orEmpty()
            .mapNotNull { PetInventoryDisplayItem.from(it, ui.catalog) }
    }
    val grouped = remember(displayItems) {
        displayItems.groupBy { it.category }.toSortedMap()
    }

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
                    title = { Text("My Items") },
                    navigationIcon = {
                        IconButton(onClick = onBack) {
                            Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = null)
                        }
                    },
                    colors = androidx.compose.material3.TopAppBarDefaults.topAppBarColors(
                        containerColor = Color.Transparent
                    )
                )
            }
        ) { padding ->
            when {
                ui.loading && ui.petData == null -> {
                    CircularProgressIndicator(modifier = Modifier.padding(padding).padding(24.dp))
                }
                ui.error != null && displayItems.isEmpty() -> {
                    Text(
                        ui.error.orEmpty(),
                        color = MaterialTheme.colorScheme.error,
                        modifier = Modifier.padding(padding).padding(24.dp)
                    )
                }
                displayItems.isEmpty() -> {
                    Text(
                        "You don't own any pet items yet.",
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(padding).padding(24.dp)
                    )
                }
                else -> {
                    LazyColumn(
                        modifier = Modifier
                            .fillMaxSize()
                            .padding(padding),
                        verticalArrangement = Arrangement.spacedBy(16.dp),
                        contentPadding = PaddingValues(vertical = 16.dp)
                    ) {
                        grouped.forEach { (category, categoryItems) ->
                            item {
                                Text(
                                    PetMarketVisibility.categoryTitle(category),
                                    style = MaterialTheme.typography.titleMedium,
                                    fontWeight = FontWeight.SemiBold,
                                    modifier = Modifier.padding(horizontal = 16.dp)
                                )
                            }
                            items(categoryItems.chunked(3)) { rowItems ->
                                Row(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .padding(horizontal = 16.dp),
                                    horizontalArrangement = Arrangement.spacedBy(16.dp)
                                ) {
                                    rowItems.forEach { item ->
                                        PetInventoryItemCard(item = item) { selected = item }
                                    }
                                }
                            }
                        }
                    }
                }
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
                PetInventoryItemOverlay(
                    item = item,
                    hasIncubator = PetMarketVisibility.hasIncubator(ui.petData?.inventory.orEmpty()),
                    canIncubate = PetMarketVisibility.canIncubate(ui.petData),
                    incubating = ui.incubating,
                    onClose = { selected = null },
                    onIncubate = { vm.startIncubation(context) { selected = null } },
                    modifier = Modifier.align(Alignment.Center)
                )
            }
        }
    }
}

@Composable
private fun PetInventoryItemOverlay(
    item: PetInventoryDisplayItem,
    hasIncubator: Boolean,
    canIncubate: Boolean,
    incubating: Boolean,
    onClose: () -> Unit,
    onIncubate: () -> Unit,
    modifier: Modifier = Modifier
) {
    val isEgg = item.itemType == "pet_egg"
    val isIncubator = item.itemType == "incubator"

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
            Text(
                if (item.quantity > 1) "Owned: ${item.quantity}" else "Already bought",
                style = MaterialTheme.typography.labelLarge,
                fontWeight = FontWeight.SemiBold
            )

            if (isEgg) {
                Button(
                    onClick = onIncubate,
                    enabled = canIncubate && !incubating,
                    modifier = Modifier.fillMaxWidth()
                ) {
                    if (incubating) {
                        CircularProgressIndicator(modifier = Modifier.padding(end = 8.dp).height(18.dp))
                    }
                    Text("Incubate")
                }
                if (!hasIncubator) {
                    Text(
                        "You need an Egg Incubator to incubate this egg.",
                        color = MaterialTheme.colorScheme.error,
                        style = MaterialTheme.typography.bodySmall,
                        textAlign = TextAlign.Center
                    )
                }
            } else if (isIncubator) {
                Text(
                    "Used when you incubate your Mysterious Egg.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    textAlign = TextAlign.Center
                )
            }

            TextButton(onClick = onClose) { Text("Close") }
        }
    }
}
