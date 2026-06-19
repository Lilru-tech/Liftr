package com.lilru.liftr.ui.profile

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
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
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.lilru.liftr.R
import com.lilru.liftr.ui.components.LiftrBackTopBar
import com.lilru.liftr.ui.components.LiftrFilterPillRow
import com.lilru.liftr.ui.components.LiftrGlassSurface
import com.lilru.liftr.ui.components.LiftrPillSelectedStyle
import dev.chrisbanes.haze.HazeState
import io.github.jan.supabase.SupabaseClient

@Composable
fun ProfilePrsListScreen(
    supabase: SupabaseClient,
    hazeState: HazeState,
    userId: String,
    username: String,
    showCompare: Boolean,
    onCompare: (() -> Unit)?,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
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
        val filterLabels = listOf(
            stringResource(R.string.home_filter_all),
            stringResource(R.string.home_filter_strength),
            stringResource(R.string.home_filter_cardio),
            stringResource(R.string.home_filter_sport)
        )
        val filterSelectedIndex = PrKindFilter.entries.indexOf(st.filter).coerceAtLeast(0)
        LiftrFilterPillRow(
            labels = filterLabels,
            selectedIndex = filterSelectedIndex,
            onSelected = { index -> vm.setFilter(PrKindFilter.entries[index]) },
            hazeState = hazeState,
            selectedStyle = LiftrPillSelectedStyle.IosWhite
        )
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
                    verticalArrangement = Arrangement.spacedBy(10.dp),
                    modifier = Modifier
                        .weight(1f)
                        .fillMaxWidth()
                ) {
                    items(
                        items = sections,
                        key = { "${it.kind}|${it.label}" }
                    ) { sec ->
                        PrActivityCard(hazeState = hazeState, section = sec)
                    }
                }
            }
        }
    }
}

@Composable
private fun PrActivityCard(hazeState: HazeState, section: ProfilePrsListSection) {
    LiftrGlassSurface(
        hazeState = hazeState,
        shape = RoundedCornerShape(14.dp),
        modifier = Modifier.fillMaxWidth(),
        elevation = 2.dp,
        strokeAlpha = 0.18f
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 14.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                if (section.icon.isNotEmpty()) {
                    Text(section.icon, fontSize = 20.sp)
                }
                Text(
                    section.title,
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold
                )
            }
            section.items.forEach { pr ->
                PrMetricRow(pr = pr)
            }
        }
    }
}

@Composable
private fun PrMetricRow(pr: ProfilePrListRow) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.Top,
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        Text(
            PrFormatting.prettyMetricName(pr.metric, pr.kind, pr.label),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.weight(1f, fill = true)
        )
        Column(
            horizontalAlignment = Alignment.End,
            verticalArrangement = Arrangement.spacedBy(2.dp)
        ) {
            Text(
                PrFormatting.formatValue(pr.metric, pr.value, pr.label),
                style = MaterialTheme.typography.bodyMedium,
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
