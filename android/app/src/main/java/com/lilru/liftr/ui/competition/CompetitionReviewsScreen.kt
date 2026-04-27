package com.lilru.liftr.ui.competition

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.ExperimentalMaterialApi
import androidx.compose.material.pullrefresh.PullRefreshIndicator
import androidx.compose.material.pullrefresh.pullRefresh
import androidx.compose.material.pullrefresh.rememberPullRefreshState
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.lilru.liftr.R
import com.lilru.liftr.ui.components.LiftrBackTopBar
import com.lilru.liftr.ui.home.WorkoutDetailScreen
import io.github.jan.supabase.SupabaseClient

@OptIn(ExperimentalMaterialApi::class)
@Composable
fun CompetitionReviewsScreen(
    supabase: SupabaseClient,
    onBack: () -> Unit,
    modifier: Modifier = Modifier
) {
    val vm: CompetitionReviewsViewModel = viewModel(factory = CompetitionReviewsViewModelFactory(supabase))
    val ui by vm.uiState.collectAsStateWithLifecycle()
    var openWorkout by rememberSaveable { mutableStateOf<Int?>(null) }

    LaunchedEffect(Unit) { vm.load(isPull = false) }

    val pullState = rememberPullRefreshState(
        refreshing = ui.isRefreshing,
        onRefresh = { vm.load(isPull = true) }
    )

    if (openWorkout != null) {
        WorkoutDetailScreen(
            supabase = supabase,
            workoutId = openWorkout!!,
            onBack = { openWorkout = null },
            modifier = modifier
        )
        return
    }

    Box(modifier = modifier.fillMaxSize()) {
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .statusBarsPadding()
                .pullRefresh(pullState)
                .padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            item {
                LiftrBackTopBar(onBack = onBack)
            }
            item {
                Text(
                    stringResource(R.string.competition_reviews_title),
                    style = MaterialTheme.typography.titleLarge
                )
            }
            if (ui.loading && !ui.isRefreshing) {
                item {
                    Row(Modifier.fillMaxWidth().padding(20.dp), horizontalArrangement = Arrangement.Center) {
                        CircularProgressIndicator()
                    }
                }
            } else if (ui.error != null) {
                item { Text(ui.error!!, color = MaterialTheme.colorScheme.error) }
            } else if (ui.rows.isEmpty() && !ui.isRefreshing) {
                item {
                    Text(
                        stringResource(R.string.competition_reviews_empty),
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            } else {
                item {
                    Card(Modifier.fillMaxWidth()) {
                        Column {
                            ui.rows.forEachIndexed { i, r ->
                                Column(Modifier.padding(14.dp, 12.dp)) {
                                    Row(
                                        Modifier
                                            .fillMaxWidth()
                                            .clickable { openWorkout = r.workoutId },
                                        horizontalArrangement = Arrangement.SpaceBetween,
                                        verticalAlignment = Alignment.CenterVertically
                                    ) {
                                        Column(Modifier.weight(1f, fill = true)) {
                                            Text(
                                                stringResource(R.string.competition_reviews_from_opponent),
                                                style = MaterialTheme.typography.titleSmall
                                            )
                                            Text(
                                                stringResource(R.string.competition_reviews_tap_details),
                                                style = MaterialTheme.typography.bodySmall,
                                                color = MaterialTheme.colorScheme.onSurfaceVariant
                                            )
                                        }
                                        Text("›", style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                    }
                                    Row(
                                        Modifier
                                            .fillMaxWidth()
                                            .padding(top = 10.dp),
                                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                                    ) {
                                        OutlinedButton(
                                            onClick = { if (!ui.actionBusy) vm.review(r.id, false) },
                                            enabled = !ui.actionBusy,
                                            modifier = Modifier.weight(1f)
                                        ) {
                                            Text(stringResource(R.string.competition_reviews_reject))
                                        }
                                        FilledTonalButton(
                                            onClick = { if (!ui.actionBusy) vm.review(r.id, true) },
                                            enabled = !ui.actionBusy,
                                            modifier = Modifier.weight(1f)
                                        ) {
                                            Text(stringResource(R.string.competition_reviews_accept))
                                        }
                                    }
                                }
                                if (i < ui.rows.size - 1) {
                                    HorizontalDivider(Modifier.padding(horizontal = 14.dp), thickness = 0.5.dp)
                                }
                            }
                        }
                    }
                }
            }
        }
        PullRefreshIndicator(
            refreshing = ui.isRefreshing,
            state = pullState,
            modifier = Modifier.align(Alignment.TopCenter)
        )
    }
}
