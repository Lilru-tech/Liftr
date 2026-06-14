package com.lilru.liftr.ui.pets

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import com.lilru.liftr.R
import com.lilru.liftr.data.PetEvolutionStages
import com.lilru.liftr.data.PetService
import com.lilru.liftr.data.PetSpeciesDetailWire
import com.lilru.liftr.ui.components.LiftrBackTopBar
import io.github.jan.supabase.SupabaseClient
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter

@Composable
fun PetSpeciesDetailScreen(
    supabase: SupabaseClient,
    petType: String,
    onBack: () -> Unit,
    showsDexStats: Boolean = true,
    modifier: Modifier = Modifier
) {
    var detail by remember { mutableStateOf<PetSpeciesDetailWire?>(null) }
    var loading by remember { mutableStateOf(true) }
    var error by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()

    fun load() {
        scope.launch {
            loading = detail == null
            error = null
            runCatching { PetService.fetchPetSpeciesDetail(supabase, petType) }
                .onSuccess { detail = it }
                .onFailure { error = it.message }
            loading = false
        }
    }

    LaunchedEffect(petType) { load() }

    Column(modifier = modifier.fillMaxSize()) {
        LiftrBackTopBar(onBack = onBack)

        when {
            loading -> {
                Box(
                    modifier = Modifier.fillMaxSize(),
                    contentAlignment = Alignment.Center
                ) {
                    CircularProgressIndicator()
                }
            }
            error != null -> {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(24.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    Text(
                        text = error.orEmpty(),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    Button(onClick = { load() }) {
                        Text(stringResource(R.string.pet_help_retry))
                    }
                }
            }
            detail != null -> {
                PetSpeciesDetailContent(
                    detail = detail!!,
                    showsDexStats = showsDexStats
                )
            }
        }
    }
}

@Composable
fun PetSpeciesDetailContent(
    detail: PetSpeciesDetailWire,
    showsDexStats: Boolean,
    modifier: Modifier = Modifier
) {
    val scroll = rememberScrollState()
    val dateFmt = remember {
        DateTimeFormatter.ofPattern("MMM d, yyyy").withZone(ZoneId.systemDefault())
    }

    Column(
        modifier = modifier
            .fillMaxWidth()
            .verticalScroll(scroll)
            .padding(horizontal = 16.dp, vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        Text(
            text = detail.displayName.ifBlank { detail.petType.replace('_', ' ').replaceFirstChar { it.titlecase() } },
            style = MaterialTheme.typography.titleLarge,
            fontWeight = FontWeight.SemiBold
        )
        if (detail.description.isNotBlank()) {
            Text(
                text = detail.description,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }

        Text(
            text = stringResource(R.string.pet_species_stages_headline),
            style = MaterialTheme.typography.titleMedium
        )
        Text(
            text = stringResource(R.string.pet_species_stages_intro),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )

        PetSpeciesStageGrid(detail = detail)

        if (showsDexStats && detail.dex != null) {
            val dex = detail.dex!!
            Surface(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(12.dp),
                color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.35f)
            ) {
                Column(
                    modifier = Modifier.padding(12.dp),
                    verticalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    Text(
                        text = stringResource(R.string.pet_species_arena_record),
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.SemiBold
                    )
                    Text(
                        text = stringResource(
                            R.string.pet_dex_battles_record,
                            dex.totalBattles,
                            dex.wins,
                            dex.losses,
                            dex.draws
                        ),
                        style = MaterialTheme.typography.bodyMedium
                    )
                    if (dex.raritiesSeen.isNotEmpty()) {
                        Text(
                            text = stringResource(
                                R.string.pet_species_rarities_faced,
                                dex.raritiesSeen.joinToString { it.replaceFirstChar { c -> c.titlecase() } }
                            ),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                    if (dex.stagesSeen.isNotEmpty()) {
                        Text(
                            text = stringResource(
                                R.string.pet_species_stages_faced,
                                dex.stagesSeen.joinToString { PetEvolutionStages.displayName(it) }
                            ),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                    dex.firstFoughtAt?.let { raw ->
                        runCatching { Instant.parse(raw) }.getOrNull()?.let { instant ->
                            Text(
                                text = stringResource(
                                    R.string.pet_species_first_fought,
                                    dateFmt.format(instant)
                                ),
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    }
                    dex.lastFoughtAt?.let { raw ->
                        runCatching { Instant.parse(raw) }.getOrNull()?.let { instant ->
                            Text(
                                text = stringResource(
                                    R.string.pet_species_last_fought,
                                    dateFmt.format(instant)
                                ),
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    }
                }
            }
        }
        Spacer(Modifier.height(24.dp))
    }
}

@Composable
fun PetSpeciesStageGrid(
    detail: PetSpeciesDetailWire,
    modifier: Modifier = Modifier
) {
    LazyVerticalGrid(
        columns = GridCells.Fixed(3),
        modifier = modifier
            .fillMaxWidth()
            .height(280.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
        userScrollEnabled = false
    ) {
        items(PetEvolutionStages.ordered) { stage ->
            PetSpeciesStageCard(
                detail = detail,
                stage = stage
            )
        }
    }
}

@Composable
fun PetSpeciesStageCard(
    detail: PetSpeciesDetailWire,
    stage: String,
    modifier: Modifier = Modifier
) {
    val discovered = detail.isStageDiscovered(stage)

    Surface(
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(12.dp),
        color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.35f)
    ) {
        Column(
            modifier = Modifier.padding(8.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(64.dp)
                    .clip(RoundedCornerShape(10.dp)),
                contentAlignment = Alignment.Center
            ) {
                if (discovered) {
                    AsyncImage(
                        model = detail.imageUrlForStage(stage),
                        contentDescription = PetEvolutionStages.displayName(stage),
                        modifier = Modifier.fillMaxSize(),
                        contentScale = ContentScale.Fit
                    )
                } else {
                    Box(
                        modifier = Modifier
                            .fillMaxSize()
                            .background(Color.Black.copy(alpha = 0.35f)),
                        contentAlignment = Alignment.Center
                    ) {
                        Icon(
                            imageVector = Icons.Filled.Lock,
                            contentDescription = null,
                            tint = Color.White.copy(alpha = 0.7f),
                            modifier = Modifier.size(24.dp)
                        )
                    }
                }
            }
            Text(
                text = PetEvolutionStages.displayName(stage),
                style = MaterialTheme.typography.labelSmall,
                fontWeight = FontWeight.SemiBold,
                color = if (discovered) {
                    MaterialTheme.colorScheme.onSurface
                } else {
                    MaterialTheme.colorScheme.onSurfaceVariant
                }
            )
        }
    }
}
