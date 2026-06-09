package com.lilru.liftr.ui.coins

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.ExperimentalMaterialApi
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Paid
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material.pullrefresh.PullRefreshIndicator
import androidx.compose.material.pullrefresh.pullRefresh
import androidx.compose.material.pullrefresh.rememberPullRefreshState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.lilru.liftr.data.BackendContracts
import com.lilru.liftr.data.CoinManager
import com.lilru.liftr.ui.LiftrBackTopBar
import com.lilru.liftr.ui.ranking.RankingInitial
import com.lilru.liftr.ui.ranking.RankingMetric
import com.lilru.liftr.ui.ranking.RankingScope
import com.lilru.liftr.ui.ranking.RankingTabScreen
import io.github.jan.supabase.SupabaseClient
import com.lilru.liftr.data.SupabaseResponseDecoding
import io.github.jan.supabase.postgrest.postgrest
import kotlinx.coroutines.launch
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.text.DateFormat
import java.text.NumberFormat
import java.util.Date

@Serializable
private data class CoinTransactionRow(
    val id: String,
    val amount: Int,
    @SerialName("action_type") val actionType: String,
    @SerialName("created_at") val createdAt: String
)

@OptIn(ExperimentalMaterialApi::class)
@Composable
fun CoinTransactionsScreen(
    supabase: SupabaseClient,
    onBack: () -> Unit,
    modifier: Modifier = Modifier
) {
    var items by remember { mutableStateOf<List<CoinTransactionRow>>(emptyList()) }
    var loading by remember { mutableStateOf(true) }
    var error by remember { mutableStateOf<String?>(null) }
    var showClearDialog by remember { mutableStateOf(false) }
    var showRanking by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val balance = CoinManager.balance

    suspend fun load() {
        loading = true
        error = null
        runCatching {
            val res = supabase.postgrest.rpc(
                BackendContracts.Rpc.LIST_MY_COIN_TRANSACTIONS_V1,
                buildJsonObject { put("p_limit", 20) }
            ) { }
            SupabaseResponseDecoding.decodeListOrObject<CoinTransactionRow>(res.data)
        }.onSuccess {
            items = it
            loading = false
        }.onFailure {
            error = it.message
            items = emptyList()
            loading = false
        }
    }

    LaunchedEffect(supabase) {
        CoinManager.refreshBalance(supabase, notifyIfEarned = false)
        load()
    }

    val refreshing = loading && items.isNotEmpty()
    val pullState = rememberPullRefreshState(refreshing, onRefresh = { scope.launch { load() } })

    if (showRanking) {
        RankingTabScreen(
            supabase = supabase,
            onOpenAddWithPendingDuplicate = {},
            rankingInitial = RankingInitial(metric = RankingMetric.COINS, scope = RankingScope.GLOBAL),
            embedBack = { showRanking = false },
            modifier = modifier
        )
        return
    }

    if (showClearDialog) {
        AlertDialog(
            onDismissRequest = { showClearDialog = false },
            title = { Text("Clear transaction history?") },
            text = {
                Text("This removes your transaction list. Your coin balance will not change.")
            },
            confirmButton = {
                TextButton(onClick = {
                    showClearDialog = false
                    scope.launch {
                        runCatching {
                            supabase.postgrest.rpc(
                                BackendContracts.Rpc.CLEAR_MY_COIN_HISTORY_V1,
                                buildJsonObject { }
                            ) { }
                        }.onSuccess {
                            items = emptyList()
                        }.onFailure { e ->
                            error = e.message
                        }
                    }
                }) {
                    Text("Clear history", color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = {
                TextButton(onClick = { showClearDialog = false }) {
                    Text("Cancel")
                }
            }
        )
    }

    Column(modifier = modifier.fillMaxSize()) {
        LiftrBackTopBar(title = "Liftr Coins", onBack = onBack)
        BoxPullRefresh(
            modifier = Modifier.fillMaxSize(),
            state = pullState,
            refreshing = refreshing
        ) {
            LazyColumn(
                modifier = Modifier
                    .fillMaxSize()
                    .pullRefresh(pullState)
                    .padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                item {
                    Card(modifier = Modifier.fillMaxWidth()) {
                        Column(
                            modifier = Modifier.padding(16.dp),
                            verticalArrangement = Arrangement.spacedBy(8.dp)
                        ) {
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.SpaceBetween,
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Text("Balance", style = MaterialTheme.typography.titleMedium)
                                TextButton(onClick = { showRanking = true }) {
                                    Text("View ranking")
                                }
                            }
                            Row(
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(8.dp)
                            ) {
                                Icon(Icons.Filled.Paid, contentDescription = null, tint = Color(0xFFFFC107))
                                Text(
                                    NumberFormat.getIntegerInstance().format(balance),
                                    style = MaterialTheme.typography.headlineSmall,
                                    fontWeight = FontWeight.Bold
                                )
                                Text("Liftr Coins", style = MaterialTheme.typography.bodyMedium)
                            }
                        }
                    }
                }

                when {
                    loading && items.isEmpty() -> item {
                        CircularProgressIndicator(modifier = Modifier.padding(24.dp))
                    }
                    error != null -> item {
                        Text(error!!, color = MaterialTheme.colorScheme.error)
                    }
                    items.isEmpty() -> item {
                        Text("No transactions yet.", color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    else -> {
                        items(items, key = { it.id }) { row ->
                            Card(modifier = Modifier.fillMaxWidth()) {
                                Column(modifier = Modifier.padding(12.dp)) {
                                    Row(
                                        modifier = Modifier.fillMaxWidth(),
                                        horizontalArrangement = Arrangement.SpaceBetween
                                    ) {
                                        Text(CoinManager.displayLabel(row.actionType))
                                        Text(
                                            CoinManager.formattedAmount(row.amount),
                                            color = if (row.amount >= 0) Color(0xFF2E7D32) else Color(0xFFC62828),
                                            fontWeight = FontWeight.SemiBold
                                        )
                                    }
                                    Text(
                                        formatCreatedAt(row.createdAt),
                                        style = MaterialTheme.typography.labelSmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant
                                    )
                                }
                            }
                        }
                        item {
                            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                                TextButton(onClick = { showClearDialog = true }) {
                                    Text("Clear history", color = MaterialTheme.colorScheme.error)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun BoxPullRefresh(
    modifier: Modifier,
    state: androidx.compose.material.pullrefresh.PullRefreshState,
    refreshing: Boolean,
    content: @Composable () -> Unit
) {
    androidx.compose.foundation.layout.Box(modifier = modifier) {
        content()
        PullRefreshIndicator(
            refreshing = refreshing,
            state = state,
            modifier = Modifier.align(Alignment.TopCenter)
        )
    }
}

private fun formatCreatedAt(raw: String): String {
    val instant = runCatching { java.time.Instant.parse(raw) }.getOrNull() ?: return raw
    return DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT)
        .format(Date.from(instant))
}
