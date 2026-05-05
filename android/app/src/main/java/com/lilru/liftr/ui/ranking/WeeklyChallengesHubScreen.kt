package com.lilru.liftr.ui.ranking

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.lilru.liftr.R
import io.github.jan.supabase.SupabaseClient
import java.time.Instant
import java.time.ZoneId

private enum class HubCategoryFilter { ALL, CARDIO, STRENGTH, SPORT }

private enum class HubCadenceFilter { ALL, WEEK, MONTH, ONCE }

private enum class HubParticipationFilter { ALL, ON_PODIUM }

@Composable
fun WeeklyChallengesHubScreen(
    supabase: SupabaseClient,
    viewModelKey: String,
    onOpenChallenge: (String) -> Unit,
    onClose: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val vm: WeeklyChallengesViewModel = viewModel(
        key = "weekly-challenges-$viewModelKey",
        factory = WeeklyChallengesViewModelFactory(supabase)
    )
    val st by vm.state.collectAsStateWithLifecycle()

    var searchText by remember { mutableStateOf("") }
    var categoryFilter by remember { mutableStateOf(HubCategoryFilter.ALL) }
    var cadenceFilter by remember { mutableStateOf(HubCadenceFilter.ALL) }
    var participationFilter by remember { mutableStateOf(HubParticipationFilter.ALL) }

    val filtered = remember(st.items, searchText, categoryFilter, cadenceFilter, participationFilter) {
        var rows = st.items
        val q = searchText.trim().lowercase()
        if (q.isNotEmpty()) {
            rows = rows.filter {
                it.title.lowercase().contains(q) ||
                    it.description.lowercase().contains(q) ||
                    it.templateCode.lowercase().contains(q)
            }
        }
        when (categoryFilter) {
            HubCategoryFilter.ALL -> Unit
            HubCategoryFilter.CARDIO -> rows = rows.filter { it.resolvedCategory() == "cardio" }
            HubCategoryFilter.STRENGTH -> rows = rows.filter { it.resolvedCategory() == "strength" }
            HubCategoryFilter.SPORT -> rows = rows.filter { it.resolvedCategory() == "sport" }
        }
        when (cadenceFilter) {
            HubCadenceFilter.ALL -> Unit
            HubCadenceFilter.WEEK -> rows = rows.filter { it.cadence.equals("week", ignoreCase = true) }
            HubCadenceFilter.MONTH -> rows = rows.filter { it.cadence.equals("month", ignoreCase = true) }
            HubCadenceFilter.ONCE -> rows = rows.filter { it.cadence.equals("once", ignoreCase = true) }
        }
        when (participationFilter) {
            HubParticipationFilter.ALL -> Unit
            HubParticipationFilter.ON_PODIUM -> rows = rows.filter { it.viewerClaimed }
        }
        rows
    }

    Column(modifier = modifier.fillMaxSize()) {
        com.lilru.liftr.ui.components.LiftrBackTopBar(
            onBack = onClose,
            title = stringResource(R.string.ranking_challenges_hub_title),
            modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp)
        )
        Text(
            text = stringResource(R.string.ranking_challenges_hub_blurb),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp)
        )
        OutlinedTextField(
            value = searchText,
            onValueChange = { searchText = it },
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 4.dp),
            placeholder = { Text(stringResource(R.string.ranking_challenges_search_placeholder)) },
            singleLine = true,
            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
            keyboardActions = KeyboardActions.Default,
        )
        filterChipRow(
            label = stringResource(R.string.ranking_challenges_filter_type),
            chips = listOf(
                HubChip("All", categoryFilter == HubCategoryFilter.ALL) { categoryFilter = HubCategoryFilter.ALL },
                HubChip("Cardio", categoryFilter == HubCategoryFilter.CARDIO) { categoryFilter = HubCategoryFilter.CARDIO },
                HubChip("Strength", categoryFilter == HubCategoryFilter.STRENGTH) { categoryFilter = HubCategoryFilter.STRENGTH },
                HubChip("Sport", categoryFilter == HubCategoryFilter.SPORT) { categoryFilter = HubCategoryFilter.SPORT },
            )
        )
        filterChipRow(
            label = stringResource(R.string.ranking_challenges_filter_when),
            chips = listOf(
                HubChip("All", cadenceFilter == HubCadenceFilter.ALL) { cadenceFilter = HubCadenceFilter.ALL },
                HubChip("Weekly", cadenceFilter == HubCadenceFilter.WEEK) { cadenceFilter = HubCadenceFilter.WEEK },
                HubChip("Monthly", cadenceFilter == HubCadenceFilter.MONTH) { cadenceFilter = HubCadenceFilter.MONTH },
                HubChip("Open", cadenceFilter == HubCadenceFilter.ONCE) { cadenceFilter = HubCadenceFilter.ONCE },
            )
        )
        filterChipRow(
            label = stringResource(R.string.ranking_challenges_filter_you),
            chips = listOf(
                HubChip(
                    stringResource(R.string.ranking_challenges_participation_all),
                    participationFilter == HubParticipationFilter.ALL
                ) { participationFilter = HubParticipationFilter.ALL },
                HubChip(
                    stringResource(R.string.ranking_challenges_participation_on_podium),
                    participationFilter == HubParticipationFilter.ON_PODIUM
                ) { participationFilter = HubParticipationFilter.ON_PODIUM },
            )
        )
        when {
            st.loading && st.items.isEmpty() -> {
                CircularProgressIndicator(
                    modifier = Modifier
                        .padding(32.dp)
                        .align(Alignment.CenterHorizontally)
                )
            }
            st.error != null && st.items.isEmpty() -> {
                Text(
                    text = st.error ?: "",
                    color = MaterialTheme.colorScheme.error,
                    modifier = Modifier.padding(16.dp)
                )
            }
            st.items.isEmpty() -> {
                Text(
                    text = stringResource(R.string.ranking_weekly_challenges_none),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(16.dp)
                )
            }
            filtered.isEmpty() -> {
                Text(
                    text = stringResource(R.string.ranking_challenges_no_filter_match),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(16.dp)
                )
            }
            else -> {
                LazyColumn(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(horizontal = 12.dp),
                    verticalArrangement = Arrangement.spacedBy(10.dp)
                ) {
                    items(filtered, key = { it.instanceId }) { row ->
                        Card(
                            onClick = { onOpenChallenge(row.instanceId) },
                            modifier = Modifier.fillMaxWidth(),
                            colors = CardDefaults.cardColors(
                                containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.55f)
                            ),
                        ) {
                            Column(
                                Modifier.padding(12.dp),
                                verticalArrangement = Arrangement.spacedBy(6.dp)
                            ) {
                                Text(
                                    text = cadenceLabel(row.cadence),
                                    style = MaterialTheme.typography.labelSmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                                Text(
                                    row.title,
                                    style = MaterialTheme.typography.titleSmall,
                                    color = MaterialTheme.colorScheme.onSurface
                                )
                                if (row.viewerClaimed && row.viewerRank != null) {
                                    Text(
                                        stringResource(R.string.ranking_challenges_you_on_podium, row.viewerRank),
                                        style = MaterialTheme.typography.labelSmall,
                                        color = MaterialTheme.colorScheme.primary
                                    )
                                }
                                Text(
                                    stringResource(
                                        R.string.ranking_challenges_slots_caption,
                                        row.claimsCount.toInt(),
                                        row.maxWinners,
                                        challengePeriodEndCaption(row),
                                    ),
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

private data class HubChip(val title: String, val selected: Boolean, val onClick: () -> Unit)

@Composable
private fun filterChipRow(
    label: String,
    chips: List<HubChip>,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .horizontalScroll(rememberScrollState())
            .padding(horizontal = 12.dp, vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(end = 4.dp)
        )
        chips.forEach { chip ->
            FilterChip(
                selected = chip.selected,
                onClick = chip.onClick,
                label = { Text(chip.title) }
            )
        }
    }
}

@Composable
private fun challengePeriodEndCaption(row: WeeklyChallengeListRowUi): String {
    if (row.cadence.equals("once", ignoreCase = true)) {
        return stringResource(R.string.ranking_challenges_no_expiry)
    }
    val iso = row.periodEndIso
    if (iso.isEmpty()) return stringResource(R.string.ranking_challenges_no_expiry)
    val z = runCatching { Instant.parse(iso).atZone(ZoneId.systemDefault()) }.getOrNull()
        ?: return iso.take(10)
    if (z.year >= 2090) {
        return stringResource(R.string.ranking_challenges_no_expiry)
    }
    return stringResource(R.string.ranking_challenges_ends_on, z.toLocalDate().toString())
}

private fun cadenceLabel(cadence: String): String = when (cadence.lowercase()) {
    "week" -> "Weekly"
    "month" -> "Monthly"
    "once" -> "Open"
    else -> cadence.replaceFirstChar { it.uppercase() }
}
