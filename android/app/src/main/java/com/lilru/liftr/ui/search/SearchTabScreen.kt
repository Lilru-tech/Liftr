package com.lilru.liftr.ui.search

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.Clear
import androidx.compose.material.icons.filled.DeleteOutline
import androidx.compose.material3.AssistChip
import androidx.compose.material3.Card
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material.ExperimentalMaterialApi
import androidx.compose.material.pullrefresh.PullRefreshIndicator
import androidx.compose.material.pullrefresh.pullRefresh
import androidx.compose.material.pullrefresh.rememberPullRefreshState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.google.android.gms.ads.AdRequest
import com.google.android.gms.ads.AdSize
import com.google.android.gms.ads.AdView
import com.lilru.liftr.BuildConfig
import com.lilru.liftr.R
import com.lilru.liftr.prefs.LiftrPreferences
import com.lilru.liftr.ui.components.LiftrAvatar
import com.lilru.liftr.ui.home.WorkoutDetailScreen
import com.lilru.liftr.ui.profile.ProfileTabScreen
import com.lilru.liftr.ui.segment.SegmentDetailScreen
import com.lilru.liftr.ui.territory.TerritoryMapScreen
import io.github.jan.supabase.SupabaseClient
import kotlinx.coroutines.delay
import java.util.UUID

@OptIn(ExperimentalLayoutApi::class, ExperimentalMaterialApi::class)
@Composable
fun SearchTabScreen(
    supabase: SupabaseClient,
    onOpenAddWithPendingDuplicate: () -> Unit = {},
    modifier: Modifier = Modifier
) {
    val searchCtx = LocalContext.current
    var isPremium by remember { mutableStateOf(LiftrPreferences.isPremium(searchCtx)) }
    LaunchedEffect(searchCtx) {
        isPremium = LiftrPreferences.isPremium(searchCtx)
    }
    val vm: SearchViewModel = viewModel(factory = SearchViewModelFactory(supabase))
    val ui by vm.uiState.collectAsStateWithLifecycle()
    var selectedWorkout by rememberSaveable { mutableStateOf<Int?>(null) }
    var selectedProfileUserId by rememberSaveable { mutableStateOf<String?>(null) }
    var selectedSegmentId by rememberSaveable { mutableStateOf<String?>(null) }

    val openSegmentUuid = remember(selectedSegmentId) {
        selectedSegmentId?.let { runCatching { UUID.fromString(it) }.getOrNull() }
    }
    if (openSegmentUuid != null) {
        SegmentDetailScreen(
            supabase = supabase,
            segmentId = openSegmentUuid,
            onBack = { selectedSegmentId = null },
            modifier = modifier
        )
        return
    }

    val selected = ui.workouts.firstOrNull { it.id == selectedWorkout }
    if (selected != null) {
        WorkoutDetailScreen(
            supabase = supabase,
            workoutId = selected.id,
            onBack = { selectedWorkout = null },
            onDuplicateToAdd = {
                onOpenAddWithPendingDuplicate()
                selectedWorkout = null
            },
            modifier = modifier
        )
        return
    }
    if (selectedProfileUserId != null) {
        ProfileTabScreen(
            supabase = supabase,
            onSignOut = {},
            targetUserId = selectedProfileUserId,
            showSignOutButton = false,
            onBack = { selectedProfileUserId = null },
            modifier = modifier
        )
        return
    }

    LaunchedEffect(ui.query) {
        if (ui.scope != SearchScope.MAP) {
            delay(400)
            vm.search()
        }
    }

    val pull = rememberPullRefreshState(
        refreshing = ui.isRefreshing,
        onRefresh = { vm.pullRefresh() }
    )

    Box(modifier = modifier.fillMaxSize()) {
        Column(Modifier.fillMaxSize()) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 12.dp, vertical = 4.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                FilterChip(
                    selected = ui.scope == SearchScope.USERS,
                    onClick = { vm.setScope(SearchScope.USERS) },
                    label = { Text(stringResource(R.string.search_scope_users)) }
                )
                FilterChip(
                    selected = ui.scope == SearchScope.WORKOUTS,
                    onClick = { vm.setScope(SearchScope.WORKOUTS) },
                    label = { Text(stringResource(R.string.search_scope_workouts)) }
                )
                FilterChip(
                    selected = ui.scope == SearchScope.SEGMENTS,
                    onClick = { vm.setScope(SearchScope.SEGMENTS) },
                    label = { Text(stringResource(R.string.search_scope_segments)) }
                )
                FilterChip(
                    selected = ui.scope == SearchScope.MAP,
                    onClick = { vm.setScope(SearchScope.MAP) },
                    label = { Text(stringResource(R.string.search_scope_map)) }
                )
            }
            if (ui.scope == SearchScope.MAP) {
                TerritoryMapScreen(
                    supabase = supabase,
                    onOpenProfile = { selectedProfileUserId = it.toString() },
                    modifier = Modifier
                        .weight(1f, fill = true)
                        .fillMaxWidth()
                )
            } else {
                Box(
                    modifier = Modifier
                        .weight(1f, fill = true)
                        .fillMaxWidth()
                ) {
                    LazyColumn(
                        modifier = Modifier
                            .fillMaxSize()
                            .pullRefresh(pull)
                            .padding(horizontal = 12.dp),
                        verticalArrangement = Arrangement.spacedBy(10.dp)
                    ) {
                        item {
                            OutlinedTextField(
                        value = ui.query,
                        onValueChange = vm::onQueryChanged,
                        label = { Text(stringResource(R.string.search_query_label)) },
                        singleLine = true,
                        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
                        keyboardActions = KeyboardActions(
                            onSearch = { vm.search() }
                        ),
                        trailingIcon = {
                            if (ui.query.isNotEmpty()) {
                                IconButton(
                                    onClick = {
                                        vm.onQueryChanged("")
                                        vm.search("")
                                    }
                                ) {
                                    Icon(
                                        Icons.Filled.Clear,
                                        contentDescription = stringResource(R.string.search_query_clear)
                                    )
                                }
                            }
                        },
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(top = 2.dp)
                    )
                        }

                if (ui.query.trim().length < 2) {
                    item {
                        Text(
                            text = stringResource(R.string.search_min_chars_hint),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }

                if (ui.trendingQueries.isNotEmpty()) {
                    item {
                        Text(
                            text = stringResource(R.string.search_trending_title),
                            style = MaterialTheme.typography.titleSmall
                        )
                    }
                    item {
                        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            ui.trendingQueries.forEach { q ->
                                AssistChip(
                                    onClick = {
                                        vm.onQueryChanged(q)
                                        vm.search(q)
                                    },
                                    label = { Text(q) }
                                )
                            }
                        }
                    }
                }

                if (ui.recentQueries.isNotEmpty()) {
                    item {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Text(
                                text = stringResource(R.string.search_recents_title),
                                style = MaterialTheme.typography.titleSmall,
                                modifier = Modifier.weight(1f)
                            )
                            IconButton(onClick = vm::clearRecents) {
                                Icon(
                                    imageVector = Icons.Filled.DeleteOutline,
                                    contentDescription = stringResource(R.string.search_clear_recents_a11y)
                                )
                            }
                        }
                    }
                    item {
                        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            ui.recentQueries.forEach { q ->
                                AssistChip(
                                    onClick = {
                                        vm.onQueryChanged(q)
                                        vm.search(q)
                                    },
                                    label = { Text(q) }
                                )
                            }
                        }
                    }
                }

                if (ui.loading) {
                    item {
                        Text(
                            text = stringResource(R.string.search_loading),
                            modifier = Modifier.padding(vertical = 8.dp)
                        )
                    }
                }
                if (ui.error != null) {
                    item {
                        Text(
                            text = ui.error ?: "",
                            color = MaterialTheme.colorScheme.error,
                            textAlign = TextAlign.Center,
                            modifier = Modifier.fillMaxWidth()
                        )
                    }
                }

                if (ui.scope == SearchScope.USERS) {
                    item {
                        Text(
                            text = stringResource(R.string.search_profiles_title),
                            style = MaterialTheme.typography.titleMedium,
                            modifier = Modifier.padding(top = 6.dp)
                        )
                    }
                    if (ui.profiles.isEmpty()) {
                        item {
                            Text(
                                text = stringResource(R.string.search_profiles_empty),
                                style = MaterialTheme.typography.bodyMedium
                            )
                        }
                    } else {
                        items(ui.profiles, key = { it.userId }) { p ->
                            Card(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .clickable { selectedProfileUserId = p.userId }
                            ) {
                                val u = p.username?.trim().orEmpty()
                                val handle = if (u.isEmpty()) {
                                    stringResource(R.string.search_unknown_user)
                                } else if (u.startsWith("@")) {
                                    u
                                } else {
                                    "@$u"
                                }
                                Row(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .padding(12.dp),
                                    verticalAlignment = Alignment.CenterVertically,
                                    horizontalArrangement = Arrangement.spacedBy(12.dp)
                                ) {
                                    LiftrAvatar(
                                        imageUrl = p.avatarUrl,
                                        displayName = p.username,
                                        size = 44.dp
                                    )
                                    Text(
                                        text = handle,
                                        style = MaterialTheme.typography.titleSmall,
                                        maxLines = 1,
                                        overflow = TextOverflow.Ellipsis,
                                        modifier = Modifier.weight(1f)
                                    )
                                    Icon(
                                        imageVector = Icons.Filled.ChevronRight,
                                        contentDescription = null,
                                        modifier = Modifier.size(22.dp),
                                        tint = MaterialTheme.colorScheme.onSurfaceVariant
                                    )
                                }
                            }
                        }
                    }
                } else if (ui.scope == SearchScope.WORKOUTS) {
                    item {
                        Text(
                            text = stringResource(R.string.search_workouts_title),
                            style = MaterialTheme.typography.titleMedium,
                            modifier = Modifier.padding(top = 8.dp)
                        )
                    }
                    if (ui.workouts.isEmpty()) {
                        item {
                            Text(
                                text = stringResource(R.string.search_workouts_empty),
                                style = MaterialTheme.typography.bodyMedium
                            )
                        }
                    } else {
                        items(ui.workouts, key = { it.id }) { w ->
                            Card(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .clickable { selectedWorkout = w.id }
                            ) {
                                Column(
                                    modifier = Modifier.padding(12.dp),
                                    verticalArrangement = Arrangement.spacedBy(4.dp)
                                ) {
                                    Text(
                                        text = w.title?.takeIf { it.isNotBlank() }
                                            ?: stringResource(R.string.home_untitled_workout),
                                        style = MaterialTheme.typography.titleSmall
                                    )
                                    Text(
                                        text = "${w.kind ?: "-"} • ${w.state ?: "-"}",
                                        style = MaterialTheme.typography.bodySmall
                                    )
                                    val owner = ui.ownerUsernames[w.userId]
                                    if (!owner.isNullOrBlank()) {
                                        Text(
                                            text = "@$owner",
                                            style = MaterialTheme.typography.bodySmall,
                                            color = MaterialTheme.colorScheme.onSurfaceVariant
                                        )
                                    }
                                }
                            }
                        }
                    }
                } else {
                    item {
                        Text(
                            text = stringResource(R.string.search_segments_title),
                            style = MaterialTheme.typography.titleMedium,
                            modifier = Modifier.padding(top = 8.dp)
                        )
                    }
                    if (ui.segments.isEmpty()) {
                        item {
                            Text(
                                text = stringResource(R.string.search_segments_empty),
                                style = MaterialTheme.typography.bodyMedium
                            )
                        }
                    } else {
                        items(ui.segments, key = { it.id }) { s ->
                            Card(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .clickable { selectedSegmentId = s.id }
                            ) {
                                Column(
                                    modifier = Modifier.padding(12.dp),
                                    verticalArrangement = Arrangement.spacedBy(4.dp)
                                ) {
                                    Text(
                                        text = s.name,
                                        style = MaterialTheme.typography.titleSmall
                                    )
                                    val buf = s.buffer_m
                                    if (buf != null) {
                                        Text(
                                            text = stringResource(R.string.search_segment_buffer_m, buf.toInt()),
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
                    PullRefreshIndicator(
                        refreshing = ui.isRefreshing,
                        state = pull,
                        modifier = Modifier.align(Alignment.TopCenter)
                    )
                }
            }
            if (!isPremium) {
                AndroidView(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(50.dp),
                    factory = { ctx ->
                        AdView(ctx).apply {
                            setAdSize(AdSize.BANNER)
                            adUnitId = BuildConfig.AD_BANNER_UNIT_ID
                            loadAd(AdRequest.Builder().build())
                        }
                    }
                )
            }
        }
    }
}
