package com.lilru.liftr.ui.profile

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilterChip
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.lilru.liftr.R
import com.lilru.liftr.ui.components.LiftrBackTopBar
import io.github.jan.supabase.SupabaseClient

@Composable
fun ProfilePrsListScreen(
    supabase: SupabaseClient,
    userId: String,
    username: String,
    showCompare: Boolean,
    onCompare: (() -> Unit)?,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
    /** Dentro de la pestaña PRs del perfil (sin botón Atrás ni padding de pantalla completa). */
    embedded: Boolean = false
) {
    val vm: ProfilePrsListViewModel = viewModel(
        key = "profile-prs-list-$userId",
        factory = ProfilePrsListViewModelFactory(supabase, userId)
    )
    val st by vm.uiState.collectAsStateWithLifecycle()
    var showSearch by remember { mutableStateOf(false) }
    val sections = remember(st.rows, st.searchQuery) {
        ProfilePrsGrouping.buildSections(st.rows, st.searchQuery)
    }
    Column(
        modifier = modifier
            .fillMaxSize()
            .then(if (embedded) Modifier else Modifier.statusBarsPadding())
            .padding(if (embedded) 4.dp else 12.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        if (!embedded) {
            LiftrBackTopBar(onBack = onBack)
        }
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.Top
        ) {
            val titleUser = if (username.isNotBlank()) "@$username" else "—"
            Text(
                stringResource(R.string.profile_prs_list_title, titleUser),
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
                modifier = Modifier
                    .weight(1f)
                    .padding(end = 8.dp)
            )
            if (showCompare && onCompare != null) {
                TextButton(onClick = onCompare) {
                    Text(stringResource(R.string.profile_compare_prs))
                }
            }
        }
        LazyRow(
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            item {
                PrKindFilterChip(PrKindFilter.ALL, st.filter) { vm.setFilter(it) }
            }
            item {
                PrKindFilterChip(PrKindFilter.STRENGTH, st.filter) { vm.setFilter(it) }
            }
            item {
                PrKindFilterChip(PrKindFilter.CARDIO, st.filter) { vm.setFilter(it) }
            }
            item {
                PrKindFilterChip(PrKindFilter.SPORT, st.filter) { vm.setFilter(it) }
            }
        }
        if (st.rows.isNotEmpty()) {
            TextButton(
                onClick = {
                    showSearch = !showSearch
                    if (!showSearch) {
                        vm.setSearchQuery("")
                    }
                }
            ) {
                Text(
                    if (showSearch) {
                        stringResource(R.string.profile_prs_hide_search)
                    } else {
                        stringResource(R.string.profile_prs_search)
                    }
                )
            }
        }
        AnimatedVisibility(visible = showSearch) {
            OutlinedTextField(
                value = st.searchQuery,
                onValueChange = vm::setSearchQuery,
                modifier = Modifier.fillMaxWidth(),
                singleLine = true,
                label = { Text(stringResource(R.string.profile_prs_search)) },
                placeholder = { Text(stringResource(R.string.profile_prs_search_hint)) }
            )
        }
        if (st.loading && st.rows.isNotEmpty()) {
            LinearProgressIndicator(Modifier.fillMaxWidth())
        }
        if (st.error != null) {
            Text(
                st.error!!,
                color = MaterialTheme.colorScheme.error,
                style = MaterialTheme.typography.bodySmall
            )
        }
        when {
            st.loading && st.rows.isEmpty() -> {
                Box(
                    Modifier
                        .fillMaxWidth()
                        .padding(24.dp),
                    contentAlignment = Alignment.Center
                ) {
                    CircularProgressIndicator()
                }
            }
            st.error != null && st.rows.isEmpty() -> {
                Text(
                    st.error!!,
                    color = MaterialTheme.colorScheme.error
                )
            }
            !st.loading && st.error == null && st.rows.isEmpty() -> {
                Text(
                    stringResource(R.string.profile_prs_empty),
                    textAlign = TextAlign.Center,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(24.dp)
                )
            }
            st.rows.isNotEmpty() && sections.isEmpty() && st.searchQuery.isNotBlank() -> {
                Text(
                    stringResource(R.string.profile_prs_no_search_results),
                    textAlign = TextAlign.Center,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(24.dp)
                )
            }
            sections.isNotEmpty() -> {
                LazyColumn(
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                    modifier = Modifier
                        .weight(1f)
                        .fillMaxWidth()
                ) {
                    sections.forEach { sec ->
                        item(key = "hdr-${sec.title}") {
                            Text(
                                sec.title,
                                style = MaterialTheme.typography.titleSmall,
                                fontWeight = FontWeight.SemiBold,
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .background(MaterialTheme.colorScheme.background)
                                    .padding(vertical = 6.dp, horizontal = 4.dp)
                            )
                        }
                        items(
                            items = sec.items,
                            key = { it.listId }
                        ) { pr ->
                            PrListRowCard(pr = pr)
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun PrKindFilterChip(
    option: PrKindFilter,
    selected: PrKindFilter,
    onSelect: (PrKindFilter) -> Unit
) {
    val label = when (option) {
        PrKindFilter.ALL -> stringResource(R.string.home_filter_all)
        PrKindFilter.STRENGTH -> stringResource(R.string.home_filter_strength)
        PrKindFilter.CARDIO -> stringResource(R.string.home_filter_cardio)
        PrKindFilter.SPORT -> stringResource(R.string.home_filter_sport)
    }
    FilterChip(
        selected = option == selected,
        onClick = { onSelect(option) },
        label = { Text(label) }
    )
}

@Composable
private fun PrListRowCard(pr: ProfilePrListRow) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(
                color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.45f),
                shape = RoundedCornerShape(12.dp)
            )
            .padding(horizontal = 12.dp, vertical = 10.dp),
        verticalAlignment = Alignment.Top,
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        Column(Modifier.weight(1f, fill = true), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(
                pr.label,
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.SemiBold
            )
            Text(
                ComparePrsFormat.prettyMetricName(pr.metric),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
        Column(
            horizontalAlignment = Alignment.End,
            verticalArrangement = Arrangement.spacedBy(2.dp)
        ) {
            Text(
                ComparePrsFormat.formatValue(pr.metric, pr.value),
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold,
                fontFamily = FontFamily.Monospace
            )
            Text(
                ProfilePrsGrouping.dateOnlyMedium(pr.achievedAt),
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}
