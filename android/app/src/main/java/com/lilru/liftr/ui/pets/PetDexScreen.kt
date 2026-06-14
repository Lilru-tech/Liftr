package com.lilru.liftr.ui.pets

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Clear
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
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
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import coil.compose.AsyncImage
import com.lilru.liftr.R
import com.lilru.liftr.data.PetDexSpeciesEntryWire
import com.lilru.liftr.data.PetService
import com.lilru.liftr.ui.components.LiftrBackTopBar
import io.github.jan.supabase.SupabaseClient

@Composable
fun PetDexScreen(
    supabase: SupabaseClient,
    onBack: () -> Unit,
    modifier: Modifier = Modifier
) {
    val vm: PetDexViewModel = viewModel(factory = PetDexViewModelFactory(supabase))
    val ui by vm.uiState.collectAsStateWithLifecycle()
    var searchText by remember { mutableStateOf("") }
    var selectedSpecies by remember { mutableStateOf<PetDexSpeciesEntryWire?>(null) }

    if (selectedSpecies != null) {
        PetSpeciesDetailScreen(
            supabase = supabase,
            petType = selectedSpecies!!.petType,
            onBack = { selectedSpecies = null },
            showsDexStats = true
        )
        return
    }

    val query = searchText.trim().lowercase()
    val filtered = remember(ui.data, query) {
        val all = ui.data?.species.orEmpty()
        if (query.isEmpty()) all
        else all.filter { row ->
            row.displayName.lowercase().contains(query)
                || row.petType.lowercase().contains(query)
                || row.description.lowercase().contains(query)
        }
    }

    Column(modifier = modifier.fillMaxSize()) {
        LiftrBackTopBar(
            onBack = onBack,
            title = stringResource(R.string.pet_dex_title)
        )

        when {
            ui.loading -> {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator()
                }
            }
            ui.error != null -> {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(24.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    Text(ui.error.orEmpty(), color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Button(onClick = { vm.retry() }) {
                        Text(stringResource(R.string.pet_help_retry))
                    }
                }
            }
            ui.data != null -> {
                val data = ui.data!!
                LazyColumn(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(horizontal = 16.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    item {
                        Text(
                            text = stringResource(
                                R.string.pet_dex_progress,
                                data.speciesDiscovered,
                                data.totalSpecies
                            ),
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.SemiBold
                        )
                    }
                    item {
                        Text(
                            text = stringResource(
                                R.string.pet_dex_collection_stats,
                                data.raritiesDiscovered,
                                data.totalRarities,
                                data.stagesDiscovered,
                                data.totalFightableStages
                            ),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                    if (ui.rarities.isNotEmpty()) {
                        item {
                            PetRarityGuideSection(rarities = ui.rarities)
                        }
                    }
                    item {
                        Spacer(Modifier.height(4.dp))
                    }
                    item {
                        OutlinedTextField(
                            value = searchText,
                            onValueChange = { searchText = it },
                            modifier = Modifier.fillMaxWidth(),
                            placeholder = { Text(stringResource(R.string.pet_dex_search)) },
                            leadingIcon = { Icon(Icons.Filled.Search, contentDescription = null) },
                            trailingIcon = {
                                if (searchText.isNotEmpty()) {
                                    IconButton(onClick = { searchText = "" }) {
                                        Icon(Icons.Filled.Clear, contentDescription = null)
                                    }
                                }
                            },
                            singleLine = true,
                            shape = RoundedCornerShape(12.dp)
                        )
                    }
                    if (filtered.isEmpty()) {
                        item {
                            Text(
                                text = stringResource(R.string.pet_dex_search_empty),
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    } else {
                        items(filtered.chunked(2), key = { chunk -> chunk.first().petType }) { rowSpecies ->
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.spacedBy(12.dp)
                            ) {
                                rowSpecies.forEach { row ->
                                    PetDexSpeciesCard(
                                        row = row,
                                        modifier = Modifier
                                            .weight(1f)
                                            .clickable { selectedSpecies = row }
                                    )
                                }
                                if (rowSpecies.size == 1) {
                                    Spacer(modifier = Modifier.weight(1f))
                                }
                            }
                        }
                    }
                    item {
                        Spacer(Modifier.height(16.dp))
                    }
                }
            }
        }
    }
}

@Composable
private fun PetDexSpeciesCard(
    row: PetDexSpeciesEntryWire,
    modifier: Modifier = Modifier
) {
    Surface(
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(12.dp),
        color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.35f)
    ) {
        Column(
            modifier = Modifier.padding(10.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(72.dp),
                contentAlignment = Alignment.Center
            ) {
                if (row.isDiscovered) {
                    AsyncImage(
                        model = row.imageEgg?.takeIf { it.isNotBlank() }
                            ?: PetService.petImageUrl(row.petType, "egg"),
                        contentDescription = null,
                        modifier = Modifier.fillMaxSize()
                    )
                } else {
                    Box(
                        modifier = Modifier
                            .fillMaxSize()
                            .background(Color.Black.copy(alpha = 0.45f), RoundedCornerShape(10.dp)),
                        contentAlignment = Alignment.Center
                    ) {
                        Text(
                            text = stringResource(R.string.pet_dex_unknown),
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.Bold,
                            color = Color.White.copy(alpha = 0.75f)
                        )
                    }
                }
            }
            Text(
                text = if (row.isDiscovered) {
                    row.displayName.ifBlank {
                        row.petType.replace('_', ' ').replaceFirstChar { it.titlecase() }
                    }
                } else {
                    stringResource(R.string.pet_dex_unknown)
                },
                style = MaterialTheme.typography.labelLarge,
                fontWeight = FontWeight.SemiBold,
                maxLines = 2
            )
            if (row.isDiscovered) {
                Text(
                    text = stringResource(
                        R.string.pet_dex_battles_record,
                        row.totalBattles,
                        row.wins,
                        row.losses,
                        row.draws
                    ),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }
}
